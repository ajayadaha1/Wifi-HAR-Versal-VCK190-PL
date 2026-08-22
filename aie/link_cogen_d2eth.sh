#!/usr/bin/env bash
# link_cogen_d2eth.sh - D2 milestone (b) co-gen link: AIE + movers + the live
# Ethernet CSI front-end, via overlay_d2_eth.tcl.
#
# Unlike D1/D2mux (catalog IP only), the live path needs THREE extra sources fed
# to the v++ Vivado project so the overlay's create_bd_cell calls resolve and the
# SFP0 pins are constrained:
#   (1) csi_udp_parser HLS IP repo   -> ip_repo_paths      (hw/ip_repo)
#   (2) eth_gt_phy.v module + XCI    -> project RTL sources (hw/hdl, hw/ip)
#   (3) SFP0 pin constraints         -> impl constraints    (hw/constraints/inline.xdc)
#
# (1) and (2) are injected with a PRE-SysLink overlay (runs before the BD is
# built, so ip_repo_paths + add_files take effect); (3) via --vivado.prop on the
# impl run. overlay_d2_eth.tcl (POST-SysLink) then does the BD wiring.
#
# Env:
#   D2_VALIDATE_ONLY=1  structural check (abort pre-synth)
#   D2_ETH_FULL=1       instantiate the GT+MAC front-end (else parser rx tied off)
set +eu
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1
set -eu
cd /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
ROOT=/group/bcapps/ajayad/master_thesis_rebirth/work
PLATFORM=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm
POST=$PWD/overlay_d2_eth.tcl
PRE=$PWD/overlay_d2_eth_pre.tcl
XDC=$ROOT/hw/constraints/sfp0.xdc
OUT="${1:-inline_cogen_d2eth.xsa}"; TMP="${2:-_x_d2eth}"

# PRE-SysLink overlay: add the parser IP repo + GT RTL/XCI + SFP0 XDC to the project.
# The csi_eth_gtwiz XCI only exposes its channel-2 outclk/rplllock ports when the
# INTF0_GT_SETTINGS + QUAD0_HSCLK1_RPLL_LOCK_EN are applied at BUILD time (they are
# NOT stored in the .xci) - exactly as project_top.tcl does. Apply them here before
# generate_target so the v++-generated gtwiz matches eth_gt_phy.v (fixes 349-390).
cat > "$PRE" <<'TCL'
set_property ip_repo_paths {__ROOT__/hw/ip_repo} [current_project]
update_ip_catalog -rebuild
add_files -norecurse {__ROOT__/hw/hdl/eth_gt_phy.v __ROOT__/hw/hdl/axis_sink.v}
import_ip {__ROOT__/hw/ip/csi_eth_gtwiz.xci}
add_files -fileset constrs_1 -norecurse {__XDC__}
set_property used_in_synthesis false [get_files __XDC__]
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
TCL
sed -i "s#__ROOT__#$ROOT#g; s#__XDC__#$XDC#g" "$PRE"

echo "D2ETH_LINK_START $(date)  out=$OUT tmp=$TMP eth_full=${D2_ETH_FULL:-0} validate_only=${D2_VALIDATE_ONLY:-0}"
rm -rf "$TMP"
v++ -l -t hw --platform "$PLATFORM" --temp_dir "$TMP" --config system.cfg \
  --advanced.param compiler.userPreSysLinkOverlayTcl="$PRE" \
  --advanced.param compiler.userPostSysLinkOverlayTcl="$POST" \
  libadf_motiononly.a mm2s.xo s2mm.xo -o "$OUT" 2>&1 || true
echo "D2ETH_LINK_DONE $(date)"
ls -la "$OUT" 2>/dev/null || echo "(no xsa - expected if validate-only or missing GT sources)"
