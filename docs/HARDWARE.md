# Hardware validation

The current tested build is `cfbfa81`, seed 1. Its bitstream matches the
mounted Pocket card by SHA-256 on 2026-09-15, when the maintainer reconfirmed
EverDrive GBA Mini gameplay, cheats and saves with Slow timing for boot.
The retail-cartridge results below were recorded on `f2a86db`, seed 3,
installed on 2026-09-10; they are not fresh tests of every path on `cfbfa81`.

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
| EverDrive GBA Mini | Boot on Slow; gameplay, cheats and saves confirmed. Fast Burst after boot provides the retail-cartridge audio fixes, including Zero Mission. A new Minish Cap EEPROM save persisted |
| EZ-Flash Omega DE on Turnaround | Games and existing EEPROM/SRAM saves load; new saves do not persist |

The twelve midair patches fit within the sixteen-slot ROM table.
Fast Burst remains opt-in; Turnaround is the default.

## Not qualified or unsupported

- Physical SRAM/Flash save-write persistence, the interrupted-transfer guard,
  and empty or partially inserted cartridges still need hardware checks.
- Fast Burst has been exercised on one cartridge, not a range of ROM chips.
- Cartridge GPIO is forwarded after read-enable; RTC and the EverDrive
  battery-warning behavior need verification. Solar and gyro are unsupported.
- New EZ-Flash Omega DE saves do not persist for either tested save type.
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

`cfbfa81`, Quartus Lite 25.1std build 1129, STANDARD FIT, seed 1:

| Measure | Result |
|---|---|
| ALMs | 15,996 / 18,480 (87 %) |
| RAM blocks | 278 / 308 |
| Worst setup / hold | +0.075 / +0.101 ns |
| Recovery / removal / minimum pulse width | +3.873 / +1.056 / +0.827 ns |
| Bitstream SHA-256 | `1c11b22d840fd5dee28d0c71b95575f4096224b9fbe8ff0461c7517f3fcd7685` |

The complete simulation suite is `make test`. Its two corpus checks require
`CHT_DB`; without a mounted corpus they report skips.
