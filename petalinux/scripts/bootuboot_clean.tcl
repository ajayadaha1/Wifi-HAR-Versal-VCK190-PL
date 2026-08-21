## Boot the CLEAN 3-branch image. BOOT_3br_clean.BIN = 3-branch PL PDI + freshly
## petalinux-built PLM/psmfw/bl31/u-boot + aie_image + the clean 3-branch dtb
## (zocl node + 6 CUs baked). Reaches U-Boot; then TFTP the clean Image /
## system.dtb / rootfs.cpio.gz.u-boot -- all fixes baked in, NO boot-time patching.
connect -url TCP:morel15:3121
after 3000
targets -set -nocase -filter {name =~ "PMC"}
rst -por
after 10000
disconnect
after 2000
connect -url TCP:morel15:3121
targets -set -nocase -filter {name =~ "PMC"}
puts stderr "INFO: device program BOOT_3br_clean.BIN -> U-Boot (clean 3-branch)"
device program "/group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux/BOOT_3br_clean.BIN"
after 2000
catch {targets -set -nocase -filter {name =~ "*A72*#0"}; con}
puts stderr "INFO: A72 released to U-Boot. TFTP the clean Image/system.dtb/rootfs."
exit
