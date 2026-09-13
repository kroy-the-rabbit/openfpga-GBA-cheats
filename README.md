# Game Boy Advance for Analogue Pocket, with cheats

A Pocket core for the Game Boy Advance that can apply cheat codes to a running
game.

**Based on [mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA)
by mincer-ray**, which is a Pocket port of
[GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer). The GBA machine and
Pocket framework come from those projects.

The fork restores MiSTer's cheat engine and adds direct `.cht` loading,
named cheat overlays, read-side ROM patches and physical cartridge support.
The cartridge controller comes from [Wokann/openfpga-GBA](https://github.com/Wokann/openfpga-GBA),
with Pocket launch plumbing informed by [Rai/openfpga-GBA](https://github.com/Rai/openfpga-GBA).
See [docs/CHEATS.md](docs/CHEATS.md) and [docs/CARTRIDGE.md](docs/CARTRIDGE.md).

> **Cheats can corrupt save files.** A cheat is a write into the memory of a
> running game, made once a frame, and a game builds its save data out of that
> same memory. A code aimed at an address that means something else in your copy
> overwrites whatever is there, and the damage is written into your save at the
> next save point. Back up anything you care about first.

> **No link cable.** Upstream's partial 2p multiplayer is stripped to buy the
> ALMs cartridge support needs. The SIO registers still read and write, so a
> game looking for a cable finds none.

## What works

Release [`v0.9999.f2a86db`](../../releases/tag/v0.9999.f2a86db) uses the
hardware-tested build installed on 2026-09-10. These features are on `main`.
The older `v0.9999` predates cartridge support and reads only `.chtbin` cheats.

| Feature | Status |
|---|---|
| Cheats from `.cht` or `.chtbin`, with a live global switch | Confirmed on hardware; off at launch |
| Overlay showing cheat names | Confirmed; `.cht` supplies names, `.chtbin` shows `CHEAT nn` |
| Sixteen read-side ROM-patch slots | Confirmed on a Zero Mission cartridge, including two midair cheats together |
| Physical cartridge gameplay and existing saves | Minish Cap and Zero Mission confirmed |
| Physical save persistence | A new Zero Mission save was read back by Analogue's own cartridge mode |
| Fast Burst cartridge timing | Clean audio on the tested Zero Mission cartridge; opt-in |
| SD-ROM RTC, fast forward, button turbo and display filters | Retained from upstream |
| Savestates, sleep and link cable | Removed |
| Cartridge RTC/GPIO, solar and gyro | Not connected |
| Physical SRAM/Flash save writes, interrupted-transfer guard, empty-slot handling | Not hardware-qualified |
| Encrypted cheat codes | No decryption; supply supported raw codes |
| 64 MB video carts | Unsupported |

[docs/HARDWARE.md](docs/HARDWARE.md) separates recorded hardware results
from the checks still needed.

## Versions

Every project in this set sits at **0.9999** and none of them moves off it.
1.0 is a claim to be finished, none of this is finished, and a version that
never climbs cannot drift into making that claim by accident.

The projects are not kept in step with each other. A release adds the short
SHA of the commit it was cut from, so a tag reads `v0.9999.<sha>`, and two
tags that share the prefix are unrelated releases. This core's `v0.9999`
predates the suffix. Read the tail, not the number.

Provenance is stated in words, above and in the credits, rather than implied by
a number.

## Installation

Prebuilt cores are on the [Releases](../../releases) page. Download
`kroy.GBA_<version>.zip`, not the "Source code" archives: the bitstream is built
on controlled runners rather than committed, so a core installed from a
source archive is listed by the Pocket and cannot start.

This core installs as `Cores/kroy.GBA` and shows as "Game Boy Advance (cheats)".
It does not replace an upstream `mincer_ray.GBA` install, it sits beside it. APF
names a core folder after the author in its `core.json`, and this one says
`kroy` because it is not mincer_ray's build. Delete the old folder if you do not
want both listed, and its `/Settings/mincer_ray.GBA` folder with it. Saves are
keyed by platform rather than by core, so they carry over untouched; settings
do not.

Copy the `Assets`, `Cores` and `Platforms` folders to the root of the SD card.
Finder on macOS *replaces* folders rather than merging them the way Windows
does, which will delete the ROMs already in `Assets`, so copy the folders inside
those three rather than dragging the three themselves.

### Boot ROM

The core will not start a game without one. It is copyrighted console code, it
is not in the zip, and nothing here will fetch it. Dump it from your own
hardware or supply your own copy.

| File | Goes in | Size |
|---|---|---|
| `gba_bios.bin` | `/Assets/gba/common/` | 16384 bytes |

## Usage

ROMs go in `/Assets/gba/common/`. Choose **Play Cartridge** in the asset
browser to boot the inserted cartridge. Cartridge saves read and write the
physical chip directly; no SD `.sav` is imported or exported in this mode.
See [docs/CARTRIDGE.md](docs/CARTRIDGE.md) for tested cartridges and limits.
Pocket firmware **1.2 or newer** is required.

For named cheats, put `Game.gba.cht` beside `Game.gba` and set the desired
`cheatN_enable` keys to `true`. The core also accepts `Game.gba.chtbin`,
which carries packed codes without titles. If both are present, select the
`.cht` through the **Cheats** slot to use its names. In Play Cartridge mode,
browse to the cheat file once; ROM-derived filenames do not autoload there.

**Cheats Enabled** and **Cheat Overlay** start off and are not persisted.
Loading a cheat file does not reset the game or turn cheats on. Enable the
global switch to apply the file's selected cheats, and enable the overlay
to see the loaded names and counts. `CL:` and `CD:` are no longer menu items.

The [desktop app](#the-desktop-app) writes cheat files for you. Conversion
to `.chtbin` is optional; [docs/CHEATS.md](docs/CHEATS.md) covers raw code
formats, the 32-entry limit and the separate sixteen-slot ROM-patch limit.
Encrypted codes need decoding before use; neither loader decrypts them.

For cartridge audio, **ROM Timing** defaults to **Turnaround**. **Fast Burst**
fixes slowdown on the tested Zero Mission cartridge but runs the bus faster
than a real GBA and remains opt-in.

### Fast forward

**Fast Forward Render** in the menu chooses between the two ways of doing it.
*Fastest* runs the core as fast as it will go and can show torn or mixed frames
in some games. *Stable* waits for whole frames, which looks far better and is
slower. Speed varies by game either way: a game that leans on the GBA's slower
external RAM will not fast-forward as quickly as one that stays in internal RAM,
which is most obvious on the Classic NES Series titles.

### RTC and save compatibility

For SD ROMs, when a game uses RTC, the core appends RTC data to the end of
the save file.
That makes the save larger than a standard GBA save, so loading it on a GBA core
without RTC support fails on the size check. To move such a save to a non-RTC
core, the extra bytes have to come off the end.

mincer_ray's [self-help tool](https://www.peterdegenaro.com/pages/rtc-save-tool.html)
does this. [mGBA](https://mgba.io/) v0.10.3 or later can also export saves with
RTC data stripped, under Tools, Save Converter, and
[save-file-converter](https://github.com/euan-forrester/save-file-converter)
converts between many retro save formats. Neither has been tested here.

### Force Quirk

For SD ROMs only, manually enables RTC for a ROM that is not in the database,
for ROM hacks that add RTC support to a game that does not normally use it.
At the time of writing
one hack needs it. Enable it on the first load of the hack, as early in the BIOS
display as possible, or the save initialises wrong.

> **The setting persists across games.** Turn it off before loading anything
> that does not need it, and do not enable it on a game that does not use RTC:
> it causes crashes and glitches.

### Accuracy

Upstream's core more or less matches the current accuracy of the MiSTer GBA
master branch and scores similarly on the mGBA test suite. What was cut to fit
the smaller FPGA was convenience features rather than accuracy logic. The cheat
engine added here does not touch any of that. A game that works on MiSTer and
not here is worth an issue.

## The desktop app

[pocket-tools](https://github.com/kroy-the-rabbit/pocket-tools) is the desktop
side of this set. It reads your Pocket SD card, lists the games on it, matches
each against the libretro cheat database and writes both the `.cht` and the
`.chtbin` beside the ROM. It will also install and update this core for you.

You do not need it. `tools/cheats/cht2bin.py` in this repository does the
conversion on its own. The app exists because picking cheats out of a few
hundred database files by hand is tedious.

## Known issues

* Fast forward shows screen tearing. Fixing it needs a frame buffer.
* 64 MB video carts do not work.
* Cartridge RTC/GPIO is disconnected. Flash save writes, the interrupted-transfer
  guard and empty-slot handling still need hardware qualification.
* Savestates, sleep and link cable are unavailable.
* Fast Burst has been tested on one cartridge; Turnaround remains the default.

## Documentation

| | |
|---|---|
| [docs/CHEATS.md](docs/CHEATS.md) | cheat files, supported codes, overlay and cartridge loading |
| [docs/CHEATBIN.md](docs/CHEATBIN.md) | the `.chtbin` format contract |
| [docs/CARTRIDGE.md](docs/CARTRIDGE.md) | Play Cartridge, physical saves, timing and limits |
| [docs/HARDWARE.md](docs/HARDWARE.md) | validating a build on a real Pocket, and what is still unwalked |
| [docs/PLAN.md](docs/PLAN.md) | design and phasing, including where the cartridge work stands |
| [docs/HANDOFF.md](docs/HANDOFF.md) | current release and historical bring-up notes |
| [docs/BASELINE.md](docs/BASELINE.md) | measured area and timing, build by build |
| [docs/BUILD-RUNNER.md](docs/BUILD-RUNNER.md) | controlled builds through the shared runner interface |

## Building from source

Quartus Prime Lite **25.1std build 1129** runs on controlled build runners
through the shared `tools/runner-build` interface. See
[docs/BUILD-RUNNER.md](docs/BUILD-RUNNER.md). Routine fits run there;
GitHub Actions runs simulations and verifies published packages.

```sh
make sim-image   # Icarus Verilog, GHDL and Python, no Quartus
make test        # complete simulation suite
```

Optional cheat-corpus checks need `CHT_DB=/path/to/cht`. Without it, both
corpus passes report a skip; the fixture and integration suites still run.

The tested `f2a86db` seed-3 build uses 16,080 of 18,480 ALMs (87 %) and
278 RAM blocks. Worst setup is +0.092 ns and hold +0.121 ns; all timing
categories pass. [docs/BASELINE.md](docs/BASELINE.md) carries the fit evidence.
`tools/podman/report.sh` rejects negative slack even when Quartus exits zero.

Releases use a signed `v0.9999.<built-commit>` tag on `main`, the tested
package, `report.txt` and `SHA256SUMS`. CI verifies them and never synthesises
or replaces the bitstream. A later documentation commit does not change the
source commit recorded for the tested package.

## Where to report a problem

Cheat engine bugs belong here. Bugs in the core itself are most likely the
Pocket port's rather than MiSTer's, so they belong
[upstream](https://github.com/mincer-ray/openfpga-GBA/issues) and will be
forwarded from here as necessary.

## Credits

This core is other people's work with a cheat engine put back into it.

| | |
|---|---|
| [GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer) | the original FPGA GBA, and `gba_cheats.vhd`, which is the cheat engine this fork restores |
| [mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA) | the Pocket port this forks, including the GBA machine integration and framework |
| [budude2/openfpga-GBC](https://github.com/budude2/openfpga-GBC) | reference for MiSTer to Pocket porting patterns |
| [Wokann/openfpga-GBA](https://github.com/Wokann/openfpga-GBA) | cartridge controller and original controller tests |
| [Rai/openfpga-GBA](https://github.com/Rai/openfpga-GBA) | reference for the APF Play Cartridge declaration |
| [agg23](https://github.com/agg23) | analogue-pocket-utils, and reference SNES and NES Pocket cores |
| [libretro/libretro-database](https://github.com/libretro/libretro-database) | the cheat files themselves, CC-BY-SA-4.0, none of them shipped here |
| [Analogue openFPGA](https://www.analogue.co/developer) | the Pocket framework and core template |

## License

The GBA core is **GPL-2.0**. That is what `pkg/Cores/kroy.GBA/info.txt` says and
what [GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer) ships under. The
MiSTer sources carry no per-file notices and no "or any later version" grant, so
version 2 is the version.

The cheat engine added here is under the same terms. The files this fork wrote
into `src/` say `GPL-2.0-or-later` in SPDX headers: *or later* because that is
this fork's grant to give, version 2 because anything narrower could not be
combined with the core it links into.

`src/fpga/apf/` is not GPL. Those files are Analogue's Pocket Framework,
supplied under Analogue's own software licence agreement and the Pocket EULA
linked from their headers, which provide that where the MIT or GNU licences must
apply, those prevail.

The host tooling under `tools/` is `GPL-3.0-or-later`. It is not part of the
bitstream and does not link with any of the above: it is separate programs that
run on a desktop and write files.

Neither this repository nor upstream carries a LICENSE file, so the per-file
notices and that `info.txt` are the licence. Binary releases here are built from
the exact tagged commit of this repository on a controlled builder, and the tag
is the corresponding source for them; the release carries the zip, its SHA-256
and the timing report.

The builder runs Quartus Prime Lite from an image assembled from Intel's own
installers. Quartus Lite needs no licence file, but that grants no right to
redistribute its installed files, so that image is private: it is never
published to a registry, never attached to a CI run, and this repository's
workflows do not pull anyone else's copy either. Anyone building this core
themselves installs Quartus from Intel and points `IMAGE` at their own.
