# Cartridges on the Pocket GBA core

The core can power the Pocket's cartridge slot, detect a GBA cartridge and read
its header. Bring-up only. Nothing here has run on hardware yet.

> **A cartridge game cannot save.** Saves, EEPROM and the GPIO block that
> carries RTC are not routed to the cartridge, and the core reports no save file
> to the Pocket while booting from a cart. Nothing in this core writes to a
> cartridge, by design, so your cartridge's existing save is not at risk. But a
> game booted from a cart has nowhere to put a new one, and anything it thinks
> it saved is gone when you close the core.

**This core requires Pocket firmware 1.2 or newer.** Declaring the cartridge
adapter raises `version_required`, and an older firmware will refuse to load the
core at all rather than start it without the slot.

## What works

| | |
|---|---|
| Powering the slot | declared, **unconfirmed on hardware** |
| Detecting a cartridge, reading its header | **unconfirmed on hardware** |
| Refusing to act on an empty or half-inserted slot | **unconfirmed on hardware** |
| ROM out of the cartridge | wired, and **the first hardware run froze at the GBA logo**, see below |
| Cartridge saves, EEPROM, RTC | **not routed**, deliberately |
| Writing to a cartridge | **nothing does**, deliberately |

## First hardware run, 2026-09-05

Build `0.9999-cheats.60990db`, `p5-cartridge` at `60990db`, Quartus 25.1std,
`STANDARD FIT`, seed 3, timing met at +0.092 ns setup and +0.111 ns hold;
installed on the card and hash-verified. Kroy booted The Legend of Zelda: The
Minish Cap from the cartridge in the slot and **it froze at the GBA logo**.

Kroy read the menu afterwards: `CG:` was 0 and `CS:` was `0x000000B0`.
Decoded: the menu was not Off, the probe finished, and it timed out. The header
fingerprint is `0000`, byte `0xB2` read as `00`, and no ROM read ever completed.
The controller never answered.

Why it never answered is in the wiring, not the slot. The probe starts on
`dataslot_allcomplete`, but the controller's reset is APF `reset_n`, and the
probe does not wait for it. The controller's ROM read path is counters only and
answers in about 64 cycles against a 4000-cycle timeout, so the one way to get
`B0` is the controller still held in reset when the probe ran, which says the
Pocket sends "data slot access all complete" before "Reset Exit". The probe
times out, `cart_detect` stays low, and `Boot` then starts the core against
SDRAM with no ROM in it, which is the GBA logo and nothing after it.

The fix is to hold the probe in reset until `reset_n` is high, so it runs only
once the controller does. Not yet built or run.

## Quick start

1. Set **Cartridge** in the core menu to `Detect`. The core restarts.
2. Insert a cartridge and restart the core.
3. Read `CG:` and `CS:` in the menu. `CG:` is the game code, `CS:` says whether
   the read is trustworthy. Both are below.
4. If `CS:` looks right, set **Cartridge** to `Boot`.

## The three settings

**Cartridge** is one menu entry with three values. It persists, and changing it
restarts the core: the save size reported to the Pocket, the ROM source and the
game-quirk table all follow it, and none may change under a running game.

| | |
|---|---|
| `Off` | The controller is held in reset and the slot pins sit at the same idle values every previous build of this core used. A cartridge in the slot does nothing. |
| `Detect` | The controller owns the slot and the header probe runs. The ROM still comes from the SD card. This is the setting to read `CS:` in. |
| `Boot` | As `Detect`, and the ROM comes from the cartridge, but only if the probe passed. |

`Boot` is deliberately not a promise. If the probe does not pass, the ROM comes
from the SD card exactly as it always did. An empty slot or a half-inserted
cartridge cannot leave you with a core that will not start.

## The probe

On every core start, the core reads the cartridge's 192-byte header twice and
requires the two passes to agree, then holds the CPU in reset until it has
finished so the ROM source is settled before the game begins. It costs about
450 us at boot and gives up after about 40 us on any single read that the
controller does not answer.

Reading it twice is not caution for its own sake. A half-inserted cartridge has
some pins touching and others floating, which returns a mix of real data and
`FF` that changes between passes. One pass cannot tell that from a cartridge.

The core does not test for a `0xEA` branch opcode at the start of the header.
Some cartridges do not have one.

## The readout

The Pocket has no console, so `CG:` and `CS:` are the whole diagnostic surface,
the same trick the cheat loader uses for `CL:` and `CD:`.

### `CG:`, the game code

The four characters at header `0xAC..0xAF`, big-endian. Read the decimal as hex
and it is four ASCII letters. Pokemon Ruby is `AXVE`, which is `0x41585645`, and
the menu prints `1096287813`.

If it spells the game you inserted, the bus is working.

### `CS:`, the status word

```
bits 31:16  header fingerprint: every halfword of the header ORed together
bits 15:8   header byte 0xB2
bit     7   the Cartridge menu is not Off
bit     6   cart detected, the ROM may come from it
bit     5   the probe has finished, pass or fail
bit     4   the probe timed out, the controller never answered
bit     3   the two passes disagreed, which is a half-inserted cartridge
bit     2   every halfword read as FFFF, which is an empty slot
bit     1   every halfword read as 0000
bit     0   the controller completed at least one ROM read
```

Convert it to hex and read it in three pieces.

**Bits 15:8 are the strongest single sign.** Header byte `0xB2` is `0x96` on
every licensed cartridge. If those bits read `96`, the read is real. It is
reported and not gated on, because an unlicensed cartridge is still a cartridge.

**Bits 31:16** say what came back at all. `0000` means nothing was read. `FFFF`
means an empty slot. Anything else is a header.

**The low byte** is the verdict:

| Low byte | Means |
|---|---|
| `E1` | Detected. Probe finished, passes agreed, a read completed. |
| `A5` | Empty slot. Every halfword read `FFFF`. |
| `A9` | Passes disagreed. Reseat the cartridge. |
| `B0` | Timed out. The controller never answered a read. |
| `A3` | Every halfword read `0000`. The slot is not being driven. |
| `00` | The menu is `Off`. Nothing ran. |

## Cheats on a cartridge game

They work, for the codes that matter. The cheat engine writes RAM through the
internal bus rather than patching ROM reads, so codes that write EWRAM, IWRAM or
IO behave the same whether the ROM came from the SD card or a cartridge. Codes
that patch the ROM image do not apply, because there is nothing writable there,
and the converter rejects them anyway.

Loading the file needs one extra step in cartridge mode, and `docs/CHEATS.md`
covers it: APF does not load a file named after slot 0 when slot 0 is not
loaded, so browse for the `.chtbin` once using the **Cheats** slot in the core
menu. The slot sets the "persist browsed filename" parameter, so it comes back
on later launches.

## What is not settled

**The bus timing is derived, not measured.** Every wait-state constant in
`src/fpga/han/gba_cart_controller.sv` is a conservative placeholder computed
from GBATEK's default `WAITCNT`, and its author says plainly that they must be
tuned on real cartridges. Nothing here has been.

**ROM reads burst, and that is new.** Words after the first in a read hold `CS#`
low and pulse `RD#` only, relying on the cartridge's own address counter, which
takes a 4-halfword read from 129 clock cycles to 69. The counter is 16 bits of
halfword address and wraps every 128K, so a read crossing that boundary falls
back to re-driving the address. If a cartridge turns out not to honour its own
counter, `ROM_BURST=0` in the controller restores the original path exactly.

**Saves are the next phase.** Routing them means writing to a cartridge, and
that stays behind an explicit toggle until it is proven on a cartridge nobody
minds losing. See `docs/PLAN.md` §5.
