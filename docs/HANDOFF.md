# Handoff

State of the fork as of 2026-08-24. Written so the work can be picked up cold.
Read this first, then `PLAN.md` for the design and `BASELINE.md` for the fit
history.

## Where the work stands in one paragraph

The cheat engine (P1) and the `.cht` loader (P2) are both written, both pass
simulation, and together they do not fit. P1 alone closes timing with room to
spare. P1+P2 together sit at 97 % ALM occupancy and miss setup by a
reproducible 0.45 ns. Nothing has been merged into `cheats` beyond the build
harness and docs, because nothing should merge from a build that fails timing.
The open question is not "does the cheat code work" (simulation says yes), it
is "what comes out of the design to make room".

## Standing constraints

- **Nothing is pushed to any remote.** Not `origin`, not anything. The user set
  this explicitly and it has not been lifted.
- **P2 does not merge into `cheats` until a build closes timing.**
- Upstream attribution stays: `info.txt`, `FUNDING.yml`, git history, the
  `upstream` remote.

## Measured results

All numbers from `tools/podman/report.sh`, worst slack across all corners.
Device is 5CEBA4F23C8: 18,480 ALMs, 308 RAM blocks. `clk_sys` at ~100.66 MHz
is the GBA domain and carries every worst-case path.

| # | Design | Fitter | Seed | ALMs | RAM | Setup | Verdict |
|---|---|---|---|---|---|---|---|
| A | upstream, no cheats | AUTO | 8 | 16,648 (90 %) | 278 | **+0.090** | met |
| B | P1 engine only | AUTO | 8 | 16,624 (90 %) | 281 | **+0.090** | met |
| C | P1+P2 | AUTO | 8 | 17,909 (97 %) | 284 | −0.846 | fail |
| D | P1+P2 | STANDARD | 8 | 17,903 (97 %) | 284 | −0.452 | fail |
| E | P1+P2, 16 entries | AUTO | 8 | 17,980 (97 %) | 284 | −0.711 | fail |
| F | P1+P2, 16 entries | AUTO | 8 | 17,980 (97 %) | 284 | −0.711 | fail, exact rerun of E |
| G | P1+P2 | AUTO | 2 | 17,988 (97 %) | 284 | −1.321 | fail |
| H | P1+P2 | STANDARD | 3 | 17,871 (97 %) | 284 | −0.453 | fail |
| I | P1+P2 | AUTO | 5 | 17,961 (97 %) | 284 | −0.887 | fail |

## What those numbers establish

1. **Only STANDARD FIT measures the design.** Three AUTO FIT seeds gave
   −0.846 (seed 8), −0.887 (seed 5) and −1.321 (seed 2). Two cluster within
   0.04 ns and one sits 0.44 ns away, so AUTO FIT is not uniformly noisy: it
   occasionally throws a much worse placement, and a single run cannot tell you
   which kind you got. STANDARD FIT gave −0.452 (seed 8) and −0.453 (seed 3),
   one picosecond apart. **Run every future comparison at STANDARD FIT** or the
   delta is not attributable to the change you made.
2. **The real gap is 0.45 ns**, not the −0.85 the first run suggested.
3. **STANDARD FIT is worth ~0.39 ns at zero area cost** (C vs D, same seed).
   It is strictly better here and should probably become the default in the
   qsf if a closing build uses it.
4. **Seed hunting is not a fix.** It is a tiebreaker for a design already
   within a few hundredths. This one is not.
5. **E and F are byte-identical.** Same inputs and seed produce the same fit,
   so numbers are comparable across worktrees. The harness is trustworthy.
6. **The 16-entry lever is dead.** Halving `CHEATCOUNT`/`MAX_ENTRIES` made the
   design *larger* (17,980 vs 17,909) and slower. Both cheat tables already
   live in RAM blocks, so shrinking the entry count buys no ALMs and only
   perturbs placement. Do not retry this.
7. **The failure is congestion, not a slow new path.** All 44 violating paths
   are pre-existing core paths: `gba_memorymux|vram_cycle` → `gba_cpu`,
   `gba_cpu|new_cycles_valid`, `gba_memorymux` → `gba_dma`. The cheat logic
   itself is not on any critical path. `gba_cpu` gained 369 ALMs with no
   source change at all, purely from physical-synthesis register duplication
   under pressure.
