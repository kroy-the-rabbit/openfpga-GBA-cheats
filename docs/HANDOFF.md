# Handoff

State of the fork as of 2026-09-05, on top of the 2026-08-30 handoff that
follows. Read this section first; the sections below it predate the release
and still say `master` and "nothing is pushed". `main` is the branch, `v0.9999`
is released from it, and CI is verify-only. `p5-cartridge` is not on the remote.

## 2026-09-05: the cartridge branch, one hardware run, one fix, no bitstream

**Branch** `p5-cartridge` at `cfd4264`, 16 commits past `main` `9002617`,
unpushed. Everything is committed.

**What happened.** Seed 3 of `60990db` was installed on the card and hash
verified. Booting Minish Cap from the slot froze at the GBA logo. The menu read
`CG:` 0 and `CS:` `0x000000B0`: probe done, timed out, nothing read. The cause
is the probe starting on `dataslot_allcomplete` while the controller resets on
APF `reset_n`, and the Pocket sends allcomplete before Reset Exit, so every
boot-time probe asked a controller in reset. `docs/CARTRIDGE.md` "First
hardware run" has the decode; the Analogue docs do not state the command order,
the readout is the evidence.

**The fix** is `cfd4264`: `~reset_n_s` added to the probe's reset condition in
`core_top.sv`. No testbench covers the probe. Proven only by a build and the
slot.

**Fits, Quartus 25.1std, STANDARD FIT**, all in `docs/BASELINE.md`:

| Commit | Seed | ALMs | Setup | Hold | Runner |
|---|---|---|---|---|---|
| `60990db` | 8 | 17,779 | -0.448 | | sisko |
| `60990db` | 2 | 17,821 | -0.562 | | sisko |
| `60990db` | 3 | 17,828 | +0.092 | +0.111 | kira, 2010 s |
| `60990db` | 1 | 17,910 | +0.075 | +0.037 | sisko, 1376 s |
| `cfd4264` | 3 | 17,744 | **-0.098** | +0.024 | sisko, 1430 s |

The `cfd4264` seed 3 package is in `build/gba` renamed `seed3-FAILED`. Do not
flash it.

**The card** still holds the seed 3 build of `60990db`, the one that froze.
The released `v0.9999` is not on it.

**Tomorrow, in order.**

1. Fit `cfd4264` at seed 1 on sisko: `SEED=1 ../tools/runner-build start sisko
   pocket-gba gba p5cart-s1 cfd4264`, then `job` to poll and `fetch`. Seed 1
   closed on the previous commit. If it misses, try 2 and 3 on both runners.
2. Install the passing package, set Cartridge to `Detect`, restart with Minish
   Cap in the slot, read `CS:`. Expected low byte `E1` and bits 15:8 `96`;
   `CG:` should be `BZME` as hex. Then `Boot`.
3. Still unknown and worth checking on the same visit: whether a card ROM boots
   on this build with the setting off, and whether the persisted `Detect`
   setting probes correctly on a cold core load rather than only after a menu
   toggle.
4. No GBA tag until a cartridge boots. The release condition was a hardware
   test and the first one failed. When it passes, rebuild the tagged commit at
   the seed that closed, publish by hand as the other cores were (workflow
   disabled, signed tag, `gh release create --verify-tag`), and re-enable.

**Also stale in the README on `main`:** "five projects share one version
number". Every project sits at `0.9999` and they are not in step.

# Handoff, 2026-08-30

State of the fork as of 2026-08-30. Written so the work can be picked up cold.
Read this after the section above, then `PLAN.md` for the design and `BASELINE.md` for the fit
history.

## Resolved: the fit problem below is solved

Everything from "Measured results" down was written on 2026-08-24, while
P1+P2 were missing setup by a reproducible 0.45 ns. It is kept because the
fifteen builds it records are what ruled out the fitter, the seed, the entry
count and the feature strip as answers, and that negative evidence is the
reason the eventual fix was the right one to reach for.

The fix was P3: stop parsing ASCII on the FPGA. `tools/cheats/cht2bin.py`
converts a `.cht` to a 16-byte-per-entry `.chtbin` on the host, and
`src/fpga/core/cheat_binloader.sv` replaces the 648-line parser with a byte
counter and a 72-bit shift register. 441 ALMs and 12.7 % of all
physical-synthesis churn became 61 ALMs and none.

