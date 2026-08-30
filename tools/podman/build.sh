#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Containerised Quartus build for the Pocket GBA core. Runs on the HOST and
# drives podman itself, so the container only ever needs Quartus.
#
#   tools/podman/build.sh            full build
#   SKIP_COMPILE=1 tools/podman/build.sh   repackage existing outputs
#   SEED=2 tools/podman/build.sh     re-run the fitter with another seed
#
# Everything lands in build/gba/. The checked-in tree is never written to:
# Quartus runs against a copy under build/gba/work, which is also what lets us
# patch fitter settings without touching files CI shares with upstream.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
BDIR="$REPO/build/gba"
WORK="$BDIR/work"

PODMAN=${PODMAN:-podman}
IMAGE=${IMAGE:-docker.io/raetro/quartus:21.1}

# The two runtimes need different flags to leave the output owned by whoever
# ran this, and that is not cosmetic: everything after the compile - rsync, the
# version stamp, zip - runs on the host against files the container wrote.
# podman's --userns=keep-id maps the caller to the same uid inside. Docker has
# no equivalent and runs as root unless told, so it is told. label=disable is
# for SELinux on the host and is only wanted where there is one.
# podman as root already maps container root to host root, and rejects
# keep-id outright ("keep-id is only supported in rootless mode"), which is
# what a build runner hits: an LXC or a VM where everything runs as root.
case "$(basename "$PODMAN"):$(id -u)" in
  docker:*) RUNAS=(--user "$(id -u):$(id -g)") ;;
  *:0)      RUNAS=(--security-opt label=disable) ;;
  *)        RUNAS=(--userns=keep-id --security-opt label=disable) ;;
esac

