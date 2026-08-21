## overlay_d2_eth.tcl - v++ postSysLinkOverlayTcl, D2 milestone (b): LIVE path.
## Extends overlay_d2_mux.tcl by wiring the Ethernet CSI front-end into
## csi_mux/S00 (the live source), keeping S01=mm2s (DDR test) as the fallback.
##
## STATUS: the csi_mux + control half (as in overlay_d2_mux.tcl) is proven.
## The Ethernet front-end (GT PHY + axi_ethernet MAC + rx CDC/dwidth + parser)
## is ported here from ../../hw/scripts/inline_design.tcl.  Two pieces cannot be
## added by BD-Tcl alone and MUST be supplied to the v++ link (see link script):
##   (1) the custom GT wrapper RTL  hw/hdl/eth_gt_phy.v   (module reference), and
##   (2) the GT wizard IP           hw/ip/csi_eth_gtwiz.xci,
##   (3) SFP0 pin constraints       hw/constraints/inline.xdc (K46/K47 rx,
##       H41/H42 tx, L39/L40 refclk) -> passed via --advanced.param or a .xo.
## These are injected via link_cogen_d2eth.sh using --vivado.prop /
## --advanced.param before this overlay runs.  This overlay only does BD wiring.
##
## Set env D2_VALIDATE_ONLY=1 for the fast pre-synth structural check.

set VALIDATE_ONLY [expr {[info exists ::env(D2_VALIDATE_ONLY)] ? 1 : 0}]
puts "OVERLAY_D2ETH: start on [current_bd_design] (validate_only=$VALIDATE_ONLY)"

# ---------- shared discovery (mm2s source, AIE clk/reset) ----------
set aie    [get_bd_cells -filter {VLNV =~ *:ai_engine:*}]
set aiepin [get_bd_intf_pins $aie/S00_AXIS]
set oldnet [get_bd_intf_nets -of $aiepin]
set srcpin ""
foreach p [get_bd_intf_pins -of $oldnet] {
    if {[get_property PATH $p] ne [get_property PATH $aiepin]} { set srcpin $p }
}
if {$srcpin eq ""} { error "OVERLAY_D2ETH: no mm2s source pin" }
set aclkname [get_property NAME [get_bd_nets -of [get_bd_pins $aie/aclk0]]]
set arstname [get_property NAME [get_bd_nets -of [get_bd_pins $aie/aresetn0]]]
puts "OVERLAY_D2ETH: mm2s=$srcpin clk=$aclkname rst=$arstname"

# =========================================================================
# 1) csi_mux + control  (identical to overlay_d2_mux.tcl; S00 now = live)
# =========================================================================
set sw [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_switch:1.1 csi_mux]
set_property -dict {CONFIG.NUM_SI 2 CONFIG.NUM_MI 1 CONFIG.ROUTING_MODE 1 CONFIG.DECODER_REG 1} $sw
delete_bd_objs $oldnet
connect_bd_intf_net $srcpin                             [get_bd_intf_pins csi_mux/S01_AXIS]
connect_bd_intf_net [get_bd_intf_pins csi_mux/M00_AXIS] $aiepin

set icn /axi_smc_vip_hier/icn_ctrl
set cur [get_property CONFIG.NUM_MI [get_bd_cells $icn]]
set midx [format "M%02d" $cur]
set_property CONFIG.NUM_MI [expr {$cur+1}] [get_bd_cells $icn]
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 /axi_smc_vip_hier/${midx}_AXI
connect_bd_intf_net [get_bd_intf_pins $icn/${midx}_AXI] [get_bd_intf_pins /axi_smc_vip_hier/${midx}_AXI]
connect_bd_intf_net [get_bd_intf_pins /axi_smc_vip_hier/${midx}_AXI] [get_bd_intf_pins csi_mux/S_AXI_CTRL]
connect_bd_net -net $aclkname [get_bd_pins csi_mux/aclk] [get_bd_pins csi_mux/s_axi_ctrl_aclk]
connect_bd_net -net $arstname [get_bd_pins csi_mux/aresetn] [get_bd_pins csi_mux/s_axi_ctrl_aresetn]
assign_bd_address -offset 0xA4060000 -range 64K -target_address_space /CIPS_0/M_AXI_FPD \
    [get_bd_addr_segs csi_mux/S_AXI_CTRL/Reg]

# small helper: grab one more icn_ctrl master, return its top boundary pin
proc icn_next_master {} {
    set icn /axi_smc_vip_hier/icn_ctrl
    set cur [get_property CONFIG.NUM_MI [get_bd_cells $icn]]
    set midx [format "M%02d" $cur]
    set_property CONFIG.NUM_MI [expr {$cur+1}] [get_bd_cells $icn]
    create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 /axi_smc_vip_hier/${midx}_AXI
    connect_bd_intf_net [get_bd_intf_pins $icn/${midx}_AXI] [get_bd_intf_pins /axi_smc_vip_hier/${midx}_AXI]
    return /axi_smc_vip_hier/${midx}_AXI
}

