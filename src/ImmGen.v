`timescale 1ns / 1ps
module ImmGen(
    input  [31:0] InstCode,
    output reg [31:0] ImmOut
);
always @(*) begin
    case (InstCode[6:0])
        7'b0000011:
            ImmOut = {{20{InstCode[31]}}, InstCode[31:20]};
        7'b0010011:
            ImmOut = {{20{InstCode[31]}}, InstCode[31:20]};
        7'b0100011:
            ImmOut = {{20{InstCode[31]}}, InstCode[31:25], InstCode[11:7]};
        default:
            ImmOut = 32'b0;
    endcase
end
endmodule