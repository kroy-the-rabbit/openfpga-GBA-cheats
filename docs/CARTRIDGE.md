# Cartridges on the Pocket GBA core

Build `99293a3` boots Minish Cap, loads a working physical
cartridge save in Read Only mode, and plays with cheats, confirmed by the user. Physical write support passes
simulation but still needs a hardware persistence test. See `docs/HANDOFF.md`
for the latest results. The installed build is now **`417a55f`**, which uses
**Play Cartridge** directly; hardware confirmation of the new launch path
is pending.

**Cartridge Saves** defaults to **Read Only** at each launch. With Play Cartridge,
SRAM/Flash reads and EEPROM read commands reach the physical save chip.
Selecting **Writes Enabled** permits physical SRAM/Flash writes and EEPROM
program commands. EEPROM permission is latched for a whole command. Progress
made with writes disabled will not persist. Flash identification and bank
selection require byte writes too, so some Flash games need Writes Enabled
before they can recognize their save chip.

No SD save file is loaded or written back for cartridge games. Physical writes
are not hardware-qualified yet. GPIO/RTC remains disconnected. Savestates are removed from the core. Minish Cap's existing slots have now been read successfully with Cartridge
Saves left at Read Only.

**This core requires Pocket firmware 1.2 or newer.** Declaring the cartridge
adapter raises `version_required`, and an older firmware will refuse to load the
core at all rather than start it without the slot.

## What works

| | |
|---|---|
| Powering the slot | working for the successful Minish Cap header read |
| Detecting a cartridge, reading its header | **Minish Cap passed** on `85bb71a`: `CG=425A4D45`, `CS=FFFF96E1` |
| Refusing to act on an empty or half-inserted slot | **unconfirmed on hardware** |
| ROM out of the cartridge | **Minish Cap gameplay from an existing save confirmed** on `99293a3`; test duration not reported |
| Cartridge saves / EEPROM | **Minish Cap existing save loaded and played on hardware**; physical write persistence pending |
| Cheats during cartridge gameplay | **Confirmed by the user on Minish Cap** with `99293a3`; specific codes not reported |
| Metroid Zero Mission (`BMXE`, SRAM) | Header passes; white screen after BIOS on `99293a3` in both save modes and on `417a55f` (Save Fault 0). Cause unresolved. |
| Cartridge RTC/GPIO | not routed |
| Writing to a cartridge | disabled by default; enabled explicitly via Cartridge Saves |

For the current white-screen investigation, see [boot diagnostics](BOOT-DEBUG.md).

**Cartridge EEPROM saves have never worked, and the reason was synthesis,
not logic.** Every build up to 2026-09-09 fitted `cart_eeprom_bridge` as one
ALM and two registers. `fault` was reported "Stuck at VCC", and
`transfer_open`, `ctl_req` and `command_active` "Stuck at GND", so the bridge
never issued a physical EEPROM access, every EEPROM read returned ones, and
the `SF` readout reported a fault that was a hardwired constant rather than
anything the cartridge did. Simulation passed throughout, because simulation
does not constant-fold. The cause was a power-up initialiser written on the
module's output port declaration, which the fitter did not honour, leaving
`fault` with no defined power-up state and letting constant propagation
resolve the cycle through `transfer_open` to the degenerate answer. The
power-up values now live on internal registers, `fault` no longer gates the
transfer-tracking clear, and `scripts/inspect_timing.tcl` fails any build
where the bridge's registers do not survive.

The abort guard is armed by the write switch, not by the abort. Since
2026-09-09 the fail-closed latch is set only when the interrupted physical
transfer was **opened with writes enabled**. With Cartridge Saves on Read
Only the bridge forwards nothing that can alter what the chip stores, so an
interrupted read leaves the serial parser confused rather than the save
damaged, and the save path stays usable for the rest of the session. The
abort still retires its accepted bit and drops the command policy either
way; only the permanent latch is conditional.

## Interrupted EEPROM transfers (new source)

**Save Fault** is normally 0. If a physical EEPROM transfer is interrupted,
the bridge blocks further physical EEPROM traffic and reports 1. Power the
Pocket fully off and relaunch the core before continuing. Reset Core does
not clear the fault; a CS pulse is not assumed to reset the chip's serial
command parser. This prevents a later transfer inheriting write permission
from an aborted DMA. It cannot undo a physical write interrupted in progress.

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
once the controller does. It is `cfd4264`, built and timing-met at seed 1 on
2026-09-06, not yet run on the slot.

## Quick start (`417a55f`; pending hardware qualification)

1. Insert the cartridge before launching the core.
2. Choose **Play Cartridge** in the GBA core's asset browser. The core probes
   and boots the cartridge automatically, including existing physical saves.
3. Select **Writes Enabled** only when testing save persistence. Every launch
   starts in Read Only, so progress otherwise will not persist.

There is no separate Off/Detect/Boot switch. Choosing an SD ROM uses the SD
path. Old persisted mode values at `0x90` are ignored. The `417a55f`
bitstream and matching package are installed; no mode-switch migration is
needed.

## Launch selection

