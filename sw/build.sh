#!/bin/bash
# Cross-compile csi_ctl for the VCK190 (aarch64) using the PetaLinux SDK9 sysroot.
# The sysroot lives in /tmp and does not survive a reboot; recreate it with
#   work/petalinux/petalinux/images/linux/sdk.sh -d /tmp/vck190-sdk -y
set -e
SDK=${SDK:-/tmp/vck190-sdk}
if [ -f "$SDK/environment-setup-cortexa72-cortexa53-amd-linux" ]; then
    # shellcheck disable=SC1090
    source "$SDK/environment-setup-cortexa72-cortexa53-amd-linux"
    ${CC} -O2 -Wall -Wextra -o csi_ctl csi_ctl.c
else
    echo "SDK sysroot not found at $SDK, falling back to the Vitis cross gcc" >&2
    /proj/gsd/vivado/2025.2/Vitis/gnu/aarch64/lin/aarch64-linux/bin/aarch64-linux-gnu-gcc \
        -O2 -Wall -Wextra -static -o csi_ctl csi_ctl.c
fi
file csi_ctl
