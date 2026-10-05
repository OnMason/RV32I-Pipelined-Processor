// -----------------------------------------------------------------------------
// rv32i_decoder — instruction -> control bundle + register addresses
//
// rs1/rs2 are forced to x0 when the instruction does not read them, and
// reg_write is never asserted for rd == x0. That lets the forwarding and
// hazard units compare register numbers without extra "is it used" qualifiers:
// a match against x0 is always ignored.
// -----------------------------------------------------------------------------
module rv32i_decoder
  import rv32i_pkg::*;
(
  input  logic [31:0] instr,
  input  logic        valid,     // 0 = bubble: produce no side effects
  output ctrl_t       ctrl,
  output logic [4:0]  rs1,
  output logic [4:0]  rs2,
  output logic [4:0]  rd,
  output logic        illegal
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic       uses_rs1, uses_rs2, writes_rd;

  assign opcode = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];

  always_comb begin
    ctrl      = '0;
    ctrl.alu_op = ALU_ADD;
    ctrl.funct3 = funct3;
    uses_rs1  = 1'b0;
    uses_rs2  = 1'b0;
    writes_rd = 1'b0;
    illegal   = 1'b0;

    unique case (opcode)
      OP_LUI: begin
        writes_rd      = 1'b1;
        ctrl.alu_b_imm = 1'b1;
        ctrl.alu_op    = ALU_PASS_B;
      end

      OP_AUIPC: begin
        writes_rd      = 1'b1;
        ctrl.alu_a_pc  = 1'b1;
        ctrl.alu_b_imm = 1'b1;
      end

      OP_JAL: begin
        writes_rd = 1'b1;
        ctrl.jal  = 1'b1;
      end

      OP_JALR: begin
        if (funct3 == 3'b000) begin
          writes_rd = 1'b1;
          uses_rs1  = 1'b1;
          ctrl.jalr = 1'b1;
        end else begin
          illegal = 1'b1;
        end
      end

      OP_BRANCH: begin
        if (funct3 == 3'b010 || funct3 == 3'b011) begin
          illegal = 1'b1;
        end else begin
          uses_rs1    = 1'b1;
          uses_rs2    = 1'b1;
          ctrl.branch = 1'b1;
        end
      end

      OP_LOAD: begin
        if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111) begin
          illegal = 1'b1;
        end else begin
          writes_rd      = 1'b1;
          uses_rs1       = 1'b1;
          ctrl.mem_read  = 1'b1;
          ctrl.alu_b_imm = 1'b1;
        end
      end

      OP_STORE: begin
        if (funct3 > 3'b010) begin
          illegal = 1'b1;
        end else begin
          uses_rs1       = 1'b1;
          uses_rs2       = 1'b1;
          ctrl.mem_write = 1'b1;
          ctrl.alu_b_imm = 1'b1;
        end
      end

      OP_IMM: begin
        writes_rd      = 1'b1;
        uses_rs1       = 1'b1;
        ctrl.alu_b_imm = 1'b1;
        unique case (funct3)
          3'b000: ctrl.alu_op = ALU_ADD;
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
          3'b001: begin
            ctrl.alu_op = ALU_SLL;
            illegal     = (funct7 != 7'b0000000);
          end
          3'b101: begin
            ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
            illegal     = (funct7 != 7'b0000000) && (funct7 != 7'b0100000);
          end
          default: illegal = 1'b1;
        endcase
      end

      OP_REG: begin
        writes_rd = 1'b1;
        uses_rs1  = 1'b1;
        uses_rs2  = 1'b1;
        unique case ({funct7, funct3})
          {7'b0000000, 3'b000}: ctrl.alu_op = ALU_ADD;
          {7'b0100000, 3'b000}: ctrl.alu_op = ALU_SUB;
          {7'b0000000, 3'b001}: ctrl.alu_op = ALU_SLL;
          {7'b0000000, 3'b010}: ctrl.alu_op = ALU_SLT;
          {7'b0000000, 3'b011}: ctrl.alu_op = ALU_SLTU;
          {7'b0000000, 3'b100}: ctrl.alu_op = ALU_XOR;
          {7'b0000000, 3'b101}: ctrl.alu_op = ALU_SRL;
          {7'b0100000, 3'b101}: ctrl.alu_op = ALU_SRA;
          {7'b0000000, 3'b110}: ctrl.alu_op = ALU_OR;
          {7'b0000000, 3'b111}: ctrl.alu_op = ALU_AND;
          default:              illegal     = 1'b1;
        endcase
      end

      // No CSRs, traps, or caches in this core: these execute as NOPs.
      OP_MISC_MEM, OP_SYSTEM: ;

      default: illegal = 1'b1;
    endcase

    // Bubbles and illegal encodings must not change architectural state.
    if (!valid || illegal) begin
      ctrl        = '0;
      ctrl.alu_op = ALU_ADD;
      ctrl.funct3 = funct3;
      uses_rs1    = 1'b0;
      uses_rs2    = 1'b0;
      writes_rd   = 1'b0;
    end
    if (!valid) illegal = 1'b0;

    rd             = writes_rd ? instr[11:7] : 5'd0;
    rs1            = uses_rs1 ? instr[19:15] : 5'd0;
    rs2            = uses_rs2 ? instr[24:20] : 5'd0;
    ctrl.reg_write = writes_rd && (instr[11:7] != 5'd0);
  end

endmodule
