#!/usr/bin/env python3
# pl_mac.py - minimal PL MAC/PCS bring-up + link/RX check over /dev/mem for the
# VCK190 D2-Ethernet CSI design. Mirrors the register map in sw/csi_ctl.c.
# stdlib only (runs on the board's minimal PetaLinux rootfs).
#
#   pl_mac.py init      # mac-init: 1G, promiscuous, RX+TX on, PCS autoneg
#   pl_mac.py status    # MAC/PCS link + RX counters + parser/mux state
#   pl_mac.py rxwatch   # sample RX bytes over ~3s -> is CSI physically arriving?
#   pl_mac.py start     # start parser (UDP 5500) + s2mm_meta free-running
#   pl_mac.py check     # init + status + rxwatch  (answers "is the link up?")
import mmap, os, struct, sys, time

PL_ETH    = 0xA4080000
PL_PARSER = 0xA4020000
PL_META   = 0xA4030000
PL_MUX    = 0xA4060000

# AXI 1G/2.5G Ethernet Subsystem registers (see sw/csi_ctl.c)
RCW1=0x404; RCW1_RST=0x80000000; RCW1_RX=0x10000000
TC=0x408;   TC_RST=0x80000000;   TC_TX=0x10000000
EMMC=0x410; EMMC_SPD_MASK=0xC0000000; EMMC_1000=0x80000000
MDIO_MC=0x500; MDIO_MC_EN=0x40
MDIO_MCR=0x504; PHYAD_SH=24; REGAD_SH=16; OP_READ=0x8000; OP_WRITE=0x4000; INITIATE=0x800; READY=0x80
MDIO_MWD=0x508; MDIO_MRD=0x50C
FMI=0x708; FMI_PM=0x80000000
RXBL=0x200; RX64BL=0x220; RXUNDRL=0x210; RXOVRL=0x250
PHYADDR=2; BMCR=0x00; BMSR=0x01; BMSR_LINK=0x0004; BMSR_ANDONE=0x0020
BMCR_ANEN=0x1000; BMCR_ANRST=0x0200

AP_CTRL=0x00; AP_START=1; AP_AUTO=0x80
PARSER_PORT=0x10
META_LO=0x10; META_HI=0x14; META_SIZE=0x1c
META_PA=0x70000000; META_WORDS=2
FRAME_B=1084.0  # ~ CSI frame on the wire (42 hdr + 1042 payload)

def omap(base):
    f=os.open("/dev/mem", os.O_RDWR|os.O_SYNC)
    return mmap.mmap(f, 0x1000, offset=base)

def rd(m,off): return struct.unpack("<I", m[off:off+4])[0]
def wr(m,off,v): m[off:off+4]=struct.pack("<I", v & 0xffffffff)
def stat64(m,off):
    lo=rd(m,off); hi=rd(m,off+4); return (hi<<32)|lo   # LSW first latches MSW

def mdio_wait(m):
    for _ in range(200000):
        if rd(m,MDIO_MCR)&READY: return True
    return False
def mdio_read(m,phy,reg):
    if not mdio_wait(m): return None
    wr(m,MDIO_MCR,(phy<<PHYAD_SH)|(reg<<REGAD_SH)|OP_READ|INITIATE)
    if not mdio_wait(m): return None
    return rd(m,MDIO_MRD)&0xffff
def mdio_write(m,phy,reg,val):
    if not mdio_wait(m): return False
    wr(m,MDIO_MWD,val&0xffff)
    wr(m,MDIO_MCR,(phy<<PHYAD_SH)|(reg<<REGAD_SH)|OP_WRITE|INITIATE)
    return mdio_wait(m)

def mac_init(m, autoneg=True):
    wr(m,RCW1,RCW1_RST); wr(m,TC,TC_RST); time.sleep(0.001)
    wr(m,RCW1,0); wr(m,TC,0)
    wr(m,EMMC,(rd(m,EMMC)&~EMMC_SPD_MASK)|EMMC_1000)
    wr(m,MDIO_MC,MDIO_MC_EN|24); time.sleep(0.002)
    wr(m,FMI,rd(m,FMI)|FMI_PM)
    bmcr=(BMCR_ANEN|BMCR_ANRST) if autoneg else 0
    if not mdio_write(m,PHYADDR,BMCR,bmcr): print("  WARN: PCS MDIO write failed")
    wr(m,RCW1,(rd(m,RCW1)&0xffff)|RCW1_RX)
    wr(m,TC,TC_TX)
    print("mac-init: 1G, promiscuous, RX+TX enabled, PCS autoneg=%s" % ("on" if autoneg else "off"))

