# BMXE ROM-header diagnostic

This build replaces the passing local pattern with a passive check of the
first 192 bytes of Metroid Zero Mission's verified BMXE cartridge ROM. It
compares the paired words returned by `rom_source_mux` to the game cache.
The first word is sampled on ready; the companion is sampled on the next
system clock, matching `cache.vhd`. Requests latch their original DWORD
address, including odd/even ordering. Only physical cartridge mode with
CG `424D5845` enables the checker. Other cartridge revisions are not qualified.

The existing direct header probe and CG/CS checks are unchanged. Their
OR/AND fingerprints cannot establish byte-for-byte header integrity. This
new checker observes game ROM requests, not the separate probe responses.
The GBA engine, cartridge controller, save guards and CPU debug connections
are unchanged from the installed pattern build. The checker never initiates,
stalls or changes ROM transfers. Its added observation logic still requires
a new fit and timing qualification before hardware use.

## Hardware capture

After installing a timing-qualified package, fully power off/on and launch
BMXE with Cartridge Saves set to Read Only and cheats disabled. At the
corrupted startup, open the core menu and photograph **CG, CS, SF, HD, HS**.
No repeated pattern captures are needed. Menu entry snapshots HD/HS together;
values remain stable while it is open. Close/reopen to refresh.

- **HD:** (`F4000010`): actual first mismatching 32-bit ROM word.
- **HS:** (`F4000014`): comparison count, flags and its header byte offset.
- **SF:** retains its EEPROM-abort meaning; it is not an SRAM status flag.

HS encoding:

| Bits | Meaning |
|---|---|
| 31:16 | Completed header pairs checked, saturates at FFFF |
| 15 | All 24 aligned header pairs have been observed |
| 14 | Unexpected response or overlapping request; treat the diagnostic as invalid |
| 13 | At least one header DWORD differed from the verified reference |
| 12 | At least one header pair has been checked |
| 11:8 | Fixed marker A, distinguishes initialized payload from pre-capture zeros |
| 7:0 | First mismatching byte offset, aligned to four bytes; meaningful only with bit 13 |

For example, HS `00309A00`, HD `00000000` means 48 pairs checked, all
24 header lines covered, and no mismatch or protocol error. HS `00013A14`,
HD `12345678` means the first checked pair contained bad word `12345678`
at ROM address `08000014`. The first failure stays latched while counts and
coverage continue updating. HD may legitimately be zero for a failing word;
use the mismatch flag, not HD alone.

HS `00000A00` means no completed header pair has been checked (also the
inactive/non-BMXE state). It is not a pass. A missing full-coverage flag is
also not a mismatch: the CPU may not have requested every header line.
Resetting the GBA CPU alone preserves evidence if cartridge mode/identity
remain valid. Loss of mode or BMXE identity clears the checker. SF has its
separate configuration-only clearing behavior.

## Limits and verification

A mismatch locates incorrect data at the ROM mux output. It does not by
itself distinguish an electrical cartridge read problem from controller,
arbiter or mux handling. A clean complete header at this boundary does not
validate cache consumption, BIOS execution, VRAM, later ROM data or saves.

Simulation covers the checker with single-bit corruption on either beat,
first-failure retention, delayed companion data, scope and protocol checks;
real controller/arbiter/mux reads from a header-backed cartridge pin model;
48 cold odd/even fills and 576 lane/width reads through the actual VHDL cache
and memorymux; and actual top-level APF menu snapshots. The reference fixture
and provenance are in `sim/fixtures/README.md`. These simulations do not
prove cartridge electrical timing or reproduce a full BIOS boot.

Post-fit checks require all 32 mismatch-data and six DWORD-offset source
registers, and at least 58 variable bits in each snapshot bank. The remaining
six payload bits are constants. All timing categories must pass; the existing
20 ns raw snapshot routing budget remains unchanged at all corners.

The previous pattern build is documented in `git show d6a04ff:docs/BOOT-DEBUG.md`.
It passed both timing and observed hardware captures (rotations 55 and 0).
