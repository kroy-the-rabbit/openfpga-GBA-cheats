# Game Boy Advance for Analogue Pocket, with cheats

A Pocket core for the Game Boy Advance that can apply cheat codes to a running
game.

**Based on [mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA)
by mincer-ray**, which is a Pocket port of
[GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer). Everything that ships
here is theirs apart from the cheat engine.

The Pocket port dropped MiSTer's `gba_cheats.vhd`. This puts it back, along with
the debug-bus arbitration and the CPU pause it needs, a data slot to load codes
through and a menu switch. That is six files touched in `src/`, three of them
new, plus a data slot and two menu entries in `pkg/`:

| | |
|---|---|
| `core/cheat_binloader.sv` | **new**, reads the `.chtbin` into the cheat table |
| `core/cheat_loader.sv` | **new**, the loader around it |
| `gba/gba_cheats.vhd` | **new** here, MiSTer's engine that the Pocket port dropped |
| `core/core_top.sv` | the data slot, the debug-bus branch, the menu switch |
| `gba/gba_top.vhd` | the engine ports and the CPU run condition |
| `build/ap_core.qsf` | two lines, so the new files are compiled |

See [docs/CHEATS.md](docs/CHEATS.md).

> **Cheats can corrupt save files.** A cheat is a write into the memory of a
> running game, made once a frame, and a game builds its save data out of that
> same memory. A code aimed at an address that means something else in your copy
> overwrites whatever is there, and the damage is written into your save at the
> next save point. Back up anything you care about first.

## What works

Confirmed on a real Pocket with v0.6.4: the core boots, a `.chtbin` beside the
ROM loads, a code visibly takes effect in game, and **Cheats Enabled** turns the
effect off and back on live.

| | |
|---|---|
| Cheats, CodeBreaker and GameShark v1/v2, from libretro `.cht` files | **works on hardware** |
| **Cheats Enabled** switch, live | **works on hardware** |
| Everything upstream's core does | **works**, unchanged. Nothing was cut to make room |
| Save states and sleep | **works**, upstream's |
| Real-time clock | **works**, upstream's |
| Fast forward, on Y | **works**, upstream's |
| Button turbo, on X | **works**, upstream's |
| Display filters | **works**, upstream's |
| Link cable | **partial**, upstream's: two-player multiplayer only |
| A stray `.cht` loading zero rather than garbage | correct in simulation, **unconfirmed on hardware** |
| Closing the lid with the engine running | **unconfirmed on hardware** |
| Encrypted codes: GameShark v3, Action Replay v3, CodeBreaker after a `9` line | refused, and cannot be made to work |
| Cartridges | **Bring-up.** Minish Cap loads an existing physical save and plays with cheats on hardware. Write persistence and the new automatic launch path still need hardware qualification. [docs/CARTRIDGE.md](docs/CARTRIDGE.md) |
| 64 MB video carts | do not work |

[docs/HARDWARE.md](docs/HARDWARE.md) is the checklist and says exactly which
steps have been walked and which have not.

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
by CI rather than committed, so a core installed from a source archive is listed
by the Pocket and cannot start.

This core installs as `Cores/kroy.GBA` and shows as "Game Boy Advance (cheats)".
It does not replace an upstream `mincer_ray.GBA` install, it sits beside it. APF
names a core folder after the author in its `core.json`, and this one says
`kroy` because it is not mincer_ray's build. Delete the old folder if you do not
want both listed, and its `/Settings/mincer_ray.GBA` folder with it. Saves are
keyed by platform rather than by core, so they carry over untouched; save states
and settings do not.

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
browser to use the inserted cartridge. Cartridge saves default to Read Only;
physical writes require the explicit test setting. This automatic launch path
is installed in `417a55f` and awaiting hardware qualification. [docs/CARTRIDGE.md](docs/CARTRIDGE.md) covers
the current hardware results and diagnostic readouts.

Declaring the cartridge adapter raises the firmware this core needs: it will not
load on a Pocket below **firmware 1.2**.

**This is the one core in the set where the file you pick from is not the file
the handheld reads.** The core reads `<rom filename>.gba.chtbin`, not a `.cht`.

That is not a preference. The cheat engine went into a design already at 90 %
logic utilisation, and an ASCII parser on the FPGA measured 441 ALMs but grew
the design by 1,285 and cost 0.54 ns of setup timing, which is the difference
between a core that runs and one that does not exist. So the parse happens on a
desktop, where it can also be cross-checked against the whole libretro Game Boy
Advance directory rather than inferred from a handheld with no console. That
cross-check is opt-in and needs the corpus mounted, `make test CHT_DB=/path/to/cht`;
a plain `make test` skips it and still exits zero, so a green run on its own is
not evidence the corpus passed.

Two ways to produce the file:

