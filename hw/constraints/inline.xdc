# inline.xdc - SFP0 GTY + refclk pin constraints for the inline Arch-B design.
#
# The ports come from hw/hdl/eth_gt_phy.v, taken external by add_eth_phy
# (hw/scripts/inline_eth_phy.tcl). Pin locations are the AMD VCK190 mapping,
# verbatim from the reference design
#   Versal-Ethernet/VCK190-Ethernet/2024.1/pl_eth_1g_rpll/hardware/vck190_axi_eth_subsys.xdc
# (identical in the 2020.2 pl_eth_1G revision), cross-checked against the board
# file, whose bank105_gty2_axi_eth interface maps to gt_quad_base_bank105
# {rxp,rxn,txp,txn}_2 and whose gtrefclk0_bank105 is GT_REFCLK0 at 156.25 MHz.
#
# eth_gt_phy.v drives quad channel 2 (QUAD0_{rxp,txp}[2]) because that is the
# channel SFP0 is wired to; the gtwiz lane map in hw/ip/csi_eth_gtwiz.xci is set
# to match. Getting these two out of step is a silent no-link.

##### GTY Bank 105 channel 2 - SFP0
set_property PACKAGE_PIN K46 [get_ports sfp_rxp]
set_property PACKAGE_PIN K47 [get_ports sfp_rxn]
set_property PACKAGE_PIN H41 [get_ports sfp_txp]
set_property PACKAGE_PIN H42 [get_ports sfp_txn]

##### GTREFCLK0 - 156.25 MHz, driven by the SI570
set_property PACKAGE_PIN L39 [get_ports mgt_clk_p]
set_property PACKAGE_PIN L40 [get_ports mgt_clk_n]
create_clock -period 6.400 -name mgt_clk -waveform {0.000 3.200} [get_ports mgt_clk_p]

# SFP0_TX_DISABLE (G21, LVCMOS33) is deliberately not driven: the VCK190 system
# controller leaves the SFP cages enabled, and the AMD reference only ties it
# from an xlconstant. Add it here if a board turns up with the optics disabled.

##### AI Engine PL-interface placement ########################################
# The AIE<->PL channel MUST land in the same AIE column the graph's PLIOs are
# placed in, or no data ever crosses and ai_engine_0/S00_AXIS simply holds
# TREADY low forever (PROJECT_STATE #17-#20).
#
# The graph puts both PLIOs in column 24:
#   Work_hw/ps/c_rts/aie_control_config.json -> PLIOs.plio0/plio1.shim_column=24
# Left unconstrained, Vivado placed the channel at AIE_PL_X10Y0, and the site
# name is NOT the AIE column - the tile mapping is AIE_PL_XnY0 -> ...CORE_X(n+1):
#   AIE_PL_X10Y0 -> AIE_INTF_B2_CORE_X11Y0   i.e. column 11, 13 columns adrift
#   AIE_PL_X23Y0 -> AIE_INTF_B3_CORE_X24Y0   i.e. column 24, what we need
#
# So this LOC and the graph's shim_column are a matched pair. If the graph is
# ever recompiled and its PLIOs move, re-read that json and move this with it.
# There are TWO channels and BOTH must move - constraining only one leaves the
# other adrift, which is exactly the trap hit on the first attempt:
#   ai_pl_ch_0 = AIE->PL (M00_AXIS, results out)
#   pl_ai_ch_0 = PL->AIE (S00_AXIS, samples in)   <-- the one holding TREADY low
# A single AIE_PL site hosts both directions, so they share one LOC.
set_property LOC AIE_PL_X23Y0 \
    [get_cells vitis_design_i/ai_engine_0/inst/ai_pl_ch_0/inst/ai_pl_channel_inst]
set_property LOC AIE_PL_X23Y0 \
    [get_cells vitis_design_i/ai_engine_0/inst/pl_ai_ch_0/inst/pl_ai_channel_inst]
