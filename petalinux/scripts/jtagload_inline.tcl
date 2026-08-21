## Step 3 of the inline Arch-B board bring-up on vck190-2 (host morel15).
##
## morel15 has a flaky GEM (DHCP binds, but bulk TFTP dies after one packet -
## PROJECT_STATE.md section 10), so the kernel, device tree and rootfs go
## straight into DDR over JTAG and Ethernet is never involved in booting.
##
## Run this with the A72 halted (xsdb `stop`), which freezes U-Boot mid-countdown
## so the download has time to finish. On `con`, U-Boot resumes, autoboot expires
## and boot.scr's jtag branch runs `booti 0x00200000 0x04000000 0x00001000` by
## itself - no console typing, which matters because com0 is read-only to
## automation (PROJECT_STATE.md section 10).
##
## Addresses match the flow that already booted this board:
##   kernel 0x00200000 · dtb 0x00100000 · ramdisk 0x04000000
set IMG /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux

connect -url TCP:morel15:3121
after 1000
targets -set -nocase -filter {name =~ "*A72*#0"}
stop
after 500

puts stderr "INFO: Image (31M) -> 0x00200000"
dow -data $IMG/Image 0x00200000

## The device tree is ALREADY at 0x1000 - the PLM put it there from BOOT.BIN
## ({type=raw, load=0x1000} in the BIF) - and boot.scr's jtag branch boots with
## `booti 0x00200000 0x04000000 0x00001000`, so it must not be loaded elsewhere.
puts stderr "INFO: boot.scr -> 0x20000000 (scriptaddr; its jtag branch autoboots us)"
dow -data $IMG/boot.scr 0x20000000

puts stderr "INFO: rootfs_inline.cpio.gz.u-boot (237M, several minutes) -> 0x04000000"
dow -data $IMG/rootfs_inline.cpio.gz.u-boot 0x04000000

after 500
con
puts stderr "INFO: DONE - U-Boot resumed; it should autoboot Linux."
puts stderr "INFO: inline-selftest.service then runs csi_ctl selftest and leaves the"
puts stderr "INFO: verdict at DDR 0x70040000 (read it with read_result.tcl)." 
exit
