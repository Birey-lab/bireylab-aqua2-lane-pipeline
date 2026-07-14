#!/usr/bin/env python3
# Differential parity test for lif_extract_headless.py's pure logic.
#
# Runs under stock CPython (no Fiji needed) -- it imports the engine with the
# Java/Fiji classes stubbed out (they only load inside decode/save functions),
# and checks the ported trim math against an INDEPENDENT transcription of the
# interactive macro's computeTrimFrames (LIF_Extract_and_Trim.ijm lines 492-517),
# plus the Hz-labelling / filename rules. This guards against transcription bugs
# in the port; the Bio-Formats *decode* is validated separately on a real LIF.
#
#   python3 fiji-macros/tests/test_lif_extract_logic.py   # exit 0 = pass

import os
import sys
import math

os.environ["LIF_EXTRACT_NO_MAIN"] = "1"  # import without running the engine
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import lif_extract_headless as E  # noqa: E402


def ref(total, fi, mode, start_sec, amount, unit_seconds):
    """Independent transcription of the macro's computeTrimFrames."""
    n_keep = amount
    if unit_seconds:
        n_keep = math.floor(amount / fi)
    if n_keep < 1:
        n_keep = 1
    short = 0
    if mode == "middle":
        start = math.floor((total - n_keep) / 2) + 1   # centered
        end = start + n_keep - 1
    elif mode == "last":
        end = total
        start = total - n_keep + 1
        if start < 1:
            start = 1
            short = 1
    else:  # first
        start = math.floor(start_sec / fi) + 1
        end = start + n_keep - 1
    if start < 1:
        start = 1
    if end > total:
        end = total
        short = 1
    bad = 1 if (start > total or start > end) else 0
    return (int(start), int(end), bool(short), bool(bad))


def main():
    fails = 0
    checks = 0
    for mode in ("middle", "last", "first"):
        for unit_seconds in (True, False):
            for fi in (0.05, 0.0553, 1.0, 0.2):
                for total in (1, 5, 100, 600, 1200, 1201):
                    for start_sec in (0, 15, 100):
                        for amount in (1, 30, 60, 500):
                            exp = ref(total, fi, mode, start_sec, amount, unit_seconds)
                            g = E.compute_trim_frames(total, fi, mode, start_sec, amount, unit_seconds)
                            got = (g[0], g[1], bool(g[2]), bool(g[3]))
                            checks += 1
                            if got != exp:
                                fails += 1
                                if fails <= 8:
                                    print("MISMATCH mode=%s us=%s fi=%s total=%s start=%s amt=%s -> got %s exp %s"
                                          % (mode, unit_seconds, fi, total, start_sec, amount, got, exp))
    print("compute_trim_frames: %d checks, %d mismatches" % (checks, fails))

    # Hz labelling: end-anchored, idempotent, respects the toggle.
    assert E.labelled("Series003", "5.00", True) == "Series003_5.00Hz"
    assert E.labelled("Series003_5.00Hz", "5.00", True) == "Series003_5.00Hz"
    assert E.labelled("S_18.06Hz", "18.06", True) == "S_18.06Hz"
    assert E.labelled("Series003", "5.00", False) == "Series003"
    assert E.d2s(1.0 / 0.05, 2) == "20.00"
    # strip_prefix: keep text after last ' - ', sanitize path chars.
    assert E.strip_prefix("Project - Region1 - Series003") == "Series003"
    assert E.strip_prefix("A/B:C") == "A_B_C"
    assert E.strip_prefix("NoDash") == "NoDash"
    print("labelling / d2s / strip_prefix: OK")

    # Frame-unit spot checks (no float-floor ambiguity) + the bad-window case.
    assert E.compute_trim_frames(1200, 1.0, "last", 0, 500, False) == (701, 1200, False, False)
    assert E.compute_trim_frames(1200, 1.0, "first", 15, 500, False)[:2] == (16, 515)
    # middle is a true centered window (distinct from first): 500 of 1200 -> 351-850
    assert E.compute_trim_frames(1200, 1.0, "middle", 0, 500, False) == (351, 850, False, False)
    _, _, _, bad = E.compute_trim_frames(1200, 0.05, "first", 100, 10, True)
    assert bad, "expected a bad (skip) window when trim start is past end of recording"
    print("exact spot-checks: OK")

    print("RESULT:", "ALL PASS" if fails == 0 else ("FAILED (%d mismatches)" % fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
