#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-side ROM patch table: fill, substitution on both words, masks, reset."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build' / 'sim'
BUILD.mkdir(parents=True, exist_ok=True)
out = BUILD / 'tb_rom_patch'
subprocess.run(['iverilog', '-g2012', '-o', str(out),
                str(ROOT / 'sim/han/tb_rom_patch.sv'),
                str(ROOT / 'src/fpga/han/rom_patch.sv')], check=True)
result = subprocess.run(['vvp', '-n', str(out)], capture_output=True, text=True, check=True)
print(result.stdout.strip())
if 'PASS' not in result.stdout:
    raise SystemExit(1)
