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
    # v++ platform clock/reset nets confirmed by overlay_d2_clkprobe.tcl:
    set SLOWC clk_wizard_0_clk_out2                  ;# 100 MHz net NAME (MAC lite/axis/freerun)
    set SLOWR /proc_sys_reset_4/peripheral_aresetn   ;# 100 MHz domain reset
    set FASTC $aclkname                               ;# 312.5 MHz datapath
    set FASTR $arstname

    # --- MAC: 1000BASE-X on an external GTY (NOT board flow -> avoids LVDS/LPDDR clash) ---
    set mac [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:8.0 axi_eth_0]
    set_property -dict [list CONFIG.PHYADDR {2} CONFIG.PHY_TYPE {1000BaseX} \
        CONFIG.ENABLE_LVDS {false} CONFIG.gt_type {GTY} CONFIG.gtlocation {X0Y3} \
        CONFIG.gtrefclkrate {156.25}] $mac
    if {[get_property CONFIG.ENABLE_LVDS $mac] ne "false"} { error "axi_eth_0 fell back to LVDS PHY" }

    # --- 50 MHz DRP/PMA ref_clk from CIPS pl0_ref_clk (platform has no 50 MHz tap) ---
    set cw [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 eth_ref_clk_wiz]
    set_property -dict [list \
        CONFIG.CLKOUT_USED {true,false,false,false,false,false,false} \
        CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {50,100.000,100.000,100.000,100.000,100.000,100.000} \
        CONFIG.USE_LOCKED {false} CONFIG.USE_RESET {true} CONFIG.RESET_TYPE {ACTIVE_LOW}] $cw
    connect_bd_net [get_bd_pins eth_ref_clk_wiz/clk_in1] [get_bd_pins CIPS_0/pl0_ref_clk]
    connect_bd_net [get_bd_pins eth_ref_clk_wiz/resetn]  [get_bd_pins CIPS_0/pl0_resetn]

    # --- GTY front end (eth_gt_phy.v: IBUFDS_GTE5 + 4x BUFG_GT + gtwiz) + SFP0 externals ---
    set phy [create_bd_cell -type module -reference eth_gt_phy eth_gt_phy_0]
    foreach p {mgt_clk_p mgt_clk_n sfp_rxp sfp_rxn sfp_txp sfp_txn} {
        make_bd_pins_external -name $p [get_bd_pins eth_gt_phy_0/$p]
    }
    connect_bd_net [get_bd_pins eth_ref_clk_wiz/clk_out1] [get_bd_pins axi_eth_0/ref_clk] [get_bd_pins eth_gt_phy_0/ref_clk]

    # --- 32 discrete GT<->MAC pins (axi_ethernet 8.0; map from eth_ex_support.v) ---
    foreach {phy_pin mac_pin} {
        pma_reset pma_reset  mmcm_locked mmcm_locked  userclk userclk  userclk2 userclk2
        rxuserclk rxuserclk  rxuserclk2 rxuserclk2  gtpowergood gtpowergood_in
        cplllock cplllock_in  gtwiz_reset_tx_done gtwiz_reset_tx_done_in
        gtwiz_reset_rx_done gtwiz_reset_rx_done_in  gtwiz_userdata_tx gtwiz_userdata_tx_out
        gtwiz_userdata_rx gtwiz_userdata_rx_in  txctrl0 txctrl0_out  txctrl1 txctrl1_out
        txctrl2 txctrl2_out  rxctrl0 rxctrl0_in  rxctrl1 rxctrl1_in  rxctrl2 rxctrl2_in
        rxctrl3 rxctrl3_in  rxclkcorcnt rxclkcorcnt_in  txbufstatus txbufstatus_in
        rxbufstatus rxbufstatus_in  txpd txpd_out  rxpd rxpd_out  txelecidle txelecidle_out
        txresetdone txresetdone_in  rxresetdone rxresetdone_in  txpmaresetdone txpmaresetdone_in
        rxpmaresetdone rxpmaresetdone_in  gtwiz_reset_tx_datapath gtwiz_reset_tx_datapath_out
        gtwiz_reset_rx_datapath gtwiz_reset_rx_datapath_out  rxpcommaalignen rxpcommaalignen_out
    } {
        connect_bd_net [get_bd_pins eth_gt_phy_0/$phy_pin] [get_bd_pins axi_eth_0/$mac_pin]
    }
    # SFP loss-of-signal is not wired on VCK190 -> tell the PCS the optical signal is present
    set c1 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 eth_sigdet_high]
    set_property -dict {CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1} $c1
    connect_bd_net [get_bd_pins eth_sigdet_high/dout] [get_bd_pins axi_eth_0/signal_detect]

    # --- RX datapath: MAC -> async CDC(100->312.5) -> dwidth(->8b) -> parser.rx ---
    set fifo [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 rx_cdc_fifo]
    set_property -dict {CONFIG.FIFO_DEPTH 2048 CONFIG.IS_ACLK_ASYNC 1 CONFIG.FIFO_MEMORY_TYPE block} $fifo
    set dw [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 rx_dwidth]
    set_property CONFIG.M_TDATA_NUM_BYTES {1} $dw
    connect_bd_intf_net [get_bd_intf_pins axi_eth_0/m_axis_rxd] [get_bd_intf_pins rx_cdc_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins rx_cdc_fifo/M_AXIS]   [get_bd_intf_pins rx_dwidth/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins rx_dwidth/M_AXIS]     [get_bd_intf_pins csi_udp_parser_0/rx]

    # --- drain the RX status stream (unconsumed m_axis_rxs back-pressures + stalls RX) ---
    set rxsink [create_bd_cell -type module -reference axis_sink rxs_sink]
    connect_bd_intf_net [get_bd_intf_pins axi_eth_0/m_axis_rxs] [get_bd_intf_pins rxs_sink/s_axis]

    # --- MAC AXI-Lite control via a 312.5->100 MHz smartconnect, @0xA4080000 (256K) ---
    set mctl [icn_next_master]
    set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 slow_ctrl_smc]
    set_property -dict {CONFIG.NUM_SI 1 CONFIG.NUM_MI 1 CONFIG.NUM_CLKS 2} $smc
    connect_bd_intf_net [get_bd_intf_pins $mctl]             [get_bd_intf_pins slow_ctrl_smc/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins slow_ctrl_smc/M00_AXI] [get_bd_intf_pins axi_eth_0/s_axi]
    assign_bd_address -offset 0xA4080000 -range 256K -target_address_space /CIPS_0/M_AXI_FPD \
        [get_bd_addr_segs -of [get_bd_intf_pins axi_eth_0/s_axi]]

    # --- clocks: 100 MHz (SLOW) domain ---
    connect_bd_net -net $SLOWC \
        [get_bd_pins axi_eth_0/s_axi_lite_clk] [get_bd_pins axi_eth_0/axis_clk] \
        [get_bd_pins slow_ctrl_smc/aclk1] [get_bd_pins eth_gt_phy_0/freerun_clk] \
        [get_bd_pins rx_cdc_fifo/s_axis_aclk] [get_bd_pins rxs_sink/aclk]
    # --- clocks: 312.5 MHz (FAST) domain ---
    connect_bd_net -net $FASTC \
        [get_bd_pins rx_cdc_fifo/m_axis_aclk] [get_bd_pins rx_dwidth/aclk] \
        [get_bd_pins slow_ctrl_smc/aclk]
    # --- resets ---
    connect_bd_net [get_bd_pins $SLOWR] \
        [get_bd_pins axi_eth_0/s_axi_lite_resetn] [get_bd_pins axi_eth_0/axi_rxd_arstn] \
        [get_bd_pins axi_eth_0/axi_rxs_arstn] [get_bd_pins axi_eth_0/axi_txc_arstn] \
        [get_bd_pins axi_eth_0/axi_txd_arstn] [get_bd_pins eth_gt_phy_0/resetn] \
        [get_bd_pins rx_cdc_fifo/s_axis_aresetn] [get_bd_pins rxs_sink/aresetn]
    connect_bd_net -net $FASTR [get_bd_pins rx_dwidth/aresetn] [get_bd_pins slow_ctrl_smc/aresetn]
    puts "OVERLAY_D2ETH: ETH front-end instantiated (GT+MAC+RX chain, SFP0 external)"
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
