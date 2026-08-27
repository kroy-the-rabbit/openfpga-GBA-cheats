# Game Boy Advance for Analogue Pocket, with cheats

Ported from the original core developed at
https://github.com/MiSTer-devel/GBA_MiSTer

This repository is
[mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA) with
**cheat support added**. The Pocket port dropped MiSTer's `gba_cheats.vhd`;
this restores it, along with the debug-bus arbitration and the CPU pause it
needs, a data slot to load codes through, and a menu switch. Everything that
ships apart from that is upstream's: three files changed in `src/` and a data
slot plus two menu entries in `pkg/`. See [docs/CHEATS.md](docs/CHEATS.md).

> **Cheats can corrupt save files.** A cheat is not a setting, it is a write
> into the memory of a running game once a frame, and a game builds its save
> data out of that same memory. A code aimed at an address that means something
> else in your copy overwrites whatever is there, and the damage is written into
> your save at the next save point. Back up anything you care about first.

**Nothing here has run on a Pocket yet.** The simulation suite and the fit
report are green and the core builds, but no cheat has been seen to take effect
on real hardware. [docs/HARDWARE.md](docs/HARDWARE.md) is the checklist that
closes that, and until it does this is a build to test rather than a build to
rely on.

Everything outside `src/` and `pkg/` is new here and none of it ships: a
containerised Quartus build, a simulation harness, the cheat converter, and the
documents below.

| | |
|---|---|
| [docs/CHEATS.md](docs/CHEATS.md) | using cheats: the converter, the file, the menu readout |
| [docs/CHEATBIN.md](docs/CHEATBIN.md) | the `.chtbin` format contract |
| [docs/HARDWARE.md](docs/HARDWARE.md) | validating a build on a real Pocket |
| [docs/PLAN.md](docs/PLAN.md) | design and phasing, including the unstarted cartridge work |
| [docs/HANDOFF.md](docs/HANDOFF.md) | the fit history, and why the parser had to leave the FPGA |
| [docs/BASELINE.md](docs/BASELINE.md) | measured area and timing, build by build |

## Installation

Prebuilt cores are on the [Releases](../../releases) page. Download
`kroy.GBA_<version>.zip`, **not** the "Source code" archives: the bitstream is
built by CI rather than committed, so a core installed from one is listed by the
Pocket and cannot start.

This core installs as `Cores/kroy.GBA` and shows as "Game Boy Advance (cheats)".
It does not replace an upstream `mincer_ray.GBA` install, it sits beside it: APF
names a core folder after the author in its `core.json`, and this one says
`kroy` because it is not mincer_ray's build. Delete the old folder if you do not
want both listed, and its `/Settings/mincer_ray.GBA` folder with it. Saves are
keyed by platform rather than by core, so they carry over untouched; save states
and settings do not.

Copy the `Assets`, `Cores` and `Platforms` folders to the root of the SD card.
Finder on macOS *replaces* folders rather than merging them the way Windows
does, which will delete the ROMs already in `Assets`, so copy the folders inside
those three rather than dragging the three themselves.

Put your ROMs and the boot ROM in `/Assets/gba/common/`. The boot ROM must be
named `gba_bios.bin` and is 16384 bytes. It is not in the zip, it is copyrighted
console code, and the core will not start a game without it.

## Cheats

CodeBreaker and GameShark v1/v2 codes, from libretro `.cht` files, **converted
on your computer**. The core reads `<rom filename>.gba.chtbin`, not a `.cht`.

That is not a preference. The cheat engine went into a design already at 90 %
logic utilisation, and an ASCII parser on the FPGA measured 441 ALMs but grew
the design by 1,285 and cost 0.54 ns of setup timing, which is the difference
between a core that runs and one that does not exist. So the parse happens on a
desktop, where it is also tested against all 513 files in the libretro Game Boy
Advance directory rather than inferred from a handheld with no console.

Two ways to produce the file:

