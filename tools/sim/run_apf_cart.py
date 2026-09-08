#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run APF cartridge launch notification and savestate command regressions."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/sim'


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    exe = BUILD / 'tb_core_bridge_cart_notify'
    sources = [ROOT / 'sim/han/tb_core_bridge_cart_notify.sv',
               ROOT / 'src/fpga/core/core_bridge_cmd.v']
    subprocess.run(['iverilog', '-g2012', '-s', 'tb_core_bridge_cart_notify',
                    '-o', str(exe), *map(str, sources)], check=True)
    result = subprocess.run(['vvp', str(exe)], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS APF cartridge notification' not in output or 'FAIL' in output:
        raise RuntimeError('APF cartridge notification regression failed:\n' + output)
    print(output.strip())
    # Compile the real top and handler; omit unrelated VHDL/vendor engines.
    # The bench supplies only clocks and external reset/probe/memory status.
    exe = BUILD / 'tb_core_top_cart_launch'
    subprocess.run(['iverilog', '-g2012', '-i', '-s', 'tb_core_top_cart_launch',
                    '-o', str(exe),
                    str(ROOT / 'sim/han/tb_core_top_cart_launch.sv'),
                    str(ROOT / 'src/fpga/han/cart_debug_snapshot.sv'),
                    *map(str, sources), str(ROOT / 'src/fpga/core/core_top.sv')], check=True)
    result = subprocess.run(['vvp', str(exe)], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS core_top cartridge launch' not in output or 'FAIL' in output:
        raise RuntimeError('Top-level cartridge launch regression failed:\n' + output)
    if 'PASS core_top debug packing' not in output:
        raise RuntimeError('Top-level debug snapshot regression did not finish:\n' + output)
    print(output.strip())


if __name__ == '__main__':
    main()
