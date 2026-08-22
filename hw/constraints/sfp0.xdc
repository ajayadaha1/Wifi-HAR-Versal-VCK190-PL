## SFP0 (bank 105 channel 2) physical pins + 156.25 MHz MGT refclk for the
## eth_gt_phy front end. Port names match make_bd_pins_external in overlay_d2_eth.tcl.
set_property PACKAGE_PIN K46 [get_ports sfp_rxp]
set_property PACKAGE_PIN K47 [get_ports sfp_rxn]
set_property PACKAGE_PIN H41 [get_ports sfp_txp]
set_property PACKAGE_PIN H42 [get_ports sfp_txn]
set_property PACKAGE_PIN L39 [get_ports mgt_clk_p]
set_property PACKAGE_PIN L40 [get_ports mgt_clk_n]
create_clock -period 6.400 -name mgt_clk -waveform {0.000 3.200} [get_ports mgt_clk_p]
