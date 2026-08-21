## jtag_loopback_test.tcl - inline Arch-B Ethernet loopback self-test, driven
## entirely over JTAG: no Linux, no console, no network.
##
## com0 is read-only to automation and morel15's GEM is unreliable, so the test
## is driven from the host. Every register and DDR buffer it needs is reachable
## from xsdb, and this works whether or not Linux booted.
##
## Physical memory MUST go through the "MicroBlaze PSM" (or "Versal*") context:
## plain "PSM" silently returns zeros and the A72 context faults through the MMU.
## The script proves the context is right by checking the arm64 kernel magic at
## 0x00200038 before trusting anything else.
##
## It sweeps loopback strategies because there is more than one way to close the
## loop and they fail differently:
##   pcs-mdio  PCS internal loopback via BMCR bit 14 - loops inside the MAC's own
##             1000BASE-X PCS, before the transceiver. Proves MAC+parser+DDR even
##             if the GT is not usable.
##   gt-*      the transceiver's own loopback, via eth_loopback_gpio. Note the
##             wizard names that port QUAD0_ch0_loopback even though our lane is
##             mapped to quad channel 2, so it is worth confirming it bites.
##
## Usage:  xsdb work/petalinux/jtag_loopback_test.tcl
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

proc r {a} { return [mrd -force -value $a] }
proc w {a v} { mwr -force $a $v }

## MDIO to the PCS/PMA internal to the MAC, at PHYADDR 2. MDIO_MRD returns more
## than 16 bits, so callers mask.
proc mdio_wait {} {
    global MAC
    for {set i 0} {$i < 4000} {incr i} {
        if {[r [expr {$MAC + 0x504}]] & 0x80} { return 1 }
        after 1
    }
    puts "WARN: MDIO timeout"
    return 0
}
proc mdio_wr {reg val} {
    global MAC
    mdio_wait
    w [expr {$MAC + 0x508}] $val
    w [expr {$MAC + 0x504}] [expr {(2 << 24) | ($reg << 16) | 0x4000 | 0x800}]
    mdio_wait
}
proc mdio_rd {reg} {
    global MAC
    mdio_wait
    w [expr {$MAC + 0x504}] [expr {(2 << 24) | ($reg << 16) | 0x8000 | 0x800}]
    mdio_wait
    return [expr {[r [expr {$MAC + 0x50c}]] & 0xffff}]
}

## One attempt: set the loopback up the requested way, fire one frame, report.
proc attempt {name gpio bmcr} {
    global META TXD TXC PARSER S2MM_MET CSI_MUX MAC TXD_K TXC_K GPIO
    puts "\n=== attempt: $name (gpio=$gpio bmcr=0x[format %04x $bmcr]) ==="

    ## quiesce, then re-arm from a known state
    w [expr {$PARSER + 0x00}] 0
    w [expr {$S2MM_MET + 0x00}] 0
    after 200
    w [expr {$MAC + 0x000}] [expr {[r [expr {$MAC + 0x000}]] | 0x2000}]   ;# RAF: reset stats
    after 100
    w [expr {$MAC + 0x000}] [expr {[r [expr {$MAC + 0x000}]] & ~0x2000}]
    mwr -force $META {0 0}

    w $GPIO $gpio
    mdio_wr 0x00 $bmcr
    after 2500
    mdio_rd 0x01
    set bmsr [mdio_rd 0x01]
    puts [format "  PCS BMCR=0x%04x BMSR=0x%04x link=%s aneg=%s" [mdio_rd 0x00] $bmsr \
            [expr {($bmsr & 0x4) ? "UP" : "down"}] [expr {($bmsr & 0x20) ? "done" : "no"}]]

    ## receive side
    w [expr {$CSI_MUX + 0x40}] 0x0
    w [expr {$CSI_MUX + 0x00}] 0x2
    w [expr {$S2MM_MET + 0x10}] $META
    w [expr {$S2MM_MET + 0x14}] 0x0
    w [expr {$S2MM_MET + 0x1c}] 2
    w [expr {$S2MM_MET + 0x00}] 0x81
    w [expr {$PARSER + 0x10}] 5500
    w [expr {$PARSER + 0x00}] 0x81

    ## fire: control packet first, then the frame
    w [expr {$TXC_K + 0x10}] $TXC ; w [expr {$TXC_K + 0x14}] 0
    w [expr {$TXC_K + 0x1c}] 5    ; w [expr {$TXC_K + 0x00}] 0x1
    w [expr {$TXD_K + 0x10}] $TXD ; w [expr {$TXD_K + 0x14}] 0
    w [expr {$TXD_K + 0x1c}] 79   ; w [expr {$TXD_K + 0x00}] 0x1

    set lo 0 ; set hi 0
    for {set i 0} {$i < 40} {incr i} {
        after 250
        set lo [r $META] ; set hi [r [expr {$META + 4}]]
        if {$lo != 0 || $hi != 0} { break }
    }
    set rxb [r [expr {$MAC + 0x200}]]
    set txb [r [expr {$MAC + 0x208}]]
    puts [format "  MAC txbytes=%u rxbytes=%u | txd=0x%02x txc=0x%02x parser=0x%02x" \
            $txb $rxb [r $TXD_K] [r $TXC_K] [r $PARSER]]
    if {$lo == 0 && $hi == 0} { puts "  -> no metadata" ; return 0 }

    set seq      [expr {$lo & 0xffff}]
    set rssi     [expr {($lo >> 16) & 0xff}]
    if {$rssi > 127} { set rssi [expr {$rssi - 256}] }
    set nsub     [expr {(($lo >> 24) & 0xff) | (($hi & 0xffff) << 8)}]
    set chanspec [expr {($hi >> 8) & 0xffff}]
    set coresp   [expr {($hi >> 24) & 0xff}]
    puts [format "  metadata 0x%08x%08x" $hi $lo]
    set bad 0
    foreach {n got want} [list seq $seq 4660 rssi $rssi -64 n_sub $nsub 64 \
                               chanspec $chanspec 57386 core_spatial $coresp 1] {
        set ok [expr {$got == $want}]
        if {!$ok} { incr bad }
        puts [format "    %-13s got %-8d want %-8d %s" $n $got $want [expr {$ok ? "ok" : "MISMATCH"}]]
    }
    if {$bad} { puts "  -> FAIL ($bad mismatches)" ; return 0 }
    puts "  -> PASS"
    return 1
}

