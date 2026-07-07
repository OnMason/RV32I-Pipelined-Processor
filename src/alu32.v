`timescale 1ns / 1ps
module alu32 (
    input  [31:0] A,
    input  [31:0] B,
    input  [3:0]  Op,
    output reg [31:0] Result,
    output reg CarryOut,
    output reg Overflow,
    output reg Zero
);
    reg [32:0] temp;
    always @(*) begin
        Result   = 32'b0;
        CarryOut = 1'b0;
        Overflow = 1'b0;
        Zero     = 1'b0;
        temp     = 33'b0;
        case (Op)
            4'b0000: begin
                Result = A & B;
                Zero   = (Result == 32'b0);
            end
            4'b0001: begin
                Result = A | B;
                Zero   = (Result == 32'b0);
            end
            4'b0010: begin
                temp     = {1'b0, A} + {1'b0, B};
                Result   = temp[31:0];
                CarryOut = temp[32];
                Overflow = (A[31] == B[31]) && (Result[31] != A[31]);
                Zero     = (Result == 32'b0);
            end
            4'b0110: begin
                temp     = {1'b0, A} - {1'b0, B};
                Result   = temp[31:0];
                CarryOut = 1'b0;
                Overflow = (A[31] != B[31]) && (Result[31] != A[31]);
                Zero     = (Result == 32'b0);
            end
            4'b0111: begin
                Result = ($signed(A) < $signed(B)) ? 32'b1 : 32'b0;
                Zero   = (Result == 32'b0);
            end
            4'b1100: begin
                Result = ~(A | B);
                Zero   = (Result == 32'b0);
            end
            4'b1111: begin
                Result = (A == B) ? 32'b1 : 32'b0;
                Zero   = (Result == 32'b0);
            end
            default: begin
                temp     = {1'b0, A} + {1'b0, B};
                Result   = temp[31:0];
                CarryOut = temp[32];
                Overflow = (A[31] == B[31]) && (Result[31] != A[31]);
            end
        endcase
    end
endmodule