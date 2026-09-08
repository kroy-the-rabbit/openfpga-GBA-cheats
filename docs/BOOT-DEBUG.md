# Cartridge boot diagnostics

These readouts are for the Zero Mission white-screen investigation. They
observe the existing CPU and cartridge path; they do not change its timing,
reset conditions, write policy or request handling.

After the game stops, open the core menu and capture **CPU PC**, **CPU State**,
**IRQ / DMA**, and **Save Bus**, along with CG/CS and Save Fault. All four debug
words are sampled together on entry to the OS menu and stay stable while it
is open. Close and reopen the menu for another sample. The CPU continues to
run as before; opening the menu only captures its state.

A toggle handshake moves the captured words from clk_sys to clk_74a. The
payload is held until the host has received its acknowledgment; it is not a
set of independently sampled live buses. The values start at zero until the
first menu entry completes a capture. A read during the brief handshake may
still return the previous snapshot. After fitting, check the bundled payload
routing against its two-host-clock settling window (about 27 ns).

## CPU PC — 0xF4000010

The CPU's existing fetch program counter, in bytes. Thumb/ARM and execution
mode are in CPU State. Repeated captures distinguish a stable wait from
ongoing execution; a single PC does not prove that an instruction retired.

## CPU State — 0xF4000014

| Bits | Meaning |
|---|---|
| 0 | CPU halted |
| 1–4 | Z, C, N, V flags |
| 5 | Thumb mode |
| 9–6 | Core CPU-mode encoding |
| 10–11 | IRQ / FIQ masks |
| 19–12 | Memorymux state |
| 20 | DMA3 transfer active |
| 21 | Cartridge arbiter busy |
| 22 | Interrupt master enable |
| 23 | Physical cartridge ROM selected and detected |
| 24 | GBA reset asserted |
| 25 | External EWRAM/save-memory request outstanding |
| 26 | CPU ROM/cache request outstanding |
| 27 | Physical SRAM/Flash byte request outstanding |
| 28 | Last SRAM/Flash request was a read |
| 29 | Cheats actually enabled |
| 30 | Physical save writes enabled |
| 31 | EEPROM abort fault latched |

Relevant memorymux states for this source:

| Hex | State |
|---|---|
| 00 | IDLE |
| 02 | READPAK_CACHE |
| 0B | WAIT_GBBUS |
| 0C | WAIT_PROCBUS |
| 0D | WAIT_SDRAM |
| 10 | ROTATE |
| 25 | CART_SAVE_WAIT |
| 27 | CART_EEPROM_WAIT |

The outstanding flags track request/completion handshakes and clear on APF
or core reset. They are observations, not timeout or error indicators.

## IRQ / DMA — 0xF4000018

Low 16 bits: existing pending interrupt flags. Upper 16 bits: the core's
existing DMA diagnostic word: bit 0 arbiter idle, bits 2–1 selected channel,
bits 6–3 active channels, bits 11–8 grants, bits 15–12 channel-idle flags.
Interrupt master enable is in CPU State bit 22.

## Save Bus — 0xF400001C

| Bits | Meaning |
|---|---|
| 16–0 | Last physical SRAM/Flash byte address |
| 24–17 | Last returned physical byte |
| 31–25 | Completed byte requests modulo 128, including denied writes |

The address is the last/current request and the byte is the last read
response; they need not belong to the same transaction while a read is
pending or after a write. A zero counter can also mean it wrapped.

For EEPROM games, these SRAM/Flash fields may remain zero. Save Fault is an
EEPROM-specific guard and cannot confirm that SRAM transfers work.
