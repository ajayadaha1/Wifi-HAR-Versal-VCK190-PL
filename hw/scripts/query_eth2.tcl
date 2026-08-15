# query_eth2.tcl — dump the AXI 1G/2.5G Ethernet Subsystem (axi_ethernet:8.0)
# interfaces, clock/reset pins, and PHY-type options to plan MAC -> parser wiring.
create_project -in_memory -part xcvc1902-vsva2197-2MP-e-S
set_property board_part xilinx.com:vck190:part0:2.2 [current_project]
create_bd_design tmpbd
set eth [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:8.0 axi_eth_0]
puts "=== axi_ethernet intf pins ==="
foreach p [get_bd_intf_pins -quiet $eth/*] { puts "ETHINTF [get_property MODE $p] $p" }
puts "=== axi_ethernet clock/reset pins ==="
foreach p [get_bd_pins -quiet $eth/*] {
  set t [get_property TYPE $p]
  if {$t eq "clk" || $t eq "rst"} { puts "ETHPIN $t $p" }
}
puts "=== PHY_TYPE options ==="
catch { puts "PHY_TYPE_VALS = [list_property_value CONFIG.PHY_TYPE $eth]" }
catch { puts "PHYTYPE_now = [get_property CONFIG.PHY_TYPE $eth]" }
puts "QUERY2_DONE"
