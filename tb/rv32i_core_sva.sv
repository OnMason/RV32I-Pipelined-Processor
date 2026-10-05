// -----------------------------------------------------------------------------
// rv32i_core_sva — SystemVerilog assertions for the pipeline control logic
//
// Bound into rv32i_core (see the bind statement at the bottom), so the RTL
// itself carries no verification code. Groups:
//
//   1. PC sequencing
//   2. Stall behaviour (load-use)
//   3. Flush behaviour (taken branch / jump)
//   4. Forwarding select and data correctness
//   5. Bubbles have no side effects, x0 is never written
//   6. No instruction is dropped or duplicated between stages
// -----------------------------------------------------------------------------
module rv32i_core_sva
  import rv32i_pkg::*;
(
  input logic        clk,
  input logic        reset,

  // hazard control
  input logic        stall_f,
  input logic        stall_d,
  input logic        flush_d,
  input logic        flush_e,

  // IF
  input logic [31:0] pc_f,

  // IF/ID + decode outputs
  input logic        if_id_valid,
  input logic [31:0] if_id_pc,
  input logic [31:0] if_id_instr,
  input logic [4:0]  rs1_d,
  input logic [4:0]  rs2_d,
  input logic        illegal_d,

  // ID/EX + EX results
  input logic        id_ex_valid,
  input logic [31:0] id_ex_pc,
  input ctrl_t       id_ex_ctrl,
  input logic [4:0]  id_ex_rs1,
  input logic [4:0]  id_ex_rs2,
  input logic [4:0]  id_ex_rd,
  input logic [31:0] id_ex_rs1_data,
  input logic [31:0] id_ex_rs2_data,
  input fwd_sel_e    fwd_a_e,
  input fwd_sel_e    fwd_b_e,
  input logic [31:0] rs1_fwd_e,
  input logic [31:0] rs2_fwd_e,
  input logic        pc_redirect_e,
  input logic [31:0] pc_target_e,

  // EX/MEM
  input logic        ex_mem_valid,
  input logic [31:0] ex_mem_pc,
  input logic        ex_mem_reg_write,
  input logic        ex_mem_mem_read,
  input logic        ex_mem_mem_write,
  input logic [4:0]  ex_mem_rd,
  input logic [31:0] ex_mem_result,
  input logic [3:0]  dmem_wstrb,

  // MEM/WB
  input logic        mem_wb_valid,
  input logic [31:0] mem_wb_pc,
  input logic        mem_wb_reg_write,
  input logic [4:0]  mem_wb_rd,
  input logic [31:0] mem_wb_wdata
);

  // Producer/consumer matches, written out independently of the forward unit
  logic m_hits_rs1, m_hits_rs2, w_hits_rs1, w_hits_rs2;
  assign m_hits_rs1 = ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1);
  assign m_hits_rs2 = ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2);
  assign w_hits_rs1 = mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1);
  assign w_hits_rs2 = mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2);

  logic load_use_d;
  assign load_use_d = id_ex_ctrl.mem_read && (id_ex_rd != 5'd0) &&
                      ((id_ex_rd == rs1_d) || (id_ex_rd == rs2_d));

  // ---------------------------------------------------------------------------
  // 1. PC sequencing: +4, hold on stall, or jump to the resolved target
  // ---------------------------------------------------------------------------
  a_pc_plus4: assert property (@(posedge clk) disable iff (reset)
      !stall_f && !pc_redirect_e |=> pc_f == $past(pc_f) + 32'd4)
    else $error("SVA a_pc_plus4: PC did not advance by 4");

  a_pc_hold_on_stall: assert property (@(posedge clk) disable iff (reset)
      stall_f && !pc_redirect_e |=> pc_f == $past(pc_f))
    else $error("SVA a_pc_hold_on_stall: PC moved during a stall");

  a_pc_redirect: assert property (@(posedge clk) disable iff (reset)
      pc_redirect_e |=> pc_f == $past(pc_target_e))
    else $error("SVA a_pc_redirect: PC did not take the branch/jump target");

  a_jump_target_aligned: assert property (@(posedge clk) disable iff (reset)
      pc_redirect_e |-> pc_target_e[0] == 1'b0)
    else $error("SVA a_jump_target_aligned: target has bit 0 set");

  // ---------------------------------------------------------------------------
  // 2. Load-use stall
  // ---------------------------------------------------------------------------
  // A dependent instruction right behind a load must stall the front end...
  a_load_use_stalls: assert property (@(posedge clk) disable iff (reset)
      load_use_d |-> stall_f && stall_d && flush_e)
    else $error("SVA a_load_use_stalls: load-use hazard did not stall");

  // ...and nothing else may stall it.
  a_stall_only_on_load_use: assert property (@(posedge clk) disable iff (reset)
      stall_f || stall_d |-> load_use_d)
    else $error("SVA a_stall_only_on_load_use: stall without a load-use hazard");

  a_stall_holds_if_id: assert property (
      @(posedge clk) disable iff (reset)
      stall_d && !flush_d |=>
        if_id_valid == $past(if_id_valid) && if_id_pc == $past(if_id_pc) &&
        if_id_instr == $past(if_id_instr))
    else $error("SVA a_stall_holds_if_id: IF/ID changed during a stall");

  a_stall_inserts_bubble: assert property (@(posedge clk) disable iff (reset)
      flush_e |=> !id_ex_valid)
    else $error("SVA a_stall_inserts_bubble: ID/EX not squashed");

  // One bubble is always enough: the load has reached MEM/WB a cycle later.
  a_stall_one_cycle: assert property (@(posedge clk) disable iff (reset)
      stall_f |=> !stall_f)
    else $error("SVA a_stall_one_cycle: stall lasted more than one cycle");

  // The case forwarding cannot fix must never reach EX: a load still in MEM
  // feeding the instruction in EX.
  a_no_forward_from_load_in_mem: assert property (
      @(posedge clk) disable iff (reset)
      !(ex_mem_mem_read && ex_mem_rd != 5'd0 &&
        (ex_mem_rd == id_ex_rs1 || ex_mem_rd == id_ex_rs2)))
    else $error("SVA a_no_forward_from_load_in_mem: EX consumed a load address as data");

  // ---------------------------------------------------------------------------
  // 3. Control-hazard flush
  // ---------------------------------------------------------------------------
  a_redirect_only_from_control: assert property (
      @(posedge clk) disable iff (reset)
      pc_redirect_e |-> id_ex_valid &&
                        (id_ex_ctrl.branch || id_ex_ctrl.jal || id_ex_ctrl.jalr))
    else $error("SVA a_redirect_only_from_control: redirect without a branch/jump in EX");

  a_redirect_flushes: assert property (@(posedge clk) disable iff (reset)
      pc_redirect_e |-> flush_d && flush_e)
    else $error("SVA a_redirect_flushes: taken branch/jump did not flush");

  // Both wrong-path instructions are gone the cycle after the redirect...
  a_redirect_squashes_two: assert property (@(posedge clk) disable iff (reset)
      pc_redirect_e |=> !if_id_valid && !id_ex_valid)
    else $error("SVA a_redirect_squashes_two: wrong-path instruction survived");

  // ...and the first instruction to reach ID afterwards is the target.
  a_target_is_next_fetched: assert property (
      @(posedge clk) disable iff (reset)
      pc_redirect_e |=> ##1 if_id_valid && if_id_pc == $past(pc_target_e, 2))
    else $error("SVA a_target_is_next_fetched: wrong instruction after redirect");

  // EX holds either a load (stall source) or a branch/jump (flush source), never both.
  a_stall_flush_exclusive: assert property (@(posedge clk) disable iff (reset)
      !(stall_f && pc_redirect_e))
    else $error("SVA a_stall_flush_exclusive: stall and redirect in the same cycle");

  // ---------------------------------------------------------------------------
  // 4. Forwarding
  // ---------------------------------------------------------------------------
  // Youngest producer wins.
  a_fwd_a_mem: assert property (@(posedge clk) disable iff (reset)
      m_hits_rs1 |-> fwd_a_e == FWD_MEM)
    else $error("SVA a_fwd_a_mem: rs1 not forwarded from EX/MEM");
  a_fwd_a_wb: assert property (@(posedge clk) disable iff (reset)
      !m_hits_rs1 && w_hits_rs1 |-> fwd_a_e == FWD_WB)
    else $error("SVA a_fwd_a_wb: rs1 not forwarded from MEM/WB");
  a_fwd_a_none: assert property (@(posedge clk) disable iff (reset)
      !m_hits_rs1 && !w_hits_rs1 |-> fwd_a_e == FWD_NONE)
    else $error("SVA a_fwd_a_none: rs1 forwarded with no matching producer");

  a_fwd_b_mem: assert property (@(posedge clk) disable iff (reset)
      m_hits_rs2 |-> fwd_b_e == FWD_MEM)
    else $error("SVA a_fwd_b_mem: rs2 not forwarded from EX/MEM");
  a_fwd_b_wb: assert property (@(posedge clk) disable iff (reset)
      !m_hits_rs2 && w_hits_rs2 |-> fwd_b_e == FWD_WB)
    else $error("SVA a_fwd_b_wb: rs2 not forwarded from MEM/WB");
  a_fwd_b_none: assert property (@(posedge clk) disable iff (reset)
      !m_hits_rs2 && !w_hits_rs2 |-> fwd_b_e == FWD_NONE)
    else $error("SVA a_fwd_b_none: rs2 forwarded with no matching producer");

  // The operand EX actually uses is the freshest copy of the register.
  a_fwd_a_data: assert property (
      @(posedge clk) disable iff (reset)
      rs1_fwd_e == (m_hits_rs1 ? ex_mem_result :
                    w_hits_rs1 ? mem_wb_wdata  : id_ex_rs1_data))
    else $error("SVA a_fwd_a_data: stale rs1 operand in EX");
  a_fwd_b_data: assert property (
      @(posedge clk) disable iff (reset)
      rs2_fwd_e == (m_hits_rs2 ? ex_mem_result :
                    w_hits_rs2 ? mem_wb_wdata  : id_ex_rs2_data))
    else $error("SVA a_fwd_b_data: stale rs2 operand in EX");

  // x0 is never a forwarding source and always reads as zero.
  a_x0_reads_zero_a: assert property (@(posedge clk) disable iff (reset)
      id_ex_rs1 == 5'd0 |-> rs1_fwd_e == 32'h0)
    else $error("SVA a_x0_reads_zero_a: x0 operand is not zero");
  a_x0_reads_zero_b: assert property (@(posedge clk) disable iff (reset)
      id_ex_rs2 == 5'd0 |-> rs2_fwd_e == 32'h0)
    else $error("SVA a_x0_reads_zero_b: x0 operand is not zero");

  // ---------------------------------------------------------------------------
  // 5. Bubbles are harmless; x0 is never written
  // ---------------------------------------------------------------------------
  a_bubble_ex_inert: assert property (
      @(posedge clk) disable iff (reset)
      !id_ex_valid |-> !(id_ex_ctrl.reg_write || id_ex_ctrl.mem_read || id_ex_ctrl.mem_write ||
                         id_ex_ctrl.branch || id_ex_ctrl.jal || id_ex_ctrl.jalr))
    else $error("SVA a_bubble_ex_inert: bubble in EX has active control");

  a_bubble_mem_inert: assert property (
      @(posedge clk) disable iff (reset)
      !ex_mem_valid |-> !(ex_mem_reg_write || ex_mem_mem_read || ex_mem_mem_write) &&
                        dmem_wstrb == 4'b0000)
    else $error("SVA a_bubble_mem_inert: bubble in MEM has active control");

  a_bubble_wb_inert: assert property (@(posedge clk) disable iff (reset)
      !mem_wb_valid |-> !mem_wb_reg_write)
    else $error("SVA a_bubble_wb_inert: bubble in WB writes a register");

  a_no_x0_write: assert property (
      @(posedge clk) disable iff (reset)
      !(id_ex_ctrl.reg_write && id_ex_rd  == 5'd0) &&
      !(ex_mem_reg_write     && ex_mem_rd == 5'd0) &&
      !(mem_wb_reg_write     && mem_wb_rd == 5'd0))
    else $error("SVA a_no_x0_write: write enable asserted for x0");

  a_store_only_when_write: assert property (@(posedge clk) disable iff (reset)
      dmem_wstrb != 4'b0000 |-> ex_mem_mem_write)
    else $error("SVA a_store_only_when_write: memory strobe without a store");

  a_load_xor_store: assert property (@(posedge clk) disable iff (reset)
      !(ex_mem_mem_read && ex_mem_mem_write))
    else $error("SVA a_load_xor_store: instruction is both load and store");

  // ---------------------------------------------------------------------------
  // 6. Instructions move through the back end without being dropped
  // ---------------------------------------------------------------------------
  a_id_to_ex: assert property (
      @(posedge clk) disable iff (reset)
      if_id_valid && !flush_e |=> id_ex_valid && id_ex_pc == $past(if_id_pc))
    else $error("SVA a_id_to_ex: instruction lost between ID and EX");

  a_ex_to_mem: assert property (
      @(posedge clk) disable iff (reset)
      id_ex_valid |=> ex_mem_valid && ex_mem_pc == $past(id_ex_pc))
    else $error("SVA a_ex_to_mem: instruction lost between EX and MEM");

  a_mem_to_wb: assert property (
      @(posedge clk) disable iff (reset)
      ex_mem_valid |=> mem_wb_valid && mem_wb_pc == $past(ex_mem_pc))
    else $error("SVA a_mem_to_wb: instruction lost between MEM and WB");

  // Stimulus sanity: the testbench only generates legal RV32I.
  a_legal_instr: assert property (@(posedge clk) disable iff (reset)
      if_id_valid |-> !illegal_d)
    else $error("SVA a_legal_instr: illegal instruction reached decode: %h", if_id_instr);

  // ---------------------------------------------------------------------------
  // Cover points: prove the interesting scenarios actually happened
  // ---------------------------------------------------------------------------
  c_fwd_a_mem:       cover property (@(posedge clk) disable iff (reset) id_ex_valid && fwd_a_e == FWD_MEM);
  c_fwd_a_wb:        cover property (@(posedge clk) disable iff (reset) id_ex_valid && fwd_a_e == FWD_WB);
  c_fwd_b_mem:       cover property (@(posedge clk) disable iff (reset) id_ex_valid && fwd_b_e == FWD_MEM);
  c_fwd_b_wb:        cover property (@(posedge clk) disable iff (reset) id_ex_valid && fwd_b_e == FWD_WB);
  c_fwd_both_mem:    cover property (@(posedge clk) disable iff (reset) fwd_a_e == FWD_MEM && fwd_b_e == FWD_MEM);
  c_fwd_mem_and_wb:  cover property (@(posedge clk) disable iff (reset) fwd_a_e == FWD_MEM && fwd_b_e == FWD_WB);
  c_fwd_priority:    cover property (@(posedge clk) disable iff (reset) m_hits_rs1 && w_hits_rs1);   // both match, MEM must win
  c_load_use_stall:  cover property (@(posedge clk) disable iff (reset) stall_f);
  c_branch_taken:    cover property (@(posedge clk) disable iff (reset) pc_redirect_e && id_ex_ctrl.branch);
  c_branch_untaken:  cover property (@(posedge clk) disable iff (reset) id_ex_valid && id_ex_ctrl.branch && !pc_redirect_e);
  c_jump:            cover property (@(posedge clk) disable iff (reset) pc_redirect_e && (id_ex_ctrl.jal || id_ex_ctrl.jalr));
  c_stall_then_redirect: cover property (@(posedge clk) disable iff (reset) stall_f ##2 pc_redirect_e);  // load -> dependent branch
  c_redirect_squashes_two: cover property (@(posedge clk) disable iff (reset) pc_redirect_e && if_id_valid && id_ex_valid);
  c_back_to_back_stalls:  cover property (@(posedge clk) disable iff (reset) stall_f ##2 stall_f);

endmodule

// Attach the checker to every instance of the core.
bind rv32i_core rv32i_core_sva u_sva (
  .clk              (clk),
  .reset            (reset),
  .stall_f          (stall_f),
  .stall_d          (stall_d),
  .flush_d          (flush_d),
  .flush_e          (flush_e),
  .pc_f             (pc_f),
  .if_id_valid      (if_id.valid),
  .if_id_pc         (if_id.pc),
  .if_id_instr      (if_id.instr),
  .rs1_d            (rs1_d),
  .rs2_d            (rs2_d),
  .illegal_d        (illegal_d),
  .id_ex_valid      (id_ex.valid),
  .id_ex_pc         (id_ex.pc),
  .id_ex_ctrl       (id_ex.ctrl),
  .id_ex_rs1        (id_ex.rs1),
  .id_ex_rs2        (id_ex.rs2),
  .id_ex_rd         (id_ex.rd),
  .id_ex_rs1_data   (id_ex.rs1_data),
  .id_ex_rs2_data   (id_ex.rs2_data),
  .fwd_a_e          (fwd_a_e),
  .fwd_b_e          (fwd_b_e),
  .rs1_fwd_e        (rs1_fwd_e),
  .rs2_fwd_e        (rs2_fwd_e),
  .pc_redirect_e    (pc_redirect_e),
  .pc_target_e      (pc_target_e),
  .ex_mem_valid     (ex_mem.valid),
  .ex_mem_pc        (ex_mem.pc),
  .ex_mem_reg_write (ex_mem.reg_write),
  .ex_mem_mem_read  (ex_mem.mem_read),
  .ex_mem_mem_write (ex_mem.mem_write),
  .ex_mem_rd        (ex_mem.rd),
  .ex_mem_result    (ex_mem.result),
  .dmem_wstrb       (dmem_wstrb),
  .mem_wb_valid     (mem_wb.valid),
  .mem_wb_pc        (mem_wb.pc),
  .mem_wb_reg_write (mem_wb.reg_write),
  .mem_wb_rd        (mem_wb.rd),
  .mem_wb_wdata     (mem_wb.wdata)
);
