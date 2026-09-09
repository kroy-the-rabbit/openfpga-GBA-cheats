#!/usr/bin/env python3
"""Exercise the actual VHDL save routing with GHDL (no FPGA primitives)."""
from pathlib import Path
import subprocess
import shutil

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/sim/cart_memorymux"
SRC = ROOT / "src/fpga/gba"


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "sim/fixtures/bmxe-header.hex", BUILD / "bmxe-header.hex")
    def run(*args):
        subprocess.run(["ghdl", *args], cwd=BUILD, check=True)
    run("-a", "--std=08", "--work=mem", str(SRC / "SyncRamDual.vhd"))
    for name in ("proc_bus_gba.vhd", "reg_savestates.vhd", "reggba_dma.vhd", "gba_dma_module.vhd", "gba_dma.vhd", "gba_bios.vhd", "cache.vhd", "gba_memorymux.vhd"):
        run("-a", "--std=08", str(SRC / name))
    run("-a", "--std=08", str(ROOT / "sim/han/tb_gba_cart_memorymux.vhd"))
    run("-e", "--std=08", "tb_gba_cart_memorymux")
    result = subprocess.run(
        ["ghdl", "-r", "--std=08", "tb_gba_cart_memorymux", "--assert-level=error",
         "--ieee-asserts=disable-at-0", "--stop-time=300us"],
        cwd=BUILD, check=True, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if "PASS cartridge memorymux" not in output or "PASS BMXE ROM header" not in output:
        raise RuntimeError("Memorymux bench did not reach PASS:\n" + output)
    for line in output.splitlines():
        if "PASS" in line:
            print(line)

if __name__ == "__main__":
    main()
