// -----------------------------------------------------------------------------
// rv32i_pkg — shared types and constants for the pipelined RV32I core
// -----------------------------------------------------------------------------
package rv32i_pkg;

  // RV32I major opcodes (instr[6:0])
  localparam logic [6:0] OP_LUI      = 7'b0110111;
  localparam logic [6:0] OP_AUIPC    = 7'b0010111;
  localparam logic [6:0] OP_JAL      = 7'b1101111;
  localparam logic [6:0] OP_JALR     = 7'b1100111;
  localparam logic [6:0] OP_BRANCH   = 7'b1100011;
  localparam logic [6:0] OP_LOAD     = 7'b0000011;
  localparam logic [6:0] OP_STORE    = 7'b0100011;
  localparam logic [6:0] OP_IMM      = 7'b0010011;
  localparam logic [6:0] OP_REG      = 7'b0110011;
  localparam logic [6:0] OP_MISC_MEM = 7'b0001111;  // FENCE   (executes as NOP)
  localparam logic [6:0] OP_SYSTEM   = 7'b1110011;  // ECALL / EBREAK (execute as NOP)

  // addi x0, x0, 0
  localparam logic [31:0] NOP = 32'h0000_0013;

  // ALU operations
  typedef enum logic [3:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_SRL,
    ALU_SRA,
    ALU_OR,
    ALU_AND,
    ALU_PASS_B   // result = B (used by LUI)
  } alu_op_e;

  // Forwarding mux selects
  typedef enum logic [1:0] {
    FWD_NONE = 2'b00,  // value read from the register file in ID
    FWD_WB   = 2'b01,  // value being written back this cycle (MEM/WB)
    FWD_MEM  = 2'b10   // ALU result of the previous instruction (EX/MEM)
  } fwd_sel_e;

  // Control bundle produced in ID and carried down the pipeline
  typedef struct packed {
    logic       reg_write;   // writes rd (never set when rd == x0)
    logic       mem_read;    // load
    logic       mem_write;   // store
    logic       branch;      // conditional branch
    logic       jal;
    logic       jalr;
    logic       alu_a_pc;    // ALU operand A: 1 = PC, 0 = rs1
    logic       alu_b_imm;   // ALU operand B: 1 = immediate, 0 = rs2
    alu_op_e    alu_op;
    logic [2:0] funct3;      // branch condition / load-store size
  } ctrl_t;

endpackage
