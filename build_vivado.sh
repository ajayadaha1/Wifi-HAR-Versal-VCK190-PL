#!/usr/bin/env bash
# build_vivado.sh - ONE-SHOT hardware build (run from the repo root).
#
# Produces the hardware handoff for PetaLinux and the on-target host app, from
# source, with NO manual vitis_hls step (the csi_udp_parser IP is pre-packaged in
# hw/ip_repo/, and the PL data movers are built here via v++ -c):
#
#   1) aiecompiler  aie/src/graph.cpp          -> aie/libadf.a            (3-branch AIE)
#   2) v++ -c       aie/pl/{mm2s,s2mm}.cpp     -> aie/{mm2s,s2mm}.xo       (PL data movers)
#   3) v++ -l       libadf.a + movers          -> aie/feature_graph_3br.xsa   <- PetaLinux input
#   4) v++ -p       xsa + libadf.a (LEAN,      -> aie/feature_graph_3br.xclbin
#                   no rootfs -> breaks the        + aie/package_3br/aie.merged.cdo.bin
#                   xclbin<->rootfs cycle)
#   5) stage xclbin + AIE CDO into the aie-validate recipe files/ so PetaLinux
#      can bake them into the rootfs.
#
# Then run:  ./build_petalinux.sh   (XSA -> image + SDK; cross-builds host_3br).
#
# Env overrides: VITIS (settings64.sh), PLATFORM (vck190 base .xpfm).
#
# NOT YET one-shot: the INLINE Arch B XSA (Ethernet MAC -> csi_udp_parser -> AIE),
# captured in hw/scripts/inline_full_bd.tcl, stops at synthesis. It still needs
# GT/PCS-PMA wiring to the SFP, hw/constraints/inline.xdc pin+clock constraints,
# impl, and write_hw_platform. See docs/PROJECT_STATE.md (todo: inline XSA).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AIE="$HERE/aie"
: "${VITIS:=/proj/gsd/vivado/2025.2/Vitis/settings64.sh}"
: "${PLATFORM:=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm}"
RECIPE_FILES="$HERE/petalinux/project-spec/meta-user/recipes-apps/aie-validate/files"

echo "== [0/5] Vitis 2025.2 env =="
# shellcheck disable=SC1090
source "$VITIS" >/dev/null 2>&1 || { echo "ERROR: cannot source $VITIS"; exit 1; }
command -v v++          >/dev/null || { echo "ERROR: v++ not on PATH"; exit 1; }
command -v aiecompiler  >/dev/null || { echo "ERROR: aiecompiler not on PATH"; exit 1; }
[ -e "$PLATFORM" ]                 || { echo "ERROR: platform not found: $PLATFORM"; exit 1; }

cd "$AIE"

echo "== [1/5] AIE compile -> libadf.a =="
./build_hw.sh                                   # handles the Ubuntu-20 debuginfod stub
[ -s libadf.a ] || { echo "ERROR: libadf.a not produced"; exit 1; }

echo "== [2/5] PL data movers -> mm2s.xo / s2mm.xo =="
for k in mm2s s2mm; do
  v++ -c -t hw --platform "$PLATFORM" -k "$k" "pl/$k.cpp" -o "$k.xo"
done

echo "== [3/5] v++ link -> feature_graph_3br.xsa =="
v++ -l -t hw --platform "$PLATFORM" --config system_3br.cfg \
    libadf.a mm2s.xo s2mm.xo -o feature_graph_3br.xsa
[ -s feature_graph_3br.xsa ] || { echo "ERROR: XSA not produced"; exit 1; }

echo "== [4/5] v++ package (lean, no rootfs) -> feature_graph_3br.xclbin + aie CDO =="
rm -rf package_3br
v++ -p -t hw --platform "$PLATFORM" --temp_dir ./_x3br \
    feature_graph_3br.xsa libadf.a \
    --package.out_dir ./package_3br \
    -o feature_graph_3br.xclbin

echo "== [5/5] stage xclbin + AIE CDO into the aie-validate recipe =="
mkdir -p "$RECIPE_FILES"
cp -f feature_graph_3br.xclbin "$RECIPE_FILES/"
[ -e package_3br/aie.merged.cdo.bin ] && cp -f package_3br/aie.merged.cdo.bin "$RECIPE_FILES/" || true

echo
echo "DONE (offline/validated datapath):"
echo "  XSA    : $AIE/feature_graph_3br.xsa   -> feed to ./build_petalinux.sh"
echo "  xclbin : $AIE/feature_graph_3br.xclbin (staged into recipe files/)"
echo "Next    : ./build_petalinux.sh"
