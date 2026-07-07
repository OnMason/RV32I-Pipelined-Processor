`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: InstMem
// Author: Mahmoud Elfar
// Date: 5/27/2026
// Project: EECS 31L - Spring 2026
// Revision 0.01 - File Created
// Revision 0.02 - Inserted NOP at address 0x00
// Additional Comments:
//   First instruction must always be NOP for a synchronous reset to work
//////////////////////////////////////////////////////////////////////////////////

module InstMem(
  input [7:0] addr,
  output wire [31:0] instruction
    );

reg [31:0] memory [63:0];
assign instruction =  memory [addr[7:2]];  

initial begin
    memory[0]   = 32'h00000000; // NOP
    memory[1+0] = 32'h00007033; // and r0,r0,r0             x"0" 
    memory[1+1] = 32'h00100093; // addi r1,r0, 1            x"1" 
    memory[1+2] = 32'h00200113; // addi r2,r0, 2            x"2"
    memory[1+3] = 32'h00308193; // addi r3,r1, 3            x"4"  
    memory[1+4] = 32'h00408213; // addi r4,r1, 4            x"5"
    memory[1+5] = 32'h00510293; // addi r5,r2, 5            x"7"
    memory[1+6] = 32'h00610313; // addi r6,r2, 6            x"8"
    memory[1+7] = 32'h00718393; // addi r7,r3, 7            x"B"
    memory[1+8] = 32'h00208433; // add  r8,r1,r2            x"3"
    memory[1+9] = 32'h404404b3; // sub  r9,r8,r4            x"fffffffe"
    memory[1+10] = 32'h00317533; // and  r10,r2,r3          x"0"
    memory[1+11] = 32'h0041e5b3; // or   r11,r3,r4          x"5"
    memory[1+12] = 32'h0041a633; // if r3 <r4  r12 = 1        x"1"
    memory[1+13] = 32'h007346b3; // nor  r13,r6,r7        x"fffffff4"
    memory[1+14] = 32'h4d34f713; // andi r14,r9, "4D3"      x"4D2"
    memory[1+15] = 32'h8d35e793; // ori  r15,r11, "8d3"       x"fffff8d7"
    memory[1+16] = 32'h4d26a813; // if r13 < x"4D2"  r16 = 1     x"1"
    memory[1+17] = 32'h4d244893; // nori r17,r8, x"4D2"         x"fffffb2C"
    memory[1+18] = 32'h02b0_2823;  // sw  r11, 48(r0)             x"
    memory[1+19] = 32'h0300_2603;  // lw  r12, 48(r0)
end

endmodule