# Cartridge boot diagnostics

The BMXE ROM-header checker was **retired from the fitted design on
2026-09-09**, having answered its question: every error it caught was in
the first halfword after the address latch, the non-sequential read. The
cause was the read window, not the slot: with a turnaround between
releasing the address bus and RD# falling (menu `ROM Timing`, any profile
but Fast) Zero Mission boots clean every time. Removing the instance
returned about 88 ALMs and one M10K.

`src/fpga/han/cart_header_check.sv`, its testbench and the ROM-path
integration bench are all still in the tree and still run under `make test`.
Re-instantiating it in `core_top.sv` and re-adding its line to
`ap_core.qsf` is all it takes to bring it back.

What remains on the menu is `EE:` at `F4000014`, the cartridge save
diagnostic, plus `CG:`, `CS:` and `SF:`.

## The `EE:` word

Snapshotted coherently when the core menu opens. If the EEPROM abort
condition ever fired, this is why it first fired, marker `E` in the top
nibble. Otherwise it is the EEPROM traffic so far:

| Bits | Meaning |
|---|---|
| 31:24 | Requests from the game that reached the bridge, modulo 256 |
| 23:16 | Requests the bridge forwarded to the slot, modulo 256 |
| 15:0 | The last sixteen bits the chip answered, newest in bit 0 |

A game at its save menu with `00000000` here never asked for its save. One
with requests and `FFFF` in the low half asked a chip that did not answer.

The abort form:

| Bits | Meaning |
|---|---|
| 31:28 | Marker `E` |
| 27:26 | Bridge FSM state |
| 25 | `host_dma_active` had dropped |
| 24 | `reset_n` had dropped |
| 23 | A bit had been sent |
| 22 | A request was being accepted on that clock |
| 21 | A command was active |
| 20 | The access was a read |
| 19 | A transfer was open |
| 18 | That transfer was opened with writes enabled |
| 17 | The access was part of a DMA |
| 16 | A host request was present |
| 15:0 | The host's bit index |

It is recorded whether or not the guard latched, so a Read Only session
still explains itself. `SF:` says whether the guard is latched.

## Hardware capture

After installing a timing-qualified package, fully power off/on and launch
BMXE with Cartridge Saves set to Read Only and cheats disabled. At the
corrupted startup, open the core menu and photograph **CG, CS, SF, HS**.
No repeated pattern captures are needed. Menu entry snapshots HS; the value
remains stable while it is open. Close/reopen to refresh.

- **HS:** (`F4000014`): on alternate menu opens, the status word below, then a detail word. Close and reopen the menu to switch. The detail is the first bad header DWORD's value when the status word's mismatch bit is set, and otherwise **why the EEPROM abort condition first fired**: zero if it never did, else marker `E` in bits 31:28, the bridge FSM state in 27:26, then `host_dma_active` fell, `reset_n` fell, `transfer_sent`, `ctl_req`, `command_active`, `host_rnw`, `transfer_open`, `transfer_writable`, `host_dma`, `host_req`, and the host's bit index in 15:0. It is recorded whether or not the guard latched, so a Read Only session still explains itself. `SF` says whether the guard is latched.
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
