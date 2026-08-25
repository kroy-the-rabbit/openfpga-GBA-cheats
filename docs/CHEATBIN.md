# `.chtbin`: the packed cheat format

## Why this exists

`cheat_loader.sv` parses libretro `.cht` ASCII on the FPGA, and that is what
stopped the cheat feature fitting. It carries a 64-bit token shift register,
hex nibble conversion, quoted-string tracking, key matching, a CodeBreaker pair
collector and a wide decoder. The module measures 441 ALMs but grows the design
by 1,285 and costs 0.54 ns of setup, and run M in `HANDOFF.md` showed the cost
is combinational, so no constraint or fitter setting reaches it.

Moving the parse to the host makes the on-chip loader a byte counter and a
shift register. **The file stores exactly the 128-bit words `gba_cheats`
consumes, so the loader performs no transformation whatsoever.**

## Layout

Little-endian throughout. A file is a 16-byte header followed by
`entry_count` 16-byte entries, and nothing else.

### Header, 16 bytes

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 4 | magic | `"GBAC"`, bytes `47 42 41 43` |
| 4 | 1 | version | `1` |
| 5 | 1 | reserved | `0` |
| 6 | 2 | `entry_count` | uint16, number of 16-byte entries that follow |
| 8 | 8 | reserved | all `0` |

The magic exists so the loader can reject a raw `.cht` dropped in by mistake
rather than shifting ASCII into the cheat table and corrupting the game. That
is a real scenario, because the previous format was exactly that file.

### Entry, 16 bytes

One 128-bit word in `gba_cheats` layout, stored little-endian, so byte 0 is
bits [7:0]:

| Bits | Field | Notes |
|---|---|---|
| [31:0] | value | the operand: what to write, or what to compare against |
| [63:32] | zero | must be 0 |
| [91:64] | address | 28 bits |
| [95:92] | zero | must be 0 |
| [99:96] | optype | 0 always, 1 `==`, 2 `>`, 3 `>=`, 4 `<`, 5 `<=`, 6 `!=`, F empty |
| [103:100] | byte enables | which lanes of the word the value occupies |
| [127:104] | zero | must be 0 |

This is `{24'b0, mask[3:0], optype[3:0], 4'b0, addr[27:0], 32'b0, val[31:0]}`,
the word `cheat_loader` already builds today.

Note the optype numbering: `OPT_GE` is 3 and `OPT_LT` is 4, which do not match
the names in the MiSTer VHDL (`OPTYPE_LESS` and `OPTYPE_GREATER_EQ`). The
numbering here is what the hardware does. See `tools/cheats/gbacht.py`.

## What the host decides, and the hardware no longer does

Everything. The converter resolves `enable` keys and emits **only enabled
cheats**, decodes GameShark and CodeBreaker pairs, places values into byte
lanes, drops address ranges the GBA does not have, enforces the 32-entry
ceiling, and orders conditional pairs so a compare entry is immediately
followed by the entry it guards. The hardware receives a finished table.

## Conditionals

`gba_cheats` implements a condition as two adjacent entries: a compare entry
with a non-zero optype, followed by the entry it guards. That adjacency is the
whole mechanism, so **entry order in the file is significant and the loader
must preserve it exactly.** Do not sort, dedupe or reorder entries.

## Limits and error handling

- `entry_count` above 32 (`CHEATCOUNT` in `gba_cheats.vhd`, `MAX_ENTRIES` in
  the loader) is not an error in the file. The converter should not emit more,
  and the loader must ignore the excess rather than wrap or corrupt.
- A file whose magic or version does not match must load **zero** entries and
  report zero. Silently loading nothing is correct here: a wrong file should
  behave as no cheats, never as garbage cheats.
- A truncated final entry is discarded. Do not pad it out.
- An empty file, or a header with `entry_count` 0, is valid and means no
  cheats.

## Naming

The Pocket clones data slot 7's filename from slot 0 and appends the slot
extension, so the file the core looks for is `<rom>.gba.chtbin`. The extension
in `data.json` changes from `cht` to `chtbin` accordingly.

## Compatibility

A `.cht` no longer works if dropped straight onto the SD card. It has to go
through `tools/cheats/cht2bin.py` first. That is a deliberate trade: it is the
only route found that keeps cheats without giving up save states or the RTC.
