# Debugging log

Each entry: symptom, root cause, how it was found, fix.

## 1. Testbench double-pulsed the fault port
- **Symptom:** single-bit test returned correct data but `sec_flag` was 0.
- **Cause:** control signals were driven with blocking assignments at the clock edge, so `inject_en` was sampled on two
  consecutive edges and the bit was flipped twice (net: no error).
- **Found by:** printing codeword and flags cycle by cycle, then testing encoder+decoder alone (all 72 single-bit flips
  correct), which isolated the problem to the wrapper stimulus.
- **Fix:** drive stimulus on the falling edge.

## 2. `$random % 72` skipped injections
- **Symptom:** a 200-trial single-bit sweep reported only 120 corrected.
- **Cause:** `$random` is signed, so the modulo went negative and produced out-of-range bit indices; the write was silently ignored.
- **Fix:** unsigned arithmetic, later replaced by a deterministic generator.

## 3. Vivado showed only 3 tests
- **Symptom:** console stopped after the basic tests with `XSim simulation ran for 1000ns`.
- **Cause:** xsim's default run time is 1000 ns; the sweep needs far longer.
- **Fix:** `run -all`, or set `xsim.simulate.runtime` to `-all`.

## 4. Vivado: identical results for 1, 2 and 3 errors (the important one)
- **Symptom:** `200 corrected, 0 detected, 0 miscorrected` for every error count, which is impossible for a SECDED code.
- **Wrong first diagnosis:** the retry loop that picked distinct bit positions. Rewriting it as a Fisher-Yates shuffle changed nothing.
- **Real cause (from the waveform):** `inject_addr` was `XX` for the whole sweep, so every injection targeted an undefined
  address and no fault was ever written. The sweep then counted "no flag raised, data intact" as "corrected", turning a
  failed stimulus into plausible output.
- **Fix:** (a) no-flag outcomes are a separate class; (b) the stored codeword is read back and its Hamming distance to the
  pre-injection word must equal the intended error count; (c) X/Z guards on every fault-port address; (d) tasks take no
  arguments (module-level registers instead of part-selects passed into static tasks); (e) deterministic xorshift32
  stimulus; (f) the testbench is itself tested by forcing the address to X (`make selftest`).
- **Status:** verified in Icarus. **Re-run in Vivado xsim pending.** If it still misbehaves there, the new `[CHECK-FAIL]`
  and `injection_verified=` lines will say whether the stimulus or the decoder is at fault.

## 5. Board demo LEDs were one operation behind
- **Symptom (board-level simulation):** after step the LEDs were undefined; after inject they showed the previous step's PASS.
- **Cause:** the FSM used `dout_valid` as "result ready", but it is already high while idle, so flags were latched before the
  new write/injection reached the output.
- **Found by:** `tb/tb_top_ecc_demo.v`, written because the demo had only ever been simulated at the memory level.
- **Fix:** fixed 8-cycle settle time before latching. The test now passes 5/5.

## 6. Signals used before declaration
- `inject_en_w` and friends were referenced in an instance before their declaration (implicit-net hazard in strict tools).
  Declarations moved above first use.

## 7. Wrong explanation of the 3-error behaviour
- An early write-up attributed silent miscorrection to the code's minimum distance. The golden model showed that is not
  generally true for shortened codes; the actual cause is the odd-parity decision rule (see `VERIFICATION.md`).
  The model also revealed the out-of-range-syndrome opportunity.

## Lessons
Test the testbench. Never let "nothing happened" count as success. Prove stimulus landed. Simulate at the level you will
demonstrate (board-level, not only memory-level). Cross-check RTL against an independent model.