| | ALMs | RAM | Setup |
|---|---|---|---|
| upstream v0.6.2 baseline | 16,648 (90 %) | 278 | +0.090 |
| P1+P2, ASCII parser | 17,903 (97 %) | 284 | −0.452 |
| **P1+P3, `.chtbin`** | **16,689 (90 %)** | **282** | **+0.090 met** |

Reproduced on CI at a different processor count, agreeing in every figure.
`docs/BASELINE.md` records an earlier 17,544 reading of the same design that
nothing has been able to repeat.

It closes at exactly the margin upstream itself ships. Merged as `d7a2138`; format contract in `docs/CHEATBIN.md`.

**This has since run on a Pocket.** The core boots, a `.chtbin` loads, a code
takes effect in game and the toggle works live. Two items on `docs/HARDWARE.md`
are still unwalked: the stray `.cht`, and sleep with the engine running.
Simulation was green end to end throughout (24 converter, 19 binloader, 10
fixture, 9 e2e, 513 corpus).

## Standing constraints

- **Nothing is pushed to any remote.** Not `origin`, not anything. The user set
  this explicitly and it has not been lifted.
- **Nothing merges into `master` from a build that fails timing.** P3 satisfied
  this; the rule stands for the cartridge work. CI enforces the release half of
  it: a tag that is not on `master` is refused, and a build that misses timing
  refuses to publish.
- **Run every fit comparison at STANDARD FIT** (finding 1 below), or the delta
  is not attributable to the change you made.
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
| J | P1+P2, **link stripped** | AUTO | 8 | 17,686 (96 %) | 284 | −0.445 | fail |
| K | link stripped | STANDARD | 8 | 17,594 (95 %) | 284 | −0.711 | fail |
| L | link stripped, dup OFF, combo-for-area ON | STANDARD | 8 | 17,594 (95 %) | 284 | −0.711 | fail, **identical to K** |
| M | P1+P2, `cheat_loader` multicycle 4 | STANDARD | 8 | 17,929 (97 %) | 284 | −0.600 | fail, see below |
| N | P1+P2, phys-synth effort NORMAL | STANDARD | 8 | 17,903 (97 %) | 284 | −0.452 | fail, **identical to D** |

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
8. **Area does not buy slack here, and the "135 ALMs per 0.1 ns" rule was
   wrong.** Run K removed 309 ALMs from run D and *lost* 0.26 ns
   (−0.452 to −0.711). At AUTO FIT the same strip gained 0.40 ns (C to J). The
   two fitter modes disagree on the sign of the same change. Do not size a cut
   by expected slack return; there is no reliable conversion.
9. **Runs K and L are identical to the digit** despite L disabling register
   duplication and enabling combinational-logic-for-area. The fitter settings
   tables confirm the options differed, so those two settings changed nothing.
   The build log shows why: only **register retiming** and **combinational
   resynthesis** ever execute. No duplication pass runs at all in Quartus Lite,
   whatever the qsf says. Do not spend another build on those two knobs.
10. **Correction: `gba_cpu`'s +369 ALMs are not from register duplication.**
   Duplication never runs (finding 9). The growth is retiming, which the log
   credits with 4,129 ps of estimated improvement.
11. **`PHYSICAL_SYNTHESIS_EFFORT` is inert too.** Run N with NORMAL instead of
   EXTRA is byte-identical to run D. That is the third dead knob. Assume the
   remaining physical synthesis settings do nothing in Lite unless a log line
   proves otherwise.
12. **The multicycle constraint worked and did not help, which kills the
   congestion theory.** Run M cut 402 registers (24,696 to 24,294) and 14 % of
   all physical-synthesis churn (5,973 to 5,155 nodes), so retiming genuinely
   backed off. ALMs moved +26 and slack got *worse*, −0.452 to −0.600. The
   manufactured registers were never the cost. **The cost is the parser's
   combinational logic, which exists no matter how the fitter treats it.**

## Area budget

Measured module costs from the fit reports:

Numbers are as attributed by the fit report. See the link-strip section below:
**actual recovery ran at about half the attributed cost**, so treat these as
upper bounds.

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

mincer-ray's v0.5.0 added a partial 2-player link. Stripping it **recovers 223
ALMs**, measured (run J against run C, same fitter and seed), and 0.40 ns of
setup at AUTO FIT.

