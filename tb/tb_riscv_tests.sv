// -----------------------------------------------------------------------------
// tb_riscv_tests — runs one official riscv-tests rv32ui image on the core
//
// This is an independent check: the tests are self-checking programs written
// by the RISC-V project, so they do not rely on this repo's reference model.
// A test parks in a jump-to-self with x26 = 0x600D (pass) or 0xBAD (fail, with
// the failing case number in x27). See tests/riscv-tests/env/riscv_test.h.
//
// Plusargs:  +TEXT=<hex>  +DATA=<hex>  +NAME=<test name>
// -----------------------------------------------------------------------------
module tb_riscv_tests;

  localparam int          IMEM_WORDS = 4096;
  localparam int          DMEM_WORDS = 4096;
  localparam int          DATA_BASE  = 32'h2000 / 4;   // word index of .data in the RAM
  localparam logic [31:0] HALT       = 32'h0000_006f;

  logic clk = 1'b0;
  logic reset = 1'b1;
  always #5 clk = ~clk;

  logic        ret_valid;
  logic [31:0] ret_pc, ret_instr;

  rv32i_top #(
    .IMEM_WORDS (IMEM_WORDS),
    .DMEM_WORDS (DMEM_WORDS)
  ) dut (
    .clk           (clk),
    .reset         (reset),
    .ret_valid     (ret_valid),
    .ret_pc        (ret_pc),
    .ret_instr     (ret_instr),
    .ret_rd_we     (),
    .ret_rd        (),
    .ret_rd_wdata  (),
    .ret_mem_wstrb (),
    .ret_mem_addr  (),
    .ret_mem_wdata ()
  );

  string text_file, data_file, name;
  int    cycles;

  initial begin
    if (!$value$plusargs("TEXT=%s", text_file)) $fatal(1, "missing +TEXT=<hex>");
    if (!$value$plusargs("DATA=%s", data_file)) $fatal(1, "missing +DATA=<hex>");
    if (!$value$plusargs("NAME=%s", name))      name = text_file;

    $readmemh(text_file, dut.u_imem.mem);
    $readmemh(data_file, dut.u_dmem.mem, DATA_BASE);

    repeat (3) @(negedge clk);
    reset = 1'b0;

    cycles = 0;
    forever begin
      @(negedge clk);
      cycles++;
      if (ret_valid && ret_instr == HALT) begin
        if (dut.u_core.u_regfile.regs[26] == 32'h0000_600D)
          $display("[PASS] rv32ui-%-8s %0d cycles", name, cycles);
        else
          $display("[FAIL] rv32ui-%-8s failing case #%0d (x26=%h)", name,
                   dut.u_core.u_regfile.regs[27], dut.u_core.u_regfile.regs[26]);
        $finish;
      end
      if (cycles > 200000) begin
        $display("[FAIL] rv32ui-%-8s timeout at pc=%h", name, ret_pc);
        $finish;
      end
    end
  end

endmodule
