catch { config_ip_cache -use_cache_location {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/inline_eth_hw/inline_eth.cache/ip} }
set_property ip_repo_paths {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip_repo} [current_project]
update_ip_catalog -rebuild
add_files -norecurse {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/hdl/eth_gt_phy.v /group/bcapps/ajayad/master_thesis_rebirth/work/hw/hdl/axis_sink.v}
add_files -norecurse {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/ip/csi_eth_gtwiz.xci}
add_files -fileset constrs_1 -norecurse {/group/bcapps/ajayad/master_thesis_rebirth/work/hw/constraints/sfp0.xdc}
set_property used_in_synthesis false [get_files /group/bcapps/ajayad/master_thesis_rebirth/work/hw/constraints/sfp0.xdc]
catch { generate_target all [get_files csi_eth_gtwiz.xci] }
puts "PRE_D2ETH: ip_repo + eth_gt_phy + gtwiz XCI (cache=/group/bcapps/ajayad/master_thesis_rebirth/work/hw/inline_eth_hw/inline_eth.cache/ip) + SFP0 XDC added"
