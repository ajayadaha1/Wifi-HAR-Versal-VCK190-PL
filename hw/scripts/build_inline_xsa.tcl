# build_inline_xsa.tcl - finish the INLINE Arch-B XSA (todo #5).  *** WIP ***
#
# The inline BD (Ethernet MAC -> rx_dwidth -> csi_udp_parser -> AIE -> s2mm -> DDR)
# is captured by inline_full_bd.tcl but stops at synthesis: the soft axi_ethernet
# MAC's PHY/GT/MDIO/s_axi ports are left EXTERNAL and unconnected, and there is no
# impl/write_hw_platform. This script is the missing orchestration.
#
# KEY FINDING (research): the PS hard GEM cannot feed the parser (it delivers RX to
# PS DRAM, exposes no AXIS RX to PL), so the inline soft MAC needs its OWN PCS/PMA +
# GT + SFP0 - it cannot piggyback on GEM0. Reuse the baseline's proven blocks.
#
# WIRING PLAN (from work/hw/scripts/ps_emio_basex_bd.tcl, "Approach B"):
#   Cells to add:  gig_ethernet_pcs_pma (set EMAC_IF_TEMAC=TEMAC so it exposes the
#     generic gmii_pcs_pma/mdio_pcs_pma), gt_quad_base (GTY, GTY-Ethernet_1G, ch2,
#     REFCLK 156.25), gt_ibufds_gte5, clk_wizard (~100 MHz indep clk), the GT
#     BUFG_GTs, proc_sys_reset, and the util_vector_logic/xlconstant tie-offs.
#   Connections:
#     axi_eth_0/gmii            -> gig_ethernet_pcs_pma_0/gmii_pcs_pma
#     axi_eth_0/mdio            -> gig_ethernet_pcs_pma_0/mdio_pcs_pma
#     pcs_pma/gt_tx_interface   -> gt_quad_base/TX2_GT_IP_Interface
#     pcs_pma/gt_rx_interface   -> gt_quad_base/RX2_GT_IP_Interface
#     gt_quad_base/{txp,txn,rxp,rxn} -> new SFP0 ports
#     new CLK_IN_D port -> gt_ibufds_gte5/CLK_IN_D -> gt_quad_base/GT_REFCLK0
#     GT_WRAPPER_usrclk2 (125 MHz) -> axi_eth_0/{gtx_clk,gmii_tx_clk,gmii_rx_clk}
#       and gig_ethernet_pcs_pma_0/userclk2      (keep axis_clk = ap_clk_bypass_m)
#     clk_wizard/clk_out1 -> pcs_pma/independent_clock_bufg; clk_in1 <- CIPS pl0_ref_clk
#     axi_eth_0/s_axi -> CIPS/M_AXI_FPD via smartconnect  (assign @ 0xA4060000)
#     gt_quad_base/APB3_INTF via axi_apb_bridge on same SC (assign @ 0xA4000000)
#     resets: proc_sys_reset/peripheral_aresetn -> axi_eth_0 *_arstn / pcs_pma resets
#     TX (RX-only capture): tie s_axis_txd/txc to an idle AXIS source so TX FSM is legal
#   Delete the graft placeholder ports first: gmii_0, mdio_0, gtx_clk_0,
#     gmii_{rx,tx,gtx}_clk_0, mdio_mdc_0, phy_rst_n_0, s_axi_lite_*_0, *_arstn_0.
#   Constraints: hw/constraints/inline.xdc (SFP0 pins + refclk; verify vs board).
#   Risks: PCS/PMA GEM-vs-TEMAC mode; SI570 refclk (156.25) vs 125 MHz GMII derived
#     from ch2_txoutclk; single 125 MHz userclk2 for all 3 MAC clocks; s_axi needs a
#     Linux axienet devicetree node. See docs/PROJECT_STATE.md for the full report.
#
# Modeled on build_baseline.tcl (impl + write_hw_platform) but on the VPL project.
set REPO_HW [file normalize [file dirname [info script]]/..]
set FG      [file normalize $REPO_HW/../aie]          ;# feature_graph work area
set PRJ     $FG/_x/link/vivado/vpl/prj/prj.xpr        ;# v++ VPL project (build output)
set XDC     $REPO_HW/constraints/inline.xdc
set OUT_XSA $REPO_HW/inline_eth_hw/inline.xsa

proc add_eth_phy {} {
    # TODO(todo #5): implement the PCS/PMA + GT + refclk + clocking + s_axi wiring
    # per the plan in this file's header. Until then, refuse to proceed so we never
    # emit an XSA with the MAC PHY side unconnected.
    return -code error "add_eth_phy: inline PHY/GT wiring not yet implemented (see header)"
}

if {![file exists $PRJ]} {
    error "VPL project not found: $PRJ  -- run build_vivado.sh (AIE link) first."
}
open_project $PRJ
set_property ip_repo_paths [list $REPO_HW/ip_repo $FG/_x/link/int/xo/ip_repo] [current_project]
update_ip_catalog
open_bd_design [get_files vitis_design.bd]

# Apply the datapath graft idempotently (parser + MAC), then the PHY/GT wiring.
if {[llength [get_bd_cells -quiet axi_eth_0]] == 0} {
    source $REPO_HW/scripts/inline_full.tcl
}
add_eth_phy                                            ;# <-- implement to enable the rest

assign_bd_address
save_bd_design
validate_bd_design
add_files -fileset constrs_1 -norecurse $XDC
set_property used_in_implementation true [get_files inline.xdc]
generate_target all [get_files vitis_design.bd]
set wrap [make_wrapper -files [get_files vitis_design.bd] -top -force]
add_files -norecurse -force $wrap
set_property top vitis_design_wrapper [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 8 ; wait_on_run synth_1
launch_runs impl_1 -to_step write_device_image -jobs 8 ; wait_on_run impl_1
write_hw_platform -fixed -include_bit -force $OUT_XSA
puts "WROTE_XSA $OUT_XSA"
close_project
