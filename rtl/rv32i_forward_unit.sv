// -----------------------------------------------------------------------------
// rv32i_forward_unit — data-hazard bypass select for the two EX-stage operands
//
// The instruction in EX may need a register that an older instruction has
// computed but not yet written back. Priority goes to the youngest producer:
//
//   EX/MEM (one instruction ahead)  ->  FWD_MEM
//   MEM/WB (two instructions ahead) ->  FWD_WB
//   otherwise                       ->  FWD_NONE (register-file value from ID)
//
// A load in EX/MEM has no data yet (its "result" is still an address); the
// hazard unit guarantees that case never reaches here by stalling one cycle.
// -----------------------------------------------------------------------------
module rv32i_forward_unit
  import rv32i_pkg::*;
(
  input  logic [4:0] rs1_e,
  input  logic [4:0] rs2_e,
  input  logic       reg_write_m,
  input  logic [4:0] rd_m,
  input  logic       reg_write_w,
  input  logic [4:0] rd_w,
  output fwd_sel_e   fwd_a,
  output fwd_sel_e   fwd_b
);

  always_comb begin
    if      (reg_write_m && rd_m != 5'd0 && rd_m == rs1_e) fwd_a = FWD_MEM;
    else if (reg_write_w && rd_w != 5'd0 && rd_w == rs1_e) fwd_a = FWD_WB;
    else                                                   fwd_a = FWD_NONE;

    if      (reg_write_m && rd_m != 5'd0 && rd_m == rs2_e) fwd_b = FWD_MEM;
    else if (reg_write_w && rd_w != 5'd0 && rd_w == rs2_e) fwd_b = FWD_WB;
    else                                                   fwd_b = FWD_NONE;
  end

endmodule
