# Open the built inline design (all-in-one BD) for REVIEW - no build, no close.
# Pins the top + disables auto source-management so that validating / Generate
# Device Image in the GUI uses vitis_design_wrapper (not the bare eth_gt_phy PHY,
# which would fail DRC CIPS-2 + unconstrained GT ports).
open_project /group/bcapps/ajayad/master_thesis_rebirth/work/hw/inline_eth_hw/inline_eth.xpr
set_property top vitis_design_wrapper [get_filesets sources_1]
open_bd_design [get_files -filter {NAME =~ *vitis_design.bd}]
puts "REVIEW: inline all-in-one BD opened; top pinned to [get_property top [get_filesets sources_1]]. Read-only review."
