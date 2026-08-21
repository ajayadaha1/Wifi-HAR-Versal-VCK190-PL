## overlay_d2_probe.tcl - DISCOVERY ONLY. Prints the v++ postSysLink FLAT BD
## control structure (smartconnect driving mm2s/s_axi_control, its clocks,
## the AIE clk/reset nets, and the CIPS address segments), then ERRORS to abort
## the link BEFORE synthesis. Use this to design the real csi_mux control wiring.
puts "PROBE_D2: ===== BD = [current_bd_design] ====="

puts "PROBE_D2: ---- top-level cells ----"
foreach c [get_bd_cells /*] {
    puts "PROBE_D2: cell $c  vlnv=[get_property VLNV $c]"
}

# --- locate mm2s control interface + the smartconnect that drives it ---
set mm2s [get_bd_cells -quiet /mm2s]
if {$mm2s eq ""} { set mm2s [lindex [get_bd_cells -quiet -filter {VLNV =~ *:mm2s:*}] 0] }
puts "PROBE_D2: mm2s cell = $mm2s"
set ctrlpin [get_bd_intf_pins -quiet $mm2s/s_axi_control]
puts "PROBE_D2: mm2s ctrl pin = $ctrlpin"
set cnet [get_bd_intf_nets -quiet -of $ctrlpin]
puts "PROBE_D2: mm2s ctrl net = $cnet"
foreach p [get_bd_intf_pins -quiet -of $cnet] {
    puts "PROBE_D2:   ctrl-net endpoint pin = $p  (cell [get_property PARENT $p])"
}

# --- for each candidate control smartconnect, dump properties + clocks ---
foreach scn [get_bd_cells -quiet -filter {VLNV =~ *:smartconnect:*}] {
    puts "PROBE_D2: ---- smartconnect $scn ----"
    foreach prop {CONFIG.NUM_SI CONFIG.NUM_MI CONFIG.NUM_CLKS} {
        puts "PROBE_D2:   $prop = [get_property $prop $scn]"
    }
    foreach clkp [get_bd_pins -quiet $scn/aclk*] {
        set n [get_bd_nets -quiet -of $clkp]
        puts "PROBE_D2:   clk pin $clkp -> net $n"
    }
    # which MI ports are used / free
    foreach mip [get_bd_intf_pins -quiet $scn/M*_AXI] {
        set mn [get_bd_intf_nets -quiet -of $mip]
        puts "PROBE_D2:   $mip -> net ${mn}"
    }
}

# --- AIE clk/reset nets (needed for csi_mux aclk/aresetn) ---
set aie [get_bd_cells -filter {VLNV =~ *:ai_engine:*}]
puts "PROBE_D2: aie clk net  = [get_bd_nets -of [get_bd_pins $aie/aclk0]]"
puts "PROBE_D2: aie rstn net = [get_bd_nets -of [get_bd_pins $aie/aresetn0]]"

# --- CIPS / control master address segments (find a free offset) ---
puts "PROBE_D2: ---- address segments (assigned) ----"
foreach seg [get_bd_addr_segs -quiet] {
    puts "PROBE_D2:   seg $seg  off=[get_property -quiet OFFSET $seg] range=[get_property -quiet RANGE $seg]"
}
puts "PROBE_D2: ---- address spaces ----"
foreach sp [get_bd_addr_spaces -quiet] {
    puts "PROBE_D2:   space $sp"
}

error "PROBE_D2: discovery complete - aborting link before synthesis (this is intentional)"
