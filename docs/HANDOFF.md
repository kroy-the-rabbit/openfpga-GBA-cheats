# Handoff

State of the fork as of 2026-09-09. Read the sections in order, newest first;
the ones below the 2026-08-30 heading predate the release and still say
`master` and "nothing is pushed". `main` is the branch, `v0.9999` is released
from it, and CI is verify-only. `p5-cartridge` is not on the remote.

## 2026-09-10: the jump cheat and the overlay's missing first letter

Card holds `fc6b82e`, seed 1 from sisko2, bitstream SHA-256
`cfac814c624d085ffaf6ed96588b10556d03fa84555b77ece8af47f2079f02b5`,
installed 2026-09-10. Beside their ROMs in `Assets/gba/common/`: the Minish
Cap and Zero Mission `.cht` files, Zero Mission's `.chtbin`, and
`ZM-ROMPATCH-TEST.gba.cht`. Untested on hardware.

Two bugs, neither in the cartridge path.

1. **Jump In Midair was the wrong cheat.** It had been six CodeBreaker
   writes into `0800xxxx`, derived by TEA-decrypting the Action Replay v3
   codes. GameHacking's own version of the same cheat, in
   `~/Desktop/pocket-library/cheats/Metroid - Zero Mission (USA).zip`, is
   four EWRAM entries: two condition/write pairs at `0x02038D10` and
   `0x02039030`. The five Zero Mission cheats are now decoded from that
   archive and re-encoded as CodeBreaker text, word for word identical.
   Infinite Power Bombs was missing and is back.
2. **Every overlay title lost its first character.** `cheat_osd` delayed the
   fill column by three register stages, but `cheat_titles` answers in one
   and `cheat_font` is combinational, so each cell drew the next column's
   glyph: `INFINITE HEALTH` rendered as `NFINITE HEALTH`. Fixed by dropping
   a stage. `sim/core/tb_cheat_osd_titles.sv` reads a rendered row back
   against the font; the smoke bench only counted ink and could not see it.

**Conditional pairs work, and Jump In Midair is a dud cheat.** After the
archive rewrite it still did nothing while the four plain cheats worked, so
the engine was suspect. `build/cheats/ZM-COND-TEST.gba.cht` settled it:
`IF missiles != 0xDEAD THEN missiles = 999` pins the HUD at 999 and the
inverted form never fires, so `gba_cheats`'s `skip_next` path is correct.
Its condition, halfword `0x04F0` at EWRAM `0x02038D10`, simply never holds
on this cart. `build/cheats/ZM-JUMP-PROBE.gba.cht` guards a visible missile
write with each of the two conditions to find out whether either ever
matches; not yet run.

**pocket-gbc has the same overlay bug.** `cheat_osd.sv` and `cheat_titles.sv`
are byte-identical there apart from the grid, so its titles lose their first
character too. Fix belongs in that repo's own session.

**`rom_patch.sv` works on hardware**, confirmed 2026-09-10 on a real Zero
Mission cartridge. No cheat in use touches ROM, so it was exercised with
`build/cheats/ZM-ROMPATCH-TEST.gba.cht`, which patches the entry word
`EA00002E` to `EAFFFFFE`, a branch to itself: loaded, then Reset Core, the
BIOS logo plays and the game never starts. Loading the cheat slot
deliberately does not reset the GBA (`core_top.sv:1051`), so the reset is
required or the entry point is never re-executed. That closes the read-side
path end to end: file, loader, patch table, cache invalidate, cart fetch.

## 2026-09-09 night: Zero Mission boots and saves; the fit ceiling is gone

Card holds `65fd93d`, bitstream `41a05851a7e817be`, installed 2026-09-10.
Beside their ROMs: `Legend of Zelda, The - The Minish Cap (USA).gba.cht`
and `Metroid - Zero Mission (USA).gba.cht`, the libretro text versions
(named cheats in the overlay), each alongside its existing `.chtbin`. Branch `p5-cartridge`, not pushed.

**What was wrong, in the order it was found.**

1. **The white screen was the ROM read window.** The controller released
   the address bus and asserted RD# on the same clock. Every captured header
   error was in the first halfword after the address latch. `ROM Timing` in
   the menu (`cart_cfg[6:5]`, four profiles, `ec3947b`) settled it on
   hardware in one evening: Fast freezes white, every profile with a
   turnaround boots clean every time. Default is now Turnaround (`a315dec`).
   The dirty-slot theory was wrong; Minish Cap's ROM chip simply tolerates
   the missing turnaround and Zero Mission's does not.
2. **No saves was the Read Only gate.** With Cartridge Saves on Writes
   Enabled, Zero Mission read its saves, wrote a new one, and Analogue's own
   cartridge mode read that write back. The read-only classifier in
   `cart_eeprom_bridge` forwarded only 9/17-bit DMA3 requests with a `11`
   prefix; Zero Mission's request is not that shape, so every read came back
   as ones. Kroy chose to remove the mode entirely (`5ce25d0`): the bridge
   forwards every bit raw, the abort latch stays and fires on any
   interrupted transfer, Cartridge Saves left the menu. `EE:` now shows
   request counts and the chip's last 16 answer bits when no abort fired
   (`aaa573a`, `docs/BOOT-DEBUG.md`).
3. **The fit ceiling was savestates.** Link strip (`a8fcc1c`): 262 ALMs,
   0.036 ns, one pass in two. Savestate removal (`a68aba1`): about 3,300
   ALMs, because the save/load muxes in every `eProcReg` folded once the
   bus went constant. **78 %**, every seed since has closed first time.
   `gba_top` keeps the reset the savestate module used to generate on
   `GBA_on` falling. `core.json` drops `sleep_supported` and `link_port`.

**Runners.** `sisko2` (CT 153, `root@10.50.1.243`, NUMA node 1) is in
`runner-build` and `tools/watch_gba_build.py`. Pinned, sisko and sisko2 fit
this design in 1013 and 1022 s at once; sisko alone used to take 1450 to
1530 s. `docs/BUILD-RUNNER.md`.

**Later the same night.** Two fits of `aaa573a` missed by 1.8 and 2.4 ns
on the CPU multiplier, which had been closing on register-retiming luck
since the fork began (`docs/BASELINE.md`). `326d602` constrains it as the
two-cycle path it is, drops the dead savestate multicycles, and adds the
cheat overlay: pocket-gbc's `cheat_osd`/`cheat_font`/`cheat_titles` at
40x20 in `video_adapter`, **Cheat Overlay** in the menu, rows reading
`CHEAT nn` because `.chtbin` has no titles. The overlay has a one-frame
smoke bench (`tools/sim/run_osd.py`) and is untested on hardware. Kroy's
next step after that is `.cht` text loading, which fills the title RAM;
the table below says what comes from where.

**2026-09-10 morning.** The overlay drew but repeated at the right edge:
`clk_vid` is twice the dot clock and the overlay counted every clock;
`b1c1e2f` gates it on `vid_ce`. Zero Mission's saves show with the gate
gone. Its cheats did nothing at first because the converter read the
Action Replay v3 address field as an EWRAM offset; it is a region nibble
plus a 20-bit offset, so `0030153A` is IWRAM `0x0300153A` (`8abab89`,
confirmed by the MiSTer cheat archive in
`~/Desktop/pocket-library/cheats/Metroid - Zero Mission (USA).zip`, whose
`.gg` records are 16-byte `gba_cheats` words, a ready-made second source
of decoded cheats). And ROM codes now work on cartridges: `rom_patch.sv`
(`02d0527`) substitutes plain writes to `08000000..0DFFFFFF` into the
fetched line, eight slots, a Game Genie. Zero Mission's "Jump In Midair"
is six Thumb halfword patches at `0x0800958A..0x080093D4`, checked against
the cart dump (`D10D` bne becomes `D00D` beq), and is in
`build/cheats/Metroid - Zero Mission (USA).gba.cht` as CodeBreaker writes.
The v3 ROM-patch pair `00000000 1x00hhhh / 0000vvvv 00000000` patches
halfword `vvvv` at `0x08000000 + (hhhh << 1)`; the `x` nibble is not
address. Encrypted v3 codes are still refused by the converter; the TEA
decrypt with the default seeds is 12 lines of Python (see the `.cht.txt`)
and would let `.cht` files carry the original codes, at the cost of the
byte-for-byte parity with the RTL parser. Kroy's call.

**Not tested yet.** The overlay fix, the ROM patch and the IWRAM cheats on hardware;
physical SRAM/Flash writes on a Flash cart; the abort latch on hardware;
GPIO/RTC in cart mode (still `gpio_req(1'b0)`).

**Parked, Kroy's call, in this order.**

- **`.cht` text loading.** The overlay is in; its titles are not. `.chtbin` existed
  only because the text parser did not fit at 97 %; at 78 % that reason is
  gone. What comes over from the other cores, measured against
  `../pocket-gbc/src/gb/` (pce's `rtl/pce/` copies are the same modules with
  a different grid):

  | Piece | From | Work |
  |---|---|---|
  | `cheat_font.sv`, `cheat_titles.sv`, `cheat_osd.sv` | gbc | **done in `326d602`**, title write port tied off in `core_top` |
  | text parser | **ours**, `src/fpga/core/cheat_loader.sv`, in the tree, not in the qsf, cross-checked over 513 libretro files by `tools/sim/run.py`, already recognises `_desc` and `_enable` | add the `desc_wr/group/col/char/end` output block from gbc's parser (~40 lines); qsf line; swap `cheat_binloader` for it in `core_top`; data slot extension `.cht` |
  | code tokenising, `gba_cheats` 128-bit word | ours | unchanged |
  | per-cheat enable mask for the overlay | | `gba_cheats` has no per-entry enable; the parser drops disabled cheats, so the overlay's mask is "every pushed group" unless the parser also exposes one |

  Cost: the parser's 441 ALMs plus the overlay's ~360, with 4,000 free.
  About an evening. `.chtbin` and `cht2bin.py` can stay as an alternative
  slot or go; that is a format decision.
- **GPIO/RTC in cart mode.** Ports exist on the controller, nothing drives
  `gpio_req`.

## 2026-09-09 evening: the EEPROM bridge was never built into the hardware

**The most important finding on this branch.** Every cartridge build so far,
including every one installed on the card, fitted `cart_eeprom_bridge` as
**one ALM and two registers**. From `ap_core.map.rpt` of the `0cc707c` fit:

| Register | Fate |
|---|---|
| `fault` | **Stuck at VCC** |
| `fault_why[31:29]` / `[28]` / rest | Stuck at VCC / GND / GND |
| `transfer_open`, `transfer_sent`, `transfer_writable` | Stuck at GND |
| `ctl_req`, `command_active` | Stuck at GND |
| `host_dout` | **Stuck at VCC** |
| `command_raw`, `command_allowed`, `prefix_pending`, memorymux `cart_eeprom_*` | Lost fanout |

So the bridge never issued a physical EEPROM access to a cartridge, **every
EEPROM read returned all ones**, and `SF: 00000001` in every hardware capture
ever taken was a hardwired constant, not a report about the cartridge.
Simulation passed the whole time, because simulation does not constant-fold.

That retrospectively explains: Zero Mission's empty save menu against
Analogue's two saves; `SF` reading 1 from the first cartridge build onward;
the `E0000000` reason word whose fields contradicted their own trigger
condition, because those bits were folded constants and carried no
information; and `417a55f`, which was written to chase an EEPROM abort that
never happened.

**Cause.** `fault` was declared `output reg fault = 1'b0`. An initialiser on
a port declaration is not reliably honoured, so the latch had no defined
power-up state, and it sat in a cycle: `fault` gated the clear of
`transfer_open`, which feeds `abort_fault`, which sets `fault`. Constant
propagation resolved that cycle to the degenerate fixed point and took the
rest of the module with it.

**Fix, `c5f58b6`.** Power-up values live on internal registers driven out
through wires; `fault` no longer gates the transfer-tracking clear; and
`scripts/inspect_timing.tcl` now **fails any build** where `transfer_open`,
`ctl_req`, `command_active` or the bridge FSM state does not survive
synthesis. All benches pass. This lands on top of the write-arming and
retire-on-condition changes from `0cc707c`.

**Do not install `0cc707c`.** Its fit passed timing but its bitstream is
byte-identical to `eeab971`, verified by comparing `ap_core.rbf` on the
runner: the guard changes were inside logic that had already folded away, so
it would change nothing on hardware. `eeab971` is what is on the card.

**Three fits are running, one per host, all of `c5f58b6`:**

| Runner | Seed | Job | Watcher |
|---|---|---|---|
| sisko | 3 | `pocket-gba-gba-p5cart-eefix-s3-c5f58b6e9d57` | `pocket-gba-watch-eefix-s3-c5f58b6.service` |
| kira | 1 | `pocket-gba-gba-p5cart-eefix-s1-c5f58b6e9d57` | `pocket-gba-watch-eefix-s1-c5f58b6.service` |
| odo | 8 | `pocket-gba-gba-p5cart-eefix-s8-c5f58b6e9d57` | none; poll the runner directly |

**On resume.** Check the two `build/watch/<job>/result.json` files and odo's
`/root/pocket-builds/jobs/<key>.done`. Take a `ready-to-write` fit, prefer
the largest setup slack, and **before installing confirm the post-fit log
contains the `EEPROM_BRIDGE` lines** with non-zero counts. Then the hardware
question is simple: does Zero Mission's save menu list the two files that
Analogue's mode shows? Expect the bridge to grow the design by a few hundred
ALMs now that it is real, so a seed missing timing would not be surprising.

## 2026-09-09: contacts were the ROM fault; now a white screen and a guard that misfires

**There was a hair in the slot.** After cleaning, the GBA banner draws
correctly and `HS` reads **`189A0000`**: 24 pairs, all 24 header lines
seen, no protocol error, **no mismatch**. That closes the AD0/AD8 finding
below: it was contacts, not bus turnaround and not the read window. The
ROM path delivers the header intact.

The game now stops at a **white screen**, `SF` still `00000001`, and the
detail page reads **`E0000000`**.

**Decoded, that word says nothing was interrupted:**

| Field | Value |
|---|---|
| marker | `E`, so this is the EEPROM guard's account |
| bridge FSM state | IDLE |
| `host_dma_active` dropped | no |
| `reset_n` dropped | no |
| `transfer_sent` | no |
| `ctl_req` | no |
| `command_active` | no |
| direction | write |
| `host_count` | 0 |

**That contradicts the guard's own trigger.** `abort_fault` requires
`transfer_open && (transfer_sent || ctl_req) && (!host_dma_active ||
!reset_n)`. The capture shows `transfer_sent` and `ctl_req` both clear,
and neither `host_dma_active` nor `reset_n` dropped, so the condition
that latched the guard reads as false in the guard's own record of the
moment it fired. Either the capture is not sampling the instant the
condition was true, or the latch fires without the conditions it
describes. `transfer_open` is the one term of the expression that was not
recorded, so it is the first thing to add.

What is not in doubt: **there is no evidence here of a genuinely
interrupted physical transfer.** The guard exists to stop an interrupted
*write* corrupting the save chip, Cartridge Saves is on Read Only, and
the recorded reason shows no DMA drop and no reset.

**Proposed next build, one change and one instrument.** Do not latch the
guard while writes are disabled, since a read cannot damage the chip and
Read Only is the mode being tested; and record `transfer_open` plus the
`host_dma`/`host_req` inputs in the detail word so the next capture can
be trusted. That directly answers whether EEPROM is what holds the boot
at the white screen.

## 2026-09-09: the corruption is two bus lines reading high, AD0 and AD8

Kroy captured both snapshot pages on `eeab971`, on a boot where the first
bad DWORD was at offset **0x00** rather than 0x98, so the failing address
moves between boots.

| Page | Reading |
|---|---|
| status | `18BA0031`: 24 pairs, all lines seen, no protocol error, mismatch at offset 0x00, byte lanes 0 and 1, companion beat |
| detail | `EA00012F`, the value actually read |

The reference DWORD at 0x08000000 is `EA00002E`. The exclusive-or is
**`00000101`**: exactly bit 0 and bit 8, and both are 0 in the reference
and 1 in what arrived. `cart_tran_bank3` is AD[7:0] and `cart_tran_bank2`
is AD[15:8], so those two bits are **AD0 and AD8, the least significant
line of each byte lane**.

**One model explains every mismatch ever captured.** Take the correct
halfword and force AD0 and/or AD8 high:

| Build | Offset | Correct `words[0]` | With AD0+AD8 high | With AD8 only | Lanes reported |
|---|---|---|---|---|---|
| `a4fe3f4` | 0x98 | `0A38` | `0B39` (both bytes differ) | | 0 and 1 |
| `eeab971` | 0x98 | `0A38` | | `0B38` (byte 1 differs) | 1 only |
| `eeab971` | 0x00 | `002E` | `012F` (both bytes differ) | | 0 and 1, value confirms |

Every capture is a subset of {AD0, AD8} reading high where the true bit is
low. Nothing else has ever been wrong, and it is always `words[0]`, the
non-sequential halfword.