* the [desktop picker](https://github.com/kroy-the-rabbit/openfpga-GBC-cheats-ui),
  which lists the games on your card, matches each against the cheat database
  and writes the file for you;
* `tools/cheats/cht2bin.py YourGame.gba.cht`, which writes
  `YourGame.gba.chtbin` beside it.

A plain `.cht` copied to the card loads **zero** cheats rather than misbehaving.
The `.chtbin` header carries a magic number precisely so the old format cannot
be mistaken for the new one and shifted into the cheat table as garbage.

**Cheats Enabled** in the core menu turns the whole lot on and off. Encrypted
codes - GameShark v3, Action Replay v3, CodeBreaker after a `9` line - are
enciphered with a per-game seed and do not work; the converter rejects them by
plausibility rather than guessing. [docs/CHEATS.md](docs/CHEATS.md) has the
detail and explains the `CL:` and `CD:` readouts, which are the whole diagnostic
surface on a handheld with no console.

## Features

Everything upstream's core does, plus cheats. Nothing was cut to make room.

### Supported

* Cheats (CodeBreaker + GameShark, from libretro `.cht` files) - see [docs/CHEATS.md](docs/CHEATS.md)
* Save states and sleep
* Real-time clock
* Fast forward, on the Y button
* Button turbo, on the X button
* Display filters
* Link cable, partial: two-player multiplayer only

### Not included

* Link cable: normal serial modes and accessories, three and four player
  multiplayer, GameCube link, GBA wireless, single-pak download
* External cartridges. Nobody ships this on a GBA core yet;
  [docs/PLAN.md](docs/PLAN.md) §2 is the design study and it is unstarted.

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
RTC data stripped, under Tools → Save Converter, and
[save-file-converter](https://github.com/euan-forrester/save-file-converter)
converts between many retro save formats; neither has been tested here.

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
master branch, and scores similarly on the mGBA test suite; what was cut to fit
the smaller FPGA was convenience features rather than accuracy logic. The cheat
engine added here does not touch any of that. A game that works on MiSTer and
not here is worth an issue.

## Known issues

* Fast forward shows screen tearing. Fixing it needs a frame buffer.
* 64 MB video carts do not work.
* Everything under [docs/HARDWARE.md](docs/HARDWARE.md) is unverified, because
  no build from this repository has been flashed.

Bugs in the cheat engine belong here. Bugs in the core itself are most likely
the Pocket port's rather than MiSTer's, so they belong
[upstream](https://github.com/mincer-ray/openfpga-GBA/issues) and will be
forwarded from here as necessary.

## Building from source

Quartus Prime Lite 21.1, containerised, and nothing installed on the host:

```sh
make gba      # -> build/gba/{bitstream.rbf_r, sd/, kroy.GBA_<version>.zip, report.txt}
make test     # the simulation suite
```

**Do not bump Quartus.** Upstream tuned the constraints, the fitter seed and the
custom STA reports against 21.1, and this design closes setup by 0.090 ns, which
is not a margin to spend on a toolchain change.

The build fails if the design misses timing. Quartus exits 0 on negative slack,
so `tools/podman/report.sh` checks worst-case slack itself and stops the build,
because a bitstream with negative slack may work on one bench and fail on
somebody's handheld. It is the same script CI runs, and a CI build and a local
one land on the same numbers.

## Credits

* **[MiSTer GBA core](https://github.com/MiSTer-devel/GBA_MiSTer)** — the original FPGA GBA implementation, and `gba_cheats.vhd`, which is the cheat engine this fork puts back
* **[mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA)** — the Pocket port this forks. Everything that ships here is theirs apart from the cheat wiring
* **[Analogue openFPGA](https://www.analogue.co/developer)** — platform framework and core template
* **[budude2/openfpga-GBC](https://github.com/budude2/openfpga-GBC)** — reference for MiSTer-to-Pocket porting patterns
* **[agg23](https://github.com/agg23)** — analogue-pocket-utils and reference SNES/NES Pocket cores

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
notices and that `info.txt` are the licence. Binary releases here are built by CI
from a tagged commit of this repository, which is the corresponding source for
them.
