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
| **Toggle fix, build runner, 16 processors** | `3bcd7d9` | **17,633** | **282** | **+0.048 ns** | **timing met; does not reproduce, see below** |

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
runner at 4, and at **17,744** on a build runner at 16. Anything sized by
comparing two builds - a feature's cost, the headroom left for the next one -
has to have both sides built on one host, back to back, or it is arithmetic on
numbers that were never comparable.

#### What a nine-build run on one host actually showed

That rule was first written claiming three instances of a thousand-ALM swing
and blaming the build host for all of them. One of the three has since
dissolved, and the mechanism was wrong.

The `17,633` figure originally recorded here for the build runner **does not
reproduce**. On that same host, `3bcd7d9` and `6994156` were rebuilt cold and
warm, four builds in all, and every one returned **17,744 / 24,735 registers /
+0.059 setup**, identical to the digit. The two commits differ only in three
documentation files, and the git SHA reaches `core.json` after the compile
rather than synthesis, so Quartus saw the same input each time. `17,633` was a
one-off whose cause was not found; it is not evidence of anything and the
number to carry forward is 17,744.

Three things were ruled out along the way, and are worth not re-testing:

- **Run-to-run variance is zero.** Repeat builds of a branch on one host agree
  exactly, including which timing corner wins.
- **Quartus scratch state is irrelevant.** A build with `work/` deleted
  outright matches one that inherited `db/` from the previous build, and it
  does not matter whether that previous build was the same branch or a
  different one.
- **Seed is not irrelevant, and is the only knob found that moves the number.**
  Identical RTL across seeds 1-3 spans 81 ALMs and 497 ps of setup slack.

So the intra-host part of the original claim was wrong: on one host this design
is deterministic per seed, not noisy by a thousand. What remains genuinely
unexplained is the **cross-host** gap - 16,689 on the workstation and in CI
against 17,744 here, ~1,050 ALMs for identical RTL - and one unreproduced
outlier. The practical instruction the rule produced is unaffected and is what
made the cartridge comparison below trustworthy; only the count of evidence
behind it, and the "it is noisy on any host" reading of it, were overstated.

What is reproducible, and what actually decides whether a build ships, is
timing closure - though "closes" now has to mean across seeds, not on one.

## Cartridge probe: it closes on one placement in three, and the cost is timing

Branch `exp-cart-probe`. Wokann's `gba_cart_controller.sv` and a
`rom_source_mux` vendored and instantiated behind a harness whose only job is
to stop the fitter optimising them away: every input driven from a bridge
register, every output folded into a bridge-readable word. `gba_top`'s ROM
reads go through the mux, which passes them to SDRAM while `cart_mode` is low.

Everything below was built on one host, back to back, under identical
conditions - the rule the previous section exists to state. Earlier numbers in
this section compared a workstation build against a runner build and are
withdrawn.

| | ALMs | RAM | Setup | Hold | |
|---|---|---|---|---|---|
| `main` `6994156` | 17,744 (96 %) | 282 | **+0.059** | +0.026 | pass |
| + cartridge front end, seed 1 | 17,814 (96 %) | 282 | **-0.410** | +0.093 | fail |
| + cartridge front end, seed 2 | 17,787 (96 %) | 282 | **-0.125** | +0.094 | fail |
| + cartridge front end, seed 3 | 17,868 (97 %) | 282 | **+0.087** | +0.108 | pass |

**It closes, but only on one placement in three.** `release.yml` retries a
timing miss at seeds 2 and 3 before giving up, so this would ship - on the
third try, with 87 ps of margin and nothing behind it.

**The multicycle constraint did its job and is not what is failing.** The
1.191 ns recovered earlier was three configuration inputs: `phi_sel`,
`gpio_timing_mode` and `gpio_recover_set` are settings, written from the menu
and then still, and `gpio_recover_set` feeds a 14-bit compare that reaches the
bus state machine. Giving the three their own register and a multicycle of 4
recovered all of it. The per-access paths were deliberately left alone -
`byte_addr` is loaded in `S_IDLE` and `out_bank*` from it in `S_ROM_CS` on the
next cycle, so those genuinely have one cycle, and a blanket multicycle would
have closed timing in the report and failed on a bench. They pass unaided.

What fails on seeds 1 and 2 is `sys_pll_i|...|PLL_OUTPUT_COUNTER|divclk`,
which is **`main`'s own worst path**, sitting at +0.059 before the controller
is added. Nothing inside `gba_cart_controller` appears. This is the P2 failure
mode - congestion pushing a pre-existing marginal path over - not the P3 one.

### The area figure has saturated and should not be used to size anything

The four builds above span 17,787 to 17,868 ALMs for **identical RTL**, purely
by seed. That spread, 81 ALMs, is the same order as the 43-124 ALM "cost" of
the entire cartridge front end measured against `main`. A 905-line bus
controller plus a ROM mux does not cost 70 ALMs; the register count *falls* by
around 400 when it is added, which is retiming and packing rearranging the
same logic into fewer, fuller ALMs.

At 96-97 % occupancy an ALM holds two LUTs and two FFs and the fitter packs
pairs into one rather than spreading them, because there is nowhere to spread
to. New logic consumes the packing headroom instead of the area headroom, and
the bill arrives as slack.

So **"how many ALMs are left" is not a question this design can answer any
more.** The previous version of this section put 640 ALMs of headroom on that
number and planned the remaining work against it. That figure is withdrawn.
What is left to do is unchanged - save and EEPROM routing to `gba_top`,
`save_size = 0` in cart mode so the Pocket does not fight the cartridge for the
save, the APF declaration, and ROM out of the cart fast enough that the CPU is
not stalled - but the thing to watch while doing it is worst-case slack across
several seeds, not the utilisation percentage.

Nothing on that branch is mergeable regardless: `cartridge_adapter` is not
declared, so the Pocket never powers the slot, and no save or cheat is routed
through the controller.

### Where these were built

The last of these ran on a dedicated LXC on a Proxmox node rather than the
workstation: 1377 s against 2610 s locally for a comparable design, on a Xeon
E5-2680 v4 at 16 cores. The workstation is a 15 W Core Ultra 7 155U, which
throttles under a 40-minute fit; a 4-core GitHub runner beat 12 threads of it
by the same ratio. Core count is not the lever, sustained clock is. `NPROC`
still does not change the result.

### What this does not establish

- **It is a probe, not an integration.** No ROM, save or cheat is routed
  through the controller; `rom_source_mux` is vendored but not instantiated,
  and `cartridge_adapter` is not declared, so the Pocket never powers the slot.
  A real integration adds the mux and the paths from `gba_top`, which this has
  not measured.
- **Wokann's wait states are placeholders** their own author says must be
  calibrated on real cartridges, so the timing this controller finally needs is
  not settled.
- **ROM-from-cart has never run anywhere.** Wokann's own `core_top` hard-wires
  `han_rom_cart_mode` to 0: their design runs a translated ROM from SD and uses
  the cart for saves, GPIO and EEPROM. The ROM read path exists and is wired
  and has never been anyone's boot path.
- **A correction on method.** An earlier reading of this experiment reported
  "400 failing paths". That was wrong: it counted incremental-delay rows inside
  a `-detail full_path` breakdown rather than violations. The report states its
  own verdict in a header - "Found 80 setup paths (0 violated)" - and that
  header is the thing to read. The identification of *which* paths were worst
  was right; the count was not.


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
