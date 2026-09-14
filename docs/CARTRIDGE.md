# Cartridges on the Pocket GBA core

The tested build is `f2a86db`, installed on 2026-09-10. **Play Cartridge**
boots Minish Cap and Zero Mission, loads their existing physical saves and
plays with cheats. A new Zero Mission save written by this core was read back
by Analogue's own cartridge mode.

Cartridge saves access the physical chip directly. The Read Only mode and
its menu entry were removed; there is no save-write enable toggle. No SD
`.sav` is loaded or written in cartridge mode. Back up saves before testing
new cheats or a cartridge that has not been qualified.

## What works

| Feature | Status |
|---|---|
| Play Cartridge, header probe, ROM reads and gameplay | Minish Cap and Zero Mission confirmed |
| Existing EEPROM saves | Both cartridges confirmed |
| Physical save persistence | Zero Mission write read back through Analogue's cartridge mode |
| RAM cheats, conditional pairs, named overlay and ROM patches | Confirmed on hardware |
| Fast Burst timing | Clean audio on the tested Zero Mission cartridge; opt-in |
| Physical SRAM/Flash write persistence | Not hardware-qualified |
| Interrupted-transfer guard | Covered in simulation; not hardware-qualified |
| Empty or partially inserted slot | Not hardware-qualified |
| Cartridge RTC/GPIO, solar and gyro | Not routed |
| Flash carts: EZ-Flash Omega DE, EverDrive | `p6-flashcarts`; simulated, not hardware-tested |
| Savestates, sleep and link cable | Removed |

## Quick start

1. Use Pocket firmware **1.2 or newer** and provide
   `/Assets/gba/common/gba_bios.bin` (16,384 bytes).
2. Insert the cartridge before launching the core and choose **Play Cartridge**
   in the asset browser. Choosing an SD ROM instead uses the SD path.
3. Browse to a `.cht` or `.chtbin` using the **Cheats** slot. Prefer text for
   overlay names. This selection persists; filename-based autoload does not
   run in cartridge mode.
4. Turn on **Cheats Enabled** and, if wanted, **Cheat Overlay**. Both start off.
5. Keep **ROM Timing** at **Turnaround** unless testing another profile.
   **Fast Burst** fixes the tested Zero Mission audio slowdown but exceeds
   real GBA bus speed and is not qualified on every cartridge.

The old Off/Detect/Boot and Cartridge Saves controls no longer exist.

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

On a cartridge launch, the core reads the cartridge's 192-byte header twice and
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

`CG:` and `CS:` describe the cartridge probe. `SF:` and `EE:` describe the
EEPROM bridge; see [BOOT-DEBUG.md](BOOT-DEBUG.md). `CL:` and `CD:` were removed.

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

**Bits 31:16** are an OR fingerprint, not an empty-slot verdict. A valid header
can also produce `FFFF`. Use bit 2 and the low-byte status to identify the
all-`FFFF` read pattern.

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

The cheat engine applies EWRAM, IWRAM and IO writes through the internal bus.
Explicit CodeBreaker ROM writes are applied by `rom_patch.sv` on reads from
either SDRAM or the cartridge; they do not modify physical ROM. The table
holds sixteen ROM patches. Conditional ROM codes are ignored.

Browse to the `.cht` or `.chtbin` once through **Cheats**. Loading a file
does not reset the game or enable cheats. See [CHEATS.md](CHEATS.md).

## Flash carts

Branch `p6-flashcarts`. Flash carts are driven through ROM space: they unlock,
select pages and reach their SD card with halfword writes and reads there.
The released core drops CPU writes to ROM space. On `f2a86db` the Omega DE
bootloops at a popup, most likely its firmware update prompt, since its version
read comes back as ROM data; the EverDrive shows a red screen.

- A CPU or DMA write to `08000000..0CFFFFFF` reaches the cart as one CS#-latched
  halfword write per halfword. The ROM cache and the 8-byte line beside it
  are dropped afterwards, since the cart may now map different ROM.
- After the first such write, reads from `09E00000..09FFFFFF` go to the cart
  one halfword at a time, uncached and never as a burst. The Omega DE keeps
  its version, SD status and sector data at `09E00000`; the EverDrive keeps
  its registers, including the SD_DAT FIFO, at `09FC0000`. The latch clears
  on reset.
