# build.tcl — recreate the Vivado project and run behavioral simulation.
# Usage:  vivado -mode batch -source build.tcl
#         (or: source build.tcl  from the Vivado Tcl console)
#
# This is a simulation-focused flow — no board/part is required for XSim.
# If you later synthesize to an FPGA, add `-part <device>` to create_project.

set proj_name rv32i
set proj_dir  ./vivado_proj

create_project $proj_name $proj_dir -force

# --- design sources ---
add_files -norecurse [glob ./src/*.v]

# --- testbenches ---
add_files -fileset sim_1 -norecurse [glob ./tb/*.v]
# To simulate the register file in isolation, set its testbench as the sim top:
# set_property top reg_file_tb [get_filesets sim_1]

set_property top processor [current_fileset]
update_compile_order -fileset sources_1

# --- run behavioral simulation ---
launch_simulation
run 400 ns
