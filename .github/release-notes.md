## Flash carts, boot timing and cartridge audio

**EverDrive GBA Mini now runs through Play Cartridge with cheats and saves.**
Set **ROM Timing** to **Slow** to get past boot, then switch back to
**Fast Burst** for the same audio fixes as physical cartridges, including
Zero Mission. The ultimate in meta: a flash cart running inside an
openFPGA GBA core, with the core applying cheats. A new Minish Cap EEPROM save
persisted, and gameplay, cheats and saves are confirmed on the Pocket.

This update forwards flash-cart register writes and reads and preserves
sequential DMA transfers from the cart's SD interface, letting the EverDrive
mount its card and load games. Timing profiles matter at the physical slot:

| Cartridge | ROM Timing | Hardware result |
|---|---|---|
| EverDrive GBA Mini | **Slow** for boot, then **Fast Burst** | Games, cheats and saves work; Fast Burst fixes audio as on retail carts |
| EZ-Flash Omega DE | **Turnaround** | Games and existing saves load; new saves do not persist |
| Metroid: Zero Mission retail cartridge | **Fast Burst**, opt-in | Fixes the audio slowdown observed in earlier hardware testing |

**Turnaround remains the default** and should let many physical games boot
without issue. Fast Burst runs faster than a real GBA
bus and is not qualified across other cartridges. Fully power off the Pocket
between flash-cart runs; a core reset can leave the cart's mapping unchanged.

## Install and use

Download **`kroy.GBA_0.9999.20260915.zip`** and merge its `Assets`, `Cores` and
`Platforms` into the SD root, preserving existing files. Supply a 16,384-byte
`Assets/gba/common/gba_bios.bin`. Pocket firmware 1.2 or newer is required.
Power cycle after installation before checking the displayed version.

For SD ROMs, put `Game.gba.cht` beside the ROM. For cartridge play, choose
**Play Cartridge**, then browse to the matching file through **Cheats**.
Enable the desired codes in the file and turn on **Cheats Enabled** in the
menu. **Cheat Overlay** displays names from `.cht`; `.chtbin` remains
supported without names. Both switches start off. Loading cheats does not
reset the game or enable them. Limits remain 32 entries and 16 ROM patches.

## Limits

- **Omega DE new saves do not persist**, for either tested EEPROM or SRAM
  save type. Existing saves load.
- Cartridge mode routes saves to the cartridge, with no Pocket SD save
  import/export. A flash cart manages its own save storage. Back up saves
  before using cheats.
- Cartridge RTC operation and the EverDrive battery-warning fix are verified.
  Save writes are confirmed on EverDrive, Minish Cap, Metroid: Zero Mission
  and other tested cartridges.
- Interrupted transfers and empty-slot handling still need hardware qualification. Savestates, sleep, link cable,
  solar, gyro, encrypted cheat decryption and 64 MB video carts are unsupported.
- The text loader has four known database mismatches, unchanged from the
  previous release: Final Fantasy VI Advance (Code Breaker), Mother 3,
  Pokemon FireRed Rev 1, and Yu-Gi-Oh! Ultimate Masters. Decoded entries
  in these files differ from the desktop decoder when all cheats are enabled.
  See the [cheat guide](https://github.com/kroy-the-rabbit/openfpga-GBA-cheats/blob/main/docs/CHEATS.md).

## Tested build and credits

The package preserves the installed **`cfbfa81`, seed 1** bitstream:
`1c11b22d840fd5dee28d0c71b95575f4096224b9fbe8ff0461c7517f3fcd7685`.
Quartus Lite 25.1std build 1129, 15,996 ALMs (87 %), 278 RAM blocks,
+0.075 ns setup and +0.101 ns hold. Every timing category passes.
`BUILD.json`, `report.txt` and `SHA256SUMS` accompany the package.

Based on [mincer-ray's Pocket GBA core](https://github.com/mincer-ray/openfpga-GBA)
and [GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer), with the cartridge
controller from [Wokann/openfpga-GBA](https://github.com/Wokann/openfpga-GBA)
and APF declaration reference from [Rai/openfpga-GBA](https://github.com/Rai/openfpga-GBA).
See the [cartridge guide](https://github.com/kroy-the-rabbit/openfpga-GBA-cheats/blob/main/docs/CARTRIDGE.md).

## Verify the downloads

Artifacts are signed with Kroy's normal key,
`7268DF1E6F75DA7731A46B65888C35858FEACF72`. The release includes its public
key and detached signatures for the ZIPs, provenance and timing report.

```sh
gpg --import RELEASE-KEY.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```
