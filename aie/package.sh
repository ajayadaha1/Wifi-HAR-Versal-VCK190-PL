#!/usr/bin/env bash
# package.sh — v++ --package the 1-branch feature graph into feature_graph.xclbin
# plus a bootable SD image, for on-target DDR->AIE->DDR validation
# (PROJECT_STATE.md §9.2 "package boot + xclbin" / §9.3 validation).
#
# Uses the 1-branch link output (feature_graph.xsa) + the MATCHING 1-branch AIE
# archive (libadf_motiononly.a). The on-disk libadf.a is now the 3-branch build,
# which does NOT match this xsa's PL wiring, so we pin the 1-branch archive here.
#
# Runtime files (host, input.txt, golden.txt, run_on_target.sh) are copied onto
# the SD card via --package.sd_dir so the board can self-validate.
#
# Prereq: source the Vitis 2025.2 environment first:
#   source /proj/gsd/vivado/2025.2/Vitis/settings64.sh
set -euo pipefail
cd "$(dirname "$0")"

PLATFORM=/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm
IMG=/group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux
XSA=feature_graph.xsa
LIBADF=libadf_motiononly.a   # 1-branch AIE, matches feature_graph.xsa

command -v v++ >/dev/null || { echo "ERROR: v++ not on PATH; source Vitis settings64.sh first"; exit 1; }
for f in "$XSA" "$LIBADF" "$IMG/rootfs.ext4" "$IMG/Image" host/host data/input.txt data/golden.txt; do
  [ -e "$f" ] || { echo "MISSING input: $f"; exit 1; }
done

# stage runtime files for the SD card
rm -rf sd_stage && mkdir -p sd_stage
cp host/host sd_stage/host
cp data/input.txt data/golden.txt run_on_target.sh sd_stage/
chmod +x sd_stage/host sd_stage/run_on_target.sh

rm -rf package
set -x
v++ -p -t hw \
  --platform "$PLATFORM" \
  "$XSA" "$LIBADF" \
  --package.out_dir ./package \
  --package.boot_mode sd \
  --package.image_format ext4 \
  --package.rootfs "$IMG/rootfs.ext4" \
  --package.kernel_image "$IMG/Image" \
  --package.sd_dir sd_stage \
  -o feature_graph.xclbin
set +x

echo "PACKAGE_DONE xclbin_bytes=$(stat -c%s feature_graph.xclbin 2>/dev/null || echo 0)"
ls -l package/ 2>/dev/null || true