- Cheat-engine traffic is not forwarded, so a ROM-patch cheat never writes
  to a cart or consumes a register read.
- The GPIO emulation at `080000C4..080000C8` keeps its writes when the game's
  quirk enables it.

**Do not accept the Omega DE's firmware update prompt** on any build unless
the version it reports is known to be correct.

`tools/sim/run_cart_rom.py` replays each cart's own register sequences, from
`ez-flash/omega-de-kernel` and the EverDrive X5 driver in
`afska/gba-flashcartio`, against pin models of both carts.
`tools/sim/run_cart_memorymux.py` checks forwarding, uncached reads, cache
invalidation and cheat-engine isolation through the real memorymux and cache.

## ROM timing

The non-sequential read needs turnaround between releasing the address bus
and asserting RD#. **Fast** failed on Zero Mission; the profiles with
turnaround booted. **Turnaround** remains the default. These cycle counts
describe the controller, not qualification on every cartridge:

| Profile | Turnaround, AD released before RD# | First RD# low | Burst halfword, RD# high/period | 8-byte line |
|---|---|---|---|---|
| 0 Fast | 0 | 24 clocks, 238 ns | 4/12 clocks, 119 ns | 640 ns |
| 1 Turnaround, **default** | 4 clocks, 40 ns | 24 clocks, 238 ns | 4/12 clocks, 119 ns | 720 ns |
| 2 GBA Power-On | 4 clocks, 40 ns | 30 clocks, 298 ns | 6/20 clocks, 199 ns | 1020 ns |
| 3 Slow | 8 clocks, 79 ns | 48 clocks, 477 ns | 8/24 clocks, 238 ns | 1360 ns |
| 4 Fast Burst | 4 clocks, 40 ns | 12 clocks, 119 ns | 3/8 clocks, 79 ns | 480 ns |

**Why profile 4 exists, 2026-09-10.** Audio from a cartridge ran slow and
inconsistently, dragging and catching up, while the same game from the SD
card was clean. That is the whole emulated machine running below realtime,
not an audio fault. The gamepak cache is 1024 lines of 8 bytes, 8 KB against
an 8 MB ROM, so misses are frequent and each one is a real cartridge
transaction that stalls the core. A real GBA fetches those 8 bytes in 595 ns
at `WAITCNT` 3,1, the setting games actually use; profile 1 takes 720 ns,
so the core loses time in proportion to ROM traffic and the audio follows.
Profile 4 does it in 480 ns, faster than the machine being emulated, so the
stall disappears rather than shrinking.

Confirmed on hardware 2026-09-10 on a Zero Mission cartridge: audio runs
clean on Fast Burst where it dragged and caught up on Turnaround.

**Turnaround stays the default, decided 2026-09-10.** Fast Burst is opt-in
and is meant to stay that way: it drives the bus faster than the hardware it
emulates, and it has been tried on one cartridge. Defaulting it would make
every cart session depend on a margin no cart promises. Do not promote it
without testing across several cartridges.

It is faster than a real GBA on purpose and is not guaranteed on every
cartridge. The address is latched 8 clocks before RD# falls, so a 150 ns
part still has about 200 ns to the sample, and a burst halfword is answered
from the cart's own address counter, where the ROM's OE access time rather
than its address access time is what has to be met. Turnaround stays the
default; profile 4 is opt-in and the other profiles remain the fallback.

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

The burst bench checks protocol, edge counts and the 128 KiB boundary
fallback. Its ROM model responds immediately, so it does not prove physical
read margin. Turnaround and Fast Burst have the hardware results stated
above; more cartridges need testing. `ROM_BURST=0` is a diagnostic fallback.

**ROM reads burst.** Words after the first in a read hold `CS#`
low and pulse `RD#` only, relying on the cartridge's own address counter.
The current controller bench measures 129 cycles per request without a burst
and 69 with a burst under its test parameters. The counter is 16 bits of
halfword address and wraps every 128K, so a read crossing that boundary falls
back to re-driving the address. If a cartridge turns out not to honour its own
counter, `ROM_BURST=0` in the controller restores the original path exactly.

**Remaining qualification:** physical SRAM/Flash save-write persistence,
interrupted transfers, empty-slot handling and Fast Burst across more
cartridges. There is no save-write toggle. See [HARDWARE.md](HARDWARE.md).
