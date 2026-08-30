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
- **`gba_cheats.vhd` turned out to be nearly free, which P1 settled.** `cheatmem`
  infers as `altsyncram` rather than registers (the fit report shows
  `gba_cheats:igba_cheats|altsyncram:cheatmem_rtl_0`), so the engine costs 3 RAM
  blocks and 14 registers, and ALMs came out 24 lower than the baseline, which is
  placement noise rather than a saving. That leaves about 27 RAM blocks and 1,850
  ALMs for the loader, the OSD and the cartridge controller.
- **Hold slack is now the number to watch, not setup.** P1 left setup untouched
  at 0.090 ns but took hold from 0.077 ns to 0.035 ns, on the same
  Quartus-managed path inside the PLL output counter. That is the path the GBC
  fork once failed by 0.001 ns, and the answer there was a different seed rather
  than a design change.
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
| P1 cheat engine restored | `1df58a0` | 16,624 | 281 | 0.090 ns (0C) | built, not yet flashed |
| P1+P2 merged, AUTO FIT | `fcc3fae` | 17,909 | 284 | **-0.846 ns** | fails timing, not built |
| P1+P2, STANDARD FIT | `fcc3fae` | 17,903 | 284 | **-0.452 ns** | fails timing, not built |
| P1+P2, 16 entries | `fcc3fae` (dirty) | 17,980 | 284 | **-0.711 ns** | lever is dead, see below |
| P1+P2, AUTO FIT seed 2 | `fcc3fae` | 17,988 | 284 | **-1.321 ns** | seed variance, not a result |
| P1+P2, STANDARD FIT seed 3 | `fcc3fae` | 17,871 | 284 | **-0.453 ns** | confirms the -0.45 floor |
| **P3 binary loader, STANDARD FIT** | `448fb44` | **17,544** | **282** | **+0.090 ns** | **timing met, bitstream built** |
| **P3 rebuilt, STANDARD FIT, 12 processors** | `66a7d6a` | **16,689** | **282** | **+0.090 ns** | **timing met, bitstream built** |
| **P3 on CI, STANDARD FIT, 4 processors** | `9650073` | **16,689** | **282** | **+0.090 ns** | **timing met, same to the digit** |
| **Toggle fix, build runner, 16 processors** | `3bcd7d9` | **17,633** | **282** | **+0.048 ns** | **timing met, see below** |

### The two P3 rows are the same design, and they disagree by 855 ALMs

Not a typo and not a change. The RTL is identical: the only diff between
`448fb44` and `66a7d6a` under `src/` is thirteen comment lines in
`cheat_loader.sv`, which stopped being synthesised when the qsf was pointed at
`cheat_binloader.sv`, and both commits list exactly the same sources. Both runs
were Standard Fit. RAM blocks and worst setup match to the digit.

The first explanation was the machine: the rebuild had all 12 processors, and
the original was made in a worktree while several experiments shared the box
under a capped `NUM_PARALLEL_PROCESSORS`. Quartus's fitter is multithreaded and
its placement may depend on how it divides the work, so that looked like the
answer.

**It is not.** The third row settles it. CI builds the same commit with
`NPROC=4` and lands on 16,689 ALMs, 282 RAM blocks and +0.090 ns - identical in
every figure to the 12-processor local build. Processor count does not move
this fit, so it cannot be what moved the earlier one.

That leaves the 17,544 figure unexplained. Both builds that agree were made
from a clean tree with `FITTER_EFFORT="STANDARD FIT"` and no seed; the one that
disagrees was made in a worktree whose exact state is gone along with its build
log, so the difference is most likely something about that tree rather than
about Quartus. **Treat 17,544 as unreproduced.** Two machines, two processor
counts, one answer is better evidence than one run nobody can repeat.

What follows:

- **Headroom after cheats is 1,791 ALMs and 26 RAM blocks**, measured twice
  independently. The earlier "936 to 1,791, do not quote a number" hedge was
  the right response to one contradiction and is superseded by the second
  measurement.
- **`FITTER_EFFORT` still has to be pinned**; that finding stands on its own
  fifteen builds. `NPROC` does not need to be, on this evidence, though CI
  pins it anyway because it costs nothing.
- **CI and a local build are the same build**, which is the point of running
  `tools/podman/build.sh` in both. This is the run that demonstrates it.

### The ALM count is a property of the build, not only of the RTL

The fourth row is the same design as the two above it. Its only RTL difference
from `9650073` is seven lines of bridge read mux and two changed comment
headers; the tree was checked clean, with no stray files and no extra qsf
entries. Nothing in that costs 950 ALMs.

So this design fits at **16,689** on a workstation at 12 processors and on a CI
runner at 4, and at **17,633** on a build runner at 16. That is the third swing
of roughly a thousand ALMs that is not the design - the first was the 17,544
reading in the section above, whose processor-count explanation was already
retracted when CI at 4 matched the workstation at 12.

Three instances is enough to stop treating it as a mystery and start treating
it as a rule. **At 90-97 % occupancy the ALM figure moves by around a thousand
depending on the build host, and an area delta taken across two builds means
very little.** Anything sized by comparing two builds - a feature's cost, the
headroom left for the next one - has to have both sides built on one host, back
to back, or it is arithmetic on numbers that were never comparable.

What is reproducible, and what actually decides whether a build ships, is
timing closure. Every build of this design has closed at a positive margin.

## The fit problem, and how to measure it

P1+P2 together do not fit. The gap is a reproducible **0.45 ns** of setup on
`clk_sys` at 97 % ALM occupancy. Three things about measuring it:

**Only STANDARD FIT measures the design.** At AUTO FIT, changing the placement
seed moved slack by half a nanosecond (-0.846 at seed 8, -1.321 at seed 2). At
STANDARD FIT it moved by one picosecond (-0.452 at seed 8, -0.453 at seed 3).
AUTO FIT was measuring placement luck, not the design. Run comparisons at
STANDARD FIT or the delta is noise. STANDARD FIT is also worth ~0.39 ns over
AUTO at the same seed, at no area cost.

**The fitter is deterministic.** Two independent runs of the 16-entry
configuration returned -0.711 ns and 17,980 ALMs to the digit, so numbers are
comparable across worktrees.

**It is congestion, not a slow new path.** All 44 violating paths are
pre-existing core paths (`gba_memorymux|vram_cycle` to `gba_cpu`,
`gba_cpu|new_cycles_valid`, `gba_memorymux` to `gba_dma`). No cheat logic
appears on any of them. `gba_cpu` gained 369 ALMs with no source change,
purely from physical-synthesis register duplication under pressure. Roughly
135 ALMs buys 0.1 ns, so the gap is about 600 ALMs.

**Shrinking the cheat table does not help.** Halving `CHEATCOUNT` and
`MAX_ENTRIES` to 16 made the design larger (17,980 vs 17,909) and slower. Both
tables already live in RAM blocks, so fewer entries buys no ALMs and only
perturbs placement. Do not retry it.

### How it was solved

The parse moved off the FPGA. `cheat_loader.sv` measured 441 ALMs and drew 930
physical-synthesis modifications onto its parser arithmetic;
`cheat_binloader.sv` measures **61 ALMs and draws zero**, because a byte counter
and a shift register give retiming nothing to chase. Setup went from -0.452 ns
to +0.090 ns, which is exactly upstream's own margin, so cheats now cost no
timing at all. See `CHEATBIN.md` for the format and `HANDOFF.md` for the full
experiment log.

**Headroom after cheats: 1,791 ALMs and 26 RAM blocks.** Measured twice, on
two machines at different processor counts, agreeing in every figure. Cartridge
work comes out of that.
