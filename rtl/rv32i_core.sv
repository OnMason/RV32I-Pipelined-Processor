// -----------------------------------------------------------------------------
// rv32i_core — 5-stage pipelined RV32I processor core
//
//   IF  ->  ID  ->  EX  ->  MEM  ->  WB
//
//   * Full RV32I base integer ISA (37 user instructions; FENCE/ECALL/EBREAK
//     execute as NOPs — no CSRs or traps).
//   * Data hazards: forwarding from EX/MEM and MEM/WB into EX, write-first
//     register file, one-cycle stall for load-use.
//   * Control hazards: branches/jumps resolve in EX, predict not-taken,
//     2-cycle flush on redirect.
//   * Harvard memory interface with combinational read (see rv32i_top).
//
// Signal suffix = the stage a signal belongs to: _f _d _e _m _w.
// -----------------------------------------------------------------------------
module rv32i_core
  import rv32i_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
  input  logic        clk,
  input  logic        reset,          // synchronous, active high

  // Instruction memory (combinational read)
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // Data memory (combinational read, synchronous byte-strobed write)
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wstrb,
  input  logic [31:0] dmem_rdata,

  // Retirement trace: one entry per instruction leaving WB (for verification)
  output logic        ret_valid,
  output logic [31:0] ret_pc,
  output logic [31:0] ret_instr,
  output logic        ret_rd_we,
  output logic [4:0]  ret_rd,
  output logic [31:0] ret_rd_wdata,
  output logic [3:0]  ret_mem_wstrb,
  output logic [31:0] ret_mem_addr,
  output logic [31:0] ret_mem_wdata
);

  // ---------------------------------------------------------------------------
  // Pipeline registers
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
  } if_id_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    ctrl_t       ctrl;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] imm;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic [2:0]  funct3;
    logic [31:0] result;      // ALU result, link address, or memory address
    logic [31:0] store_data;  // rs2 (after forwarding)
    logic [4:0]  rd;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic        reg_write;
    logic [4:0]  rd;
    logic [31:0] wdata;       // value written to rd
    logic [3:0]  mem_wstrb;   // trace only
    logic [31:0] mem_addr;    // trace only
    logic [31:0] mem_wdata;   // trace only
  } mem_wb_t;

  if_id_t  if_id;
  id_ex_t  id_ex;
  ex_mem_t ex_mem;
  mem_wb_t mem_wb;

  // Hazard control
  logic stall_f, stall_d, flush_d, flush_e;

  // ---------------------------------------------------------------------------
  // IF — instruction fetch
  // ---------------------------------------------------------------------------
  logic [31:0] pc_f, pc_next;
  logic        pc_redirect_e;
  logic [31:0] pc_target_e;

  always_comb begin
    if (pc_redirect_e) pc_next = pc_target_e;
    else if (stall_f)  pc_next = pc_f;
    else               pc_next = pc_f + 32'd4;
  end

  always_ff @(posedge clk) begin
    if (reset) pc_f <= RESET_PC;
    else       pc_f <= pc_next;
  end

  assign imem_addr = pc_f;

  always_ff @(posedge clk) begin
    if (reset || flush_d) begin
      if_id       <= '0;
      if_id.instr <= NOP;
    end else if (!stall_d) begin
      if_id.valid <= 1'b1;
      if_id.pc    <= pc_f;
      if_id.instr <= imem_rdata;
    end
  end

  // ---------------------------------------------------------------------------
  // ID — decode and register read
  // ---------------------------------------------------------------------------
  ctrl_t       ctrl_d;
  logic [4:0]  rs1_d, rs2_d, rd_d;
  logic [31:0] rs1_data_d, rs2_data_d, imm_d;
  logic        illegal_d;

  rv32i_decoder u_decoder (
    .instr   (if_id.instr),
    .valid   (if_id.valid),
    .ctrl    (ctrl_d),
    .rs1     (rs1_d),
    .rs2     (rs2_d),
    .rd      (rd_d),
    .illegal (illegal_d)
  );

  rv32i_imm_gen u_imm_gen (
    .instr (if_id.instr),
    .imm   (imm_d)
  );

  rv32i_regfile u_regfile (
    .clk    (clk),
    .we     (mem_wb.reg_write),
    .waddr  (mem_wb.rd),
    .wdata  (mem_wb.wdata),
    .raddr1 (rs1_d),
    .raddr2 (rs2_d),
    .rdata1 (rs1_data_d),
    .rdata2 (rs2_data_d)
  );

  always_ff @(posedge clk) begin
    if (reset || flush_e) begin
      id_ex             <= '0;
      id_ex.instr       <= NOP;
      id_ex.ctrl.alu_op <= ALU_ADD;
    end else begin
      id_ex.valid    <= if_id.valid;
      id_ex.pc       <= if_id.pc;
      id_ex.instr    <= if_id.instr;
      id_ex.ctrl     <= ctrl_d;
      id_ex.rs1_data <= rs1_data_d;
      id_ex.rs2_data <= rs2_data_d;
      id_ex.imm      <= imm_d;
      id_ex.rs1      <= rs1_d;
      id_ex.rs2      <= rs2_d;
      id_ex.rd       <= rd_d;
    end
  end

  // ---------------------------------------------------------------------------
  // EX — forwarding, ALU, branch/jump resolution
  // ---------------------------------------------------------------------------
  fwd_sel_e    fwd_a_e, fwd_b_e;
  logic [31:0] rs1_fwd_e, rs2_fwd_e;
  logic [31:0] alu_a_e, alu_b_e, alu_result_e, result_e;
  logic        branch_taken_e;

  rv32i_forward_unit u_forward (
    .rs1_e       (id_ex.rs1),
    .rs2_e       (id_ex.rs2),
    .reg_write_m (ex_mem.reg_write),
    .rd_m        (ex_mem.rd),
    .reg_write_w (mem_wb.reg_write),
    .rd_w        (mem_wb.rd),
    .fwd_a       (fwd_a_e),
    .fwd_b       (fwd_b_e)
  );

  always_comb begin
    unique case (fwd_a_e)
      FWD_MEM: rs1_fwd_e = ex_mem.result;
      FWD_WB:  rs1_fwd_e = mem_wb.wdata;
      default: rs1_fwd_e = id_ex.rs1_data;
    endcase
    unique case (fwd_b_e)
      FWD_MEM: rs2_fwd_e = ex_mem.result;
      FWD_WB:  rs2_fwd_e = mem_wb.wdata;
      default: rs2_fwd_e = id_ex.rs2_data;
    endcase
  end

  assign alu_a_e = id_ex.ctrl.alu_a_pc  ? id_ex.pc  : rs1_fwd_e;
  assign alu_b_e = id_ex.ctrl.alu_b_imm ? id_ex.imm : rs2_fwd_e;

  rv32i_alu u_alu (
    .a      (alu_a_e),
    .b      (alu_b_e),
    .op     (id_ex.ctrl.alu_op),
    .result (alu_result_e)
  );

  rv32i_branch_cmp u_branch_cmp (
    .a      (rs1_fwd_e),
    .b      (rs2_fwd_e),
    .funct3 (id_ex.ctrl.funct3),
    .taken  (branch_taken_e)
  );

  // Dedicated target adder: PC + imm for branches and JAL, (rs1 + imm) & ~1 for JALR.
  logic [31:0] target_base_e, target_sum_e;
  assign target_base_e = id_ex.ctrl.jalr ? rs1_fwd_e : id_ex.pc;
  assign target_sum_e  = target_base_e + id_ex.imm;
  assign pc_target_e   = id_ex.ctrl.jalr ? {target_sum_e[31:1], 1'b0} : target_sum_e;

  assign pc_redirect_e = id_ex.ctrl.jal || id_ex.ctrl.jalr ||
                         (id_ex.ctrl.branch && branch_taken_e);

  // Jumps write the link address; everything else writes the ALU result.
  assign result_e = (id_ex.ctrl.jal || id_ex.ctrl.jalr) ? id_ex.pc + 32'd4 : alu_result_e;

  always_ff @(posedge clk) begin
    if (reset) begin
      ex_mem       <= '0;
      ex_mem.instr <= NOP;
    end else begin
      ex_mem.valid      <= id_ex.valid;
      ex_mem.pc         <= id_ex.pc;
      ex_mem.instr      <= id_ex.instr;
      ex_mem.reg_write  <= id_ex.ctrl.reg_write;
      ex_mem.mem_read   <= id_ex.ctrl.mem_read;
      ex_mem.mem_write  <= id_ex.ctrl.mem_write;
      ex_mem.funct3     <= id_ex.ctrl.funct3;
      ex_mem.result     <= result_e;
      ex_mem.store_data <= rs2_fwd_e;
      ex_mem.rd         <= id_ex.rd;
    end
  end

  // ---------------------------------------------------------------------------
  // MEM — data memory access
  //
  // Accesses are aligned to their natural size by ignoring the low address
  // bits (no misaligned-access trap): LW/SW use addr[31:2], LH/SH use addr[1],
  // LB/SB use addr[1:0].
  // ---------------------------------------------------------------------------
  logic [1:0]  byte_off_m;
  logic [3:0]  wstrb_m;
  logic [31:0] wdata_m;
  logic [31:0] load_data_m;
  logic [7:0]  load_byte_m;
  logic [15:0] load_half_m;

  assign byte_off_m = ex_mem.result[1:0];

  always_comb begin
    wstrb_m = 4'b0000;
    wdata_m = ex_mem.store_data;
    unique case (ex_mem.funct3[1:0])
      2'b00: begin  // SB
        wstrb_m = 4'b0001 << byte_off_m;
        wdata_m = {4{ex_mem.store_data[7:0]}};
      end
      2'b01: begin  // SH
        wstrb_m = byte_off_m[1] ? 4'b1100 : 4'b0011;
        wdata_m = {2{ex_mem.store_data[15:0]}};
      end
      default: begin  // SW
        wstrb_m = 4'b1111;
        wdata_m = ex_mem.store_data;
      end
    endcase
    if (!ex_mem.mem_write) wstrb_m = 4'b0000;
  end

  assign dmem_addr  = ex_mem.result;
  assign dmem_wdata = wdata_m;
  assign dmem_wstrb = wstrb_m;

  assign load_byte_m = dmem_rdata[8*byte_off_m +: 8];
  assign load_half_m = byte_off_m[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];

  always_comb begin
    unique case (ex_mem.funct3)
      3'b000:  load_data_m = {{24{load_byte_m[7]}}, load_byte_m};    // LB
      3'b001:  load_data_m = {{16{load_half_m[15]}}, load_half_m};   // LH
      3'b100:  load_data_m = {24'b0, load_byte_m};                   // LBU
      3'b101:  load_data_m = {16'b0, load_half_m};                   // LHU
      default: load_data_m = dmem_rdata;                             // LW
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      mem_wb       <= '0;
      mem_wb.instr <= NOP;
    end else begin
      mem_wb.valid     <= ex_mem.valid;
      mem_wb.pc        <= ex_mem.pc;
      mem_wb.instr     <= ex_mem.instr;
      mem_wb.reg_write <= ex_mem.reg_write;
      mem_wb.rd        <= ex_mem.rd;
      mem_wb.wdata     <= ex_mem.mem_read ? load_data_m : ex_mem.result;
      mem_wb.mem_wstrb <= wstrb_m;
      mem_wb.mem_addr  <= ex_mem.result;
      mem_wb.mem_wdata <= wdata_m;
    end
  end

  // ---------------------------------------------------------------------------
  // WB — register write happens inside u_regfile; expose the retirement trace
  // ---------------------------------------------------------------------------
  assign ret_valid     = mem_wb.valid;
  assign ret_pc        = mem_wb.pc;
  assign ret_instr     = mem_wb.instr;
  assign ret_rd_we     = mem_wb.reg_write;
  assign ret_rd        = mem_wb.rd;
  assign ret_rd_wdata  = mem_wb.wdata;
  assign ret_mem_wstrb = mem_wb.mem_wstrb;
  assign ret_mem_addr  = mem_wb.mem_addr;
  assign ret_mem_wdata = mem_wb.mem_wdata;

  // ---------------------------------------------------------------------------
  // Hazard unit
  // ---------------------------------------------------------------------------
  rv32i_hazard_unit u_hazard (
    .rs1_d         (rs1_d),
    .rs2_d         (rs2_d),
    .mem_read_e    (id_ex.ctrl.mem_read),
    .rd_e          (id_ex.rd),
    .pc_redirect_e (pc_redirect_e),
    .stall_f       (stall_f),
    .stall_d       (stall_d),
    .flush_d       (flush_d),
    .flush_e       (flush_e)
  );

endmodule
