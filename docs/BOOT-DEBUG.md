# Cartridge boot diagnostics

The menu provides `EE:` at `F4000014`, the cartridge save diagnostic,
plus `CG:`, `CS:` and `SF:`.

## The `EE:` word on `p6-flashcarts`

On this branch `EE:` and `SF:` carry the flash-cart words instead, taken
together when the core menu opens.

`EE:`

| Bits | Meaning |
|---|---|
| 31:28 | Top nibble of the CPU's PC: `0` BIOS, `2` EWRAM, `3` IWRAM, `8`..`D` cart |
| 27 | CPU halted (waiting for an interrupt) |
| 26 | The last flash-cart access was a read |
| 25:20 | Flash-cart accesses so far, modulo 64 |
| 19:16 | Top nibble of the PC when the last access was made |
| 15:8 | Halfword address bits 23:16 of the last access |
| 7:0 | Halfword address bits 7:0 of the last access |

`SF:`

| Bits | Meaning |
|---|---|
| 31:16 | Data of the last flash-cart write |
| 15:8 | Cart ROM reads since the last access, saturating at `FF` |
| 7:0 | PC bits 23:16 now |

EverDrive registers read as `FEnn` in `EE:` bits 15:0, `nn` the register
number (`00` CFG, `01` STATUS, `09` SD_DAT, `0A` SD_CFG, `5A` KEY); `FF00`
is its EEPROM port. Omega DE registers read as `A000` (SD ctl), `C400`
(ROM page), `F000` (SD data and status). Close and reopen the menu: a rising
count with the same address is a poll; a fixed count is a CPU that stopped
talking to the cart.

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
| 21 | Reserved, always 0 |
| 20 | The access was a read |
| 19 | A transfer was open |
| 18 | Reserved, always 0 |
| 17 | The access was part of a DMA |
| 16 | A host request was present |
| 15:0 | The host's bit index |

Any abort latches the guard, and `SF:` says whether it is latched.

## Hardware capture

After installing a timing-qualified package, power cycle the Pocket and
launch the cartridge with cheats disabled and ROM Timing at Turnaround.
Open the core menu and record **CG, CS, SF, EE**. Menu entry snapshots these
values; close and reopen to refresh. There is no Cartridge Saves toggle.
`SF` is the EEPROM abort latch, not a general SRAM failure flag.


[Retired diagnostics and verification history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/gba/docs/BOOT-DEBUG.md) (private).