Note the gap between that and `gba_serial`'s 417 ALMs in the fit report. The
strip returned 53 % of the module's listed cost, because the module is not
deleted but replaced by a stub that still costs something, and because
module-level attribution does not capture how the fitter redistributes logic.
**Read every figure in the area budget above as an upper bound on what cutting
it would actually return**, likely around half. That reframes the remaining
candidates: `gba_savestates` plus `save_state_controller` are quoted at 536
together but should be expected to yield roughly 300.

The strip is a **restoration, not a rewrite**: `gba_serial.vhd` is
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

Nothing. The four builds that were running on 2026-08-24 all finished and are
runs I, J, K and L in the table above. The commands that produced them are in
"Re-running the in-flight builds" below, kept because the branches still exist.

## Feasibility verdict: delete the ASCII parser, do not shrink it

Fifteen builds. Nothing has ever come closer than −0.445 ns. Two fitter modes,
four seeds, an entry-count halving, a feature strip, three fitter knobs and a
timing constraint have all failed to move it toward zero, and three of those
knobs turned out to do nothing at all in Lite. **There is no tuning left that
should be expected to find 0.45 ns.** Stop looking for one.

The problem is narrow, which is the good news. **P1, the cheat engine, is
free**: 16,624 ALMs and +0.090 ns, slightly better than baseline. Every bit of
the damage comes from P2, and specifically from the fact that `cheat_loader`
parses ASCII. It carries a 64-bit token shift register, hex nibble conversion,
quoted-string tracking, key matching, a CodeBreaker pair collector and a wide
decoder. That turns a module measuring 506 ALMs into 1,285 ALMs of design
growth and 0.54 ns of slack, and run M proved the growth is combinational and
therefore not something the fitter can be talked out of.

**The fix is to stop parsing ASCII on the FPGA.** Convert `.cht` to a packed
binary on the host, and the on-chip loader becomes a byte counter feeding a
128-bit shift register with a write strobe: no hex conversion, no tokeniser, no
key matching, no state machine. Estimate 60-120 ALMs against the current 441,
with far less for the fitter to inflate. P2 needs to cost about 300 ALMs of
growth instead of 1,285, which is well within reach when the parser is deleted
rather than shrunk.

This also fits the tooling that already exists. The cheats GUI in the GBC fork
is the natural place to emit the binary, and the 513-file corpus becomes the
conversion test set instead of an RTL test set, so the parsing logic keeps its
coverage on the host where it is much easier to verify.

**The cost is a usability regression**: a `.cht` dropped straight onto the SD
card stops working, and has to go through the converter first. That is a user
call. It is the only path found that does not give up save states or the RTC,
and unlike those it is not a gamble, because finding 8 says a feature cut is
not even guaranteed to buy slack.

### P3, delivered: the binary format

Format pinned in `docs/CHEATBIN.md`; converter in `tools/cheats/cht2bin.py`;
loader in `src/fpga/core/cheat_binloader.sv`. All merged via `p3-format` ->
`p3-converter` + `p3-binloader` -> `p3-binary` -> `d7a2138`.

The converter is a thin wrapper, not a reimplementation: `tools/cheats/gbacht.py`
was already the Python reference model for the RTL and exposes `parse()` and
`words()`, so the parsing logic that left the FPGA had been sitting in the repo
as the thing that validated it.

The file stores the 128-bit words verbatim, so the loader does no
transformation. Two things in the format are load-bearing and easy to get
wrong:

- **Entry order matters.** A conditional is a compare entry immediately
  followed by the entry it guards. Nothing may sort, dedupe or reorder.
- **The header magic is a safety interlock, not decoration.** The previous
  format was a plain `.cht`, so someone dropping the old file in is a real
  scenario, and shifting ASCII into the cheat table would corrupt the game.
  Wrong magic or version loads zero entries.

Outcome against the target: P2's growth was 1,285 ALMs, the goal was about 300,
and the measured cost is **61 ALMs with zero physical-synthesis churn**.
`cheat_loader.sv` is still in the tree and is not dead code: `tools/sim/run.py`
compiles it as the reference that cross-checks `gbacht.py`, which is what the
shipping converter parses with.

### What was tried and did not work, so it is not retried

The section below is kept because the reasoning was sound and the measurement
is what refuted it. Constraining `cheat_loader` was the best available theory
until run M tested it.

## Superseded: constrain `cheat_loader` instead of cutting features

Counting every node physical synthesis modified, retimed or created in run L:

