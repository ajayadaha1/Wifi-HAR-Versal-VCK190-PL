## Step 1 of the inline Arch-B board bring-up on vck190-2 (host morel15).
##
## Programs BOOT_inline.BIN, which carries the inline PL PDI + PLM/psmfw/bl31/
## u-boot + the AIE graph CDO (aie_image) + system-inline.dtb, and releases the
## A72 to U-Boot. Everything is baked in - no boot-time patching (see
## PROJECT_STATE.md sections 12-13).
##
## Full sequence:
##   1) xsdb bootuboot_inline.tcl   <- this: POR + program -> U-Boot
##   2) at com0, press a key at the "Hit any key to stop autoboot" countdown
##   3) xsdb jtagload_inline.tcl    -> DDR-load Image / dtb / rootfs over JTAG
##   4) at the U-Boot prompt:  booti 0x200000 0x4000000 0x100000
##
## A POR first is mandatory: once the board has run Linux, `device program`
## fails with PLM Error Major 0x302 / Minor 0x4001 (PROJECT_STATE.md section 10).
set BIN /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux/BOOT_inline.BIN

connect -url TCP:morel15:3121
after 3000
targets -set -nocase -filter {name =~ "PMC"}
rst -por
after 10000
disconnect
after 2000

## the JTAG chain re-enumerates after a POR, so reconnect before programming
connect -url TCP:morel15:3121
after 5000
targets -set -nocase -filter {name =~ "PMC"}
puts stderr "INFO: device program $BIN"
device program $BIN
after 2000
catch {targets -set -nocase -filter {name =~ "*A72*#0"}; con}
puts stderr "INFO: A72 released to U-Boot. Stop autoboot at com0, then run jtagload_inline.tcl"
exit
