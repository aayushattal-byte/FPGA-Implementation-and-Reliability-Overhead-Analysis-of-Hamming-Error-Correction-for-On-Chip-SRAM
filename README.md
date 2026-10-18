# Hamming(72,64) SECDED SRAM on Spartan-7 -- simplified, single-file version

Hamming-only (no BCH). Everything is consolidated to as few files as
possible so it's fast to get running in Vivado.

**Verified by simulation** (Icarus Verilog, results below are from an actual
run of this exact code, not hand-waving):
```
Basic tests: 3 passed, 0 failed

1 bit flip(s) per word, 200 trials: 200 corrected, 0 detected-uncorrectable, 0 miscorrected
2 bit flip(s) per word, 200 trials: 0 corrected, 200 detected-uncorrectable, 0 miscorrected
3 bit flip(s) per word, 200 trials: 0 corrected, 0 detected-uncorrectable, 200 miscorrected
```
That last line is not a bug -- it's the expected, textbook behavior of
SECDED codes: they guarantee correction up to 1 bit and detection up to 2
bits, and beyond that (3+ flips) they can be fooled into "confidently"
returning the wrong answer with no warning. This is genuinely useful data
for your report's reliability-vs-overhead discussion.

## Files (only 3 to add to Vivado)

```
rtl/ecc_sram_top.v         ALL design logic in one file (6 modules inside)
tb/tb_ecc_sram.v           testbench: sanity checks + the 1/2/3-bit fault sweep
constraints/boolean_board.xdc   REAL, verified pin mapping for the RealDigital
                                 Boolean Board (xc7s50csga324-1) -- use this one
constraints/example_arty_s7.xdc TEMPLATE only, for a different Spartan-7 board
                                 (kept for reference, not needed if you're on
                                 the Boolean board)
```

`ecc_sram_top.v` contains, in this order: `hamming_encoder`, `hamming_decoder`,
`ecc_sram_wrapper`, `fault_injector`, `stats_logger`, `top_ecc_demo`. They're
still separate modules internally (that's just good practice, and Verilog
allows multiple modules per file) -- you just only have to add *one file* to
your project instead of six.

## Fastest path to done

### 1. Simulate first (5 minutes, catches any setup mistakes before Vivado)
```bash
sudo apt-get install iverilog        # one-time, skip if you have it
cd ecc_hamming_only
iverilog -g2005 -o sim.out rtl/ecc_sram_top.v tb/tb_ecc_sram.v
vvp sim.out
```
You should see the numbers above. If so, the logic is fully correct and
you can move straight to Vivado with confidence.

### 2. Vivado project
1. **Create Project** -> RTL Project -> select part **xc7s50csga324-1** (RealDigital
   Boolean Board)
2. **Add Sources** -> add `rtl/ecc_sram_top.v` as a design source
3. **Add Sources** -> add `tb/tb_ecc_sram.v` as simulation-only
4. **Add Constraints** -> add `constraints/boolean_board.xdc` (pin numbers are
   already correct for this board -- no editing needed, unlike a generic
   template)
5. In Sources, right-click `top_ecc_demo` -> **Set as Top** (for
   implementation), and `tb_ecc_sram` -> **Set as Top** (for simulation)

### 3. Confirm in Vivado's own simulator (optional if you already ran step 1)
Flow Navigator -> **Run Simulation -> Run Behavioral Simulation**. Same
pass/fail lines appear in the Tcl console.

### 4. Build and program
Flow Navigator -> **Run Synthesis** -> **Run Implementation** -> **Generate
Bitstream** -> Hardware Manager -> **Open Target** -> **Program Device**.

Check the **Utilization Report** after synthesis -- that's your overhead
number (LUTs/FFs used by the ECC logic).

### 5. See it work on the board
- Press **BTN_STEP** repeatedly: writes+reads a test pattern each press,
  `LED_PASS` lights (no error).
- Set switches to a bit position (0-71), press **BTN_INJECT**: flips that
  bit and re-reads. `LED_SEC` lights -- corrected in real time on real
  silicon.
- Press **BTN_INJECT** twice with two different switch settings before the
  next BTN_STEP: now `LED_DED` lights instead (two-bit error, correctly
  flagged as uncorrectable rather than silently returned wrong).
- `LED_HEARTBEAT` blinks continuously so you know the bitstream loaded and
  the clock is alive, independent of everything else.

## What to put in your report

- **Overhead**: 72/64 = 12.5% storage overhead (fixed, from the code math),
  plus whatever LUT/FF count Vivado's utilization report shows for the
  encoder+decoder+wrapper logic, plus the 2-cycle read latency
- **Reliability**: the three-line sweep result above -- this alone tells
  the whole story of what SECDED guarantees and where that guarantee ends
- **The narrative**: "Hamming SECDED gives 100% single-bit correction and
  100% double-bit detection at 12.5% storage overhead, but has zero
  protection against 3+ simultaneous bit errors in the same word -- which
  is an acceptable tradeoff for typical SRAM upset rates (single-bit upsets
  dominate), but would need a stronger code like BCH for higher-radiation
  or more error-prone environments."

## Notes

- Single-port memory: reads, writes, and fault injection all share one
  address bus (priority: inject > write > read). Real ECC controllers often
  use dual-port RAM for concurrent scrubbing -- worth a sentence as future
  work in your report.
- Read latency is 2 clock cycles (address in, `dout_valid` pulses 2 cycles
  later).
- If you ever do want to extend to BCH for a stronger comparison later, the
  `ecc_sram_wrapper` module's interface (`hamming_encoder`/`hamming_decoder`
  ports) is designed to be a drop-in swap -- ask any time.