| Module | nodes touched | share | share of area |
|---|---|---|---|
| `gba_top` (the whole emulator) | 6,267 | 85 % | ~95 % |
| **`cheat_loader`** | **930** | **12.7 %** | **2.5 %** |
| `save_type_detector`, `sdram_pocket`, `data_loader`, others | 139 | 2 % | |

`cheat_loader` absorbs five times its share of optimisation effort. The named
nodes are its parser arithmetic: `Add4`, `Add6`, `Add7`, `Decoder0`, each
spawning `_OTERM` retimed registers and `_RESYN*_BDD*` resynthesised nodes.

This explains the amplification that has been the real problem all along. P1
alone was free (16,624 ALMs, +0.090 ns). Adding P2 took it to 17,909, a jump of
**1,285 ALMs for a module that measures 506**, and registers rose only 433, so
the growth is combinational.

**The effort is being spent on something that does not need it.**
`cheat_loader` parses a `.cht` file once at load time. It has no gameplay
timing requirement, it is not in the video or CPU path, and none of the 44
violating paths touch it. The fitter has not been told any of that, so it
retimes a file parser as though it were critical, manufacturing area that
congests the paths that genuinely are.

So the next move is a constraint, not a cut. In the SDC, declare
`cheat_loader`'s internal paths false or multicycle and let the fitter stop
paying for speed nobody needs. Ranked by how much it gives up:

1. **`set_multicycle_path` on `cheat_loader` internals.** Costs nothing, the
   parser has hundreds of idle cycles per byte. Try this first.
2. **`set_false_path`**, if the parser is fully self-timed and its outputs are
   only sampled after a done handshake. Verify the handshake before claiming
   it, since a wrong false path is a silent hardware bug rather than a build
   error.
3. **Restructure the parser RTL** to shorten the combinational adder and
   decoder chains, so there is less for retiming to find.

If this works it preserves **every** feature, and the link cable strip on
branch `exp-nolink` may not be needed at all. Do not merge the strip until this
has been tried; run K shows it does not help timing at STANDARD FIT anyway.

## Branch map

The thirteen experiment worktrees under `~/Desktop/repos/` were removed on
2026-08-26. **Every branch survives** in the main repo's `.git`; the worktrees
were only checkouts. None of them is on the remote and none should be: `origin`
carries `master` alone. `git worktree add ../<dir> <branch>` brings any of them
back. Nothing is pushed to any remote; `origin` holds only upstream's `master`
and `rumble-support`.

| Branch | Tip | Holds |
|---|---|---|
| `master` | (tip) | **the integration branch**, and the only one on the remote. P1 + P3, closes timing. Releases are built from here and CI refuses a tag that is not on it. |
| `p5-cartridge` | `cfd4264` | **the cartridge branch.** Slot declared and powered, header probe, ROM out of the cart. First hardware run froze; fix committed, not yet fit. See the top of this file. |
| `p3-binary` | `d7a2138`^ | P3 assembled: format, converter, binloader. Merged. |
| `p3-format` / `p3-converter` / `p3-binloader` | | the three P3 strands, merged into `p3-binary`. |
| `p2-cheat-loader` | `c7aebd5` | P1+P2 with the ASCII parser. The design that failed timing. |
| `p1-cheat-engine` | | P1 alone, the build that proved there was room for the engine. |
| `exp-nolink` | `e3c6d64` | P2 plus the link-cable strip. **Retire, do not merge:** run K showed the strip does not help, and `master` closes with the link intact. |
| `exp-nolink-g` | `40ac38c` | as `exp-nolink` at STANDARD FIT (run K). |
| `exp-nolink-h` | `0e807d6` | as G plus area-biased physical synthesis (run L). |
| `exp-standard-16` | `47496dc` | the dead 16-entry lever, kept for reproducibility. |
| `exp-seed2` | `fcc3fae` | seed 2 roll (run G). |
| `exp-16entries` | `fcc3fae` | misleading name, clean at 32 entries; the seed 5 roll (run I). |
| `exp-cheat-mcp` | | the multicycle constraint (run M). |
| `exp-psnormal` | | `PHYSICAL_SYNTHESIS_EFFORT NORMAL` (run N). |
| `master` | | upstream v0.6.2, untouched. |

Two git-ignored things went with the worktrees, both regenerable:

