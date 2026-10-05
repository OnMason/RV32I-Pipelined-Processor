// -----------------------------------------------------------------------------
// rv32i_dmem — data RAM, word-addressed, byte-strobed synchronous write,
//              combinational read
// -----------------------------------------------------------------------------
module rv32i_dmem #(
  parameter int DEPTH_WORDS = 1024,
  parameter     INIT_FILE   = ""      // optional $readmemh image
) (
  input  logic        clk,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic [31:0] rdata
);

  localparam int AW = $clog2(DEPTH_WORDS);

  logic [31:0] mem [0:DEPTH_WORDS-1];

  initial begin
    for (int i = 0; i < DEPTH_WORDS; i++) mem[i] = 32'h0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  // Plain always (not always_ff): the array is also written by the initial block
  // above and loaded through the back door by the testbench.
  always @(posedge clk) begin
    for (int b = 0; b < 4; b++) begin
      if (wstrb[b]) mem[addr[AW+1:2]][8*b +: 8] <= wdata[8*b +: 8];
    end
  end

  assign rdata = mem[addr[AW+1:2]];

endmodule
