# Verification

Everything below is reproduced by `make test`; the raw logs are in [`../results`](../results).

## What is checked

| Test | File | Checks |
|---|---|---|
| 64-bit SRAM | `tb/tb_ecc_sram.v` | round trip, single-bit correct, double-bit detect, then a sweep of 1/2/3 distinct random bit errors x 200 trials. Each trial's injection is verified by reading the stored codeword (Hamming distance must equal the intended error count). |
| 13-bit codec | `tb/tb_hamming_13_8.v` | basic cases, then **every** 3-bit error pattern (286) |
| Board demo | `tb/tb_top_ecc_demo.v` | presses step / inject / inject+inject like a person and checks the LEDs |
| Golden model | `model/hamming_model.py` | independent Python implementation, exhaustive sweeps for both codes |
| Cross-check | `scripts/check_results.py` | RTL logs must agree with the model and with the SECDED guarantees |
| Testbench self-test | `scripts/selftest_tb.sh` | forces the fault port to an undefined address; the testbench must report FAIL |

## Results

**RTL, Hamming(72,64), 200 random trials per row** (deterministic xorshift32 stimulus):

| Errors | corrected | detected | miscorrected | no flag | injections verified |
|---|---|---|---|---|---|
| 1 | 200 | 0 | 0 | 0 | 200/200 |
| 2 | 0 | 200 | 0 | 0 | 200/200 |
| 3 | 0 | 0 | 200 | 0 | 200/200 |

**Exhaustive (golden model)**:

| Code | errors | patterns | corrected | detected | miscorrected | harmless |
|---|---|---|---|---|---|---|
| (13,8) | 1 | 13 | 13 | 0 | 0 | - |
| (13,8) | 2 | 78 | 0 | 78 | 0 | - |
| (13,8) | 3 | 286 | 0 | 0 | 284 | 2 |
| (72,64) | 1 | 72 | 72 | 0 | 0 | - |
| (72,64) | 2 | 2,556 | 0 | 2,556 | 0 | - |
| (72,64) | 3 | 59,640 | 0 | 0 | 59,625 | 15 |

"Harmless" = the decoder reported a correction and the data happened to be intact (all residual errors fell on parity bits).
The RTL's exhaustive (13,8) result (2 / 284 / 0) equals the model's exactly. The 200-trial RTL sample for (72,64)
shows 200/200 miscorrected, consistent with the model: at 15 harmless in 59,640 a 200-trial sample contains none
about 95% of the time.

## Why 3 errors fail

The decoder's decision table (see [`DESIGN.md`](DESIGN.md)) sends every word whose overall parity check fails to the
single-error branch. An odd number of flips always fails that check, so with 3 errors the decoder:

1. never reaches the double-error branch (`ded` stays 0 in all 286 and all 59,640 patterns), and
2. flips one bit chosen by the syndrome, unrelated to the real error pattern, leaving at least two errors in place.

The data is right only when the leftover errors all land on parity positions.

(An earlier explanation, that a 3-bit error always lies at distance 1 from another codeword, is only true for
unshortened codes. It was caught by the golden model and corrected.)

## A possible improvement (not implemented in RTL)

Because (72,64) and (13,8) are shortened codes, a 3-bit error can produce a syndrome that points outside the codeword:
14,336 of 59,640 patterns (24.0%) for (72,64) and 66 of 286 (23.1%) for (13,8). The RTL currently performs no flip and
reports `sec`. Treating an out-of-range syndrome as uncorrectable (`ded`) would detect those patterns at no cost to
1- and 2-bit behaviour. This is a model-derived estimate; implementing and re-verifying it is a next step.

## Testbench integrity

A testbench can be wrong in ways that look like success. Two safeguards were added after real incidents
([`DEBUGGING.md`](DEBUGGING.md)): no-flag outcomes are never counted as "corrected", and the stored codeword is read
back to prove each injection landed. `scripts/selftest_tb.sh` proves these safeguards work by breaking the fault
port on purpose.

## Not yet verified

- Updated testbenches in Vivado xsim (the earlier sweep misbehaved there for the reason documented in the debugging log).
- Post-synthesis / post-implementation simulation and timing.
- Behaviour on the physical board ([`HARDWARE_VALIDATION.md`](HARDWARE_VALIDATION.md)).
