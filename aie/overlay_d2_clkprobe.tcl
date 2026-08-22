## overlay_d2_clkprobe.tcl - dump v++ BD clock sources for the ETH front-end.
puts "CLKPROBE: ===== clock topology ====="
puts "CLKPROBE: --- CIPS_0 pl*_ref_clk / clk pins ---"
foreach p [get_bd_pins -quiet /CIPS_0/*] {
    set n [get_property NAME $p]
    if {[string match -nocase *ref_clk* $n] || [string match -nocase *pl0* $n] || [string match -nocase *pl_clk* $n]} {
        puts "CLKPROBE:   /CIPS_0/$n  dir=[get_property DIR $p]  net=[get_bd_nets -quiet -of $p]"
    }
}
puts "CLKPROBE: --- clk_wizard_0 config + outputs ---"
set cw /clk_wizard_0
catch { puts "CLKPROBE:   CLKOUT_PORT=[get_property CONFIG.CLKOUT_PORT [get_bd_cells $cw]]" }
catch { puts "CLKPROBE:   CLKOUT_REQUESTED_OUT_FREQUENCY=[get_property CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY [get_bd_cells $cw]]" }
foreach p [get_bd_pins -quiet $cw/clk_out*] {
    puts "CLKPROBE:   $p net=[get_bd_nets -quiet -of $p]"
}
foreach p [get_bd_pins -quiet $cw/*] {
    set n [get_property NAME $p]
    if {[string match -nocase *clk_in* $n] || [string match -nocase *locked* $n] || [string match -nocase *reset* $n]} {
        puts "CLKPROBE:   $cw/$n net=[get_bd_nets -quiet -of $p]"
    }
}
puts "CLKPROBE: --- proc_sys_reset cells + their slowest_sync_clk ---"
foreach c [get_bd_cells -quiet -filter {VLNV =~ *:proc_sys_reset:*}] {
    puts "CLKPROBE:   $c clk=[get_bd_nets -quiet -of [get_bd_pins $c/slowest_sync_clk]] rstn=[get_bd_nets -quiet -of [get_bd_pins $c/peripheral_aresetn]]"
}
error "CLKPROBE: done - abort before synth"
