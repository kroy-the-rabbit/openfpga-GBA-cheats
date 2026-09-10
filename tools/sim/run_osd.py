#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Render one frame of the cheat overlay and check that it draws where it should."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build' / 'sim'
BUILD.mkdir(parents=True, exist_ok=True)
out = BUILD / 'tb_cheat_osd_smoke'
subprocess.run(['iverilog', '-g2012', '-o', str(out),
                str(ROOT / 'sim/core/tb_cheat_osd_smoke.sv'),
                str(ROOT / 'src/fpga/core/cheat_osd.sv'),
                str(ROOT / 'src/fpga/core/cheat_font.sv'),
                str(ROOT / 'src/fpga/core/cheat_titles.sv')], check=True)
result = subprocess.run(['vvp', '-n', str(out)], capture_output=True, text=True, check=True)
print(result.stdout.strip())
if 'PASS' not in result.stdout:
    raise SystemExit(1)
