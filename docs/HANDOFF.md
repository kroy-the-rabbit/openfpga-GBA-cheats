# Development status

## Current state

`main` contains the cartridge work from `p5-cartridge` and is pushed.
Release `v0.9999.20260913` contains the cartridge update. Its tested build is **`f2a86db`**, seed 3, installed on 2026-09-10.
`f5de823` adds only documentation to that source; the main-alignment changes
update documentation and simulation CI, not the FPGA design or package.

| Tested build | Result |
|---|---|
| Quartus | Lite 25.1std build 1129, STANDARD FIT |
| ALMs / RAM blocks | 16,080 / 18,480 (87 %); 278 / 308 |
| Setup / hold | +0.092 / +0.121 ns; all timing categories pass |
| Bitstream SHA-256 | `489904ea59dea4e1408c770cbe8e853a67741f5817d1884d59e57e77b7d3f31b` |

**On hardware:** Minish Cap and Zero Mission cartridge gameplay and existing
saves; a new Zero Mission save read back through Analogue's own mode; direct
`.cht`, named overlay, RAM conditions and read-side ROM patches. Both midair
cheats work together, using twelve of sixteen ROM-patch slots. Fast Burst
gives clean audio on the tested Zero Mission cart; Turnaround stays default.

**Behavior:** cheats and overlay start off and are not persisted. Loading
cheats neither resets the game nor enables the switch. Slot 7 accepts `.cht`
and `.chtbin`; cartridge games require browsing to the file. Physical saves
read and write the cartridge directly, with no Read Only mode or SD save.
Savestates, sleep and link cable are removed. RTC remains for SD ROMs.

**Remaining:** SRAM/Flash write persistence, interrupted transfers, empty-slot
handling and Fast Burst on more cartridges need hardware qualification.
Cartridge GPIO/RTC, solar and gyro are disconnected. Native Action Replay
ROM-patch opcodes and encrypted codes need conversion to supported raw codes.

## Branch `p6-flashcarts`

Flash-cart support: CPU writes to ROM space reach the cart, and register reads
at `09E00000..09FFFFFF` bypass the cache after the first write. Baseline on
`f2a86db`: the Omega DE bootloops at a popup, most likely its firmware update prompt, and the
EverDrive shows a red screen. `1a7e841` (seed 3 on kira, +0.092 ns) boots both
on Turnaround; the EverDrive then fails to mount its SD card. The next build
adds a turnaround to register reads.
See [CARTRIDGE.md](CARTRIDGE.md#flash-carts).

## Release preparation

Use a signed `v0.9999.YYYYMMDD` tag whose commit is on `main`. Publish
the tested bitstream with dated package metadata, `BUILD.json`, `report.txt`
and `SHA256SUMS`. A package built from
`f2a86db` retains that source identity even when later docs are on `main`.
Check the workflow at the tagged commit before publication; the workflow on
`main` may be newer. Current CI runs `make sim-image` and `make test`, then
verifies release assets. Quartus runs only through `tools/runner-build` on
controlled runners; CI does not build or replace bitstreams.

Prepared assets are under `build/releases/0.9999.20260913/`, copied from
`build/watch/pocket-gba-gba-slots16-s3-f2a86db59fa9/`. Ignore stale
`build/gba/sd` and old top-level packages when selecting release assets.
See [HARDWARE.md](HARDWARE.md), [BUILD-RUNNER.md](BUILD-RUNNER.md) and
[BASELINE.md](BASELINE.md).


[Engineering history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/gba/docs/HANDOFF.md) (private).
