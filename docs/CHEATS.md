# Cheats on the Pocket GBA core

CodeBreaker and GameShark codes, read straight from a libretro `.cht` file.
Which cheats are on is decided by the file; the core menu has a single global
switch. Nothing has to be converted or precompiled: the core parses the ASCII
itself.

Status: the loader, the emitter and the data slot are done and proven in
simulation. The engine they feed, MiSTer's `gba_cheats`, is restored in P1 and
is not wired up yet. See `docs/PLAN.md`.

## Quick start

1. Put the `.cht` next to the ROM, named after the **whole** ROM filename with
   `.cht` appended:
   `/Assets/gba/common/Zelda.gba` -> `/Assets/gba/common/Zelda.gba.cht`.
   That is APF's rule for a slot whose filename is cloned from slot 0: the
   extension is appended, not swapped.

   The file is plain text and you can write it by hand. Only keys ending
   `_code`, `_desc` and `_enable` are read; `_code` and `_desc` take a quoted
   value, `_enable` a bare `true` or `false`. Everything else is ignored,
   including `cheats = N` and the number in `cheatN_`: cheats are taken in file
   order and each `_code` starts a new one.

   ```
   cheat0_desc = "Infinite Health"
   cheat0_code = "3200E924+0096"
   cheat0_enable = true
   ```

   Watch the extension. Windows hides known ones, so a file saved from Notepad
   as `Zelda.gba.cht` may really be `Zelda.gba.cht.txt`: turn on "File name
   extensions" in Explorer's View tab. On macOS, TextEdit writes rich text
   unless you pick Format > Make Plain Text first.

2. Load the game. **Cheats Enabled** in the core menu turns the whole lot on
   and off; it is on at every launch and is not persisted.

3. If nothing happens, read `CL:` in the menu. It is three numbers packed into
   one, and it says which of the three things went wrong.

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

## The readout

Two numbers in the core menu, for when a file does not do what you expected.

`CL:` packs three counters into one 32-bit number:

```
bits 31:12  bytes received
bits 11:6   cheats pushed
bits  5:0   entries pushed
```

* Zero bytes means the file was never loaded: wrong name, wrong extension, or
  it is not next to the ROM.
* Bytes but no cheats means the file was read and nothing in it survived. Every
  cheat is probably `enable = false`, or the codes are encrypted.
* Cheats but the game is unchanged means the codes are running and are wrong
  for your save or your version of the game.

`CD:` is the diagnostics word:

```
bit   7     push overrun; a real file cannot set this
bit   6     the master switch
bits  5:0   enabled cheats the table had no room for
```

## Cartridges

The cheat engine writes RAM through the internal bus rather than patching ROM
reads, so codes that write EWRAM, IWRAM or IO work the same whether the ROM came
from the SD card or from a cartridge. Codes that patch the ROM image itself do
not apply to a cartridge, because there is nothing writable there. The core
rejects those anyway.

The one gap is loading the file: in Play Cartridge mode APF does not load slots
named after slot 0, so `<rom filename>.gba.cht` is not picked up automatically.
Use the **Cheats** slot in the core menu to browse for the file once; the slot
sets the "persist browsed filename" parameter, so it comes back on later
launches.

## How it is tested

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