8. **Rough conversion: ~135 ALMs per 0.1 ns**, derived from our own points.
   Treat as a sighting shot, not a law; it was fitted on AUTO FIT data. It
   puts the 0.45 ns gap at roughly 600 ALMs, call it 700-800 for margin.

## Area budget

Measured module costs from the fit reports:

| Module | ALMs | Notes |
|---|---|---|
| `gba_sound` | 973 | cutting this means no audio, non-starter |
| `cheat_loader` | 441 (+65 data_loader) | the feature itself |
| `gba_serial` | 417 | **being stripped**, see below |
| `gba_gpioRTCSolarGyro` | 341 | RTC (Pokémon time events), solar (Boktai), gyro (WarioWare Twisted) |
| `gba_savestates` | 297 | |
| `save_state_controller` | 239 | |
| `gba_cheats` | 151 | the engine, nearly free |

Already decided as droppable by the user: the OSD overlay menu ("ultimately
unneeded assuming the cheats work and the on/off toggle work too"), and the
partial link cable.

## The link strip (branch `exp-nolink`, commit `e3c6d64`)

mincer-ray's v0.5.0 added a partial 2-player link. Stripping it recovers
~417 ALMs. The strip is a **restoration, not a rewrite**: `gba_serial.vhd` is
restored from commit `7cd1ac6`, the 67-line register-only stub that shipped
before the link redo (PR #31 / commit `69ebe91`). That stub still answers on
the SIO registers with no-cable-present semantics (`SIOCNT` readback forces
bit 7 = 0 and bit 6 = 1, `SIOMULTI`/`SIODATA32` read `0xFFFF`), so a game
probing for a link partner finds none instead of hanging on a bus that never
acks.

A plain revert of PR #31 was deliberately **not** done: that commit also
carried unrelated `gba_cpu`, `gba_memorymux` and drawer accuracy fixes, which
the targeted strip keeps.

Also changed: twelve `serial_*` ports removed from `gba_top`'s entity, the
multiplexed drive logic on `port_tran_*` in `core_top.sv` replaced with
tri-state tie-offs, `"link_port": false` in `core.json`, README moved link
from features to not-included with the reason.

## Fitter settings: no free headroom

Checked before assuming otherwise. Upstream's `ap_core.qsf` **already** runs
every aggressive lever: `PLACEMENT_EFFORT_MULTIPLIER 4.0`,
`ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM`, `PHYSICAL_SYNTHESIS_EFFORT EXTRA`,
register duplication ON, retiming ON, combo logic ON, `ECO_OPTIMIZE_TIMING ON`.
mincer-ray was clearly already fighting this same margin. Do not go looking for
an unused speed setting; there isn't one.

The two settings still untried both bias toward **area** rather than speed,
which is the right direction when the failure is congestion:
`PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION OFF` and
`PHYSICAL_SYNTHESIS_COMBO_LOGIC_FOR_AREA ON`.

## In flight at handoff time

| Worktree | Branch | Config | Purpose |
|---|---|---|---|
| `pocket-gba-nolink` | `exp-nolink` | AUTO, seed 8 | link strip, A/B against C's −0.846 |
| `pocket-gba-p1` | `exp-16entries` (clean, 32 entries) | AUTO, seed 5 | seed roll, low value given finding 1 |
| `pocket-gba-g` | `exp-nolink-g` | **STANDARD** | link strip at the valid measurement setting. **The decisive run.** |
| `pocket-gba-h` | `exp-nolink-h` | **STANDARD** + area-biased phys synth | as G, plus duplication OFF and combo-for-area ON |

H is a genuine coin flip and worth understanding: register duplication exists
to *help* timing by shortening fanout paths, so disabling it normally costs
slack. But it is also what added 369 ALMs to `gba_cpu` for free, and at 97 %
occupancy that growth may cost more in routing congestion than the duplication
buys. If that reasoning holds, H beats G despite disabling a timing
optimisation. If not, H is clearly worse and the question is closed.


## Worktree and branch map

All worktrees are committed and clean. Nothing is pushed to any remote;
`origin` holds only upstream's `master` and `rumble-support`.

| Worktree (in `~/Desktop/repos/`) | Branch | Tip | Holds |
|---|---|---|---|
| `pocket-gba` | `cheats` | (tip) | harness, docs, P1. The integration branch. |
| `pocket-gba-loader` | `p2-cheat-loader` | `c7aebd5` | P1+P2 merged. The design that fails timing. |
| `pocket-gba-nolink` | `exp-nolink` | `e3c6d64` | P2 plus the link cable strip. |
| `pocket-gba-g` | `exp-nolink-g` | `40ac38c` | as `exp-nolink`, run at STANDARD FIT. |
| `pocket-gba-h` | `exp-nolink-h` | `0e807d6` | as G, plus area-biased physical synthesis. |
| `pocket-gba-exp-c` | `exp-standard-16` | `47496dc` | the dead 16-entry lever, kept for reproducibility. |
| `pocket-gba-exp-d` | `exp-seed2` | `fcc3fae` | seed 2 roll, superseded by the STANDARD FIT finding. |
| `pocket-gba-p1` | `exp-16entries` | `fcc3fae` | misleading name, now clean at 32 entries; used for the seed 5 roll. |

Each worktree keeps its own `build/gba/report.txt`, `build.log` and, on
failure, a `TIMING_FAILED` marker. Those are the raw results.

## Next steps, in order

1. Read G and H (`build/gba/report.txt` in each worktree).
2. **If G or H closes:** merge `exp-nolink` into `cheats`, then P2, then record
   the run in `BASELINE.md`'s phase log and update `PLAN.md`. Flash and
   validate on hardware, which has never been done for P1 or P2.
3. **If neither closes**, report the residual gap before cutting anything else.
   The next candidates in preference order are `gba_savestates` +
   `save_state_controller` (536 ALMs together, costs save states) and
   `gba_gpioRTCSolarGyro` (341, costs Pokémon RTC events and two niche
   sensors). Both are user calls, not ours.
4. Unstarted: hardware validation of P1/P2, P5-P7 cartridge work (import
   Wokann's controller plus Rai's APF plumbing), P8 release and docs. P4 (OSD)
   is authorised to drop.

## Re-running the in-flight builds

If the session ended before these finished, the containers died with it. The
results are only on disk if `build/gba/report.txt` is newer than the build
started and no `TIMING_FAILED` ambiguity remains. To re-run, from the worktree:

```sh
# G: the decisive run
cd ~/Desktop/repos/pocket-gba-g && make gba FITTER_EFFORT="STANDARD FIT" NPROC=3

# H: same design, area-biased physical synthesis
cd ~/Desktop/repos/pocket-gba-h && make gba FITTER_EFFORT="STANDARD FIT" NPROC=3
```

`make report` re-renders `build/gba/report.txt` from existing outputs without
recompiling. `make gba SKIP_COMPILE=1` repackages the SD tree and zip from an
existing `.rbf`. Three concurrent builds is the practical ceiling on 14 cores.

## Harness gotchas that cost time already

- `FITTER_EFFORT` and `NPROC` only landed on `cheats` at `e5656b6`. Worktrees
  branched before that **silently ignore them** as unset variables, and the run
  measures AUTO FIT while the command line says STANDARD. Check
  `grep FITTER_EFFORT tools/podman/build.sh` in any worktree before trusting a
  result. This already invalidated one run.
- Makefile quoting: `FITTER_EFFORT="$(FITTER_EFFORT)"`. Unquoted, `STANDARD FIT`
  splits and you get `FIT: command not found`.
- **Quartus exits 0 on failed timing.** `report.sh` is what catches it: exits 3
  and touches `TIMING_FAILED`. Never judge a build by its exit code alone.
- Use `set -o pipefail`. `make gba | tail` reports success for a failed build.
- Invoke `quartus_sh` directly, never through `bash -lc`. The image sets PATH
  via ENV and a login shell resets it.
- `podman pull` needs an empty authfile if a stale docker.io login is present.
  See `tools/podman/README.md`; do not touch the user's credentials.
- A build is ~19-25 min alone. Five concurrent on 14 cores stretches it to ~50
  min at load 42. Do not run more than three at once.
- A `report.txt` in a worktree may be **stale** from a previous run while a new
  build is still going. Check `TIMING_FAILED` mtime against the build log.

## Simulation

Green on the merged tree and independent of the fit problem: 10/10 fixtures,
9/9 e2e, 513/513 corpus files against the reference model. `make test`.
