# project_top.tcl - build the INLINE Arch-B XSA end to end.
#
# Chain: SFP0 -> GTY -> axi_ethernet(1000BASE-X) -> rx_dwidth(32->8) ->
#        csi_udp_parser -> csi_mux -> AI Engine -> s2mm -> DDR,
#        plus csi_udp_parser meta_out -> s2mm_meta -> DDR, and a DDR-fed TX
#        injection path so the design can loop back and test itself.
# The design itself lives in inline_design.tcl (entry point build_inline_bd);
# this file just configures the project and drives the build.
#
# KEY FINDING (research): the PS hard GEM cannot feed the parser (it delivers RX to
# PS DRAM, exposes no AXIS RX to PL), so the inline soft MAC needs its OWN PCS/PMA +
# GT + SFP0 - it cannot piggyback on GEM0.
#
# APPROACH: rather than bolt a standalone gig_ethernet_pcs_pma onto the MAC's GMII
# (which is what the PS-GEM baseline ps_emio_basex_bd.tcl has to do, because a hard
# GEM has no GT interface), reconfigure axi_eth_0 itself to PHY_TYPE=1000BaseX. The
# soft MAC then instantiates its own PCS/PMA internally and exposes gt_tx_interface
# / gt_rx_interface straight to a GTY quad - fewer cells, and it matches the AMD
# VCK190 reference design Versal-Ethernet/VCK190-Ethernet/2024.1/pl_eth_1g_rpll
# exactly (same board, GT type, line rate and 156.25 MHz SI570 refclk), which is
# where the topology and the GTY preset are lifted from.
#
# Constraints: hw/constraints/inline.xdc (SFP0 pins + refclk; board automation is
# preferred - board_part is set below).
#
# ---------------------------------------------------------------------------
# Reference-style flow (like ps_emio_basex_1g/Scripts): configure the project,
# source the main BD tcl, then build. The files in this dir are:
#     project_top.tcl    (this: the top - configure the project + run the build)
#     inline_design.tcl  (the whole block design; entry point build_inline_bd)
# Those are the only two, on purpose.
#
# PREREQ: run ../build_vivado.sh first (v++ link) so the mover/AIE IPs the BD
#   references exist at aie/_x/link/int/xo/ip_repo.
# INSPECT the BD: run `vivado -source build_inline_xsa.tcl` in the GUI - the BD is
#   built, validated and opened (step 3) before the guarded wiring/impl steps.
# ---------------------------------------------------------------------------
set HERE       [file normalize [file dirname [info script]]]
set REPO_HW    [file normalize $HERE/..]
set FG         [file normalize $REPO_HW/../aie]
set PART       xcvc1902-vsva2197-2MP-e-S
set BOARD      xilinx.com:vck190:part0:3.4
set XDC        $REPO_HW/constraints/inline.xdc
set OUT_XSA    $REPO_HW/inline_eth_hw/inline.xsa
set VPL_IPREPO $FG/_x/link/int/xo/ip_repo
set HDL        [list $REPO_HW/hdl/axis_sink.v $REPO_HW/hdl/eth_gt_phy.v]
set GTWIZ_XCI  $REPO_HW/ip/csi_eth_gtwiz.xci

# Stop before impl (BD inspection / faster iteration): -tclargs bd_only
set BD_ONLY [expr {[lsearch -exact $argv bd_only] >= 0}]

# 1) configure project + IP catalog (csi_udp_parser + the v++ mover/AIE IPs)
create_project -force inline_eth $REPO_HW/inline_eth_hw -part $PART
set_property board_part $BOARD [current_project]
set ipdirs [list $REPO_HW/ip_repo]
if {[file exists $VPL_IPREPO]} {
    lappend ipdirs $VPL_IPREPO
} else {
    puts "WARN: v++ mover/AIE IP repo not found ($VPL_IPREPO) - run build_vivado.sh first."
}
set_property ip_repo_paths $ipdirs [current_project]
update_ip_catalog

