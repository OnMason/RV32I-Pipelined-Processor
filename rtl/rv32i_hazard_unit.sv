// -----------------------------------------------------------------------------
// rv32i_hazard_unit — stall and flush control
//
// Load-use hazard
//   A load's data only exists at the end of MEM, so the instruction right
//   behind it cannot get the value by forwarding into EX. Hold PC and IF/ID for
//   one cycle and send a bubble into EX; after that the value forwards from WB.
//
// Control hazard
//   Branches and jumps resolve in EX (predict not-taken). When one redirects
//   the PC, the two younger instructions in IF and ID are on the wrong path and
//   are squashed: 2-cycle penalty for every taken branch or jump.
// -----------------------------------------------------------------------------
module rv32i_hazard_unit (
  input  logic [4:0] rs1_d,
  input  logic [4:0] rs2_d,
  input  logic       mem_read_e,
  input  logic [4:0] rd_e,
  input  logic       pc_redirect_e,
  output logic       stall_f,   // hold PC
  output logic       stall_d,   // hold IF/ID
  output logic       flush_d,   // squash IF/ID
  output logic       flush_e    // squash ID/EX (insert bubble)
);

  logic load_use;
  assign load_use = mem_read_e && (rd_e != 5'd0) &&
                    ((rd_e == rs1_d) || (rd_e == rs2_d));

  assign stall_f = load_use;
  assign stall_d = load_use;
  assign flush_d = pc_redirect_e;
  assign flush_e = load_use || pc_redirect_e;

endmodule
