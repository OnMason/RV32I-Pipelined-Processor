// -----------------------------------------------------------------------------
// rv32i_alu — 32-bit ALU covering every RV32I arithmetic/logic/shift operation
// -----------------------------------------------------------------------------
module rv32i_alu
  import rv32i_pkg::*;
(
  input  logic [31:0] a,
  input  logic [31:0] b,
  input  alu_op_e     op,
  output logic [31:0] result
);

  logic [4:0] shamt;
  assign shamt = b[4:0];

  always_comb begin
    unique case (op)
      ALU_ADD:    result = a + b;
      ALU_SUB:    result = a - b;
      ALU_SLL:    result = a << shamt;
      ALU_SLT:    result = {31'b0, $signed(a) < $signed(b)};
      ALU_SLTU:   result = {31'b0, a < b};
      ALU_XOR:    result = a ^ b;
      ALU_SRL:    result = a >> shamt;
      ALU_SRA:    result = $unsigned($signed(a) >>> shamt);
      ALU_OR:     result = a | b;
      ALU_AND:    result = a & b;
      ALU_PASS_B: result = b;
      default:    result = a + b;
    endcase
  end

endmodule
