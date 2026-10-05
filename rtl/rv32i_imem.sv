// -----------------------------------------------------------------------------
// rv32i_imem — instruction ROM, word-addressed, combinational read
// -----------------------------------------------------------------------------
module rv32i_imem #(
  parameter int DEPTH_WORDS = 1024,
  parameter     INIT_FILE   = ""      // optional $readmemh image
) (
  input  logic [31:0] addr,
  output logic [31:0] rdata
);

  localparam int AW = $clog2(DEPTH_WORDS);

  logic [31:0] mem [0:DEPTH_WORDS-1];

  initial begin
    for (int i = 0; i < DEPTH_WORDS; i++) mem[i] = 32'h0000_0013;  // NOP
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  assign rdata = mem[addr[AW+1:2]];

endmodule
