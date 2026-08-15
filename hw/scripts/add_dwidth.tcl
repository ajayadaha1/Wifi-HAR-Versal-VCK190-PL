# add_dwidth.tcl — insert a 32->8 bit AXIS width converter between the MAC RX
# stream (m_axis_rxd, 4 bytes) and the parser rx (1 byte), both in the 312.5 MHz
# axis_clk domain. Makes the MAC->parser path byte-correct; re-validate + capture.
set fg   /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
set repo /group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo
set out  /group/bcapps/ajayad/master_thesis_rebirth/work/hw/scripts/inline_full_bd.tcl
open_project $fg/_x/link/vivado/vpl/prj/prj.xpr
set_property ip_repo_paths [list $repo $fg/_x/link/int/xo/ip_repo] [current_project]
update_ip_catalog
open_bd_design [lindex [get_files -quiet vitis_design.bd] 0]

create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 rx_dwidth
# replace the direct MAC->parser stream with MAC -> dwidth(32->8) -> parser
set oldnet [get_bd_intf_nets -quiet -of [get_bd_intf_pins axi_eth_0/m_axis_rxd]]
if {[llength $oldnet]} { delete_bd_objs $oldnet }
connect_bd_intf_net [get_bd_intf_pins axi_eth_0/m_axis_rxd] [get_bd_intf_pins rx_dwidth/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins rx_dwidth/M_AXIS] [get_bd_intf_pins csi_udp_parser_0/rx]
connect_bd_net [get_bd_pins VitisRegion/ap_clk_bypass_m]   [get_bd_pins rx_dwidth/aclk]
connect_bd_net [get_bd_pins VitisRegion/ap_rst_n_bypass_m] [get_bd_pins rx_dwidth/aresetn]

save_bd_design
set rc [catch {validate_bd_design} verr]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VERR: $verr" }
write_bd_tcl -force $out
puts "ADD_DWIDTH_DONE"
