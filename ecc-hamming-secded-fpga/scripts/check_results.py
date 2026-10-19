#!/usr/bin/env python3
"""Pass/fail gate for `make test`.

Checks the RTL simulation logs against (a) the guarantees of a SECDED code and
(b) the independent Python golden model, so a regression in either the RTL or the
testbench stimulus fails loudly instead of silently producing plausible numbers.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "model"))
from hamming_model import SecdedCode  # noqa: E402

failures = []


def check(cond, msg):
    print(("  ok    " if cond else "  FAIL  ") + msg)
    if not cond:
        failures.append(msg)


def read(name):
    with open(os.path.join(ROOT, "results", name)) as f:
        return f.read()


# ------------------------------------------------------------------ 64-bit SRAM
print("sim64.log  (Hamming(72,64) SRAM wrapper)")
log = read("sim64.log")
check("Basic tests: 3 passed, 0 failed" in log, "basic tests 1-3 pass")
check("[VERDICT] PASS" in log, "testbench verdict PASS (injection + stimulus checks clean)")
rows = {}
for m in re.finditer(r"\[RESULT\] flips=(\d+) trials=(\d+) corrected=(\d+) detected=(\d+) "
                     r"miscorrected=(\d+) noflag_ok=(\d+) noflag_wrong=(\d+) injection_verified=(\d+)", log):
    f, *vals = map(int, m.groups())
    rows[f] = dict(zip(["trials", "ok", "det", "mis", "nof_ok", "nof_bad", "inj"], vals))
check(set(rows) == {1, 2, 3}, "sweep results present for 1, 2 and 3 flips")
for f, r in rows.items():
    check(r["inj"] == r["trials"], f"{f}-bit: stored word verified to differ in exactly {f} bit(s) "
                                   f"in {r['inj']}/{r['trials']} trials")
if {1, 2, 3} <= set(rows):
    r = rows[1]; check(r["ok"] == r["trials"], "1-bit errors: 100% corrected")
    r = rows[2]; check(r["det"] == r["trials"], "2-bit errors: 100% detected as uncorrectable")
    r = rows[3]
    check(r["det"] == 0 and r["nof_ok"] == 0 and r["nof_bad"] == 0,
          "3-bit errors: never flagged as double error, never silent (always reported as 'corrected')")
    check(r["mis"] >= 0.95 * r["trials"], f"3-bit errors: {r['mis']}/{r['trials']} silently miscorrected (>=95%)")

# --------------------------------------------------- 13-bit codec vs golden model
print("sim13.log  (Hamming(13,8) codec, exhaustive 3-bit sweep) vs Python golden model")
log = read("sim13.log")
check("TOTAL (Cases 1-3): 3 passed, 0 failed" in log, "basic cases 1-3 pass")


def grab(label):
    m = re.search(re.escape(label) + r"\s*:\s*(\d+)", log)
    return int(m.group(1)) if m else None


tally, total, _ = SecdedCode(8).sweep(3, 0b10100110)
expected = {
    "error_correct=1, data CORRECT (lucky)": tally["corrected_ok"],
    "error_correct=1, data WRONG   (MISCORRECTED)": tally["miscorrected"],
    "double_error=1   (caught, safely rejected)": tally["detected"],
    "no flags, data still correct (harmless)": tally["noflag_ok"],
    "no flags, data WRONG  (SILENT CORRUPTION)": tally["noflag_wrong"],
}
check(total == 286, "model enumerated all 286 three-bit patterns")
for label, exp in expected.items():
    got = grab(label)
    check(got == exp, f"RTL {got} == model {exp}  [{label.strip()}]")

# ------------------------------------------------------ board-level (buttons -> LEDs)
print("simtop.log  (top_ecc_demo: button presses -> LED behaviour)")
log = read("simtop.log")
check(log.count("[PASS]") == 5 and "[FAIL]" not in log, "5/5 board-level LED checks pass")
check("[VERDICT] PASS" in log, "board-level verdict PASS")

print()
if failures:
    print(f"{len(failures)} CHECK(S) FAILED")
    sys.exit(1)
print("ALL CHECKS PASSED")
