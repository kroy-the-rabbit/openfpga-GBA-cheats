# Cheats on the Pocket GBA core

CodeBreaker and GameShark codes from a libretro `.cht` file, converted on your
computer and copied to the SD card as a `.chtbin`. Which cheats are on is
decided by the file; the core menu has a single global switch.

**The core no longer parses `.cht` on the handheld, and a `.cht` copied
straight to the SD card will not work.** That is not a preference. The ASCII
parser fit in the FPGA only on paper: it measured 441 ALMs but grew the design
by 1,285 and cost 0.54 ns of setup timing at 97 % utilisation, which is the
difference between a core that runs and one that does not exist. The parse
moved to your computer, where it is also far easier to test. `docs/HANDOFF.md`
has the measurements and `docs/CHEATBIN.md` has the format.

## Quick start

There are two ways to get a `.chtbin` onto the card. The desktop picker is the
one to use if you have it:

**[pocket-tools](https://github.com/kroy-the-rabbit/pocket-tools)**
lists the games on your card, matches each against the libretro cheat database,
and lets you tick what you want. It knows this format, uses the same decoder
this repo does, and writes the `.chtbin` for you. It also writes a `.cht`
alongside, which is deliberate and explained under
[Two files](#two-files-if-you-used-the-picker) below.

By hand, with this repo checked out:

1. Convert the `.cht` on your computer:

   ```
   tools/cheats/cht2bin.py Zelda.gba.cht          # writes Zelda.gba.chtbin
   tools/cheats/cht2bin.py *.cht -d out/          # or a whole directory
   ```

   It prints what it found and what it had to drop. A cheat that produces no
   entries is reported rather than silently skipped, so an empty result is
   distinguishable from a broken file.

2. Put the `.chtbin` next to the ROM, named after the **whole** ROM filename
   with `.chtbin` appended:
   `/Assets/gba/common/Zelda.gba` -> `/Assets/gba/common/Zelda.gba.chtbin`.
   That is APF's rule for a slot whose filename is cloned from slot 0: the
   extension is appended, not swapped.

   The `.cht` you convert from is plain text and you can write it by hand. Only keys ending
   `_code`, `_desc` and `_enable` are read; `_code` and `_desc` take a quoted
   value, `_enable` a bare `true` or `false`. Everything else is ignored,
   including `cheats = N` and the number in `cheatN_`: cheats are taken in file
   order and each `_code` starts a new one.

   ```
   cheat0_desc = "Infinite Health"
   cheat0_code = "3200E924+0096"
   cheat0_enable = true
   ```

   Watch the extension when you write the `.cht`. Windows hides known ones, so
   a file saved from Notepad as `Zelda.gba.cht` may really be
   `Zelda.gba.cht.txt`: turn on "File name extensions" in Explorer's View tab.
   On macOS, TextEdit writes rich text unless you pick Format > Make Plain
   Text first. The converter will tell you if it read nothing useful.

3. Load the game. **Cheats Enabled** in the core menu turns the whole lot on
   and off; it is on at every launch and is not persisted.

4. If nothing happens, run `cht2bin.py` on the file again and read what it
   prints; the core no longer reports counts in its menu (see below).

If you copy a `.cht` to the SD card by mistake, the core loads **zero** cheats
rather than misbehaving: the `.chtbin` header carries a magic number precisely
so the old file cannot be mistaken for the new one and shifted into the cheat
table as garbage.

## Two files, if you used the picker

The picker leaves both `Game.gba.chtbin` and `Game.gba.cht` beside the ROM.
That is not the mistake above and nothing is wrong.

The core reads the `.chtbin` and only the `.chtbin`: data slot 7 accepts that
extension and no other, so the `.cht` is invisible to the hardware. It is there
for the picker, which needs somewhere to keep the descriptions and the enable
flags that the packed format has no room for and the core has no use for. It is
what makes your ticks come back the next time you open the app.

Edit or delete them as a pair. Changing the `.cht` by hand does nothing until
it is converted again; deleting only the `.chtbin` leaves the app thinking the
cheats are installed.

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
  fills, ROM patches, button tests and pointer chains.
* **Addresses outside EWRAM (`0x02000000`), IWRAM (`0x03000000`) and IO
  (`0x04000000`).** The engine writes 32 bits at a time through the internal
  bus. ROM and BIOS are not writable, SRAM at `0x0E000000` is a byte-wide bus
  that a 32-bit access misreads, and VRAM, OAM and palette RAM are rewritten by
  the game every frame after the vblank write lands.
* **Master and hook codes** (CodeBreaker types `0` and `1`, GameShark type `F`).
  They tell a cheat device where to install itself and have no memory effect,
  so dropping them is right, not a limitation.
* **Chains of conditions.** The engine's `skip_next` suppresses exactly one
  entry, so a condition guarding another condition cannot be expressed. Such a
  cheat produces nothing rather than a write that runs when it should not.

Over the whole libretro GBA cheat database, 514 files, this admits 7570 entries
<!-- The count disagrees with the 513 of 513 below. Both were recorded from
     corpus runs and only one can be right; settle it the next time a corpus is
     mounted rather than by picking the nicer number. -->
and not one address outside those three regions. The comparison worth making is
MiSTer's own pre-encoded cheat files, which gamehacking.org generates and which
do not filter: their GBA files carry entries with addresses like `0b070768`,
encrypted codes run through a raw decoder, poking nothing, out of a table that
has 32 slots in it.

### Limits

* **32 entries**, which is the engine's table. A conditional code costs two,
  because the condition and the write it guards are separate entries.
* A cheat is **all or nothing**. If the remaining slots cannot hold a whole
  cheat it is skipped and counted, and a later, smaller cheat can still fit.
* 1 MB of file.

## The overlay

**Cheat Overlay** in the core menu draws the loaded cheats over the game
picture: a header row with the counts, a row saying whether the game came
from the SD card or the cartridge slot, then one row per cheat. It is the
`cheat_osd` / `cheat_font` / `cheat_titles` trio from pocket-gbc, regridded
to 40 columns by 20 rows for 240x160 and composited in `video_adapter` on
`clk_vid`. Off by default, not persisted.

The `.chtbin` format carries no titles, so every row reads `CHEAT nn` for
now. The title RAM is wired and empty; the `.cht` text loader will fill it.

## The readout, removed 2026-09-09

`CL:` and `CD:` were two numbers in the core menu for when a file did not do
what you expected. They were removed to give the fitter room while the
cartridge branch is near the device limit; Cheats Enabled is the only
control now. The loader still keeps the counters internally and the
simulation benches still check them, so the description stays for the RTL
and for a future readout. A file's expected numbers come from
`cht2bin.py`, which prints them as it writes.

`CL:` packs three counters into one 32-bit number:

```
bits 31:12  bytes received, used or not
bits 11:6   entries the file's header DECLARED
bits  5:0   entries actually pushed to the engine
```

Read the low two fields against each other:

* **Zero bytes.** The file was never loaded: wrong name, wrong extension, or it
  is not next to the ROM. Nothing downstream of this matters.
* **Bytes, but declared and pushed are both zero.** The file arrived and was
  rejected at the header. Almost always a `.cht` that got renamed rather than
  converted, see `CD:` bit 7. This is the safety interlock doing its job.
* **Declared higher than pushed.** The file is truncated, or it declared more
  entries than the 32-slot table holds. `CD:` bits 5:0 tell you which.
* **Declared equals pushed, game unchanged.** The codes are loading and running
  and are simply wrong for your version of the game or your save.

A worked example. `cht2bin.py` prints what it wrote:

```
smoke.cht: 3 cheats, 4 entries, 0 dropped at the 32-entry cap, 80 bytes
```

so `CL:` should read `(80 << 12) | (4 << 6) | 4` = **327,940**. If it does not,
the difference tells you where it went wrong before you have opened anything.

`CD:` is the diagnostics word:

```
bit   7     the file was malformed: wrong magic, wrong version, or it ended
            mid-entry. This is the only state that otherwise looks exactly
            like a valid file containing no cheats.
bit   6     the master switch, i.e. Cheats Enabled
bits  5:0   declared entries the table had no room for
```

Two cautions on those fields. **`CD:` bit 7 is set by a plain `.cht`**, which is
the point: the header magic exists so that renaming a file instead of converting
it loads nothing, rather than shifting ASCII into the cheat table and corrupting
the game. And **bits 5:0 saturate**: the declared count is clamped at 63, so the
overflow tally stops at 31. It means "there were more", not an exact number, and
a file that trips it should have been trimmed by the converter already.

One name to be aware of if you read the RTL: internally these are
`group_count` and `overrun`, names inherited from the ASCII loader where they
counted cheats and push collisions. Under the binary format they count declared
entries and malformed files. The RTL says so at
`src/fpga/core/cheat_binloader.sv:76`.

## Cartridges

The cheat engine writes RAM through the internal bus rather than patching ROM
reads, so codes that write EWRAM, IWRAM or IO work the same whether the ROM came
from the SD card or from a cartridge. Codes that patch the ROM image itself do
not apply to a cartridge, because there is nothing writable there. The core
rejects those anyway.

The one gap is loading the file: in Play Cartridge mode APF does not load slots
named after slot 0, so `<rom filename>.gba.chtbin` is not picked up
automatically.
Use the **Cheats** slot in the core menu to browse for the file once; the slot
sets the "persist browsed filename" parameter, so it comes back on later
launches.

## How it is tested

`docs/HARDWARE.md` is the checklist for validating a build on a real Pocket,
including the stray-`.cht` case. In simulation:

```
make sim-image                     # once
make test                          # fixtures, end to end, and the cross-check
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
  a pass over them would prove nothing about the emitter. 513 of 513 files
  match, at both the slowest and the fastest byte rate the hardware can produce.
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
