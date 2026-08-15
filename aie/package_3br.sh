#!/usr/bin/env bash
# package_3br.sh — v++ --package the 3-branch feature graph:
#   feature_graph_3br.xsa (6 PLIO) + libadf.a (3-branch) -> feature_graph_3br.xclbin
#   + package_3br/aie.merged.cdo.bin (the 3-branch aie_image to bake into BOOT.BIN).
# Prereq: source /proj/gsd/vivado/2025.2/Vitis/settings64.sh
set -euo pipefail
cd "$(dirname "$0")"

PLATFORM=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm
IMG=/group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux
XSA=feature_graph_3br.xsa
LIBADF=libadf.a            # 3-branch, matches feature_graph_3br.xsa

command -v v++ >/dev/null || { echo "ERROR: source Vitis settings64.sh first"; exit 1; }
for f in "$XSA" "$LIBADF" "$IMG/rootfs.ext4" "$IMG/Image" host/host_3br; do
  [ -e "$f" ] || { echo "MISSING input: $f"; exit 1; }
done

rm -rf sd_stage_3br && mkdir -p sd_stage_3br
cp host/host_3br sd_stage_3br/host_3br
cp data/input.txt data/golden.txt data/breath_input.txt data/breath_golden.txt \
   data/phase_input.txt data/phase_golden.txt sd_stage_3br/
chmod +x sd_stage_3br/host_3br

rm -rf package_3br
set -x
v++ -p -t hw \
  --platform "$PLATFORM" \
  --temp_dir ./_x3br \
  "$XSA" "$LIBADF" \
  --package.out_dir ./package_3br \
  --package.boot_mode sd \
  --package.image_format ext4 \
  --package.rootfs "$IMG/rootfs.ext4" \
  --package.kernel_image "$IMG/Image" \
  --package.sd_dir sd_stage_3br \
  -o feature_graph_3br.xclbin
set +x

echo "PACKAGE_3BR_DONE xclbin_bytes=$(stat -c%s feature_graph_3br.xclbin 2>/dev/null || echo 0)"
ls -l package_3br/aie.merged.cdo.bin 2>/dev/null || true
