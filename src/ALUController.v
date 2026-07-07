`timescale 1ns / 1ps
module ALUController (
    ALUOp, Funct7, Funct3, Operation
);
input  [1:0] ALUOp;
input  [6:0] Funct7;
input  [2:0] Funct3;
output reg [3:0] Operation;
always @(*) begin
    case (ALUOp)
        2'b10: begin
            case (Funct3)
                3'b000: begin
                    if (Funct7 == 7'b0100000)
                        Operation = 4'b0110;
                    else
                        Operation = 4'b0010;
                end
                3'b010: Operation = 4'b0111;
                3'b100: Operation = 4'b1100;
                3'b110: Operation = 4'b0001;
                3'b111: Operation = 4'b0000;
                default: Operation = 4'b0000;
            endcase
        end
        2'b00: begin
            case (Funct3)
                3'b000: Operation = 4'b0010;
                3'b010: Operation = 4'b0111;
                3'b100: Operation = 4'b1100;
                3'b110: Operation = 4'b0001;
                3'b111: Operation = 4'b0000;
                default: Operation = 4'b0000;
            endcase
        end
        2'b01: Operation = 4'b0010;
        default: Operation = 4'b0000;
    endcase
end
endmodule