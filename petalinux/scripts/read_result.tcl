## read_result.tcl - collect the inline self-test verdict from the board.
##
## csi_ctl selftest leaves a result block in DDR at 0x70040000 (inside the 1 MB
## no-map carve-out, so Linux never touches it). Reading it over JTAG is how the
## test reports back: com0 is read-only to automation, and morel15's GEM is too
## flaky to rely on for ssh, so DDR + JTAG is the only channel that always works.
##
## Reads through the DPC target before boot, or the APU once Linux is running
## (DPC disappears after the PLM runs). Either way the A72 is not halted.
##
## Usage:  xsdb work/petalinux/read_result.tcl
set BASE 0x70040000
set META 0x70000000

connect -url TCP:morel15:3121
after 3000
## DPC only exists before the PLM runs; once Linux is up, read through the APU
## (non-intrusively - the A72 keeps running).
if {[catch {targets -set -nocase -filter {name =~ "DPC"}}]} {
    targets -set -nocase -filter {name =~ "*A72*#0"}
}

set w {}
for {set i 0} {$i < 12} {incr i} {
    if {[catch {set v [mrd -force -value [format 0x%x [expr {$BASE + 4*$i}]]]} e]} {
        puts "READ_FAIL at word $i: $e"
        exit 2
    }
    lappend w $v
}

set magic   [lindex $w 0]
set verdict [lindex $w 1]

puts "---- inline self-test result block @ $BASE ----"
if {$magic != 0xC5170001} {
    puts [format "magic 0x%08x - NOT VALID (expected 0xC5170001)" $magic]
    puts "The self-test has not written a result yet: Linux may still be booting,"
    puts "or inline-selftest.service did not run. Wait and re-read."
    exit 1
}
puts [format "magic        0x%08x  ok" $magic]
if {$verdict == 0xffffffff} {
    puts "verdict      IN PROGRESS (block initialised, test still running)"
    exit 1
}
puts [format "verdict      %s" [expr {$verdict == 0 ? "PASS" : "FAIL"}]]
puts [format "stage        %d  (1 mac-init, 2 link checked, 3 txtest done)" [lindex $w 2]]

set mlo [lindex $w 3]
set mhi [lindex $w 4]
puts [format "metadata     0x%08x%08x" $mhi $mlo]
if {$mlo != 0 || $mhi != 0} {
    set seq      [expr {$mlo & 0xffff}]
    set rssi     [expr {($mlo >> 16) & 0xff}]
    if {$rssi > 127} { set rssi [expr {$rssi - 256}] }
    set nsub     [expr {(($mlo >> 24) & 0xff) | (($mhi & 0xffff) << 8)}]
    set chanspec [expr {($mhi >> 8) & 0xffff}]
    set coresp   [expr {($mhi >> 24) & 0xff}]
    puts [format "  seq        0x%04x   (expected 0x1234)" $seq]
    puts [format "  rssi       %d dBm  (expected -64)" $rssi]
    puts [format "  n_sub      %d      (expected 64)" $nsub]
    puts [format "  chanspec   0x%04x   (expected 0xe02a)" $chanspec]
    puts [format "  core/spat  0x%02x     (expected 0x01)" $coresp]
}
puts [format "MAC RCW1     0x%08x  rx=%s" [lindex $w 5] \
        [expr {([lindex $w 5] & 0x10000000) ? "ENABLED" : "disabled"}]]
puts [format "PCS BMSR     0x%04x      link=%s" [lindex $w 6] \
        [expr {([lindex $w 6] & 0x4) ? "UP" : "down"}]]
puts [format "MAC rx frames %d" [lindex $w 7]]
puts [format "MAC rx bytes  %d" [lindex $w 11]]
puts [format "ap_ctrl      parser 0x%02x  txd 0x%02x  txc 0x%02x" \
        [lindex $w 8] [lindex $w 9] [lindex $w 10]]
puts "-----------------------------------------------"
disconnect
exit [expr {$verdict == 0 ? 0 : 1}]
