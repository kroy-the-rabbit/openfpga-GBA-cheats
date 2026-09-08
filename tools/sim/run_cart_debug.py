#!/usr/bin/env python3
"""Check coherent cartridge diagnostics across asynchronous host/system clocks."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/sim"


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    executable = BUILD / "tb_cart_debug_snapshot"
    subprocess.run([
        "iverilog", "-g2012", "-s", "tb_cart_debug_snapshot", "-o", str(executable),
        str(ROOT / "sim/han/tb_cart_debug_snapshot.sv"),
        str(ROOT / "src/fpga/han/cart_debug_snapshot.sv"),
    ], check=True)
    result = subprocess.run(["vvp", str(executable)], check=True, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if "PASS coherent asynchronous debug snapshots" not in output:
        raise RuntimeError("Snapshot bench did not reach PASS:\n" + output)
    print(output.strip())


if __name__ == "__main__":
    main()
