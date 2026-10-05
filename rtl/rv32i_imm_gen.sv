// -----------------------------------------------------------------------------
// rv32i_imm_gen — sign-extended immediate for every RV32I format
// -----------------------------------------------------------------------------
module rv32i_imm_gen
  import rv32i_pkg::*;
(
  input  logic [31:0] instr,
  output logic [31:0] imm
);

  always_comb begin
    unique case (instr[6:0])
      OP_LUI, OP_AUIPC: imm = {instr[31:12], 12'b0};                                   // U
      OP_JAL:           imm = {{12{instr[31]}}, instr[19:12], instr[20],
                               instr[30:21], 1'b0};                                    // J
      OP_BRANCH:        imm = {{20{instr[31]}}, instr[7], instr[30:25],
                               instr[11:8], 1'b0};                                     // B
      OP_STORE:         imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};            // S
      default:          imm = {{20{instr[31]}}, instr[31:20]};                         // I
    endcase
  end

endmodule
