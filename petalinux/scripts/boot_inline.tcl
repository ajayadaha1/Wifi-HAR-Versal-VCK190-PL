## boot_inline.tcl - one-shot, unattended boot of the inline Arch-B image on
## vck190-2 (host morel15). Replaces the two-step bootuboot/jtagload pair,
## because the two steps have to be atomic: U-Boot must be frozen mid-countdown
## before the 237 MB rootfs download starts, and the only way to be sure of that
## is to program it and halt it in the same session.
##
## Sequence:
##   1. rst -system, then program BOOT_inline.BIN.
##      NOT rst -por: on a board that has already run, POR leaves the boot ROM
##      wedged and `device program` fails with "ROM in error state" every time.
##      rst -system clears it. (Boot mode is already JTAG - PMC_GLOBAL
##      BOOT_MODE_USER/POR at 0xf1110200/4 both read 0, checked over the DPC
##      target, which is the only one with memory access before the PLM runs.)
##   2. Release the A72 to U-Boot, then immediately halt it. U-Boot sits frozen
##      at "Hit any key to stop autoboot" for as long as the download needs -
##      this looks like a hang but is normal (PROJECT_STATE.md section 10).
##   3. JTAG-load kernel, boot.scr, device tree and rootfs into DDR. morel15's
##      GEM is too flaky for TFTP, so nothing is fetched over the network.
##      The PLM has ALREADY placed the dtb at 0x1000 from BOOT.BIN
##      ({type=raw, load=0x1000} in the BIF), so re-loading it here is
##      redundant on a matched pair - but it is only 132 KB, and it means a
##      device-tree change can be tested by re-running this script alone,
##      without a bootgen rebuild. Given how much of this bring-up has been
##      device-tree bugs (see check_linux_dtb.py), that is worth 132 KB.
##   4. con. U-Boot resumes, autoboot expires, and boot.scr's jtag branch runs
##      `booti 0x00200000 0x04000000 0x00001000` on its own - no console typing,
##      which matters because com0 is read-only to automation.
##   5. inline-selftest.service runs csi_ctl selftest and leaves the verdict at
##      DDR 0x70040000; collect it with read_result.tcl.
##
## Usage:  xsdb work/petalinux/boot_inline.tcl
set IMG /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux
set BIN $IMG/BOOT_inline.BIN

proc reconnect {} {
    catch {disconnect}
    after 2000
    connect -url TCP:morel15:3121
    after 4000
}

reconnect
targets -set -nocase -filter {name =~ "PMC"}

puts stderr "INFO: rst -system (clears a wedged boot ROM)"
catch {rst -system}
after 8000
catch {targets -set -nocase -filter {name =~ "PMC"}}

puts stderr "INFO: device program [file tail $BIN]"
if {[catch {device program $BIN} e]} {
    puts stderr "FATAL: device program failed: $e"
    exit 1
}
puts stderr "INFO: PROGRAM_OK"
after 2000

## release to U-Boot, then freeze it before the countdown can expire
targets -set -nocase -filter {name =~ "*A72*#0"}
catch {con}
after 1500
catch {stop}
puts stderr "INFO: U-Boot frozen at the autoboot countdown"

puts stderr "INFO: Image -> 0x00200000"
dow -data $IMG/Image 0x00200000
puts stderr "INFO: boot.scr -> 0x20000000"
dow -data $IMG/boot.scr 0x20000000
puts stderr "INFO: system-inline.dtb -> 0x00001000"
dow -data $IMG/system-inline.dtb 0x00001000
puts stderr "INFO: rootfs_inline.cpio.gz.u-boot (237M, several minutes) -> 0x04000000"
dow -data $IMG/rootfs_inline.cpio.gz.u-boot 0x04000000

after 500
catch {con}
puts stderr "INFO: BOOT_RELEASED - U-Boot resumed, autoboot should bring up Linux"
exit 0
