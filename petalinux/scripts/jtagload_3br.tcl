## No-Ethernet boot helper for morel15 (bad-gem => no TFTP/scp).
## Loads kernel Image, the clean 3-branch dtb, and the rootfs straight into DDR
## over JTAG, so we never need Ethernet.
##
## Flow:
##   1) xsdb bootuboot_clean.tcl      -> brings up U-Boot
##   2) at com0, hit a key at the "autoboot" countdown to stop at the U-Boot prompt
##   3) xsdb jtagload_3br.tcl         -> this script (halts A72, DDR-loads, resumes)
##   4) at the U-Boot prompt (com0):  booti 0x200000 0x4000000 0x100000
##
## Addresses match the old TFTP flow: kernel@0x200000, ramdisk@0x4000000, dtb@0x100000.
set IMG /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux
connect -url TCP:morel15:3121
after 1000
targets -set -nocase -filter {name =~ "*A72*#0"}
stop
after 500
puts stderr "INFO: JTAG-load Image (31M) -> 0x00200000"
dow -data $IMG/Image 0x00200000
puts stderr "INFO: JTAG-load system.dtb (clean 3-branch) -> 0x00100000"
dow -data $IMG/system.dtb 0x00100000
puts stderr "INFO: JTAG-load rootfs.cpio.gz.u-boot (238M, takes a few minutes) -> 0x04000000"
dow -data $IMG/rootfs.cpio.gz.u-boot 0x04000000
after 500
con
puts stderr "INFO: DONE. At the U-Boot prompt run:  booti 0x200000 0x4000000 0x100000"
exit
