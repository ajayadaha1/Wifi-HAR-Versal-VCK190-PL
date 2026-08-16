#!/usr/bin/env bash
# package_movers.sh - package the PL data movers (mm2s, s2mm) as Vivado IP
# (xilinx.com:hls:mm2s:1.0 / xilinx.com:hls:s2mm:1.0) into hw/ip_repo/, so the
# inline BD (hw/scripts/inline_full_bd.tcl) can be rebuilt WITHOUT the v++ VPL
# project. Run once; the packaged IPs are committed alongside csi_udp_parser.
set -euo pipefail
cd "$(dirname "$0")"                                   # work/aie/feature_graph/pl
unset LD_LIBRARY_PATH XILINX_VITIS XILINX_VIVADO XILINX_HLS XILINX_XRT 2>/dev/null || true
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1
command -v vitis-run >/dev/null || { echo "ERROR: source Vitis 2025.2 settings64.sh first"; exit 1; }
IPREPO="$(cd ../../../hw/ip_repo && pwd)"
PART=xcvc1902-vsva2197-2MP-e-S

for k in mm2s s2mm; do
  rm -rf ${k}_prj
  cat > run_hls_${k}.tcl <<EOF
open_project -reset ${k}_prj
set_top ${k}
add_files ${k}.cpp
open_solution -reset sol1 -flow_target vitis
set_part {${PART}}
create_clock -period 3.0 -name default
csynth_design
export_design -format ip_catalog -rtl verilog
exit
EOF
  echo "=== vitis-run --mode hls: packaging ${k} ==="
  vitis-run --mode hls --tcl run_hls_${k}.tcl
  rm -rf "$IPREPO/${k}"
  mkdir -p "$IPREPO/${k}"
  cp -rf ${k}_prj/sol1/impl/ip/* "$IPREPO/${k}/"
  if [ -f "$IPREPO/${k}/component.xml" ]; then
    echo "PACKAGED ${k} -> $IPREPO/${k}  (component.xml OK)"
  else
    echo "WARN: no component.xml in $IPREPO/${k} - check ${k}_prj/sol1/impl/ip"
  fi
done
echo "DONE packaging movers."
