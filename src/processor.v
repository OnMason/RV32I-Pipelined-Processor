`timescale 1ns / 1ps
module processor (
    input clk, reset,
    output [31:0] Result
);
wire [6:0] opcode;
wire [6:0] funct7;
wire [2:0] funct3;
wire [1:0] ALUOp;
wire [3:0] ALU_CC;
wire       ALUSrc;
wire       MemtoReg;
wire       RegWrite;
wire       MemRead;
wire       MemWrite;
Controller ctrl (
    .Opcode   (opcode),
    .ALUSrc   (ALUSrc),
    .MemtoReg (MemtoReg),
    .RegWrite (RegWrite),
    .MemRead  (MemRead),
    .MemWrite (MemWrite),
    .ALUOp    (ALUOp)
);
ALUController alu_ctrl (
    .ALUOp     (ALUOp),
    .Funct7    (funct7),
    .Funct3    (funct3),
    .Operation (ALU_CC)
);
data_path dp (
    .clk        (clk),
    .reset      (reset),
    .reg_write  (RegWrite),
    .mem2reg    (MemtoReg),
    .alu_src    (ALUSrc),
    .mem_write  (MemWrite),
    .mem_read   (MemRead),
    .alu_cc     (ALU_CC),
    .opcode     (opcode),
    .funct7     (funct7),
    .funct3     (funct3),
    .alu_result (Result)
);
endmodule