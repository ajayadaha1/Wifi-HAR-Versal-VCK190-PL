# synth_full.tcl — synthesize the full inline design (MAC + dwidth + parser + AIE
# + s2mm) to get full-chain PL utilization QoR. External GMII/GT ports are fine
# for synthesis (only impl needs their I/O placement, which requires the GT).
set fg   /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
set repo /group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo
open_project $fg/_x/link/vivado/vpl/prj/prj.xpr
set_property ip_repo_paths [list $repo $fg/_x/link/int/xo/ip_repo] [current_project]
update_ip_catalog
set bdf [lindex [get_files -quiet vitis_design.bd] 0]
generate_target all [get_files $bdf]
set w [make_wrapper -files [get_files $bdf] -top -force]
puts "WRAPPER=$w"
add_files -norecurse -force $w
set_property top vitis_design_wrapper [current_fileset]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH_PROGRESS=[get_property PROGRESS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] eq "100%"} {
  open_run synth_1 -name netlist_1
  report_utilization -file /tmp/inline_full_util.rpt
  puts "UTIL_WRITTEN"
}
puts "SYNTH_FULL_DONE"
