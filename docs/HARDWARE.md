# Hardware validation

The tested candidate is `f2a86db`, seed 3, installed on 2026-09-10.
Later changes through `f5de823` are documentation only. This document records
hardware evidence; simulation and timing results are separate checks.

## Recorded results

| Feature | Evidence |
|---|---|
| SD ROMs, `.chtbin` loading, visible cheat effect and live global switch | Confirmed on the earlier v0.6.4 core |
| Physical cartridge gameplay | Minish Cap and Zero Mission boot and play |
| Existing physical saves | Both cartridges load their existing saves |
| New physical save | Zero Mission wrote a save that Analogue's own cartridge mode read back |
| Direct `.cht` and named overlay | Confirmed on a real cartridge; the first-character alignment fix is included |
| RAM writes and conditional pairs | Visible Zero Mission counter tests, including inverted conditions |
| EWRAM, IWRAM and IO reads | Guarded HUD-counter writes exercise each region |
| Read-side ROM patches | Entry-word test plus both six-patch midair cheats together on `f2a86db` |
| Fast Burst timing | Clean cartridge audio on the tested Zero Mission cartridge |

The twelve midair patches fit within the sixteen-slot ROM table.
Fast Burst remains opt-in; Turnaround is the default.

## Not qualified or unsupported

- Physical SRAM/Flash save-write persistence, the interrupted-transfer guard,
  and empty or partially inserted cartridges still need hardware checks.
- Fast Burst has been exercised on one cartridge, not a range of ROM chips.
- Cartridge GPIO/RTC, solar and gyro are disconnected.
- Savestates, sleep and link cable are removed. Sleep is not a pending feature test.
- The malformed-binary cases pass simulation; no new on-device malformed-file
  result is recorded. A normal `.cht` is supported and should load cheats.

## Qualifying a package

1. Use a package built from the exact source commit on a controlled runner.
   [BUILD-RUNNER.md](BUILD-RUNNER.md) describes the interface. Check every
   timing category in that package's report; a zero Quartus exit is not enough.
2. Merge its `Assets`, `Cores` and `Platforms` into the SD root. Preserve
   existing ROMs, BIOS and saves. Compare the installed bitstream's hash to
   the file inside that exact ZIP, then sync the card and power cycle the
   Pocket before checking its displayed version.
3. Boot an SD ROM with cheats disabled. Load a supported `.cht`, inspect its
   names and counts in **Cheat Overlay**, enable a visible cheat, and check
   the global switch off and on. Disabling stops new writes; it does not undo
   values already written into game memory.
4. Select a `.chtbin` explicitly and verify the same code effect, with
   `CHEAT nn` titles. Reloading either file must not reset gameplay or change
   **Cheats Enabled**. A fresh core launch starts both cheat switches off.
5. Choose **Play Cartridge** with a tested cartridge inserted. Browse to its
   cheat file through the **Cheats** slot. Verify gameplay and existing saves.
   Qualify write persistence separately by reloading a backed-up test save.
6. Record the source commit, package and bitstream hashes, cartridge/game,
   timing profile and observed result. Report any untested cases explicitly.

`CL:` and `CD:` are no longer menu diagnostics. Cartridge readouts are
`CG:`, `CS:`, `SF:` and `EE:`; see [BOOT-DEBUG.md](BOOT-DEBUG.md).

## Candidate fit

`f2a86db`, Quartus Lite 25.1std build 1129, STANDARD FIT, seed 3:

| Measure | Result |
|---|---|
| ALMs | 16,080 / 18,480 (87 %) |
| RAM blocks | 278 / 308 |
| Worst setup / hold | +0.092 / +0.121 ns |
| Recovery / removal / minimum pulse width | +2.935 / +0.966 / +0.827 ns |
| Bitstream SHA-256 | `489904ea59dea4e1408c770cbe8e853a67741f5817d1884d59e57e77b7d3f31b` |

The complete simulation suite is `make test`. Its two corpus checks require
`CHT_DB`; without a mounted corpus they report skips.
