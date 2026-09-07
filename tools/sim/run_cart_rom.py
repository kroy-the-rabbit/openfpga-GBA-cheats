#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Cartridge ROM read path: src/fpga/han/gba_cart_controller.sv.

Three passes.

1. sim/han/tb_gba_cart_controller.sv, Wokann's whole-controller bench,
   vendored verbatim. It covers SRAM, GPIO and EEPROM as well as ROM, so it
   is the regression that says the burst work did not disturb anything else.
   Its cart model has no internal address counter (ROM data is a pure
   function of the address latched on the CS# falling edge), so it cannot
   represent a burst: run it against ROM_BURST=0. Passing there is also the
   claim that the fallback path still behaves exactly as Wokann shipped it.

2. sim/han/tb_gba_cart_rom_burst.sv, the burst bench, against the controller
   as built. It runs a ROM_BURST=0 and a ROM_BURST=1 controller side by side
   against a cart model that does advance its counter on the RD# rising edge,
   and checks the data, the pin waveform and the cycle count.

3. sim/han/tb_rom_source_mux.sv checks the CPU cache's paired-DWORD
   contract through the mux and real controller, including odd addresses.

ROM_BURST is a module parameter with no port, and iverilog's -P only reaches
root modules, so pass 1 gets a copy of the controller with the parameter
default rewritten. The rewrite is asserted to have landed rather than
assumed; a silently unpatched copy would make pass 1 pass for the wrong
reason.

    tools/sim/run_cart_rom.py
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD = os.path.join(ROOT, "build", "sim")

CTRL = os.path.join(ROOT, "src", "fpga", "han", "gba_cart_controller.sv")
TB_WOKANN = os.path.join(ROOT, "sim", "han", "tb_gba_cart_controller.sv")
TB_BURST = os.path.join(ROOT, "sim", "han", "tb_gba_cart_rom_burst.sv")
TB_MUX = os.path.join(ROOT, "sim", "han", "tb_rom_source_mux.sv")
MUX = os.path.join(ROOT, "src", "fpga", "han", "rom_source_mux.sv")

BURST_PARAM = re.compile(r"^(\s*parameter integer ROM_BURST\s*=\s*)\d+(\s*,)$",
                         re.M)


def no_burst_copy() -> str:
    """The controller with ROM_BURST defaulted off, for Wokann's bench."""
    src = open(CTRL).read()
    out, n = BURST_PARAM.subn(r"\g<1>0\g<2>", src)
    if n != 1:
        raise SystemExit(
            f"run_cart_rom.py: expected exactly one ROM_BURST parameter "
            f"declaration in {CTRL}, found {n}. Update the pattern.")
    path = os.path.join(BUILD, "gba_cart_controller_noburst.sv")
    open(path, "w").write(out)
    return path


def run(name: str, exe: str, sources: list, top: str | None = None) -> bool:
    select = ["-s", top] if top else []
    subprocess.run(["iverilog", "-g2012", "-o", exe] + select + sources, check=True)
    result = subprocess.run([exe], capture_output=True, text=True)
    out = result.stdout + result.stderr
    ok = result.returncode == 0 and "PASS" in out and "FAIL" not in out
    print(f"{'ok  ' if ok else 'FAIL'} {name}")
    for line in out.strip().splitlines():
        if line.startswith(("FAIL", "CYCLES", "PASS")):
            print(f"       {line}")
    if not ok:
        print(out)
    return ok


def main() -> int:
    os.makedirs(BUILD, exist_ok=True)
    passes = 0
    passes += run("wokann whole-controller bench, ROM_BURST=0 "
                  "(ROM, SRAM, GPIO, EEPROM)",
                  os.path.join(BUILD, "tb_cart_wokann"),
                  [TB_WOKANN, no_burst_copy()])
    passes += run("ROM read burst vs per-word, waveform and cycle count",
                  os.path.join(BUILD, "tb_cart_rom_burst"),
                  [TB_BURST, CTRL])
    passes += run("ROM mux cache-line ordering and SDRAM forwarding",
                  os.path.join(BUILD, "tb_rom_source_mux"),
                  [TB_MUX, TB_BURST, CTRL, MUX], top="tb_rom_source_mux")
    print(f"\n{passes}/3 benches pass")
    return 0 if passes == 3 else 1


if __name__ == "__main__":
    sys.exit(main())
