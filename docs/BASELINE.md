# P0 baseline: upstream v0.6.2, unmodified

Built here with `make gba` from `98c04b2`, whose RTL is untouched upstream
v0.6.2: Quartus Prime Lite 21.1.1 Build 850 inside
`docker.io/raetro/quartus:21.1`, device `5CEBA4F23C8`, `FITTER_EFFORT
"AUTO FIT"`, `SEED 8` from `src/fpga/build/ap_core.qsf`. 1,049 s wall clock on
14 cores, 59 min of CPU. Numbers come from `build/gba/report.txt`.

They match mincer-ray's own CI (run `27648777430`, tag v0.6.2) exactly, ALM for
ALM and picosecond for picosecond, which is the useful result: the local harness
reproduces upstream's build rather than approximating it, so any movement from
here is ours.

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

Worst slack per analysis type, across all four corners:

| Analysis | Slack | Corner / clock |
|---|---|---|
| Setup | **0.090 ns** | Slow 1100mV 0C, `...sys_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk` |
| Setup (85C) | 0.102 ns | Slow 1100mV 85C, same clock |
| Hold | 0.077 ns | Fast 1100mV 0C, same clock |
| Recovery | 6.939 ns | Slow 1100mV 85C, same clock |
| Removal | 0.330 ns | Fast 1100mV 0C, same clock |
| Min pulse width | 0.827 ns | Slow 1100mV 85C, `...gpll~FRACTIONAL_PLL|vcoph[0]` |

Every one of those worst cases is on the same clock, and that clock is
`clk_sys`: `src/fpga/core/core_constraints.sdc:82` names it, and
`src/fpga/core/core_top.sv:1078` documents it as about 100.66 MHz, the GBA core
domain. `gba_top` is clocked from it (`core_top.sv:1575`). So the tightest paths
in the design are on the clock any cheat engine or cartridge controller runs in,
with 0.09 ns to spare against a 9.93 ns period.

## What this means for the work

- **Fit is the first-order constraint,** the opposite of the GBC fork. There it
  was 9,296 / 18,480 ALMs (50 %) with 2.374 ns of setup slack, and the plan
  could say "fit is not a concern". Here there are about 1,830 ALMs and 30 M10K
  blocks left, and both the cheat engine and the cartridge bus controller have
  to come out of that.
- **`gba_cheats.vhd` is the cheap half but not free.** 32 entries x 128 bits is
  4,096 bits of cheat storage plus a 128-bit `SyncFifo`. If Quartus infers M10Ks
  that is roughly 2 more blocks on 278/308; if `cheatmem` falls back to
  registers it is about 4,096 registers plus a 32-way 128-bit read mux. Read the
  inference lines in the fit report, not just the summary.
- **The OSD is the expensive half.** `cheat_font.sv` in the GBC fork is a
  595-line font ROM. At 90 % RAM blocks that is the first thing to lose, and the
  menu readout may have to carry the whole diagnostic story.
- **Slack this thin is placement-sensitive.** Upstream ships `SEED 8` and a
  `scripts/seed_sweep.sh` because of it. `make gba SEED=<n>` is the first move
  against a marginal path, ahead of any design change.

## Phase log

| Phase | Commit | ALMs | RAM blocks | Worst setup | Hardware |
|---|---|---|---|---|---|
| Upstream v0.6.2, upstream CI | `b08568f` | 16,648 | 278 | 0.102 ns (85C) | mincer-ray's release |
| P0 local baseline | `98c04b2` | 16,648 | 278 | 0.090 ns (0C) | not yet flashed |
| P1 cheat engine restored | `a0370cb` | pending | pending | pending | |
