# inline.xdc - SFP0 GT + refclk constraints for the inline Arch-B design.
#
# STATUS: WIP scaffold for hw/scripts/build_inline_xsa.tcl (todo #5).
# board_part xilinx.com:vck190:part0:3.4 is set on the VPL project, so Vivado
# board automation can place the SFP0 GTY channel + SI570 refclk (Approach A).
# The explicit pin locations below are the baseline VCK190 SFP0 mapping (from
# work/hw/constraints/ps_emio_basex.xdc, where they ship commented, relying on
# board automation). They are kept here as a REFERENCE only - VERIFY against the
# vck190 board file / schematic before uncommenting; wrong GT pins will not bring
# up the link.
#
# --- SFP0 GTY (Bank 105, channel 2) - reference, verify before use ---
# set_property PACKAGE_PIN K46 [get_ports {gt_rxp_in_0[0]}]
# set_property PACKAGE_PIN K47 [get_ports {gt_rxn_in_0[0]}]
# set_property PACKAGE_PIN H41 [get_ports {gt_txp_out_0[0]}]
# set_property PACKAGE_PIN H42 [get_ports {gt_txn_out_0[0]}]
#
# --- GT refclk (SI570, 156.25 MHz) ---
# set_property PACKAGE_PIN L39 [get_ports {CLK_IN_D_0_clk_p}]
# set_property PACKAGE_PIN L40 [get_ports {CLK_IN_D_0_clk_n}]
# create_clock -period 6.400 -name gt_refclk [get_ports {CLK_IN_D_0_clk_p}]  ;# 156.25 MHz
#
# --- SFP0 TX enable (active-low disable) ---
# set_property IOSTANDARD LVCMOS15 [get_ports SFP0_TX_DISABLE]
# set_property PACKAGE_PIN <pin>   [get_ports SFP0_TX_DISABLE]
