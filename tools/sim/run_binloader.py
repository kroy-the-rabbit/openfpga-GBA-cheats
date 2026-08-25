#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Cases for src/fpga/core/cheat_binloader.sv, each carrying its own answer.

The loader does no transformation, so the interesting behaviour is entirely at
the edges of the file: framing, the header interlock, and what happens when the
file disagrees with itself. Those are the cases below, and each one says what
the loader must emit and what its readout must say.

The fixtures are generated rather than committed. A .chtbin is 16-byte binary
records and a hexdump of one in the tree would be unreadable and unreviewable,
whereas build_cases below says what each file means and why. They are written
to build/sim/fixtures-bin/ so a failing case can be re-run by hand.

The expected 128-bit word is not derived from the file bytes: entry_bytes packs
little-endian integers into a bytearray and word_hex shifts the same fields into
a Python integer at their bit positions. A byte-order or lane mistake in the
RTL, or in one of these two, shows up as a mismatch rather than cancelling out.

    tools/sim/run_binloader.py
"""
from __future__ import annotations

import os
import re
import struct
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD = os.path.join(ROOT, "build", "sim")
TB = os.path.join(BUILD, "tb_cheat_binloader")
FIX = os.path.join(BUILD, "fixtures-bin")

SOURCES = ["tools/sim/tb_cheat_binloader.sv", "tools/sim/gba_cheats_model.sv",
           "src/fpga/core/cheat_binloader.sv"]

# The same end to end harness run_e2e.py uses, built against this loader
# instead. See the BINLOADER define in tb_e2e.sv.
E2E_TB = os.path.join(BUILD, "tb_e2e_bin")
E2E_SOURCES = ["tools/sim/tb_e2e.sv", "tools/sim/dcfifo.sv",
               "tools/sim/gba_cheats_model.sv",
               "src/fpga/pocket/data_loader.sv",
               "src/fpga/core/cheat_binloader.sv"]

WORD = re.compile(r"WORD ([0-9a-f]{32})")
TOTAL = re.compile(r"TOTAL bytes=(\d+) declared=(\d+) entries=(\d+) "
                   r"rejected=(\d+) malformed=(\d+) stored=(\d+)")


def header(count: int, magic: bytes = b"GBAC", version: int = 1) -> bytes:
    """A .chtbin header. See docs/CHEATBIN.md."""
    return magic + bytes([version, 0]) + struct.pack("<H", count) + bytes(8)


def entry_bytes(value: int, addr: int, optype: int, mask: int,
                junk: bool = False) -> bytes:
    """One 16-byte entry as it sits in the file.

    junk fills every reserved field with 0xFF. The format says they are zero
    and gba_cheats does not read them, so a conforming file never does this;
    the fixture exists to pin down what happens when one does.
    """
    fill = 0xFF if junk else 0x00
    b = bytearray([fill] * 16)
    b[0:4] = struct.pack("<I", value)
    b[8:12] = struct.pack("<I", (0xF0000000 if junk else 0) | (addr & 0x0FFFFFFF))
    b[12] = ((mask & 0xF) << 4) | (optype & 0xF)
    return bytes(b)


def word_hex(value: int, addr: int, optype: int, mask: int) -> str:
    """The same entry as the 128-bit word gba_cheats must end up holding."""
    w = (((mask & 0xF) << 100) | ((optype & 0xF) << 96)
         | ((addr & 0x0FFFFFFF) << 64) | (value & 0xFFFFFFFF))
    return "%032x" % w


# A cheat table that touches every byte lane, both halfword lanes, all three
# writable regions, and ends with a conditional: a compare entry immediately
# followed by the entry it guards. That adjacency is the whole mechanism for a
# condition in gba_cheats, so it is also the thing an ordering bug would break.
TABLE = [
    (0x000000AB, 0x02000000, 0x0, 0x1),   # byte write, lane 0, EWRAM
    (0x0000CD00, 0x02000104, 0x0, 0x2),   # byte write, lane 1
    (0x12345678, 0x03001234, 0x0, 0xF),   # word write, IWRAM
    (0x0000BEEF, 0x04000208, 0x0, 0x3),   # halfword write, IO
    (0x00001234, 0x02005678, 0x1, 0x3),   # compare: halfword == 0x1234
    (0xDEAD0000, 0x02005678, 0x0, 0xC),   # what it guards
]


def stream(entries, count=None, **hdr) -> bytes:
    n = len(entries) if count is None else count
    return header(n, **hdr) + b"".join(entry_bytes(*e) for e in entries)


def words(entries) -> list:
    return [word_hex(*e) for e in entries]


# name -> (file bytes, expected words, (declared, entries, rejected, malformed))
def build_cases() -> dict:
    cases = {}

    # The ordinary case. Six entries, in file order, all of them pushed.
    cases["good"] = (stream(TABLE), words(TABLE), (6, 6, 0, 0))

    # A raw .cht dropped in by mistake, which is the reason the magic exists at
    # all: the previous format was exactly this file. Three blocks of ASCII go
    # past after the header is rejected and not one of them may be pushed.
    cht = (b"cheats = 2\ncheat0_desc = \"Infinite HP\"\n"
           b"cheat0_code = \"02000000+000000AB\"\ncheat0_enable = true\n")
    cases["wrongmagic"] = (cht, [], (0, 0, 0, 1))

    # Right magic, a version this loader does not know. Same answer: nothing.
    cases["wrongversion"] = (stream(TABLE, version=2), [], (0, 0, 0, 1))

    # The header is fine but the file ends nine bytes into its third entry. The
    # two whole ones load, the partial one is discarded rather than padded, and
    # declared (3) against entries (2) is what says so on the handheld.
    cases["truncated"] = (stream(TABLE[:2], count=3)
                          + entry_bytes(*TABLE[2])[:9],
                          words(TABLE[:2]), (3, 2, 0, 1))

    # A header with no entries after it is a valid file meaning no cheats. The
    # malformed flag is what separates it from wrongmagic in the readout.
    cases["zero"] = (header(0), [], (0, 0, 0, 0))

    # An empty file is the same thing with even less of it.
    cases["empty"] = (b"", [], (0, 0, 0, 0))

    # Half a header. Nothing was ever validated, so nothing loads.
    cases["shortheader"] = (header(1)[:8], [], (0, 0, 0, 1))

    # Exactly the table's capacity, so the entry after the last one is the
    # first that would not fit. Nothing may be rejected here.
    full = [(0x1000 + i, 0x02000000 + 4 * i, 0x0, 0xF) for i in range(32)]
    cases["exact32"] = (stream(full), words(full), (32, 32, 0, 0))

    # Eight more than fit. The first 32 load in file order, the excess is
    # counted and dropped: wrapping would overwrite entries already loaded.
    over = [(0x2000 + i, 0x02001000 + 4 * i, 0x0, 0xF) for i in range(40)]
    cases["over32"] = (stream(over), words(over[:32]), (40, 32, 8, 0))

    # A count that does not fit the six-bit readout at all. The declared count
    # saturates at 63, so 63 entries are consumed, 32 load, 31 are rejected and
    # the seven blocks past that are ignored entirely.
    huge = [(0x3000 + i, 0x02002000 + 4 * i, 0x0, 0xF) for i in range(70)]
    cases["huge"] = (stream(huge, count=1000), words(huge[:32]), (63, 32, 31, 0))

    # More blocks in the file than the header declared. Only the declared one
    # loads: an entry has no framing of its own, so trailing bytes are
    # indistinguishable from a real entry and the count is the only guard.
    cases["extra"] = (stream(TABLE, count=1), words(TABLE[:1]), (1, 1, 0, 0))

    # Reserved fields full of 0xFF. gba_cheats does not read those bits and the
    # format says they are zero, so they must not reach the word.
    dirty = [(0x000000AB, 0x02000000, 0x0, 0x1)]
    cases["reserved"] = (header(1) + entry_bytes(*dirty[0], junk=True),
                         words(dirty), (1, 1, 0, 0))

    return cases


# The entries the end to end case loads, the memory they act on before they do,
# and the memory they must leave behind. Two of them are compares: the first
# passes and its guarded entry runs, the second fails and suppresses the entry
# after it, which is the only way to tell that entry adjacency survived the
# trip through data_loader's FIFO.
E2E_TABLE = [
    (0x000000AB, 0x02000000, 0x0, 0x1),   # byte write
    (0x0000CD00, 0x02000004, 0x0, 0x2),   # byte write into lane 1
    (0x12345678, 0x03001000, 0x0, 0xF),   # word write, IWRAM
    (0x00001234, 0x02000100, 0x1, 0x3),   # halfword == 0x1234, and it is
    (0x000000EE, 0x02000104, 0x0, 0x1),   # so this one runs
    (0x00005555, 0x02000200, 0x1, 0x3),   # halfword == 0x5555, and it is not
    (0x000000FF, 0x02000204, 0x0, 0x1),   # so this one must not
]

E2E_SEED = """02000100 34
02000101 12
"""

E2E_EXPECT = """02000000 ab
02000001 00
02000002 00
02000003 00
02000004 00
02000005 cd
03001000 78
03001001 56
03001002 34
03001003 12
02000100 34
02000101 12
02000104 ee
02000200 00
02000201 00
02000204 00
"""


def compile_tb() -> None:
    os.makedirs(BUILD, exist_ok=True)
    subprocess.run(["iverilog", "-g2012", "-o", TB]
                   + [os.path.join(ROOT, s) for s in SOURCES], check=True)
    subprocess.run(["iverilog", "-g2012", "-DBINLOADER", "-o", E2E_TB]
                   + [os.path.join(ROOT, s) for s in E2E_SOURCES], check=True)


def run_e2e() -> bool:
    """The whole path: APF bridge writes, data_loader's FIFO, the apply pass."""
    stem = os.path.join(FIX, "e2e")
    open(stem + ".chtbin", "wb").write(stream(E2E_TABLE))
    open(stem + ".seed", "w").write(E2E_SEED)
    open(stem + ".expect", "w").write(E2E_EXPECT)
    out = subprocess.run([E2E_TB, f"+f={stem}.chtbin", f"+seed={stem}.seed",
                          f"+e={stem}.expect"],
                         capture_output=True, text=True).stdout
    ok = "PASS" in out and "OVERFLOW" not in out
    print(f"{'ok  ' if ok else 'FAIL'} e2e (bridge -> data_loader -> gba_cheats)")
    for line in out.strip().splitlines():
        if line.startswith(("RESULT", "FAIL", "DCFIFO", "CHECKED", "FAILURES")):
            print(f"       {line}")
    return ok


