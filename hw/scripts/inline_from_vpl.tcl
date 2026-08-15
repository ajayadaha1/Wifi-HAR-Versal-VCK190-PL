# inline_from_vpl.tcl — graft the csi_udp_parser HLS IP into the v++-generated
# vitis_design so the datapath becomes:
#   [eth bytes] -> csi_udp_parser -> AI Engine (feature graph) -> s2mm -> DDR
# The parser's csi_out (32-bit) replaces mm2s as the AI Engine's S00_AXIS driver;
# the parser reuses the AI Engine datapath clock/reset. Saves the whole design
# with write_bd_tcl (single reproducible script).
set fg   /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
set repo /group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo
set out  /group/bcapps/ajayad/master_thesis_rebirth/work/hw/scripts/inline_csi_bd.tcl

open_project $fg/_x/link/vivado/vpl/prj/prj.xpr
set_property ip_repo_paths [list $repo] [current_project]
update_ip_catalog
open_bd_design [lindex [get_files -quiet vitis_design.bd] 0]

puts "STEP: add csi_udp_parser"
create_bd_cell -type ip -vlnv xilinx.com:hls:csi_udp_parser:1.0 csi_udp_parser_0

puts "STEP: reuse AI Engine datapath clock/reset"
connect_bd_net [get_bd_pins csi_udp_parser_0/ap_clk]   [get_bd_pins VitisRegion/ap_clk_bypass_m]
connect_bd_net [get_bd_pins csi_udp_parser_0/ap_rst_n] [get_bd_pins VitisRegion/ap_rst_n_bypass_m]

puts "STEP: re-route mm2s->AIE  =>  parser.csi_out->AIE"
delete_bd_objs [get_bd_intf_nets mm2s_s]
connect_bd_intf_net [get_bd_intf_pins csi_udp_parser_0/csi_out] [get_bd_intf_pins ai_engine_0/S00_AXIS]

puts "STEP: expose parser rx / meta / ctrl / irq + freed mm2s output"
make_bd_intf_pins_external [get_bd_intf_pins csi_udp_parser_0/rx]
make_bd_intf_pins_external [get_bd_intf_pins csi_udp_parser_0/meta_out]
make_bd_intf_pins_external [get_bd_intf_pins csi_udp_parser_0/s_axi_ctrl]
make_bd_pins_external      [get_bd_pins csi_udp_parser_0/interrupt]
make_bd_intf_pins_external [get_bd_intf_pins VitisRegion/s]

# tie off clk_period input if the IP exposes it
set cp [get_bd_pins -quiet csi_udp_parser_0/clk_period]
if {[llength $cp]} {
  set W [expr {[get_property LEFT $cp] + 1}]
  create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 clk_period_const
  set_property -dict [list CONFIG.CONST_WIDTH $W CONFIG.CONST_VAL {10000}] [get_bd_cells clk_period_const]
  connect_bd_net [get_bd_pins clk_period_const/dout] $cp
}

puts "STEP: validate + capture"
assign_bd_address
save_bd_design
set rc [catch {validate_bd_design} verr]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VERR: $verr" }
write_bd_tcl -force $out
puts "WROTE_TCL $out"
close_project
puts "INLINE_FROM_VPL_DONE"
