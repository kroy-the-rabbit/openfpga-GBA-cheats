> **This build has never run on a Pocket.** The simulation suite and the fit
> report are green and the core builds and closes timing, but no cheat has been
> seen to take effect on real hardware, and neither has the core been seen to
> boot. Treat it as something to test rather than something to rely on, and back
> up your saves. `docs/HARDWARE.md` in the repository is the checklist.

**Download `kroy.GBA_<version>.zip` below**, not the "Source code" archives.
Those are the repository, and the bitstream is built by CI rather than
committed, so a core installed from one is listed by the Pocket but cannot
start: *error in framework, can't find bitstream*.

This is [mincer-ray's Game Boy Advance core](https://github.com/mincer-ray/openfpga-GBA)
with a cheat engine added. It installs as `Cores/kroy.GBA` and shows as
"Game Boy Advance (cheats)", so it sits **beside** an existing `mincer_ray.GBA`
install rather than replacing it. Settings and save states do not carry over
between the two; saves do, because those are per platform.

## Installing

Unzip and merge `Assets`, `Cores` and `Platforms` into the root of the SD card.

On macOS, Finder **replaces** a folder instead of merging it, which deletes the
ROMs and BIOS already in `Assets`. Copy the folders inside `Assets`, `Cores` and
`Platforms` rather than dragging the three top-level ones.

No BIOS is included and the core will not start without one:

| File | Goes in |
|---|---|
| `gba_bios.bin` | `/Assets/gba/common` |

## Cheats

Cheats are **converted on your computer**, not read from a `.cht` on the card.
The core reads `<rom filename>.gba.chtbin`. Either use the
[desktop picker](https://github.com/kroy-the-rabbit/openfpga-GBC-cheats-ui),
which knows this format and writes the file for you, or convert by hand:

```sh
tools/cheats/cht2bin.py YourGame.gba.cht     # -> YourGame.gba.chtbin
```

A plain `.cht` copied to the card loads **zero** cheats rather than
misbehaving; the header carries a magic number so the old format cannot be
mistaken for the new one. [docs/CHEATS.md](https://github.com/kroy-the-rabbit/openfpga-GBA-cheats/blob/main/docs/CHEATS.md)
explains why the parse is not on the handheld, and which code formats work.

**Cheats can corrupt saves.** A cheat is a write into the memory of a running
game, and games build their save data out of that same memory, so a code aimed
at the wrong address gets written into your save at the next save point. Back
up anything you care about.

## Checking a download

```sh
sha256sum -c SHA256SUMS --ignore-missing
```