# The GT wizard behind eth_gt_phy.v. This .xci is the axi_ethernet example
# design's gtwiz_versal with INTF0_LANE_MAP / INTF0_CHANNEL_MAP rewritten onto
# quad channel 2 (VCK190 SFP0); those parameters are "disabled" and cannot be
# reached with set_property, so the file is edited directly. Import it before
# the HDL so eth_gt_phy.v's csi_eth_gtwiz instance resolves.
import_ip $GTWIZ_XCI

# Everything except the lane assignment IS settable from Tcl, so it lives here
# rather than being baked into the .xci. Defaults would give a 125 MHz refclk on
# the LCPLL; the VCK190 SI570 on bank 105 is 156.25 MHz and the AMD reference
# design runs this link off the RPLL with TXPROGDIV at 125 MHz (which is what
# makes TXOUTCLK 125 MHz and RXOUTCLK 62.5 MHz - eth_gt_phy.v's BUFG_GT divides
# assume exactly that). QUAD0_HSCLK1_RPLL_LOCK_EN exposes the lock of the PLL
# actually in use, which feeds the MAC's cplllock_in.
set_property -dict [list \
  CONFIG.INTF0_GT_SETTINGS {LR0_SETTINGS {\
     TX_REFCLK_FREQUENCY 156.25 RX_REFCLK_FREQUENCY 156.25 \
     TX_PLL_TYPE RPLL RX_PLL_TYPE RPLL \
     TXPROGDIV_FREQ_SOURCE RPLL RXPROGDIV_FREQ_SOURCE RPLL \
     TXPROGDIV_FREQ_VAL 125.000 RXPROGDIV_FREQ_VAL 62.500 \
     RX_OUTCLK_SOURCE RXPROGDIVCLK TX_OUTCLK_SOURCE TXPROGDIVCLK}} \
  CONFIG.QUAD0_HSCLK1_RPLL_LOCK_EN {true} \
] [get_ips csi_eth_gtwiz]
generate_target {synthesis instantiation_template} [get_ips csi_eth_gtwiz]

