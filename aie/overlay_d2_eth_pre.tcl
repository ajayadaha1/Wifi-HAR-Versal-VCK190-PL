set_property ip_repo_paths {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo} [current_project]
update_ip_catalog -rebuild
add_files -norecurse {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/hdl/eth_gt_phy.v /group/bcapps/ajayad/master_thesis_rebirth/work/hw/hdl/axis_sink.v}
import_ip {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip/csi_eth_gtwiz.xci}
add_files -fileset constrs_1 -norecurse {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/constraints/sfp0.xdc}
set_property used_in_synthesis false [get_files /group/bcapps/ajayad/master_thesis_rebirth/work/hw/constraints/sfp0.xdc]
set _gtip [get_ips -all -filter {NAME =~ *csi_eth_gtwiz*}]
if {[llength $_gtip]} {
    set_property -dict [list \
        CONFIG.INTF0_GT_SETTINGS {LR0_SETTINGS { TX_REFCLK_FREQUENCY 156.25 RX_REFCLK_FREQUENCY 156.25 TX_PLL_TYPE RPLL RX_PLL_TYPE RPLL TXPROGDIV_FREQ_SOURCE RPLL RXPROGDIV_FREQ_SOURCE RPLL TXPROGDIV_FREQ_VAL 125.000 RXPROGDIV_FREQ_VAL 62.500 RX_OUTCLK_SOURCE RXPROGDIVCLK TX_OUTCLK_SOURCE TXPROGDIVCLK}} \
        CONFIG.QUAD0_HSCLK1_RPLL_LOCK_EN {true} ] $_gtip
    puts "PRE_D2ETH: applied INTF0_GT_SETTINGS + HSCLK1_RPLL_LOCK to $_gtip"
    catch { generate_target all $_gtip }
} else {
    puts "PRE_D2ETH: WARN csi_eth_gtwiz IP not found for GT settings"
}
puts "PRE_D2ETH: ip_repo + eth_gt_phy + gtwiz XCI (ch2 GT settings) + SFP0 XDC added"
