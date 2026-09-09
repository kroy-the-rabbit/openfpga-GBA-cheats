#!/usr/bin/env python3
"""Check coherent cartridge diagnostics across asynchronous host/system clocks."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/sim"


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    for name, marker in (("cart_debug_snapshot", "PASS coherent asynchronous debug snapshots"),
                         ("cart_header_check", "PASS header diagnostic")):
        executable = BUILD / ("tb_" + name)
        subprocess.run([
            "iverilog", "-g2012", "-s", "tb_" + name, "-o", str(executable),
            str(ROOT / "sim/han" / ("tb_" + name + ".sv")),
            str(ROOT / "src/fpga/han" / (name + ".sv")),
        ], check=True)
        result = subprocess.run(["vvp", str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
        output = result.stdout + result.stderr
        if marker not in output:
            raise RuntimeError("Diagnostic bench did not reach PASS:\n" + output)
        print(output.strip())


if __name__ == "__main__":
    main()
