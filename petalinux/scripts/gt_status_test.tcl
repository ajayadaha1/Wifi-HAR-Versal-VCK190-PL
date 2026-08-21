## gt_status_test.tcl - measure the GT, then run the loopback frame test.
##
## The point of this script is the STATUS read. eth_gt_phy exports GT state and,
## crucially, free-running heartbeat counters in the userclk2 / rxuserclk2
## domains to eth_loopback_gpio channel 2 (GPIO2_DATA, 0xA40E0008). Reading it
## twice answers the question that blocked bring-up: are the GT clocks actually
## running? The MAC can report "link UP" over MDIO and still never transmit a
## byte, and without this there is no way to tell a stuck reset from a dead
## reference clock. See PROJECT_STATE.md section 14.
##
## Runs with no Linux: `device program` configures the PL and the PLM brings up
## DDR, which is all this needs.
set BIN /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux/images/linux/BOOT_inline.BIN
set META 0x70000000
set TXD  0x70020000
set TXC  0x70030000
set PARSER   0xA4020000
set S2MM_MET 0xA4030000
set CSI_MUX  0xA4060000
set MAC      0xA4080000
set TXD_K    0xA40C0000
set TXC_K    0xA40D0000
set GPIO     0xA40E0000
set GPIO2    0xA40E0008

proc r {a} { return [mrd -force -value $a] }
proc w {a v} { mwr -force $a $v }
proc mdio_wait {} { global MAC ; for {set i 0} {$i<4000} {incr i} { if {[r [expr {$MAC+0x504}]] & 0x80} {return 1}; after 1 }; return 0 }
proc mdio_wr {reg val} { global MAC ; mdio_wait ; w [expr {$MAC+0x508}] $val
    w [expr {$MAC+0x504}] [expr {(2<<24)|($reg<<16)|0x4000|0x800}] ; mdio_wait }
proc mdio_rd {reg} { global MAC ; mdio_wait
    w [expr {$MAC+0x504}] [expr {(2<<24)|($reg<<16)|0x8000|0x800}] ; mdio_wait
    return [expr {[r [expr {$MAC+0x50c}]] & 0xffff}] }

proc show_status {tag} {
    global GPIO2
    set a [r $GPIO2] ; after 300 ; set b [r $GPIO2]
    set hb_tx_a [expr {($a >> 16) & 0xff}] ; set hb_tx_b [expr {($b >> 16) & 0xff}]
    set hb_rx_a [expr {($a >> 24) & 0xff}] ; set hb_rx_b [expr {($b >> 24) & 0xff}]
    puts "  --- GT status ($tag) : 0x[format %08x $a] ---"
    foreach {n bit} {gtpowergood 0 cplllock 1 tx_done 2 rx_done 3 txresetdone 4
                     rxresetdone 5 txpmaresetdone 6 rxpmaresetdone 7
                     pma_reset 8 resetn 9 mmcm_locked 10} {
        puts [format "    %-16s %d" $n [expr {($a >> $bit) & 1}]]
    }
    puts [format "    userclk2   heartbeat %3d -> %3d   %s" $hb_tx_a $hb_tx_b \
            [expr {$hb_tx_a != $hb_tx_b ? "RUNNING" : "*** NOT RUNNING ***"}]]
    puts [format "    rxuserclk2 heartbeat %3d -> %3d   %s" $hb_rx_a $hb_rx_b \
            [expr {$hb_rx_a != $hb_rx_b ? "RUNNING" : "*** NOT RUNNING ***"}]]
}

catch {disconnect}
after 1000
connect -url TCP:morel15:3121
after 4000
targets -set -nocase -filter {name =~ "PMC"}
catch {rst -system}
after 8000
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

show_status "after configuration, before any MAC setup"

## bring the MAC up and put the PHY in loopback
w [expr {$MAC + 0x410}] 0x80000000
w [expr {$MAC + 0x500}] [expr {0x40 | 24}]
after 50
w [expr {$MAC + 0x708}] [expr {[r [expr {$MAC+0x708}]] | 0x80000000}]
w [expr {$MAC + 0x404}] [expr {([r [expr {$MAC+0x404}]] & 0xffff) | 0x10000000}]
w [expr {$MAC + 0x408}] 0x10000000
w $GPIO 0x2
mdio_wr 0x00 0x4140
after 2500
mdio_rd 0x01
puts [format "INFO: PCS BMSR=0x%04x link=%s" [mdio_rd 0x01] \
        [expr {([mdio_rd 0x01] & 0x4) ? "UP" : "down"}]]
show_status "after MAC init + loopback"

