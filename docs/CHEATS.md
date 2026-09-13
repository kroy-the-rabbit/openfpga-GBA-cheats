# Cheats on the Pocket GBA core

CodeBreaker and GameShark codes load directly from libretro `.cht` text.
The optional `.chtbin` format carries the same decoded entries without names.
Each file selects its cheats; **Cheats Enabled** is the global switch.

## Quick start

1. Put `Game.gba.cht` beside `Game.gba` in `/Assets/gba/common/`.
   Set the cheats you want to `cheatN_enable = true`; stock database files
   usually have every cheat disabled.
2. Load the game. Use the **Cheats** slot to select the `.cht` explicitly if
   there is also a `.chtbin`. In **Play Cartridge** mode, browse to the file
   once; it does not autoload from a ROM filename.
3. Turn on **Cheats Enabled**. It starts off on each core launch and is not
   persisted. Loading another file neither resets the game nor changes this
   switch.
4. Turn on **Cheat Overlay** to see the loaded names and counts. It also
   starts off and is not persisted.

A file is plain text. `_code` and `_desc` take quoted values, `_enable`
takes a bare `true` or `false`. Cheats are read in file order:

```
cheat0_desc = "Infinite Health"
cheat0_code = "3200E924+0096"
cheat0_enable = true
```

Check that a text editor has not appended `.txt` or saved rich text.
The whole ROM filename is retained: `Game.gba.cht`, not `Game.cht`.

## Optional binary conversion

