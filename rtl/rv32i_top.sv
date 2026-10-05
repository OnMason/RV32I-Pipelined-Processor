// -----------------------------------------------------------------------------
// rv32i_top — pipelined core + instruction ROM + data RAM
// -----------------------------------------------------------------------------
module rv32i_top #(
  parameter int          IMEM_WORDS = 1024,
  parameter int          DMEM_WORDS = 1024,
  parameter              IMEM_INIT  = "",
  parameter              DMEM_INIT  = "",
  parameter logic [31:0] RESET_PC   = 32'h0000_0000
) (
  input  logic        clk,
  input  logic        reset,

  // Retirement trace (leave unconnected for synthesis; used by the testbench)
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

  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_wstrb;

  rv32i_core #(
    .RESET_PC (RESET_PC)
  ) u_core (
    .clk           (clk),
    .reset         (reset),
    .imem_addr     (imem_addr),
    .imem_rdata    (imem_rdata),
    .dmem_addr     (dmem_addr),
    .dmem_wdata    (dmem_wdata),
    .dmem_wstrb    (dmem_wstrb),
    .dmem_rdata    (dmem_rdata),
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

  rv32i_imem #(
    .DEPTH_WORDS (IMEM_WORDS),
    .INIT_FILE   (IMEM_INIT)
  ) u_imem (
    .addr  (imem_addr),
    .rdata (imem_rdata)
  );

  rv32i_dmem #(
    .DEPTH_WORDS (DMEM_WORDS),
    .INIT_FILE   (DMEM_INIT)
  ) u_dmem (
    .clk   (clk),
    .addr  (dmem_addr),
    .wdata (dmem_wdata),
    .wstrb (dmem_wstrb),
    .rdata (dmem_rdata)
  );

endmodule
