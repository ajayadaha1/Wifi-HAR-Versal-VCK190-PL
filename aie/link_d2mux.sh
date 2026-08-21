#!/usr/bin/env bash
set +eu
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1
set -eu
cd /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
PLATFORM=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm
OVERLAY=/group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph/overlay_d2_mux.tcl
OUT="${1:-inline_cogen_d2mux.xsa}"; TMP="${2:-_x_d2mux}"
echo "D2MUX_LINK_START $(date)  out=$OUT tmp=$TMP validate_only=${D2_VALIDATE_ONLY:-0}"
rm -rf "$TMP"
v++ -l -t hw --platform "$PLATFORM" --temp_dir "$TMP" --config system.cfg \
  --advanced.param compiler.userPostSysLinkOverlayTcl="$OVERLAY" \
  libadf_motiononly.a mm2s.xo s2mm.xo -o "$OUT" 2>&1 || true
echo "D2MUX_LINK_DONE $(date)"
ls -la "$OUT" 2>/dev/null || echo "(no xsa - expected if validate-only)"
