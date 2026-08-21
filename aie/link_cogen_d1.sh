#!/usr/bin/env bash
# D1 co-generation link: v++ links mm2s+s2mm+AIE against the base platform, then
# the postSysLink overlay inserts csi_mux on the AIE input. One link => paired
# PDI shim + AIE CDO (the whole point, vs #21's mixed artifacts).
set +eu
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1
set -eu
cd /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph

PLATFORM=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm
OVERLAY=/group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph/overlay_d1.tcl

echo "COGEN_D1_START $(date)"
rm -rf _x_d1
v++ -l -t hw \
  --platform "$PLATFORM" \
  --temp_dir _x_d1 \
  --config system.cfg \
  --advanced.param compiler.userPostSysLinkOverlayTcl="$OVERLAY" \
  libadf_motiononly.a mm2s.xo s2mm.xo \
  -o inline_cogen_d1.xsa
echo "COGEN_D1_EXIT=$? $(date)"
ls -la inline_cogen_d1.xsa 2>/dev/null
