# GBA for Analogue Pocket

This repository is
[mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA) with a
**cheat engine** added. The Pocket port dropped MiSTer's `gba_cheats.vhd`; this
restores it, along with the debug-bus arbitration and the CPU pause it needs,
a data slot to load codes through, and a menu switch. See
[docs/CHEATS.md](docs/CHEATS.md).

The core installs as `Cores/kroy.GBA` and shows as "Game Boy Advance (cheats)",
so it sits **beside** an upstream `mincer_ray.GBA` install rather than replacing
it.

> **Cheats can corrupt save files.** A cheat is not a setting, it is a write
> into the memory of a running game once a frame, and a game builds its save
> data out of that same memory. A code aimed at an address that means something
> else in your copy overwrites whatever is there, and the damage is written into
> your save at the next save point. Back up anything you care about first.

**Cheats are converted on your computer.** The core reads
`<rom filename>.gba.chtbin`, not a `.cht`, and that is not a preference: an
ASCII parser on the FPGA measured 441 ALMs but grew the design by 1,285 and cost
0.54 ns of setup timing at 97 % utilisation, which is the difference between a
core that runs and one that does not exist. A plain `.cht` on the card loads
**zero** cheats rather than misbehaving. Use the
[desktop picker](https://github.com/kroy-the-rabbit/openfpga-GBC-cheats-ui) or
`tools/cheats/cht2bin.py`.

Everything outside `src/` and `pkg/` is new here and none of it ships: a
containerised Quartus build, a simulation harness, the converter, and the docs
below. Builds here also differ from upstream's in one way that is not the
cheats - the fitter runs STANDARD FIT rather than AUTO - because at this
occupancy AUTO measures placement luck rather than the design;
[docs/HANDOFF.md](docs/HANDOFF.md) has the fifteen builds that establish it.

**Not yet validated on hardware.** Simulation and the fit report are green;
nothing here has run on a Pocket. [docs/HARDWARE.md](docs/HARDWARE.md) is the
checklist that closes that.

| Document | |
|---|---|
| [docs/CHEATS.md](docs/CHEATS.md) | using cheats: the converter, the file, the menu readout |
| [docs/CHEATBIN.md](docs/CHEATBIN.md) | the `.chtbin` format contract |
| [docs/HARDWARE.md](docs/HARDWARE.md) | validating a build on a real Pocket |
| [docs/PLAN.md](docs/PLAN.md) | design and phasing, including the unstarted cartridge work |
| [docs/HANDOFF.md](docs/HANDOFF.md) | the fit history, and why the on-FPGA parser had to go |
| [docs/BASELINE.md](docs/BASELINE.md) | measured area and timing, build by build |

---

Everything from here down is upstream's README: their badges, their credits and
their own description of their work. The badges report
`mincer-ray/openfpga-GBA`, not this fork. Where this fork differs from what
they wrote, the difference is a marked note like this one and nothing else has
been altered.

[![Latest Release](https://img.shields.io/github/v/tag/mincer-ray/openfpga-GBA?label=latest)](https://github.com/mincer-ray/openfpga-GBA/releases/latest) [![Downloads](https://img.shields.io/github/downloads/mincer-ray/openfpga-GBA/total)](https://github.com/mincer-ray/openfpga-GBA/releases) [![Platform](https://img.shields.io/badge/platform-Analogue%20Pocket-blue)](https://openfpga-library.github.io/analogue-pocket/)

LLM assisted port of [MiSTer GBA core](https://github.com/MiSTer-devel/GBA_MiSTer)

## Features

- **Filters**
- **Save States**
- **Fast Forward (Bound to Y button)**
- **Button Turbo (Bound to X button)**
- **RTC**
- **Link Cable (Partial)** - 2p Multiplayer

##  Currently Not Included

- **Link Cable** - normal serial modes/accessories, 3p/4p Multiplayer, GCN link, GBA wireless, Single Pak download

## Fast Forward

You can change fast forward behavior with the "Fast Forward Render" setting in the menu. Choices are:

- Fastest: core runs as fast as possible, highest possible fast forward speed but can show tearing/mixed/corrupted frames in some games.
- Stable: wait for full frames. video during fast forward is MUCH more stable, however max fast forward speed is decreased.

## RTC and Save Compatibility

When a game uses RTC (either detected automatically or forced on), the core appends RTC data to the end of the save file. This makes the save file larger than a standard GBA save. If you then try to load that save on a GBA core that doesn't support RTC, it will fail with an error because the save file size doesn't match what the core expects. To use the save on a non-RTC core, you would need to trim the extra RTC bytes from the end of the file to restore it to its original size.

>For saves you might be having issues with try the new online self help tool I have added here:
>
>https://www.peterdegenaro.com/pages/rtc-save-tool.html

The following tools might be able to help you but I have not tested them:
- [mGBA](https://mgba.io/) — The built-in Save Converter tool (Tools → Save Converter) can export saves with RTC data stripped. Requires mGBA v0.10.3 or later.
- [save-file-converter](https://github.com/euan-forrester/save-file-converter) — A web-based tool that can convert and resize save files across many retro formats.

## **FORCE QUIRK**
At the moment there only seems to be 1 romhack that needs this feature. If you are trying to play Unbound keep reading, otherwise PLEASE ignore this feature.

— Manually enables RTC for ROMs that aren't in the database. This is useful for ROM hacks that add RTC support to games that don't normally use it. Make sure to enable this on first load of the hack, ideally as soon as possible during the bios display to avoid any issues with initializing the save. **USE WITH CAUTION:** enabling this on a game that doesn't actually use RTC can cause crashes or glitches.
### **⚠️WARNING: Forced RTC setting persists across games! Remember to turn it off before loading a game that doesn't need it⚠️**
### **⚠️WARNING: Do not enable this setting unless you are playing a romhack that needs it⚠️**

## Accuracy

This core more or less replicates the current accuracy of the MiSTer GBA core master branch. The features that were cut to fit the smaller FPGA were convenience features, not accuracy-related logic. It scores similarly to the MiSTer core in the mGBA test suite. If you encounter a game that works on MiSTer but not here, please open an issue.

Note: MiSTer core has an accuracy branch! A few of those changes have made it into this port but due to it not supporting fast forward (never coming due to technical limitations) or link port (probably coming) I've kinda stalled on that branch for the time being. I'm considering maybe splitting into 2 cores, but probably we just need to wait for the MiSTer devs to finish before really committing to that plan. The regular MiSTer core works well enough for now.

## Installation

> This fork is on the [Releases](../../releases) page. Download
> `kroy.GBA_<version>.zip`, **not** the "Source code" archives: the bitstream is
> built by CI rather than committed, so a core installed from one is listed by
> the Pocket and cannot start. Upstream's own instructions follow and are
> otherwise unchanged.

The core should be available on pocket manager apps, or you can install manually:

1. Download the latest release
2. Copy the 3 folders `Cores/`, `Platforms/`, `Assets/`  to your SD card
   - **macOS users:** Note: macOS Finder replaces folders instead of merging them so do it all manually and be careful.
3. Place your ROMs and `gba_bios.bin` in `/Assets/gba/common/`

## Known Issues

- **Fast forward speed varies by game** — Games that make heavy use of the GBA's slower external RAM will not fast-forward as quickly as games that primarily use internal RAM. This is most noticeable with the Classic NES Series titles.

- **Fast forward creates visible screen tearing** — Nothing i can do about this for the time being. Would need a frame buffer.

- **64MB Video carts do not work** you cant watch shrek, shrek 2, or shark tale =(

## Building from Source

Should be very easy

### Prerequisites

- Docker
- `raetro/quartus:21.1` Docker image

### Build

```bash
./scripts/build.sh
```

> This fork builds with `make gba`, which runs the same image under Podman,
> keeps the checked-in tree read-only, and **fails the build on negative
> slack** - Quartus exits 0 on a design that misses timing, so the gate lives
> in `tools/podman/report.sh`. It is the same script CI runs. `make test` is
> the simulation suite.

## Credits

- **[MiSTer GBA core](https://github.com/MiSTer-devel/GBA_MiSTer)** — original FPGA GBA implementation
- **[Analogue openFPGA](https://www.analogue.co/developer)** — platform framework and core template
- **[budude2/openfpga-GBC](https://github.com/budude2/openfpga-GBC)** — reference for MiSTer-to-Pocket porting patterns
- **[agg23](https://github.com/agg23)** — analogue-pocket-utils and reference SNES/NES Pocket cores
- **[mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA)** — the Pocket port this forks; everything in `src/` and `pkg/` is theirs apart from the cheat engine

## License

GPL-2.0 — see [GBA_MiSTer LICENSE](https://github.com/MiSTer-devel/GBA_MiSTer/blob/master/LICENSE) for details.

2c5aef5574b6a47c95bb8154197059d99acbd555a7b5b25365112b56b7a79a17
