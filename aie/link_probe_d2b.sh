#!/usr/bin/env bash
set +eu
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1
set -eu
cd /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph
PLATFORM=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm
OVERLAY=/group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph/overlay_d2_probe2.tcl
echo "PROBE_D2_START $(date)"
rm -rf _x_probe2
v++ -l -t hw --platform "$PLATFORM" --temp_dir _x_probe2 --config system.cfg \
  --advanced.param compiler.userPostSysLinkOverlayTcl="$OVERLAY" \
  libadf_motiononly.a mm2s.xo s2mm.xo -o /tmp/probe_d2.xsa 2>&1 || true
echo "PROBE_D2_DONE $(date)"
