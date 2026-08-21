#!/usr/bin/env bash
# Re-run the single-branch v++ --link to regenerate the ground-truth vpl BD
# (_x/link/int/dr.bd.tcl), the ip_repo project_top.tcl consumes, and the
# AIE<->PL shim solution (aiearchive.aieprj). Reproduces feature_graph.xsa
# (validated bit-accurate on silicon, PROJECT_STATE P6/P7).
set +eu
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1
set -eu
cd /group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph

PLATFORM=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm

echo "RELINK_START $(date)"
rm -rf _x/link
v++ -l -t hw \
  --platform "$PLATFORM" \
  --config system.cfg \
  libadf_motiononly.a mm2s.xo s2mm.xo \
  -o feature_graph_relink.xsa
echo "RELINK_EXIT=$? $(date)"
echo "=== dr.bd.tcl ==="; ls -la _x/link/int/dr.bd.tcl 2>/dev/null || echo MISSING
echo "=== ip_repo ==="; ls _x/link/int/xo/ip_repo/ 2>/dev/null || echo MISSING