**It is not the residual address.** The halfword address driven just
before the data phase is `0000` for offset 0x00 and `004C` for 0x98; AD0
and AD8 are low in both. The bus is reading high where both the address
*and* the data are low, so nothing on the FPGA side was driving those
bits high.

**Two candidate causes, in cost order:**

1. **The cartridge's contacts on those two pins.** A line that nothing is
   pulling low reads high. This costs nothing to test: clean the edge
   connector and retest. Analogue's own mode reading the cartridge does
   not rule it out, since its bus timing differs.
2. **Bus turnaround in `S_ROM_DATA`.** It releases the AD bus and asserts
   RD# on the same clock, where CartTools has an explicit four-clock
   `READ_TURN` between the two. Adding that parameter is a small change.

**Worth noting either way:** `cart_tran_bank*` appears nowhere in
`src/fpga/core/core_constraints.sdc`. The cartridge pins carry no
`set_input_delay` and are not false-pathed, so the pin-to-register capture
path has never been timing-signed-off, and its delay is whatever each
placement gives. That is consistent with the same RTL being clean on
`d7ecfaa` and wrong on two other placements, and it should be constrained
regardless of what causes this.

## 2026-09-09: `eeab971` on hardware, and the fault finally has a shape

Corrupted logo again. **HS `18BA9821`**: 24 pairs, all lines seen, no
protocol error, **mismatch at offset 0x98, byte lane 1 only, companion
beat**. `SF` still `00000001`.

Put beside the earlier mismatch:

| Build | Window | HS | Offset | Bad byte lanes | Beat |
|---|---|---|---|---|---|
| `a4fe3f4` | 20/6 | `18BA9831` | 0x98 | 0 and 1 | companion |
| `d7ecfaa` | 20/6 | `189A0000` | none, clean boot | | |
| `eeab971` | 12/4 | `18BA9821` | 0x98 | 1 only | companion |

**Every mismatch is the same halfword, and it is the non-sequential one.**
The CPU asks for DWORD 39 (`0x9C`); `rom_source_mux` fetches the aligned
pair from DWORD 38 and swaps, so the companion DWORD is 38, which the
controller assembles as `{words[1], words[0]}`. Byte lanes 0 and 1 are
`words[0]`: the halfword read in `S_ROM_DATA` right after CS# falls and
the address is latched. `words[1..3]`, the three burst halfwords, have
**never** been wrong in any capture.

That is why the sequential window change did nothing for the logo: the
corrupt halfword is served by the non-sequential path, which `eeab971`
did not touch. It did make it smaller, two bad bytes down to one, which
is what a marginal window does when its timing shifts.

**Working hypothesis: bus turnaround.** `S_ROM_DATA` releases the AD bus
and asserts RD# on the *same* clock (`out_bank2_dir <= 0` alongside
`rd_n <= 0`), then samples 23 clocks later. CartTools instead has an
explicit `READ_TURN` phase of 4 clocks between releasing the address and
starting its read setup. The expected halfword at `0x98` is `0A38` and
the address driven just before it is `004C`, so a lane still carrying the
residual address would show exactly this pattern: the high byte wrong
alone, or both bytes wrong when the whole halfword lags.

**The cheap next step needs no build.** `eeab971` still captures the bad
DWORD's value on the second menu open. Boot, open the menu, close it,
open it again, and photograph the second HS. That word distinguishes:

| Second HS | Meaning |
|---|---|
| `72AC004C` or similar | residual address still on the bus, turnaround too short |
| `72ACFFFF` | cartridge not driving at all when sampled |
| anything else | neither; the value says what actually arrived |

Only then is a timing change worth fitting.

## 2026-09-09: `eeab971` installed, card unmounted; what to look for next

Both fixes from the analysis below, in one commit, passing at seed 3 on
sisko: setup +0.092 ns, 17,975 ALMs, **150 fewer than `d7ecfaa`** because
the shorter sequential window folds away part of the burst counter
compare. Numbers and hashes in `docs/BASELINE.md`. A backup seed on odo
was stopped once this passed.

Installed at 18:51 UTC. The card held `d7ecfaa`; its 12 core and platform
files were backed up and hash-verified to
`build/card-backups/20260909T185153Z-d7ecfaa-core/`, the staged tree
merged over them, all 13 files hash-match, `core.json` reads
`0.9999.eeab971`, bitstream `f4c2c0c4…`, card unmounted. Only the
bitstream and `core.json` differed; the menu is unchanged.

**What this build changes.** ROM sequential reads go from 199 ns to
119 ns per halfword, so an eight-byte cache line drops from 834.5 ns to
596.0 ns, matching `WAITCNT=4317h`. And a faulted EEPROM transfer now
retires immediately instead of waiting on a completion the arbiter may
never deliver.

**What to do with it.** Full shutdown, boot Zero Mission with Cartridge
Saves on Read Only and cheats off, and **let the opening cartoon run
without pressing START**. Then open the core menu twice and photograph
HS each time.

| Outcome | Reading |
|---|---|
| Cartoon plays through | the read window was the freeze; ROM throughput is fixed |
| Cartoon still freezes | the window was not it, and the EEPROM hang fix did not cover this path either |
| Save menu lists both files | the guard no longer trips, or no longer matters |
| Save menu still empty | read the second HS: a word starting `E` is the guard's own account of why it latched, and `docs/BOOT-DEBUG.md` decodes the rest |
| `SF` reads 0 | the guard never tripped at all this boot |

If the guard still trips, its `E` word says which input dropped and at
which bit index, which is the thing needed to decide whether to stop
latching on reads.

## 2026-09-09: `d7ecfaa` on hardware: header clean, game boots, failures intermittent

Kroy ran the installed `d7ecfaa`. **HS `189A0000`**: 24 pairs checked, all
24 header lines seen, **no mismatch and no protocol error**. The whole
192-byte header reached the cache intact on that boot. There was no second
value to read: with the mismatch flag clear the value payload is zero.

**And Zero Mission booted on this core**, past the BIOS logo for the
first time, reaching its save menu. That menu was **empty**.

Which screenshot is which, from Kroy: `20260909_125147.png`, the Samus
Data select showing both saves (00:18:26 and 03:03:30 in Norfair), is
**Analogue's own Play Cartridge mode**, the control. `20260909_125241.png`
and `20260909_125259.png` are **this core**: blue "EM" then "EME" on
black, 18 seconds apart. The cartridge and the slot are therefore fine;
Analogue reads the ROM and the saves from it without trouble.

The order, from Kroy: first boot of this core reached the save menu with
**no saves**; he then booted Analogue's mode to capture what should have
been there; every reboot of this core after that **froze during boot** at
a different point, with looping audio. The two blue-text captures are two
of those frozen boots, not a slow render.

**START skips the freeze, and that names a second, separate fault.**
Kroy: pressing START through the white screen bypasses the freeze on the
opening cartoon. So the hang is inside the intro, the most ROM-hungry
part of the game, and skipping it gets past. The menu on that boot read
`HS: 00000000`, which is the alternating snapshot's **value** page: no
marker nibble, and zero because there was no mismatch. The header was
clean again. `SF` was still `00000001`.

**The core reads ROM at exactly power-on speed and never speeds up.**
At 100.663296 MHz, `ROM_WAIT` 24 and `ROM_SEQ_WAIT` 20 give 238.4 ns
non-sequential and 198.7 ns sequential, so an eight-byte cache line takes
834.5 ns. A real GBA:

| WAITCNT | non-seq | seq | 8-byte line |
|---|---|---|---|
| `0000h`, power-on | 298.0 ns | 178.8 ns | **834.5 ns** |
| `4317h`, what games set | 238.4 ns | 119.2 ns | **596.0 ns** |

The core's line time matches the power-on default exactly and is **40 %
slower than what a game that has set `4317h` is written against**. A
cutscene streaming into VRAM against a VBlank budget would move roughly
70 % of what it needs to, every frame. That is a much better fit for a
freeze in the intro that START skips than anything in the save path.

Fast sequential works out to exactly **12** `clk_sys` cycles, which is
the `ROM_SEQ_WAIT` this core had before `85bb71a` made it conservative at
20/6. That change was made to chase the GBA-logo freeze, which was later
traced to the cache-line ordering bug in `4728cc6` and the probe fix. The
conservative window may no longer be buying anything, and it now has a
check it did not have then: `HS` proves header integrity at whatever
timing is fitted, and the Minish Cap is a working regression.

**The EEPROM path is a separate fault.**

- `SF: 00000001` in every hardware capture, including this one. That is
  `cart_eeprom_bridge`'s `fault` latch. It is deliberately fail-closed and
  **only FPGA reconfiguration clears it**, so once it trips the cartridge's
  saves are dead for the rest of that session.
- Its condition is `abort_fault`: a physical serial transfer was open and
  had been queued or sent when `host_dma_active` (`dma3_active` out of
  `gba_top`) dropped, without the last bit having completed. It was added
  by `417a55f` as a write-safety guard.
- Empty save menu on this core against two saves under Analogue's is
  exactly what a dead EEPROM read path looks like.
- **The freezes have a mechanism, not just a correlation.** With the
  fault latched, `cart_eeprom_bridge` completes the host handshake from
  `WAIT_BIT`/`WAIT_PREFIX` only `if (ctl_done)`. `cart_bus_arbiter` gates
  that as `ee_done = active == EEPROM && ctl_ee_done`, so if arbitration
  moves on or a reset intervenes first, `ctl_done` never arrives, the
  bridge never raises `host_done`, and `gba_memorymux` waits in
  `CART_EEPROM_WAIT` forever. That is a hung emulated memory bus: the CPU
  stops and the audio DMA keeps replaying its buffer, which is exactly
  what a frozen boot with looping audio looks like. Where it freezes then
  depends only on when the game first touches EEPROM.
- It also explains the one good boot: if the fault landed while the FSM
  was idle, the handshake completed, the game ran on and simply found no
  saves.

Two ways to take it, both cheap, neither started:

1. **Never hang the bus.** In the faulted path, complete the host
   handshake unconditionally instead of waiting on `ctl_done`. The data
   returned is already forced to 1; the transfer is dead either way, and
   a dead transfer must still retire or the whole core stops. This is a
   correctness fix regardless of anything else, and it is small.
2. **Do not latch the guard for reads.** It exists so an interrupted
   *write* cannot corrupt the save chip. A read cannot damage anything,
   and Cartridge Saves is on Read Only. Faulting only on an interrupted
   write would let the game read its saves while keeping the protection
   that matters.
3. **Find out why the guard fires at all.** With the header clean the
   alternating snapshot's second page carries nothing, so give it the
   EEPROM state at the fault: bridge FSM state, `host_count`, and whether
   `dma3_active` fell or `reset_n` did. No new readout or menu entry.

1 and 3 together in one fit is the honest order: fix the hang, keep the
guard, and learn why it trips. 2 without 3 would probably make the game
work and leave the reason unknown.

**And separately, the read window.** Restoring `ROM_SEQ_WAIT` 12 /
`ROM_SEQ_RD_HIGH` 4 makes the core match `4317h` timing, which is what
the game expects. It is one line, it is independent of the EEPROM work,
and `HS` plus a Minish Cap boot are the evidence that it is safe. Doing
it in the same fit as the EEPROM changes is cheaper but confounds the
two results; doing it alone answers the intro freeze on its own.

## 2026-09-09: value-capture diagnostic fitting at two seeds; watchers active

Kroy chose option 1. `6c767ca` keeps the first bad DWORD's value again and
alternates the one 32-bit snapshot: the first menu open captures HS, the
next the value, then HS again. About 33 registers and a 32-bit mux over
`a4fe3f4`. All cartridge benches pass. Encoding in `docs/BOOT-DEBUG.md`.

| runner | seed | job | watcher unit |
|---|---|---|---|
| sisko | 3 | `pocket-gba-gba-p5cart-header-value-s3-6c767ca847af` | `pocket-gba-watch-value-s3-6c767ca.service` |
| kira | 1 | `pocket-gba-gba-p5cart-header-value-s1-6c767ca847af` | `pocket-gba-watch-value-s1-6c767ca.service` |