mwr -force [expr {$TXD + 0}] {0xffffffff 0x0202ffff 0x02020202 0x00450008 0x00002e01 0x11400000 0x0a0a0000 0x14140a0a 0x39301414 0x1a017c15 0x11110000 0xaaaa08c0 0xaaaaaaaa 0x00011234 0x02d2e02a 0x00000000}
mwr -force [expr {$TXD + 64}] {0xffff0001 0xfffe0002 0xfffd0003 0xfffc0004 0xfffb0005 0xfffa0006 0xfff90007 0xfff80008 0xfff70009 0xfff6000a 0xfff5000b 0xfff4000c 0xfff3000d 0xfff2000e 0xfff1000f 0xfff00010}
mwr -force [expr {$TXD + 128}] {0xffef0011 0xffee0012 0xffed0013 0xffec0014 0xffeb0015 0xffea0016 0xffe90017 0xffe80018 0xffe70019 0xffe6001a 0xffe5001b 0xffe4001c 0xffe3001d 0xffe2001e 0xffe1001f 0xffe00020}
mwr -force [expr {$TXD + 192}] {0xffdf0021 0xffde0022 0xffdd0023 0xffdc0024 0xffdb0025 0xffda0026 0xffd90027 0xffd80028 0xffd70029 0xffd6002a 0xffd5002b 0xffd4002c 0xffd3002d 0xffd2002e 0xffd1002f 0xffd00030}
mwr -force [expr {$TXD + 256}] {0xffcf0031 0xffce0032 0xffcd0033 0xffcc0034 0xffcb0035 0xffca0036 0xffc90037 0xffc80038 0xffc70039 0xffc6003a 0xffc5003b 0xffc4003c 0xffc3003d 0xffc2003e 0xffc1003f}
mwr -force $TXC {0 0 0 0 0}
mwr -force $META {0 0}
w [expr {$CSI_MUX + 0x40}] 0x0 ; w [expr {$CSI_MUX + 0x00}] 0x2
w [expr {$S2MM_MET + 0x10}] $META ; w [expr {$S2MM_MET + 0x14}] 0
w [expr {$S2MM_MET + 0x1c}] 2 ; w [expr {$S2MM_MET + 0x00}] 0x81
w [expr {$PARSER + 0x10}] 5500 ; w [expr {$PARSER + 0x00}] 0x81
w [expr {$TXC_K + 0x10}] $TXC ; w [expr {$TXC_K + 0x14}] 0
w [expr {$TXC_K + 0x1c}] 5 ; w [expr {$TXC_K + 0x00}] 0x1
w [expr {$TXD_K + 0x10}] $TXD ; w [expr {$TXD_K + 0x14}] 0
w [expr {$TXD_K + 0x1c}] 79 ; w [expr {$TXD_K + 0x00}] 0x1
puts "INFO: frame fired"

set lo 0 ; set hi 0
for {set i 0} {$i < 40} {incr i} {
    after 250
    set lo [r $META] ; set hi [r [expr {$META + 4}]]
    if {$lo != 0 || $hi != 0} { break }
}
show_status "after transmit"
puts [format "  MAC txbytes=%u rxbytes=%u | txd=0x%02x txc=0x%02x parser=0x%02x" \
        [r [expr {$MAC+0x208}]] [r [expr {$MAC+0x200}]] [r $TXD_K] [r $TXC_K] [r $PARSER]]

puts "======================================================"
if {$lo == 0 && $hi == 0} { puts "RESULT: FAIL - no metadata record" ; disconnect ; exit 1 }
set seq [expr {$lo & 0xffff}]
set rssi [expr {($lo >> 16) & 0xff}] ; if {$rssi > 127} { set rssi [expr {$rssi-256}] }
set nsub [expr {(($lo >> 24) & 0xff) | (($hi & 0xffff) << 8)}]
set chanspec [expr {($hi >> 8) & 0xffff}] ; set coresp [expr {($hi >> 24) & 0xff}]
puts [format "metadata 0x%08x%08x" $hi $lo]
set bad 0
foreach {n got want} [list seq $seq 4660 rssi $rssi -64 n_sub $nsub 64 \
                           chanspec $chanspec 57386 core_spatial $coresp 1] {
    set ok [expr {$got == $want}] ; if {!$ok} { incr bad }
    puts [format "  %-13s got %-8d want %-8d %s" $n $got $want [expr {$ok ? "ok" : "MISMATCH"}]]
}
if {$bad} { puts "RESULT: FAIL ($bad mismatches)" ; disconnect ; exit 1 }
puts "RESULT: PASS - MAC TX -> loopback -> MAC RX -> parser -> DDR bit-correct"
puts "======================================================"
disconnect
exit 0
