#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Render frames of the cheat overlay and check that it draws what it should.

tb_cheat_osd_smoke counts ink: where the overlay draws and where it must not.
tb_cheat_osd_titles reads the picture back cell by cell against the font, which
is what catches a title drawn one column off.
"""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build' / 'sim'
BUILD.mkdir(parents=True, exist_ok=True)
COMMON = ['src/fpga/core/cheat_osd.sv', 'src/fpga/core/cheat_font.sv',
          'src/fpga/core/cheat_titles.sv']
failed = False
for name in ('tb_cheat_osd_smoke', 'tb_cheat_osd_titles'):
    out = BUILD / name
    subprocess.run(['iverilog', '-g2012', '-o', str(out),
                    str(ROOT / f'sim/core/{name}.sv')]
                   + [str(ROOT / s) for s in COMMON], check=True)
    result = subprocess.run(['vvp', '-n', str(out)], capture_output=True, text=True)
    print(result.stdout.strip())
    if 'PASS' not in result.stdout:
        failed = True
if failed:
    raise SystemExit(1)