# =========================================================================
# 2) CSI parser -> csi_mux/S00  (HLS IP from hw/ip_repo, added via ip_repo_paths)
# =========================================================================
set parser [create_bd_cell -type ip -vlnv xilinx.com:hls:csi_udp_parser:1.0 csi_udp_parser_0]
connect_bd_intf_net [get_bd_intf_pins csi_udp_parser_0/csi_out] [get_bd_intf_pins csi_mux/S00_AXIS]
connect_bd_net -net $aclkname [get_bd_pins csi_udp_parser_0/ap_clk]
connect_bd_net -net $arstname [get_bd_pins csi_udp_parser_0/ap_rst_n]
# parser control AXI (own icn_ctrl master + address just above csi_mux)
set pctl [icn_next_master]
connect_bd_intf_net [get_bd_intf_pins $pctl] [get_bd_intf_pins csi_udp_parser_0/s_axi_ctrl]
assign_bd_address -offset 0xA4020000 -range 64K -target_address_space /CIPS_0/M_AXI_FPD \
    [get_bd_addr_segs csi_udp_parser_0/s_axi_ctrl/Reg]

# =========================================================================
# 3) Ethernet MAC + GT PHY + RX clock-crossing/width  (ports the inline chain)
#    axi_eth_0 (1000BASE-X) -> rx_cdc_fifo(async 100->312.5) -> rx_dwidth(->8b)
#    -> csi_udp_parser_0/rx ;  GT wrapper eth_gt_phy_0 drives the SGMII/1000BX PHY.
#    NOTE: requires eth_gt_phy.v + csi_eth_gtwiz.xci in the v++ project (link
#    script) and SFP0 XDC. Guarded so the structural check of (1)+(2) can run
#    even before the RTL/IP are injected.
# =========================================================================
set ETH_ENABLE [expr {[info exists ::env(D2_ETH_FULL)] ? 1 : 0}]
if {$ETH_ENABLE} {
    set mac  [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:8.0 axi_eth_0]
    set_property -dict [list CONFIG.PHY_TYPE {1000BaseX} CONFIG.ENABLE_LVDS {false} \
        CONFIG.gt_type {GTY} CONFIG.SupportLevel {0} CONFIG.GTinEx {true} \
        CONFIG.DIFFCLK_BOARD_INTERFACE {Custom} CONFIG.PHYADDR {0x2}] $mac
    set phy  [create_bd_cell -type module -reference eth_gt_phy eth_gt_phy_0]
    set fifo [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 rx_cdc_fifo]
    set_property -dict {CONFIG.FIFO_DEPTH 2048 CONFIG.IS_ACLK_ASYNC 1 CONFIG.FIFO_MEMORY_TYPE block} $fifo
    set dw   [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 rx_dwidth]
    set_property CONFIG.M_TDATA_NUM_BYTES {1} $dw
    # RX datapath: MAC -> async fifo -> dwidth(8b) -> parser.rx
    connect_bd_intf_net [get_bd_intf_pins axi_eth_0/m_axis_rxd] [get_bd_intf_pins rx_cdc_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins rx_cdc_fifo/M_AXIS]   [get_bd_intf_pins rx_dwidth/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins rx_dwidth/M_AXIS]     [get_bd_intf_pins csi_udp_parser_0/rx]
    # MAC control on its own icn_ctrl master @0xA4080000 (256K)
    set mctl [icn_next_master]
    connect_bd_intf_net [get_bd_intf_pins $mctl] [get_bd_intf_pins axi_eth_0/s_axi]
    assign_bd_address -offset 0xA4080000 -range 256K -target_address_space /CIPS_0/M_AXI_FPD \
        [get_bd_addr_segs axi_eth_0/s_axi/Reg]
    # RX-only tie-offs (idle tx, drain rxs) + GT<->MAC discrete-pin map + clocking
    # (eth_gt_phy.v encapsulates IBUFDS_GTE5 + 4x BUFG_GT; see inline_design.tcl
    #  steps "attach the 100 MHz MAC/PHY clock/reset" and PROJECT_STATE 313-345).
    puts "OVERLAY_D2ETH: TODO GT<->MAC discrete pins + 125/100MHz clocks + SFP XDC"
    # (full pin map intentionally staged for board-cycle bring-up; see PROJECT_STATE.)
} else {
    puts "OVERLAY_D2ETH: ETH front-end NOT instantiated (D2_ETH_FULL unset)."
    puts "OVERLAY_D2ETH: csi_mux/S00 (parser) present; parser rx will be tied off."
    # keep validate happy: tie parser rx to an idle AXIS source
    set idle [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 parser_rx_idle]
    set_property -dict {CONFIG.FIFO_DEPTH 16} $idle
    connect_bd_intf_net [get_bd_intf_pins parser_rx_idle/M_AXIS] [get_bd_intf_pins csi_udp_parser_0/rx]
    connect_bd_net -net $aclkname [get_bd_pins parser_rx_idle/s_axis_aclk]
    connect_bd_net -net $arstname [get_bd_pins parser_rx_idle/s_axis_aresetn]
}

validate_bd_design
puts "OVERLAY_D2ETH: validate_bd_design PASSED"
if {$VALIDATE_ONLY} { error "OVERLAY_D2ETH: validate-only stop (intentional)" }
