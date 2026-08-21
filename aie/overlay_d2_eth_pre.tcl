set_property ip_repo_paths {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo} [current_project]
update_ip_catalog -rebuild
add_files -norecurse {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/hdl/eth_gt_phy.v /group/bcapps/ajayad/master_thesis_rebirth/work/hw/hdl/axis_sink.v}
add_files -norecurse {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip/csi_eth_gtwiz.xci}
puts "PRE_D2ETH: ip_repo + eth_gt_phy + gtwiz XCI added"
