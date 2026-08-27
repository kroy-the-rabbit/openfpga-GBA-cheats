#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/cheats/cht2bin.py.

    .venv/bin/python -m pytest tools/cheats/test_cht2bin.py -rs
    .venv/bin/python tools/cheats/test_cht2bin.py            # no pytest needed
    .venv/bin/python tools/cheats/test_cht2bin.py --corpus   # add the 513 files

Two kinds of case here, and the split matters.

Most of the file compares the converter against `gbacht.words()`, which proves
the packing is reversible and nothing reordered. That alone would not catch a
field at the wrong offset, because the same wrong offset would be used to read
it back. So the entry tests below carry **literal expected bytes**, derived by
hand from the bit table in docs/CHEATBIN.md and written out in the comments. A
field offset is the most likely mistake in this file and the quietest: a
misplaced address still loads, still runs, and pokes the wrong memory.

The corpus pass is the breadth. It converts every real libretro `.cht` and
checks the words survive the round trip, twice per file: as shipped, and with
every cheat switched on. Stock libretro files set every cheat to
`enable = false`, so a pass over them as shipped proves only the enable path.
"""
from __future__ import annotations

import contextlib
import io
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cht2bin                                                      # noqa: E402
import gbacht                                                       # noqa: E402

try:
    import pytest
except ImportError:                 # running as a plain script
    pytest = None

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FIXTURES = os.path.join(ROOT, "tools", "sim", "fixtures")
# The same corpus tools/sim/run.py uses: $CHT_DB, else external/cht, which is
# git-ignored and fetched by the user. See docs/CHEATS.md.
CHT_DB = os.environ.get("CHT_DB") or os.path.join(ROOT, "external", "cht")
ENABLE = re.compile(rb"(_enable\s*=\s*)false", re.I)

HEADER = b"GBAC" + bytes((1, 0)) + b"\x00\x00" + bytes(8)


class Skipped(Exception):
    """Raised in plain-script mode where pytest would skip."""


# pytest.skip() raises its own exception, and pytest may well be installed even
# when the tests are run as a script, so the runner has to know both.
SKIPS = (Skipped,) + ((pytest.skip.Exception,) if pytest is not None else ())


def skip(reason: str):
    """Skip, but never silently: an absent corpus must be visible in the log."""
    print(f"SKIP: {reason}", file=sys.stderr, flush=True)
    if pytest is not None:
        pytest.skip(reason)
    raise Skipped(reason)


def cht(*codes: str) -> bytes:
    """A minimal .cht file, one cheat per code string, all enabled."""
    out = [f"cheats = {len(codes)}\n"]
    for i, code in enumerate(codes):
        out.append(f'\ncheat{i}_desc = "cheat {i}"\n'
                   f'cheat{i}_code = "{code}"\n'
                   f'cheat{i}_enable = true\n')
    return "".join(out).encode()


def run_cli(*argv: str) -> tuple[int, str]:
    """main() with its report captured, so the tests stay readable."""
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        try:
            rc = cht2bin.main(list(argv))
        except SystemExit as e:                 # argparse errors
            rc = e.code if isinstance(e.code, int) else 1
    return rc, err.getvalue()


# ------------------------------------------------------------------ header --
def test_header_is_the_documented_bytes():
    blob = cht2bin.pack([])
    assert blob == HEADER
    assert len(blob) == 16
    assert blob[0:4] == b"GBAC" == bytes((0x47, 0x42, 0x41, 0x43))
    assert blob[4] == 1                         # version
    assert blob[5] == 0                         # reserved
    assert blob[6:8] == b"\x00\x00"             # entry_count
    assert blob[8:16] == bytes(8)               # reserved


def test_entry_count_is_a_little_endian_uint16_at_offset_6():
    blob = cht2bin.pack([0] * 3)
    assert blob[6:8] == b"\x03\x00"
    assert len(blob) == 16 + 3 * 16
    # 0x0102 would look identical to 0x0201 if the field were byte swapped,
    # so use a count whose two bytes differ. pack() will not take one that
    # large, hence header() directly.
    assert cht2bin.header(0x0102)[6:8] == b"\x02\x01"


def test_wrong_magic_or_version_reads_as_no_cheats():
    good = cht2bin.pack([0x12345678])
    assert cht2bin.unpack(good) == [0x12345678]
    assert cht2bin.unpack(b"cheats = 1\ncheat0_code = ...") == []
    assert cht2bin.unpack(b"GBAX" + good[4:]) == []
    assert cht2bin.unpack(good[:4] + b"\x02" + good[5:]) == []
    assert cht2bin.unpack(b"") == []


def test_truncated_final_entry_is_discarded():
    blob = cht2bin.pack([0xAA, 0xBB])
    assert cht2bin.unpack(blob[:-1]) == [0xAA]


# ------------------------------------------------------- hand-computed bytes --
def test_codebreaker_byte_write_packs_to_the_documented_bytes():
    """`32000001 0022`: CodeBreaker type 3, write 0x22 to 0x02000001.

    gba_cheats only does 32-bit accesses, so the address aligns down to
    0x02000000 and the value moves into byte lane 1: value 0x00002200, byte
    enables 0b0010. The 128-bit word is then, from the table in CHEATBIN.md,

        [31:0]    value     0x00002200
        [63:32]   zero
        [91:64]   address   0x2000000
        [95:92]   zero
        [99:96]   optype    0 (always: this entry is itself a write)
        [103:100] enables   0x2
        [127:104] zero

        00000020 02000000 00000000 00002200

    which little-endian is byte 0 first, so the low half of the value leads
    and the byte-enable nibble ends up in the high nibble of the last byte.
    """
    want = bytes((0x00, 0x22, 0x00, 0x00,       # [31:0]   value
                  0x00, 0x00, 0x00, 0x00,       # [63:32]  zero
                  0x00, 0x00, 0x00, 0x02,       # [95:64]  address
                  0x20, 0x00, 0x00, 0x00))      # [127:96] enables, optype
    res = cht2bin.convert(cht("32000001+0022"))
    assert res.blob == HEADER[:6] + b"\x01\x00" + HEADER[8:] + want
    assert res.entries == 1 and res.cheats == 1 and res.dropped == 0


def test_conditional_is_two_adjacent_entries_in_order():
    """`72000200 00AA + 32000204 0001`: if the halfword at 0x2000200 is 0xAA,
    write 0x01 to 0x2000204.

    Entry 0 is the compare: optype 1 (`==`), operand in the same byte lane a
    16-bit write would use (enables 0b0011), address 0x2000200.
    Entry 1 is the guarded write: optype 0, enables 0b0001, address 0x2000204.

        00000031 02000200 00000000 000000AA
        00000010 02000204 00000000 00000001

    The order is the whole mechanism: gba_cheats' skip_next suppresses the
    entry *after* a failed compare. Reversed, this would write unconditionally
    and then compare against nothing.
    """
    compare = bytes((0xAA, 0x00, 0x00, 0x00,
                     0x00, 0x00, 0x00, 0x00,
                     0x00, 0x02, 0x00, 0x02,
                     0x31, 0x00, 0x00, 0x00))
    write = bytes((0x01, 0x00, 0x00, 0x00,
                   0x00, 0x00, 0x00, 0x00,
                   0x04, 0x02, 0x00, 0x02,
                   0x10, 0x00, 0x00, 0x00))
    res = cht2bin.convert(cht("72000200+00AA+32000204+0001"))
    assert res.entries == 2
    assert res.blob[16:32] == compare
    assert res.blob[32:48] == write


def test_gameshark_greater_or_equal_emits_optype_3():
    """The inverted optype names in gba_cheats.vhd, pinned to a byte.

    `D2000200 003000AA` is a GameShark conditional whose selector is 3, which
    mGBA calls "greater or equal". OPTYPE_LESS in the VHDL is the constant
    that produces that behaviour, so the number in the file must be 3 and not
    the 4 the constant names suggest. Getting this wrong swaps two live
    comparisons and the file still loads.

    It needs a write after it: a compare with nothing to guard is dropped.
    """
    res = cht2bin.convert(cht("D2000200+003000AA+32000204+0001"))
    assert res.entries == 2
    assert res.blob[28] == 0x33                 # enables 0x3, optype 0x3
    assert cht2bin.unpack(res.blob)[0] >> 96 & 0xF == gbacht.OPT_GE


def test_gameshark_sp_code_matches_its_codebreaker_twin():
    """The SP/Action-Replay-v3 reading, pinned against codes that already work.

    A gamehacking.org export writes `0WAAAAAA VVVVVVVV`: the width is the
    second nibble, and the address is a 24-bit EWRAM offset rather than a bus
    address. Nothing in the file declares that, so the only honest way to pin
    it is a game whose list carries the same cheats in both dialects. The
    Minish Cap list does, and the two must produce the same word.
    """
    same = (("00202AEA+000000A0", "32002AEA+00A0"),      # Infinite Health
            ("02202B00+000003E7", "82002B00+03E7"),      # 999 Rupees
            ("02202B30+00005555", "82002B30+5555"))      # All Items
    for sp, cb in same:
        got = cht2bin.unpack(cht2bin.convert(cht(sp)).blob)
        want = cht2bin.unpack(cht2bin.convert(cht(cb)).blob)
        assert got == want, f"{sp} != {cb}: {got} vs {want}"


def test_gameshark_sp_width_is_the_second_nibble():
    """0 is a byte, 2 a halfword, 4 a word, and the address is an offset.

    `042C2B58` is a word write to EWRAM + 0x2B58: the offset is masked to the
    256 KB the hardware mirrors, so the 0x2C0000 in the token falls away.
    """
    for code, mask, addr in (("00202AEA+000000A0", 0x4, 0x2002AE8),
                             ("02202B00+000003E7", 0x3, 0x2002B00),
                             ("042C2B58+75707172", 0xF, 0x2002B58)):
        word = cht2bin.unpack(cht2bin.convert(cht(code)).blob)[0]
        assert word >> 100 & 0xF == mask, code
        assert word >> 64 & 0x0FFFFFFF == addr, code


def test_gameshark_sp_never_overrides_a_working_reading():
    """A code both dialects can read stays v1/v2, or this would change cheats.

    `02002AEA 00000050` is a valid v1/v2 8-bit assign *and* a valid SP
    halfword assign, and they disagree: the halfword one also zeroes the byte
    above, which on this game is Max HP. The SP reading is only ever reached
    for a code v1/v2 has already thrown out.
    """
    e, why = gbacht.decode_pair("02002AEA", "00000050")
    assert e is not None and why == "ok"
    assert e.kind == "gs" and e.bytemask == 0x4


def test_encrypted_words_are_still_refused():
    """The filter this dialect is threaded through must still hold.

    `0b070768` and `0f0e1320` are the addresses the module docstring cites
    from Cheats_MiSTer: encrypted codes run through a raw decoder. Their width
    nibbles are not 0, 2 or 4, so the SP reading declines them too.
    """
    for op1, op2 in (("0B070768", "00000000"), ("0F0E1320", "12345678"),
                     ("9E6EE1B0", "D14F1E6F"), ("A4699E04", "BB9B2A8F")):
        e, why = gbacht.decode_pair(op1, op2)
        assert e is None, f"{op1} {op2} decoded to {e} ({why})"


def test_reserved_bits_are_refused_rather_than_masked():
    for bad in (1 << 32, 1 << 63, 1 << 104, 1 << 127):
        try:
            cht2bin.pack([bad])
        except ValueError:
            continue
        raise AssertionError(f"reserved bit {bad:032x} was accepted")


# ------------------------------------------------------------------- limits --
def test_more_than_32_entries_cannot_be_packed():
    try:
        cht2bin.pack([0] * 33)
    except ValueError:
        pass
    else:
        raise AssertionError("pack() accepted 33 entries")


def test_cap_drops_whole_cheats_and_reports_them():
    """gbacht already stops at 32, so the cap is driven through parse_limit.

    Twenty conditional cheats are forty entries. Cutting at exactly 32 would
    split the sixteenth pair and leave a compare entry last, where its
    skip_next lands on an unrelated cheat. Four whole cheats go instead.
    """
    codes = [f"7200{0x200 + i * 8:04X}+00AA+3200{0x204 + i * 8:04X}+0001"
             for i in range(20)]
    res = cht2bin.convert(cht(*codes), parse_limit=1000)
    assert res.entries == 32 and res.dropped == 8 and res.cheats == 16
    assert len(res.blob) == 16 + 32 * 16
    assert res.blob[6:8] == b"\x20\x00"
    words = cht2bin.unpack(res.blob)
    assert len(words) == 32
    assert words[-1] >> 96 & 0xF == gbacht.OPT_ALWAYS, "pair split by the cap"
    # The words kept are the first 32 gbacht produced, in order.
    groups, _ = gbacht.parse(cht(*codes), max_entries=1000)
    assert words == gbacht.words(groups)[:32]


def test_cap_is_reported_on_stderr():
    codes = [f"3200{0x1000 + i:04X}+0001" for i in range(40)]
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "many.cht")
        open(src, "wb").write(cht(*codes))
        # Through the CLI the parse budget applies first, so gbacht itself
        # sheds the excess and the file simply holds 32 entries.
        rc, err = run_cli(src)
        assert rc == 0
        assert len(cht2bin.unpack(open(src[:-4] + ".chtbin", "rb").read())) == 32
        assert "32 entries" in err and "no room=8" in err
    # The converter's own cap, when something hands it more than the table.
    res = cht2bin.convert(cht(*codes), parse_limit=1000)
    assert res.entries == 32 and res.dropped == 8


# -------------------------------------------------------------- empty input --
def test_no_enabled_cheats_still_produces_a_valid_header():
    data = b'cheats = 1\n\ncheat0_code = "32001000+0001"\ncheat0_enable = false\n'
    res = cht2bin.convert(data)
    assert res.blob == HEADER and res.entries == 0 and res.cheats == 0
    assert cht2bin.unpack(res.blob) == []
    assert res.reasons.get("disabled") == 1


def test_empty_file_is_not_an_error():
    res = cht2bin.convert(b"")
    assert res.blob == HEADER
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "empty.cht")
        open(src, "wb").write(b"")
        assert run_cli(src)[0] == 0
        assert open(os.path.join(d, "empty.chtbin"), "rb").read() == HEADER


def test_only_enabled_cheats_are_emitted():
    """gbacht resolves the enable keys; this checks the converter adds nothing.

    One cheat off, one on, one with no key at all, which libretro treats as on.
    """
    data = (b'cheats = 3\n'
            b'\ncheat0_code = "32001000+0001"\ncheat0_enable = false\n'
            b'\ncheat1_code = "32001001+0002"\ncheat1_enable = true\n'
            b'\ncheat2_code = "32001002+0003"\n')
    res = cht2bin.convert(data)
    groups, _ = gbacht.parse(data)
    assert all(g.enabled for g in groups)
    assert res.entries == 2
    assert cht2bin.unpack(res.blob) == gbacht.words(groups)


# ----------------------------------------------------------------- garbage --
def test_malformed_input_converts_to_nothing_rather_than_failing():
    """A file that is not a .cht at all is not a converter error.

    There is nothing in a `.cht` that can fail to parse: the lexer only ever
    accepts hex runs inside a `_code` value and drops whatever it cannot use.
    A file with no such value is a file with no cheats, which is a valid
    result, so these must all produce a bare header and exit 0.
    """
    for data in (b"\x00\xff\xfe\x7f" * 64,
                 b"not a cheat file at all\n",
                 b'cheats = 2\ncheat0_code = "zzzz+not+hex"\n',
                 b'cheat0_code = "3200',              # truncated mid value
                 b'# _code means "Facade"\n',         # free text that looks
                 bytes(range(256))):
        res = cht2bin.convert(data)
        assert res.blob == HEADER, data[:24]
        assert cht2bin.unpack(res.blob) == []


def test_unreadable_input_exits_nonzero():
    with tempfile.TemporaryDirectory() as d:
        rc, err = run_cli(os.path.join(d, "missing.cht"))
        assert rc != 0 and "missing.cht" in err
        rc, err = run_cli(d)                    # a directory, not a file
        assert rc != 0
        # A bad file among good ones still fails the run, and the good ones
        # are still converted.
        good = os.path.join(d, "good.cht")
        open(good, "wb").write(cht("32001000+0001"))
        rc, _ = run_cli(os.path.join(d, "missing.cht"), good)
        assert rc != 0
        assert os.path.exists(os.path.join(d, "good.chtbin"))


# --------------------------------------------------------------------- CLI --
def test_default_output_name_replaces_the_last_extension():
    assert cht2bin.out_path("game.gba.cht", None) == "game.gba.chtbin"
    assert cht2bin.out_path("/a/b/game.cht", None) == "/a/b/game.chtbin"
    assert cht2bin.out_path("/a/b/game.gba.cht", "/out") == "/out/game.gba.chtbin"


def test_cli_writes_output_next_to_the_input():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "Some Game (USA).gba.cht")
        open(src, "wb").write(cht("32001000+0001"))
        rc, err = run_cli(src)
        assert rc == 0
        blob = open(os.path.join(d, "Some Game (USA).gba.chtbin"), "rb").read()
        assert len(blob) == 32
        for field in ("1 cheats", "1 entries", "0 dropped", "32 bytes", src):
            assert field in err


def test_cli_handles_several_inputs_and_an_outdir():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "out")
        names = ["a.cht", "b.cht"]
        for n in names:
            open(os.path.join(d, n), "wb").write(cht("32001000+0001"))
        rc, _ = run_cli("-d", out, *[os.path.join(d, n) for n in names])
        assert rc == 0
        assert sorted(os.listdir(out)) == ["a.chtbin", "b.chtbin"]


def test_cli_rejects_o_with_several_inputs():
    rc, err = run_cli("-o", "x.chtbin", "a.cht", "b.cht")
    assert rc != 0 and "single input" in err


def test_cli_reads_stdin():
    class FakeStdin:
        buffer = io.BytesIO(cht("32001000+0001"))

    with tempfile.TemporaryDirectory() as d:
        dst = os.path.join(d, "piped.chtbin")
        real, sys.stdin = sys.stdin, FakeStdin()
        try:
            rc, _ = run_cli("-", "-o", dst)
        finally:
            sys.stdin = real
        assert rc == 0
        assert len(open(dst, "rb").read()) == 32


# ------------------------------------------------------------- round trips --
def roundtrip(data: bytes) -> None:
    """The whole point of the format: what comes back out is what went in."""
    groups, _ = gbacht.parse(data)
    want = gbacht.words(groups)
    blob = cht2bin.convert(data).blob
    assert len(blob) == 16 + 16 * len(want)
    assert int.from_bytes(blob[6:8], "little") == len(want)
    assert cht2bin.unpack(blob) == want         # order included
    assert len(want) <= cht2bin.MAX_ENTRIES


def test_fixtures_round_trip():
    names = sorted(f for f in os.listdir(FIXTURES) if f.endswith(".cht"))
    assert names, "the fixture set went missing"
    for name in names:
        data = open(os.path.join(FIXTURES, name), "rb").read()
        roundtrip(data)
        roundtrip(ENABLE.sub(rb"\1true", data))


def test_entries_match_an_encoder_nobody_here_wrote():
    """The layout checked against MiSTer's own pre-encoded cheats.

    `mister_007.words` is the same libretro codes for 007 - Everything or
    Nothing as encoded by gamehacking.org and shipped in
    MiSTer-devel/Cheats_MiSTer, read back out of those binaries. It is a
    different implementation, by different people, of the same mapping, so it
    catches a byte lane or an address offset that our own decoder would agree
    with us about. Each entry in a `.chtbin` must be that 128-bit word with
    its bytes in the opposite order, because their file is most significant
    word first and ours is little-endian throughout.
    """
    want = [line.split()[0] for line
            in open(os.path.join(FIXTURES, "mister_007.words"))
            if line.strip() and not line.startswith("#")]
    blob = cht2bin.convert(
        open(os.path.join(FIXTURES, "mister_007.cht"), "rb").read()).blob
    assert len(want) == 8
    assert int.from_bytes(blob[6:8], "little") == len(want)
    for i, hexword in enumerate(want):
        entry = blob[16 + i * 16:32 + i * 16]
        assert entry == bytes.fromhex(hexword)[::-1], f"entry {i}"


def corpus_files() -> list[str]:
    return sorted(os.path.join(d, f)
                  for d, _, fs in os.walk(CHT_DB) for f in fs
                  if f.endswith(".cht"))


def test_corpus_round_trips():
    """Every real .cht in the corpus, as shipped and with every cheat on.

    This is the same set tools/sim/run.py checks the RTL against, so a pass
    here means the host converter and the parser that used to run on the FPGA
    agree over every file that verified the hardware.
    """
    files = corpus_files()
    if not files:
        if os.environ.get("CHT_DB"):
            raise AssertionError(
                f"CHT_DB={CHT_DB} holds no .cht files; the cross-check that "
                f"was asked for did not run")
        skip(f"no .cht files under {CHT_DB}; set CHT_DB to a corpus "
             f"(see docs/CHEATS.md) to run the cross-check")
    entries = enabled_entries = 0
    for path in files:
        data = open(path, "rb").read()
        try:
            roundtrip(data)
            entries += cht2bin.convert(data).entries
            flipped = ENABLE.sub(rb"\1true", data)
            roundtrip(flipped)
            enabled_entries += cht2bin.convert(flipped).entries
        except AssertionError as e:
            raise AssertionError(f"{os.path.basename(path)}: {e}") from None
    print(f"corpus: {len(files)} files round tripped, {entries} entries as "
          f"shipped, {enabled_entries} with every cheat enabled",
          file=sys.stderr, flush=True)


# ------------------------------------------------------------ script runner --
def main(argv: list[str]) -> int:
    """Run the tests without pytest, so the tool needs no dependency at all."""
    # The corpus pass needs a corpus this repo does not carry, so it is opt in
    # here. Under pytest it always runs, and skips loudly when there is
    # nothing to run it over.
    corpus = "--corpus" in argv
    tests = [(n, f) for n, f in sorted(globals().items())
             if n.startswith("test_") and callable(f)
             and (corpus or "corpus" not in n)]
    failed = skipped = 0
    for name, fn in tests:
        try:
            fn()
        except SKIPS:
            skipped += 1
        except AssertionError as e:
            failed += 1
            print(f"FAIL {name}: {e}", file=sys.stderr)
        except Exception as e:                  # noqa: BLE001
            failed += 1
            print(f"ERROR {name}: {type(e).__name__}: {e}", file=sys.stderr)
        else:
            print(f"ok   {name}")
    print(f"\n{len(tests) - failed - skipped}/{len(tests)} passed, "
          f"{skipped} skipped, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
