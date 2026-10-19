# Simulation flow (Icarus Verilog + Python golden model).
#   make test   : run both RTL simulations + golden model, then check the results
#   make sim64  : Hamming(72,64) SRAM wrapper testbench
#   make sim13  : Hamming(13,8) codec testbench (exhaustive 3-bit sweep)
#   make simtop : board-level test (buttons -> LEDs) of top_ecc_demo
#   make selftest : prove the testbench detects broken fault injection
IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
BUILD    := build
RES      := results

.PHONY: all test sim64 sim13 simtop model selftest single clean
all: test

sim64:
	mkdir -p $(BUILD) $(RES)
	$(IVERILOG) -g2005 -s tb_ecc_sram -o $(BUILD)/sim64 rtl/sram64/*.v tb/tb_ecc_sram.v
	cd $(BUILD) && $(VVP) sim64 | tee ../$(RES)/sim64.log

sim13:
	mkdir -p $(BUILD) $(RES)
	$(IVERILOG) -g2005 -s tb_hamming_13_8 -o $(BUILD)/sim13 rtl/codec13_8/hamming_13_8.v tb/tb_hamming_13_8.v
	cd $(BUILD) && $(VVP) sim13 | tee ../$(RES)/sim13.log

simtop:
	mkdir -p $(BUILD) $(RES)
	$(IVERILOG) -g2005 -s tb_top_ecc_demo -o $(BUILD)/simtop rtl/sram64/*.v tb/tb_top_ecc_demo.v
	cd $(BUILD) && $(VVP) simtop | tee ../$(RES)/simtop.log

selftest:
	mkdir -p $(BUILD) $(RES)
	bash scripts/selftest_tb.sh

model:
	mkdir -p $(RES)
	$(PYTHON) model/hamming_model.py | tee $(RES)/model.log

test: sim64 sim13 simtop model selftest
	$(PYTHON) scripts/check_results.py

single:
	bash scripts/make_single_file.sh
	$(IVERILOG) -g2005 -s tb_ecc_sram -o $(BUILD)/sim_single vivado/ecc_sram_top.v tb/tb_ecc_sram.v

clean:
	rm -rf $(BUILD)
