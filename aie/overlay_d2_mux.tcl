## overlay_d2_mux.tcl - v++ postSysLinkOverlayTcl, D2 milestone (a).
## Replaces the D1 axis_register_slice with a real csi_mux (axis_switch) that has
## a WORKING AXI4-Lite control port, so Linux (/dev/mem) can select the AIE source
## between S01=mm2s (DDR test) and S00=parser (live Ethernet, added in D2b).
## ai_engine_0 is left untouched so the co-generated AIE<->PL shim binding holds.
##
## Control is added by widening the platform control smartconnect
## /axi_smc_vip_hier/icn_ctrl (7->8 MI), exposing a new boundary master, and
## wiring it to csi_mux/S_AXI_CTRL @ 0xA406_0000 (free: intc are at A404/A405).
##
## Set env D2_VALIDATE_ONLY=1 to run the BD edits + validate_bd_design and then
## abort BEFORE synthesis (fast ~2.5 min structural check).

set VALIDATE_ONLY [expr {[info exists ::env(D2_VALIDATE_ONLY)] ? 1 : 0}]
puts "OVERLAY_D2: start on [current_bd_design]  (validate_only=$VALIDATE_ONLY)"

# ---- discover the AIE input source (mm2s) + AIE clk/reset nets (as in D1) ----
set aie    [get_bd_cells -filter {VLNV =~ *:ai_engine:*}]
set aiepin [get_bd_intf_pins $aie/S00_AXIS]
set oldnet [get_bd_intf_nets -of $aiepin]
set srcpin ""
foreach p [get_bd_intf_pins -of $oldnet] {
    if {[get_property PATH $p] ne [get_property PATH $aiepin]} { set srcpin $p }
}
if {$srcpin eq ""} { error "OVERLAY_D2: no mm2s source pin on $oldnet" }
set aclk     [get_bd_nets -of [get_bd_pins $aie/aclk0]]
set arstn    [get_bd_nets -of [get_bd_pins $aie/aresetn0]]
set aclkname [get_property NAME $aclk]
set arstname [get_property NAME $arstn]
puts "OVERLAY_D2: mm2s src=$srcpin  clk=$aclkname  rst=$arstname"

# ---- 1) csi_mux (2 SI -> 1 MI, control-register routing) ----
set sw [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_switch:1.1 csi_mux]
set_property -dict [list \
    CONFIG.NUM_SI {2} CONFIG.NUM_MI {1} \
    CONFIG.ROUTING_MODE {1} CONFIG.DECODER_REG {1} ] $sw
delete_bd_objs $oldnet
# S01 = mm2s (DDR test path, matches mux_set.py sel=1); S00 = parser (D2b live).
connect_bd_intf_net $srcpin                             [get_bd_intf_pins csi_mux/S01_AXIS]
connect_bd_intf_net [get_bd_intf_pins csi_mux/M00_AXIS] $aiepin

# ---- 2) control: widen icn_ctrl, expose a boundary master, wire to csi_mux ----
set icn /axi_smc_vip_hier/icn_ctrl
set cur [get_property CONFIG.NUM_MI [get_bd_cells $icn]]
set new [expr {$cur + 1}]
set midx [format "M%02d" $cur]   ;# current count -> next zero-based index (7 -> M07)
puts "OVERLAY_D2: icn_ctrl NUM_MI $cur -> $new, new master $midx"
set_property CONFIG.NUM_MI $new [get_bd_cells $icn]
if {[get_bd_intf_pins -quiet $icn/${midx}_AXI] eq ""} {
    error "OVERLAY_D2: expected $icn/${midx}_AXI after widening"
}
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 \
    /axi_smc_vip_hier/${midx}_AXI
connect_bd_intf_net [get_bd_intf_pins $icn/${midx}_AXI] \
                    [get_bd_intf_pins /axi_smc_vip_hier/${midx}_AXI]
connect_bd_intf_net [get_bd_intf_pins /axi_smc_vip_hier/${midx}_AXI] \
                    [get_bd_intf_pins csi_mux/S_AXI_CTRL]

# ---- 3) clocks + resets (AIE 312.5 MHz domain; icn_ctrl is on the same net) ----
connect_bd_net -net $aclkname  [get_bd_pins csi_mux/aclk] [get_bd_pins csi_mux/s_axi_ctrl_aclk]
connect_bd_net -net $arstname  [get_bd_pins csi_mux/aresetn] [get_bd_pins csi_mux/s_axi_ctrl_aresetn]

# ---- 4) address: pin csi_mux control at 0xA406_0000 (free slot) ----
assign_bd_address -offset 0xA4060000 -range 64K \
    -target_address_space /CIPS_0/M_AXI_FPD [get_bd_addr_segs csi_mux/S_AXI_CTRL/Reg]
foreach s [get_bd_addr_segs -quiet /CIPS_0/M_AXI_FPD/*] {
    if {[string match *csi_mux* $s]} {
        puts "OVERLAY_D2: csi_mux ctrl @ [get_property OFFSET $s] range [get_property RANGE $s]"
    }
}

validate_bd_design
puts "OVERLAY_D2: validate_bd_design PASSED (csi_mux inserted, control wired)"
if {$VALIDATE_ONLY} { error "OVERLAY_D2: validate-only stop (intentional, pre-synth)" }
