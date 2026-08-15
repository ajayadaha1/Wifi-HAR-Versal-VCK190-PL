# inspect_vpl.tcl — open the v++-generated vitis_design BD and dump its structure
# (cells, AI Engine interface pins, and what drives the AIE PLIO input) so we can
# graft the csi_udp_parser into the datapath.
set prj /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph/_x/link/vivado/vpl/prj/prj.xpr
open_project $prj
set bdf [get_files -quiet *.bd]
puts "BD_FILE=$bdf"
open_bd_design [lindex $bdf 0]
puts "=== CELLS ==="
foreach c [get_bd_cells] { puts "CELL $c [get_property VLNV $c]" }
set aie [get_bd_cells -quiet -filter {VLNV=~*ai_engine*}]
puts "AIE_CELL=$aie"
puts "=== AIE intf pins ==="
foreach p [get_bd_intf_pins -quiet $aie/*] { puts "AIEPIN $p [get_property MODE $p]" }
puts "=== mm2s / s2mm cells ==="
foreach c [get_bd_cells -quiet -filter {VLNV=~*mm2s* || VLNV=~*s2mm*}] { puts "DM $c [get_property VLNV $c]" }
puts "=== interface nets touching AIE ==="
foreach n [get_bd_intf_nets -quiet] {
  set pins [get_bd_intf_pins -quiet -of $n]
  if {[string match *ai_engine* $pins] || [string match *mm2s* $pins] || [string match *s2mm* $pins]} {
    puts "NET $n :: $pins"
  }
}
close_project
puts "INSPECT_DONE"