- **The 513-file `.cht` corpus.** Re-fetch from libretro-database,
  `cht/Nintendo - Game Boy Advance`, and either drop it at `external/cht` or
  pass `CHT_DB=`. Without it `make test` skips the two corpus passes and says
  so; it does not silently pass.
- **Every built bitstream**, including the one that closed. Rebuild from
  `master` with `make gba FITTER_EFFORT="STANDARD FIT"`, about 23 minutes.

## Next steps, in order

1. **Hardware validation, mostly done.** `docs/HARDWARE.md` is the checklist,
   with the expected `CL:` value worked out for each case. Everything below has
   been seen work on a Pocket except the last item, and sleep with the engine
   running is still unreported. What had to be seen:
   - the core boots a ROM at all, i.e. P1's engine did not break the build;
   - `<rom>.gba.chtbin` loads and the `CL:`/`CD:` menu readouts show a
     plausible entry count;
   - a code visibly takes effect in-game;
   - the Cheats Enabled toggle turns it off and back on live;
   - a stray `.cht` renamed to `.chtbin` loads **zero** entries rather than
     corrupting anything. This is what the `GBAC` magic is for and it is the
     one failure mode simulation cannot fully vouch for.
2. **P8 packaging**, done for the cheat feature: shipped as v0.9999.
3. **Cartridge (P5) is under way on branch `p5-cartridge`, and the sizing
   question this item used to propose has been answered.** Wokann's
   `gba_cart_controller.sv` and `rom_source_mux.sv` are vendored verbatim under
   Wokann's authorship, instantiated rather than merely listed in the qsf, and
   `gba_top`'s ROM reads run through the mux with the cart side idle and
   `cart_mode` off a live register, so nothing folds away and the measurement is
   real.

   Nine builds on one host: `main` `6994156` at 17,744 ALMs (96 %) and +0.059 ns
   setup, the branch at -0.410, -0.125 and **+0.087** on seeds 1, 2 and 3. **It
   closes on one placement seed in three**, and what fails on the other two is
   the PLL output counter that is already `main`'s worst path, not anything in
   the controller. An initial 1.191 ns miss was entirely three configuration
   inputs sharing a register with the per-access inputs; splitting them out with
   a multicycle of 4 recovered all of it, and the bus logic met 100 MHz unaided.

   **The area half of this item cannot be answered.** Identical RTL spans 81
   ALMs across seeds, which is the size of the thing being measured, so the
   1,791-ALM headroom figure above cannot size a 905-line module, and the
   "640 ALMs left" reading taken mid-branch is **withdrawn**. Slack across
   several seeds is the measure now. Also still unexplained: 16,689 ALMs on the
   workstation and in CI against 17,744 on the build runner, for identical RTL.

   What is left is listed in `PLAN.md` §2b: the APF declaration, the cart pin
   handover, detection and header read, ROM read speed, save/EEPROM/GPIO routing
   and `save_size = 0` in cart mode. All but the ROM boot path already exist on
   `wokann/master`, debugged on real hardware, so they are there to import
   rather than to solve.

   Tables in `docs/BASELINE.md`. Note that `mincer-ray/openfpga-GBA` reports
   `parent: none` - it is the root of the lineage, so there is no better base to
   rebase onto; all 14 forks are downstream additions. Upstream has not moved
   since v0.6.2, so no rebase is pending.
4. **Retire `exp-nolink`.** Do not merge it. See the branch map.
5. **P4 (OSD) is closed, not deferred.** The user has confirmed the overlay is
   not wanted. The `CL:`/`CD:` menu readouts carry the diagnostics.

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

- `FITTER_EFFORT` and `NPROC` only landed on the integration branch at
  `e5656b6`. Worktrees
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

Green end to end on `master`, and it always was: the fit problem was never a
correctness problem. `make test`:

| Pass | Result | Covers |
|---|---|---|
| `test_cht2bin.py` | 24/24 | the converter, including three hand-computed entries with derivations and a cross-check against an encoder nobody here wrote |
| `run_binloader.py` | 19/19 | `cheat_binloader.sv`. Mutation-verified: reversing the shift loses 10 cases, delaying `cheat_on` loses exactly the two zero-gap cases |
| `run_fixtures.py` | 10/10 | known-good words |
| `run_e2e.py` | 9/9 | `.cht` in, cheat table out |
| `run.py` | 513/513 | the whole libretro GBA corpus, RTL parser against `gbacht.py` |

The last two want the corpus; see the branch map for where it went and how to
get it back.
