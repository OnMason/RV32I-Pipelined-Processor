// -----------------------------------------------------------------------------
// rv32i_tb_pkg — verification components for the pipelined RV32I core
//
//   * rv32i_asm         : tiny assembler (one function per instruction)
//   * rv32i_rand_instr  : one constrained-random instruction
//   * rv32i_rand_program: constrained-random program builder (always terminates)
//   * rv32i_ref_model   : untimed instruction-set reference model
//   * rv32i_coverage    : functional coverage bins with a text report
// -----------------------------------------------------------------------------
package rv32i_tb_pkg;

  import rv32i_pkg::*;

  // jal x0, 0 — jump-to-self. The testbench ends a program when this retires.
  localparam bit [31:0] HALT = 32'h0000_006f;

  // Register reserved as the loop counter in random programs (never a random rd).
  localparam bit [4:0] LOOP_REG = 5'd31;

  // Every instruction the core implements
  typedef enum int {
    I_LUI, I_AUIPC, I_JAL, I_JALR,
    I_BEQ, I_BNE, I_BLT, I_BGE, I_BLTU, I_BGEU,
    I_LB, I_LH, I_LW, I_LBU, I_LHU,
    I_SB, I_SH, I_SW,
    I_ADDI, I_SLTI, I_SLTIU, I_XORI, I_ORI, I_ANDI, I_SLLI, I_SRLI, I_SRAI,
    I_ADD, I_SUB, I_SLL, I_SLT, I_SLTU, I_XOR, I_SRL, I_SRA, I_OR, I_AND,
    I_FENCE, I_ECALL, I_EBREAK
  } instr_e;

  localparam int NUM_INSTR = 40;

  // Stimulus "knob" values. These are text macros for plain literals (rather
  // than enums or localparams) because they are used as dist targets, and
  // literal bit-vector dist is the one form every solver weights the same way
  // (Verilator, for one, ignores the weights when the targets are named constants).

  // Instruction categories used to steer the random mix
  typedef bit [2:0] cat_t;
  `define CAT_ALU_REG 3'd0
  `define CAT_ALU_IMM 3'd1
  `define CAT_UPPER   3'd2
  `define CAT_LOAD    3'd3
  `define CAT_STORE   3'd4
  `define CAT_BRANCH  3'd5
  `define CAT_JUMP    3'd6
  `define CAT_SYSTEM  3'd7

  // Where a source register comes from, relative to earlier instructions
  typedef bit [1:0] dep_t;
  `define DEP_RANDOM 2'd0   // drawn from a register pool
  `define DEP_PREV1  2'd1   // rd of the previous instruction     (EX/MEM forward or load-use)
  `define DEP_PREV2  2'd2   // rd of the instruction before that  (MEM/WB forward)

  // Register pools: a few hot registers make unplanned collisions likely too
  typedef bit [1:0] pool_t;
  `define POOL_X0  2'd0
  `define POOL_HOT 2'd1
  `define POOL_ANY 2'd2

  // One retired instruction, as seen by the scoreboard
  typedef struct {
    bit [31:0] pc;
    bit [31:0] instr;
    bit        rd_we;
    bit [4:0]  rd;
    bit [31:0] rd_wdata;
    bit [3:0]  mem_wstrb;
    bit [31:0] mem_addr;
    bit [31:0] mem_wdata;
  } retire_t;

  // ---------------------------------------------------------------------------
  // Assembler
  // ---------------------------------------------------------------------------
  class rv32i_asm;
    static function bit [31:0] r_type(bit [6:0] f7, bit [4:0] rs2, bit [4:0] rs1,
                                      bit [2:0] f3, bit [4:0] rd, bit [6:0] op);
      return {f7, rs2, rs1, f3, rd, op};
    endfunction

    static function bit [31:0] i_type(bit [11:0] imm, bit [4:0] rs1, bit [2:0] f3,
                                      bit [4:0] rd, bit [6:0] op);
      return {imm, rs1, f3, rd, op};
    endfunction

    static function bit [31:0] s_type(bit [11:0] imm, bit [4:0] rs2, bit [4:0] rs1,
                                      bit [2:0] f3, bit [6:0] op);
      return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
    endfunction

    // off = byte offset from this instruction (bit 0 ignored)
    static function bit [31:0] b_type(bit [12:0] off, bit [4:0] rs2, bit [4:0] rs1,
                                      bit [2:0] f3);
      return {off[12], off[10:5], rs2, rs1, f3, off[4:1], off[11], OP_BRANCH};
    endfunction

    static function bit [31:0] u_type(bit [19:0] imm, bit [4:0] rd, bit [6:0] op);
      return {imm, rd, op};
    endfunction

    static function bit [31:0] j_type(bit [20:0] off, bit [4:0] rd);
      return {off[20], off[10:1], off[11], off[19:12], rd, OP_JAL};
    endfunction

    static function bit [31:0] lui  (bit [4:0] rd, bit [19:0] imm);  return u_type(imm, rd, OP_LUI);   endfunction
    static function bit [31:0] auipc(bit [4:0] rd, bit [19:0] imm);  return u_type(imm, rd, OP_AUIPC); endfunction
    static function bit [31:0] jal  (bit [4:0] rd, int off);         return j_type(off[20:0], rd);     endfunction
    static function bit [31:0] jalr (bit [4:0] rd, bit [4:0] rs1, int imm);
      return i_type(imm[11:0], rs1, 3'b000, rd, OP_JALR);
    endfunction

    static function bit [31:0] beq (bit [4:0] rs1, bit [4:0] rs2, int off); return b_type(off[12:0], rs2, rs1, 3'b000); endfunction
    static function bit [31:0] bne (bit [4:0] rs1, bit [4:0] rs2, int off); return b_type(off[12:0], rs2, rs1, 3'b001); endfunction
    static function bit [31:0] blt (bit [4:0] rs1, bit [4:0] rs2, int off); return b_type(off[12:0], rs2, rs1, 3'b100); endfunction
    static function bit [31:0] bge (bit [4:0] rs1, bit [4:0] rs2, int off); return b_type(off[12:0], rs2, rs1, 3'b101); endfunction
    static function bit [31:0] bltu(bit [4:0] rs1, bit [4:0] rs2, int off); return b_type(off[12:0], rs2, rs1, 3'b110); endfunction
    static function bit [31:0] bgeu(bit [4:0] rs1, bit [4:0] rs2, int off); return b_type(off[12:0], rs2, rs1, 3'b111); endfunction

    static function bit [31:0] lb (bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b000, rd, OP_LOAD); endfunction
    static function bit [31:0] lh (bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b001, rd, OP_LOAD); endfunction
    static function bit [31:0] lw (bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b010, rd, OP_LOAD); endfunction
    static function bit [31:0] lbu(bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b100, rd, OP_LOAD); endfunction
    static function bit [31:0] lhu(bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b101, rd, OP_LOAD); endfunction

    static function bit [31:0] sb(bit [4:0] rs2, bit [4:0] rs1, int imm); return s_type(imm[11:0], rs2, rs1, 3'b000, OP_STORE); endfunction
    static function bit [31:0] sh(bit [4:0] rs2, bit [4:0] rs1, int imm); return s_type(imm[11:0], rs2, rs1, 3'b001, OP_STORE); endfunction
    static function bit [31:0] sw(bit [4:0] rs2, bit [4:0] rs1, int imm); return s_type(imm[11:0], rs2, rs1, 3'b010, OP_STORE); endfunction

    static function bit [31:0] addi (bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b000, rd, OP_IMM); endfunction
    static function bit [31:0] slti (bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b010, rd, OP_IMM); endfunction
    static function bit [31:0] sltiu(bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b011, rd, OP_IMM); endfunction
    static function bit [31:0] xori (bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b100, rd, OP_IMM); endfunction
    static function bit [31:0] ori  (bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b110, rd, OP_IMM); endfunction
    static function bit [31:0] andi (bit [4:0] rd, bit [4:0] rs1, int imm); return i_type(imm[11:0], rs1, 3'b111, rd, OP_IMM); endfunction
    static function bit [31:0] slli (bit [4:0] rd, bit [4:0] rs1, bit [4:0] sh); return i_type({7'b0000000, sh}, rs1, 3'b001, rd, OP_IMM); endfunction
    static function bit [31:0] srli (bit [4:0] rd, bit [4:0] rs1, bit [4:0] sh); return i_type({7'b0000000, sh}, rs1, 3'b101, rd, OP_IMM); endfunction
    static function bit [31:0] srai (bit [4:0] rd, bit [4:0] rs1, bit [4:0] sh); return i_type({7'b0100000, sh}, rs1, 3'b101, rd, OP_IMM); endfunction

    static function bit [31:0] add (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0000000, rs2, rs1, 3'b000, rd, OP_REG); endfunction
    static function bit [31:0] sub (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0100000, rs2, rs1, 3'b000, rd, OP_REG); endfunction
    static function bit [31:0] sll (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0000000, rs2, rs1, 3'b001, rd, OP_REG); endfunction
    static function bit [31:0] slt (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0000000, rs2, rs1, 3'b010, rd, OP_REG); endfunction
    static function bit [31:0] sltu(bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0000000, rs2, rs1, 3'b011, rd, OP_REG); endfunction
    static function bit [31:0] xor_(bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0000000, rs2, rs1, 3'b100, rd, OP_REG); endfunction
    static function bit [31:0] srl (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0000000, rs2, rs1, 3'b101, rd, OP_REG); endfunction
    static function bit [31:0] sra (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0100000, rs2, rs1, 3'b101, rd, OP_REG); endfunction
    static function bit [31:0] or_ (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0000000, rs2, rs1, 3'b110, rd, OP_REG); endfunction
    static function bit [31:0] and_(bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return r_type(7'b0000000, rs2, rs1, 3'b111, rd, OP_REG); endfunction

    static function bit [31:0] nop();    return 32'h0000_0013; endfunction
    static function bit [31:0] fence();  return 32'h0ff0_000f; endfunction
    static function bit [31:0] ecall();  return 32'h0000_0073; endfunction
    static function bit [31:0] ebreak(); return 32'h0010_0073; endfunction
  endclass

  // Classify an encoded instruction (used by coverage and the log)
  function automatic instr_e decode_kind(bit [31:0] instr);
    bit [2:0] f3 = instr[14:12];
    bit       f7b5 = instr[30];
    case (instr[6:0])
      OP_LUI:    return I_LUI;
      OP_AUIPC:  return I_AUIPC;
      OP_JAL:    return I_JAL;
      OP_JALR:   return I_JALR;
      OP_BRANCH: case (f3)
                   3'b000: return I_BEQ;  3'b001: return I_BNE;
                   3'b100: return I_BLT;  3'b101: return I_BGE;
                   3'b110: return I_BLTU; default: return I_BGEU;
                 endcase
      OP_LOAD:   case (f3)
                   3'b000: return I_LB;  3'b001: return I_LH; 3'b010: return I_LW;
                   3'b100: return I_LBU; default: return I_LHU;
                 endcase
      OP_STORE:  case (f3)
                   3'b000: return I_SB; 3'b001: return I_SH; default: return I_SW;
                 endcase
      OP_IMM:    case (f3)
                   3'b000: return I_ADDI;  3'b010: return I_SLTI; 3'b011: return I_SLTIU;
                   3'b100: return I_XORI;  3'b110: return I_ORI;  3'b111: return I_ANDI;
                   3'b001: return I_SLLI;  default: return f7b5 ? I_SRAI : I_SRLI;
                 endcase
      OP_REG:    case (f3)
                   3'b000: return f7b5 ? I_SUB : I_ADD;
                   3'b001: return I_SLL;   3'b010: return I_SLT; 3'b011: return I_SLTU;
                   3'b100: return I_XOR;   3'b101: return f7b5 ? I_SRA : I_SRL;
                   3'b110: return I_OR;    default: return I_AND;
                 endcase
      OP_MISC_MEM: return I_FENCE;
      default:     return instr[20] ? I_EBREAK : I_ECALL;
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // Stimulus knobs for one instruction
  //
  // Randomized first, on their own, so the weights below are exactly the
  // probabilities that come out. (If knobs and instruction fields were solved
  // together, the solver would pick uniformly over whole solutions and favour
  // whichever knob setting leaves the fields most freedom.)
  // ---------------------------------------------------------------------------
  class rv32i_instr_knobs;
    // instruction mix (relative weights)
    int unsigned w_alu_reg = 20;
    int unsigned w_alu_imm = 20;
    int unsigned w_upper   = 4;
    int unsigned w_load    = 14;
    int unsigned w_store   = 12;
    int unsigned w_branch  = 14;
    int unsigned w_jump    = 5;
    int unsigned w_system  = 1;
    // % of source registers that read the previous / second-previous rd
    int unsigned w_dep_prev1 = 35;
    int unsigned w_dep_prev2 = 20;

    rand cat_t  cat;
    rand dep_t  dep_rs1, dep_rs2;
    rand pool_t pool_rd, pool_rs1, pool_rs2;
    rand bit    near_mem;   // load/store hits the small shared window at 0..63
    rand bit    jalr_lsb;   // set bit 0 of the JALR offset (must be cleared by the core)
    rand bit [9:0] pick;    // selects one instruction uniformly within the category

    constraint c_mix {
      cat dist {
        `CAT_ALU_REG := w_alu_reg, `CAT_ALU_IMM := w_alu_imm, `CAT_UPPER  := w_upper,
        `CAT_LOAD    := w_load,    `CAT_STORE   := w_store,   `CAT_BRANCH := w_branch,
        `CAT_JUMP    := w_jump,    `CAT_SYSTEM  := w_system
      };
    }

    constraint c_dep {
      dep_rs1 dist { `DEP_PREV1 := w_dep_prev1, `DEP_PREV2 := w_dep_prev2,
                     `DEP_RANDOM := (100 - w_dep_prev1 - w_dep_prev2) };
      dep_rs2 dist { `DEP_PREV1 := w_dep_prev1, `DEP_PREV2 := w_dep_prev2,
                     `DEP_RANDOM := (100 - w_dep_prev1 - w_dep_prev2) };
    }

    constraint c_pool {
      pool_rd  dist { `POOL_X0 := 4, `POOL_HOT := 66, `POOL_ANY := 30 };
      pool_rs1 dist { `POOL_X0 := 4, `POOL_HOT := 60, `POOL_ANY := 36 };
      pool_rs2 dist { `POOL_X0 := 4, `POOL_HOT := 60, `POOL_ANY := 36 };
    }

    constraint c_mem { near_mem dist { 1'b1 := 70, 1'b0 := 30 }; }
  endclass

  // ---------------------------------------------------------------------------
  // One constrained-random instruction
  // ---------------------------------------------------------------------------
  class rv32i_rand_instr;

    // ---- knobs: chosen first by randomize_instr(), then held fixed ----
    rv32i_instr_knobs knobs;
    cat_t             cat;
    dep_t             dep_rs1, dep_rs2;
    pool_t            pool_rd, pool_rs1, pool_rs2;
    bit               near_mem;
    bit               jalr_lsb;
    bit [2:0]         max_skip = 3'd4;  // furthest forward branch/jump, in instructions

    // ---- context: what the two previous instructions wrote ----
    bit [4:0] prev1_rd;
    bit [4:0] prev2_rd;

    instr_e           kind;             // drawn uniformly within the category

    // ---- random instruction fields ----
    rand bit [4:0]  rd;
    rand bit [4:0]  rs1;
    rand bit [4:0]  rs2;
    rand bit [11:0] imm12;
    rand bit [19:0] imm20;
    rand bit [4:0]  shamt;
    rand bit [2:0]  skip;       // control flow: instructions jumped over

    // Destination: mostly a small pool of hot registers so instructions collide
    // with each other; never the loop counter.
    constraint c_rd {
      (pool_rd == `POOL_X0)  -> rd == 5'd0;
      (pool_rd == `POOL_HOT) -> rd inside {[5'd1:5'd7]};
      rd != LOOP_REG;
    }

    // rs1 is pinned by the instruction in two cases:
    //   * near-window memory access: base register is x0
    //   * JALR: emitted as "auipc rs1, 0 ; jalr rd, rs1, off", so rs1 is a
    //     scratch register that must be real and must not be the loop counter
    // Otherwise it either tracks an earlier rd (to force a forwarding path or a
    // load-use stall) or is drawn from its pool.
    constraint c_rs1 {
      if ((cat == `CAT_LOAD || cat == `CAT_STORE) && near_mem) {
        rs1 == 5'd0;
        imm12 < 12'd64;
      } else if (cat == `CAT_JUMP) {
        rs1 inside {[5'd1:5'd30]};
      } else if (dep_rs1 == `DEP_PREV1) {
        rs1 == prev1_rd;
      } else if (dep_rs1 == `DEP_PREV2) {
        rs1 == prev2_rd;
      } else {
        (pool_rs1 == `POOL_X0)  -> rs1 == 5'd0;
        (pool_rs1 == `POOL_HOT) -> rs1 inside {[5'd1:5'd7]};
      }
    }

    constraint c_rs2 {
      if (dep_rs2 == `DEP_PREV1) {
        rs2 == prev1_rd;
      } else if (dep_rs2 == `DEP_PREV2) {
        rs2 == prev2_rd;
      } else {
        (pool_rs2 == `POOL_X0)  -> rs2 == 5'd0;
        (pool_rs2 == `POOL_HOT) -> rs2 inside {[5'd1:5'd7]};
      }
    }

    constraint c_flow { skip <= max_skip; }

    function new();
      knobs = new();
    endfunction

    // The instructions in each category; pick chooses one of them
    static function instr_e pick_kind(cat_t c, bit [9:0] pick);
      instr_e alu_reg [10] = '{I_ADD, I_SUB, I_SLL, I_SLT, I_SLTU, I_XOR, I_SRL, I_SRA, I_OR, I_AND};
      instr_e alu_imm [9]  = '{I_ADDI, I_SLTI, I_SLTIU, I_XORI, I_ORI, I_ANDI, I_SLLI, I_SRLI, I_SRAI};
      instr_e upper   [2]  = '{I_LUI, I_AUIPC};
      instr_e load    [5]  = '{I_LB, I_LH, I_LW, I_LBU, I_LHU};
      instr_e store   [3]  = '{I_SB, I_SH, I_SW};
      instr_e branch  [6]  = '{I_BEQ, I_BNE, I_BLT, I_BGE, I_BLTU, I_BGEU};
      instr_e jump    [2]  = '{I_JAL, I_JALR};
      instr_e system  [3]  = '{I_FENCE, I_ECALL, I_EBREAK};
      case (c)
        `CAT_ALU_REG: return alu_reg[pick % 10];
        `CAT_ALU_IMM: return alu_imm[pick % 9];
        `CAT_UPPER:   return upper  [pick % 2];
        `CAT_LOAD:    return load   [pick % 5];
        `CAT_STORE:   return store  [pick % 3];
        `CAT_BRANCH:  return branch [pick % 6];
        `CAT_JUMP:    return jump   [pick % 2];
        default:      return system [pick % 3];
      endcase
    endfunction

    // Seed both solver streams from one value
    function void seed(int unsigned s);
      this.srandom(s);
      knobs.srandom(s ^ 32'h5EED_C0DE);
    endfunction

    // Two-step randomization: knobs, then the instruction they describe
    function bit randomize_instr();
      if (!knobs.randomize()) return 1'b0;
      cat      = knobs.cat;
      dep_rs1  = knobs.dep_rs1;   dep_rs2  = knobs.dep_rs2;
      pool_rd  = knobs.pool_rd;   pool_rs1 = knobs.pool_rs1;   pool_rs2 = knobs.pool_rs2;
      near_mem = knobs.near_mem;  jalr_lsb = knobs.jalr_lsb;
      kind     = pick_kind(cat, knobs.pick);
      if (!this.randomize()) return 1'b0;
      return 1'b1;
    endfunction

    // Snapshot of the current random values (the builder reuses one generator
    // object so that a single srandom() seed reproduces the whole program).
    function rv32i_rand_instr copy();
      rv32i_rand_instr c = new();
      c.cat = cat;   c.kind = kind;   c.rd = rd;   c.rs1 = rs1;   c.rs2 = rs2;
      c.dep_rs1 = dep_rs1;   c.dep_rs2 = dep_rs2;
      c.pool_rd = pool_rd;   c.pool_rs1 = pool_rs1;   c.pool_rs2 = pool_rs2;
      c.imm12 = imm12;   c.imm20 = imm20;   c.shamt = shamt;
      c.near_mem = near_mem;   c.skip = skip;   c.jalr_lsb = jalr_lsb;
      return c;
    endfunction

    function bit is_two_words();
      return (kind == I_JALR);
    endfunction

    // rd written by this instruction (0 if none), for dependency tracking
    function bit [4:0] dest();
      case (cat)
        `CAT_STORE, `CAT_BRANCH, `CAT_SYSTEM: return 5'd0;
        default:                           return rd;
      endcase
    endfunction

    // Encode into 1 or 2 words. skip_bytes = size in bytes of the instructions
    // this one jumps over (only used by branches and jumps).
    function void encode(int skip_bytes, ref bit [31:0] q[$]);
      int simm = $signed(imm12);
      case (kind)
        I_LUI:    q.push_back(rv32i_asm::lui(rd, imm20));
        I_AUIPC:  q.push_back(rv32i_asm::auipc(rd, imm20));
        I_JAL:    q.push_back(rv32i_asm::jal(rd, 4 + skip_bytes));
        I_JALR: begin
          q.push_back(rv32i_asm::auipc(rs1, 20'd0));
          q.push_back(rv32i_asm::jalr(rd, rs1, 8 + skip_bytes + int'(jalr_lsb)));
        end
        I_BEQ:    q.push_back(rv32i_asm::beq (rs1, rs2, 4 + skip_bytes));
        I_BNE:    q.push_back(rv32i_asm::bne (rs1, rs2, 4 + skip_bytes));
        I_BLT:    q.push_back(rv32i_asm::blt (rs1, rs2, 4 + skip_bytes));
        I_BGE:    q.push_back(rv32i_asm::bge (rs1, rs2, 4 + skip_bytes));
        I_BLTU:   q.push_back(rv32i_asm::bltu(rs1, rs2, 4 + skip_bytes));
        I_BGEU:   q.push_back(rv32i_asm::bgeu(rs1, rs2, 4 + skip_bytes));
        I_LB:     q.push_back(rv32i_asm::lb (rd, rs1, simm));
        I_LH:     q.push_back(rv32i_asm::lh (rd, rs1, simm));
        I_LW:     q.push_back(rv32i_asm::lw (rd, rs1, simm));
        I_LBU:    q.push_back(rv32i_asm::lbu(rd, rs1, simm));
        I_LHU:    q.push_back(rv32i_asm::lhu(rd, rs1, simm));
        I_SB:     q.push_back(rv32i_asm::sb(rs2, rs1, simm));
        I_SH:     q.push_back(rv32i_asm::sh(rs2, rs1, simm));
        I_SW:     q.push_back(rv32i_asm::sw(rs2, rs1, simm));
        I_ADDI:   q.push_back(rv32i_asm::addi (rd, rs1, simm));
        I_SLTI:   q.push_back(rv32i_asm::slti (rd, rs1, simm));
        I_SLTIU:  q.push_back(rv32i_asm::sltiu(rd, rs1, simm));
        I_XORI:   q.push_back(rv32i_asm::xori (rd, rs1, simm));
        I_ORI:    q.push_back(rv32i_asm::ori  (rd, rs1, simm));
        I_ANDI:   q.push_back(rv32i_asm::andi (rd, rs1, simm));
        I_SLLI:   q.push_back(rv32i_asm::slli (rd, rs1, shamt));
        I_SRLI:   q.push_back(rv32i_asm::srli (rd, rs1, shamt));
        I_SRAI:   q.push_back(rv32i_asm::srai (rd, rs1, shamt));
        I_ADD:    q.push_back(rv32i_asm::add (rd, rs1, rs2));
        I_SUB:    q.push_back(rv32i_asm::sub (rd, rs1, rs2));
        I_SLL:    q.push_back(rv32i_asm::sll (rd, rs1, rs2));
        I_SLT:    q.push_back(rv32i_asm::slt (rd, rs1, rs2));
        I_SLTU:   q.push_back(rv32i_asm::sltu(rd, rs1, rs2));
        I_XOR:    q.push_back(rv32i_asm::xor_(rd, rs1, rs2));
        I_SRL:    q.push_back(rv32i_asm::srl (rd, rs1, rs2));
        I_SRA:    q.push_back(rv32i_asm::sra (rd, rs1, rs2));
        I_OR:     q.push_back(rv32i_asm::or_ (rd, rs1, rs2));
        I_AND:    q.push_back(rv32i_asm::and_(rd, rs1, rs2));
        I_FENCE:  q.push_back(rv32i_asm::fence());
        I_ECALL:  q.push_back(rv32i_asm::ecall());
        default:  q.push_back(rv32i_asm::ebreak());
      endcase
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Constrained-random program
  //
  // Layout:  [register init] [random body] [NOP landing pad] [HALT]
  //
  // Termination is guaranteed by construction:
  //   * random branches and jumps only go forward, to an instruction boundary;
  //   * the only backward branches close counted loops on a reserved register
  //     (x31) that random instructions never write. Loops are not nested and a
  //     loop exits as soon as x31 <= 0, so entering one sideways is harmless.
  // ---------------------------------------------------------------------------
  typedef enum int { PROF_BALANCED, PROF_HAZARD, PROF_BRANCH, PROF_MEMORY } profile_e;

  // Program-structure choices: register start values and counted loops
  class rv32i_prog_knobs;
    rand bit [31:0] init_val;     // start value for one register
    rand bit [6:0]  loop_roll;    // a loop opens when this lands below 6 (~6%)
    rand bit [3:0]  loop_len;     // loop body length, instructions
    rand bit [2:0]  loop_iters;   // loop trip count
    constraint c_loop {
      loop_roll < 7'd100;
      loop_len   inside {[4'd2:4'd8]};
      loop_iters inside {[3'd1:3'd4]};
    }
  endclass

  class rv32i_rand_program;

    profile_e         profile = PROF_BALANCED;   // set by the test, not randomized
    rand int unsigned num_items;     // random-body length in instructions
    int unsigned      min_items = 200;
    int unsigned      max_items = 400;

    constraint c_len     { num_items inside {[min_items:max_items]}; }

    bit [31:0] words[$];             // the assembled program

    rand int unsigned item_seed;     // seeds the per-instruction generators

    local function void apply_profile(rv32i_instr_knobs it);
      case (profile)
        PROF_HAZARD: begin   // dense dependencies and many loads -> forwarding + stalls
          it.w_load = 24; it.w_branch = 12; it.w_dep_prev1 = 55; it.w_dep_prev2 = 25;
        end
        PROF_BRANCH: begin   // control-flow heavy -> flushes
          it.w_branch = 34; it.w_jump = 12; it.w_alu_reg = 14; it.w_alu_imm = 14;
        end
        PROF_MEMORY: begin   // load/store heavy
          it.w_load = 26; it.w_store = 24; it.w_alu_reg = 12; it.w_alu_imm = 12;
        end
        default: ;
      endcase
    endfunction

    function void build();
      rv32i_rand_instr items[$];
      int              item_bytes[$];    // encoded size of each body entry
      int              loop_back[$];     // >0: entry is a loop-close, value = body start index
      int              loop_init[$];     // >0: entry is "addi x31, x0, n"
      rv32i_rand_instr gen, it;
      rv32i_prog_knobs pk;
      bit [31:0]       iv;
      bit [4:0]        prev1, prev2;
      int              in_loop_left;     // body instructions left in the open loop
      int              loop_start_idx;
      int              n;

      words.delete();
      gen = new();
      gen.seed(item_seed);
      apply_profile(gen.knobs);
      pk = new();
      pk.srandom(item_seed ^ 32'hA5A5_1234);

      // --- give every register a random starting value (lui + addi) ---
      for (int r = 1; r < 31; r++) begin
        if (!pk.randomize()) $fatal(1, "randomize(prog knobs) failed");
        iv = pk.init_val;
        // lui loads the upper 20 bits; addi adds a sign-extended low 12, so the
        // upper part is pre-compensated when bit 11 is set.
        words.push_back(rv32i_asm::lui(r[4:0], iv[31:12] + {19'b0, iv[11]}));
        words.push_back(rv32i_asm::addi(r[4:0], r[4:0], $signed(iv[11:0])));
      end

      // --- random body: first choose every instruction ---
      prev1 = 5'd0; prev2 = 5'd0; in_loop_left = 0; loop_start_idx = 0;
      n = 0;
      while (n < int'(num_items)) begin
        // maybe open a counted loop
        if (in_loop_left == 0) begin
          if (!pk.randomize()) $fatal(1, "randomize(prog knobs) failed");
          if (pk.loop_roll < 7'd6) begin
            items.push_back(null); item_bytes.push_back(4);
            loop_back.push_back(0); loop_init.push_back(int'(pk.loop_iters));
            in_loop_left   = int'(pk.loop_len);
            loop_start_idx = items.size();
          end
        end

        gen.prev1_rd = prev1;
        gen.prev2_rd = prev2;
        if (!gen.randomize_instr()) $fatal(1, "randomize(instr) failed");
        it = gen.copy();
        items.push_back(it); item_bytes.push_back(it.is_two_words() ? 8 : 4);
        loop_back.push_back(0); loop_init.push_back(0);
        prev2 = prev1;
        prev1 = it.dest();
        n++;

        // close the loop: addi x31, x31, -1 ; blt x0, x31, body_start
        if (in_loop_left > 0) begin
          in_loop_left--;
          if (in_loop_left == 0) begin
            items.push_back(null); item_bytes.push_back(8);
            loop_back.push_back(loop_start_idx + 1);   // +1 so 0 means "not a loop close"
            loop_init.push_back(0);
            prev2 = prev1; prev1 = LOOP_REG;
          end
        end
      end

      // --- landing pad so the last forward jumps stay inside the program ---
      for (int i = 0; i < 8; i++) begin
        items.push_back(null); item_bytes.push_back(4);
        loop_back.push_back(0); loop_init.push_back(0);
      end

      // --- then encode, now that every instruction's size is known ---
      for (int i = 0; i < items.size(); i++) begin
        if (loop_init[i] > 0) begin
          words.push_back(rv32i_asm::addi(LOOP_REG, 5'd0, loop_init[i]));
        end else if (loop_back[i] > 0) begin
          int back = 4;                                   // the addi in front of the blt
          for (int j = loop_back[i] - 1; j < i; j++) back += item_bytes[j];
          words.push_back(rv32i_asm::addi(LOOP_REG, LOOP_REG, -1));
          words.push_back(rv32i_asm::blt(5'd0, LOOP_REG, -back));
        end else if (items[i] == null) begin
          words.push_back(rv32i_asm::nop());
        end else begin
          int skip_bytes = 0;
          for (int j = 1; j <= int'(items[i].skip) && (i + j) < items.size(); j++)
            skip_bytes += item_bytes[i + j];
          items[i].encode(skip_bytes, words);
        end
      end

      words.push_back(HALT);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Reference model — executes one instruction per call, no notion of time.
  // Written straight from the ISA spec, deliberately independent of the RTL.
  // ---------------------------------------------------------------------------
  class rv32i_ref_model;
    bit [31:0] pc;
    bit [31:0] x [32];
    bit [31:0] imem [];
    bit [31:0] dmem [];
    int unsigned imem_words, dmem_words;
    longint unsigned num_steps;

    function new(int unsigned imem_words_, int unsigned dmem_words_);
      imem_words = imem_words_;
      dmem_words = dmem_words_;
      imem = new[imem_words];
      dmem = new[dmem_words];
    endfunction

    function void reset(bit [31:0] reset_pc = 32'h0);
      pc = reset_pc;
      num_steps = 0;
      foreach (x[i]) x[i] = 32'h0;
    endfunction

    function retire_t step();
      retire_t   r;
      bit [31:0] instr, rs1v, rs2v, imm_i, imm_s, imm_b, imm_u, imm_j;
      bit [31:0] next_pc, wval, addr, word;
      bit [4:0]  rd, rs1, rs2, sh;
      bit [2:0]  f3;
      bit        wr, taken;
      int unsigned idx, boff;

      instr = imem[(pc >> 2) % imem_words];
      rd    = instr[11:7];
      rs1   = instr[19:15];
      rs2   = instr[24:20];
      f3    = instr[14:12];
      rs1v  = x[rs1];
      rs2v  = x[rs2];
      imm_i = {{20{instr[31]}}, instr[31:20]};
      imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      imm_u = {instr[31:12], 12'b0};
      imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

      next_pc = pc + 4;
      wr      = 0;
      wval    = 0;
      r.pc    = pc;
      r.instr = instr;
      r.mem_wstrb = 4'b0;
      r.mem_addr  = 32'h0;
      r.mem_wdata = 32'h0;

      case (instr[6:0])
        OP_LUI:   begin wr = 1; wval = imm_u; end
        OP_AUIPC: begin wr = 1; wval = pc + imm_u; end
        OP_JAL:   begin wr = 1; wval = pc + 4; next_pc = pc + imm_j; end
        OP_JALR:  begin wr = 1; wval = pc + 4; next_pc = (rs1v + imm_i) & 32'hFFFF_FFFE; end

        OP_BRANCH: begin
          case (f3)
            3'b000:  taken = (rs1v == rs2v);
            3'b001:  taken = (rs1v != rs2v);
            3'b100:  taken = ($signed(rs1v) <  $signed(rs2v));
            3'b101:  taken = ($signed(rs1v) >= $signed(rs2v));
            3'b110:  taken = (rs1v <  rs2v);
            default: taken = (rs1v >= rs2v);
          endcase
          if (taken) next_pc = pc + imm_b;
        end

        OP_LOAD: begin
          addr = rs1v + imm_i;
          word = dmem[(addr >> 2) % dmem_words];
          boff = addr[1:0];
          wr   = 1;
          case (f3)
            3'b000:  begin wval = (word >> (8 * boff)) & 32'hFF;                 // LB
                           if (wval[7])  wval |= 32'hFFFF_FF00; end
            3'b100:  wval = (word >> (8 * boff)) & 32'hFF;                       // LBU
            3'b001:  begin wval = (word >> (16 * (boff / 2))) & 32'hFFFF;        // LH
                           if (wval[15]) wval |= 32'hFFFF_0000; end
            3'b101:  wval = (word >> (16 * (boff / 2))) & 32'hFFFF;              // LHU
            default: wval = word;                                                // LW
          endcase
        end

        OP_STORE: begin
          addr = rs1v + imm_s;
          idx  = (addr >> 2) % dmem_words;
          boff = addr[1:0];
          word = dmem[idx];
          case (f3)
            3'b000: begin                                                        // SB
              word[8*boff +: 8] = rs2v[7:0];
              r.mem_wstrb = 4'b0001 << boff;
            end
            3'b001: begin                                                        // SH
              if (boff >= 2) begin word[31:16] = rs2v[15:0]; r.mem_wstrb = 4'b1100; end
              else           begin word[15:0]  = rs2v[15:0]; r.mem_wstrb = 4'b0011; end
            end
            default: begin word = rs2v; r.mem_wstrb = 4'b1111; end               // SW
          endcase
          dmem[idx]   = word;
          r.mem_addr  = addr;
          r.mem_wdata = word;   // full word after the write; compared per strobed byte
        end

        OP_IMM: begin
          wr = 1;
          sh = instr[24:20];
          case (f3)
            3'b000:  wval = rs1v + imm_i;
            3'b010:  wval = ($signed(rs1v) < $signed(imm_i)) ? 32'd1 : 32'd0;
            3'b011:  wval = (rs1v < imm_i) ? 32'd1 : 32'd0;
            3'b100:  wval = rs1v ^ imm_i;
            3'b110:  wval = rs1v | imm_i;
            3'b111:  wval = rs1v & imm_i;
            3'b001:  wval = rs1v << sh;
            default: wval = instr[30] ? $unsigned($signed(rs1v) >>> sh) : (rs1v >> sh);
          endcase
        end

        OP_REG: begin
          wr = 1;
          sh = rs2v[4:0];
          case (f3)
            3'b000:  wval = instr[30] ? (rs1v - rs2v) : (rs1v + rs2v);
            3'b001:  wval = rs1v << sh;
            3'b010:  wval = ($signed(rs1v) < $signed(rs2v)) ? 32'd1 : 32'd0;
            3'b011:  wval = (rs1v < rs2v) ? 32'd1 : 32'd0;
            3'b100:  wval = rs1v ^ rs2v;
            3'b101:  wval = instr[30] ? $unsigned($signed(rs1v) >>> sh) : (rs1v >> sh);
            3'b110:  wval = rs1v | rs2v;
            default: wval = rs1v & rs2v;
          endcase
        end

        default: ;   // FENCE / ECALL / EBREAK: no architectural effect
      endcase

      r.rd_we    = wr && (rd != 5'd0);
      r.rd       = r.rd_we ? rd : 5'd0;
      r.rd_wdata = r.rd_we ? wval : 32'h0;
      if (r.rd_we) x[rd] = wval;

      pc = next_pc;
      num_steps++;
      return r;
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Functional coverage — named bins with hit counters.
  //
  // Kept as plain counters (rather than only covergroups) so the same numbers
  // come out of every simulator, including ones without covergroup support.
  // ---------------------------------------------------------------------------
  class rv32i_coverage;
    int unsigned hits [string];
    string       order [$];

    function void define_bin(string name);
      if (!hits.exists(name)) begin
        hits[name] = 0;
        order.push_back(name);
      end
    endfunction

    function void hit(string name);
      if (!hits.exists(name)) define_bin(name);
      hits[name]++;
    endfunction

    function int unsigned num_bins();
      return order.size();
    endfunction

    function int unsigned num_hit();
      int unsigned n = 0;
      foreach (order[i]) if (hits[order[i]] > 0) n++;
      return n;
    endfunction

    function real percent();
      if (order.size() == 0) return 0.0;
      return 100.0 * real'(num_hit()) / real'(order.size());
    endfunction

    function void report(bit show_all = 0);
      $display("---------------- functional coverage ----------------");
      foreach (order[i]) begin
        if (show_all || hits[order[i]] == 0)
          $display("  %-34s %0d%s", order[i], hits[order[i]],
                   hits[order[i]] == 0 ? "   <-- NOT HIT" : "");
      end
      $display("  bins hit: %0d / %0d  (%.1f%%)", num_hit(), num_bins(), percent());
      $display("-----------------------------------------------------");
    endfunction
  endclass

endpackage
