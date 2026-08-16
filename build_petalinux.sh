#!/usr/bin/env bash
# build_petalinux.sh - ONE-SHOT PetaLinux build (run from the repo root).
#
# Consumes aie/feature_graph_3br.xsa (from ./build_vivado.sh) and produces a
# bootable image with the AIE validation app baked in. Resolves the host<->SDK
# ordering cycle: build the SDK first, cross-build host_3br against it, stage it
# into the recipe, then do the final rootfs build.
#
# PREREQ (AMD internal env; the `petalinux-*` tools must be on PATH):
#   export TMPDIR=/tmp/petalinux-$USER        # BEFORE sourcing (fixes false zlib/ncurses error)
#   ts -petalinux petalinux-v2025.2_released  # GUUP alias that puts petalinux-* on PATH
#   unset XILINX_VITIS XILINX_VIVADO XILINX_HLS XILINX_XRT LD_LIBRARY_PATH  # Vitis env breaks the build
# Long builds: wrap this script in `nohup ... &`.
#
# Env overrides: XSA, PLNX (project dir), SDK_DIR, VITIS (for the host cross-compile).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${XSA:=$HERE/aie/feature_graph_3br.xsa}"
: "${PLNX:=$HERE/plnx}"
: "${SDK_DIR:=/tmp/vck190-sdk}"
: "${VITIS:=/proj/gsd/vivado/2025.2/Vitis/settings64.sh}"
RECIPE_FILES="$HERE/petalinux/project-spec/meta-user/recipes-apps/aie-validate/files"

command -v petalinux-build >/dev/null || { echo "ERROR: petalinux-* not on PATH - source the PetaLinux env first (see header)"; exit 1; }
[ -e "$XSA" ] || { echo "ERROR: XSA not found: $XSA  (run ./build_vivado.sh first)"; exit 1; }
export TMPDIR="${TMPDIR:-/tmp/petalinux-$USER}"; mkdir -p "$TMPDIR"

echo "== [1/7] create project (versal template) =="
[ -d "$PLNX" ] || petalinux-create --type project --template versal --name "$(basename "$PLNX")" --tmpdir "$TMPDIR" -p "$(dirname "$PLNX")"

echo "== [2/7] import hardware (XSA -> SDT/config) =="
( cd "$PLNX" && petalinux-config --get-hw-description="$(dirname "$XSA")" --silentconfig )

echo "== [3/7] overlay committed project-spec (meta-user + configs) =="
cp -rf "$HERE/petalinux/project-spec/"* "$PLNX/project-spec/"
( cd "$PLNX" && petalinux-config --silentconfig )

echo "== [4/7] build SDK (aarch64 XRT sysroot for the host app) =="
( cd "$PLNX" && petalinux-build --sdk )
( cd "$PLNX" && petalinux-package --sysroot -d "$SDK_DIR" ) 2>/dev/null || \
  ( cd "$PLNX/images/linux" && ./sdk.sh -d "$SDK_DIR" -y )

echo "== [5/7] cross-build host_3br against the SDK, stage into recipe =="
ENVSETUP="$(ls "$SDK_DIR"/environment-setup-* 2>/dev/null | head -1)"
[ -n "$ENVSETUP" ] || { echo "ERROR: SDK env-setup not found under $SDK_DIR"; exit 1; }
( unset LD_LIBRARY_PATH XILINX_VITIS XILINX_VIVADO XILINX_HLS XILINX_XRT
  # shellcheck disable=SC1090
  source "$ENVSETUP"
  cd "$HERE/aie/host"
  $CXX -std=c++17 -O2 host_3br.cpp -o host_3br -lxrt_coreutil -pthread
  ${STRIP:-aarch64-amd-linux-strip} host_3br )
cp -f "$HERE/aie/host/host_3br" "$RECIPE_FILES/host_3br"
# host_3br (1-branch 'host') and the xclbin are staged by build_vivado.sh / the SDK build.

echo "== [6/7] final rootfs build (bakes host_3br + xclbin + aie-validate.service) =="
cp -rf "$HERE/petalinux/project-spec/"* "$PLNX/project-spec/"
( cd "$PLNX" && petalinux-build )

echo "== [7/7] package boot image =="
( cd "$PLNX" && petalinux-package --boot --u-boot --force )

echo
echo "DONE: $PLNX/images/linux/  (Image, rootfs, BOOT.BIN, system.dtb)"
echo
echo "TODO (todo #4 - web dashboard deps): add the meta-openembedded/meta-python"
echo "  layer to project-spec/meta-user/conf/, enable python3-numpy in configs/"
echo "  rootfs_config, and IMAGE_INSTALL:append flask/uvicorn in petalinuxbsp.conf."
