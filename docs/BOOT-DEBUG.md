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

The revised checker keeps its 48 reference DWORDs in a synchronous M10K
ROM and shares one 32-bit comparator across the two response clocks. This
replaces the resettable 64-bit reference register and two separate compares.
The sampling cycles are unchanged. Actual M10K placement is checked after
fitting; timing improvement is not assumed from the RTL.

The shrunk checker (2026-09-09) reports through one 32-bit snapshot.
The status word carries the first bad DWORD's differing byte lanes and
beat; the count is eight bits; `HD:` is retired (`F4000010` reads zero).
Since the same day's follow-up, the value of the first bad DWORD is kept
again and the snapshot **alternates**: the first menu open after power-on
captures the status word, the next captures the bad DWORD's value, the
next the status again. The status is the one with marker `A` in bits
19:16 and zeros in bits 3:1; the value has no marker.
This follows [Altera's ROM inference guidance](https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-rom-functions-from-hdl-code).

## Hardware capture

After installing a timing-qualified package, fully power off/on and launch
BMXE with Cartridge Saves set to Read Only and cheats disabled. At the
corrupted startup, open the core menu and photograph **CG, CS, SF, HS**.
No repeated pattern captures are needed. Menu entry snapshots HS; the value
remains stable while it is open. Close/reopen to refresh.

- **HS:** (`F4000014`): on alternate menu opens, the status word below, then a detail word. Close and reopen the menu to switch. The detail is the first bad header DWORD's value when the status word's mismatch bit is set, and otherwise **why the EEPROM guard latched**: zero if it never did, else marker `E` in bits 31:28, the bridge FSM state in 27:26, then `host_dma_active` fell, `reset_n` fell, `transfer_sent`, `ctl_req`, `command_active`, `host_rnw`, four zero bits, and the host's bit index in 15:0. `SF` says whether the guard is latched at all.
- **SF:** retains its EEPROM-abort meaning; it is not an SRAM status flag.

HS encoding:

| Bits | Meaning |
|---|---|
| 31:24 | Completed header pairs checked, saturates at FF |
| 23 | All 24 aligned header pairs have been observed |
| 22 | Unexpected response or overlapping request; treat the diagnostic as invalid |
| 21 | At least one header DWORD differed from the verified reference |
| 20 | At least one header pair has been checked |
| 19:16 | Fixed marker A, distinguishes initialized payload from pre-capture zeros |
| 15:8 | First mismatching byte offset, aligned to four bytes; meaningful only with bit 21 |
| 7:4 | Byte lanes of that DWORD that differed, bit 7 the most significant byte; meaningful only with bit 21 |
| 3:1 | Zero |
| 0 | That DWORD was the companion beat, sampled the clock after ready |

For example, HS `309A0000` means 48 pairs checked, all 24 header lines
covered, and no mismatch or protocol error. HS `013A14F0` means the first
checked pair had a bad first-beat DWORD at ROM address `08000014` with all
four bytes wrong; `013A1011` means the companion DWORD at `08000010` was
wrong in its low byte only. The first failure stays latched while counts and
coverage continue updating.

HS `000A0000` means no completed header pair has been checked (also the
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

Post-fit checks require the 32 value, four lane, six DWORD-offset and one
beat source registers, and at least 23 variable bits in each snapshot bank. All timing categories must pass; the existing
20 ns raw snapshot routing budget remains unchanged at all corners.

The previous pattern build is documented in `git show d6a04ff:docs/BOOT-DEBUG.md`.
It passed both timing and observed hardware captures (rotations 55 and 0).
