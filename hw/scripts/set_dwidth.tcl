# set_dwidth.tcl — force the RX width converter output to 1 byte (8-bit) so it
# exactly matches the parser byte stream, then re-validate + re-capture.
set fg   /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
set repo /group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo
set out  /group/bcapps/ajayad/master_thesis_rebirth/work/hw/scripts/inline_full_bd.tcl
open_project $fg/_x/link/vivado/vpl/prj/prj.xpr
set_property ip_repo_paths [list $repo $fg/_x/link/int/xo/ip_repo] [current_project]
update_ip_catalog
open_bd_design [lindex [get_files -quiet vitis_design.bd] 0]
set_property CONFIG.M_TDATA_NUM_BYTES {1} [get_bd_cells rx_dwidth]
save_bd_design
set rc [catch {validate_bd_design} verr]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VERR: $verr" }
write_bd_tcl -force $out
puts "SET_DWIDTH_DONE"
