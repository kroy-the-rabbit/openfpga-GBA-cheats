# P0 baseline: upstream v0.6.2, unmodified

Numbers below are **upstream's**, not ours: this fork has not built anything
locally yet. They come from mincer-ray's own CI, run `27648777430`
(commit `b08568f`, tag v0.6.2, 2026-06-16), whose `reports` artifact carries the
fit and STA reports. Quartus Prime Lite 21.1.1 Build 850, device `5CEBA4F23C8`,
`FITTER_EFFORT "AUTO FIT"`, `SEED 8` (both from `src/fpga/build/ap_core.qsf`).

P0 is not complete until the same build is reproduced locally under a Podman
harness and the numbers here are replaced with ours. See `docs/PLAN.md` §4.

## Utilization

| Resource | Used | Available | |
|---|---|---|---|
| Logic (ALMs) | 16,648 | 18,480 | **90 %** |
| Registers | 24,249 | | |
| RAM blocks | 278 | 308 | **90 %** |
| Block memory bits | 2,056,488 | 3,153,920 | 65 % |
| DSP blocks | 26 | 66 | 39 % |
| PLLs | 2 | 4 | 50 % |
| Pins | 224 | 224 | 100 % |

## Timing

Timing is met, and `timing.txt` from the same run reads "No timing closure
failures", but the margin is thin and it is thin in the worst possible place.
Worst slack in each direction, across all four corners:

| Analysis | Slack | Corner / clock |
|---|---|---|
| Setup | **0.102 ns** | Slow 1100mV 85C, `...sys_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk` |
| Setup | 0.090 ns | Slow 1100mV 0C, same clock |
| Hold | 0.077 ns | Fast 1100mV 0C, same clock |
| Setup | 1.551 ns | Slow 1100mV 85C, `clk_74a` |
| Setup | 2.873 ns | Slow 1100mV 85C, `sdram_clk` |
| Setup | 9.520 ns | Slow 1100mV 85C, `bridge_spiclk` |

That PLL output counter is `clk_sys`: `src/fpga/core/core_constraints.sdc:82`
names exactly this clock, and `src/fpga/core/core_top.sv:1078` documents it as
about 100.66 MHz, the GBA core domain. `gba_top` is clocked from it
(`core_top.sv:1575`). So the tightest path in the design is on the clock any
cheat engine or cartridge controller would run on, with 0.1 ns to spare against
a 9.93 ns period.

## What this means for the work

- **Fit is the first-order constraint,** the opposite of the GBC fork. There it
  was 9,296 / 18,480 ALMs (50 %) with 2.374 ns of setup slack, and the plan
  could say "fit is not a concern". Here there are roughly 1,830 ALMs and 30
  M10K blocks left, and both the cheat engine and the cartridge bus controller
  have to come out of that.
- **`gba_cheats.vhd` is the cheap half but not free.** 32 entries x 128 bits is
  4,096 bits of storage that Quartus will put in registers unless it infers
  MLABs, plus a 128-bit `SyncFifo` and an FSM. Measure at P1 with one hardcoded
  cheat before any loader work; if it does not close, cut `CHEATCOUNT` to 16
  first.
- **The OSD is the expensive half.** `cheat_font.sv` in the GBC fork is a
  595-line font ROM. At 90 % RAM blocks that is the first thing to lose, and
  the menu readout may have to carry the whole diagnostic story.
- **Upstream already spends effort on closure.** `scripts/seed_sweep.sh` and
  `scripts/sta_custom_report.tcl` exist because this design is marginal. Keep
  them, keep Quartus 21.1, and make the local wrapper fail on negative slack
  rather than trusting Quartus's exit code, which is the lesson the GBC harness
  learned the hard way.

## Phase log

| Phase | Commit | ALMs | Worst setup | Hardware |
|---|---|---|---|---|
| Upstream v0.6.2 (reference) | `b08568f` | 16,648 | 0.102 ns | mincer-ray's release, not tested here |
| P0 local baseline | pending | | | |
