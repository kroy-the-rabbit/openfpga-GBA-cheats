# Development status

## Current release

Release `v0.9999.20260915` on `main` packages tested build **`cfbfa81`, seed 1**. Its bitstream
matches the mounted Pocket card by SHA-256 on 2026-09-15. The maintainer
confirmed EverDrive GBA Mini gameplay, cheats and saves, using **Slow** timing
to get past boot, then Fast Burst for the same audio fixes as retail
cartridges, including Zero Mission. A new Minish Cap EEPROM save persisted.

| Measure | Result |
|---|---|
| Quartus | Lite 25.1std build 1129, STANDARD FIT |
| ALMs / RAM blocks | 15,996 / 18,480 (87 %); 278 / 308 |
| Setup / hold | +0.075 / +0.101 ns; every timing category passes |
| Bitstream SHA-256 | `1c11b22d840fd5dee28d0c71b95575f4096224b9fbe8ff0461c7517f3fcd7685` |

The source package and report are in
`build/watch/pocket-gba-gba-rtcgpio-s1-cfbfa819589c/`. Later release-preparation
changes are documentation and test fixtures only. Preserve these tested
bitstream bytes and record their original build commit in `BUILD.json`.

**Limits:** Omega DE runs games and loads existing saves on Turnaround, but
new EEPROM and SRAM saves do not persist. Cartridge RTC operation and the EverDrive battery-warning fix are verified.
Save writes are confirmed on EverDrive, Minish Cap, Metroid: Zero Mission
and other tested cartridges. Four text-cheat corpus mismatches reproduce identically
on the September 13 release and this candidate; see [CHEATS.md](CHEATS.md).

The previous public release is `v0.9999.20260913`, built from `f2a86db`, seed 3.
Its retail-cartridge results include Minish Cap and Zero Mission gameplay and
existing saves, a new Zero Mission save read through Analogue's own mode,
cheats and named overlays, and Fast Burst correcting Zero Mission audio.
See [HARDWARE.md](HARDWARE.md), [CARTRIDGE.md](CARTRIDGE.md) and
[BASELINE.md](BASELINE.md) for the evidence and limits.

## Publication

Release notes are in `.github/release-notes.md`. The signed dated tag is on
`main`. The release ZIP carries dated package metadata, the unchanged tested
bitstream, `BUILD.json`, `report.txt` and `SHA256SUMS`. `BUILD.json` records
build and release commits separately. CI tests the source and verifies the
published package; it does not synthesize or replace the bitstream. Quartus
runs through `tools/runner-build` only.

[Engineering history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/gba/docs/HANDOFF.md) (private).
