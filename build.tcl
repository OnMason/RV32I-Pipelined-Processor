# build.tcl — recreate the Vivado project and run the self-checking testbench.
#
#   vivado -mode batch -source build.tcl
#   (or: source build.tcl   from the Vivado Tcl console)
#
# Simulation needs no board. The part below is the Basys 3 (XC7A35T) so the same
# project can be synthesised; change it to match your board.

set proj_name rv32i_pipeline
set proj_dir  ./vivado_proj
set part      xc7a35tcpg236-1

create_project $proj_name $proj_dir -part $part -force

# --- design sources (the package must compile first) ---
add_files -norecurse [list \
  ./rtl/rv32i_pkg.sv \
  ./rtl/rv32i_decoder.sv \
  ./rtl/rv32i_imm_gen.sv \
  ./rtl/rv32i_regfile.sv \
  ./rtl/rv32i_alu.sv \
  ./rtl/rv32i_branch_cmp.sv \
  ./rtl/rv32i_forward_unit.sv \
  ./rtl/rv32i_hazard_unit.sv \
  ./rtl/rv32i_core.sv \
  ./rtl/rv32i_imem.sv \
  ./rtl/rv32i_dmem.sv \
  ./rtl/rv32i_top.sv ]
set_property top rv32i_top [current_fileset]

# --- verification sources ---
add_files -fileset sim_1 -norecurse [list \
  ./tb/rv32i_tb_pkg.sv \
  ./tb/rv32i_core_sva.sv \
  ./tb/tb_rv32i.sv ]
set_property top tb_rv32i [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# --- run: directed test + 20 constrained-random programs ---
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.more_options} \
             -value {-testplusarg SEED=1 -testplusarg NTESTS=20} -objects [get_filesets sim_1]
launch_simulation
