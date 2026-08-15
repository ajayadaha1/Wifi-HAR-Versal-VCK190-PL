#!/usr/bin/env bash
# build.sh — cross-compile host.cpp for the VCK190 A72 using the PetaLinux SDK.
#
# 1) Install the SDK once it is built:
#      work/petalinux/petalinux/images/linux/sdk.sh -d /tmp/vck190-sdk -y
# 2) Then run this:  bash build.sh   (or pass a custom env-setup path)
#
# The SDK's environment-setup script sets $CXX/$SYSROOT to the aarch64
# cross-toolchain that provides the target XRT headers + libs.
set -euo pipefail
ENV=${1:-/tmp/vck190-sdk/environment-setup-cortexa72-cortexa53-amd-linux}
if [ ! -f "$ENV" ]; then
  echo "SDK env-setup not found: $ENV"
  echo "Build+install the SDK first:"
  echo "  (in work/petalinux/petalinux) petalinux-build --sdk"
  echo "  ./images/linux/sdk.sh -d /tmp/vck190-sdk -y"
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV"
cd "$(dirname "$0")"
$CXX -std=c++17 -O2 host.cpp -o host -lxrt_coreutil -pthread
echo "OK built: $(file host | cut -d: -f2-)"