APF's [Cartridge Adapter notification](https://www.analogue.co/developer/docs/host-target-commands#0x00b1)
provides Play Cartridge in bit 24 and power-at-reset-exit in bit 16. The
[core definition](https://www.analogue.co/developer/docs/core-definition-files/core-json)
already enables that browser entry and skips ROM-derived SD files when used.
The command handler now consumes the notification, retains it across reset,
and routes ROM/save traffic after a successful header probe. The controller
stays in reset until APF Reset Exit and never runs without advertised power.

If the probe fails, the CPU stays in reset: there is no loaded SD ROM to fall
back to. The core menu remains available for **CG/CS** and **Reset Core**.
SD save size is zero for the entire cartridge launch, including before
detection and during reset. Savestate requests, which the core no longer
supports anywhere, return an error instead of waiting forever for an
acknowledgment.

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
the same trick the cheat loader used for `CL:` and `CD:` until those went.

### `CG:`, the game code

The four characters at header `0xAC..0xAF`, big-endian. Read the decimal as hex
and it is four ASCII letters. Pokemon Ruby is `AXVE`, which is `0x41585645`, and
the menu prints `1096287813`.

If it spells the game you inserted, the bus is working.

### `CS:`, the status word

```
bits 31:16  header fingerprint: every halfword of the header ORed together
bits 15:8   header byte 0xB2
bit     7   Play Cartridge selected and firmware advertises slot power
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
| `00` | Cartridge hardware disabled (SD launch or no advertised power). |

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

**The bus timing still needs hardware qualification in this core.** The
sequential defaults are `ROM_SEQ_WAIT=12`, `ROM_SEQ_RD_HIGH=4` since
2026-09-09, which is a real GBA's `WAITCNT=4317h` sequential access. They
were 20/6, matching `pocket-cartridge`'s `gba_cart_bus.sv` edge intervals,
until hardware showed what that costs: 20/6 makes an eight-byte cache line
take 834.5 ns, exactly a GBA's **power-on** `WAITCNT=0000h`, while a game
that has set `4317h` is written against 596.0 ns. Zero Mission froze in its
opening cutscene at 20/6 and START skipped past the freeze. CartTools can
afford the slower window because it is the only master and is not racing a
frame budget. CartTools has dumped cartridges, including Minish Cap,
byte-exact against No-Intro. That is evidence for its complete
implementation, not proof that either window makes this controller work on
hardware.

The following counts were checked by simulating both controllers, not by
measuring connector pins. At `clk_sys=100.663296 MHz`:

| Sequential halfword | RD# high | RD# low | Total |
|---|---|---|---|
| Current pocket-gba defaults, 12/4 | 4 clocks, 40 ns | 8 clocks, 79 ns | 12 clocks, 119 ns |
| pocket-gba 20/6, 2026-09-06 to 09-09 | 6 clocks, 60 ns | 14 clocks, 139 ns | 20 clocks, 199 ns |
| CartTools | 6 clocks, 60 ns | 14 clocks, 139 ns | 20 clocks, 199 ns |
| Real GBA, `WAITCNT=4317h` | | | 2 GBA clocks, 119 ns |
| Real GBA, `WAITCNT=0000h` | | | 3 GBA clocks, 179 ns |

CartTools' turnaround parameter is 4, but its countdown and state transitions
add two clocks to the high pulse. The earlier 18-clock comparison omitted
them. Setting this controller to 18/4 matches only CartTools' low pulse.
The earlier non-sequential comparison also added parameter values rather
than measuring edges and has been removed; that path is unchanged here.

The real GBA powers on with `WAITCNT=0000h`: WS0 sequential access takes one
clock plus two waitstates, about 179 ns. The commonly used fast setting
`4317h` gives one clock plus one waitstate, about 119 ns. Neither total specifies
the safe RD# high/low split through the Pocket's electrical path.
See [GBATEK's WAITCNT description](https://problemkaputt.de/gbatek-gba-system-control.htm).

The burst bench now asserts the default six-clock high and fourteen-clock low
pulses, including around 128 KiB boundary fallback. Its ROM data model still
responds immediately: it proves protocol and edge counts, not physical read
margin. Repeat full ROM hash checks and gameplay on real cartridges before
calling this timing qualified or restoring the faster setting. Measure the
performance cost too. `ROM_BURST=0` remains a diagnostic fallback, not a
guarantee that every other electrical assumption is correct.

**ROM reads burst, and that is new.** Words after the first in a read hold `CS#`
low and pulse `RD#` only, relying on the cartridge's own address counter, which
takes a 4-halfword read from 129 clock cycles to 93 with the current defaults
(the previous 12/4 setting took 69). The counter is 16 bits of
halfword address and wraps every 128K, so a read crossing that boundary falls
back to re-driving the address. If a cartridge turns out not to honour its own
counter, `ROM_BURST=0` in the controller restores the original path exactly.

**Save-write persistence is the next hardware test.** Physical saves are now
routed and Minish Cap existing-save reads work. Writes remain behind the
explicit test setting until persistence is qualified. See `docs/HANDOFF.md`.
