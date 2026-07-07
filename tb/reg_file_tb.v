`timescale 1ns / 1ps

module reg_file_tb;

reg clk_tb;
reg reset_tb;
reg rg_wrt_en_tb;
reg [4:0] rg_wrt_addr_tb;
reg [4:0] rg_rd_addr1_tb;
reg [4:0] rg_rd_addr2_tb;
reg [31:0] rg_wrt_data_tb;
wire [31:0] rg_rd_data1_tb;
wire [31:0] rg_rd_data2_tb;

RegFile uut (
    .clk(clk_tb),
    .reset(reset_tb),
    .rg_wrt_en(rg_wrt_en_tb),
    .rg_wrt_addr(rg_wrt_addr_tb),
    .rg_rd_addr1(rg_rd_addr1_tb),
    .rg_rd_addr2(rg_rd_addr2_tb),
    .rg_wrt_data(rg_wrt_data_tb),
    .rg_rd_data1(rg_rd_data1_tb),
    .rg_rd_data2(rg_rd_data2_tb)
);

// 20 ns clock period
always #10 clk_tb = ~clk_tb;

initial begin
    clk_tb = 1'b0;

    // Step 1: assert reset and verify both read ports output zero
    reset_tb = 1'b1;
    rg_wrt_en_tb = 1'b0;
    rg_wrt_addr_tb = 5'd0;
    rg_wrt_data_tb = 32'h00000000;
    rg_rd_addr1_tb = 5'd18;
    rg_rd_addr2_tb = 5'd5;
    #5;

    // Step 2: deassert reset, enable write, write a value to register 18
    reset_tb = 1'b0;
    rg_wrt_en_tb = 1'b1;
    rg_wrt_addr_tb = 5'd18;
    rg_wrt_data_tb = 32'h12345678;
    rg_rd_addr1_tb = 5'd18;
    rg_rd_addr2_tb = 5'd0;
    #20;

    // Step 3: write a second value to register 5 and read both ports
    rg_wrt_addr_tb = 5'd5;
    rg_wrt_data_tb = 32'hABCDEF01;
    rg_rd_addr1_tb = 5'd18;
    rg_rd_addr2_tb = 5'd5;
    #20;

    // Step 4: assert reset again and verify both outputs return to zero
    reset_tb = 1'b1;
    #5;

    $finish;
end

endmodule