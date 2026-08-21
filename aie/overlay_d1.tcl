## overlay_d1.tcl - v++ postSysLinkOverlayTcl, milestone D1 (register-slice variant).
## Runs on v++'s FLAT postSysLink BD. Inserts an axis_register_slice on
## ai_engine_0's input net (no control AXI needed), leaving ai_engine_0 untouched
## so the co-generated AIE<->PL binding is preserved. Proves: v++ overlay flow +
## PL element inserted before the AIE + AIE still consumes on silicon.
puts "OVERLAY_D1: start on [current_bd_design]"
set aie [get_bd_cells -filter {VLNV =~ *:ai_engine:*}]
set aiepin [get_bd_intf_pins $aie/S00_AXIS]
set oldnet [get_bd_intf_nets -of $aiepin]
set srcpin ""
foreach p [get_bd_intf_pins -of $oldnet] {
    if {[get_property PATH $p] ne [get_property PATH $aiepin]} { set srcpin $p }
}
if {$srcpin eq ""} { error "OVERLAY_D1: no mm2s source pin on $oldnet" }
puts "OVERLAY_D1: mm2s source = $srcpin (net $oldnet)"
set aclk  [get_bd_nets -of [get_bd_pins $aie/aclk0]]
set arstn [get_bd_nets -of [get_bd_pins $aie/aresetn0]]
set aclkname [get_property NAME $aclk]
set arstname [get_property NAME $arstn]
puts "OVERLAY_D1: clk=$aclkname rst=$arstname"

set rs [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 csi_slice]
delete_bd_objs $oldnet
connect_bd_intf_net $srcpin                              [get_bd_intf_pins csi_slice/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins csi_slice/M_AXIS]  $aiepin
connect_bd_net -net $aclkname  [get_bd_pins csi_slice/aclk]
connect_bd_net -net $arstname  [get_bd_pins csi_slice/aresetn]

validate_bd_design
puts "OVERLAY_D1: done, validate_bd_design PASSED (register_slice inserted)"
