# Vivado guide (RealDigital Boolean Board, xc7s50csga324-1)

## Create the project
1. Create Project -> RTL Project -> part **xc7s50csga324-1**.
2. **Design source:** `vivado/ecc_sram_top.v` (all six modules; regenerate with `make single`).
3. **Simulation sources:** `tb/tb_ecc_sram.v`, `tb/tb_top_ecc_demo.v` (and `tb/tb_hamming_13_8.v` plus
   `rtl/codec13_8/hamming_13_8.v` if you want the 13-bit sweep; that pair does not need constraints).
4. **Constraints:** `constraints/boolean_board.xdc`.
5. Set top: `top_ecc_demo` for implementation; `tb_ecc_sram` (or `tb_top_ecc_demo`) for simulation.

## Simulate
Set the run time first, otherwise xsim stops at 1000 ns:

```
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]
```

or type `run -all` in the Tcl console after launching. Expected end of `tb_ecc_sram` log:
`[RESULT] flips=1 ... corrected=200 ... injection_verified=200`, flips=2 -> `detected=200`, flips=3 -> `miscorrected=200`,
and `[VERDICT] PASS`. For `tb_top_ecc_demo`: five `[PASS]` lines and `[VERDICT] PASS`.

If a `[CHECK-FAIL]` or `[ERROR]` line appears, the stimulus (not the decoder) is the problem; send that log output.

## Build and program
Run Synthesis, Run Implementation, Generate Bitstream, then Hardware Manager -> Open Target -> Program Device.
After synthesis and implementation, record **utilization** and **timing** in
[`HARDWARE_VALIDATION.md`](HARDWARE_VALIDATION.md).