connect -url TCP:morel15:3121
after 3000
targets -set -nocase -filter {name =~ "MicroBlaze PSM"}
if {[r 0x00200038] != 0x644d5241} {
    puts "FATAL: this memory context is not reading physical DDR"
    exit 2
}
puts "INFO: physical DDR access confirmed"

puts "INFO: writing the nexmon CSI frame (316 B, 64 subcarriers)"
mwr -force [expr {$TXD + 0}] {0xffffffff 0x0202ffff 0x02020202 0x00450008 0x00002e01 0x11400000 0x0a0a0000 0x14140a0a 0x39301414 0x1a017c15 0x11110000 0xaaaa08c0 0xaaaaaaaa 0x00011234 0x02d2e02a 0x00000000}
mwr -force [expr {$TXD + 64}] {0xffff0001 0xfffe0002 0xfffd0003 0xfffc0004 0xfffb0005 0xfffa0006 0xfff90007 0xfff80008 0xfff70009 0xfff6000a 0xfff5000b 0xfff4000c 0xfff3000d 0xfff2000e 0xfff1000f 0xfff00010}
mwr -force [expr {$TXD + 128}] {0xffef0011 0xffee0012 0xffed0013 0xffec0014 0xffeb0015 0xffea0016 0xffe90017 0xffe80018 0xffe70019 0xffe6001a 0xffe5001b 0xffe4001c 0xffe3001d 0xffe2001e 0xffe1001f 0xffe00020}
mwr -force [expr {$TXD + 192}] {0xffdf0021 0xffde0022 0xffdd0023 0xffdc0024 0xffdb0025 0xffda0026 0xffd90027 0xffd80028 0xffd70029 0xffd6002a 0xffd5002b 0xffd4002c 0xffd3002d 0xffd2002e 0xffd1002f 0xffd00030}
mwr -force [expr {$TXD + 256}] {0xffcf0031 0xffce0032 0xffcd0033 0xffcc0034 0xffcb0035 0xffca0036 0xffc90037 0xffc80038 0xffc70039 0xffc6003a 0xffc5003b 0xffc4003c 0xffc3003d 0xffc2003e 0xffc1003f}
mwr -force $TXC {0 0 0 0 0}

## MAC: 1G, MDIO on, promiscuous, RX+TX enabled. FCS bits left clear so the MAC
## inserts FCS on TX and strips it on RX, which is what csi_udp_parser assumes.
w [expr {$MAC + 0x410}] 0x80000000
w [expr {$MAC + 0x500}] [expr {0x40 | 24}]
after 50
w [expr {$MAC + 0x708}] [expr {[r [expr {$MAC + 0x708}]] | 0x80000000}]
w [expr {$MAC + 0x404}] [expr {([r [expr {$MAC + 0x404}]] & 0xffff) | 0x10000000}]
w [expr {$MAC + 0x408}] 0x10000000
puts [format "INFO: MAC RCW1=0x%08x TC=0x%08x EMMC=0x%08x" \
        [r [expr {$MAC + 0x404}]] [r [expr {$MAC + 0x408}]] [r [expr {$MAC + 0x410}]]]

## 0x0140 = 1000 Mb/s + full duplex; 0x4000 adds PCS internal loopback,
## 0x1000/0x0200 are autoneg enable/restart.
set pass 0
foreach {name gpio bmcr} {
    pcs-mdio-loopback      0 0x4140
    gt-near-pma            2 0x0140
    gt-near-pma-autoneg    2 0x1340
    gt-near-pcs            1 0x0140
    gt-far-pma             4 0x0140
    pcs-mdio+gt-near-pma   2 0x4140
} {
    if {[attempt $name $gpio $bmcr]} { set pass 1 ; set winner $name ; break }
}

puts "\n======================================================"
if {$pass} {
    puts "RESULT: PASS via $winner"
    puts "  MAC TX -> loopback -> MAC RX -> csi_udp_parser -> s2mm_meta -> DDR"
    puts "  is bit-correct on real silicon."
} else {
    puts "RESULT: FAIL - no strategy closed the loop"
}
puts "======================================================"
disconnect
exit [expr {$pass ? 0 : 1}]