def run(path: str, gap: int):
    args = [TB, f"+f={path}"]
    if gap != 4:
        args.append(f"+gap={gap}")
    out = subprocess.run(args, capture_output=True, text=True,
                         check=True).stdout
    m = TOTAL.search(out)
    if not m:
        raise SystemExit(f"no TOTAL line from {path}:\n{out}")
    return WORD.findall(out), tuple(int(g) for g in m.groups()), out


def check(name, path, want_words, want_counts, gap):
    got_words, tot, out = run(path, gap)
    errs = []
    if tot[1:5] != want_counts:
        errs.append(f"declared/entries/rejected/malformed = "
                    f"{'/'.join(str(v) for v in tot[1:5])}, "
                    f"expected {'/'.join(str(v) for v in want_counts)}")
    if tot[0] != os.path.getsize(path):
        errs.append(f"counted {tot[0]} bytes, file is {os.path.getsize(path)}")
    if tot[5] != len(want_words):
        errs.append(f"gba_cheats stored {tot[5]}, expected {len(want_words)}")
    if got_words != want_words:
        for i, (a, b) in enumerate(zip(got_words, want_words)):
            if a != b:
                errs.append(f"word {i}: got {a}, expected {b}")
                break
        else:
            errs.append(f"{len(got_words)} words emitted, "
                        f"expected {len(want_words)}")
    if "FAIL" in out:
        errs.append(next(l for l in out.splitlines() if "FAIL" in l))
    tag = name if gap == 4 else f"{name} (gap={gap})"
    print(f"{'ok  ' if not errs else 'FAIL'} {tag}")
    for e in errs:
        print(f"       {e}")
    return not errs


def main() -> int:
    compile_tb()
    os.makedirs(FIX, exist_ok=True)
    cases = build_cases()

    runs = []
    for name, (blob, want_words, want_counts) in cases.items():
        path = os.path.join(FIX, name + ".chtbin")
        with open(path, "wb") as f:
            f.write(blob)
        runs.append((name, path, want_words, want_counts, 4))

    # data_loader cannot deliver bytes faster than one every four cycles, but
    # cheat_in is a wire off the shift register rather than a registered copy,
    # so the claim that it is stable across the rising edge of cheat_on is
    # worth checking with no slack in it at all. gap 0 is a byte every cycle,
    # which is the only rate at which the next entry's first byte can reach the
    # register while the pulse for this one is still up.
    for gap in (0, 1, 2):
        for name in ("good", "over32"):
            blob, want_words, want_counts = cases[name]
            runs.append((name, os.path.join(FIX, name + ".chtbin"),
                         want_words, want_counts, gap))

    ok = sum(check(*r) for r in runs)
    total = len(runs) + 1
    ok += run_e2e()
    print(f"\n{ok}/{total} cases behave as specified")
    return 0 if ok == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
