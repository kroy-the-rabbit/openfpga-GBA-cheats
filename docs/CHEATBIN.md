# `.chtbin`: the packed cheat format

## Purpose

The packed format stores exactly the 128-bit words `gba_cheats` consumes.
It was introduced when the text parser could not fit alongside savestates.
The current core accepts both `.cht` and `.chtbin`; text carries overlay
names, while the packed format is an optional input and remains compatible
with the published `v0.9999` core.

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

The binary loader validates this magic. The current core selects the binary
loader for `GBAC` streams and the text parser otherwise; both file formats
are supported.

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

## What the host decides for a binary file

Everything. The converter resolves `enable` keys and emits **only enabled
cheats**, decodes GameShark and CodeBreaker pairs, places values into byte
lanes, filters by address region, enforces the 32-entry ceiling, and orders
conditional pairs so a compare entry is immediately followed by the entry it
guards. The hardware receives a finished table.

The region filter keeps EWRAM, IWRAM and IO. Explicit CodeBreaker writes may
also target ROM at `0x08000000` through `0x0DFFFFFF`; the core applies these
as read-side patches rather than physical ROM writes. Conditional ROM codes
are rejected. The raw eight-plus-eight-digit forms retain the RAM/IO filter.
See `REGIONS`, `ROM` and the decoder in `tools/cheats/gbacht.py`.

The ROM-patch table holds sixteen entries, separate from the 32-entry input
limit. A producer must keep the ROM entries within that smaller limit too.

## Conditionals

`gba_cheats` implements a condition as two adjacent entries: a compare entry
with a non-zero optype, followed by the entry it guards. That adjacency is the
whole mechanism, so **entry order in the file is significant and the loader
must preserve it exactly.** Do not sort, dedupe or reorder entries.

## Limits and error handling

- `entry_count` above 32 (`CHEATCOUNT` in `gba_cheats.vhd`, `MAX_ENTRIES` in
  the loader) is not an error in the file. The converter should not emit more,
  and the loader must ignore the excess rather than wrap or corrupt.
- **At the cap, shed whole cheats, never a partial one.** Truncating at exactly
  32 entries can cut between a compare entry and the entry it guards. That
  leaves the compare last in the table, where its `skip_next` falls on an
  unrelated cheat and the write it was guarding is gone: a silently wrong
  cheat, which is worse than a missing one. So a file may legitimately carry
  fewer than 32 entries even when the source had more to give. This matches
  `gbacht`'s existing all-or-nothing policy for a group.
- A file whose magic or version does not match must load **zero** entries and
  report zero. Silently loading nothing is correct here: a wrong file should
  behave as no cheats, never as garbage cheats.
- A truncated final entry is discarded. Do not pad it out.
- **`entry_count` is a hard stop, not a hint.** The loader must stop after that
  many entries and ignore anything after them. A 16-byte entry carries no
  framing of its own, so trailing bytes are indistinguishable from real
  entries and the declared count is the only thing that can tell them apart.
- An empty file, or a header with `entry_count` 0, is valid and means no
  cheats.
- **Reserved bytes are ignored on read, written as zero.** A loader must not
  reject a file for a non-zero reserved byte at offset 5 or in 8:16. Rejecting
  would make any future use of those bytes a breaking change, which defeats
  the point of reserving them.
- **The file never pads to 32 entries and never contains optype `F`.**
  `entry_count` bounds the table. What happens to the table slots past
  `entry_count` is the loader's business: `gba_cheats` wants them empty, and
  the loader is what clears them. Do not expect padding entries in the file.

## Naming

The Pocket clones data slot 7's filename from slot 0 and appends the slot
extension, so a binary file is named `Game.gba.chtbin` for `Game.gba`.
`data.json` accepts both `cht` and `chtbin`. In Play Cartridge mode, browse
to the file through the Cheats slot; ROM-derived names do not autoload.

## Compatibility

The published `v0.9999` core accepts only `.chtbin`. Current `main` also
parses `.cht` directly and uses its descriptions as overlay titles. A binary
file has no titles, so the overlay uses `CHEAT nn`. Savestates and sleep
have been removed; RTC remains available for SD ROMs.
