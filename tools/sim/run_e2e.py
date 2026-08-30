#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Drive a .cht through the whole core path in simulation and check memory.

Sends the file as APF bridge writes at hardware rates, through data_loader's
dual clock FIFO and cheat_loader, into a behavioural gba_cheats, then runs its
vblank apply pass over a model of EWRAM, IWRAM and IO and asserts every byte
the fixture says should have changed, and that nothing else did.

    tools/sim/run_e2e.py                    # the fixtures with a .expect file
    tools/sim/run_e2e.py path/to/game.cht   # just report what a file does

A fixture is `<name>.cht`, optionally `<name>.seed` (memory before the pass,
so a conditional code can be tested against a value that makes its test go both
ways) and `<name>.expect` (memory after). Both are lines of "<hex addr> <hex
byte>". The expectations are written by hand, not generated from the model, so
the two agreeing cannot hide a mistake in both.
"""
from __future__ import annotations

import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD = os.path.join(ROOT, "build", "sim")
TB = os.path.join(BUILD, "tb_e2e")
FIX = os.path.join(ROOT, "tools", "sim", "fixtures")

SOURCES = ["tools/sim/tb_e2e.sv", "tools/sim/dcfifo.sv",
           "tools/sim/gba_cheats_model.sv", "src/fpga/pocket/data_loader.sv",
           "src/fpga/core/cheat_loader.sv"]


def compile_tb() -> None:
    os.makedirs(BUILD, exist_ok=True)
    subprocess.run(["iverilog", "-g2012", "-o", TB]
                   + [os.path.join(ROOT, s) for s in SOURCES], check=True)


def run(path: str) -> bool:
    stem = path[:-4]
    args = [TB, f"+f={path}"]
    if os.path.exists(stem + ".seed"):
        args.append(f"+seed={stem}.seed")
    if os.path.exists(stem + ".expect"):
        args.append(f"+e={stem}.expect")
    out = subprocess.run(args, capture_output=True, text=True).stdout
    ok = "PASS" in out and "OVERFLOW" not in out
    print(f"--- {os.path.basename(path)}")
    for line in out.strip().splitlines():
        if line.startswith(("RESULT", "FAIL", "DCFIFO", "CHECKED", "FAILURES")):
            print(f"    {line}")
    print(f"    {'PASS' if ok else 'FAIL'}")
    return ok


def main() -> int:
    files = sys.argv[1:] or sorted(
        f for f in glob.glob(os.path.join(FIX, "*.cht"))
        if os.path.exists(f[:-4] + ".expect"))
    if not files:
        print("no .cht files given")
        return 2
    compile_tb()
    bad = [p for p in files if not run(p)]
    print()
    print(f"{len(files) - len(bad)}/{len(files)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
