# fix_full.tcl — match the MAC's external AXIS ports (TX + RX-status) to the
# 312.5 MHz axis_clk domain, then re-validate and re-capture the full inline design.
set fg   /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
set repo /group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo
set out  /group/bcapps/ajayad/master_thesis_rebirth/work/hw/scripts/inline_full_bd.tcl
open_project $fg/_x/link/vivado/vpl/prj/prj.xpr
set_property ip_repo_paths [list $repo $fg/_x/link/int/xo/ip_repo] [current_project]
update_ip_catalog
open_bd_design [lindex [get_files -quiet vitis_design.bd] 0]
foreach pn {s_axis_txd_0 s_axis_txc_0 m_axis_rxs_0} {
  set p [get_bd_intf_ports -quiet $pn]
  if {[llength $p]} { catch { set_property CONFIG.FREQ_HZ 312500000 $p ; puts "SETFREQ $pn" } }
}
save_bd_design
set rc [catch {validate_bd_design} verr]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VERR: $verr" }
write_bd_tcl -force $out
puts "FIX_FULL_DONE"
