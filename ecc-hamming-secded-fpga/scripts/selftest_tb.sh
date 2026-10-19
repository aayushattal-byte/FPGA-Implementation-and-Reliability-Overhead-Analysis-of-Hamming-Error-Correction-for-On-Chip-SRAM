#!/usr/bin/env bash
# Testbench self-test ("test the tester"): re-create the failure that fooled the
# first version of the sweep -- the fault port receiving an undefined address so
# no fault ever lands -- and require the testbench to FAIL loudly.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
sed "s/inject_addr = t_addr;/inject_addr = 8'bx;/" tb/tb_ecc_sram.v > build/tb_mutant.v
iverilog -g2005 -s tb_ecc_sram -o build/sim_mutant rtl/sram64/*.v build/tb_mutant.v
(cd build && vvp sim_mutant) > results/selftest_mutant.log
grep -q "\[VERDICT\] FAIL" results/selftest_mutant.log \
  && grep -q "injection_verified=0" results/selftest_mutant.log \
  && ! grep -q "corrected=200" results/selftest_mutant.log \
  && echo "selftest ok: broken fault injection is detected (verdict FAIL, injection_verified=0, no fake 'corrected')" \
  || { echo "SELFTEST FAILED: the testbench did not flag broken fault injection"; exit 1; }
