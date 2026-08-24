#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Cases that carry the right answer with them, rather than a model to agree with.

tools/sim/run.py compares the RTL against tools/cheats/gbacht.py over the whole
libretro GBA database, which proves the two agree and nothing more. A mistake
present in both is invisible to it, and in the GB core one was: the parser armed
on the bare characters `_code`, so a comment reading `# _code means "Facade"`
emitted a phantom patch, and both sides did it, and 2456 files still matched.

Two kinds of case here.

The counter table below says how many cheats and entries each fixture must
produce and why, which pins down the decisions the file format does not: what
happens to a condition with nothing to guard, to a chain of conditions, to a
cheat that does not fit in the table, to an encrypted blob.

mister_007.words is an oracle nothing here wrote. It is the same libretro codes
encoded by gamehacking.org, shipped as MiSTer-devel/Cheats_MiSTer and read back
out of those binaries: a different implementation, by different people, of the
same mapping. If our emitter and their encoder disagree about a byte lane or an
address, this is what says so.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD = os.path.join(ROOT, "build", "sim")
TB = os.path.join(BUILD, "tb_cheat_loader")
FIX = os.path.join(ROOT, "tools", "sim", "fixtures")

SOURCES = ["tools/sim/tb_cheat_loader.sv", "tools/sim/gba_cheats_model.sv",
           "src/fpga/core/cheat_loader.sv"]

WORD = re.compile(r"WORD ([0-9a-f]{32})")
TOTAL = re.compile(r"TOTAL bytes=(\d+) cheats=(\d+) entries=(\d+) "
                   r"rejected=(\d+) overrun=(\d+) stored=(\d+)")

# fixture -> (cheats pushed, entries pushed, cheats rejected for want of room)
CASES = {
    # four cheats, eight entries: every byte lane, both halfword lanes, a
    # misaligned byte in IWRAM and an IO register
    "basic.cht":      (4, 8, 0),
    # seven conditionals, each a pair, so fourteen entries for seven cheats
    "cond.cht":       (7, 14, 0),
    # raw GameShark: three writes and one conditional pair
    "gameshark.cht":  (4, 5, 0),
    # encrypted blobs, types gba_cheats cannot express, master and hook codes,
    # unwritable regions, addresses past the end of RAM, malformed tokens
    "reject.cht":     (0, 0, 0),
    # one cheat off, one on, one with no key at all (which means on) and
    # nothing after it in the file, so only end of file can resolve it
    "enable.cht":     (2, 2, 0),
    # a comment and a description that both look like codes
    "freetext.cht":   (1, 1, 0),
    # a chain of conditions cannot be expressed, so that cheat produces
    # nothing; a condition with nothing after it is dropped along with the
    # rest of its cheat, leaving the write that came before it
    "chain.cht":      (1, 1, 0),
    # spaces and a colon between the two words of a code
    "spaced.cht":     (2, 2, 0),
    # twenty entries fit, the next twenty do not and the cheat is dropped
    # whole rather than in part, and five more still fit after it
    "budget.cht":     (2, 25, 1),
    "mister_007.cht": (5, 8, 0),
}

ORACLE = {"mister_007.cht": "mister_007.words"}


def compile_tb() -> None:
    os.makedirs(BUILD, exist_ok=True)
    subprocess.run(["iverilog", "-g2012", "-o", TB]
                   + [os.path.join(ROOT, s) for s in SOURCES], check=True)


def run(path: str):
    out = subprocess.run([TB, f"+f={path}"], capture_output=True, text=True,
                         check=True).stdout
    m = TOTAL.search(out)
    return WORD.findall(out), tuple(int(g) for g in m.groups()), out


def main() -> int:
    compile_tb()
    bad = 0
    for name, (cheats, entries, rejected) in CASES.items():
        words, tot, out = run(os.path.join(FIX, name))
        errs = []
        if (tot[1], tot[2], tot[3]) != (cheats, entries, rejected):
            errs.append(f"cheats/entries/rejected = {tot[1]}/{tot[2]}/{tot[3]}, "
                        f"expected {cheats}/{entries}/{rejected}")
        if tot[4]:
            errs.append("push overrun")
        if tot[5] != entries:
            errs.append(f"gba_cheats stored {tot[5]}, expected {entries}")
        if len(words) != entries:
            errs.append(f"{len(words)} words latched, expected {entries}")
        if name in ORACLE:
            want = [l.split()[0] for l in
                    open(os.path.join(FIX, ORACLE[name]))
                    if l.strip() and not l.startswith("#")]
            if words != want:
                for i, (a, b) in enumerate(zip(words, want)):
                    if a != b:
                        errs.append(f"word {i}: ours {a}, MiSTer {b}")
                        break
                else:
                    errs.append(f"{len(words)} words, MiSTer has {len(want)}")
        bad += bool(errs)
        print(f"{'ok  ' if not errs else 'FAIL'} {name}")
        for e in errs:
            print(f"       {e}")
    n = len(CASES)
    print(f"\n{n - bad}/{n} cases behave as specified")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
