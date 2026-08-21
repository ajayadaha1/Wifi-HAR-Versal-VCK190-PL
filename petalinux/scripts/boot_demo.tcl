## boot_d1.tcl - unattended boot of the co-gen D1 image (csi_mux inserted).
## Mirrors boot_inline.tcl but loads BOOT_d1.BIN + the ZOCL dtb (D1 is XRT) +
## rootfs_d1 (d1-validate autorun). Board host via env BOARD_URL (e.g. TCP:morelNN:3121).
## Usage: BOARD_URL=TCP:<host>:3121 xsdb work/petalinux/boot_d1.tcl
set IMG /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux
set BIN $IMG/BOOT_d1.BIN
set URL $::env(BOARD_URL)
proc reconnect {u} { catch {disconnect}; after 2000; connect -url $u; after 4000 }
reconnect $URL
targets -set -nocase -filter {name =~ "PMC"}
puts stderr "INFO: rst -system"; catch {rst -system}; after 8000
catch {targets -set -nocase -filter {name =~ "PMC"}}
puts stderr "INFO: device program BOOT_d1.BIN"
if {[catch {device program $BIN} e]} { puts stderr "FATAL: device program failed: $e"; exit 1 }
puts stderr "INFO: PROGRAM_OK"; after 2000
targets -set -nocase -filter {name =~ "*A72*#0"}
catch {con}; after 1500; catch {stop}
puts stderr "INFO: U-Boot frozen at countdown"
puts stderr "INFO: Image -> 0x00200000";        dow -data $IMG/Image 0x00200000
puts stderr "INFO: boot.scr -> 0x20000000";      dow -data $IMG/boot.scr 0x20000000
puts stderr "INFO: system-default-d1.dtb -> 0x1000"; dow -data $IMG/system-default-d1.dtb 0x00001000
puts stderr "INFO: rootfs_d1 (239M, several min) -> 0x04000000"; dow -data $IMG/rootfs_demo.cpio.gz.u-boot 0x04000000
after 500; catch {con}
puts stderr "INFO: BOOT_RELEASED - autoboot should bring up Linux + d1-validate autorun"
exit 0
