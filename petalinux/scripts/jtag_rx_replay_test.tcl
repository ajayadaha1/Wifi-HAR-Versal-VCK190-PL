## jtag_rx_replay_test.tcl - prove the CSI ingest chain on silicon, no MAC.
##
## Pushes a synthetic nexmon_csi frame from DDR straight into the real parser via
## the rx_mux replay port, and checks the metadata the parser produces comes back
## in DDR:
##
##     DDR -> mm2s_rx -> rx_inj_dwidth(32->8) -> rx_mux(S01)
##         -> csi_udp_parser -> meta_dwidth -> s2mm_meta -> DDR
##
## This deliberately avoids the MAC (which will not transmit - PROJECT_STATE #14)
## and the AIE, so it isolates the CSI ingest logic. The frame is byte-identical
## to the one in udp_parser/csi_udp_parser_tb.cpp that the parser's C/RTL
## co-simulation was validated against, so any mismatch is a hardware problem,
## not new stimulus.
##
## Runs with no Linux and no console: `device program` configures the PL and the
## PLM brings up DDR.
##
## Usage:  xsdb work/petalinux/jtag_rx_replay_test.tcl
set BIN /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux/BOOT_inline.BIN
set META  0x70000000
set RXBUF 0x70020000
set PARSER   0xA4020000
set S2MM_MET 0xA4030000
set MM2S_RX  0xA4070000
set RX_MUX   0xA40F0000
proc r {a} { return [mrd -force -value $a] }
proc w {a v} { mwr -force $a $v }

catch {disconnect} ; after 1000
connect -url TCP:morel15:3121 ; after 4000
targets -set -nocase -filter {name =~ "PMC"}
catch {rst -system} ; after 8000
catch {targets -set -nocase -filter {name =~ "PMC"}}
if {[catch {device program $BIN} e]} { puts "FATAL: device program: $e" ; exit 2 }
puts "INFO: PL configured"
after 4000

set ctx ""
foreach f {"MicroBlaze PSM" "Versal*"} {
    if {[catch {targets -set -nocase -filter "name =~ \"$f\""}]} { continue }
    catch {mwr -force 0x70050000 0xA5A5F00D}
    if {![catch {set v [mrd -force -value 0x70050000]}] && $v == 0xA5A5F00D} { set ctx $f ; break }
}
if {$ctx eq ""} { puts "FATAL: no DDR access" ; exit 2 }
puts "INFO: DDR access via '$ctx'"

puts "INFO: writing the nexmon CSI frame (316 B, 64 subcarriers) to $RXBUF"
mwr -force [expr {$RXBUF + 0}] {0xffffffff 0x0202ffff 0x02020202 0x00450008 0x00002e01 0x11400000 0x0a0a0000 0x14140a0a 0x39301414 0x1a017c15 0x11110000 0xaaaa08c0 0xaaaaaaaa 0x00011234 0x02d2e02a 0x00000000}
mwr -force [expr {$RXBUF + 64}] {0xffff0001 0xfffe0002 0xfffd0003 0xfffc0004 0xfffb0005 0xfffa0006 0xfff90007 0xfff80008 0xfff70009 0xfff6000a 0xfff5000b 0xfff4000c 0xfff3000d 0xfff2000e 0xfff1000f 0xfff00010}
mwr -force [expr {$RXBUF + 128}] {0xffef0011 0xffee0012 0xffed0013 0xffec0014 0xffeb0015 0xffea0016 0xffe90017 0xffe80018 0xffe70019 0xffe6001a 0xffe5001b 0xffe4001c 0xffe3001d 0xffe2001e 0xffe1001f 0xffe00020}
mwr -force [expr {$RXBUF + 192}] {0xffdf0021 0xffde0022 0xffdd0023 0xffdc0024 0xffdb0025 0xffda0026 0xffd90027 0xffd80028 0xffd70029 0xffd6002a 0xffd5002b 0xffd4002c 0xffd3002d 0xffd2002e 0xffd1002f 0xffd00030}
mwr -force [expr {$RXBUF + 256}] {0xffcf0031 0xffce0032 0xffcd0033 0xffcc0034 0xffcb0035 0xffca0036 0xffc90037 0xffc80038 0xffc70039 0xffc6003a 0xffc5003b 0xffc4003c 0xffc3003d 0xffc2003e 0xffc1003f}
mwr -force $META {0 0}

## parser input <- replay port
w [expr {$RX_MUX + 0x40}] 0x1
w [expr {$RX_MUX + 0x00}] 0x2
after 200
puts [format "INFO: rx_mux MI0 = 0x%08x (1 = replay from DDR)" [r [expr {$RX_MUX + 0x40}]]]

## arm the receive side before injecting
w [expr {$S2MM_MET + 0x10}] $META ; w [expr {$S2MM_MET + 0x14}] 0
w [expr {$S2MM_MET + 0x1c}] 2     ; w [expr {$S2MM_MET + 0x00}] 0x81
w [expr {$PARSER + 0x10}] 5500    ; w [expr {$PARSER + 0x00}] 0x81
puts [format "INFO: parser=0x%02x s2mm_meta=0x%02x" [r $PARSER] [r $S2MM_MET]]

## inject
w [expr {$MM2S_RX + 0x10}] $RXBUF ; w [expr {$MM2S_RX + 0x14}] 0
w [expr {$MM2S_RX + 0x1c}] 79     ; w [expr {$MM2S_RX + 0x00}] 0x1
puts "INFO: frame injected"

set lo 0 ; set hi 0
for {set i 0} {$i < 40} {incr i} {
    after 250
    set lo [r $META] ; set hi [r [expr {$META + 4}]]
    if {$lo != 0 || $hi != 0} { break }
}
puts [format "INFO: mm2s_rx=0x%02x parser=0x%02x s2mm_meta=0x%02x" \
        [r $MM2S_RX] [r $PARSER] [r $S2MM_MET]]

puts "======================================================"
if {$lo == 0 && $hi == 0} {
    puts "RESULT: FAIL - parser produced no metadata"
    puts "  mm2s_rx not idle => the replay mover stalled (DDR read or stream)"
    puts "  mm2s_rx idle     => the parser did not accept/emit"
    disconnect ; exit 1
}
set seq      [expr {$lo & 0xffff}]
set rssi     [expr {($lo >> 16) & 0xff}] ; if {$rssi > 127} { set rssi [expr {$rssi - 256}] }
set nsub     [expr {(($lo >> 24) & 0xff) | (($hi & 0xffff) << 8)}]
set chanspec [expr {($hi >> 8) & 0xffff}]
set coresp   [expr {($hi >> 24) & 0xff}]
puts [format "metadata 0x%08x%08x" $hi $lo]
set bad 0
foreach {n got want} [list seq $seq 4660 rssi $rssi -64 n_sub $nsub 64 \
                           chanspec $chanspec 57386 core_spatial $coresp 1] {
    set ok [expr {$got == $want}] ; if {!$ok} { incr bad }
    puts [format "  %-13s got %-8d want %-8d %s" $n $got $want [expr {$ok ? "ok" : "MISMATCH"}]]
}
if {$bad} { puts "RESULT: FAIL ($bad mismatches)" ; disconnect ; exit 1 }
puts "RESULT: PASS - DDR -> csi_udp_parser -> s2mm_meta -> DDR is bit-correct on silicon"
puts "======================================================"
disconnect
exit 0
