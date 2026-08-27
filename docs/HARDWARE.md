# Hardware validation

Everything in this fork is proven in simulation and in the fit report. **None of
it has ever run on a Pocket.** This is the checklist that closes that gap.

It is written to be worked through in order, on one SD card, in one sitting.
Each step names what to look at and what it means when the number is wrong, so
that a failure identifies itself instead of starting an investigation. The
Pocket has no console; `CL:` and `CD:` in the core menu are the entire
diagnostic surface, and `docs/CHEATS.md` documents what their bits mean.

## Before you start

```
make gba FITTER_EFFORT="STANDARD FIT"
```

About 23 minutes. `FITTER_EFFORT` is not optional: AUTO FIT throws placements
up to 0.9 ns worse on this design, and the closing result was measured at
STANDARD. The build fails loudly on negative slack rather than shipping a
bitstream that will not run.

It leaves `build/gba/kroy.GBA_<version>.zip`, which unzips over the root of the
Pocket's SD card. Confirm before copying:

```
grep -E 'ALM|RAM|setup' build/gba/report.txt
```

Expect roughly **17,544 ALMs (95 %), 282 RAM blocks, setup +0.090 ns**. If
setup is negative the build should not have got this far; if it is positive but
much smaller than 0.090, something changed and the fit history in
`docs/HANDOFF.md` is the place to start.

You also need a test `.chtbin`. Make one from a game you own, and **write down
what `cht2bin.py` printed** — the entry count is what step 3 checks against:

```
python3 tools/cheats/cht2bin.py YourGame.gba.cht
```

Pick codes whose effect is immediate and unmistakable: max money, infinite
health, a character that should be visibly wrong. A code that only matters
three hours in is not a test.

## The five checks

### 1. The core still boots

Load any ROM, no `.chtbin` present at all.

This is the one that catches a broken P1. The cheat engine sits on `gba_top`'s
debug bus alongside the savestate path and adds `sleep_cheats` to the CPU run
condition, so an arbitration mistake shows up as a core that hangs or never
draws rather than as a cheat that does not work. If this fails, nothing below
is worth trying.

Also check that closing the lid and reopening it resumes. `core.json` declares
`sleep_supported`, that path shares the run-condition gate the cheat engine now
writes into, and it is the interaction nothing in simulation covers.

### 2. The file loads

Put `YourGame.gba.chtbin` next to the ROM, named after the **whole** ROM
filename with `.chtbin` appended — `YourGame.gba` -> `YourGame.gba.chtbin`, not
`YourGame.chtbin`. Load the game and read `CL:`.

* **`CL:` is 0.** The file never arrived. Wrong name, wrong directory, or
  Windows appended `.txt`. Nothing to do with the core.
* **`CL:` is non-zero.** The bytes got there. Go to step 3.

### 3. It loaded the right number of entries

`CL:` packs `(bytes << 12) | (declared << 6) | pushed`. Against the converter's
own output — 4 entries in an 80-byte file — that is `(80 << 12) | (4 << 6) | 4`
= **327,940**.

Compute the expected value for your file and compare. The interesting failures:

* **Declared and pushed both 0, with bytes non-zero.** The header was rejected.
  Check `CD:` bit 7. Almost certainly a `.cht` that got renamed rather than
  converted, which is exactly what the magic exists to catch — see step 5.
* **Declared higher than pushed.** Truncated file, or more entries than the
  32-slot table holds; `CD:` bits 5:0 say which.
* **Bytes disagree with the file size.** The slot is reading something else.

### 4. A cheat actually takes effect, and the switch works

With the numbers right, look at the game.

* The code visibly does its thing.
* **Cheats Enabled** off in the core menu: the effect stops. The engine pokes
  on vblank and does not restore, so a value it wrote stays written until the
  game overwrites it — expect the effect to stop being *reapplied*, not to
  rewind. Watching health drain again from a full bar is the pass.
* Back on: it resumes.

The switch is `persist: false` and defaults on, so it is on again at every
launch. That is deliberate and it is why `CD:` bit 6 reports its live state.

### 5. A stray `.cht` loads nothing

Copy an unconverted `.cht` to the card, renamed to `.chtbin`. Load the game.

Expected: `CL:` shows bytes but zero declared and zero pushed, `CD:` bit 7 set,
and **the game is completely unaffected**.

This is the most important check on the list and the one simulation can only
partly vouch for. The previous format was a plain `.cht`, so someone dropping
the old file in is a real scenario, not a hypothetical, and without the header
magic it would shift ASCII into the cheat table and poke it into live memory.
A pass here is what makes the format change safe to ship.

## What a full pass means

P1, P2's surviving parts and P3 are done — closed at both ends, simulation and
hardware. That clears P8 (packaging and release) and makes the cartridge
question in `docs/PLAN.md` §2 the next real decision, to be made against the
**936 ALMs and 26 RAM blocks** left over.

Record the result in `docs/BASELINE.md` next to the fit numbers. A green fit
report and a green hardware pass are different claims and the log should not
blur them.
