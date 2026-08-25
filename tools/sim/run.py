#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Cross-check src/fpga/core/cheat_loader.sv against tools/cheats/gbacht.py.

Runs the RTL in Icarus Verilog over real libretro .cht files and diffs the
128-bit words it pushes into gba_cheats against the Python reference model,
word for word.

    tools/sim/run.py                 # every .cht under $CHT_DB
    tools/sim/run.py -n 200          # a sample
    tools/sim/run.py path/to/x.cht   # specific files

Every file is run twice. Stock libretro files ship with every cheat set to
`enable = false`, so a stock pass proves the enable path (both sides must push
nothing at all) and would prove nothing about the emitter. The second pass
rewrites those keys to `true` and is where the words are actually compared.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import os
import random
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "cheats"))
import gbacht  # noqa: E402

# A corpus of real .cht files. This repo does not carry one: point CHT_DB at
# libretro-database/cht/Nintendo - Game Boy Advance, or at any directory of
# .cht files. Without one the cross-check is skipped and the rest still runs.
DB = os.environ.get("CHT_DB") or os.path.join(ROOT, "external", "cht")
BUILD = os.path.join(ROOT, "build", "sim")
TB = os.path.join(BUILD, "tb_cheat_loader")
TMP = os.path.join(BUILD, "enabled")

SOURCES = ["tools/sim/tb_cheat_loader.sv", "tools/sim/gba_cheats_model.sv",
           "src/fpga/core/cheat_loader.sv"]

WORD = re.compile(r"WORD ([0-9a-f]{32})")
TOTAL = re.compile(r"TOTAL bytes=(\d+) cheats=(\d+) entries=(\d+) "
                   r"rejected=(\d+) overrun=(\d+) stored=(\d+)")
# Stock files set every cheat to false. Only the value of an _enable key is
# touched, so a description containing the word "false" is left alone.
ENABLE = re.compile(rb"(_enable\s*=\s*)false", re.I)


def compile_tb() -> None:
    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    subprocess.run(["iverilog", "-g2012", "-o", TB]
                   + [os.path.join(ROOT, s) for s in SOURCES], check=True)


def rtl(path: str, gap: int) -> tuple[list[int], tuple]:
    out = subprocess.run([TB, f"+f={path}", f"+gap={gap}"],
                         capture_output=True, text=True, check=True).stdout
    if "FAIL" in out:
        raise RuntimeError(out[out.index("FAIL"):].splitlines()[0])
    m = TOTAL.search(out)
    if not m:
        raise RuntimeError("testbench printed no total")
    return ([int(w, 16) for w in WORD.findall(out)],
            tuple(int(g) for g in m.groups()))


def model(data: bytes) -> tuple[list[int], int, int, int]:
    groups, st = gbacht.parse(data)
    return gbacht.words(groups), st.byte_count, st.group_count, st.entry_count


def check_one(path: str, gap: int) -> str | None:
    data = open(path, "rb").read()
    want, nbytes, ngroups, nentries = model(data)
    got, tot = rtl(path, gap)
    if got != want:
        for i, (a, b) in enumerate(zip(got, want)):
            if a != b:
                return f"word {i} differs: rtl={a:032x} model={b:032x}"
        return f"count differs: rtl={len(got)} model={len(want)}"
    if (tot[0], tot[1], tot[2]) != (nbytes, ngroups, nentries):
        return (f"totals differ (bytes, cheats, entries): "
                f"rtl={tot[:3]} model={(nbytes, ngroups, nentries)}")
    if tot[4]:
        return "loader reported a push overrun"
    if tot[5] != len(want):
        return f"gba_cheats stored {tot[5]} of {len(want)} words"
    return None


def check(args: tuple[str, int]) -> tuple[str, str | None]:
    path, gap = args
    try:
        err = check_one(path, gap)
        if err:
            return path, f"as written: {err}"
        # Same file with every cheat switched on. This is the pass that
        # actually exercises the emitter; stock files push nothing.
        data = open(path, "rb").read()
        flipped = ENABLE.sub(rb"\1true", data)
        if flipped != data:
            alt = os.path.join(TMP, f"{abs(hash(path)):016x}.cht")
            open(alt, "wb").write(flipped)
            err = check_one(alt, gap)
            os.unlink(alt)
            if err:
                return path, f"all enabled: {err}"
    except Exception as e:                      # noqa: BLE001
        return path, f"error: {e}"
    return path, None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("-n", type=int, default=0, help="sample N files at random")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--gap", type=int, default=4,
                    help="clk cycles between bytes; 4 is data_loader's floor")
    args = ap.parse_args()

    files = args.files or [os.path.join(d, f)
                           for d, _, fs in os.walk(DB) for f in fs
                           if f.endswith(".cht")]
    if not files:
        print(f"SKIPPED: no .cht files under {DB}\n"
              f"  set CHT_DB to a directory of them to run the cross-check "
              f"(see docs/CHEATS.md)", file=sys.stderr)
        return 0
    files.sort()
    if args.n and args.n < len(files):
        files = random.Random(0).sample(files, args.n)

    compile_tb()
    bad = 0
    with cf.ThreadPoolExecutor(max_workers=args.j) as ex:
        for i, (path, err) in enumerate(
                ex.map(check, [(f, args.gap) for f in files]), 1):
            if err:
                bad += 1
                print(f"FAIL {os.path.basename(path)}: {err}")
            if i % 100 == 0:
                print(f"  {i}/{len(files)} checked, {bad} failures", flush=True)
    print(f"\n{len(files) - bad}/{len(files)} files match the reference model")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