# Guard the two things that silently produce a dead link rather than an error:
# the lane must be on quad channel 2 (SFP0) and the refclk must be 156.25 MHz.
set quad_xci [lindex [glob -nocomplain \
    $REPO_HW/inline_eth_hw/inline_eth.gen/sources_1/ip/csi_eth_gtwiz/ip_0/*gt_quad_base_0.xci] 0]
if {$quad_xci eq "" || ![file exists $quad_xci]} {
    return -code error "csi_eth_gtwiz did not generate a gt_quad_base - cannot verify the SFP0 lane"
}
set fh [open $quad_xci r] ; set quad_txt [read $fh] ; close $fh

# Does the value of parameter $key mention $want? (Plain string search: regexes
# with character classes would need braces, which Tcl will not nest here.)
proc _quad_param_has {txt key want} {
    set i [string first $key $txt]
    if {$i < 0} { return 0 }
    set seg [string range $txt $i [expr {$i + 300}]]
    return [expr {[string first $want $seg] >= 0}]
}

foreach {what key want} [list \
    "RX on quad channel 2" "RX2_LANE_SEL"  "PROT0" \
    "TX on quad channel 2" "TX2_LANE_SEL"  "PROT0" \
    "156.25 MHz refclk"    "REFCLK_STRING" "refclk_PROT0_R0_156.25_MHz" \
] {
    if {![_quad_param_has $quad_txt $key $want]} {
        return -code error "csi_eth_gtwiz: $what not confirmed in [file tail $quad_xci] - SFP0 would not link"
    }
}
puts "GTWIZ_OK  SFP0 on quad channel 2, 156.25 MHz refclk"

# The BD instantiates axis_sink and eth_gt_phy as module references, so their
# sources must be in the project before create_bd_cell -type module runs.
add_files -norecurse -fileset sources_1 $HDL
update_compile_order -fileset sources_1

# inline_design.tcl checks the IP catalog as it is sourced (that check is part
# of the captured write_bd_tcl preamble), so it must be sourced only once the
# catalog above is in place - not at the top of this file.
source $HERE/inline_design.tcl

# 2) build the block design and close out every dangling port
build_inline_bd

# 3) validate
regenerate_bd_layout
validate_bd_design
save_bd_design
puts "BD_VALIDATE_OK"

# 3b) Associate the AIE<->PL shim-solution archive (system.aieprj) with
# ai_engine_0 so Vivado applies the graph's aieshim_solution / aie_pl_intf during
# synthesis and configures the ai_engine shim + NoC to match where the graph's
# PLIO is placed. Without this the shim config is default and never pairs with the
# graph CDO -> ai_engine_0/S00_AXIS TREADY never asserts, stalling the datapath
# (PROJECT_STATE #17-#20). The .aieprj (FILE_TYPE AIEPRJ) is what v++ itself
# scopes to the cell (see vpl.tcl aie_archive_file = int/system.aieprj); a raw .a
# is FILE_TYPE Unknown and has no SCOPED_TO_* properties. This archive was
# captured from the single-branch v++ link (same libadf_motiononly.a + base
# platform that produced the silicon-validated feature_graph.xsa). Pair with the
# HDL_ATTRIBUTE.ME_ANNOTATION {PLIO_in}/{PLIO_out} set in inline_design.tcl.
set AIE_ARCHIVE $FG/feature_graph/aie_integration/motiononly.aieprj
if {![file exists $AIE_ARCHIVE]} {
    return -code error "AIE shim-solution archive missing: $AIE_ARCHIVE (capture system.aieprj from a v++ link first)"
}
add_files -norecurse $AIE_ARCHIVE
set _aie_file_local_ [get_files -all $AIE_ARCHIVE]
if {[get_property FILE_TYPE $_aie_file_local_] ne "AIEPRJ"} {
    return -code error "expected FILE_TYPE AIEPRJ for $AIE_ARCHIVE, got [get_property FILE_TYPE $_aie_file_local_]"
}
set_property SCOPED_TO_REF   [current_bd_design] $_aie_file_local_
set_property SCOPED_TO_CELLS { ai_engine_0 }     $_aie_file_local_
set_property USED_IN_IMPLEMENTATION true         $_aie_file_local_
puts "AIE_ARCHIVE_SCOPED $AIE_ARCHIVE -> ai_engine_0"

# 4) wrap + constrain + impl -> XSA
make_wrapper -files [get_files *vitis_design.bd] -top -import -force
update_compile_order -fileset sources_1
# Pin the top explicitly. eth_gt_phy.v is added to sources_1 before the BD
# exists, so Vivado's automatic top detection latches onto it and never lets go
# - synth/impl then run on the bare PHY and write_device_image fails with
# "[DRC CIPS-2] Versal designs must contain a CIPS IP" plus ~150 unconstrained
# ports.
set_property top vitis_design_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[get_property top [get_filesets sources_1]] ne "vitis_design_wrapper"} {
    return -code error "top is [get_property top [get_filesets sources_1]], expected vitis_design_wrapper"
}
add_files -fileset constrs_1 -norecurse $XDC
generate_target all [get_files *vitis_design.bd]

if {$BD_ONLY} {
    puts "BD_ONLY: stopping before synthesis (drop the bd_only tclarg to build)."
    close_project
    return
}

launch_runs synth_1 -jobs 8 ; wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    return -code error "synth_1 failed - see the run log"
}
launch_runs impl_1 -to_step write_device_image -jobs 8 ; wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    return -code error "impl_1 failed - see the run log"
}
write_hw_platform -fixed -include_bit -force $OUT_XSA
puts "WROTE_XSA $OUT_XSA"
close_project