def status(m, pm=None, xm=None):
    rcw1=rd(m,RCW1); tc=rd(m,TC); emmc=rd(m,EMMC); fmi=rd(m,FMI)
    spd={0:"10M",0x40000000:"100M",0x80000000:"1G"}.get(emmc&EMMC_SPD_MASK,"?")
    print("MAC  rx=%s tx=%s speed=%s promisc=%s" % (
        "ENABLED" if rcw1&RCW1_RX else "disabled", "en" if tc&TC_TX else "dis",
        spd, "yes" if fmi&FMI_PM else "no"))
    bmcr=mdio_read(m,PHYADDR,BMCR); bmsr=mdio_read(m,PHYADDR,BMSR); bmsr=mdio_read(m,PHYADDR,BMSR)
    if bmcr is None or bmsr is None:
        print("PCS  MDIO not responding (run init first)")
    else:
        print("PCS  BMCR=0x%04x BMSR=0x%04x  LINK=%s  autoneg=%s" % (
            bmcr, bmsr, "UP" if bmsr&BMSR_LINK else "DOWN",
            "done" if bmsr&BMSR_ANDONE else "not-done"))
    print("RX   bytes=%d frames64=%d undersize=%d oversize=%d" % (
        stat64(m,RXBL), stat64(m,RX64BL), stat64(m,RXUNDRL), stat64(m,RXOVRL)))
    if pm is not None:
        print("parser ap_ctrl=0x%02x udp_port=%d" % (rd(pm,AP_CTRL), rd(pm,PARSER_PORT)&0xffff))
    if xm is not None:
        print("csi_mux MI0 select=%d (0=parser/live 1=mm2s/DDR)" % (rd(xm,0x40)&0x7))

def rxwatch(m, secs=3.0):
    b0=stat64(m,RXBL); t0=time.time()
    time.sleep(secs)
    b1=stat64(m,RXBL); dt=time.time()-t0
    db=b1-b0
    print("RXWATCH %.1fs: d_bytes=%d  (~%.0f frames, ~%.0f B/s)" % (dt, db, db/FRAME_B, db/dt))
    if db > 0:
        print("  -> LIVE CSI IS ARRIVING at the MAC RX (link up + correct SFP + Pi streaming)")
    else:
        print("  -> NO RX bytes: link DOWN / wrong SFP port / Pi not streaming")

def start(pm, mm):
    wr(mm,META_LO,META_PA&0xffffffff); wr(mm,META_HI,META_PA>>32); wr(mm,META_SIZE,META_WORDS)
    wr(mm,AP_CTRL,AP_START|AP_AUTO)
    wr(pm,PARSER_PORT,5500); wr(pm,AP_CTRL,AP_START|AP_AUTO)
    print("start: parser on UDP 5500, meta->0x%x, free-running" % META_PA)

def parser_on(pm):
    # Start ONLY the csi_udp_parser (feeds mux->AIE). s2mm_meta is deliberately
    # NOT armed, so nothing DMAs into DDR -> cannot corrupt kernel memory.
    wr(pm,PARSER_PORT,5500); wr(pm,AP_CTRL,AP_START|AP_AUTO)
    print("parser-on: UDP 5500, ap_ctrl=0x%02x (parser only, no s2mm_meta -> no DDR write)" % (rd(pm,AP_CTRL)&0xff))

def parser_off(pm):
    wr(pm,AP_CTRL,0)
    print("parser-off: ap_ctrl=0x%02x" % (rd(pm,AP_CTRL)&0xff))

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    m=omap(PL_ETH); pm=omap(PL_PARSER); mm=omap(PL_META); xm=omap(PL_MUX)
    if cmd == "init":
        mac_init(m, autoneg=("noan" not in sys.argv))
    elif cmd == "status":
        status(m, pm, xm)
    elif cmd == "rxwatch":
        rxwatch(m, float(sys.argv[2]) if len(sys.argv) > 2 else 3.0)
    elif cmd == "start":
        start(pm, mm)
    elif cmd == "parseron":
        parser_on(pm)
    elif cmd == "parseroff":
        parser_off(pm)
    elif cmd == "check":
        mac_init(m, autoneg=("noan" not in sys.argv))
        time.sleep(1.5)   # let autoneg settle
        status(m, pm, xm)
        rxwatch(m, 3.0)
    else:
        print("usage: pl_mac.py {init|status|rxwatch [s]|start|check} [noan]")
    print("DONE_pl_mac")

if __name__ == "__main__":
    main()
