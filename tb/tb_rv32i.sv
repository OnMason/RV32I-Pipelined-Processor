// -----------------------------------------------------------------------------
// tb_rv32i — self-checking testbench for the pipelined RV32I core
//
//   1. A directed program with hand-computed expected results (sanity anchor
//      that does not depend on the reference model).
//   2. NTESTS constrained-random programs. Every retired instruction is
//      compared against the reference model (PC, instruction, register write,
//      memory write); final register file and data memory are compared too.
//   3. SVA assertions (rv32i_core_sva, bound into the core) run throughout.
//   4. Functional coverage is collected and reported at the end.
//
// Plusargs:
//   +SEED=<n>      base random seed            (default 1)
//   +NTESTS=<n>    number of random programs   (default 20)
//   +MIN_LEN=<n>   min random-body length      (default 200)
//   +MAX_LEN=<n>   max random-body length      (default 400)
//   +VERBOSE       print every retired instruction
//   +COV_ALL       print every coverage bin, not just the misses
//   +WAVES         dump tb_rv32i.vcd
// -----------------------------------------------------------------------------

module tb_rv32i;

  import rv32i_pkg::*;
  import rv32i_tb_pkg::*;

  localparam int IMEM_WORDS = 4096;
  localparam int DMEM_WORDS = 1024;

  // ---------------------------------------------------------------------------
  // Clock, reset, DUT
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  logic reset = 1'b1;
  always #5 clk = ~clk;

  logic        ret_valid;
  logic [31:0] ret_pc, ret_instr, ret_rd_wdata, ret_mem_addr, ret_mem_wdata;
  logic        ret_rd_we;
  logic [4:0]  ret_rd;
  logic [3:0]  ret_mem_wstrb;

  rv32i_top #(
    .IMEM_WORDS (IMEM_WORDS),
    .DMEM_WORDS (DMEM_WORDS)
  ) dut (
    .clk           (clk),
    .reset         (reset),
    .ret_valid     (ret_valid),
    .ret_pc        (ret_pc),
    .ret_instr     (ret_instr),
    .ret_rd_we     (ret_rd_we),
    .ret_rd        (ret_rd),
    .ret_rd_wdata  (ret_rd_wdata),
    .ret_mem_wstrb (ret_mem_wstrb),
    .ret_mem_addr  (ret_mem_addr),
    .ret_mem_wdata (ret_mem_wdata)
  );

  // ---------------------------------------------------------------------------
  // Testbench state
  // ---------------------------------------------------------------------------
  rv32i_ref_model model;
  rv32i_coverage  cov;

  int unsigned seed, ntests, min_len, max_len;
  bit          verbose, cov_all;

  int unsigned errors;           // scoreboard mismatches (all tests)
  int unsigned tests_run, tests_failed;
  longint unsigned total_cycles, total_retired;

  bit          checking;         // scoreboard + coverage enabled
  bit          halted;
  int unsigned test_errors;
  longint unsigned test_cycles, test_retired;
  int unsigned idle_cycles;

  // ---------------------------------------------------------------------------
  // Coverage model
  // ---------------------------------------------------------------------------
  instr_e ret_kind;
  assign ret_kind = decode_kind(ret_instr);

  // Native covergroups for simulators that support them (e.g. Vivado XSim).
  // The rv32i_coverage counters below mirror these bins for portability.
  covergroup cg_retire;
    cp_instr: coverpoint ret_kind;
    cp_rd:    coverpoint ret_rd { bins x0 = {0}; bins low[] = {[1:7]}; bins high = {[8:31]}; }
  endgroup

  covergroup cg_hazard;
    cp_fwd_a: coverpoint dut.u_core.fwd_a_e { bins none = {FWD_NONE}; bins wb = {FWD_WB}; bins mem = {FWD_MEM}; }
    cp_fwd_b: coverpoint dut.u_core.fwd_b_e { bins none = {FWD_NONE}; bins wb = {FWD_WB}; bins mem = {FWD_MEM}; }
    cp_stall: coverpoint dut.u_core.stall_f;
    cp_redir: coverpoint dut.u_core.pc_redirect_e;
    x_fwd:    cross cp_fwd_a, cp_fwd_b;
  endgroup

  cg_retire cg_retire_i = new();
  cg_hazard cg_hazard_i = new();

  function automatic string fwd_name(fwd_sel_e f);
    case (f)
      FWD_MEM: return "MEM";
      FWD_WB:  return "WB";
      default: return "NONE";
    endcase
  endfunction

  // "I_BEQ" -> "BEQ"
  function automatic string mnemonic(instr_e k);
    string n = k.name();
    return n.substr(2, n.len() - 1);
  endfunction

  function automatic string consumer_name(ctrl_t c);
    if (c.branch)    return "branch";
    if (c.jalr)      return "jalr";
    if (c.mem_read)  return "load_addr";
    if (c.mem_write) return "store";
    return "alu";
  endfunction

  function automatic void define_coverage();
    instr_e k;
    string  fwd [3]  = '{"NONE", "WB", "MEM"};
    string  cons [5] = '{"alu", "branch", "jalr", "load_addr", "store"};
    string  br [6]   = '{"BEQ", "BNE", "BLT", "BGE", "BLTU", "BGEU"};

    // every instruction retired at least once
    k = k.first();
    for (int i = 0; i < NUM_INSTR; i++) begin
      cov.define_bin({"instr.", mnemonic(k)});
      k = k.next();
    end
    // forwarding path x what consumed the value
    foreach (fwd[i]) foreach (cons[j]) begin
      cov.define_bin({"fwd_a.", fwd[i], ".", cons[j]});
      if (cons[j] != "jalr" && cons[j] != "load_addr")       // these only read rs1
        cov.define_bin({"fwd_b.", fwd[i], ".", cons[j]});
    end
    cov.define_bin("fwd.a_and_b_same_cycle");
    cov.define_bin("fwd.priority_mem_over_wb");
    // stalls
    cov.define_bin("stall.load_use_rs1");
    cov.define_bin("stall.load_use_rs2");
    cov.define_bin("stall.then_wb_forward");
    cov.define_bin("stall.dependent_is_branch");
    cov.define_bin("stall.dependent_is_store_data");
    cov.define_bin("stall.dependent_is_load");
    // control flow
    foreach (br[i]) begin
      cov.define_bin({"branch.", br[i], ".taken"});
      cov.define_bin({"branch.", br[i], ".not_taken"});
    end
    cov.define_bin("branch.backward_taken");
    cov.define_bin("branch.forward_taken");
    cov.define_bin("jump.JAL");
    cov.define_bin("jump.JALR");
    cov.define_bin("jump.JALR_lsb_cleared");
    cov.define_bin("flush.squashed_two_valid");
    cov.define_bin("flush.squashed_store");
    cov.define_bin("flush.squashed_load");
    cov.define_bin("flush.squashed_branch_or_jump");
    // memory access shapes
    for (int o = 0; o < 4; o++) begin
      cov.define_bin($sformatf("mem.LB_off%0d", o));
      cov.define_bin($sformatf("mem.LBU_off%0d", o));
      cov.define_bin($sformatf("mem.SB_off%0d", o));
    end
    for (int o = 0; o < 4; o += 2) begin
      cov.define_bin($sformatf("mem.LH_off%0d", o));
      cov.define_bin($sformatf("mem.LHU_off%0d", o));
      cov.define_bin($sformatf("mem.SH_off%0d", o));
    end
    cov.define_bin("mem.LW");
    cov.define_bin("mem.SW");
    cov.define_bin("mem.load_sign_extended_negative");
    cov.define_bin("mem.store_then_load_same_word");
    // misc
    cov.define_bin("reg.write_to_x0_discarded");
    cov.define_bin("reg.wb_to_id_same_cycle_bypass");
  endfunction

  // Sample pipeline-internal events (EX stage) and retirements
  bit [31:0] last_store_word_addr;
  bit        last_store_valid;
  bit [1:0]  stall_hist;          // stall_d one and two cycles ago

  always @(posedge clk) stall_hist <= {stall_hist[0], dut.u_core.stall_d};

  always @(posedge clk) begin
    if (checking && !reset) begin
      cg_hazard_i.sample();

      // ---- EX stage ----
      if (dut.u_core.id_ex.valid) begin
        automatic ctrl_t c    = dut.u_core.id_ex.ctrl;
        automatic string cons = consumer_name(c);
        automatic bit uses_b  = (dut.u_core.id_ex.rs2 != 5'd0);
        automatic bit uses_a  = (dut.u_core.id_ex.rs1 != 5'd0);

        if (uses_a) cov.hit({"fwd_a.", fwd_name(dut.u_core.fwd_a_e), ".", cons});
        if (uses_b) cov.hit({"fwd_b.", fwd_name(dut.u_core.fwd_b_e), ".", cons});
        if (dut.u_core.fwd_a_e != FWD_NONE && dut.u_core.fwd_b_e != FWD_NONE)
          cov.hit("fwd.a_and_b_same_cycle");
        if (dut.u_core.ex_mem.reg_write && dut.u_core.mem_wb.reg_write &&
            dut.u_core.ex_mem.rd == dut.u_core.mem_wb.rd &&
            (dut.u_core.ex_mem.rd == dut.u_core.id_ex.rs1 ||
             dut.u_core.ex_mem.rd == dut.u_core.id_ex.rs2))
          cov.hit("fwd.priority_mem_over_wb");

        if (c.branch) begin
          automatic instr_e k = decode_kind(dut.u_core.id_ex.instr);
          cov.hit({"branch.", mnemonic(k), dut.u_core.pc_redirect_e ? ".taken" : ".not_taken"});
          if (dut.u_core.pc_redirect_e) begin
            if (dut.u_core.pc_target_e < dut.u_core.id_ex.pc) cov.hit("branch.backward_taken");
            else                                              cov.hit("branch.forward_taken");
          end
        end
        if (c.jal)  cov.hit("jump.JAL");
        if (c.jalr) begin
          cov.hit("jump.JALR");
          if (dut.u_core.target_sum_e[0]) cov.hit("jump.JALR_lsb_cleared");
        end

        if (dut.u_core.pc_redirect_e) begin
          automatic ctrl_t cd = dut.u_core.ctrl_d;
          if (dut.u_core.if_id.valid) cov.hit("flush.squashed_two_valid");
          if (cd.mem_write)           cov.hit("flush.squashed_store");
          if (cd.mem_read)            cov.hit("flush.squashed_load");
          if (cd.branch || cd.jal || cd.jalr) cov.hit("flush.squashed_branch_or_jump");
        end
      end

      // ---- load-use stall (seen from ID) ----
      if (dut.u_core.stall_d) begin
        automatic ctrl_t cd = dut.u_core.ctrl_d;
        if (dut.u_core.id_ex.rd == dut.u_core.rs1_d) cov.hit("stall.load_use_rs1");
        if (dut.u_core.id_ex.rd == dut.u_core.rs2_d) cov.hit("stall.load_use_rs2");
        if (cd.branch)   cov.hit("stall.dependent_is_branch");
        if (cd.mem_read) cov.hit("stall.dependent_is_load");
        if (cd.mem_write && dut.u_core.id_ex.rd == dut.u_core.rs2_d)
          cov.hit("stall.dependent_is_store_data");
      end
      // the stalled instruction then picks the load data up from MEM/WB
      if (dut.u_core.id_ex.valid && stall_hist[1] &&
          (dut.u_core.fwd_a_e == FWD_WB || dut.u_core.fwd_b_e == FWD_WB))
        cov.hit("stall.then_wb_forward");

      // ---- WB writes a register that ID reads in the same cycle ----
      if (dut.u_core.mem_wb.reg_write && dut.u_core.if_id.valid &&
          (dut.u_core.mem_wb.rd == dut.u_core.rs1_d || dut.u_core.mem_wb.rd == dut.u_core.rs2_d))
        cov.hit("reg.wb_to_id_same_cycle_bypass");

      // ---- retirement ----
      if (ret_valid) begin
        automatic instr_e k   = ret_kind;
        automatic int     off = ret_mem_addr[1:0];
        cg_retire_i.sample();
        cov.hit({"instr.", mnemonic(k)});
        if (!ret_rd_we && ret_instr[11:7] == 5'd0 &&
            (ret_instr[6:0] inside {OP_IMM, OP_REG, OP_LUI, OP_AUIPC, OP_LOAD, OP_JAL, OP_JALR}))
          cov.hit("reg.write_to_x0_discarded");
        case (k)
          I_SB: cov.hit($sformatf("mem.SB_off%0d", off));
          I_SH: cov.hit($sformatf("mem.SH_off%0d", off & 2));
          I_SW: cov.hit("mem.SW");
          default: ;
        endcase
        if (k inside {I_SB, I_SH, I_SW}) begin
          last_store_word_addr = {ret_mem_addr[31:2], 2'b00};
          last_store_valid     = 1'b1;
        end
      end

      // ---- loads, sampled in MEM where the address is visible ----
      if (dut.u_core.ex_mem.valid && dut.u_core.ex_mem.mem_read) begin
        automatic int     off = dut.u_core.ex_mem.result[1:0];
        automatic instr_e k   = decode_kind(dut.u_core.ex_mem.instr);
        case (k)
          I_LB:  cov.hit($sformatf("mem.LB_off%0d", off));
          I_LBU: cov.hit($sformatf("mem.LBU_off%0d", off));
          I_LH:  cov.hit($sformatf("mem.LH_off%0d", off & 2));
          I_LHU: cov.hit($sformatf("mem.LHU_off%0d", off & 2));
          default: cov.hit("mem.LW");
        endcase
        if ((k == I_LB || k == I_LH) && dut.u_core.load_data_m[31])
          cov.hit("mem.load_sign_extended_negative");
        if (last_store_valid &&
            {dut.u_core.ex_mem.result[31:2], 2'b00} == last_store_word_addr)
          cov.hit("mem.store_then_load_same_word");
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Scoreboard: compare every retirement against the reference model
  // ---------------------------------------------------------------------------
  function automatic void mismatch(string what, bit [31:0] exp, bit [31:0] got, retire_t e);
    errors++;
    test_errors++;
    if (test_errors <= 10)
      $display("  [MISMATCH] t=%0t pc=%08h instr=%08h (%s): %s expected %08h, got %08h",
               $time, e.pc, e.instr, mnemonic(decode_kind(e.instr)), what, exp, got);
  endfunction

  always @(posedge clk) begin
    if (checking && !reset && !halted) begin
      test_cycles++;
      if (ret_valid) begin
        automatic retire_t e = model.step();
        test_retired++;
        idle_cycles = 0;

        if (verbose)
          $display("  ret pc=%08h instr=%08h %-7s rd=x%0d<=%08h we=%0b mem[%08h]<=%08h strb=%04b",
                   ret_pc, ret_instr, mnemonic(ret_kind), ret_rd, ret_rd_wdata, ret_rd_we,
                   ret_mem_addr, ret_mem_wdata, ret_mem_wstrb);

        if (ret_pc !== e.pc)                 mismatch("PC", e.pc, ret_pc, e);
        if (ret_instr !== e.instr)           mismatch("instruction", e.instr, ret_instr, e);
        if (ret_rd_we !== e.rd_we)           mismatch("rd write enable", {31'b0, e.rd_we}, {31'b0, ret_rd_we}, e);
        if (e.rd_we) begin
          if (ret_rd !== e.rd)               mismatch("rd", {27'b0, e.rd}, {27'b0, ret_rd}, e);
          if (ret_rd_wdata !== e.rd_wdata)   mismatch("rd data", e.rd_wdata, ret_rd_wdata, e);
        end
        if (ret_mem_wstrb !== e.mem_wstrb)   mismatch("store strobe", {28'b0, e.mem_wstrb}, {28'b0, ret_mem_wstrb}, e);
        if (e.mem_wstrb != 4'b0) begin
          if (ret_mem_addr[31:2] !== e.mem_addr[31:2])
            mismatch("store address", e.mem_addr, ret_mem_addr, e);
          for (int b = 0; b < 4; b++)
            if (e.mem_wstrb[b] && ret_mem_wdata[8*b +: 8] !== e.mem_wdata[8*b +: 8])
              mismatch($sformatf("store data byte %0d", b), e.mem_wdata, ret_mem_wdata, e);
        end

        if (ret_instr === HALT) halted = 1'b1;
      end else begin
        idle_cycles++;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Program runner
  // ---------------------------------------------------------------------------
  task automatic run_program(input string name, input bit [31:0] prog[$],
                             input int unsigned mem_seed);
    int unsigned max_cycles;
    bit [31:0]   v;

    if (prog.size() > IMEM_WORDS) $fatal(1, "program '%s' does not fit in IMEM", name);

    // ---- hold reset and load memories through the back door ----
    checking = 1'b0;
    @(negedge clk);
    reset = 1'b1;

    model.reset();
    for (int i = 0; i < IMEM_WORDS; i++) begin
      v = (i < prog.size()) ? prog[i] : HALT;
      dut.u_imem.mem[i] = v;
      model.imem[i]     = v;
    end
    void'($urandom(mem_seed));
    for (int i = 0; i < DMEM_WORDS; i++) begin
      v = $urandom();
      dut.u_dmem.mem[i] = v;
      model.dmem[i]     = v;
    end
    for (int i = 1; i < 32; i++) dut.u_core.u_regfile.regs[i] = 32'h0;

    halted           = 1'b0;
    test_errors      = 0;
    test_cycles      = 0;
    test_retired     = 0;
    idle_cycles      = 0;
    last_store_valid = 1'b0;

    repeat (3) @(negedge clk);
    reset    = 1'b0;
    checking = 1'b1;

    // ---- run until HALT retires ----
    max_cycles = 64 * prog.size() + 2000;
    while (!halted) begin
      @(negedge clk);
      if (test_cycles > max_cycles) begin
        $display("  [ERROR] %s: timeout after %0d cycles (pc=%08h)", name, test_cycles, dut.u_core.pc_f);
        errors++; test_errors++;
        break;
      end
      if (idle_cycles > 8) begin
        $display("  [ERROR] %s: nothing retired for %0d cycles — pipeline is stuck", name, idle_cycles);
        errors++; test_errors++;
        break;
      end
    end
    checking = 1'b0;

    // ---- final architectural state ----
    for (int i = 1; i < 32; i++) begin
      if (dut.u_core.u_regfile.regs[i] !== model.x[i]) begin
        errors++; test_errors++;
        $display("  [MISMATCH] %s: final x%0d expected %08h, got %08h",
                 name, i, model.x[i], dut.u_core.u_regfile.regs[i]);
      end
    end
    for (int i = 0; i < DMEM_WORDS; i++) begin
      if (dut.u_dmem.mem[i] !== model.dmem[i]) begin
        errors++; test_errors++;
        if (test_errors <= 20)
          $display("  [MISMATCH] %s: final dmem[%0d] expected %08h, got %08h",
                   name, i, model.dmem[i], dut.u_dmem.mem[i]);
      end
    end

    tests_run++;
    total_cycles  += test_cycles;
    total_retired += test_retired;
    if (test_errors != 0) tests_failed++;
    $display("[%s] %-22s %5d words  %6d instrs  %6d cycles  CPI %.3f  errors %0d",
             test_errors == 0 ? "PASS" : "FAIL", name, prog.size(),
             test_retired, test_cycles, real'(test_cycles) / real'(test_retired), test_errors);
  endtask

  // ---------------------------------------------------------------------------
  // Directed program — expected values worked out by hand
  // ---------------------------------------------------------------------------
  function automatic void expect_reg(int r, bit [31:0] exp);
    if (dut.u_core.u_regfile.regs[r] !== exp) begin
      errors++;
      $display("  [MISMATCH] directed: x%0d expected %08h, got %08h",
               r, exp, dut.u_core.u_regfile.regs[r]);
    end
  endfunction

  task automatic run_directed();
    bit [31:0] p[$];
    int unsigned err_before = errors;

    // -- arithmetic with back-to-back dependencies (EX/MEM + MEM/WB forwarding)
    p.push_back(rv32i_asm::addi(1, 0, 5));           //  0: x1 = 5
    p.push_back(rv32i_asm::addi(2, 1, 7));           //  4: x2 = 12       (fwd MEM)
    p.push_back(rv32i_asm::add (3, 1, 2));           //  8: x3 = 17       (fwd WB + MEM)
    p.push_back(rv32i_asm::sub (4, 3, 1));           //  c: x4 = 12
    p.push_back(rv32i_asm::slli(5, 4, 4));           // 10: x5 = 192
    p.push_back(rv32i_asm::xor_(6, 5, 3));           // 14: x6 = 192 ^ 17 = 209
    p.push_back(rv32i_asm::addi(0, 6, 1));           // 18: write to x0 is discarded
    p.push_back(rv32i_asm::add (7, 0, 0));           // 1c: x7 = 0
    // -- loop: sum 1..10 (backward branch taken 9 times, then falls through)
    p.push_back(rv32i_asm::addi(10, 0, 0));          // 20: sum = 0
    p.push_back(rv32i_asm::addi(11, 0, 10));         // 24: i = 10
    p.push_back(rv32i_asm::add (10, 10, 11));        // 28: sum += i
    p.push_back(rv32i_asm::addi(11, 11, -1));        // 2c: i--
    p.push_back(rv32i_asm::bne (11, 0, -8));         // 30: loop while i != 0
    // -- memory: store, load-use stall, sub-word access
    p.push_back(rv32i_asm::sw  (10, 0, 64));         // 34: mem[64] = 55
    p.push_back(rv32i_asm::lw  (12, 0, 64));         // 38: x12 = 55
    p.push_back(rv32i_asm::addi(13, 12, 1));         // 3c: x13 = 56      (load-use stall)
    p.push_back(rv32i_asm::lui (14, 20'hDEADC));     // 40
    p.push_back(rv32i_asm::addi(14, 14, -273));      // 44: x14 = 0xDEADBEEF
    p.push_back(rv32i_asm::sw  (14, 0, 68));         // 48: mem[68] = 0xDEADBEEF
    p.push_back(rv32i_asm::lb  (15, 0, 68));         // 4c: x15 = 0xFFFFFFEF
    p.push_back(rv32i_asm::lbu (16, 0, 71));         // 50: x16 = 0x000000DE
    p.push_back(rv32i_asm::lh  (17, 0, 70));         // 54: x17 = 0xFFFFDEAD
    p.push_back(rv32i_asm::lhu (18, 0, 68));         // 58: x18 = 0x0000BEEF
    p.push_back(rv32i_asm::sb  (1, 0, 69));          // 5c: mem[69] = 0x05
    p.push_back(rv32i_asm::lw  (19, 0, 68));         // 60: x19 = 0xDEAD05EF
    // -- call / return through JAL + JALR
    p.push_back(rv32i_asm::jal (1, 12));             // 64: call 0x70, x1 = 0x68
    p.push_back(rv32i_asm::addi(20, 20, 100));       // 68: x20 = 7 + 100 = 107 (after return)
    p.push_back(rv32i_asm::jal (0, 12));             // 6c: skip the function body -> 0x78
    p.push_back(rv32i_asm::addi(20, 0, 7));          // 70: function: x20 = 7
    p.push_back(rv32i_asm::jalr(0, 1, 0));           // 74: return
    // -- comparisons and signed/unsigned branches
    p.push_back(rv32i_asm::addi(21, 0, -1));         // 78: x21 = -1
    p.push_back(rv32i_asm::slt (22, 21, 0));         // 7c: x22 = 1  (-1 < 0 signed)
    p.push_back(rv32i_asm::sltu(23, 21, 0));         // 80: x23 = 0  (0xFFFFFFFF < 0 unsigned)
    p.push_back(rv32i_asm::srai(24, 21, 4));         // 84: x24 = -1
    p.push_back(rv32i_asm::srli(25, 21, 28));        // 88: x25 = 0xF
    p.push_back(rv32i_asm::bltu(21, 0, 8));          // 8c: not taken
    p.push_back(rv32i_asm::addi(26, 0, 1));          // 90: x26 = 1
    p.push_back(rv32i_asm::blt (21, 0, 8));          // 94: taken -> 0x9c
    p.push_back(rv32i_asm::addi(26, 0, 99));         // 98: squashed
    p.push_back(rv32i_asm::auipc(27, 20'h1));        // 9c: x27 = 0x9c + 0x1000
    // -- JALR whose base register is forwarded from MEM/WB
    p.push_back(rv32i_asm::auipc(28, 20'h0));        // a0: x28 = 0xa0
    p.push_back(rv32i_asm::addi(29, 0, 1));          // a4: x29 = 1
    p.push_back(rv32i_asm::jalr(30, 28, 12));        // a8: jump to 0xac, x30 = 0xac
    p.push_back(HALT);                               // ac

    run_program("directed", p, 32'hD1EC7ED);

    expect_reg( 1, 32'h0000_0068);
    expect_reg( 2, 32'd12);
    expect_reg( 3, 32'd17);
    expect_reg( 4, 32'd12);
    expect_reg( 5, 32'd192);
    expect_reg( 6, 32'd209);
    expect_reg( 7, 32'd0);
    expect_reg(10, 32'd55);
    expect_reg(11, 32'd0);
    expect_reg(12, 32'd55);
    expect_reg(13, 32'd56);
    expect_reg(14, 32'hDEAD_BEEF);
    expect_reg(15, 32'hFFFF_FFEF);
    expect_reg(16, 32'h0000_00DE);
    expect_reg(17, 32'hFFFF_DEAD);
    expect_reg(18, 32'h0000_BEEF);
    expect_reg(19, 32'hDEAD_05EF);
    expect_reg(20, 32'd107);
    expect_reg(21, 32'hFFFF_FFFF);
    expect_reg(22, 32'd1);
    expect_reg(23, 32'd0);
    expect_reg(24, 32'hFFFF_FFFF);
    expect_reg(25, 32'h0000_000F);
    expect_reg(26, 32'd1);
    expect_reg(27, 32'h0000_109C);
    expect_reg(28, 32'h0000_00A0);
    expect_reg(29, 32'd1);
    expect_reg(30, 32'h0000_00AC);
    if (dut.u_dmem.mem[16] !== 32'd55) begin
      errors++;
      $display("  [MISMATCH] directed: mem[64] expected 55, got %08h", dut.u_dmem.mem[16]);
    end
    if (errors != err_before && tests_failed == 0) tests_failed++;
  endtask

  // ---------------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------------
  initial begin
    rv32i_rand_program prog;
    string             prof_name;

    if (!$value$plusargs("SEED=%d", seed))       seed    = 1;
    if (!$value$plusargs("NTESTS=%d", ntests))   ntests  = 20;
    if (!$value$plusargs("MIN_LEN=%d", min_len)) min_len = 200;
    if (!$value$plusargs("MAX_LEN=%d", max_len)) max_len = 400;
    verbose = $test$plusargs("VERBOSE");
    cov_all = $test$plusargs("COV_ALL");
    if ($test$plusargs("WAVES")) begin
      $dumpfile("tb_rv32i.vcd");
      $dumpvars(0, tb_rv32i);
    end

    model = new(IMEM_WORDS, DMEM_WORDS);
    cov   = new();
    define_coverage();

    $display("=====================================================================");
    $display(" RV32I 5-stage pipeline testbench   seed=%0d  random tests=%0d", seed, ntests);
    $display("=====================================================================");

    run_directed();

    for (int unsigned t = 0; t < ntests; t++) begin
      prog = new();
      prog.srandom(seed * 1000 + t);
      case (t % 4)                      // rotate through the stimulus profiles
        0:       begin prog.profile = PROF_BALANCED; prof_name = "balanced"; end
        1:       begin prog.profile = PROF_HAZARD;   prof_name = "hazard";   end
        2:       begin prog.profile = PROF_BRANCH;   prof_name = "branch";   end
        default: begin prog.profile = PROF_MEMORY;   prof_name = "memory";   end
      endcase
      prog.min_items = min_len;
      prog.max_items = max_len;
      if (!prog.randomize()) $fatal(1, "randomize(program) failed");
      prog.build();
      run_program($sformatf("random_%0d_%s", t, prof_name), prog.words, seed * 1000 + t);
    end

    $display("=====================================================================");
    cov.report(cov_all);
    $display(" tests: %0d run, %0d failed    instructions: %0d    cycles: %0d    CPI: %.3f",
             tests_run, tests_failed, total_retired, total_cycles,
             real'(total_cycles) / real'(total_retired));
    if (errors == 0) $display(" RESULT: PASS");
    else             $display(" RESULT: FAIL  (%0d mismatches)", errors);
    $display("=====================================================================");
    $finish;
  end

endmodule
