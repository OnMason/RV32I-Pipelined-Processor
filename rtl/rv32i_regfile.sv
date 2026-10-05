// -----------------------------------------------------------------------------
// rv32i_regfile — 32 x 32-bit register file
//
//   * x0 is hardwired to zero (reads 0, writes ignored).
//   * Two combinational read ports, one synchronous write port.
//   * Write-first: a read of the register being written this cycle returns the
//     new value, so an instruction in ID sees the result of the one in WB
//     without a third forwarding path.
// -----------------------------------------------------------------------------
module rv32i_regfile (
  input  logic        clk,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata,
  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2
);

  logic [31:0] regs [1:31];

  // No reset: registers hold whatever the program writes. Zero at power-up so
  // simulation starts from a known state (FPGA flops also initialise to 0).
  initial begin
    for (int i = 1; i < 32; i++) regs[i] = 32'h0;
  end

  // Plain always (not always_ff): the array is also written by the initial block
  // above and loaded through the back door by the testbench.
  always @(posedge clk) begin
    if (we && waddr != 5'd0) regs[waddr] <= wdata;
  end

  always_comb begin
    if (raddr1 == 5'd0)                rdata1 = 32'h0;
    else if (we && waddr == raddr1)    rdata1 = wdata;
    else                               rdata1 = regs[raddr1];

    if (raddr2 == 5'd0)                rdata2 = 32'h0;
    else if (we && waddr == raddr2)    rdata2 = wdata;
    else                               rdata2 = regs[raddr2];
  end

endmodule
