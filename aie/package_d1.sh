#!/usr/bin/env bash
# package_d1.sh - package the co-gen D1 XSA (csi_mux inserted) for on-target validation.
set -euo pipefail
cd "$(dirname "$0")"
PLATFORM=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm
IMG=/group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux
XSA=inline_cogen_d1.xsa
LIBADF=libadf_motiononly.a
command -v v++ >/dev/null || { echo "source Vitis settings64.sh first"; exit 1; }
for f in "$XSA" "$LIBADF" "$IMG/rootfs.ext4" "$IMG/Image" host/host data/input.txt data/golden.txt; do
  [ -e "$f" ] || { echo "MISSING: $f"; exit 1; }
done
rm -rf sd_stage_d1 && mkdir -p sd_stage_d1
cp host/host mux_set.py run_d1.sh sd_stage_d1/
cp data/input.txt data/golden.txt sd_stage_d1/
chmod +x sd_stage_d1/host sd_stage_d1/run_d1.sh
rm -rf package_d1
set -x
v++ -p -t hw --platform "$PLATFORM" --temp_dir ./_x_d1 \
  "$XSA" "$LIBADF" \
  --package.out_dir ./package_d1 \
  --package.boot_mode sd --package.image_format ext4 \
  --package.rootfs "$IMG/rootfs.ext4" --package.kernel_image "$IMG/Image" \
  --package.sd_dir sd_stage_d1 \
  -o inline_cogen_d1.xclbin
set +x
echo "PACKAGE_D1_DONE xclbin=$(stat -c%s inline_cogen_d1.xclbin 2>/dev/null || echo 0)"
ls -l package_d1/ 2>/dev/null; ls -l package_d1/aie.merged.cdo.bin 2>/dev/null || true
