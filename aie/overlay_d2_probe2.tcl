## overlay_d2_probe2.tcl - DISCOVERY 2: dump the control hierarchy internals.
puts "PROBE2: ===== hierarchy /axi_smc_vip_hier ====="
foreach c [get_bd_cells -quiet /axi_smc_vip_hier/*] {
    puts "PROBE2: cell $c  vlnv=[get_property -quiet VLNV $c]"
}
puts "PROBE2: ---- hierarchy MASTER intf pins (M*_AXI) ----"
foreach p [get_bd_intf_pins -quiet /axi_smc_vip_hier/*] {
    set mode [get_property -quiet MODE $p]
    puts "PROBE2:   pin $p mode=$mode"
}
puts "PROBE2: ---- clock/reset pins on hierarchy ----"
foreach p [get_bd_pins -quiet /axi_smc_vip_hier/*] {
    puts "PROBE2:   pin $p  net=[get_bd_nets -quiet -of $p]"
}
# each icn_ctrl smartconnect inside
foreach scn [get_bd_cells -quiet -filter {VLNV =~ *:smartconnect:*} /axi_smc_vip_hier/*] {
    puts "PROBE2: ---- smartconnect $scn ----"
    foreach prop {CONFIG.NUM_SI CONFIG.NUM_MI CONFIG.NUM_CLKS} {
        puts "PROBE2:   $prop=[get_property -quiet $prop $scn]"
    }
    foreach mip [get_bd_intf_pins -quiet $scn/M*_AXI] {
        puts "PROBE2:   $mip -> [get_bd_intf_nets -quiet -of $mip]"
    }
    foreach mip [get_bd_intf_pins -quiet $scn/S*_AXI] {
        puts "PROBE2:   $mip <- [get_bd_intf_nets -quiet -of $mip]"
    }
    foreach clkp [get_bd_pins -quiet $scn/aclk*] {
        puts "PROBE2:   clk $clkp -> [get_bd_nets -quiet -of $clkp]"
    }
}
# Which master actually drives mm2s control, trace inside: what feeds icn_ctrl S?
puts "PROBE2: ---- mm2s control seg mapping in M_AXI_FPD ----"
foreach seg [get_bd_addr_segs -quiet /CIPS_0/M_AXI_FPD/*] {
    puts "PROBE2:   $seg off=[get_property -quiet OFFSET $seg] range=[get_property -quiet RANGE $seg]"
}
error "PROBE2: done - abort before synth"
