# inspect2_vpl.tcl — dump clock/reset scalar pins + nets on ai_engine_0 and
# VitisRegion so the parser can reuse the same datapath clock/reset.
set prj /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph/_x/link/vivado/vpl/prj/prj.xpr
open_project $prj
open_bd_design [lindex [get_files -quiet vitis_design.bd] 0]
puts "=== ai_engine_0 scalar pins + nets ==="
foreach p [get_bd_pins -quiet /ai_engine_0/*] {
  set net [get_bd_nets -quiet -of $p]
  puts "AIESCALAR $p dir=[get_property DIR $p] net=$net"
}
puts "=== VitisRegion pins ==="
foreach p [get_bd_pins -quiet /VitisRegion/*] {
  set net [get_bd_nets -quiet -of $p]
  puts "VRPIN $p dir=[get_property DIR $p] net=$net"
}
foreach p [get_bd_intf_pins -quiet /VitisRegion/*] { puts "VRINTF $p [get_property MODE $p]" }
puts "=== clk_wizard_0 outputs ==="
foreach p [get_bd_pins -quiet /clk_wizard_0/*] { puts "CLKW $p dir=[get_property DIR $p] net=[get_bd_nets -quiet -of $p]" }
close_project
puts "INSPECT2_DONE"
