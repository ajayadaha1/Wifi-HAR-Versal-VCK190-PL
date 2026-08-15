# inline_full.tcl — merge the PL Ethernet MAC into the inline AIE datapath, giving
# the complete Arch-B chain:
#   [GT/PCS-PMA] -> axi_ethernet (MAC) -> csi_udp_parser -> ai_engine -> s2mm -> DDR
# The MAC's AXIS domain shares the 312.5 MHz AIE datapath clock (the subsystem does
# the GMII<->AXIS CDC internally); its GMII/GT/MDIO/control/TX are left external to
# attach to the baseline gig_ethernet_pcs_pma + gt_quad_base + CIPS. write_bd_tcl saves it.
set fg   /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
set repo /group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo
set out  /group/bcapps/ajayad/master_thesis_rebirth/work/hw/scripts/inline_full_bd.tcl

open_project $fg/_x/link/vivado/vpl/prj/prj.xpr
set_property ip_repo_paths [list $repo $fg/_x/link/int/xo/ip_repo] [current_project]
update_ip_catalog
open_bd_design [lindex [get_files -quiet vitis_design.bd] 0]

puts "STEP: add axi_ethernet MAC"
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:8.0 axi_eth_0

puts "STEP: replace parser external rx port with MAC RX stream"
delete_bd_objs [get_bd_intf_ports rx_0]
connect_bd_intf_net [get_bd_intf_pins axi_eth_0/m_axis_rxd] [get_bd_intf_pins csi_udp_parser_0/rx]

puts "STEP: MAC AXIS domain on the AIE datapath clock (internal GMII<->AXIS CDC)"
connect_bd_net [get_bd_pins VitisRegion/ap_clk_bypass_m] [get_bd_pins axi_eth_0/axis_clk]

puts "STEP: expose MAC PHY/GT + TX + control external (attach to PCS-PMA/GT/CIPS later)"
foreach i {gmii mdio s_axi s_axis_txd s_axis_txc m_axis_rxs} {
  make_bd_intf_pins_external [get_bd_intf_pins axi_eth_0/$i]
}
foreach p {gtx_clk gmii_rx_clk gmii_tx_clk gmii_gtx_clk s_axi_lite_clk mdio_mdc} {
  catch { make_bd_pins_external [get_bd_pins axi_eth_0/$p] }
}
foreach r {phy_rst_n s_axi_lite_resetn axi_rxd_arstn axi_rxs_arstn axi_txc_arstn axi_txd_arstn} {
  catch { make_bd_pins_external [get_bd_pins axi_eth_0/$r] }
}

puts "STEP: set external Ethernet clock ports to 125 MHz"
foreach cp {gtx_clk gmii_rx_clk gmii_tx_clk gmii_gtx_clk} {
  set port [get_bd_ports -quiet ${cp}_0]
  if {[llength $port]} { catch { set_property CONFIG.FREQ_HZ 125000000 $port } }
}

puts "STEP: validate + capture"
save_bd_design
set rc [catch {validate_bd_design} verr]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VERR: $verr" }
write_bd_tcl -force $out
puts "WROTE_TCL $out"
close_project
puts "INLINE_FULL_DONE"
