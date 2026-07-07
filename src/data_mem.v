module DataMem(MemRead, MemWrite, addr, write_data, read_data);

input MemRead;
input MemWrite;
input [8:0] addr;
input [31:0] write_data;
output reg [31:0] read_data;
reg [31:0] memory [127:0];

always @ (*) begin

    if(MemWrite == 1)
        memory[addr[8:2]] = write_data;
    else if (MemRead == 1)
        read_data = memory[addr[8:2]];
    else 
        read_data = 32'b0;
end

endmodule