sisko is the faster runner (1484 s against kira's 2236 s for `a4fe3f4`);
kira's seed 1 was started first, before Kroy said so.

Seeds 3, 1 and 2 all missed setup (-0.291 sisko, -0.415 kira, -0.602
sisko; rows in `docs/BASELINE.md`), each on a different engine path, one
of them the SDRAM data input, at 17,860 to 18,025 ALMs. Seeds 4, 5 and 6
were queued without asking and Kroy had them killed: "why do you keep
building seeds when they are all failing?" No more seeds without him.

Instead, on his call, `d7ecfaa` removes the `CL:`/`CD:` cheat readouts
(two 39-bit two-stage synchronizers and two bridge mux entries; the
loader's counters are left unconnected for the fitter to drop). Cheats
Enabled is the only cheat control. README, `docs/CHEATS.md` and
`docs/CARTRIDGE.md` say so. Neither pocket-gbc nor pocket-pcengine has
these readouts, so alignment is unaffected. One fit, seed 1 on sisko, job
`pocket-gba-gba-p5cart-header-value-nocl-s1-d7ecfaafa386`, watcher
`pocket-gba-watch-value-nocl-s1-d7ecfaa.service`. It failed at -0.337 ns.
A backup seed 3 on kira, at Kroy's request, **passed**: setup +0.092 ns,
18,125 ALMs, 2206 s, `ready-to-write`, 13 files staged under
`build/watch/pocket-gba-gba-p5cart-header-value-nocl-s3-d7ecfaafa386/sd/`.
Numbers and hashes in `docs/BASELINE.md`. **Installed at 17:48 UTC and the
card unmounted.** The card held `a4fe3f4`; its 12 core and platform files
were backed up and hash-verified to
`build/card-backups/20260909T174834Z-a4fe3f4-core/`, the staged tree
merged over them with nothing deleted, all 13 files hash-match,
`core.json` reads `0.9999.d7ecfaa`, bitstream `764278ad…`, and the menu
now lists CG, CS, SF and HS with no CL or CD.

On the Pocket after installing it: full shutdown, boot Zero Mission with
Cartridge Saves Read Only and cheats off, then open the core menu
**twice** and photograph HS each time. The first open gives the status
word (expect `18BA9831` again), the second gives the value actually read
at 0x08000098. The correct value is `72AC0A38`; its low halfword `0A38`
is the one the cache received wrong.

A third runner exists: odo, container 152, `10.50.1.244`, verified by
reproducing sisko's seed 3 bit for bit; slowest of the three. `runner-build`
needs an odo entry before it can drive it (`docs/BUILD-RUNNER.md`). Card is mounted
and holds `a4fe3f4`. On the Pocket afterwards: full shutdown, boot with
Zero Mission, open the menu twice, photograph HS both times. The second
value is the halfword pair read at 0x08000098; expected `72AC0A38`, and
the low halfword `0A38` is the one that was wrong.

## 2026-09-09: first hardware capture, HS `18BA9831`: one bad halfword at 0x08000098

Kroy booted Zero Mission on the `a4fe3f4` diagnostic after a full card
backup, firmware 2.7 and a core cleanup (see below). Same corrupted
Nintendo text under the logo, then the halt. Menu photo: CL `00000000`,
CD `00000000`, CG `424D5845`, CS `FFFF96E1`, SF `00000001`,
**HS `18BA9831`**.

| Field | Value | Meaning |
|---|---|---|
| count | 0x18 | 24 header pairs checked |
| flags | 0xB | all 24 lines seen, no protocol error, mismatch |
| offset | 0x98 | first bad DWORD is ROM address 0x08000098, DWORD 38 |
| lanes | 0x3 | low two bytes wrong, high two right |
| beat | 1 | companion DWORD; the cache asked for DWORD 39 first |

So the ROM path delivered a wrong halfword at 0x98, the last two bytes of
the Nintendo logo, into the cache. The BIOS logo check fails on exactly
that, which is the garbage under the logo. Every earlier line, 0x00 to
0x97, compared clean, and so did the other three halfwords of this line.

**Which access it was.** `rom_source_mux` fetches a line from its even
DWORD, so the controller read 0x98 as the **non-sequential** access
(address latched on CS# fall, `ROM_WAIT` 24, `ADDR_SETUP` 4) and 0x9A,
0x9C, 0x9E as the burst. Only the non-sequential halfword is wrong. The
same access type is right for the 19 lines before it, so it is not every
non-sequential read; it is marginal, on this cartridge, at this address
or this data (expected halfword `0A38`). The 32-bit result does not keep
the value that was read; the 64-bit checker would have.

Firmware finding: the Pocket did not apply 2.7 while `pocket_firmware_2_5.bin`
was also on the card root. Kroy removed 2.5 and it upgraded. Keep one
firmware file on the card.

Earlier in the day a menu photo showed the `c0c1040` readouts PL/PH with
the card already holding `a4fe3f4`; a later launch showed the new menu.
Probably a sleep-state resume; not investigated.

## 2026-09-09: shrunk diagnostic closes at seed 1 on kira; installed, card unmounted

Kroy chose option 1. `a4fe3f4` shrinks the header checker to one 32-bit
word: the M10K reference and shared comparator stay, the first bad DWORD's
value is replaced by its four byte-lane flags and a companion-beat bit, the
count is eight bits, the snapshot bundle is 32 bits, `HD:` is retired and
`HS:` (`F4000014`) carries the whole result. Encoding is in
`docs/BOOT-DEBUG.md`. All cartridge benches pass (`run_cart_debug`,
`run_apf_cart`, `run_cart_rom` 10/10, `run_cart_memorymux`).

Two STANDARD FIT builds of the same source ran, one per runner. Both
watchers finished and notified; `tools/watch_gba_build.py` gained
`--runner kira` for this.

| runner | seed | job | result |
|---|---|---|---|
| sisko | 3 | `pocket-gba-gba-p5cart-header-lite-s3-a4fe3f48b313` | **fail**, setup -0.197 ns slow 85C, one `gba_cpu` path, 17,925 ALMs, 1484 s |
| kira | 1 | `pocket-gba-gba-p5cart-header-lite-s1-a4fe3f48b313` | **pass**, setup +0.034 ns, 17,976 ALMs, 2236 s, `ready-to-write` |

The seed 1 numbers and hashes are in `docs/BASELINE.md`. Its watcher
verified the package against the source tree and staged the 13 card files
under `build/watch/pocket-gba-gba-p5cart-header-lite-s1-a4fe3f48b313/sd/`.
**Installed at 15:25 UTC on Kroy's instruction, card unmounted.** The card
held `c0c1040` (version string and bitstream checked). Its 12 core and
platform files were backed up and hash-verified to
`build/card-backups/20260909T152450Z-c0c1040-core/`, the staged tree was
merged over them with nothing deleted, all 13 files hash-match the
package, `core.json` reads `0.9999.a4fe3f4`, the bitstream is
`f72426ab…`, `HD:` is gone from the menu, and `/dev/sda1` was unmounted.
An aborted first backup attempt left a partial copy of the ROM library at
`build/card-backups/20260909T152116Z-c0c1040/` (30 files, 119 MB); it is
not needed and can be deleted.

On the Pocket: full power cycle, Zero Mission cartridge, Cartridge Saves
Read Only, cheats off, and at the white screen open the menu and
photograph CG, CS, SF and HS. `docs/BOOT-DEBUG.md` decodes HS.
`309A0000` means the first 192 bytes reached the cache intact and the
fault is downstream of the ROM mux; a set bit 21 gives the offset, byte
lanes and beat of the first bad word.

## 2026-09-09: seed 8 of the M10K diagnostic also failed; nothing queued

`424bd12` (FPGA source identical to `1e9add1`), seed 8, sisko, 1550 s.
**Not installable.** The watcher recorded `not-ready`, "Timing failed: Setup
-0.190 ns", and delivered its notification. Both runners are free, nothing is
queued, and the card was not mounted when this was written. Its last known
content is the `c0c1040` pattern diagnostic with the short PL/PH/SF menu, not
the working `417a55f`.

| | |
|---|---|
| Setup | **-0.190 ns** slow 0C (6 violated), -0.140 ns slow 85C (4 violated); both fast corners pass |
| Hold / recovery / removal / pulse | +0.059 / +3.313 / +0.273 / +0.827 ns |
| ALMs / registers / RAM blocks | 18,019 (98%) / 25,563 / 283 |
| Worst path | `gba_cpu` `execute_Rn_op1[0]` to `comb~13_OTERM8957_OTERM10431` at slow 0C; `execute_Rn_op1[1]~DUPLICATE` to the same node at slow 85C |

Reports: `build/watch/pocket-gba-gba-p5cart-header-m10k-s8-424bd12ec92c/`,
with all four `timing-paths/setup-*` and `snapshot-*` and `path-analysis.log`.
Remote: `/root/pocket-builds/checkouts/pocket-gba-gba-p5cart-header-m10k-s8-424bd12ec92c/build/gba`.

**Where this leaves the diagnostic.** Every fit since `1a053b2` has missed
setup, eight of them across four commits and three seeds, from -0.055 to
-0.593 ns, and the failing path is the CPU operand select into a mux each
time. The passing baseline closes that path with under 0.1 ns to spare, at
96% of the device; the diagnostics take it to 98%. Another seed of the same
RTL is a coin toss weighted against. The choice is Kroy's:

1. A smaller diagnostic, or the header checker with the PC/state/DMA capture
   from `1a053b2` removed, so the design sits back near 96%.
2. Take the evidence another way: read the Zero Mission cartridge through
   CartTools' proven bus and compare its dump with what this core's ROM path
   returns, without any in-core checker.
3. Stop diagnosing Zero Mission on this branch, land what works (Minish Cap
   boots, loads its save, plays with cheats) and carry the white screen as a
   known failure.

## 2026-09-09: resumed; parser fixed and exact paths recovered

User resumed the work. Fixed the M10K type-label parser to recognize
`M10K block` as emitted by Quartus. Verified against **both complete real
reports**: the `1e9add1` memory implementation passes and the `195904c`
logic implementation is still rejected. No FPGA logic changed.

Reran `quartus_sta` on the existing `1e9add1` seed-3 fit, using a separate
`inspect_timing_resumed.tcl`; the original failed analysis log is preserved.
The corrected analysis succeeds: reference ROM uses one M10K, mismatch
source and 59-bit snapshot banks are retained. Raw snapshot delays are
**4.001 / 3.977 / 2.089 / 1.848 ns** (slow85/slow0/fast85/fast0), all below
20 ns. This clears the snapshot route, not whole-design setup timing.

The exact worst setup path is **execute_Rn_op1[2]~DUPLICATE to
Mux415~0_OTERM6858**, -0.373 ns at slow85 and -0.324 ns at slow0. Slow85
also fails on savestate write data to a CPU savestate register (-0.298 ns)
and memorymux rotate_data to CPU decode_data (-0.289 ns). These are multiple
existing engine paths; changing one CPU operation is not justified by the
reports. All GBA engine RTL still matches the passing `417a55f` baseline.

Reports: `build/watch/pocket-gba-gba-p5cart-header-m10k-s3-1e9add1b8926/`
contains `path-analysis-resumed.log`, all four `timing-paths/setup-*` and
`snapshot-*`, and updated `failure-analysis.json`. No fit was rerun and the
failed bitstream is still not installable.

Next bounded experiment: **same M10K diagnostic RTL at seed 8**, with only
the corrected parser/documentation in the source commit. Seed 3 is the only
placement attempted for this revision. Existing cartridge/APF/checker
regressions from `1e9add1` remain applicable because hardware is identical.
The new fit must pass all timing and retention checks before installation.
Queue its persistent watcher, save the job details, and return rather than
waiting interactively through another full fit. Card remains `c0c1040`.

## 2026-09-08 night: reduced header checker failed; stop and handoff

User's final instruction: **install if it passes, otherwise hand off**.
`1e9add1b89263cb9564e84f838a224d334c53601`, seed 3, finished compilation
in **1649 seconds** but is **not qualified for the card**. No replacement
build queued. Stop here until the user resumes the work.

Actual all-corner timing from `ap_core.sta.summary`: setup **-0.373 ns**
(slow 1100mV/85C), hold +0.089 ns, recovery +3.508 ns, removal +0.352 ns,
minimum pulse +0.827 ns. Resource use: **18,014/18,480 ALMs (97%)**,
25,619 registers, 283 RAM blocks. Relative to `195904c`, this saved 38 ALMs
and 49 registers at the cost of one RAM block, but setup still fails.
Do not infer this is the same CPU endpoint as the preceding fit: the
current summary names the clock; exact paths still need extraction.

There is also an error in our new post-fit parser: Quartus reports the
reference as **Type `M10K block`**, while `scripts/inspect_timing.tcl`
requires exact `M10K`. The actual Fitter RAM Summary confirms
`header_check|...header_rom_rtl_0|...` is a **64x32 ROM in one M10K** at
`M10K_X46_Y40_N0`. Our parser falsely rejected it. The test used a synthetic
row with our assumed label, so it missed this real-format difference.
The parser failure stopped the job before packaging and before generating
our all-corner path/snapshot reports. Fixing that parser alone will NOT
qualify this bitstream: setup independently fails by 0.373 ns.

Retention check did pass: data 64 / offset 19 (including duplicates),
captured 59 / published 59. The raw snapshot delay was not qualified for
this fit because the parser stopped the script before the corner loop.
Next session: correct the parser against the real archived report, then
rerun STA on this existing fit to collect exact failing paths and snapshot
delays. That analysis does not require another full compile. Use those paths
to choose the next change; keep timing gates and physical save guards intact.

Watcher `pocket-gba-watch-1e9add1.service` completed **not-ready**, with its
desktop notification delivered. It names the parser failure because that
was the first build-stopping check. Both independent failures are recorded in
`build/watch/pocket-gba-gba-p5cart-header-m10k-s3-1e9add1b8926/failure-analysis.json`.
That folder also holds the build log, `path-analysis.log`, `ap_core.fit.rpt`
(Latin-1), and `ap_core.sta.summary`.
Remote fit: `/root/pocket-builds/checkouts/pocket-gba-gba-p5cart-header-m10k-s3-1e9add1b8926/build/gba/work` on sisko.

**No card installation occurred.** The mounted card UUID `7AFF-9FB9`
remains on `0.9999.c0c1040` with the short PL/PH/SF menu patch. It was
mounted writable outside the sandbox. No fsck, repair, unmount or save write.
Prepared installer `build/gba/install_1e9add1.py` was never executed;
`build/gba/deployment-1e9add1.json` is now **failed-not-installed** and its
state guard prevents installation. Do not reuse it without requalifying a
new successful build and its actual baseline. No new hardware test needed
for this failed fit.

## Reduced header checker build running; watcher active

**Source `1e9add1b89263cb9564e84f838a224d334c53601`, seed 3**, queued on
sisko as `pocket-gba-gba-p5cart-header-m10k-s3-1e9add1b8926`, launcher PID
`670632`. Verified Quartus started elaboration. This is the proposed timing
fix; passing timing and actual M10K placement remain pending.

Watcher **`pocket-gba-watch-1e9add1.service`**, PID `2354034`, is active.
Initial poll returned running and the startup desktop notification succeeded.
It checks timing, diagnostic retention, snapshot routing and package integrity;
the build additionally rejects a reference ROM not fitted in M10K memory.
Durable result: `build/watch/pocket-gba-gba-p5cart-header-m10k-s3-1e9add1b8926/result.json`.
Check: `../tools/runner-build job sisko pocket-gba gba p5cart-header-m10k-s3 1e9add1`.

All ten cartridge benches plus checker/snapshot/APF integration passed for
this revision. No card write. Return after queueing; completion is reported
by desktop notification. Do not claim timing or boot corruption fixed until
those separate build and hardware checks pass.

## Header checker reduced to synchronous ROM and shared comparison

User requested fixing the failed build. The -0.416 ns path is in existing
CPU operand selection/address calculation; CPU RTL remains unchanged.
Reworked only the diagnostic: the resettable 64-bit expected pair and two
word comparisons become one synchronous 64x32 reference ROM requested in an
M10K block and one shared 32-bit comparator. The first reference is fetched
on request acceptance; the companion is fetched on ready, for comparison
on the following clock. HD/HS behavior and all first-mismatch evidence stay
unchanged. No timing exceptions were added or relaxed.

The new post-fit guard reads the actual Fitter RAM Summary and rejects a
reference that did not use M10K memory. It handles the report's Latin-1 degree
symbols. Verified the guard rejects the previous logic implementation and
accepts a representative fitted memory row. Existing snapshot retention,
20 ns bundle routing and all timing-category gates remain mandatory.

Regression log: `build/timing-analysis/header-m10k-regression.log`.
All ten cartridge benches, actual APF menu integration and snapshot/checker
benches passed. The checker also exercises all 48 reference words at minimum
response latency. Next: commit and queue a seed-3 fit
with its persistent desktop watcher. Timing improvement is unproven until
that fit finishes. Installed card remains `c0c1040`; no card changes.

## Header diagnostic seed 3 failed setup timing; not ready for card

Status check confirmed `195904c` seed 3 completed in **1638 seconds**.
Setup **-0.416 ns** failed; hold +0.034 ns, recovery +2.963 ns,
removal +0.325 ns and minimum pulse +0.827 ns passed. Utilization is
18,052/18,480 ALMs (98%), 25,668 registers, 282 RAM blocks.

Fetched exact setup report: the worst path is inside the existing GBA CPU,
`execute_Rn_op1[0]` to `Mux416~0_OTERM8135`, at slow 1100mV/0C.
This establishes the failing endpoint, not the cause of the hardware boot
corruption or a reason to change CPU behavior. Simulation remains passing.

Watcher completed with **not-ready**, reason `Timing failed: Setup -0.416 ns`;
desktop notification delivered. Reports and result are under
`build/watch/pocket-gba-gba-p5cart-header-s3-195904cc0015/`, including
`setup-critical.txt`. No card write and no replacement build queued.
Installed card remains the passing `c0c1040` pattern diagnostic.

## Header diagnostic queued on sisko; watcher active

**Source `195904cc00152b5ba61f39050652dd6d57f313f4`, seed 3**, is running
on sisko. Job `pocket-gba-gba-p5cart-header-s3-195904cc0015`, launcher PID
`664731`. Verified Quartus reached fitter placement. This is a diagnostic,
not a claimed fix. Full simulation passed before queueing; no card write.

Persistent user service **`pocket-gba-watch-195904c.service`** is active,
PID `2332634`. Initial poll returned running; startup desktop notification
was delivered. It will fetch and qualify timing, retained diagnostic bits,
snapshot routing and package integrity, stage the package, then issue a
**desktop notification** for ready-to-write or the failure reason. It does
not automatically send a chat message or write the card.

Durable status: `build/watch/pocket-gba-gba-p5cart-header-s3-195904cc0015/result.json`.
Runner check: `../tools/runner-build job sisko pocket-gba gba p5cart-header-s3 195904c`.
If ready, install against the actual `c0c1040` plus short-menu baseline,
back up and verify protected files, flush and **leave the card mounted**.
If timing or retention checks fail, inspect exact reports before changing
anything. Do not install a failed fit or relax timing gates.

Next hardware capture is **CG/CS/SF/HD/HS** after cold launch of BMXE with
Read Only and cheats off. `docs/BOOT-DEBUG.md` explains the new encoding.
No further interactive waiting for this build is needed.

## BMXE header diagnostic implemented; regression passed, fit next

User asked what is next. Implemented a passive header comparison at the game
ROM mux output, replacing the pattern source. HD/HS replace PL/PH in the menu.
`docs/BOOT-DEBUG.md` defines the precise encoding and hardware procedure.
The first bad DWORD and byte offset latch; count/coverage continue. A separate
protocol flag disqualifies unexpected or overlapping handshakes. The checker
uses the verified BMXE 192-byte header and only enables for its cartridge ID.
It samples the companion on the clock after ready, matching the actual cache.
No changes to CPU/GBA engine, save policy or cartridge controller.

New tests cover all reference words, both response orders, corruption on
either beat, retention and protocol guards; the real controller/arbiter/mux
with a header-backed pin model; actual VHDL cache/memorymux byte/halfword/word
reads; and actual top-level menu snapshots. Full regression log:
`build/timing-analysis/header-regression.log`. **Full make test passed**, including
all ten cartridge benches, 48 cold odd/even fills, 576 byte/halfword/word
reads, APF snapshots and the corruption checker. Optional cheat corpus skipped.
Post-fit register guards now require the 58 variable payload bits (six others
are intentional constants), with the existing timing and snapshot-delay gates.

Installed card remains `0.9999.c0c1040` with the shorter PL/PH/SF menu patch.
This source is not a boot fix and is not installed. Next:
queue one seed-3 sisko fit plus the persistent desktop watcher, then return
without waiting for the full build. No card write or unmount in this work.

## Follow-up pattern passes again; startup remains corrupted

Follow-up photo `/tmp/codex-clipboard-4AEjhO.png` shows CG `424D5845`,
CS `FFFF96E1`, **SF `00000001`**, PL `4B3C2907`, PH `D1A65EED`.
Joined `D1A65EED4B3C2907` is exactly rotation **0** of the seed. Together
with the previous rotation-55 capture, this completes the requested hardware
pattern check for the observed samples. The corrupted startup persists;
neither capture measures CPU state or validates cartridge ROM data.
Archived photo and analysis: `build/hardware-results/c0c1040/pattern-sf1-followup*`.
The photo follows the request for full power-off/on; reset history was not
explicitly confirmed in text. SF remains one in the follow-up observation.

Code inspection found a limit of CG/CS: the probe reads the full 192-byte
header twice, but compares only accumulated 16-bit OR/AND values. It does
not compare each byte or validate the Nintendo logo. Passing detection can
therefore coexist with bad header data. The game ROM path also passes through
`rom_source_mux` and the GBA cache, unlike the direct header probe.

Next diagnostic should compare header data returned through the game ROM
path against the verified BMXE dump, capturing the first mismatch address
and returned word. Exercise byte/halfword/word reads and both DWORD orders
in simulation before fitting. A correct response at the mux would only
clear that boundary; cache/memorymux consumption would still need checking.
Avoid another pattern-only build or treating SF as proof of SRAM failure.
Preserve the EEPROM abort guard while investigating its request sequence.

[GBATEK's header reference](https://problemkaputt.de/gbatek-gba-cartridge-header.htm)
describes the cartridge-supplied compressed Nintendo logo, BIOS comparison,
and startup dummy reads. Thus SRAM save type alone does not establish which
ROM addresses the BIOS accesses; the actual EEPROM/DMA sequence remains
unexplained. No root cause or fix is established. No new build is queued,
and no card changes were made for this follow-up.

## Full pattern verified on hardware; EEPROM abort flag is now one

User explicitly corrected the earlier screenshot interpretation: the Game Boy
startup screen is **corrupted**, including the graphic beneath GAME BOY.
Do not describe this as a normal BIOS screen or infer successful boot.

New photo `/tmp/codex-clipboard-ORZwCp.png` shows full values:
CG `424D5845`, CS `FFFF96E1`, **SF `00000001`**, PL `76A59E14`,
PH `83E8D32F`. Joined pattern `83E8D32F76A59E14` exactly matches rotation
**55** of `D1A65EED4B3C2907`. This sample validates coherent pattern capture
and full menu readback on hardware; it does not validate the CPU or ROM data.
Archived photo and analysis: `build/hardware-results/c0c1040/pattern-sf1*`.

SF=1 is new evidence: `cart_eeprom_bridge.fault` latched its abort condition
while a tracked physical serial DMA transfer was open/sent and DMA became
inactive or bridge reset asserted before its final host completion. This
flag is EEPROM-specific, not a generic save-corruption or SRAM error flag.
It survives Reset Core and clears with FPGA configuration. Zero Mission's
verified ROM uses SRAM_V113, so determine why EEPROM traffic was observed
rather than assuming the SRAM save failed. Current memorymux unconditionally
routes the 0x0D region through EEPROM handling; no new root cause is proven.

Asked asynchronously whether this reading followed full power-off/on or a
Reset Core/earlier test. Answer is pending at this entry. No new build or card
write. Next step depends on whether SF=1 reproduces from fresh configuration;
if fresh, investigate how the EEPROM request/DMA abort sequence is reached
alongside the corrupted cartridge startup. Preserve the save fault guard.

## Pattern hardware photo received; shorter labels installed

Read `/home/kroy/Downloads/signal-2026-09-08-212350.jpeg` and the newly
mounted card's `Memories/Screenshots/20260908_211742.png`. Archived both plus
hashes/analysis in `build/hardware-results/c0c1040/`. The saved screenshot
shows the Game Boy startup logo, not a game title. Photo shows
CG `424D5845`, CS `FFFF96E1`, Save Fault prefix `0000…`, Pattern Lo prefix
`0FA3…`, Pattern Hi prefix `DA967…`. The visible pair uniquely matches
rotation 25 of the seed, whose expected full value is `DA9678520FA34CBD`.
**The hidden suffixes are inferred, not observed**; the photo cannot fully
qualify the 64-bit snapshot or zero fault. No boot success claimed.

The long readout labels caused the OS to ellipsize the values. Changed only
menu names: id 54 → **SF:**, id 60 → **PL:**, id 61 → **PH:**. After the user
confirmed the card mounted, installed the menu-only update with verified
22-file backup and **21 protected files unchanged**, including bitstream,
BIOS, saves and settings. Flush and mount verification passed; card left mounted.
Backup: `build/card-backups/20260909T022736Z-menu`.
Menu patch manifest: `build/gba/menu-c0c1040/manifest.json`.
Main installed-file manifest updated with the new interact.json hash.

Installed FPGA/version remains `0.9999.c0c1040`; this menu patch is newer
than its packaged source. No FPGA rebuild needed or queued. On relaunch,
read the full PL/PH/SF values (close/reopen OS menu for a second capture) to
finish the pattern check. The label changes are documented in BOOT-DEBUG.

## Pattern diagnostic installed and verified; card left mounted

User explicitly requested installation. **Installed version `0.9999.c0c1040`**
(pattern diagnostic, seed 3). The guarded installer verified card UUID
`7AFF-9FB9`, prior `417a55f` version/bitstream, timing and snapshot budgets,
and exact package contents before writing. It verified **13 installed files**,
**9 protected files unchanged**, flushed writes and confirmed the card remained
mounted. No filesystem check, repair or unmount was performed.

Fresh verified **22-file backup**: `/home/kroy/Desktop/repos/pocket-dev/pocket-gba/build/card-backups/20260909T021649Z`.
Contains prior core plus current GBA settings/saves, BIOS and package paths.
Manifest: `build/gba/deployment-c0c1040.json` (`installed-verified-mounted`).
Installer: `build/gba/install_c0c1040.py`; it expects the old baseline and is
not intended to be rerun blindly after successful installation.

Next hardware observation: open the core menu and capture **Pattern Lo** and
**Pattern Hi**. Join Hi then Lo (eight hex digits each); it must be one of the
64 rotations of `D1A65EED4B3C2907`. It stays stable while the menu is open.
Close/reopen to recapture; a repeated value is possible. These are pattern
data, not CPU state. This installation does not claim a Zero Mission boot fix
or physical save-write persistence. Future installs must recognize `c0c1040`
as the current card baseline; `417a55f` is the backed-up rollback version.

## Pattern diagnostic passed; verified package staged, not installed

Check-in confirmed `c0c1040` seed 3 completed successfully in 1535 s:
setup **+0.092 ns**, hold **+0.121 ns**, recovery +2.933 ns,
removal +0.276 ns, minimum pulse +0.827 ns. Utilization 18,052/18,480 ALMs
(98%), 25,632 registers, 282 RAM blocks.

Post-fit checks found **65 source registers, 64 captured and 64 published**;
the pattern/snapshot was not optimized away. Worst raw snapshot data delay
is **3.085 ns**, below the 20 ns budget at all four corners. The watcher
verified all 14 archive files against source and staged 13 card files.
Bitstream SHA256:
`10fe733a309abb343443126e3e6e3219feead956a1a7d428f7f48be273de6c54`.

Result, reports and stage:
`build/watch/pocket-gba-gba-p5cart-pattern-s3-c0c1040ce033/`.
Watcher state **ready-to-write**; completion notification delivered.
The card remains untouched on `417a55f`; this check-in did not authorize
resuming installation after the prior stop request. No build is running.

This establishes that the snapshot can meet timing with its local pattern
source at seed 3, despite higher total ALM use than the failing compact live
variant. It points the next isolation experiment toward retained CPU debug
outputs and their routing/optimization effects, rather than total register
count alone. It does not prove which live observation causes the problem,
qualify live CPU diagnostics, or fix Zero Mission's white screen.

## 2026-09-08: pattern diagnostic queued; stop requested

User requested: **queue it, then stop and hand off for now**. Do not continue
into additional builds or installation without a resumed request. The queued
build and its completion watcher should continue running.

**Pattern source `c0c1040ce03328600b11c1e3b3fec4992007bba4`, seed 3**, is
verified running on sisko. Job `pocket-gba-gba-p5cart-pattern-s3-c0c1040ce033`,
launcher PID `655805`. Status command:
`../tools/runner-build job sisko pocket-gba gba p5cart-pattern-s3 c0c1040`.

This isolates the existing 64-bit menu snapshot from CPU output retention
and cartridge/memory request fanout. CPU debug outputs and arbiter debug
output are disconnected exactly as in `417a55f`; all GBA engine sources still
match that passing baseline. A local 64-bit word `D1A65EED4B3C2907` rotates
left each system clock and feeds the snapshot. It has 64 distinct nonzero
rotations. The local source adds 64 registers, so this is an isolation
experiment, not an equal-area comparison with the live diagnostic variant.

Menu readouts are **Pattern Lo / Pattern Hi**, not CPU PC/State. A menu entry
captures them together; join Hi then Lo to obtain one rotation of the seed.
Snapshots stay stable while open and may repeat across captures. Pattern
works while GBA reset is held. It does not diagnose Zero Mission's CPU stall.
See `docs/BOOT-DEBUG.md` for the exact purpose and capture procedure.

**Full make test passed**, including actual top-level dynamic pattern capture,
menu retention/recapture during GBA reset, retired addresses returning zero,
standalone async snapshot test, nine cartridge benches, GHDL and cheat suites.
Optional external corpus skipped. Log: `build/timing-analysis/pattern-regression.log`.
Post-fit checks now require at least 64 source, capture and publication
registers, preventing optimized-away pattern circuitry from counting as a
successful experiment. Timing and snapshot-delay gates remain unchanged.

**Watcher active and first poll verified**:
`pocket-gba-watch-c0c1040.service`, PID `2273532` at startup. Startup desktop
notification delivered. Result and fetched artifacts will be at:
`build/watch/pocket-gba-gba-p5cart-pattern-s3-c0c1040ce033/result.json`.
It will report ready-to-write or not-ready by desktop notification, then exit.
Post-fit analysis logs are now fetched even on failure, with their first error
included in the failure reason when available. No automatic card writes.

On resumption: read that result first. If passing, inspect the actual fit and
preserved-pattern report and staged 13-file package. Decide whether to install
this pattern experiment or proceed with a separately validated live-observer
variant. The pattern fit alone cannot establish live CPU diagnostic timing.
If failing, inspect the saved paths/analysis error before deciding another build.

**Card untouched and not unmounted**, still installed `417a55f`. The exact
baseline control passed and reproduced its bitstream hash (next section).
Metroid Zero Mission remains unresolved; no save-write persistence claimed.

## 2026-09-08: control passed and reproduced the original bitstream exactly

The clean `417a55f` seed-3 control completed successfully in 1443 s.
All worst slacks exactly reproduce the original: setup **+0.092 ns**, hold
**+0.114 ns**, recovery +2.717 ns, removal +0.387 ns, minimum pulse +0.827 ns.
Utilization also matches: 17,819 ALMs, 25,136 registers, 282 RAM blocks.

**Bitstream SHA256 matches the archived passing artifact exactly**:
`62c6506b1915502fd65818c3d5f892aa1d8772329e5118b5de37f48a68a3ca25`.
This control demonstrates reproducibility for the existing baseline on sisko;
the diagnostic variants' failures cannot be attributed to a failure to
reproduce this baseline. It does not identify which observer changes perturb
synthesis/placement or demonstrate that the diagnostic datapath itself is critical.

Watcher result is `baseline-passed`, package verified, notification delivered.
Evidence: `build/watch/pocket-gba-gba-p5cart-control-s3-417a55f1c21b/`.
No build is currently queued and no card write/unmount occurred. This is the
same installed `417a55f`, not a new diagnostic package or a Zero Mission fix.
Next investigation should isolate effects of CPU diagnostic output retention
and snapshot routing against this proven baseline before another engine edit.

## 2026-09-08: compact diagnostics failed; exact passing control rebuilding

`3f7ae09` seed 3 failed setup **−2.790 ns** (1463 s), despite reducing area
to 17,751/18,480 ALMs (96%), 25,334 registers. Other worst slacks: hold
+0.074 ns, recovery +3.825 ns, removal +0.327 ns, minimum pulse +0.827 ns.
Actual worst path: CPU `block_pc_next[24]` → `block_writevalue[24]`, with
12.401 ns data delay against a 9.931 ns clock relationship. Other reported
failures involve CPU operand selection. The compact experiment did not close
timing. Watcher saved its result/reports and delivered the failure notification.
Artifacts: `build/watch/pocket-gba-gba-p5cart-compact-s3-3f7ae094b13f/`.

Before further RTL edits, an **exact control rebuild of the previously passing
`417a55f1c21bd1a6fa27c27e158987ddfd1c5011`, seed 3**, is running on sisko:
job `pocket-gba-gba-p5cart-control-s3-417a55f1c21b`, launcher PID `649432`.
Actual generated QSF and generate.tcl were byte-compared against the previous
`p5cart-abort-s3` passing job and match. This is a clean detached checkout of
the old revision, not current RTL with features toggled. Prior passing result:
setup +0.092 ns, hold +0.114 ns, 17,819 ALMs, 25,136 registers.

This control checks reproducibility of the baseline under the current build
runner. A pass directs attention back to diagnostic-induced synthesis/placement
changes; a failure requires investigating build variability/settings before
further RTL changes. Do not conclude that lower area guarantees better timing.

Persistent watcher: `pocket-gba-watch-control-417a55f.service`, PID `2258245`
at startup. First SSH poll and desktop notification verified. Its result is
`build/watch/pocket-gba-gba-p5cart-control-s3-417a55f1c21b/result.json`.
New explicit `--baseline` mode validates timing/fit/package but does not require
diagnostic registers absent in old RTL, and reports **baseline-passed**, never
ready-to-write. Default diagnostic mode still requires snapshot routing.
Validated against the authentic old passing package; failed timing and missing
snapshot reports in normal mode were rejected as intended.

**No card write or unmount.** The control is not a new diagnostic/game fix;
installed `417a55f` remains unchanged, and Zero Mission is still unresolved.
No further diagnostic build is queued until the control result is examined.

## 2026-09-08: compact diagnostics building from the passing engine baseline

User approved the smaller diagnostic experiment. Source
**`3f7ae094b13fd9ed0f42e55f11dd7afc4bc7c376`**, seed 3, is verified running
on sisko: job `pocket-gba-gba-p5cart-compact-s3-3f7ae094b13f`, launcher
PID `643446`. No card write or unmount occurred; installed baseline is `417a55f`.

Restored `gba_memorymux.vhd` byte-for-byte from `417a55f`, withdrawing the
unsuccessful I/O read-buffer edit. All `src/fpga/gba/` engine files now match
that timing-passing revision. The top-level differences observe state only.
The diagnostic payload is 64 bits: **CPU PC** and **CPU State**, sampled
together on OS-menu entry. This removes 128 payload registers, the seven-bit
save completion counter, full IRQ/DMA readout and SRAM address/data readout.
CPU State retains its previous encoding, including all three bus wait flags,
IME, DMA3 active, cheats/write policy and reset. Retired readout addresses
F4000018/F400001C return zero. See `docs/BOOT-DEBUG.md` for capture/decoding.
This reduces observation overhead; it does not guarantee timing closure.

**Full `make test` passed**: nine cartridge benches (including the combined
SRAM/ROM test), GHDL memorymux including I/O coverage, APF launch and compact
readout integration, coherent asynchronous snapshots and cheat suites.
The optional external cheat corpus was unavailable and skipped.
Log: `build/timing-analysis/compact-regression.log`. Whitespace checked with
`core.whitespace=cr-at-eol` for the restored upstream CRLF file; no global
Git setting changed.

**Persistent watcher verified active**, PID `2239287` at startup:
`pocket-gba-watch-3f7ae09.service`. Its first SSH poll succeeded and desktop
startup notification was delivered. It uses the same all-corner timing,
snapshot routing and exact package/source verification gates documented below.
It will send a desktop notification for ready-to-write or not-ready and save
its result at:
`build/watch/pocket-gba-gba-p5cart-compact-s3-3f7ae094b13f/result.json`.

The watcher does not install. After readiness, back up current card files,
install the verified 13-file stage against the `417a55f` baseline, flush,
verify protected saves/settings and leave mounted. Then reproduce Zero
Mission and capture CPU PC/CPU State with CG/CS and Save Fault twice, closing
and reopening the OS menu between samples. No save-write persistence or
Zero Mission boot success is yet claimed.

## 2026-09-08: c115fbf failed timing; watcher reported failure

The targeted I/O reply change **did not produce an installable build**.
Seed 3 finished in 1425 s: setup **−1.573 ns**, hold +0.039 ns,
recovery +3.711 ns, removal +0.297 ns, minimum pulse +0.827 ns.
18,017/18,480 ALMs (97%), 25,387 registers, 282 RAM blocks.

Actual worst path is CPU `execute_functions_detail.mulboth` →
`calc_result[1]`; savestate `ss_dout[52]` → `bus_out_Adr[8]` follows
at −1.397 ns. The earlier I/O path change is functionally tested, but this
fit has worse overall setup timing and different critical paths. Do not
claim timing closure or a hardware fix from it.

The watcher finished with `not-ready`, saved reports and all-corner paths
under `build/watch/pocket-gba-gba-p5cart-ioreply-s3-c115fbf6d3e4/`, and
successfully delivered its failure desktop notification at 18:12:27 UTC.
No replacement diagnostic build has been launched. No card write or unmount
occurred; the installed baseline remains `417a55f`. Zero Mission remains
unresolved. Next work should address overall timing/placement pressure;
another isolated critical-path edit is not yet justified by these results.

## 2026-09-08: targeted I/O timing fix building; persistent watcher active

Source **`c115fbf6d3e42e38160804c072c68eb73235a876`**, seed 3, is verified
running on sisko. Job `pocket-gba-gba-p5cart-ioreply-s3-c115fbf6d3e4`,
launcher PID `637358`. The user asked for a watcher that reports readiness or
failure. No card write or unmount was performed; installed baseline is `417a55f`.

Actual post-fit analysis of the old diagnostic seed 3 identified only two
failing paths at 85 C: memorymux I/O address bit 6 through the combined
`gb_bus.done` decode into `rotate_data` (−0.055 / −0.047 ns). Seed 2 also
failed CPU DMA-to-cycle-count and SDRAM input paths. This is placement-sensitive;
the clock named in a timing summary is not a path diagnosis.

The fix samples I/O reply data on the original cycle without gating that
buffer write on `gb_bus.done`. Readability still selects the original state
transition. Unreadable data is replaced by READ_UNREADABLE before ROTATE;
no extra bus cycle or acknowledgement is added. No timing constraints changed.
The existing stale QSF resource-sharing target was observed but not changed.

Validation: `make test` passed (external cheat corpus skipped). Added I/O
regression covers readable/unreadable replies at all widths and byte lanes,
write pulse count and a delayed read. A temporary baseline/current GHDL
comparison produced **3,408 identical cycle/data trace entries**. Evidence:
`build/timing-analysis/regression.log`, `compare_memorymux.py`, and
`seed3-all-corners/`. Snapshot raw data delay in old seed 3 is 6.854 ns at
85 C; the new build must independently pass its routing check.

`scripts/inspect_timing.tcl` now emits actual setup endpoints and raw snapshot
payload delays at all four operating corners after every fit. The existing
SDC remains in force. The new build also runs this report script automatically.

**Watcher is a persistent user service**, not a chat process:
`pocket-gba-watch-c115fbf.service`, PID `2211597` at startup. Its first SSH
poll succeeded and its startup desktop notification was delivered. It polls
sisko every 45 seconds, fetches the exact job artifacts (avoiding the
runner-fetch ambiguity), and sends a desktop notification when finished.
A shell/nohup launch did not survive; the user service is the verified watcher.

- Durable result: `build/watch/pocket-gba-gba-p5cart-ioreply-s3-c115fbf6d3e4/result.json`.
- Journal: `journalctl --user -u pocket-gba-watch-c115fbf.service`.
- Readiness requires build success, five nonnegative timing summaries,
  valid fit, all four snapshot paths under a conservative 20 ns budget,
  exact package/source/version agreement and matching bitstream bytes.
- On success: verifies 14 archive files, stages the 13 Assets/Cores/Platforms
  files under that watch directory's `sd/`, and records `ready-to-write`.
  Root `instructions.txt` is verified but not staged for the card.
- On failure: records `not-ready` plus the reason; timing failures include
  detailed path reports when available. Five network failures or three hours
  without completion also report an explicit monitoring failure.
- Watcher validation rejected a real failed report, a corrupted bitstream and
  an over-budget snapshot fixture; its success fixture staged the expected
  package files. The test fixture did not alter real failed artifacts.
- **The watcher never writes the card.** When ready, adapt the guarded
  installer to this revision and the existing `417a55f` baseline, back up
  fresh saves/settings, flush and verify the write, and leave it mounted.
- Metroid Zero Mission's hardware white screen remains unresolved. The
  diagnostic package is intended to capture its CPU PC/state, IRQ/DMA and
  Save Bus on two OS-menu entries, not a confirmed game-specific fix.

## 2026-09-08: Zero Mission also whitescreens on 417a55f

User reports the same white screen after BIOS on the new installed build.
CG/CS remain `424D5845` / `FFFF96E1`; Save Fault is zero. This confirms header
probing works, but the EEPROM-specific fault flag does not qualify SRAM.
The underlying boot failure is still unresolved. No speculative cartridge
bus timing or save-policy change is justified by the current evidence.

Added capture of the existing CPU PC, CPU/memory state, IRQ/DMA status,
and SRAM address/data when the user opens the OS menu. Four stable readouts
are documented in `docs/BOOT-DEBUG.md`. No game reset dependency or execution
gating was added. Standalone asynchronous-clock snapshot tests and actual
core_top/APF packing/readout tests pass; independent review found no behavior
change in the cartridge or CPU paths.

The new combined test exercises actual core_top write policy → arbiter →
controller → pin model: 12,294 SRAM reads, 4,096 copy writes, 4,098 denied
writes and 16,390 concurrent ROM reads. It passes, including payload changes
after request pulses, boundary addresses, neighbor preservation and no
physical write pulses for denied requests. No hardware root cause reproduced.
It is the ninth cartridge bench; unrelated CPU/VHDL engines are omitted from
this mixed test, so it does not simulate Zero Mission startup itself.

`make test` passed: 9 cartridge benches, GHDL memorymux, APF command/launch
and actual-top debug readouts, asynchronous snapshot test, and cheat suites.
Optional external cheat corpus was unavailable and skipped.

**Diagnostic seed 3 failed timing**: setup **−0.055 ns**, hold +0.030 ns,
recovery +3.578 ns, removal +0.411 ns, minimum pulse +0.827 ns;
18,045/18,480 ALMs (98%), 25,638 registers, 282 RAM blocks, 1494 s.
Reports, log and package are archived in
`build/gba/artifacts/1a053b2-seed3-FAILED/`; **do not install that package**.
The user reports the card mounted. No card writes or unmount were performed.

**Diagnostic seed 8 also failed timing**: setup **−0.300 ns**, hold +0.026 ns,
recovery +2.429 ns, removal +0.276 ns, minimum pulse +0.827 ns;
17,819/18,480 ALMs (96%), 25,579 registers, 282 RAM blocks, 1626 s.
Artifacts: `build/gba/artifacts/1a053b2-seed8-FAILED/`; do not install.

**Diagnostic seed 2 also failed timing**: setup **−0.593 ns**, hold +0.025 ns,
recovery +3.131 ns, removal +0.449 ns, minimum pulse +0.827 ns;
17,829/18,480 ALMs (96%), 25,549 registers, 282 RAM blocks, 1572 s.
Artifacts: `build/gba/artifacts/1a053b2-seed2-FAILED/`; do not install.
All three diagnostic fits (seeds 3, 8, 2) failed. No diagnostic build is
currently running, and none has been installed. Card remains on `417a55f`.

Next: extract actual post-fit setup paths from the diagnostic checkout before
choosing another fit or RTL change. The summary names a clock, not the
failing path endpoints; it does not establish the cause. Do not use the stale
local `build/gba/work` reports for this purpose or relax timing exceptions.

- Source: `1a053b20bc00303b2c7cc29156e001a28d57fab6`.
- Latest job: `pocket-gba-gba-p5cart-debug-s2-1a053b20bc00`, completed.
- Remote output:
  `/root/pocket-builds/checkouts/pocket-gba-gba-p5cart-debug-s2-1a053b20bc00/build/gba/`.
- Fetch caveat: runner fetch matches all checkouts at the same commit and
  fails with multiple seeds. Use explicit file paths via SCP.
- Require passing timing and fit before installing. Preserve installed
  `417a55f` as the rollback baseline; leave the card mounted after writes.
- Once a diagnostic build passes and is installed, reproduce Zero Mission's
  white screen, open the OS/core menu and capture CPU PC, CPU State,
  IRQ / DMA and Save Bus. Close/reopen and capture a second set to establish
  whether the PC or completion count moves.

After fit,
check the snapshot's bundled data routing against the ~27 ns settling window.
The diagnostic snapshot starts at zero before a menu entry completes; close
and reopen the OS menu to recapture. Save completions count modulo 128 and
include denied writes. SRAM address/data describe request/last response, not
necessarily the same transaction while a request is pending.
No further card write has occurred since the 417a55f installation.

## 2026-09-07: 417a55f installed and verified; card left mounted

User remounted the card and explicitly said not to unmount. The guarded
installer completed: **13 package files verified**, **9 protected files
unchanged**, filesystem writes flushed, and the card left mounted.
The prior core and current GBA saves/settings are preserved in a verified
22-file backup at `/home/kroy/Desktop/repos/pocket-dev/pocket-gba/build/card-backups/20260908T042119Z`.

Installed version: **0.9999.417a55f**, seed 3, setup +0.092 ns and hold
+0.114 ns. Manifest: `build/gba/deployment-417a55f.json`.
Next hardware test: select Play Cartridge directly, cheats off, and retry
Metroid Zero Mission. Read Only is the default; capture CG/CS and Save Fault
if it still whitescreens. This package is not a confirmed Metroid-specific
fix. Physical save-write persistence remains unqualified.

## 2026-09-07: Zero Mission white screen; new GBA build passes timing

User tested Metroid Zero Mission on installed `99293a3`: `CG=424D5845`
(`BMXE`), `CS=FFFF96E1`. Header detection passes; screenshot
`20260907_230950.png` is plain white after the BIOS logo. Both Read Only and
Writes Enabled produced the same result. The user noted write permission
reverts on relaunch; that is the intentional nonpersistent menu setting,
not evidence about physical save persistence. Cheats-off confirmation is pending.

The exact verified 8 MiB ROM uses `SRAM_V113`, with a verified 32768-byte
physical save backup (SHA256
`de92473cc3074a592caa43881240bc755bca2533da2c3be3b6635ab37098da21`).
Backup/provenance and the white screenshot are in
`build/hardware-results/metroid-zero-mission/`. Flash ID commands are not
applicable to this cartridge. Public matching decomp startup blanks the
screen before SRAM reads; its write/readback test has bounded retries. No
confirmed infinite loop or RTL defect explains the freeze yet. Byte-return
replication and DWORD-based MaxPakAddr look correct. If the failure persists
on the new build with cheats off, CPU PC and outstanding ROM/SRAM requests
would distinguish a cartridge access stall from later IRQ/VBlank waiting.

**`417a55f`, seed 3, completed successfully on sisko:** 1447 s, setup
**+0.092 ns**, hold **+0.114 ns**, recovery +2.717 ns, removal +0.387 ns,
minimum pulse +0.827 ns. **17,819/18,480 ALMs (96%)**, 25,136 registers,
282 RAM blocks. Reports/log/bitstream archived in
`build/gba/artifacts/417a55f-seed3/`; the 13-file package is staged at
`build/gba/deploy-417a55f/` and its bitstream/hash/menu match verified source.
Manifest: `build/gba/deployment-417a55f.json`.

Installation was attempted with approved access outside the sandbox but the
UUID/mount precondition could not be verified; it stopped before backup or
card writes. No filesystem check was run. The guarded installer
`build/gba/install_417a55f.py` is ready once the card is available at the
expected mount. It requires the existing `99293a3` bitstream, backs up current
GBA core/settings/saves, verifies all candidate/protected bytes after flush,
and leaves the card mounted. Do not treat this as an installed Metroid fix.

## 2026-09-07: new screenshot reports CartTools restore progress

The user's latest screenshot `20260907_224214.png` is **CartTools Save
Restore**, not the GBA gameplay core. It reaches the recovery-backup filename
probe and stops at SD error 4, with cartridge save writes disabled. The
restore engine only enters that stage after validating metadata/input-save
CRC, matching ROM identity, and comparing two complete 8192-byte reads of
the original cartridge save. This is additional CartTools preflight progress;
it does not qualify GBA save-write persistence or a completed restore.
Evidence is archived separately in `build/hardware-results/carttools-1540/`.
The preceding screenshots show the older input-open and slot-ID failures.

## 2026-09-07: EEPROM persistence preparation and interrupted-DMA fix

User asked to fan out and continue toward cartridge play/save support.

- Physical Minish EEPROM backup found and SHA256-verified at
  `../pocket-cartridge/build/card-verified-250d/GBAZELDA_MC.sav` (8192 bytes,
  `2fb51f21588769f0183d8ead956758d3812397d8f6370458dd639b617c83fad0`).
  Matching rollback copy and provenance are in
  `build/hardware-results/99293a3/physical-save-backup/`.
- Added EEPROM busy-to-ready polling and readback after FPGA reset to existing
  pin-model benches; these pass. This models host reset after programming is
  complete, not interrupted physical power or programming.
- Reproduced a bridge permission leak after a DMA abort: a later transfer
  could inherit an earlier Writes Enabled decision. The fix exposes live DMA3
  activity and stops physical EEPROM traffic after an interrupted
  physical command. Do not infer recovery from a CS pulse or pad a command.
- A sticky **Save Fault** diagnostic at `0xF4000008` reports that condition;
  normal traffic is 0. A value of 1 requires a full power cycle and relaunch,
  not Reset Core. Writes remain a nonpersistent test opt-in.
- Removed the obsolete `cart_menu_sync` timing exception; automatic launch
  signals retain normal single-cycle timing. The previous seed-8 automatic
  launch build failed setup (details below) and is not installable.

Validation complete: `make test` passed all 8 cartridge benches (including
seven abort/boundary cases and four physical EEPROM model variants), GHDL
memorymux, APF command/top-level launch benches, and cheat suites. Optional
external cheat-corpus checks were skipped. The updated VHDL hierarchy also
analyzes/elaborates with the existing unrelated vendor RAM interface stub.
The regression caught and fixed a false fault at simultaneous final-bit
completion/DMA inactivity; valid save data now reads back at that boundary.

**Combined revision is queued and verified running on sisko, seed 3.**

- Source: `417a55f1c21bd1a6fa27c27e158987ddfd1c5011`.
- Job: `pocket-gba-gba-p5cart-abort-s3-417a55f1c21b`, PID `602890`.
- Quartus 25.1std, STANDARD FIT, NPROC 16; runner log confirms explicit seed 3.
- Status: `../tools/runner-build job sisko pocket-gba gba p5cart-abort-s3 417a55f`.
- Fetch: `../tools/runner-build fetch sisko pocket-gba gba p5cart-abort-s3 417a55f`.
- Includes automatic Play Cartridge and the EEPROM abort fix. Check all timing
  types and utilization before installation; do not install on negative slack.
- Do not wait interactively for compilation. Seed 8 failed the earlier launch
  revision; no unproven timing exception was added to get this one through.

Independent final RTL/wiring review passed. The existing hardware-proven card
build is still `99293a3`; no card files were changed this turn.

Next physical persistence test, after installing a timing-passing candidate:
disable cheats; confirm Adam/BRO and empty slot 2; enable Writes Enabled,
create **TEST** in slot 2 and save through the game, wait for save completion,
then fully power off. Relaunch in Read Only and verify TEST progress plus
unchanged Adam/BRO. Do not change write permission during a save operation;
Flash permission is currently per byte, not per complete Flash command.

## 2026-09-07: loaded cartridge save and gameplay with cheats confirmed

Kroy confirms the same Minish Cap test successfully **loaded a working save
and played with cheats**, beyond displaying the populated file-selection
screen. This is hardware evidence for existing physical save loading and
cartridge gameplay with cheats on the installed **`0.9999.99293a3`**.
Specific cheat codes and gameplay duration were not reported.

This result does not yet test physical save-write persistence or the automatic
Play Cartridge change in `6302c43`, which was queued separately on sisko.
No card files or FPGA source changed for this confirmation.

## 2026-09-07: remove redundant Cartridge mode menu

User request: choosing **Play Cartridge** should be sufficient to play the
inserted game. The old handler ignored APF command `00B1`, so the browser
selection powered the slot but left the core waiting for a separate Boot setting.

- Decode `00B1` bits 24/16 (Play Cartridge / power after reset exit), retaining
  them through APF resets. Synchronize launch intent and powered enable.
- Remove the Off/Detect/Boot menu and its register. Ignore stale persisted
  writes at `0x90`; there is no settings migration needed on the card.
- Probe/boot/read saves automatically. Keep the CPU held if power or a valid
  header is absent; do not run uninitialized SDRAM on a failed cartridge launch.
- Suppress SD save size and savestate support from launch intent immediately.
  Unsupported APF save/load requests now complete with error 3, without a pulse
  to the gated consumer. Normal SD savestate handshakes are preserved.
- CG/CS diagnostics and the nonpersistent Read Only/Writes Enabled test setting
  remain. Physical write persistence is still unqualified.

Validation: `make test` passed (7 cartridge benches, GHDL memorymux, 30 APF
commands covering both byte orders/reset retention and savestate handshakes,
and the cheat suites). Optional external cheat-corpus cross-check skipped
because no corpus is configured. Independent RTL/UI review passed. The
actual `core_top` control-path bench also passed: APF notification through
source synchronizers, CPU/controller reset, save isolation and stale `0x90`
immunity. This bench models probe results and omits unrelated engines; the
real probe/VHDL/pins are covered separately, not by that launch bench.
**Build finished but failed timing on sisko**, explicit seed 8:

- Source: `6302c433339cbe79592a8e7ae54c7348b4ac860c`.
- Job: `pocket-gba-gba-p5cart-auto-s8-6302c433339c`.
- Launcher PID: `597423`; finished rc=2 after 1733 seconds.
- Setup **-0.110 ns**, hold +0.072 ns, 18,093/18,480 ALMs (98%).
  **Do not install.** Artifacts: `build/gba/artifacts/6302c43-seed8-FAILED/`.
- Status: `../tools/runner-build job sisko pocket-gba gba p5cart-auto-s8 6302c43`.
- Fetch when done: `../tools/runner-build fetch sisko pocket-gba gba p5cart-auto-s8 6302c43`.
- Do not wait interactively for compilation. Check all timing types and fit
  before installing the matching bitstream/package. Preserve the existing
  verified `99293a3` rollback archive and back up current card files.
- Hardware check after installation: choose Play Cartridge directly, confirm
  Minish Cap's Adam/BRO slots without touching a mode switch; then verify SD
  launch remains independent. Keep saves Read Only for this check.

No new package has been installed; the mounted card still runs hardware-tested `99293a3`.
The earlier read-only mount observation came from the sandbox and was not
evidence of a card fault. The user ran `fsck.exfat -a /dev/sdb1` and reported
**clean: 813 directories, 6917 files**. Do not repeat filesystem checks or
repair based on sandbox restrictions. Use the normal approved access outside
the sandbox for card installation, identify the card by UUID `7AFF-9FB9`, and
leave it mounted after writing. For necessary privilege elevation the user
prefers **pkexec**, not sudo. Never hard-code a stale device name.

## 2026-09-07: existing Minish Cap cartridge saves confirmed on hardware

**`0.9999.99293a3` boots and reads the physical EEPROM save.** The user
reported success with Cartridge Saves set to **Read Only**. The latest card
screenshot `Memories/Screenshots/20260907_211307.png` shows Minish Cap's file
selection with **Adam** in slot 1 and **BRO** in slot 3; slot 2 is empty.
The image is preserved in `build/hardware-results/99293a3/` with hashes.
Physical write persistence remains untested.

The preceding BIOS-screen report is **not a confirmed code regression**.
That attempt had CG=CS=0 (cartridge controller disabled). After checking
**Cartridge → Boot** separately from **Cartridge Saves → Read Only**, the
user reported that it worked. The mounted card's persisted interact setting
is id 50, value 2 (Boot). The source's combined ROM-path simulation also passes.
Normal use needs only **Boot**; it automatically probes. Detect is a diagnostic
mode, not a required first step. The user found the startup process clunky;
the user clarified that Play Cartridge should be sufficient. The new source
change above removes the redundant mode switch.

No new bitstream was installed for this confirmation. Card writes must still
be flushed without automatically unmounting. Before any write-persistence
test, verify the actual cartridge EEPROM backup described below and use the
explicit Writes Enabled setting. SD card backups are not physical EEPROM
backups.

Separate audit finding, not linked to the resolved startup report:
unsupported APF save/load commands could wait forever because Boot-mode gating
suppressed their acknowledgments. The new launch change above also makes the
command handler return error 3 without asserting an unsupported request.

## 2026-09-07: physical-save build installed; test existing slots in Read Only

**Hardware regression:** after installing `99293a3`, Kroy reports a freeze
at the BIOS screen again. `4728cc6` previously reached Minish Cap title/save
selection. CG/CS from the failed session are pending. Do not treat the
simulation/timing passes as a successful hardware save test. Investigation
is checking the complete ROM mux → arbiter → controller path and startup.

The new combined simulation passes: 48 held header-probe requests followed
by 70 CPU cache-line reads through the actual ROM mux, arbiter, controller
and cartridge pin model. All 7 cartridge benches pass; no lost/duplicate
requests or cache ordering regression reproduced. This does not qualify the
hardware path. A displayed GBA logo can also mean the game entered save
initialization and stalled before drawing its first frame. CG/CS are needed
to separate failed detection from later execution. No new FPGA build started.

**`0.9999.99293a3` is installed on the Pocket card**, UUID `7AFF-9FB9`.
The overnight sisko build completed successfully (rc=0), explicit seed 8,
Quartus 25.1std, STANDARD FIT, in 1659 s. All timing types passed:
setup **+0.088 ns**, hold **+0.054 ns**, recovery +2.379 ns, removal +0.248 ns,
minimum pulse width +0.827 ns. Utilization: 18,057/18,480 ALMs (98%),
25,347 registers, 282 RAM blocks.

Fresh verification passed all 6 cartridge benches and the GHDL memorymux
bench. Existing-save reads, write protection, EEPROM program/readback and
raw byte-save routing are simulation-tested; physical saves are not yet
hardware-qualified. **Next test: Minish Cap Boot, Cartridge Saves → Read Only;
check whether the existing save slots appear.** Writes remain an explicit,
nonpersistent menu opt-in. The 32 MiB EEPROM/Flash/reset limits below still apply.

The package's 13 files were installed and hash-verified; 8 existing
BIOS/save/settings/firmware files were verified unchanged against a new
21-file backup at `build/card-backups/20260908T010801Z`.
Writes were flushed and **the card was left mounted**, as requested.

- Package: `build/gba/kroy.GBA_0.9999.99293a3.zip`
- Package SHA256: `f7090310c8ecf07db8efcbf2257bc457fdb88f5698fc2e5bf7fe7ba74b65ed43`
- Bitstream SHA256: `04ab61d4f79d228a51c8313d216da3a900b04b002015c15c07f83b622a2a784e`
- Report/log/bitstream archive: `build/gba/artifacts/99293a3-seed 8/`
- Deployment manifest: `build/gba/deployment-99293a3.json`

## 2026-09-06 overnight: physical saves implemented; FPGA build to check tomorrow

Kroy asked to fan out and implement save support, then finish for the night
and queue a build on **sisko**. Work is integrated and tested. **Do not install
anything tonight.** The card remains on the hardware-booted **`0.9999.4728cc6`**,
which cannot read/write physical saves. Preserve Kroy's instruction:
**do not automatically unmount the card after writing it.**

### What changed

- `gba_memorymux.vhd` bypasses save emulation in cart mode and forwards raw
  SRAM/Flash bytes and serial EEPROM bits. `gba_top.vhd`/`gba_dma.vhd` expose
  actual DMA3 ownership, complete transfer count and last-bit boundaries;
  stale count or generic DMA ownership cannot authorize EEPROM commands.
- `cart_eeprom_bridge.sv` defaults to read-only. It buffers both prefix bits
  before permitting only `11` read-address commands of 9/17 bits. Denied
  program commands produce no physical strobes. Writes Enabled permits
  program traffic, with permission fixed for the whole command.
- `cart_bus_arbiter.sv` queues pulsed ROM/save/EEPROM requests while the slot
  is busy and routes each completion only to its owner. Held probe requests
  become single transactions. The ROM cache-line fix is retained.
- `gba_cart_controller.sv` now latches EEPROM data/direction, provides actual
  first-bit address setup and final-bit address hold, and samples D0 while
  RD is still low. The old sample-after-RD-rise failed the stricter model.
- Menu **Cartridge Saves** at `0x94`, default **Read Only**, nonpersistent;
  **Writes Enabled** must be selected explicitly. SRAM/Flash byte writes
  are blocked when disabled. Cart save data never goes to an SD `.sav`.
- APF savestates, restore triggers and state payload writes are disabled
  in Boot mode. GPIO/RTC remains disconnected.

### Validation completed tonight

`make test` passed: converter 27 passed/1 corpus skip, binloader19,
fixtures10, end-to-end9, EEPROM/controller/ROM/mux benches and the GHDL
memorymux regression. The subsequently added arbiter test brings the final
cartridge suite to **6/6 passing**. Both 512-byte and 8-KiB EEPROM models
cover existing-save reads, program/readback, neighboring data preservation,
zero-strobe write rejection, malformed prefixes, permission changes,
consecutive same-direction commands, and CPU ready polling. DMA tests cover
9/17/73/81-bit commands and 68-bit reads, actual ownership and final-bit
boundaries, and SD-save isolation.

GHDL also analyzed/elaborated the GBA VHDL hierarchy using an interface stub
for unrelated vendor byte-enable RAM; no new interface errors. Quartus remains
the authority for mixed-language FPGA elaboration and timing. The sim image
now includes GHDL (`make sim-image` rebuilt locally).

### Tomorrow

**Running on sisko:** source commit **`99293a3`**
(`99293a313577213c2ac545b286dc984ba6b209ad`), job
`pocket-gba-gba-p5cart-saves-s8-99293a313577`, launcher PID `579902`.
Started with explicit `SEED=8`, Quartus 25.1std, STANDARD FIT, 16 processors.
The build was confirmed running before ending the session; no timing result
was available yet. Do not use `HEAD` for this job, since the handoff itself is
committed afterward.

```sh
../tools/runner-build job sisko pocket-gba gba p5cart-saves-s8 99293a3
../tools/runner-build fetch sisko pocket-gba gba p5cart-saves-s8 99293a3
```

Expected package: `build/gba/kroy.GBA_0.9999.99293a3.zip`.
If it fails timing, preserve that report/package as failed and try another
explicit seed against the same source; do not install a timing-failed build.

Check the job's return code and **all-corner timing**
before fetching/installing; do not infer success from a `.zip` existing.
The prior build's report/bitstream is archived under
`build/gba/artifacts/4728cc6-seed8/`.

If timing passes, back up the card's current files, install the new package,
verify hashes and preserve saves/settings/BIOS. Flush writes and **leave the
card mounted**. First test Minish Cap Boot with **Read Only**: the existing
save slots should appear. Only then test write persistence using an expendable
slot/verified backup and the explicit Writes Enabled setting.

Minish Cap `BZME` is a locally hardware-qualified 8-KiB EEPROM cartridge;
`../pocket-cartridge/docs/CARTRIDGE-CORPUS.md` records an existing verified
8192-byte backup SHA256
`2fb51f21588769f0183d8ead956758d3812397d8f6370458dd639b617c83fad0`.
Find and verify that actual backup before any physical program experiment;
this is distinct from our SD-card backup.

Limitations: physical save reads/writes are **not hardware-qualified yet**;
Flash ID/bank commands are blocked in Read Only and may require Writes Enabled.
32-MiB EEPROM cart address decoding is not qualified; do not claim coverage
from Minish Cap. Reset/power interruption during a physical program command
has not been qualified. Sustained gameplay, RTC/GPIO and cart savestates remain
outstanding. No release/tag/publication tonight.

## 2026-09-06: cache-line fix boots Minish Cap to title and save selection

**Hardware result:** Kroy reports that `0.9999.4728cc6` boots Minish Cap
past the GBA startup logo to the title and save-slot screen. The slots were
empty. This is expected with the current integration: cartridge `save_req`
and `eeprom_req` are tied low, and cartridge mode reports zero save-file
size to APF. The core does not load the physical cartridge's existing save
or write to it. This result validates startup after the cache-line fix;
sustained gameplay and other cartridges remain unqualified.

**`4728cc6` is installed as `0.9999.4728cc6`.** Its cartridge ROM mux
preserves the aligned cache-line contract described below. The build passed
on sisko, Quartus 25.1std, STANDARD FIT, 16 processors, in **1401 s**:

| | |
|---|---|
| Seed | **8**, confirmed in `ap_core.fit.rpt` |
| Setup / hold | **+0.077 / +0.092 ns** |
| Recovery / removal / minimum pulse width | +4.242 / +0.398 / +0.827 ns |
| ALMs / registers / RAM blocks | 17,762 (96%) / 24,867 / 282 |
| Package | `build/gba/kroy.GBA_0.9999.4728cc6.zip` |
| Package SHA-256 | `3e2bb7c61a5889a7c1a96b70a32418a729e4740d33648a56f81e9d9376e73ebc` |
| Bitstream SHA-256 | `23cb3bca36648168f6a43d84863c7c34152f601a3779a1a038178dbf6372cc50` |

Runner job: `runner-build job sisko pocket-gba gba p5cart-cache-s1 4728cc6`.
The job label says `s1`, but the launch omitted `SEED=1` and used the QSF's
default seed **8**. It passed its own timing gate. Reports and bitstream are
preserved in `build/gba/artifacts/4728cc6-seed8/`.

All 13 installed package files were hash-verified. Eight existing BIOS,
save/settings/firmware files were verified unchanged against the fresh backup
at `build/card-backups/20260907T020719Z/`. Writes were flushed.
**The card remains mounted at `/run/media/kroy/pocket`, as Kroy requested;
do not automatically unmount it after future writes.** Deployment manifest:
`build/gba/deployment-4728cc6.json`.

**Next:** qualify gameplay and repeated cold boots, then implement cartridge
save access as a separate feature. Existing physical saves are inaccessible
in this build, and new in-core progress is not persistent in cartridge mode.

## 2026-09-06: conservative sequential timing hardware result and cache diagnosis

**Latest Boot retest:** after the successful detection below, Kroy selected
Boot and reported another freeze at the beginning. The subsequent photo,
explicitly identified as the frozen Boot session, shows `CG=425A4D45` and
`CS=FFFF96E1`: the probe passed on that restart too. Kroy then confirmed
the frozen screen is the **GBA startup logo**, before the game begins. This
failure occurred despite successful header detection; the earlier probe
timeout does not explain this attempt.

Investigation found a separate, reproducible cache-fill defect in
`rom_source_mux.sv`: `cache.vhd` expects the companion DWORD from the same
aligned 8-byte line, as SDRAM's burst returns, but the cart controller reads
four consecutive halfwords. Odd DWORD requests therefore supplied the next
line's lower DWORD in place of the current line's lower DWORD. The header
probe uses even DWORD addresses and cannot expose this bug. The mux now
aligns cart requests and swaps the two returned DWORDs for an odd original
address, latched with the request. The direct header-probe path is unchanged.

The new `tb_rom_source_mux.sv` exercises the mux with the actual controller
and sequential cartridge model. Before the fix it failed at DWORD address 1
(companion `D7CDB802`, expected `5EE9C0DE`); after the fix all 70 line reads,
SDRAM forwarding, and the two existing cartridge benches pass. This is a
confirmed cache corruption fix, not yet confirmation of the hardware freeze's
cause. The new FPGA build is installed as described above; hardware boot
retesting remains required.

The 20/6 sequential timing change is committed as **`85bb71a`** on
`p5-cartridge`. It closed at **seed 1 on sisko**, Quartus 25.1std,
STANDARD FIT, 16 processors, in **1449 s**:

| | |
|---|---|
| Setup | **+0.086 ns** |
| Hold | **+0.086 ns** |
| Recovery / removal / minimum pulse width | +4.196 / +0.380 / +0.827 ns |
| ALMs | 17,778 / 18,480, 96% |
| Registers / RAM blocks | 25,214 / 282 |
| Package | `build/gba/kroy.GBA_0.9999.85bb71a.zip` |
| Package SHA-256 | `d742a9363137af427d9d777b40c52d67a136fda56d0bcec90a3a9c439d4a10aa` |
| Bitstream SHA-256 | `b876ec7a2ae9f30e9c2fd4ae40bbdcc89696c3fa1a7de26e521fcc4cf82a65ad` |

Job: `runner-build job sisko pocket-gba gba p5cart-seq20-s1 85bb71a`.
`fetch` worked for this job. The report and build log are in `build/gba/`;
the previous passing `cfd4264` seed 1 report, log and bitstream are preserved
under `build/gba/artifacts/cfd4264-seed1/`.

**Installed on the Pocket card**, UUID `7AFF-9FB9`, firmware 2.5. The package's
`Assets`, `Cores` and `Platforms` were merged into the card. All 13 installed
files were hash-verified, including the bitstream, and the card was flushed
and unmounted. The menu version is **`0.9999.85bb71a`**. The existing GBA
saves, settings and 16 KiB BIOS were verified unchanged. The previous core,
platform files, settings and saves are backed up under
`build/card-backups/20260907T012500Z/`; the deployment manifest is
`build/gba/deployment-85bb71a.json`.

`make test` passed: 27 converter tests, 19 binloader cases, 10 fixtures,
9 end-to-end cases and both cartridge benches. The optional cheat corpus
checks were skipped because no `CHT_DB` was configured.

**Hardware result:** Kroy reported `CG: 0x54005400`, `CS: 0x007C58E1`
after this installation. The probe now completes, but this is a false-positive
detection, not a valid cartridge header. The fixed byte is `58`, not `96`,
and the game code is wrong. These readings exactly match a model in which
every halfword in each burst returns its initially driven address: request
index 42 drives halfword address `0054`, index 44 drives `0058`, and ORing
all 24 request addresses gives `007C`. Address readback is therefore the
leading hypothesis; these readings alone do not distinguish retained bus
values, a pin-direction/read-path problem, or an unresponsive cartridge.
The two-pass OR/AND comparison accepts this repeatable bad data. Hardware
qualification failed on that attempt; do not treat `E1` alone as a valid header.

**Successful detection retest:** Kroy's subsequent menu photo shows
`CG: 0x425A4D45` (`BZME`, Minish Cap) and `CS: 0xFFFF96E1`.
The game code and fixed header byte now match, and both probe fingerprints
agree without timeout. `FFFF` here is the OR fingerprint of the header;
the all-FFFF flag is clear, so this does not indicate an empty slot.
This followed a request to power off and reseat the cartridge, but the exact
steps taken were not reported; the cause of the initial failure remains open.

**Next:** select Cartridge `Boot`, restart, and check boot and gameplay.
Also check an SD ROM with Cartridge `Off` and a cold load with `Detect`
persisted. Detection has now passed on hardware; sustained cartridge reads
and gameplay remain unqualified. Cartridge saves remain unsupported.
No GBA tag until a cartridge boots.

## Earlier 2026-09-06 snapshot: conservative sequential timing, not yet fit

The working tree now sets `ROM_SEQ_WAIT=20` and `ROM_SEQ_RD_HIGH=6` in
`gba_cart_controller.sv`. This replaces 12/4 and matches CartTools' actual
six-clock high, fourteen-clock low sequential RD# waveform. The old 18-clock
CartTools comparison omitted two FSM clocks. `4317h` is a common fast WAITCNT
setting, not the power-on default `0000h`; `docs/CARTRIDGE.md` has the corrected
comparison and its limits. Non-sequential reads and `ROM_BURST=0` are unchanged.

Both containerized ROM benches passed, including the new edge-count
assertions. A full four-halfword request now takes 93 clocks instead of 69
(per-word fallback: 129). These are simulation results, not cartridge
qualification. Repeated ROM hashes and gameplay, including the previously
troublesome carts, are still required. This change does not establish the
cause of the earlier boot failure.

No fit or deployment has been performed for this timing change. Commit the
intended tree before requesting a build through `../tools/runner-build`.
The seed 1 `cfd4264` artifact below does not include this change. Its fit
results remain valid for that older source, not for the current working tree.

## Earlier 2026-09-06 snapshot: the probe fix has a bitstream

`p5-cartridge` is 18 commits past `main` `9002617` plus this docs commit,
unpushed. **`cfd4264` closed at seed 1 on sisko**, Quartus 25.1std, STANDARD
FIT, 1402 s:

| | |
|---|---|
| Setup | **+0.075 ns**, the PLL output path as always |
| Hold | +0.109 ns |
| ALMs | 17,860 / 18,480, 97% |
| Registers | 25,238 |
| RAM blocks | 282 / 308 |
| Package | `build/gba/kroy.GBA_0.9999.cfd4264.zip`, SHA-256 `3526ed6586eefd4ae08d98c0ee07d75ca8d686bc950d61c60b08ee1c894dbda5` |
| Bitstream | `bitstream.rbf_r`, SHA-256 `ab612812d007e8c35bf330def30af98eff5af481a4b7407233e8da39ac1fa37a`, identical inside and outside the zip |

The seed 3 package of the same commit missed timing and is still beside it as
`seed3-FAILED`. The two zips carry the same name apart from that suffix, so the
seed is tracked by the filename and by this table, nowhere else.

Seeds on the fix, Quartus 25.1std, STANDARD FIT, sisko unless noted:

| Commit | seed 8 | seed 1 | seed 2 | seed 3 |
|---|---|---|---|---|
| `60990db` | -0.448 | **+0.075** | -0.562 | **+0.092** (kira) |
| `cfd4264` | untried | **+0.075** | untried | -0.098 |

**The runner's `fetch` refused this job**: "expected one checkout, found 2".
It resolves a checkout by commit, and sisko holds both the seed 3 and the seed
1 checkouts of `cfd4264`. The files were copied by hand from the job's own
directory, `checkouts/pocket-gba-gba-p5cart-s1-cfd42641332a/build/gba`, the same
set `fetch` copies. Reported to the orchestrator; the tool is its to change.
Nothing on the runner was deleted.

**Next, in order.**

1. Install the seed 1 package on the card, merge not replace, hash-verify
   `bitstream.rbf_r` against the value above, unmount.
2. Set Cartridge to `Detect`, restart with Minish Cap in the slot, read `CS:`.
   Expected low byte `E1`, bits 15:8 `96`, `CG:` = `BZME` as hex, which the
   menu prints as `1113214277`. Anything else: `docs/CARTRIDGE.md` decodes it.
3. If `E1`, set `Boot`. This older artifact uses the 12/4 sequential window.
   The current working tree changes it to 20/6, matching CartTools' sequential
   edge counts, but needs a new fit. `ROM_BURST=0` is a separate diagnostic
   fallback. Neither change has been qualified in this core on hardware.
4. Still unchecked on the same visit: a card ROM with the setting `Off`, and a
   cold core load with `Detect` persisted.
5. No GBA tag until a cartridge boots.

**Alignment with the other cores, checked today.** `release.yml` is
verify-only and gated on `main`, as in the other repos. `core.json` declares
`version_required` 1.2 and the cartridge adapter exactly as CartTools does.
The README's version paragraph now says what PCE's and CartTools' say: every
project sits at 0.9999, the number is not shared, a tag adds the short SHA.
The two stale pre-move worktree paths in this file are gone.

**Do not trust any area figure from `exp-cart-probe`.** Measured at Quartus
21.1: the probe build has about 1,000 fewer registers inside `gba_top` than
`main` does, and about 1,150 fewer ALMs overall. Adding a 905-line controller
cannot shrink the core, so the probe wiring left part of `gba_top` unreachable
and the fitter deleted it. The integrated build restores them. The probe's
"859 ALMs", "1,004 ALMs" and "1,151 ALMs" controller costs are therefore
measurements of a partially deleted design and none of them is a cost. Not
rechecked at 25.1, but the cause is structural rather than version specific.

## 2026-09-05: the cartridge branch, one hardware run, one fix, no bitstream

**Branch** `p5-cartridge` at `cfd4264`, 16 commits past `main` `9002617`,
unpushed. Everything is committed.

**What happened.** Seed 3 of `60990db` was installed on the card and hash
verified. Booting Minish Cap from the slot froze at the GBA logo. The menu read
`CG:` 0 and `CS:` `0x000000B0`: probe done, timed out, nothing read. The cause
is the probe starting on `dataslot_allcomplete` while the controller resets on
APF `reset_n`, and the Pocket sends allcomplete before Reset Exit, so every
boot-time probe asked a controller in reset. `docs/CARTRIDGE.md` "First
hardware run" has the decode; the Analogue docs do not state the command order,
the readout is the evidence.

**The fix** is `cfd4264`: `~reset_n_s` added to the probe's reset condition in
`core_top.sv`. No testbench covers the probe. Proven only by a build and the
slot.

**Fits, Quartus 25.1std, STANDARD FIT**, all in `docs/BASELINE.md`:

| Commit | Seed | ALMs | Setup | Hold | Runner |
|---|---|---|---|---|---|
| `60990db` | 8 | 17,779 | -0.448 | | sisko |
| `60990db` | 2 | 17,821 | -0.562 | | sisko |
| `60990db` | 3 | 17,828 | +0.092 | +0.111 | kira, 2010 s |
| `60990db` | 1 | 17,910 | +0.075 | +0.037 | sisko, 1376 s |
| `cfd4264` | 3 | 17,744 | **-0.098** | +0.024 | sisko, 1430 s |

The `cfd4264` seed 3 package is in `build/gba` renamed `seed3-FAILED`. Do not
flash it.

**The card** still holds the seed 3 build of `60990db`, the one that froze.
The released `v0.9999` is not on it.

**Tomorrow, in order.**

1. Fit `cfd4264` at seed 1 on sisko: `SEED=1 ../tools/runner-build start sisko
   pocket-gba gba p5cart-s1 cfd4264`, then `job` to poll and `fetch`. Seed 1
   closed on the previous commit. If it misses, try 2 and 3 on both runners.
2. Install the passing package, set Cartridge to `Detect`, restart with Minish
   Cap in the slot, read `CS:`. Expected low byte `E1` and bits 15:8 `96`;
   `CG:` should be `BZME` as hex. Then `Boot`.
3. Still unknown and worth checking on the same visit: whether a card ROM boots
   on this build with the setting off, and whether the persisted `Detect`
   setting probes correctly on a cold core load rather than only after a menu
   toggle.
4. No GBA tag until a cartridge boots. The release condition was a hardware
   test and the first one failed. When it passes, rebuild the tagged commit at
   the seed that closed, publish by hand as the other cores were (workflow
   disabled, signed tag, `gh release create --verify-tag`), and re-enable.

**Also stale in the README on `main`:** "five projects share one version
number". Every project sits at `0.9999` and they are not in step.

# Handoff, 2026-08-30

State of the fork as of 2026-08-30. Written so the work can be picked up cold.
Read this after the section above, then `PLAN.md` for the design and `BASELINE.md` for the fit
history.

## Resolved: the fit problem below is solved

Everything from "Measured results" down was written on 2026-08-24, while
P1+P2 were missing setup by a reproducible 0.45 ns. It is kept because the
fifteen builds it records are what ruled out the fitter, the seed, the entry
count and the feature strip as answers, and that negative evidence is the
reason the eventual fix was the right one to reach for.

The fix was P3: stop parsing ASCII on the FPGA. `tools/cheats/cht2bin.py`
converts a `.cht` to a 16-byte-per-entry `.chtbin` on the host, and
`src/fpga/core/cheat_binloader.sv` replaces the 648-line parser with a byte
counter and a 72-bit shift register. 441 ALMs and 12.7 % of all
physical-synthesis churn became 61 ALMs and none.

| | ALMs | RAM | Setup |
|---|---|---|---|
| upstream v0.6.2 baseline | 16,648 (90 %) | 278 | +0.090 |
| P1+P2, ASCII parser | 17,903 (97 %) | 284 | −0.452 |
| **P1+P3, `.chtbin`** | **16,689 (90 %)** | **282** | **+0.090 met** |

Reproduced on CI at a different processor count, agreeing in every figure.
`docs/BASELINE.md` records an earlier 17,544 reading of the same design that
nothing has been able to repeat.

It closes at exactly the margin upstream itself ships. Merged as `d7a2138`; format contract in `docs/CHEATBIN.md`.

**This has since run on a Pocket.** The core boots, a `.chtbin` loads, a code
takes effect in game and the toggle works live. Two items on `docs/HARDWARE.md`
are still unwalked: the stray `.cht`, and sleep with the engine running.
Simulation was green end to end throughout (24 converter, 19 binloader, 10
fixture, 9 e2e, 513 corpus).

## Standing constraints

- **Nothing is pushed to any remote.** Not `origin`, not anything. The user set
  this explicitly and it has not been lifted.
- **Nothing merges into `master` from a build that fails timing.** P3 satisfied
  this; the rule stands for the cartridge work. CI enforces the release half of
  it: a tag that is not on `master` is refused, and a build that misses timing
  refuses to publish.
- **Run every fit comparison at STANDARD FIT** (finding 1 below), or the delta
  is not attributable to the change you made.
- Upstream attribution stays: `info.txt`, `FUNDING.yml`, git history, the
  `upstream` remote.

## Measured results

All numbers from `tools/podman/report.sh`, worst slack across all corners.
Device is 5CEBA4F23C8: 18,480 ALMs, 308 RAM blocks. `clk_sys` at ~100.66 MHz
is the GBA domain and carries every worst-case path.

| # | Design | Fitter | Seed | ALMs | RAM | Setup | Verdict |
|---|---|---|---|---|---|---|---|
| A | upstream, no cheats | AUTO | 8 | 16,648 (90 %) | 278 | **+0.090** | met |
| B | P1 engine only | AUTO | 8 | 16,624 (90 %) | 281 | **+0.090** | met |
| C | P1+P2 | AUTO | 8 | 17,909 (97 %) | 284 | −0.846 | fail |
| D | P1+P2 | STANDARD | 8 | 17,903 (97 %) | 284 | −0.452 | fail |
| E | P1+P2, 16 entries | AUTO | 8 | 17,980 (97 %) | 284 | −0.711 | fail |
| F | P1+P2, 16 entries | AUTO | 8 | 17,980 (97 %) | 284 | −0.711 | fail, exact rerun of E |
| G | P1+P2 | AUTO | 2 | 17,988 (97 %) | 284 | −1.321 | fail |
| H | P1+P2 | STANDARD | 3 | 17,871 (97 %) | 284 | −0.453 | fail |
| I | P1+P2 | AUTO | 5 | 17,961 (97 %) | 284 | −0.887 | fail |
| J | P1+P2, **link stripped** | AUTO | 8 | 17,686 (96 %) | 284 | −0.445 | fail |
| K | link stripped | STANDARD | 8 | 17,594 (95 %) | 284 | −0.711 | fail |
| L | link stripped, dup OFF, combo-for-area ON | STANDARD | 8 | 17,594 (95 %) | 284 | −0.711 | fail, **identical to K** |
| M | P1+P2, `cheat_loader` multicycle 4 | STANDARD | 8 | 17,929 (97 %) | 284 | −0.600 | fail, see below |
| N | P1+P2, phys-synth effort NORMAL | STANDARD | 8 | 17,903 (97 %) | 284 | −0.452 | fail, **identical to D** |

## What those numbers establish

1. **Only STANDARD FIT measures the design.** Three AUTO FIT seeds gave
   −0.846 (seed 8), −0.887 (seed 5) and −1.321 (seed 2). Two cluster within
   0.04 ns and one sits 0.44 ns away, so AUTO FIT is not uniformly noisy: it
   occasionally throws a much worse placement, and a single run cannot tell you
   which kind you got. STANDARD FIT gave −0.452 (seed 8) and −0.453 (seed 3),
   one picosecond apart. **Run every future comparison at STANDARD FIT** or the
   delta is not attributable to the change you made.
2. **The real gap is 0.45 ns**, not the −0.85 the first run suggested.
3. **STANDARD FIT is worth ~0.39 ns at zero area cost** (C vs D, same seed).
   It is strictly better here and should probably become the default in the
   qsf if a closing build uses it.
4. **Seed hunting is not a fix.** It is a tiebreaker for a design already
   within a few hundredths. This one is not.
5. **E and F are byte-identical.** Same inputs and seed produce the same fit,
   so numbers are comparable across worktrees. The harness is trustworthy.
6. **The 16-entry lever is dead.** Halving `CHEATCOUNT`/`MAX_ENTRIES` made the
   design *larger* (17,980 vs 17,909) and slower. Both cheat tables already
   live in RAM blocks, so shrinking the entry count buys no ALMs and only
   perturbs placement. Do not retry this.
7. **The failure is congestion, not a slow new path.** All 44 violating paths
   are pre-existing core paths: `gba_memorymux|vram_cycle` → `gba_cpu`,
   `gba_cpu|new_cycles_valid`, `gba_memorymux` → `gba_dma`. The cheat logic
   itself is not on any critical path. `gba_cpu` gained 369 ALMs with no
   source change at all, purely from physical-synthesis register duplication
   under pressure.
8. **Area does not buy slack here, and the "135 ALMs per 0.1 ns" rule was
   wrong.** Run K removed 309 ALMs from run D and *lost* 0.26 ns
   (−0.452 to −0.711). At AUTO FIT the same strip gained 0.40 ns (C to J). The
   two fitter modes disagree on the sign of the same change. Do not size a cut
   by expected slack return; there is no reliable conversion.
9. **Runs K and L are identical to the digit** despite L disabling register
   duplication and enabling combinational-logic-for-area. The fitter settings
   tables confirm the options differed, so those two settings changed nothing.
   The build log shows why: only **register retiming** and **combinational
   resynthesis** ever execute. No duplication pass runs at all in Quartus Lite,
   whatever the qsf says. Do not spend another build on those two knobs.
10. **Correction: `gba_cpu`'s +369 ALMs are not from register duplication.**
   Duplication never runs (finding 9). The growth is retiming, which the log
   credits with 4,129 ps of estimated improvement.
11. **`PHYSICAL_SYNTHESIS_EFFORT` is inert too.** Run N with NORMAL instead of
   EXTRA is byte-identical to run D. That is the third dead knob. Assume the
   remaining physical synthesis settings do nothing in Lite unless a log line
   proves otherwise.
12. **The multicycle constraint worked and did not help, which kills the
   congestion theory.** Run M cut 402 registers (24,696 to 24,294) and 14 % of
   all physical-synthesis churn (5,973 to 5,155 nodes), so retiming genuinely
   backed off. ALMs moved +26 and slack got *worse*, −0.452 to −0.600. The
   manufactured registers were never the cost. **The cost is the parser's
   combinational logic, which exists no matter how the fitter treats it.**

## Area budget

Measured module costs from the fit reports:

Numbers are as attributed by the fit report. See the link-strip section below:
**actual recovery ran at about half the attributed cost**, so treat these as
upper bounds.

| Module | ALMs | Notes |
|---|---|---|
| `gba_sound` | 973 | cutting this means no audio, non-starter |
| `cheat_loader` | 441 (+65 data_loader) | the feature itself |
| `gba_serial` | 417 | **being stripped**, see below |
| `gba_gpioRTCSolarGyro` | 341 | RTC (Pokémon time events), solar (Boktai), gyro (WarioWare Twisted) |
| `gba_savestates` | 297 | |
| `save_state_controller` | 239 | |
| `gba_cheats` | 151 | the engine, nearly free |

Already decided as droppable by the user: the OSD overlay menu ("ultimately
unneeded assuming the cheats work and the on/off toggle work too"), and the
partial link cable.

## The link strip (branch `exp-nolink`, commit `e3c6d64`)

mincer-ray's v0.5.0 added a partial 2-player link. Stripping it **recovers 223
ALMs**, measured (run J against run C, same fitter and seed), and 0.40 ns of
setup at AUTO FIT.

Note the gap between that and `gba_serial`'s 417 ALMs in the fit report. The
strip returned 53 % of the module's listed cost, because the module is not
deleted but replaced by a stub that still costs something, and because
module-level attribution does not capture how the fitter redistributes logic.
**Read every figure in the area budget above as an upper bound on what cutting
it would actually return**, likely around half. That reframes the remaining
candidates: `gba_savestates` plus `save_state_controller` are quoted at 536
together but should be expected to yield roughly 300.

The strip is a **restoration, not a rewrite**: `gba_serial.vhd` is
restored from commit `7cd1ac6`, the 67-line register-only stub that shipped
before the link redo (PR #31 / commit `69ebe91`). That stub still answers on
the SIO registers with no-cable-present semantics (`SIOCNT` readback forces
bit 7 = 0 and bit 6 = 1, `SIOMULTI`/`SIODATA32` read `0xFFFF`), so a game
probing for a link partner finds none instead of hanging on a bus that never
acks.

A plain revert of PR #31 was deliberately **not** done: that commit also
carried unrelated `gba_cpu`, `gba_memorymux` and drawer accuracy fixes, which
the targeted strip keeps.

Also changed: twelve `serial_*` ports removed from `gba_top`'s entity, the
multiplexed drive logic on `port_tran_*` in `core_top.sv` replaced with
tri-state tie-offs, `"link_port": false` in `core.json`, README moved link
from features to not-included with the reason.

## Fitter settings: no free headroom

Checked before assuming otherwise. Upstream's `ap_core.qsf` **already** runs
every aggressive lever: `PLACEMENT_EFFORT_MULTIPLIER 4.0`,
`ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM`, `PHYSICAL_SYNTHESIS_EFFORT EXTRA`,
register duplication ON, retiming ON, combo logic ON, `ECO_OPTIMIZE_TIMING ON`.
mincer-ray was clearly already fighting this same margin. Do not go looking for
an unused speed setting; there isn't one.

The two settings still untried both bias toward **area** rather than speed,
which is the right direction when the failure is congestion:
`PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION OFF` and
`PHYSICAL_SYNTHESIS_COMBO_LOGIC_FOR_AREA ON`.

## In flight at handoff time

Nothing. The four builds that were running on 2026-08-24 all finished and are
runs I, J, K and L in the table above. The commands that produced them are in
"Re-running the in-flight builds" below, kept because the branches still exist.

## Feasibility verdict: delete the ASCII parser, do not shrink it

Fifteen builds. Nothing has ever come closer than −0.445 ns. Two fitter modes,
four seeds, an entry-count halving, a feature strip, three fitter knobs and a
timing constraint have all failed to move it toward zero, and three of those
knobs turned out to do nothing at all in Lite. **There is no tuning left that
should be expected to find 0.45 ns.** Stop looking for one.

The problem is narrow, which is the good news. **P1, the cheat engine, is
free**: 16,624 ALMs and +0.090 ns, slightly better than baseline. Every bit of
the damage comes from P2, and specifically from the fact that `cheat_loader`
parses ASCII. It carries a 64-bit token shift register, hex nibble conversion,
quoted-string tracking, key matching, a CodeBreaker pair collector and a wide
decoder. That turns a module measuring 506 ALMs into 1,285 ALMs of design
growth and 0.54 ns of slack, and run M proved the growth is combinational and
therefore not something the fitter can be talked out of.

**The fix is to stop parsing ASCII on the FPGA.** Convert `.cht` to a packed
binary on the host, and the on-chip loader becomes a byte counter feeding a
128-bit shift register with a write strobe: no hex conversion, no tokeniser, no
key matching, no state machine. Estimate 60-120 ALMs against the current 441,
with far less for the fitter to inflate. P2 needs to cost about 300 ALMs of
growth instead of 1,285, which is well within reach when the parser is deleted
rather than shrunk.

This also fits the tooling that already exists. The cheats GUI in the GBC fork
is the natural place to emit the binary, and the 513-file corpus becomes the
conversion test set instead of an RTL test set, so the parsing logic keeps its
coverage on the host where it is much easier to verify.

**The cost is a usability regression**: a `.cht` dropped straight onto the SD
card stops working, and has to go through the converter first. That is a user
call. It is the only path found that does not give up save states or the RTC,
and unlike those it is not a gamble, because finding 8 says a feature cut is
not even guaranteed to buy slack.

### P3, delivered: the binary format

Format pinned in `docs/CHEATBIN.md`; converter in `tools/cheats/cht2bin.py`;
loader in `src/fpga/core/cheat_binloader.sv`. All merged via `p3-format` ->
`p3-converter` + `p3-binloader` -> `p3-binary` -> `d7a2138`.

The converter is a thin wrapper, not a reimplementation: `tools/cheats/gbacht.py`
was already the Python reference model for the RTL and exposes `parse()` and
`words()`, so the parsing logic that left the FPGA had been sitting in the repo
as the thing that validated it.

The file stores the 128-bit words verbatim, so the loader does no
transformation. Two things in the format are load-bearing and easy to get
wrong:

- **Entry order matters.** A conditional is a compare entry immediately
  followed by the entry it guards. Nothing may sort, dedupe or reorder.
- **The header magic is a safety interlock, not decoration.** The previous
  format was a plain `.cht`, so someone dropping the old file in is a real
  scenario, and shifting ASCII into the cheat table would corrupt the game.
  Wrong magic or version loads zero entries.

Outcome against the target: P2's growth was 1,285 ALMs, the goal was about 300,
and the measured cost is **61 ALMs with zero physical-synthesis churn**.
`cheat_loader.sv` is still in the tree and is not dead code: `tools/sim/run.py`
compiles it as the reference that cross-checks `gbacht.py`, which is what the
shipping converter parses with.

### What was tried and did not work, so it is not retried

The section below is kept because the reasoning was sound and the measurement
is what refuted it. Constraining `cheat_loader` was the best available theory
until run M tested it.

## Superseded: constrain `cheat_loader` instead of cutting features

Counting every node physical synthesis modified, retimed or created in run L:

| Module | nodes touched | share | share of area |
|---|---|---|---|
| `gba_top` (the whole emulator) | 6,267 | 85 % | ~95 % |
| **`cheat_loader`** | **930** | **12.7 %** | **2.5 %** |
| `save_type_detector`, `sdram_pocket`, `data_loader`, others | 139 | 2 % | |

`cheat_loader` absorbs five times its share of optimisation effort. The named
nodes are its parser arithmetic: `Add4`, `Add6`, `Add7`, `Decoder0`, each
spawning `_OTERM` retimed registers and `_RESYN*_BDD*` resynthesised nodes.

This explains the amplification that has been the real problem all along. P1
alone was free (16,624 ALMs, +0.090 ns). Adding P2 took it to 17,909, a jump of
**1,285 ALMs for a module that measures 506**, and registers rose only 433, so
the growth is combinational.

**The effort is being spent on something that does not need it.**
`cheat_loader` parses a `.cht` file once at load time. It has no gameplay
timing requirement, it is not in the video or CPU path, and none of the 44
violating paths touch it. The fitter has not been told any of that, so it
retimes a file parser as though it were critical, manufacturing area that
congests the paths that genuinely are.

So the next move is a constraint, not a cut. In the SDC, declare
`cheat_loader`'s internal paths false or multicycle and let the fitter stop
paying for speed nobody needs. Ranked by how much it gives up:

1. **`set_multicycle_path` on `cheat_loader` internals.** Costs nothing, the
   parser has hundreds of idle cycles per byte. Try this first.
2. **`set_false_path`**, if the parser is fully self-timed and its outputs are
   only sampled after a done handshake. Verify the handshake before claiming
   it, since a wrong false path is a silent hardware bug rather than a build
   error.
3. **Restructure the parser RTL** to shorten the combinational adder and
   decoder chains, so there is less for retiming to find.

If this works it preserves **every** feature, and the link cable strip on
branch `exp-nolink` may not be needed at all. Do not merge the strip until this
has been tried; run K shows it does not help timing at STANDARD FIT anyway.

## Branch map

The thirteen experiment worktrees under `~/Desktop/repos/` were removed on
2026-08-26. **Every branch survives** in the main repo's `.git`; the worktrees
were only checkouts. None of them is on the remote and none should be: `origin`
carries `master` alone. `git worktree add ../<dir> <branch>` brings any of them
back. Nothing is pushed to any remote; `origin` holds only upstream's `master`
and `rumble-support`.

| Branch | Tip | Holds |
|---|---|---|
| `master` | (tip) | **the integration branch**, and the only one on the remote. P1 + P3, closes timing. Releases are built from here and CI refuses a tag that is not on it. |
| `p5-cartridge` | `97e1e0b` | **the cartridge branch.** Slot declared and powered, header probe, ROM out of the cart. First hardware run froze at the GBA logo; the fix is `cfd4264` and has never been fit. See the top of this file. |
| `p3-binary` | `d7a2138`^ | P3 assembled: format, converter, binloader. Merged. |
| `p3-format` / `p3-converter` / `p3-binloader` | | the three P3 strands, merged into `p3-binary`. |
| `p2-cheat-loader` | `c7aebd5` | P1+P2 with the ASCII parser. The design that failed timing. |
| `p1-cheat-engine` | | P1 alone, the build that proved there was room for the engine. |
| `exp-nolink` | `e3c6d64` | P2 plus the link-cable strip. **Retire, do not merge:** run K showed the strip does not help, and `master` closes with the link intact. |
| `exp-nolink-g` | `40ac38c` | as `exp-nolink` at STANDARD FIT (run K). |
| `exp-nolink-h` | `0e807d6` | as G plus area-biased physical synthesis (run L). |
| `exp-standard-16` | `47496dc` | the dead 16-entry lever, kept for reproducibility. |
| `exp-seed2` | `fcc3fae` | seed 2 roll (run G). |
| `exp-16entries` | `fcc3fae` | misleading name, clean at 32 entries; the seed 5 roll (run I). |
| `exp-cheat-mcp` | | the multicycle constraint (run M). |
| `exp-psnormal` | | `PHYSICAL_SYNTHESIS_EFFORT NORMAL` (run N). |
| `master` | | upstream v0.6.2, untouched. |

Two git-ignored things went with the worktrees, both regenerable:

- **The 513-file `.cht` corpus.** Re-fetch from libretro-database,
  `cht/Nintendo - Game Boy Advance`, and either drop it at `external/cht` or
  pass `CHT_DB=`. Without it `make test` skips the two corpus passes and says
  so; it does not silently pass.
- **Every built bitstream**, including the one that closed. Rebuild from
  `master` with `make gba FITTER_EFFORT="STANDARD FIT"`, about 23 minutes.

## Next steps, in order

1. **Hardware validation, mostly done.** `docs/HARDWARE.md` is the checklist,
   with the expected `CL:` value worked out for each case. Everything below has
   been seen work on a Pocket except the last item, and sleep with the engine
   running is still unreported. What had to be seen:
   - the core boots a ROM at all, i.e. P1's engine did not break the build;
   - `<rom>.gba.chtbin` loads and the `CL:`/`CD:` menu readouts show a
     plausible entry count;
   - a code visibly takes effect in-game;
   - the Cheats Enabled toggle turns it off and back on live;
   - a stray `.cht` renamed to `.chtbin` loads **zero** entries rather than
     corrupting anything. This is what the `GBAC` magic is for and it is the
     one failure mode simulation cannot fully vouch for.
2. **P8 packaging**, done for the cheat feature: shipped as v0.9999.
3. **Cartridge (P5) is under way on branch `p5-cartridge`, and the sizing
   question this item used to propose has been answered.** Wokann's
   `gba_cart_controller.sv` and `rom_source_mux.sv` are vendored verbatim under
   Wokann's authorship, instantiated rather than merely listed in the qsf, and
   `gba_top`'s ROM reads run through the mux with the cart side idle and
   `cart_mode` off a live register, so nothing folds away and the measurement is
   real.

   Nine builds on one host: `main` `6994156` at 17,744 ALMs (96 %) and +0.059 ns
   setup, the branch at -0.410, -0.125 and **+0.087** on seeds 1, 2 and 3. **It
   closes on one placement seed in three**, and what fails on the other two is
   the PLL output counter that is already `main`'s worst path, not anything in
   the controller. An initial 1.191 ns miss was entirely three configuration
   inputs sharing a register with the per-access inputs; splitting them out with
   a multicycle of 4 recovered all of it, and the bus logic met 100 MHz unaided.

   **The area half of this item cannot be answered.** Identical RTL spans 81
   ALMs across seeds, which is the size of the thing being measured, so the
   1,791-ALM headroom figure above cannot size a 905-line module, and the
   "640 ALMs left" reading taken mid-branch is **withdrawn**. Slack across
   several seeds is the measure now. Also still unexplained: 16,689 ALMs on the
   workstation and in CI against 17,744 on the build runner, for identical RTL.

   What is left is listed in `PLAN.md` §2b: the APF declaration, the cart pin
   handover, detection and header read, ROM read speed, save/EEPROM/GPIO routing
   and `save_size = 0` in cart mode. All but the ROM boot path already exist on
   `wokann/master`, debugged on real hardware, so they are there to import
   rather than to solve.

   Tables in `docs/BASELINE.md`. Note that `mincer-ray/openfpga-GBA` reports
   `parent: none` - it is the root of the lineage, so there is no better base to
   rebase onto; all 14 forks are downstream additions. Upstream has not moved
   since v0.6.2, so no rebase is pending.
4. **Retire `exp-nolink`.** Do not merge it. See the branch map.
5. **P4 (OSD) is closed, not deferred.** The user has confirmed the overlay is
   not wanted. The `CL:`/`CD:` menu readouts carry the diagnostics.

## Re-running the in-flight builds

Historical. The G and H runs were local worktrees beside the repo,
`pocket-gba-g` and `pocket-gba-h`, which no longer exist; their results are in
the tables above. A fit of any commit now goes through the orchestrator's
restricted interface, from this directory:

```sh
SEED=<n> ../tools/runner-build start sisko pocket-gba gba <job> <commit>
```

`make report` re-renders `build/gba/report.txt` from existing outputs without
recompiling. `make gba SKIP_COMPILE=1` repackages the SD tree and zip from an
existing `.rbf`.

## Harness gotchas that cost time already

- `FITTER_EFFORT` and `NPROC` only landed on the integration branch at
  `e5656b6`. Worktrees
  branched before that **silently ignore them** as unset variables, and the run
  measures AUTO FIT while the command line says STANDARD. Check
  `grep FITTER_EFFORT tools/podman/build.sh` in any worktree before trusting a
  result. This already invalidated one run.
- Makefile quoting: `FITTER_EFFORT="$(FITTER_EFFORT)"`. Unquoted, `STANDARD FIT`
  splits and you get `FIT: command not found`.
- **Quartus exits 0 on failed timing.** `report.sh` is what catches it: exits 3
  and touches `TIMING_FAILED`. Never judge a build by its exit code alone.
- Use `set -o pipefail`. `make gba | tail` reports success for a failed build.
- Invoke `quartus_sh` directly, never through `bash -lc`. The image sets PATH
  via ENV and a login shell resets it.
- `podman pull` needs an empty authfile if a stale docker.io login is present.
  See `tools/podman/README.md`; do not touch the user's credentials.
- A build is ~19-25 min alone. Five concurrent on 14 cores stretches it to ~50
  min at load 42. Do not run more than three at once.
- A `report.txt` in a worktree may be **stale** from a previous run while a new
  build is still going. Check `TIMING_FAILED` mtime against the build log.

## Simulation

Green end to end on `master`, and it always was: the fit problem was never a
correctness problem. `make test`:

| Pass | Result | Covers |
|---|---|---|
| `test_cht2bin.py` | 24/24 | the converter, including three hand-computed entries with derivations and a cross-check against an encoder nobody here wrote |
| `run_binloader.py` | 19/19 | `cheat_binloader.sv`. Mutation-verified: reversing the shift loses 10 cases, delaying `cheat_on` loses exactly the two zero-gap cases |
| `run_fixtures.py` | 10/10 | known-good words |
| `run_e2e.py` | 9/9 | `.cht` in, cheat table out |
| `run.py` | 513/513 | the whole libretro GBA corpus, RTL parser against `gbacht.py` |

The last two want the corpus; see the branch map for where it went and how to
get it back.
