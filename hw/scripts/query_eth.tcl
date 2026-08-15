# query_eth.tcl — discover Ethernet MAC IPs that emit an RX AXI-Stream (to feed
# the parser) and dump the AXI 1G/2.5G Ethernet Subsystem interface pins.
create_project -in_memory -part xcvc1902-vsva2197-2MP-e-S
puts "=== ethernet/mac IP defs ==="
foreach ip [get_ipdefs -all *ethernet* *tri_mode* *temac* *mac*] {
  if {[string match *ethernet* $ip] || [string match *temac* $ip] || [string match *tri_mode* $ip]} { puts "IPDEF $ip" }
}
create_bd_design tmpbd
set vlnv [lindex [lsort -decreasing [get_ipdefs -all *axi_ethernet*]] 0]
puts "AXI_ETH_VLNV=$vlnv"
if {$vlnv ne ""} {
  set eth [create_bd_cell -type ip -vlnv $vlnv axi_eth_0]
  puts "=== axi_ethernet intf pins ==="
  foreach p [get_bd_intf_pins -quiet $eth/*] { puts "ETHINTF $p [get_property MODE $p]" }
  puts "=== key config (PHY types) ==="
  foreach c {CONFIG.PHY_TYPE CONFIG.Physical_Interface CONFIG.PHYADDR CONFIG.ENABLE_AVB CONFIG.MAC_Speed CONFIG.include_io} {
    catch { puts "CFG $c = [get_property $c $eth]" }
  }
}
puts "QUERY_DONE"
