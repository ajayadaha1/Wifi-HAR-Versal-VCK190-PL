# validate_inline.tcl — re-open the grafted design with BOTH IP repos (parser +
# the v++ mm2s/s2mm kernel IPs) so the locked IPs resolve, then validate and
# re-capture the whole design as tcl.
set fg   /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
set repo /group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo
set out  /group/bcapps/ajayad/master_thesis_rebirth/work/hw/scripts/inline_csi_bd.tcl

open_project $fg/_x/link/vivado/vpl/prj/prj.xpr
set_property ip_repo_paths [list $repo $fg/_x/link/int/xo/ip_repo] [current_project]
update_ip_catalog
open_bd_design [lindex [get_files -quiet vitis_design.bd] 0]
puts "LOCKED_BEFORE: [get_bd_cells -quiet -filter {IS_LOCKED==1}]"
puts "EXT_INTF_PORTS: [get_bd_intf_ports]"
# The parser + freed-mm2s external ports inherit 100 MHz; the datapath runs at
# 312.5 MHz. Match FREQ_HZ so the AXI/AXIS clock-domain check passes.
foreach pn [get_bd_intf_ports] {
  if {[llength [get_property -quiet CONFIG.FREQ_HZ $pn]]} {
    if {[string match *rx_0* $pn] || [string match *s_axi_ctrl_0* $pn] || \
        [string match *_s_0* $pn] || [string match *VitisRegion* $pn] || [string match *mm2s* $pn]} {
      catch { set_property CONFIG.FREQ_HZ 312500000 $pn ; puts "SETFREQ $pn" }
    }
  }
}
set rc [catch {validate_bd_design} verr]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VERR: $verr" }
save_bd_design
write_bd_tcl -force $out
puts "WROTE_TCL $out"
close_project
puts "VALIDATE_INLINE_DONE"
