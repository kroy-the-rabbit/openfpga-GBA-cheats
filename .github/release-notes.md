Physical GBA cartridges now boot with cheats, named overlays and read-side
ROM patches. Minish Cap and Zero Mission gameplay and existing saves are
confirmed on hardware. A new Zero Mission save was read back through
Analogue's own cartridge mode.

The tested source is `f2a86db`, seed 3. The package includes direct `.cht`
loading, the overlay title fix and sixteen ROM-patch slots. Both six-patch
Zero Mission midair cheats work together. `.chtbin` remains supported, with
`CHEAT nn` in place of names.

**Download `kroy.GBA_<version>.zip`**, not the source archives. Merge its
`Assets`, `Cores` and `Platforms` into the SD root, preserving existing files.
On macOS, copy the contents into existing folders rather than replacing them.
Pocket firmware **1.2 or newer** and a separately supplied 16,384-byte
`Assets/gba/common/gba_bios.bin` are required. Power cycle after installation
before checking the displayed core version.

## Using cheats and cartridges

- For SD ROMs, place `Game.gba.cht` beside `Game.gba`. Enable the desired
  `cheatN_enable` entries in the file.
- In **Play Cartridge** mode, browse to the file through **Cheats** once.
  Choose `.cht` explicitly when both text and binary files are present.
- **Cheats Enabled** and **Cheat Overlay** start off and are not persisted.
  Loading a file does not reset gameplay or turn cheats on.
- Cartridge saves access the physical chip directly. There is no Read Only
  toggle and no SD save import/export in this mode. Back up saves before
  experimenting with cheats; game-memory writes can be saved by the game.
- **ROM Timing** defaults to **Turnaround**. **Fast Burst** fixes audio
  slowdown on the tested Zero Mission cartridge and remains opt-in.

## Limits

Savestates, sleep and link cable were removed. RTC remains available for SD
ROMs; cartridge RTC/GPIO, solar and gyro are disconnected. Physical SRAM/Flash
save writes, interrupted-transfer protection and empty-slot handling still
need hardware qualification. Fast Burst has been tried on one cartridge.
Encrypted codes are not decrypted. The load limit is 32 entries, with a
separate sixteen-slot limit for ROM patches. 64 MB video carts are unsupported.

## Verification and sources

The seed-3 fit uses 16,080 / 18,480 ALMs (87 %) and 278 RAM blocks. Every
timing category passes, with +0.092 ns setup and +0.121 ns hold. The tested
bitstream SHA-256 is
`489904ea59dea4e1408c770cbe8e853a67741f5817d1884d59e57e77b7d3f31b`.
The release carries the ZIP, `report.txt` and `SHA256SUMS`:

```sh
sha256sum -c SHA256SUMS
```

This is [mincer-ray's Pocket GBA core](https://github.com/mincer-ray/openfpga-GBA),
derived from [GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer), with
cheat and cartridge integration. The controller comes from
[Wokann/openfpga-GBA](https://github.com/Wokann/openfpga-GBA), with APF
declaration reference from [Rai/openfpga-GBA](https://github.com/Rai/openfpga-GBA).
It installs alongside `mincer_ray.GBA` as `kroy.GBA`; SD saves are shared by
platform, while settings are separate. The
[desktop picker](https://github.com/kroy-the-rabbit/pocket-tools) writes cheat
files and installs cores. [Cheat documentation](https://github.com/kroy-the-rabbit/openfpga-GBA-cheats/blob/main/docs/CHEATS.md)
covers supported raw codes and loading.
