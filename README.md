# RV32I 5-Stage Pipelined Processor

> A 5-stage pipelined RISC-V core implementing the full RV32I base integer instruction set in SystemVerilog, with data forwarding, a load-use hazard unit, and branch flushing — verified by a constrained-random testbench with a reference model, SystemVerilog assertions, functional coverage, and the official `riscv-tests` suite.

![HDL](https://img.shields.io/badge/HDL-SystemVerilog-blue)
![ISA](https://img.shields.io/badge/ISA-RV32I-green)
![Simulation](https://img.shields.io/badge/sim-Verilator%20%7C%20Vivado%20XSim-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

This repository started as a single-cycle RV32I-subset core written for UC Irvine EECS 31L. That version is preserved on the [`single-cycle`](../../tree/single-cycle) branch; `main` is now the pipelined redesign described here.

---

## Overview

| | |
|---|---|
| **ISA** | RV32I base integer, all 37 user-level instructions. `FENCE`, `ECALL`, `EBREAK` decode and execute as NOPs (no CSRs or traps). |
| **Pipeline** | IF → ID → EX → MEM → WB |
| **Data hazards** | Forwarding from EX/MEM and MEM/WB into EX; write-first register file; one-cycle stall for load-use |
| **Control hazards** | Branches and jumps resolve in EX, predict not-taken, 2-cycle flush when taken |
| **Memory** | Harvard: instruction ROM + byte-strobed data RAM, combinational read |
| **Verification** | Constrained-random programs checked instruction-by-instruction against a reference model, 35 SVA assertions, 117 functional coverage bins, 40 official `rv32ui` tests |

---

## Architecture

```
            ┌────────┐   ┌────────────┐   ┌───────────────┐   ┌──────────┐   ┌────────┐
   pc_next  │   IF   │   │     ID     │   │      EX       │   │   MEM    │   │   WB   │
  ┌────────►│  PC    │──►│  decoder   │──►│ fwd muxes     │──►│ store    │──►│ regfile│
  │         │  imem  │   │  imm gen   │   │ ALU           │   │ align    │   │ write  │
  │         └────────┘   │  regfile   │   │ branch cmp    │   │ dmem     │   └───┬────┘
  │            IF/ID     │  (read)    │   │ target adder  │   │ load ext │       │
  │                      └────────────┘   └──────┬────────┘   └────┬─────┘       │
  │                         ID/EX                │  EX/MEM         │  MEM/WB     │
  │                                              │                 │             │
  │   branch/jump target (redirect)              │                 │             │
  └──────────────────────────────────────────────┘                 │             │
                              ▲          ▲                         │             │
                              │          └───── forward EX/MEM ────┘             │
                              └──────────────── forward MEM/WB ──────────────────┘

   hazard unit:   load in EX + dependent instr in ID  →  stall PC and IF/ID, bubble into EX
                  taken branch / jump in EX           →  flush IF/ID and ID/EX
```

### Stages

| Stage | What happens | Modules |
|---|---|---|
| **IF** | PC register, instruction ROM read, next-PC select (PC+4 / hold / redirect target) | `rv32i_core`, `rv32i_imem` |
| **ID** | Decode to a control bundle, generate the immediate, read two registers | `rv32i_decoder`, `rv32i_imm_gen`, `rv32i_regfile` |
| **EX** | Forwarding muxes, ALU, branch comparison, branch/jump target adder | `rv32i_forward_unit`, `rv32i_alu`, `rv32i_branch_cmp` |
| **MEM** | Store alignment and byte strobes, data RAM access, load sign/zero extension | `rv32i_core`, `rv32i_dmem` |
| **WB** | Write the result to the register file | `rv32i_regfile` |

Every pipeline register carries a `valid` bit, the PC, and the instruction word alongside its data and control. A bubble is simply an entry with `valid = 0` and all side-effect controls cleared. The PC and instruction travel all the way to WB so each retiring instruction can be reported on a trace port and checked by the testbench.

### Data hazards

**Forwarding.** The instruction in EX may need a register that an older instruction has computed but not yet written back. `rv32i_forward_unit` selects, per operand, the freshest copy:

```
if      (EX/MEM.reg_write && EX/MEM.rd != 0 && EX/MEM.rd == ID/EX.rs)  →  EX/MEM result
else if (MEM/WB.reg_write && MEM/WB.rd != 0 && MEM/WB.rd == ID/EX.rs)  →  MEM/WB write data
else                                                                    →  value read in ID
```

The same forwarded operands feed the ALU, the branch comparator, the JALR target adder, and the store-data path.

**Write-first register file.** A register written in WB and read in ID during the same cycle returns the new value, which covers the three-instructions-apart case without a third forwarding path.

**Load-use stall.** A load's data only exists at the end of MEM, so the instruction immediately behind it cannot be fixed by forwarding. `rv32i_hazard_unit` holds the PC and IF/ID for one cycle and sends a bubble into EX; one cycle later the value forwards from MEM/WB:

```
stall  when  ID/EX.mem_read && ID/EX.rd != 0 && (ID/EX.rd == rs1_ID || ID/EX.rd == rs2_ID)
```

The decoder forces `rs1`/`rs2` to `x0` for instructions that do not read them (e.g. `LUI`, `JAL`), so unused register fields never cause a false stall or a false forward.

### Control hazards

Branches and jumps resolve in EX. The fetch stage assumes not-taken and keeps fetching sequentially; when EX redirects the PC, the two younger instructions in IF and ID are squashed. Every taken branch or jump therefore costs 2 cycles, and a not-taken branch costs nothing.

Resolving in EX rather than ID is a deliberate trade: resolving in ID would cut the penalty to one cycle, but it puts forwarding, a 32-bit compare, and the next-PC mux in series in one stage and needs extra stall cases for a branch that depends on the instruction right ahead of it. EX resolution keeps the hazard logic small and the critical path short.

### Design decisions

- **`x0` is hardwired to zero.** Reads return 0, writes are dropped, and `reg_write` is never asserted for `rd = x0` anywhere in the pipeline. (The single-cycle version treated `x0` as a normal register.)
- **Standard RV32I encodings.** `funct3 = 100` is XOR, as the spec defines. (The single-cycle version followed the course ALU spec, where it was NOR.)
- **Misaligned accesses are not trapped.** With no trap support, a load or store is aligned to its natural size by ignoring the low address bits: `LW`/`SW` use `addr[31:2]`, `LH`/`SH` use `addr[1]`, `LB`/`SB` use `addr[1:0]`.
- **Synchronous reset, no reset on datapath registers.** Only the PC and the `valid`/control bits need a reset value.

---

## Verification

Everything in this section was run with Verilator 5.x. The testbench is plain IEEE 1800 SystemVerilog and a Vivado XSim flow is included (`make xsim`, `build.tcl`).

### Testbench structure

```
 rv32i_rand_program ──► program words ──┬──► instruction ROM ──► DUT ──► retirement trace ─┐
 (constrained-random)                   │                                                  ▼
                                        └──► rv32i_ref_model ──► expected retirement ──► scoreboard
                                                                                           │
 rv32i_core_sva  (bound into the core, checks pipeline control every cycle)                │
 rv32i_coverage  (functional coverage bins) ◄──────────────────────────────────────────────┘
```

**Constrained-random stimulus** (`tb/rv32i_tb_pkg.sv`). Each instruction is drawn in two steps. First a set of *knobs* is randomized with weighted `dist` constraints: instruction category, whether each source register should match the destination of the previous or second-previous instruction, which register pool to draw from, and whether a memory access targets a small shared window. Then the instruction fields are randomized under constraints shaped by those knobs. The dependency knobs are what make the stimulus effective: they deliberately create EX/MEM forwards, MEM/WB forwards, and load-use stalls far more often than uniform random registers would.

Four stimulus profiles rotate across tests: balanced, hazard-heavy (dense dependencies, many loads), branch-heavy, and memory-heavy.

Programs always terminate by construction. Random branches and jumps only go forward to an instruction boundary. Backward branches come from counted loops on a reserved register (`x31`) that random instructions never write; loops are not nested and exit as soon as the counter is ≤ 0.

**Reference model.** `rv32i_ref_model` is an untimed instruction-set simulator written directly from the ISA spec. On every retirement the scoreboard compares PC, instruction word, register write (enable, index, data), and memory write (strobes, address, data). At the end of each program the full register file and data memory are compared as well.

**Directed test.** One hand-written program with expected values worked out by hand (loop sum, sub-word loads and stores, call/return, signed vs. unsigned compares). This anchors the flow to something that does not depend on the reference model.

**Official tests.** `tests/riscv-tests/` holds prebuilt images of the RISC-V project's `rv32ui` suite. They are self-checking programs with no connection to this repo's reference model, so they are an independent check on ISA correctness.

### Assertions

`tb/rv32i_core_sva.sv` is attached to the core with `bind`, so the RTL carries no verification code. 35 assertions in six groups:

| Group | Examples |
|---|---|
| PC sequencing | PC advances by 4, holds during a stall, or takes the resolved target; targets have bit 0 clear |
| Load-use stall | A dependent instruction behind a load stalls; nothing else stalls; IF/ID holds; a bubble enters EX; the stall lasts one cycle; EX never consumes data from a load still in MEM |
| Flush | A redirect only comes from a valid branch/jump; both wrong-path instructions are squashed; the next instruction to reach ID is the target; stall and redirect never coincide |
| Forwarding | Youngest producer wins; the operand used in EX equals the freshest copy of the register; no forward without a matching producer; `x0` always reads 0 |
| Side effects | Bubbles have no active control in EX/MEM/WB; `x0` is never written; no memory strobe without a store |
| Flow | No instruction is dropped between ID→EX, EX→MEM, MEM→WB |

14 `cover property` statements confirm the interesting scenarios occurred (each forwarding path, both paths at once, MEM-over-WB priority, stall followed by a dependent branch, back-to-back stalls, and so on).

### Functional coverage

117 bins, reported at the end of every run:

- every instruction retired
- forwarding source (none / WB / MEM) × consumer (ALU, branch, JALR base, load address, store address, store data) for both operands
- load-use stall on `rs1` and on `rs2`; the stalled instruction being a branch, a load, or a store's data
- each branch type taken and not taken; forward and backward taken branches; JALR with bit 0 set
- flushes that squash a store, a load, or another branch
- every load/store size at every byte offset; sign-extension of a negative value; a load reading back a store
- writes to `x0` discarded; same-cycle WB-write / ID-read

Native `covergroup`s for instruction and hazard coverage are declared in `tb_rv32i.sv` for simulators that support them. The bins above are also kept as plain counters so the same report comes out of every simulator (Verilator parses covergroups but does not collect them).

### Results

| Check | Result |
|---|---|
| Directed program | pass |
| Constrained-random regression, 10 seeds × 50 programs | 500 programs, ~218,000 instructions retired, 0 mismatches |
| Functional coverage | 117 / 117 bins (reached within 8 programs on seed 1) |
| SVA assertions | 0 failures across the regression |
| Official `riscv-tests` `rv32ui` | 40 / 40 pass |
| Verilator lint (`-Wall`) on the RTL | clean |

Average CPI over the random regression is 1.32. The gap from 1.0 is the 2-cycle flush on taken branches and jumps plus the 1-cycle load-use stall; the random programs are far more branch- and dependency-dense than compiled code.

Two `rv32ui` tests are not run: `fence_i` (needs Zifencei and self-modifying code) and `ma_data` (misaligned accesses, which this core does not trap).

### Does the testbench catch bugs?

To check that a passing run means something, 25 single-line bugs were injected into the RTL one at a time and the random testbench was rerun (4 programs each). All 25 were caught by the scoreboard, and the assertions independently flagged the ones in pipeline control:

| Injected bug | Scoreboard | Assertion that fired |
|---|---|---|
| Forwarding priority swapped (WB before MEM) | caught | `a_fwd_a_mem` |
| No MEM/WB forward on `rs2` | caught | `a_fwd_b_wb` |
| Load-use stall removed | caught | `a_load_use_stalls` |
| Load-use stall ignores `rs2` | caught | `a_load_use_stalls` |
| IF/ID not held during stall | caught | `a_load_use_stalls` |
| PC not held during stall | caught | `a_pc_hold_on_stall` |
| IF/ID not flushed on redirect | caught | `a_redirect_flushes` |
| ID/EX not flushed on redirect | caught | `a_redirect_flushes` |
| Redirect raised by a bubble | caught | `a_redirect_only_from_control` |
| JALR target keeps bit 0 | caught | `a_jump_target_aligned` |
| Register file without write-first bypass | caught | — |
| Store data / branch operand taken before forwarding | caught | — |
| Datapath bugs (SRA as SRL, SLTU as SLT, BGE as BGEU, SLTIU as SLTI, LB zero-extends, LH wrong half, SB strobe not shifted, RAM ignores strobes, wrong link address, B-immediate bit swapped, AUIPC uses rs1, store writes rd) | caught | — |

Datapath bugs are the scoreboard's job; the assertions target control. A few of the bugs, including the swapped forwarding priority, slip past the directed test and are only caught by random stimulus.

---

## Repository structure

```
├── rtl/
│   ├── rv32i_pkg.sv            # opcodes, ALU ops, control bundle
│   ├── rv32i_core.sv           # the pipeline: stage registers + datapath
│   ├── rv32i_decoder.sv        # instruction → control signals
│   ├── rv32i_imm_gen.sv        # I/S/B/U/J immediates
│   ├── rv32i_regfile.sv        # 32×32, x0 = 0, write-first
│   ├── rv32i_alu.sv            # add/sub/shift/compare/logic
│   ├── rv32i_branch_cmp.sv     # six branch conditions
│   ├── rv32i_forward_unit.sv   # bypass selects
│   ├── rv32i_hazard_unit.sv    # stall + flush
│   ├── rv32i_imem.sv           # instruction ROM
│   ├── rv32i_dmem.sv           # data RAM with byte strobes
│   └── rv32i_top.sv            # core + memories
├── tb/
│   ├── rv32i_tb_pkg.sv         # assembler, random generator, reference model, coverage
│   ├── rv32i_core_sva.sv       # assertions + bind
│   ├── tb_rv32i.sv             # directed + constrained-random testbench
│   └── tb_riscv_tests.sv       # runner for the official rv32ui images
├── tests/riscv-tests/          # prebuilt rv32ui images, env header, linker script, build script
├── Makefile                    # Verilator and XSim flows
└── build.tcl                   # Vivado project + simulation
```

---

## How to run

### Verilator

Needs a recent Verilator 5 (tested with 5.048; early 5.0xx releases lack constraint-solver support) and `z3` on the PATH, which Verilator uses to solve constraints.

```bash
make sim                      # directed + 20 random programs
make sim SEED=7 NTESTS=200    # different seed, more programs
make sim PLUSARGS=+COV_ALL    # print every coverage bin with its hit count
make sim PLUSARGS=+VERBOSE    # print every retired instruction
make regress                  # 10 seeds × 50 programs
make riscv-tests              # official rv32ui suite
make lint
```

A failing run prints the first mismatches with PC, instruction, and expected vs. actual values. Re-running with the same `SEED` reproduces it exactly.

### Vivado

```bash
vivado -mode batch -source build.tcl     # creates the project, runs tb_rv32i in XSim
make xsim                                # or the command-line flow
```

`build.tcl` targets the Basys 3 part (`xc7a35tcpg236-1`) so the same project can be synthesised.

---

## Limitations and next steps

- **Not yet on an FPGA.** The RTL is written to be synthesisable, but synthesis, timing closure, and an Fmax comparison against the single-cycle core have not been done. The memories use combinational read, which maps to distributed RAM; moving to block RAM means registering the read and adjusting IF and MEM.
- **No CSRs, interrupts, or exceptions.** Illegal instructions execute as NOPs.
- **Static not-taken prediction.** A small branch predictor would cut the 2-cycle taken penalty.
- **Verified in Verilator.** The XSim flow is provided but the results above come from Verilator.

---

## Tools

- **HDL:** SystemVerilog (IEEE 1800-2017)
- **Simulation:** Verilator 5.x; Xilinx Vivado XSim
- **Reference tests:** [riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests) (BSD-3-Clause)
- **ISA reference:** *The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA*
