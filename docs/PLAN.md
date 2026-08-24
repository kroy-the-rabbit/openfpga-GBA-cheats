# Plan: cartridge support and cheats for `kroy.GBA`

Fork of https://github.com/mincer-ray/openfpga-GBA (Pocket port of
`MiSTer-devel/GBA_MiSTer`), tracked here as `upstream`. Two goals, in this
order of confidence:

1. **Cheats.** Game Genie-style patches and GameShark-style pokes read straight
   from a libretro `.cht` file, the same user-facing contract as
   [openfpga-GBC-cheats](https://github.com/kroy-the-rabbit/openfpga-GBC-cheats).
2. **Physical cartridges.** Boot and play a real GBA cart in this core, so the
   cheat engine, the display modes and fast forward apply to cart games.

Neither exists in any shipping GBA core today. The cheat half is a re-port of
code that exists upstream in MiSTer; the cartridge half is genuinely new work
with two partial implementations to draw on.

---

## 0. Where this fork stands

| | |
|---|---|
| Base | `upstream/master` v0.6.2 (`b08568f`, 2026-06-16) |
| Branch | `cheats` |
| Core identity | `pkg/Cores/kroy.GBA`, author `kroy`, description `Game Boy Advance (cheats)` |
| Platform id | `gba`, unchanged, so `/Assets/gba/common` is shared with any other GBA core |
| Licence | upstream MiSTer core is GPL-2.0 (`pkg/Cores/kroy.GBA/info.txt`); no LICENSE file in the port, so per-file notices and that info.txt govern |

Remotes, and what each is for:

| Remote | Repo | Why |
|---|---|---|
| `origin` | `kroy-the-rabbit/openfpga-GBA-cheats` | this fork |
| `upstream` | `mincer-ray/openfpga-GBA` | the live core, still moving |
| `wokann` | `Wokann/openfpga-GBA` | cartridge bus controller, furthest along |
| `rai` | `Rai/openfpga-GBA` branch `feat/cartridge-support` | ROM-from-cart path and the APF plumbing |

Identity rename: only `author`, `description` and `url` in
`core.json` changed, plus the folder name that follows `author`. `info.txt` and
`.github/FUNDING.yml` keep mincer_ray's and MiSTer's attribution verbatim, and
upstream history is intact in git. Same pattern as the GBC fork. The cost of the
rename is that the Pocket sees a different core id, so `/Settings/mincer_ray.GBA`
does not carry over; saves are per-platform and are unaffected.

---

## 1. Findings from the repo

### 1a. The cheat engine was cut in the port, and the hook it needs is still there

`grep -ri cheat` over this tree returns nothing. Upstream MiSTer has
`rtl/gba_cheats.vhd` (293 lines), and, crucially, the arbiter it hangs off
survived the port.

| Thing | Upstream MiSTer | This repo |
|---|---|---|
| Cheat module | `rtl/gba_cheats.vhd`, `entity gba_cheats` | absent |
| `gba_top` ports | `cheat_clear`, `cheats_enabled`, `cheat_on`, `cheat_in[127:0]`, `cheats_active` (`rtl/gba_top.vhd:61-66`) | absent |
| Bus master arbitration | `Cheats_Bus*` branch in the debug-bus process | absent, but `GBA_Bus*` and `SAVE_Bus*` branches remain at `src/fpga/gba/gba_top.vhd:393-419` |
| CPU pause during poke | `sleep_cheats` in the run condition (`rtl/gba_top.vhd:1088`) | the same condition is `src/fpga/gba/gba_top.vhd:976`, with `sleep_savestate` and `sleep_external` but no `sleep_cheats` |
| Code delivery | `GBA.sv:424-428`, HPS ships pre-decoded 128-bit words | absent, Pocket has no HPS |

So the restore is: add the five ports back to `gba_top`, add a third branch to
the debug-bus process next to `SAVE_Bus_ena` at `gba_top.vhd:406`, add
`sleep_cheats` to the run condition at `gba_top.vhd:976`, instantiate
`gba_cheats`, and add both files to the source list in
`src/fpga/build/ap_core.qsf` (every file is listed explicitly there, around
line 829). `SyncFifo.vhd`, which `gba_cheats` instantiates, is already in the
tree.

### 1b. What `gba_cheats` actually expects, decoded from its RTL

One cheat is a 128-bit word. There is no documentation for the layout, so this
is read off `gba_cheats.vhd` directly:

| Bits | Meaning |
|---|---|
| `31:0` | replacement value, and *also* the operand for a compare entry |
| `63:32` | not read by the module |
| `91:64` | 28-bit GBA bus address |
| `95:92` | not read |
| `99:96` | optype: `0` always, `1` `=`, `2` `>`, `3` `<`, `4` `>=`, `5` `<=`, `6` `!=`, `F` empty slot |
| `103:100` | byte enables for the four bytes of the value |

Behaviour worth knowing before writing the loader:

- 32 entries (`CHEATCOUNT`), loaded through a `SyncFifo` on the rising edge of
  `cheat_on`, and matched to the free slot marked `OPTYPE_EMPTY`.
- All bus accesses are 32-bit (`BusACC <= ACCESS_32BIT`); byte granularity comes
  from the read-modify-write plus the byte-enable nibble.
- It is a **poker, not a read override**: on `vsync` it waits for the memory bus
  to go idle (`bus_ena_in` low for `SETTLECOUNT` cycles), raises `sleep_cheats`
  and writes each entry through the debug bus. That covers EWRAM, IWRAM, IO and
  save memory, which is where GBA codes point in practice.
- **Conditional codes are entry pairs.** A non-`ALWAYS` entry sets `skip_next`
  when its test fails, which suppresses the *following* entry. The loader must
  emit condition and write as two consecutive entries, in that order, and count
  them against the 32-entry budget.

### 1c. Hook points in this repo

- `src/fpga/core/core_top.sv:1269` - bridge read mux: `0x2xxxxxxx` save,
  `0x4xxxxxxx` savestate, `0xF8xxxxxx` command. Everything else reads 0.
- `src/fpga/core/core_top.sv:1356` - bridge write decode: `0xF0000000` reset,
  `0x80`/`0x84`/`0x88`/`0x8C` menu settings. **`0x90` onward is free** for a
  cheat enable, and `0x5xxxxxxx` is free as a cheat data-slot window (`0x1`,
  `0x2`, `0x3`, `0x4` are ROM, save, BIOS, savestate).
- `src/fpga/core/core_top.sv:354`, `:803`, `:1012` - three existing
  `data_loader` instances (save, ROM, BIOS). A fourth for cheats is a copy of
  the BIOS one with a different window.
- `pkg/Cores/kroy.GBA/data.json` - slots 1 (ROM), 4 (BIOS), 10 (Save). **Slot 7
  is free**, and the GBC fork already proved the `0x205` parameter combination
  (user-reloadable, filename cloned from slot 0, persist browsed filename) that
  makes `<rom>.gba.cht` load automatically.
- `pkg/Cores/kroy.GBA/interact.json` - 5 of the 16 permitted entries used, all
  `"writeonly": true`. Room for a master cheat switch and a parsed-count
  readout.
- `src/fpga/core/core_top.sv:1575` - `gba_top` is clocked by `clk_sys`, about
  100.66 MHz. Everything below runs in that domain.
- `src/fpga/core/video_adapter.sv` - video is a framebuffer plus raster scan,
  not a scanline pipe like the GB core. The GBC OSD hooks the pixel stream, so
  it has to be re-attached here rather than copied.

### 1d. There is no headroom

From upstream CI run 27648777430, the v0.6.2 build this fork starts from:

| Resource | Used | Available | |
|---|---|---|---|
| Logic (ALMs) | 16,648 | 18,480 | **90 %** |
| RAM blocks | 278 | 308 | **90 %** |
| Block memory bits | 2,056,488 | 3,153,920 | 65 % |
| Registers | 24,249 | | |
| DSP | 26 | 66 | 39 % |
| Pins | 224 | 224 | 100 % |

Worst setup slack is **0.102 ns**, and it is on `clk_sys`, the domain the cheat
engine and any cart controller live in. For comparison, the GBC fork started at
50 % ALMs and 2.374 ns. Every design decision below is downstream of this.

---

## 2. Cartridge support

### 2a. Prior art

Nobody ships it. mincer-ray's issue
[#17](https://github.com/mincer-ray/openfpga-GBA/issues/17) is the request, and
two forks have taken it on.

**`wokann/master`**, 45 commits ahead of v0.6.2, active to 2026-08-13, is the
serious bus work: `src/fpga/han/gba_cart_controller.sv` (905 lines),
`rom_source_mux.sv`, four iverilog testbenches under `sim/han/`, and `HAN.md`
deriving the timing from GBATEK, jojolebarjos/gba-cartridge, insideGadgets
logic-analyser captures and the ChisFlash cart-side firmware. It covers ROM
reads over CS1, SRAM/Flash over CS2 with data on `A[23:16]`, bit-level EEPROM
passthrough over ROMCS/A23, and the GPIO window at `0x080000C4` for RTC. Per
their own notes: SRAM works on hardware, Flash512 reads work, Flash writes
needed a WE#-falling-edge setup fix, EEPROM read sampling was moved after the
RD# rising edge, and the wait-state parameters are still placeholders pending
calibration on real carts. Their goal is not ours: they run a translated ROM
from SD and put only saves, GPIO and EEPROM on the cart, so `han_rom_cart_mode`
(ROM out of the cart) is wired but held at 0.

**`rai/feat/cartridge-support`**, 3 commits, last touched 2026-06-01 and now 27
behind upstream, is the straight "play the cart" attempt:
`src/fpga/core/gba_cart_bus.sv` (351 lines) plus a testbench, EEPROM fixes, and
the APF side nobody else has done - `core.json` `version_required` bumped to
`1.2` and `"cartridge_adapter": "0x01000000"`, which is what makes the Pocket
offer "Play Cartridge" and power the slot. Rai posted a photo of it partly
running and described timing problems.

### 2b. What to take

Take Wokann's controller as the bus layer and Rai's APF plumbing and ROM path.
Neither is a merge: both are built against a moving upstream and one is 27
commits behind. Import them as vendored modules on our own branch, with their
authorship preserved in the commits.

The parts that stay ours to finish:

- **ROM out of the cart at speed.** Wokann's ROM read path exists but has never
  been the boot path. This is the hard part: sequential burst reads with the
  address auto-increment on RD#, feeding the same interface `sdram_pocket.sv`
  serves today, fast enough that the CPU is not stalled to a crawl.
- **The SD/cart source mux.** `rom_source_mux.sv` is the seed; it has to sit
  where the ROM `data_loader` and SDRAM read path meet in `core_top.sv`.
- **Save routing.** In cart mode the cart owns the save. That means reporting
  `save_size = 0` to the Pocket, which Wokann already does, and keeping the
  savestate path honest about memory it no longer owns.
- **Timing.** The level translators have a per-bank direction pin, and the GBA
  bus multiplexes address and data on the same 16 lines, so every access flips
  bank direction mid-cycle. Wokann's parameters are conservative placeholders,
  and calibrating them is hardware work, not simulation work.

### 2c. What cartridge mode gets you for free, and what it does not

Because `gba_cheats` pokes RAM through the internal bus rather than patching
ROM reads, cheats that write EWRAM, IWRAM or IO work identically whether the
ROM came from SD or from the cart. Codes that patch the ROM image itself do not
apply to a cart, since there is nothing writable there.

The APF caveat from the GBC work applies unchanged: in Play Cartridge mode slot
0 is not loaded, so a `.cht` named after slot 0 never loads. Parameter bit 9
(persist browsed filename) is the fallback, exactly as in the GBC core.

---

## 3. Cheats: what ports over from the GBC fork, and what does not

| Module in `openfpga-GBC-cheats` | Fate here |
|---|---|
| `cheat_loader.sv` (379 lines, ASCII `.cht` parser) | ports, back end retargeted to emit 128-bit words instead of the GB code table |
| `cheat_titles.sv`, `cheat_font.sv`, `cheat_osd.sv` | port, but the OSD has to re-attach to `video_adapter.sv`'s framebuffer, and the font ROM is a fit risk at 90 % RAM blocks |
| `cheatcodes.sv` (`CODES`, Game Genie read override) | dropped, `gba_cheats.vhd` replaces it |
| `cheat_poker.sv` (GameShark vblank poker) | dropped, `gba_cheats.vhd` does this properly and through the real bus |
| data slot + interact entries | port, slot 7, `0x50000000`, master switch on `0x90` |
| `tools/sim` harness, `tools/cheats` reference model | port, and extend the reference model to the 128-bit format |

**The loader's new job.** Same tokenizer, different emitter. A GBA `.cht` code
is `AAAAAAAA VVVVVVVV`, eight hex digits of address and eight of value, and the
common raw forms map onto the word from §1b directly:

| Code form | Word |
|---|---|
| `8-digit addr` + `8-digit value`, 32-bit write | addr into `91:64`, value into `31:0`, optype `0`, byte mask `1111` |
| 16-bit write | byte mask `0011` or `1100` by address parity |
| 8-bit write | one byte-mask bit |
| conditional (`if value == X then next`) | condition entry with optype `1`, followed by the write entry |

**The format question that has to be answered before P3.** GameShark v3, Action
Replay v3 and CodeBreaker codes are encrypted with a per-game seed, and a
`.cht` file gives no reliable indication which encoding a code uses. Options:
decrypt in RTL (large, and the seed handling is per-game), decrypt in the
desktop picker
([openfpga-GBC-cheats-ui](https://github.com/kroy-the-rabbit/openfpga-GBC-cheats-ui))
and write plain codes, or support only the unencrypted forms and say so. Given
§1d, the picker is the honest answer, at the cost of the "drop any file in and
it works" property the GBC core has. Decide before writing the emitter.

---

## 4. Phasing

| Phase | Deliverable | Done when |
|---|---|---|
| **P0** | Reproducible local build. Upstream ships `scripts/build.sh` on `raetro/quartus:21.1` under Docker plus `print_timing.sh`, `seed_sweep.sh` and custom STA reports. Convert to Podman to match the GBC harness, keep Quartus 21.1, and make the wrapper fail the build on negative slack the way `tools/podman/build-core.sh` does in the GBC repo. | Unmodified v0.6.2 builds locally, boots a ROM on hardware, and `docs/BASELINE.md` carries our own numbers next to upstream's. |
| **P1** | Restore the cheat engine: `gba_cheats.vhd` and `SyncFifo` wiring, the five `gba_top` ports, the third debug-bus branch, `sleep_cheats` in the run condition, qsf entries. Feed it one hardcoded 128-bit word. | A hardcoded code visibly takes effect on hardware, and the fit report still closes. This is the phase that answers whether there is room at all. |
| **P2** | Data slot 7, a fourth `data_loader`, `cheat_loader.sv` ported with the 128-bit emitter, master switch on `0x90`. | A `.cht` next to the ROM applies its codes. Verified in simulation against the libretro GBA cheat database before it goes near hardware. |
| **P3** | Code-format decision from §3 implemented: raw forms in RTL, encrypted forms handled in the picker or explicitly unsupported and documented. | `docs/CHEATS.md` describes exactly what a user can paste in, with no asterisks. |
| **P4** | OSD readout (`CL:` equivalent) re-attached to `video_adapter.sv`, or dropped if RAM blocks say no. | Parsed count visible in the menu or on screen. |
| **P5** | Cartridge bring-up: import Wokann's controller and Rai's APF plumbing, cart detected, header read, `cartridge_adapter` enabled. | The core boots with a cart inserted and reads a correct header, on hardware. |
| **P6** | ROM from cart as the boot path, source mux, save routing to the cart. | A real cart boots and plays, saves land on the cart. |
| **P7** | Cheats on cart games, cart-mode `.cht` loading via parameter bit 9. | Both features work together in one session. |
| **P8** | README, `docs/CHEATS.md`, release packaging as `kroy.GBA_<version>.zip`, and upstreaming whatever belongs upstream. | Release published. |

P1 is deliberately before any file I/O, and P5 deliberately after the cheat work
is closed: cartridge bring-up is the phase most likely to stall on hardware
timing, and it should not block a feature that is a re-port of working code.

---

## 5. Risks

- **Fit, and this time it is real.** 90 % ALMs, 90 % RAM blocks, 0.102 ns worst
  setup slack on `clk_sys`. `gba_cheats` alone is 32 x 128 bits of cheat storage
  in registers (4,096 registers if Quartus does not infer MLABs) plus a 128-bit
  FIFO plus an FSM. If P1 does not close, the options are: force `cheatmem` into
  MLABs, cut `CHEATCOUNT` to 16, drop the OSD and its font ROM, or take the
  savestate route upstream already took and trade a feature out. Decide by
  measuring at P1, not by guessing now.
- **Do not casually bump Quartus.** Upstream tuned constraints, seeds and custom
  STA reports against 21.1. The GBC harness uses 25.1; keep them separate.
- **Upstream is moving.** v0.6.2 is two months old and mincer-ray is active.
  Rebase on upstream at phase boundaries, never mid-phase.
- **Cart writes touch someone's real save.** Wokann's own notes record Flash
  writes that reported success and did not persist. Every write path stays
  behind an explicit toggle until it is proven on a cart nobody minds losing.
- **The 28-bit address in the cheat word is a GBA bus address**, not a Softmap
  offset. `bus_out_Adr` in `core_top.sv:586` is a flat 26-bit DWORD offset into
  PSRAM. The translation lives inside `gba_memorymux`, which is exactly why
  `gba_cheats` must go through the debug bus and not be bolted onto
  `bus_out_*` in `core_top.sv`.
- **Savestates and cheats interact.** A state saved with cheats on must not
  restore into a core with different codes loaded. `cheat_clear` on ROM load and
  on state restore, same as MiSTer.

---

## 6. Open questions

1. Which code formats ship in P3, and does the picker take on decryption?
2. Is `CHEATCOUNT` 32 affordable here, or does the entry-pair encoding of
   conditional codes make 16 too small in practice?
3. Does the OSD survive the fit, and is a menu-only readout enough if it does
   not?
4. Cart mode and savestates: does a savestate taken in cart mode mean anything,
   or is it disabled there?
5. Do we contribute the cartridge work back to mincer-ray, or keep it here? Rai
   and Wokann are both working the same problem, and three private branches is
   the worst outcome for everyone.