* the [desktop app](#the-desktop-app), which lists the games on your card,
  matches each against the cheat database and writes both files for you;
* `tools/cheats/cht2bin.py YourGame.gba.cht`, which writes
  `YourGame.gba.chtbin` beside it.

A plain `.cht` copied to the card loads **zero** cheats rather than misbehaving.
The `.chtbin` header carries a magic number precisely so the old format cannot
be mistaken for the new one and shifted into the cheat table as garbage. That is
correct in simulation and is one of the two things still unconfirmed on
hardware.

**Cheats Enabled** in the core menu turns the whole lot on and off, and is
the only cheat control. The `CL:` and `CD:` readouts that counted bytes,
entries and rejects were removed on 2026-09-09 to give the fitter room;
[docs/CHEATS.md](docs/CHEATS.md) says what they showed and how to check a
file without them.

Encrypted codes, meaning GameShark v3, Action Replay v3 and CodeBreaker codes
after a `9` line, are enciphered with a per-game seed and cannot work. The
converter rejects them by plausibility rather than guessing: a real code's
address lands in the machine's RAM and an enciphered word almost never does. A
few real codes will be refused this way and a few enciphered ones will slip
through as pokes at nothing.

### Fast forward

**Fast Forward Render** in the menu chooses between the two ways of doing it.
*Fastest* runs the core as fast as it will go and can show torn or mixed frames
in some games. *Stable* waits for whole frames, which looks far better and is
slower. Speed varies by game either way: a game that leans on the GBA's slower
external RAM will not fast-forward as quickly as one that stays in internal RAM,
which is most obvious on the Classic NES Series titles.

### RTC and save compatibility

When a game uses RTC, the core appends RTC data to the end of the save file.
That makes the save larger than a standard GBA save, so loading it on a GBA core
without RTC support fails on the size check. To move such a save to a non-RTC
core, the extra bytes have to come off the end.

mincer_ray's [self-help tool](https://www.peterdegenaro.com/pages/rtc-save-tool.html)
does this. [mGBA](https://mgba.io/) v0.10.3 or later can also export saves with
RTC data stripped, under Tools, Save Converter, and
[save-file-converter](https://github.com/euan-forrester/save-file-converter)
converts between many retro save formats. Neither has been tested here.

### Force Quirk

Manually enables RTC for a ROM that is not in the database, for ROM hacks that
add RTC support to a game that does not normally use it. At the time of writing
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
* Two items on [docs/HARDWARE.md](docs/HARDWARE.md) are still unwalked: the
  stray `.cht`, and closing the lid with the engine in the CPU run condition.

## Documentation

| | |
|---|---|
| [docs/CHEATS.md](docs/CHEATS.md) | using cheats: the converter, the file, the menu readout |
| [docs/CHEATBIN.md](docs/CHEATBIN.md) | the `.chtbin` format contract |
| [docs/CARTRIDGE.md](docs/CARTRIDGE.md) | using a cartridge: the menu setting, the probe, the readout |
| [docs/HARDWARE.md](docs/HARDWARE.md) | validating a build on a real Pocket, and what is still unwalked |
| [docs/PLAN.md](docs/PLAN.md) | design and phasing, including where the cartridge work stands |
| [docs/HANDOFF.md](docs/HANDOFF.md) | the fit history, and why the parser had to leave the FPGA |
| [docs/BASELINE.md](docs/BASELINE.md) | measured area and timing, build by build |
| [docs/BUILD-RUNNER.md](docs/BUILD-RUNNER.md) | standing up a dedicated build runner, if a workstation is not the place for a 40-minute fit |

## Building from source

Quartus Prime Lite runs in a container and nothing is installed on the host.
The container is one you build yourself from Intel's installers, see the
licence section below; the harness expects it as `localhost/pocket-quartus:25.1std`
and `IMAGE=` points it anywhere else:

```sh
make gba      # -> build/gba/{bitstream.rbf_r, sd/, kroy.GBA_<version>.zip, report.txt}
make test     # the simulation suite
```

**Measure before moving the toolchain.** Upstream tuned the constraints, the
fitter seed and the custom STA reports against 21.1, and this design closes
setup by about 0.09 ns on one placement seed in three. That held across the
move to 25.1std: seed 3 closes at +0.092 ns where 21.1 gave +0.087, and the
other seeds miss on both. `docs/BASELINE.md` has every number; a version
change without a row in that table is a guess.

The build fails if the design misses timing. Quartus exits 0 on negative slack,
so `tools/podman/report.sh` checks worst-case slack itself and stops the build,
because a bitstream with negative slack may work on one bench and fail on
somebody's handheld. Releases are built with the same script on a controlled
builder, `SEED=3`, and the timing report ships beside the zip.

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
| [mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA) | the Pocket port this forks. Everything that ships here is theirs apart from the cheat wiring |
| [budude2/openfpga-GBC](https://github.com/budude2/openfpga-GBC) | reference for MiSTer to Pocket porting patterns |
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