CORE_DIR=$(ls -d "$REPO/pkg/Cores"/*/ | head -1)
CORE_NAME=$(basename "$CORE_DIR")
GIT_SHA=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo nogit)
GIT_DIRTY=$(git -C "$REPO" status --porcelain 2>/dev/null | grep -q . && echo 1 || true)

# A venv, because host python is off limits on this machine. Nothing is
# installed into it: reverse_bitstream.py is stdlib only, and the venv exists
# so that stays true and visible.
VENV="$BDIR/venv"
[[ -x "$VENV/bin/python3" ]] || python3 -m venv "$VENV"
PY="$VENV/bin/python3"

echo "== core=$CORE_NAME commit=$GIT_SHA${GIT_DIRTY:+ (dirty)} image=$IMAGE"

# ---- 1. Sync the build copy ------------------------------------------------
# Quartus scratch (db/, incremental_db/, output_files/) is deliberately kept
# across runs so incremental compiles work; `make clean` wipes the lot.
mkdir -p "$WORK"
rsync -a --delete \
  --exclude 'output_files/' --exclude 'db/' --exclude 'incremental_db/' \
  --exclude 'build_output/' \
  "$REPO/src/" "$WORK/src/"
rsync -a --delete "$REPO/scripts/" "$WORK/scripts/"
cp "$REPO/generate.tcl" "$WORK/generate.tcl"

# ---- 2. Patch the build copy ----------------------------------------------
QSF="$WORK/src/fpga/build/ap_core.qsf"

# Upstream's generate.tcl pins the compile to 4 processors, which is right for a
# CI runner and wasteful here. The build copy uses whatever the host has.
sed -i 's/^set_global_assignment -name NUM_PARALLEL_PROCESSORS 4$/set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL/' "$WORK/generate.tcl"

# Optional fitter seed. This design closes setup by 0.102 ns on clk_sys in
# upstream's own build, so placement variance alone can decide a marginal path.
# Re-running with another seed is the right first move there, not a design
# change. Upstream keeps SEED 8 in the qsf; SEED= overrides it here only.
# Fitter effort. Upstream leaves this at AUTO FIT, which lowers effort once the
# fitter thinks timing is achievable. Near the device ceiling that judgement is
# worth overriding: STANDARD FIT costs compile time and buys placement quality.
if [[ -n "${FITTER_EFFORT:-}" ]]; then
  printf '\nset_global_assignment -name FITTER_EFFORT "%s"\n' "$FITTER_EFFORT" >> "$QSF"
  printf '\nset_global_assignment -name OPTIMIZE_HOLD_TIMING "ALL PATHS"\n' >> "$QSF"
  echo "== fitter effort $FITTER_EFFORT"
fi

# NPROC caps Quartus's parallelism, so two experiments can share the machine.
if [[ -n "${NPROC:-}" ]]; then
  sed -i "s/^set_global_assignment -name NUM_PARALLEL_PROCESSORS .*$/set_global_assignment -name NUM_PARALLEL_PROCESSORS $NPROC/" "$WORK/generate.tcl"
  echo "== parallel processors $NPROC"
fi

if [[ -n "${SEED:-}" ]]; then
  printf '\nset_global_assignment -name SEED %s\n' "$SEED" >> "$QSF"
  echo "== fitter seed $SEED"
fi

# ---- 3. Compile ------------------------------------------------------------
if [[ -z "${SKIP_COMPILE:-}" ]]; then
  start=$(date +%s)
  set +e
  $PODMAN run --rm \
    "${RUNAS[@]}" \
    -v "$WORK:/work" -w /work -e HOME=/tmp \
    "$IMAGE" quartus_sh -t generate.tcl 2>&1 | tee "$BDIR/build.log"
  rc=${PIPESTATUS[0]}
  set -e
  echo "$(( $(date +%s) - start ))" > "$BDIR/elapsed"
  [[ $rc -eq 0 ]] || { echo "quartus failed (rc=$rc), see $BDIR/build.log" >&2; exit "$rc"; }
  $PODMAN run --rm "$IMAGE" quartus_sh --version 2>/dev/null | sed -n 2p > "$BDIR/quartus.version" || true
else
  echo "== SKIP_COMPILE set, packaging existing outputs"
fi

RBF="$WORK/src/fpga/build/output_files/ap_core.rbf"
test -f "$RBF" || { echo "no .rbf produced, see $BDIR/build.log" >&2; exit 1; }

# ---- 4. Bitstream, SD tree, zip -------------------------------------------
RBF_NAME=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['core']['cores'][0]['filename'])" "$CORE_DIR/core.json")
VERSION=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['core']['metadata']['version'])" "$CORE_DIR/core.json")

"$PY" "$REPO/scripts/reverse_bitstream.py" "$RBF" "$BDIR/$RBF_NAME"

rm -rf "$BDIR/sd"
rsync -a "$REPO/pkg/" "$BDIR/sd/"
cp "$BDIR/$RBF_NAME" "$BDIR/sd/Cores/$CORE_NAME/$RBF_NAME"

# The packaged core.json carries a version the Pocket menu can be read against,
# so there is never a question of which commit is on the card. The checked-in
# pkg/ keeps the plain upstream-style version.
STAMP="${RELEASE_NAME:-}"
STAMP="${STAMP#v}"
[[ -n "$STAMP" ]] || STAMP="${VERSION}-cheats.${GIT_SHA}${GIT_DIRTY:+.dirty}"
"$PY" - "$BDIR/sd/Cores/$CORE_NAME/core.json" "$STAMP" "$(date -u +%Y-%m-%d)" <<'PY'
import json, sys
path, version, date = sys.argv[1:]
assert len(version) <= 31, f"version too long for APF: {version}"
j = json.load(open(path))
j["core"]["metadata"]["version"] = version
j["core"]["metadata"]["date_release"] = date
json.dump(j, open(path, "w"), indent=2)
open(path, "a").write("\n")
print(f"stamped core.json: version={version} date_release={date}")
PY

ZIP="$BDIR/${CORE_NAME}_${STAMP}.zip"
rm -f "$ZIP"
(cd "$BDIR/sd" && zip -qr "$ZIP" .)

echo
echo "== done"
echo "   bitstream: $BDIR/$RBF_NAME"
echo "   sd tree:   $BDIR/sd/"
echo "   zip:       $ZIP"
echo
GIT_SHA="$GIT_SHA" GIT_DIRTY="$GIT_DIRTY" "$HERE/report.sh"