The [pocket-tools picker](https://github.com/kroy-the-rabbit/pocket-tools)
writes `.cht` and `.chtbin` files. Prefer the text file for overlay names;
the packed file remains compatible with the older `v0.9999` GBA release.

For a manual conversion, use a Python virtual environment:

```sh
python3 -m venv build/cheats-venv
build/cheats-venv/bin/python tools/cheats/cht2bin.py Game.gba.cht
```

This writes `Game.gba.chtbin` beside the input and reports accepted entries
and dropped cheats. The core recognises binary `GBAC` magic and otherwise
parses the stream as text; a text file is a supported input.

## Two files, if you used the picker

Data slot 7 accepts both extensions. `.cht` supplies the selected codes and
their names; `.chtbin` supplies packed codes and displays `CHEAT nn`.
After editing text by hand, regenerate the binary if you still use it.
Remove both files to remove an installation made by the picker.

## Which cheats are on

Each cheat carries its own flag, exactly as libretro writes it:

```
cheat0_desc = "Infinite Health"
cheat0_code = "3200E924+0096"
cheat0_enable = true
```

* `true` or `1` means on, anything else means off.
* A cheat with **no** enable key at all defaults to on, so a hand-written file
  of nothing but codes works.
* Stock files from the libretro database ship with every cheat set to `false`,
  which is why dropping one in unedited does nothing until you turn some on.
  Write a file with just the cheats you want, enabled, rather than editing a
  stock one: the table holds 32 entries and a stock file has hundreds of cheats
  in it.
* One cheat can hold several codes joined with `+`; they are one cheat and
  share one flag.

## Supported code formats

A GBA code is two words. They pair up two at a time, and `+`, spaces and `:`
all separate them.

| Form | Example | |
|---|---|---|
| CodeBreaker | `3200E924+0096` | eight digits then four |
| CodeBreaker, run together | `3200E9240096` | twelve digits |
| GameShark v1/v2, raw | `02000900 00000012` | eight digits then eight |
| GameShark, run together | `0200090000000012` | sixteen digits |

The top nibble of the first word is the code type. These are the types the core
can run, and they are the ones almost every real code uses:

| Type | | |
|---|---|---|
| CodeBreaker `3` | `3AAAAAAA 00VV` | write one byte |
| CodeBreaker `8` | `8AAAAAAA VVVV` | write a halfword |
| CodeBreaker `7` `A` `B` `C` | `7AAAAAAA VVVV` | if the halfword is `==`, `!=`, `>`, `<` the operand, run the next code |
| GameShark `0` | `0AAAAAAA 000000VV` | write one byte |
| GameShark `1` | `1AAAAAAA 0000VVVV` | write a halfword |
| GameShark `2` | `2AAAAAAA VVVVVVVV` | write a word |
| GameShark `D` | `DAAAAAAA 0000VVVV` | if the halfword is `==`, `!=`, `<=`, `>=` the operand, run the next code |

Type semantics follow mGBA's `src/gba/cheats/codebreaker.c` and `gameshark.c`.

### What is dropped, and why

The core skips what it cannot run rather than poking something at random.

* **Encrypted codes.** GameShark v3, Action Replay v3, and any CodeBreaker line
  after a type `9`, are encrypted with a per-game seed. A `.cht` file gives no
  indication which encoding a code uses, and an encrypted pair is eight hex
  digits and eight more, exactly like a raw one, so they cannot be told apart
  by shape. They are rejected on plausibility instead: a raw code's address
  lands in EWRAM, IWRAM or IO, and an encrypted word almost never does.
* **Types the engine has no way to express**: `OR`, `AND`, `ADD`, multi-line
  fills, native Action Replay ROM-patch opcodes, button tests and pointer chains.
  Plain CodeBreaker writes to ROM are supported as read-side patches.
* **Addresses outside EWRAM (`0x02000000`), IWRAM (`0x03000000`) and IO
  (`0x04000000`), except explicit CodeBreaker ROM writes.** ROM addresses
  `0x08000000` through `0x0DFFFFFF` go to the read-side patch table.
  BIOS is not writable; SRAM at `0x0E000000` is a byte-wide bus
  that a 32-bit access misreads, and VRAM, OAM and palette RAM are rewritten by
  the game every frame after the vblank write lands.
* **Master and hook codes** (CodeBreaker types `0` and `1`, GameShark type `F`).
  They tell a cheat device where to install itself and have no memory effect,
  so dropping them is right, not a limitation.
* **Chains of conditions.** The engine's `skip_next` suppresses exactly one
  entry, so a condition guarding another condition cannot be expressed. Such a
  cheat produces nothing rather than a write that runs when it should not.

The raw eight-plus-eight-digit forms keep the RAM/IO address filter.
Only explicit CodeBreaker writes may target ROM; accepting that larger
address window for ambiguous raw codes would admit encrypted junk.

### Limits

* **32 entries**, which is the engine's table. A conditional code costs two,
  because the condition and the write it guards are separate entries.
* A cheat is **all or nothing**. If the remaining slots cannot hold a whole
  cheat it is skipped and counted, and a later, smaller cheat can still fit.
* **16 ROM-patch slots**, separate from the 32-entry load budget. Each ROM
  patch also consumes a loaded entry. Do not select more than 16 ROM entries.
* 1 MB of file.

## What is confirmed on hardware

The following paths have been exercised on a real Zero Mission
cartridge, 2026-09-10, on `fc6b82e`:

| Path | How |
|---|---|
| Plain writes | the four Zero Mission counter cheats |
| Conditional pairs | `IF missiles != 0xDEAD THEN missiles = 999` pins the HUD at 999, and the same test inverted never fires |
| Reads of every region the bus covers | one guarded write per region, each gated on `!= 0xDEAD` at an EWRAM, IWRAM and IO address, each pointed at a different HUD counter |
| ROM patches | the entry word rewritten to a branch to itself halts the game after the BIOS logo |
| `.cht` titles in the overlay | the cheat names draw instead of `CHEAT nn` |

On `f2a86db`, both six-patch Zero Mission midair cheats also worked together,
using twelve of the sixteen ROM-patch slots. A non-working cheat still needs
its address, game revision and condition checked; these tests qualify the
listed paths, not every code in a database.

## The overlay

**Cheat Overlay** in the core menu draws the loaded cheats over the game
picture: a header row with the counts, a row saying whether the game came
from the SD card or the cartridge slot, then one row per cheat. It is the
`cheat_osd` / `cheat_font` / `cheat_titles` trio from pocket-gbc, regridded
to 40 columns by 20 rows for 240x160 and composited in `video_adapter` on
`clk_vid`. Off by default, not persisted.

A `.cht` file's `cheatN_desc` strings are the row titles, uppercased and cut
at 26 characters. A `.chtbin` carries none, so its rows read `CHEAT nn`.

The line buffer's address delay has to match the title RAM's read latency
exactly: one stage too many and every title loses its first character.
`sim/core/tb_cheat_osd_titles.sv` reads a rendered row back against the font
and fails if it slips.

## Diagnostics

`CL:` and `CD:` were removed from the menu. Use the overlay's loaded counts
and names, the converter's report, and a cheat with a visible gameplay effect.
Loader counters remain available to simulation. The historical binary-only
menu layout is documented in `f5de823:docs/CHEATS.md`; that layout is retired.

## Cartridges

The cheat engine writes RAM through the internal bus rather than patching ROM
reads, so codes that write EWRAM, IWRAM or IO work the same whether the ROM came
from the SD card or from a cartridge. Codes that patch the ROM itself, a
plain write to `08000000`..`0DFFFFFF`, are applied on the read side instead:
`src/fpga/han/rom_patch.sv` holds sixteen of them and substitutes the bytes as
the cache line is fetched, so the CPU sees the patched program whether the
ROM came from the card or the slot. Conditional codes on ROM addresses are
ignored. Action Replay's encrypted "ROM patch" pairs must be decrypted and
written as a CodeBreaker halfword write, `8AAAAAAA VVVV`, to use this.

Proven on hardware on 2026-09-10 with a real Zero Mission cartridge and
`build/cheats/ZM-ROMPATCH-TEST.gba.cht`, which rewrites the ROM entry word
`EA00002E` to `EAFFFFFE`, a branch to itself: the BIOS logo plays and the
game never starts. A ROM line already in the cache when the file loads is
only re-fetched because `rom_patch` pulses `changed` into `cache.vhd`'s
`invalidate`, and the cheat slot does not reset the GBA
(`core_top.sv:1051`), so the test needs Reset Core after loading.

The one gap is loading the file: in Play Cartridge mode APF does not load slots
named after slot 0, so neither `.cht` nor `.chtbin` is picked up
automatically.
Use the **Cheats** slot in the core menu to browse for the file once; the slot
sets the "persist browsed filename" parameter, so it comes back on later
launches.

## How it is tested

`docs/HARDWARE.md` records tested behavior and the remaining hardware checks. In simulation:

```
make sim-image                     # once
make test                          # fixtures and integration; corpus checks skip
make test CHT_DB=/path/to/cht      # against your own corpus
make test ARGS="-n 100"            # sample the corpus instead of all of it
```

`tools/cheats/gbacht.py` is a reference model of the parser and the emitter,
written as the same flat state machine as the RTL so the two can be read side
by side. Three harnesses use it:

* `tools/sim/run.py` streams every `.cht` under `$CHT_DB` through the actual
  RTL in Icarus Verilog and diffs the 128-bit words it pushes against the model,
  word for word. Each file is run twice, once as written and once with every
  cheat switched on, because stock libretro files are all `enable = false` and
  a pass over them would prove nothing about the emitter. Corpus results depend
  on the mounted dataset; a run without it is a skip.
* `tools/sim/run_fixtures.py` runs cases that carry the right answer with them,
  so the two agreeing cannot hide a mistake in both. Among them is an oracle
  nothing in this repo wrote: the same libretro codes encoded by
  gamehacking.org and shipped as `MiSTer-devel/Cheats_MiSTer`, read back out of
  those binaries and compared word for word against ours.
* `tools/sim/run_e2e.py` sends a file as APF bridge writes at hardware rates,
  through `data_loader`'s dual clock FIFO, into a behavioural `gba_cheats` with
  a model of EWRAM, IWRAM and IO behind it, runs its vblank pass and checks the
  bytes. That is what proves a conditional code is an entry pair and that its
  `skip_next` suppresses the right entry.

The cheat corpus is not carried in this repo. It is
`cht/Nintendo - Game Boy Advance` in
[libretro/libretro-database](https://github.com/libretro/libretro-database);
point `CHT_DB` at a copy of it, or at any directory of `.cht` files.
