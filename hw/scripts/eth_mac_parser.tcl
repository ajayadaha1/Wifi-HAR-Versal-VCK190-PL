# eth_mac_parser.tcl — PL Ethernet front-end: AXI 1G/2.5G Ethernet Subsystem
# (GMII MAC) RX stream feeding the CSI UDP parser.
#   axi_ethernet.m_axis_rxd (8-bit RX bytes) -> csi_udp_parser.rx
# PHY/GT-side (gmii, mdio, s_axi, tx, clocks) is left external here; it attaches
# to the baseline gig_ethernet_pcs_pma + gt_quad_base in the full inline design.
# Saved via write_bd_tcl.
set scripts [file normalize [file dirname [info script]]]
create_project -force inline_eth [file normalize $scripts/../inline_eth_hw] -part xcvc1902-vsva2197-2MP-e-S
set_property board_part xilinx.com:vck190:part0:2.2 [current_project]
set_property ip_repo_paths [list [file normalize $scripts/../ip_repo]] [current_project]
update_ip_catalog
create_bd_design eth_mac_parser

puts "STEP: add MAC + parser"
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:8.0 axi_eth_0
create_bd_cell -type ip -vlnv xilinx.com:hls:csi_udp_parser:1.0 csi_udp_parser_0

puts "STEP: MAC RX data stream -> parser.rx"
connect_bd_intf_net [get_bd_intf_pins axi_eth_0/m_axis_rxd] [get_bd_intf_pins csi_udp_parser_0/rx]

puts "STEP: shared 125 MHz AXIS clock (external) drives MAC axis_clk + parser"
create_bd_port -dir I -type clk -freq_hz 125000000 axis_aclk
connect_bd_net [get_bd_ports axis_aclk] [get_bd_pins axi_eth_0/axis_clk]
connect_bd_net [get_bd_ports axis_aclk] [get_bd_pins csi_udp_parser_0/ap_clk]

puts "STEP: expose PHY/GT-side + TX + control as external (deferred to full design)"
foreach i {gmii mdio s_axi s_axis_txd s_axis_txc m_axis_rxs} {
  make_bd_intf_pins_external [get_bd_intf_pins axi_eth_0/$i]
}
foreach p {gtx_clk gmii_rx_clk gmii_tx_clk gmii_gtx_clk s_axi_lite_clk mdio_mdc} {
  catch { make_bd_pins_external [get_bd_pins axi_eth_0/$p] }
}
foreach r {phy_rst_n s_axi_lite_resetn axi_rxd_arstn axi_rxs_arstn axi_txc_arstn axi_txd_arstn} {
  catch { make_bd_pins_external [get_bd_pins axi_eth_0/$r] }
}
make_bd_pins_external [get_bd_pins csi_udp_parser_0/ap_rst_n]
make_bd_pins_external [get_bd_pins csi_udp_parser_0/interrupt]
foreach i {csi_out meta_out s_axi_ctrl} {
  make_bd_intf_pins_external [get_bd_intf_pins csi_udp_parser_0/$i]
}

puts "STEP: validate + capture"
save_bd_design
set rc [catch {validate_bd_design} verr]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VERR: $verr" }
write_bd_tcl -force $scripts/eth_mac_parser_bd.tcl
puts "WROTE_TCL"
close_project
puts "ETH_MAC_PARSER_DONE"
