#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The names a .cht carries are the names the overlay's title RAM holds.

Runs each fixture through the real parser into the real title RAM, reads the
RAM back, and compares against the cheatN_desc strings of the cheats the
parser pushed: uppercased, cut at 26, characters outside the font as space.
"""
from __future__ import annotations
import os, re, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "cheats"))
import gbacht  # noqa: E402
BUILD = os.path.join(ROOT, "build", "sim"); TB = os.path.join(BUILD, "tb_cheat_titles")
FIX = os.path.join(ROOT, "tools", "sim", "fixtures")
SOURCES = ["tools/sim/tb_cheat_titles.sv", "src/fpga/core/cheat_loader.sv",
           "src/fpga/core/cheat_titles.sv"]
CASES = ["basic.cht", "enable.cht", "freetext.cht", "rompatch.cht"]

def expect(path: str) -> list[str]:
    groups, _ = gbacht.parse(open(path, "rb").read())
    out = []
    for g in groups:
        t = "".join(ch if 32 <= ord(ch) <= 95 else " " for ch in (g.desc or "").upper())[:26]
        out.append(t)
    return out

def main() -> int:
    os.makedirs(BUILD, exist_ok=True)
    subprocess.run(["iverilog", "-g2012", "-o", TB] + [os.path.join(ROOT, s) for s in SOURCES], check=True)
    bad = 0
    for name in CASES:
        out = subprocess.run([TB, f"+f={os.path.join(FIX, name)}"], capture_output=True, text=True, check=True).stdout
        got = []
        for m in re.finditer(r"TITLE (\d+) (\d+)((?: \d+)*)", out):
            got.append("".join(chr(int(x) + 32) for x in m.group(3).split()))
        want = expect(os.path.join(FIX, name))
        ok = got == want
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name}: {len(got)} titles")
        if not ok:
            for i, (a, b) in enumerate(zip(got + [None]*len(want), want + [None]*len(got))):
                if a != b: print(f"       title {i}: ram {a!r}, file {b!r}")
    print(f"\n{len(CASES) - bad}/{len(CASES)} title sets match")
    return 1 if bad else 0

if __name__ == "__main__":
    raise SystemExit(main())
