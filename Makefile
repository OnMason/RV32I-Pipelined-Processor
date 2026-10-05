# RV32I 5-stage pipeline — simulation
#
#   make sim                     directed + 20 constrained-random programs (Verilator)
#   make sim SEED=7 NTESTS=200   another seed / more programs
#   make sim PLUSARGS=+COV_ALL   print every coverage bin
#   make regress                 10 seeds x 50 programs
#   make riscv-tests             official rv32ui instruction tests
#   make lint                    Verilator lint of the RTL
#   make xsim                    random testbench under Vivado XSim
#   make clean
#
# Needs a recent Verilator 5 (tested with 5.048) for constraints, SVA and --timing;
# its constraint solver needs z3 on the PATH.

SEED     ?= 1
NTESTS   ?= 20
SEEDS    ?= 1 2 3 4 5 6 7 8 9 10
PLUSARGS ?=

RTL := rtl/rv32i_pkg.sv rtl/rv32i_decoder.sv rtl/rv32i_imm_gen.sv rtl/rv32i_regfile.sv \
       rtl/rv32i_alu.sv rtl/rv32i_branch_cmp.sv rtl/rv32i_forward_unit.sv \
       rtl/rv32i_hazard_unit.sv rtl/rv32i_core.sv rtl/rv32i_imem.sv rtl/rv32i_dmem.sv \
       rtl/rv32i_top.sv
SVA := tb/rv32i_core_sva.sv
TB  := tb/rv32i_tb_pkg.sv $(SVA) tb/tb_rv32i.sv

VERILATOR ?= verilator
VFLAGS := --binary --timing --assert -j 0 --timescale 1ns/1ps \
          -Wno-fatal -Wno-COVERIGN -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL \
          -Wno-IMPLICITSTATIC -Wno-PINCONNECTEMPTY \
          -CFLAGS "-std=c++20 -fcoroutines"

SIM   := build/verilator/Vtb_rv32i
RVSIM := build/riscv-tests/Vtb_riscv_tests
RVHEX := $(wildcard tests/riscv-tests/hex/*.text.hex)

.PHONY: sim regress riscv-tests lint xsim clean

$(SIM): $(RTL) $(TB)
	@mkdir -p $(dir $@)
	$(VERILATOR) $(VFLAGS) --top-module tb_rv32i -Mdir $(dir $@) $(RTL) $(TB) -o $(notdir $@)

$(RVSIM): $(RTL) $(SVA) tb/tb_riscv_tests.sv
	@mkdir -p $(dir $@)
	$(VERILATOR) $(VFLAGS) --top-module tb_riscv_tests -Mdir $(dir $@) $(RTL) $(SVA) tb/tb_riscv_tests.sv -o $(notdir $@)

sim: $(SIM)
	./$(SIM) +SEED=$(SEED) +NTESTS=$(NTESTS) $(PLUSARGS)

regress: $(SIM)
	@mkdir -p build/logs; fail=0; \
	for s in $(SEEDS); do \
	  ./$(SIM) +SEED=$$s +NTESTS=50 > build/logs/seed_$$s.log 2>&1; \
	  if grep -q "RESULT: PASS" build/logs/seed_$$s.log; then \
	    echo "seed $$s: $$(grep 'tests:' build/logs/seed_$$s.log)"; \
	  else echo "seed $$s: FAILED (see build/logs/seed_$$s.log)"; fail=1; fi; \
	done; exit $$fail

riscv-tests: $(RVSIM)
	@fail=0; for t in $(RVHEX); do \
	  n=$$(basename $$t .text.hex); \
	  out=$$(./$(RVSIM) +TEXT=$$t +DATA=$${t%.text.hex}.data.hex +NAME=$$n 2>&1 | grep -E "PASS|FAIL|Error"); \
	  echo "$$out"; case "$$out" in *"[PASS]"*) ;; *) fail=1 ;; esac; \
	done; exit $$fail

lint:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL $(RTL) --top-module rv32i_top

xsim:
	mkdir -p build/xsim && cd build/xsim && \
	xvlog -sv $(addprefix ../../,$(RTL) $(TB)) && \
	xelab tb_rv32i -s tb_rv32i_sim -timescale 1ns/1ps && \
	xsim tb_rv32i_sim -runall -testplusarg SEED=$(SEED) -testplusarg NTESTS=$(NTESTS)

clean:
	rm -rf build obj_dir *.vcd xsim.dir vivado_proj *.jou *.log *.pb
