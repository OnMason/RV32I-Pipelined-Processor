module data_path #(
    parameter PC_W = 8,
    parameter INS_W = 32,
    parameter RF_ADDRESS = 5,
    parameter DATA_W = 32,
    parameter DM_ADDRESS = 9,
    parameter ALU_CC_W = 4

)
(

    input                  clk,
    input                  reset,
    input                  reg_write,
    input                  mem2reg,
    input                  alu_src,
    input                  mem_write,
    input                  mem_read,
    input  [ALU_CC_W-1:0]  alu_cc,
    output          [6:0]  opcode,
    output          [6:0]  funct7,
    output          [2:0]  funct3,
    output   [DATA_W-1:0]  alu_result

);

    wire [PC_W-1:0]       pc_out;
    wire [PC_W-1:0]       pc_plus4;
    wire [INS_W-1:0]      instruction;
    wire [DATA_W-1:0]     rg_rd_data1;
    wire [DATA_W-1:0]     rg_rd_data2;
    wire [DATA_W-1:0]     imm_out;
    wire [DATA_W-1:0]     alu_b;
    wire [DATA_W-1:0]     alu_out;
    wire                  zero;
    wire                  overflow;
    wire                  carry_out;
    wire [DATA_W-1:0]     dm_read_data;
    wire [DATA_W-1:0]     wb_data;
    wire [RF_ADDRESS-1:0] rd_rg_wrt_wire;
    wire [RF_ADDRESS-1:0] rd_rg_addr_wire1;
    wire [RF_ADDRESS-1:0] rd_rg_addr_wire2;
    assign opcode           = instruction[6:0];
    assign funct3           = instruction[14:12];
    assign funct7           = instruction[31:25];
    assign rd_rg_wrt_wire   = instruction[11:7];
    assign rd_rg_addr_wire1 = instruction[19:15];
    assign rd_rg_addr_wire2 = instruction[24:20];
    assign alu_result       = alu_out;
    assign pc_plus4         = pc_out + 8'd4;

    FlipFlop pc_reg (
        .clk   (clk),
        .reset (reset),
        .d     (pc_plus4),
        .q     (pc_out)
    );

    InstMem im (
        .addr        (pc_out),
        .instruction (instruction)

    );

    RegFile rf (
        .clk         (clk),
        .reset       (reset),
        .rg_wrt_en   (reg_write),
        .rg_wrt_addr (rd_rg_wrt_wire),
        .rg_rd_addr1 (rd_rg_addr_wire1),
        .rg_rd_addr2 (rd_rg_addr_wire2),
        .rg_wrt_data (wb_data),
        .rg_rd_data1 (rg_rd_data1),
        .rg_rd_data2 (rg_rd_data2)

    );

    ImmGen ig (
        .InstCode (instruction),
        .ImmOut   (imm_out)

    );

    mux_32 alu_mux (

        .s  (alu_src),
        .d0 (rg_rd_data2),
        .d1 (imm_out),
        .y  (alu_b)

    );

    alu32 alu (

        .A        (rg_rd_data1),
        .B        (alu_b),
       .Op       (alu_cc),
        .Result   (alu_out),
        .CarryOut (carry_out),
        .Zero     (zero),
        .Overflow (overflow)

    );

    DataMem dm (

        .MemRead    (mem_read),
        .MemWrite   (mem_write),
        .addr       (alu_out[DM_ADDRESS-1:0]),
        .write_data (rg_rd_data2),
        .read_data  (dm_read_data)

    );

    mux_32 wb_mux (

        .s  (mem2reg),
        .d0 (alu_out),
        .d1 (dm_read_data),
        .y  (wb_data)

    );

endmodule