// ---------------------------------------------------------------------------
// csi_ctl.c - bring-up and control for the inline Arch-B design (inline.xsa).
//
// The inline design is a plain Vivado design, NOT a Vitis platform: there is no
// xclbin and XRT does not apply, so the aie/feature_graph/host apps are not
// usable here. Everything is driven by writing the AXI-Lite slaves directly
// through /dev/mem.
//
// There is also deliberately no axi_dma in the design (the PS is kept out of the
// CSI datapath), so the Linux axienet driver never binds and nothing configures
// the MAC for us - that is what `mac-init` below is for.
//
// Register offsets are taken from the shipped drivers, not invented:
//   MAC     Vivado .../drivers/axiethernet_v5_18/src/xaxiethernet_hw.h
//   parser  work/hw/ip_repo/csi_udp_parser/drivers/.../xcsi_udp_parser_hw.h
//   s2mm    work/hw/ip_repo/s2mm/drivers/.../xs2mm_hw.h
//
// Build (native on the target):  gcc -O2 -Wall -o csi_ctl csi_ctl.c
// Cross:  $CC -O2 -Wall -o csi_ctl csi_ctl.c     (SDK9 aarch64 sysroot)
// ---------------------------------------------------------------------------
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// --- address map (auto-assigned by add_eth_phy; see PROJECT_STATE.md #12) ----
#define PL_BASE          0xA4000000UL
#define PL_SPAN          0x00100000UL   // covers 0xA400_0000 .. 0xA40F_FFFF

// These offsets are PINNED in the block design (inline_design.tcl pins them and
// then asserts they landed); do not let them drift.
#define OFF_MM2S         0x00000000UL   // 0xA400_0000  AIE input replay mover
#define OFF_S2MM         0x00010000UL   // 0xA401_0000  AIE result writer
#define OFF_PARSER       0x00020000UL   // 0xA402_0000
#define OFF_S2MM_META    0x00030000UL   // 0xA403_0000
#define OFF_CSI_MUX      0x00060000UL   // 0xA406_0000
#define OFF_ETH          0x00080000UL   // 0xA408_0000, 256 KB
#define OFF_MM2S_TXD     0x000C0000UL   // 0xA40C_0000  TX frame injector
#define OFF_MM2S_TXC     0x000D0000UL   // 0xA40D_0000  TX control-packet injector
#define OFF_LOOPBACK     0x000E0000UL   // 0xA40E_0000  axi_gpio -> GT loopback

// axi_gpio
#define GPIO_DATA        0x00
#define GPIO_TRI         0x04
// GT loopback encodings (gtwiz / GTY)
#define LB_NORMAL        0
#define LB_NEAR_PCS      1
#define LB_NEAR_PMA      2
#define LB_FAR_PMA       4
#define LB_FAR_PCS       6

// --- HLS ap_ctrl_hs control registers (parser, s2mm, s2mm_meta) -------------
#define HLS_AP_CTRL      0x00
#define HLS_GIE          0x04
#define  AP_START        (1u << 0)
#define  AP_DONE         (1u << 1)
#define  AP_IDLE         (1u << 2)
#define  AP_READY        (1u << 3)
#define  AP_AUTO_RESTART (1u << 7)
#define PARSER_UDP_PORT  0x10           // XCSI_UDP_PARSER_CTRL_ADDR_UDP_PORT_DATA
#define S2MM_MEM_LO      0x10           // XS2MM_CONTROL_ADDR_MEM_DATA (64-bit)
#define S2MM_MEM_HI      0x14
#define S2MM_SIZE        0x1c           // XS2MM_CONTROL_ADDR_SIZE_DATA

// --- axi_ethernet (xaxiethernet_hw.h) ---------------------------------------
#define XAE_RAF          0x0000
#define XAE_IS           0x000C
#define XAE_RCW0         0x0400
#define XAE_RCW1         0x0404
#define  RCW1_RST        0x80000000u
#define  RCW1_RX         0x10000000u
#define XAE_TC           0x0408
#define  TC_RST          0x80000000u
#define  TC_TX           0x10000000u
#define XAE_EMMC         0x0410
#define  EMMC_LINKSPEED_MASK 0xC0000000u
#define  EMMC_LINKSPD_1000   0x80000000u
#define XAE_MDIO_MC      0x0500
#define  MDIO_MC_MDIOEN  0x00000040u
#define XAE_MDIO_MCR     0x0504
#define  MCR_PHYAD_SHIFT 24
#define  MCR_REGAD_SHIFT 16
#define  MCR_OP_READ     0x00008000u
#define  MCR_OP_WRITE    0x00004000u
#define  MCR_INITIATE    0x00000800u
#define  MCR_READY       0x00000080u
#define XAE_MDIO_MWD     0x0508
#define XAE_MDIO_MRD     0x050C
#define XAE_FMI          0x0708
#define  FMI_PM          0x80000000u
// statistics counters (64-bit, LSW/MSW pairs)
#define XAE_RXBL         0x0200
#define XAE_RX64BL       0x0220
#define XAE_RXUNDRL      0x0210
#define XAE_RXOVRL       0x0250

// PCS/PMA is internal to the MAC in 1000BASE-X and answers on MDIO at PHYADDR,
// which the BD sets to 2 (CONFIG.PHYADDR).
#define PCS_PHYADDR      2
#define MII_BMCR         0x00
#define  BMCR_RESET      0x8000
#define  BMCR_LOOPBACK   0x4000
#define  BMCR_ANENABLE   0x1000
#define  BMCR_ANRESTART  0x0200
#define MII_BMSR         0x01
#define  BMSR_LSTATUS    0x0004
#define  BMSR_ANEGDONE   0x0020

// The default metadata landing zone. This MUST be memory Linux does not own -
// carve it out with a reserved-memory node in the device tree (or a mem= limit)
// before trusting it, otherwise s2mm_meta will scribble on the kernel.
#define DEFAULT_META_PA  0x70000000UL
#define META_WORDS       2               // one packed csi_meta_t = 64 bits

// Rest of the 1 MB carve-out. live/inline_reader.py uses RESULTS_PA too, so
// keep these in step with work/petalinux/inline_extras.dtsi.
#define RESULTS_PA       0x70010000UL    // AIE feature results
#define TXD_PA           0x70020000UL    // synthetic frame for the loopback test
#define TXC_PA           0x70030000UL    // the MAC's 5-word TX control packet
#define TXC_WORDS        5               // APP0..APP4, XAXIDMA_LAST_APPWORD = 4
#define RESULT_PA        0x70040000UL    // self-test verdict, readable over JTAG
#define RESULT_MAGIC     0xC5170001u

// The self-test frame. Mirrors the synthetic frame in
// work/udp_parser/csi_udp_parser_tb.cpp, which is what the parser's C/RTL
// co-simulation was validated against, so a mismatch here points at the
// hardware rather than at a new, untested stimulus.
#define TEST_N_SUB       64
// One page, which is what cmd_txtest maps for the frame. 60 + 4*TEST_N_SUB must
// fit; the build asserts it below so a bigger TEST_N_SUB cannot silently
// overrun either the staging buffer or the mapping.
#define TXD_MAX_BYTES    4096
_Static_assert(60 + 4 * TEST_N_SUB <= TXD_MAX_BYTES, "TEST_N_SUB too large for one page");
#define TEST_SEQ         0x1234
#define TEST_RSSI        (-64)           // 0xC0
#define TEST_CHANSPEC    0xE02A
#define TEST_CORE_SP     0x01

static volatile uint8_t *pl;             // mapped PL AXI-Lite window
static int devmem_fd = -1;

static uint32_t rd(unsigned long off)              { return *(volatile uint32_t *)(pl + off); }
static void     wr(unsigned long off, uint32_t v)  { *(volatile uint32_t *)(pl + off) = v; }

static uint64_t stat64(unsigned long lsw) {
    // LSW must be read first; the MSW latches on the LSW read.
    uint32_t lo = rd(OFF_ETH + lsw);
    uint32_t hi = rd(OFF_ETH + lsw + 4);
    return ((uint64_t)hi << 32) | lo;
}

// --- MDIO to the internal PCS/PMA -------------------------------------------
static int mdio_wait(void) {
    for (int i = 0; i < 100000; i++)
        if (rd(OFF_ETH + XAE_MDIO_MCR) & MCR_READY) return 0;
    fprintf(stderr, "csi_ctl: MDIO timeout (is MDIO enabled / s_axi_lite_clk running?)\n");
    return -1;
}

static int mdio_read(int phy, int reg, uint16_t *out) {
    if (mdio_wait()) return -1;
    wr(OFF_ETH + XAE_MDIO_MCR,
       ((uint32_t)phy << MCR_PHYAD_SHIFT) | ((uint32_t)reg << MCR_REGAD_SHIFT) |
       MCR_OP_READ | MCR_INITIATE);
    if (mdio_wait()) return -1;
    *out = (uint16_t)rd(OFF_ETH + XAE_MDIO_MRD);
    return 0;
}

static int mdio_write(int phy, int reg, uint16_t val) {
    if (mdio_wait()) return -1;
    wr(OFF_ETH + XAE_MDIO_MWD, val);
    wr(OFF_ETH + XAE_MDIO_MCR,
       ((uint32_t)phy << MCR_PHYAD_SHIFT) | ((uint32_t)reg << MCR_REGAD_SHIFT) |
       MCR_OP_WRITE | MCR_INITIATE);
    return mdio_wait();
}

// --- commands ----------------------------------------------------------------
static const char *hls_state(uint32_t c) {
    static char b[64];
    snprintf(b, sizeof b, "0x%02x%s%s%s%s", c,
             (c & AP_START) ? " start" : "", (c & AP_DONE) ? " done" : "",
             (c & AP_IDLE) ? " idle" : "", (c & AP_AUTO_RESTART) ? " auto" : "");
    return b;
}

static int cmd_status(void) {
    printf("MAC   @0x%08lx\n", PL_BASE + OFF_ETH);
    uint32_t rcw1 = rd(OFF_ETH + XAE_RCW1), tc = rd(OFF_ETH + XAE_TC);
    uint32_t emmc = rd(OFF_ETH + XAE_EMMC), fmi = rd(OFF_ETH + XAE_FMI);
    printf("  RCW1 0x%08x  rx=%s\n", rcw1, (rcw1 & RCW1_RX) ? "ENABLED" : "disabled");
    printf("  TC   0x%08x  tx=%s\n", tc,   (tc & TC_TX) ? "enabled" : "disabled");
    const char *spd = "?";
    switch (emmc & EMMC_LINKSPEED_MASK) {
        case 0x00000000u: spd = "10M";   break;
        case 0x40000000u: spd = "100M";  break;
        case 0x80000000u: spd = "1G";    break;
    }
    printf("  EMMC 0x%08x  speed=%s\n", emmc, spd);
    printf("  FMI  0x%08x  promiscuous=%s\n", fmi, (fmi & FMI_PM) ? "yes" : "no");
    printf("  IS   0x%08x\n", rd(OFF_ETH + XAE_IS));

    uint16_t bmcr = 0, bmsr = 0;
    if (mdio_read(PCS_PHYADDR, MII_BMCR, &bmcr) == 0 &&
        mdio_read(PCS_PHYADDR, MII_BMSR, &bmsr) == 0 &&
        mdio_read(PCS_PHYADDR, MII_BMSR, &bmsr) == 0) {   // BMSR link bit is latch-low
        printf("PCS   phy=%d BMCR 0x%04x BMSR 0x%04x  link=%s autoneg=%s\n",
               PCS_PHYADDR, bmcr, bmsr,
               (bmsr & BMSR_LSTATUS) ? "UP" : "down",
               (bmsr & BMSR_ANEGDONE) ? "done" : "not done");
    } else {
        printf("PCS   MDIO not responding (run `csi_ctl mac-init` first)\n");
    }

    printf("RX    bytes=%llu frames64=%llu undersize=%llu oversize=%llu\n",
           (unsigned long long)stat64(XAE_RXBL), (unsigned long long)stat64(XAE_RX64BL),
           (unsigned long long)stat64(XAE_RXUNDRL), (unsigned long long)stat64(XAE_RXOVRL));

    printf("parser   ap_ctrl %s  udp_port=%u\n",
           hls_state(rd(OFF_PARSER + HLS_AP_CTRL)), rd(OFF_PARSER + PARSER_UDP_PORT) & 0xffff);
    printf("s2mm_meta ap_ctrl %s  size=%u\n",
           hls_state(rd(OFF_S2MM_META + HLS_AP_CTRL)), rd(OFF_S2MM_META + S2MM_SIZE));
    printf("s2mm      ap_ctrl %s  size=%u\n",
           hls_state(rd(OFF_S2MM + HLS_AP_CTRL)), rd(OFF_S2MM + S2MM_SIZE));
    printf("csi_mux   MI0 select = %u (0=parser/live, 1=mm2s/DDR replay)\n",
           rd(OFF_CSI_MUX + 0x40) & 0x7);
    return 0;
}

static int cmd_mac_init(int autoneg) {
    // 1) hold the receiver and transmitter in reset while we configure
    wr(OFF_ETH + XAE_RCW1, RCW1_RST);
    wr(OFF_ETH + XAE_TC,   TC_RST);
    usleep(1000);
    wr(OFF_ETH + XAE_RCW1, 0);
    wr(OFF_ETH + XAE_TC,   0);

    // 2) 1000BASE-X is fixed 1G
    uint32_t emmc = rd(OFF_ETH + XAE_EMMC);
    wr(OFF_ETH + XAE_EMMC, (emmc & ~EMMC_LINKSPEED_MASK) | EMMC_LINKSPD_1000);

    // 3) MDIO clock: s_axi_lite_clk is 100 MHz and MDC must stay <= 2.5 MHz.
    //    f_MDC = f_AXI / (2 * (divisor + 1)) -> divisor 24 gives 2.0 MHz.
    wr(OFF_ETH + XAE_MDIO_MC, MDIO_MC_MDIOEN | 24);
    usleep(1000);

    // 4) the Pi sends to whatever MAC/broadcast, and this is a capture-only
    //    node, so take everything
    wr(OFF_ETH + XAE_FMI, rd(OFF_ETH + XAE_FMI) | FMI_PM);

    // 5) bring the internal PCS/PMA up
    uint16_t bmcr = autoneg ? (BMCR_ANENABLE | BMCR_ANRESTART) : 0;
    if (mdio_write(PCS_PHYADDR, MII_BMCR, bmcr)) {
        fprintf(stderr, "csi_ctl: PCS MDIO write failed\n");
        return 1;
    }

    // 6) enable receiver and transmitter. TX is needed for the loopback
    //    self-test; in normal capture it simply never sends anything.
    //    Leaving the FCS bits clear means the MAC inserts FCS on TX and strips
    //    it on RX, which is what csi_udp_parser assumes.
    wr(OFF_ETH + XAE_RCW1, (rd(OFF_ETH + XAE_RCW1) & 0x0000ffffu) | RCW1_RX);
    wr(OFF_ETH + XAE_TC,   TC_TX);

    printf("mac-init: 1G, promiscuous, RX+TX enabled, PCS autoneg=%s\n",
           autoneg ? "on" : "off");
    printf("  give the link a second, then `csi_ctl status` and look for link=UP\n");
    return 0;
}

static int cmd_start(unsigned long meta_pa, unsigned udp_port) {
    // s2mm_meta writes META_WORDS words from the buffer base on every restart,
    // so DDR always holds the most recent record.
    wr(OFF_S2MM_META + S2MM_MEM_LO, (uint32_t)(meta_pa & 0xffffffffu));
    wr(OFF_S2MM_META + S2MM_MEM_HI, (uint32_t)(meta_pa >> 32));
    wr(OFF_S2MM_META + S2MM_SIZE,   META_WORDS);
    wr(OFF_S2MM_META + HLS_AP_CTRL, AP_START | AP_AUTO_RESTART);

    wr(OFF_PARSER + PARSER_UDP_PORT, udp_port);
    wr(OFF_PARSER + HLS_AP_CTRL,     AP_START | AP_AUTO_RESTART);

    printf("start: parser on UDP port %u, metadata -> 0x%lx (%d words), free-running\n",
           udp_port, meta_pa, META_WORDS);
    return 0;
}

static int cmd_stop(void) {
    wr(OFF_PARSER + HLS_AP_CTRL, 0);        // clear auto-restart; finishes the frame
    wr(OFF_S2MM_META + HLS_AP_CTRL, 0);
    printf("stop: auto-restart cleared on parser and s2mm_meta\n");
    return 0;
}

static int cmd_mux(unsigned sel) {
    // axis_switch in control-register routing mode: MI0 mux register at 0x40,
    // bit 31 = disable. Commit needs a write to the control register (0x00).
    wr(OFF_CSI_MUX + 0x40, sel & 0x7);
    wr(OFF_CSI_MUX + 0x00, 0x2);            // reg update
    printf("mux: AIE input = %s\n", sel ? "mm2s (DDR replay)" : "csi_udp_parser (live)");
    return 0;
}

static int cmd_meta(unsigned long meta_pa) {
    off_t page = meta_pa & ~(off_t)(sysconf(_SC_PAGESIZE) - 1);
    off_t skew = meta_pa - page;
    void *m = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ, MAP_SHARED, devmem_fd, page);
    if (m == MAP_FAILED) { perror("mmap meta"); return 1; }
    volatile uint32_t *w = (volatile uint32_t *)((uint8_t *)m + skew);
    uint64_t v = ((uint64_t)w[1] << 32) | w[0];
    munmap(m, sysconf(_SC_PAGESIZE));

    // layout from work/udp_parser/csi_udp_parser.hpp (csi_meta_pack)
    unsigned seq      =  v        & 0xffff;
    int      rssi     = (int8_t)((v >> 16) & 0xff);
    unsigned n_sub    = (v >> 24) & 0xffff;
    unsigned chanspec = (v >> 40) & 0xffff;
    unsigned core_sp  = (v >> 56) & 0xff;
    printf("meta @0x%lx raw=0x%016llx\n", meta_pa, (unsigned long long)v);
    printf("  seq=%u rssi=%d dBm n_sub=%u chanspec=0x%04x core/spatial=0x%02x\n",
           seq, rssi, n_sub, chanspec, core_sp);
    printf("  feature[7] (rssi+100)/100 = %.4f\n", (rssi + 100) / 100.0);
    return 0;
}

// --- loopback self-test ------------------------------------------------------
// Map a physical DDR region for read/write. Returns the base of the page-aligned
// mapping and the offset of the requested address within it.
static void *map_pa(unsigned long pa, size_t len, size_t *skew) {
    long ps = sysconf(_SC_PAGESIZE);
    off_t page = pa & ~(off_t)(ps - 1);
    *skew = pa - page;
    void *m = mmap(NULL, len + *skew, PROT_READ | PROT_WRITE, MAP_SHARED, devmem_fd, page);
    return (m == MAP_FAILED) ? NULL : m;
}

// --- writing the DDR carve-out ----------------------------------------------
// The carve-out is `no-map` reserved memory, so the kernel keeps it out of the
// linear map and /dev/mem hands it back with Device-nGnRE attributes. On arm64
// Device memory forbids unaligned multi-byte stores and DC ZVA - exactly what
// memset()/memcpy() emit - and doing so raises an alignment fault that reaches
// userspace as SIGBUS. It dies on the very first write, before any printf has
// flushed, so it presents as a silent "Bus error (core dumped)" with no clue
// attached.
//
// That is why `csi_ctl status` always worked (aligned 32-bit register reads)
// while `txtest` died instantly: its first act is to lay down a frame in DDR.
//
// So: never memset/memcpy a mapped region. Build in ordinary memory and move it
// across in aligned 32-bit words.
static void ddr_zero(volatile void *dst, size_t bytes) {
    volatile uint32_t *d = (volatile uint32_t *)dst;
    for (size_t i = 0; i < (bytes + 3) / 4; i++) d[i] = 0;
}

static void ddr_copy(volatile void *dst, const void *src, size_t bytes) {
    volatile uint32_t *d = (volatile uint32_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    for (size_t i = 0; i < (bytes + 3) / 4; i++) {
        uint32_t w;
        memcpy(&w, s + 4 * i, 4);        // src is ordinary memory - safe here
        d[i] = w;
    }
}

static void put_be16(uint8_t *p, uint16_t v) { p[0] = v >> 8;   p[1] = v & 0xff; }
static void put_le16(uint8_t *p, uint16_t v) { p[0] = v & 0xff; p[1] = v >> 8; }

// Build the synthetic nexmon_csi frame. Layout and offsets come from
// work/udp_parser/csi_udp_parser.hpp: 14 eth + 20 IPv4 + 8 UDP + 18 nexmon = 60,
// then int16-LE I/Q per subcarrier. CSI payload is real=i, imag=-i, matching the
// parser testbench. Returns the frame length, always a multiple of 4.
static size_t build_nexmon_frame(uint8_t *f, unsigned udp_port, unsigned n_sub) {
    size_t o = 0;
    memset(f, 0, 60 + 4 * n_sub);
    for (int i = 0; i < 6; i++) f[o++] = 0xff;          // dst MAC: broadcast
    for (int i = 0; i < 6; i++) f[o++] = 0x02;          // src MAC
    put_be16(f + o, 0x0800); o += 2;                    // ethertype IPv4
    f[o++] = 0x45; f[o++] = 0x00;                       // IPv4, IHL=5
    put_be16(f + o, (uint16_t)(20 + 8 + 18 + 4 * n_sub)); o += 2;  // total length
    o += 4;                                             // id, flags/frag
    f[o++] = 0x40; f[o++] = 17;                         // ttl, proto = UDP
    o += 2;                                             // header checksum (unchecked)
    for (int i = 0; i < 4; i++) f[o++] = 10;            // src IP
    for (int i = 0; i < 4; i++) f[o++] = 20;            // dst IP
    put_be16(f + o, 12345); o += 2;                     // src port
    put_be16(f + o, (uint16_t)udp_port); o += 2;        // dst port
    put_be16(f + o, (uint16_t)(8 + 18 + 4 * n_sub)); o += 2;  // UDP length
    o += 2;                                             // UDP checksum (unused)
    // nexmon header, 18 bytes, little-endian
    put_le16(f + o, 0x1111); o += 2;                    // magic
    f[o++] = (uint8_t)(int8_t)TEST_RSSI;                // byte 44: rssi
    f[o++] = 0x08;                                      // frame control
    for (int i = 0; i < 6; i++) f[o++] = 0xAA;          // src MAC
    put_le16(f + o, TEST_SEQ); o += 2;                  // bytes 52-53: sequence
    put_le16(f + o, TEST_CORE_SP); o += 2;              // byte 54: core/spatial
    put_le16(f + o, TEST_CHANSPEC); o += 2;             // bytes 56-57: chanspec
    put_le16(f + o, 0x02D2); o += 2;                    // chip version
    for (unsigned i = 0; i < n_sub; i++) {              // CSI from byte 60
        put_le16(f + o, (uint16_t)(int16_t)i);        o += 2;
        put_le16(f + o, (uint16_t)(int16_t)(-(int)i)); o += 2;
    }
    return o;
}

static int cmd_loopback(unsigned mode) {
    wr(OFF_LOOPBACK + GPIO_DATA, mode & 0x7);
    const char *n = "?";
    switch (mode) {
        case LB_NORMAL:   n = "normal (optics)";  break;
        case LB_NEAR_PCS: n = "near-end PCS";     break;
        case LB_NEAR_PMA: n = "near-end PMA";     break;
        case LB_FAR_PMA:  n = "far-end PMA";      break;
        case LB_FAR_PCS:  n = "far-end PCS";      break;
    }
    printf("loopback: GT mode %u = %s (readback 0x%x)\n",
           mode, n, rd(OFF_LOOPBACK + GPIO_DATA));
    return 0;
}

// Push one synthetic nexmon frame out of the MAC and check it comes back all
// the way through MAC RX -> parser -> metadata writer -> DDR. With the GT in
// near-end PMA loopback this needs no Pi, no SFP and no cable, and it exercises
// every block in the real chain rather than a simulation of it.
static int cmd_txtest(unsigned long meta_pa, unsigned udp_port, unsigned mode, int quiet) {
    size_t skew_f, skew_c, skew_m;
    uint8_t *frame = map_pa(TXD_PA, 4096, &skew_f);
    uint8_t *ctrl  = map_pa(TXC_PA, 4096, &skew_c);
    uint8_t *meta  = map_pa(meta_pa, 4096, &skew_m);
    if (!frame || !ctrl || !meta) { perror("mmap DDR"); return 1; }
    frame += skew_f; ctrl += skew_c; meta += skew_m;

    // Build in ordinary memory, then move it across in aligned words - see the
    // ddr_copy/ddr_zero comment: memset/memcpy straight into the mapping is a
    // SIGBUS on arm64.
    static uint8_t stage[TXD_MAX_BYTES];
    size_t len = build_nexmon_frame(stage, udp_port, TEST_N_SUB);
    ddr_copy(frame, stage, len);
    ddr_zero(ctrl, TXC_WORDS * 4);               // no checksum offload -> zeros
    __sync_synchronize();

    // clear the metadata slot so we can tell a fresh record from a stale one
    volatile uint32_t *mw = (volatile uint32_t *)meta;
    mw[0] = 0; mw[1] = 0;
    __sync_synchronize();

    if (!quiet)
        printf("txtest: frame %zu bytes (%u subcarriers) at 0x%lx, loopback mode %u\n",
               len, TEST_N_SUB, TXD_PA, mode);

    cmd_loopback(mode);
    usleep(200000);                              // let the PCS re-sync in loopback

    // receiver side first, so nothing is missed
    wr(OFF_S2MM_META + S2MM_MEM_LO, (uint32_t)meta_pa);
    wr(OFF_S2MM_META + S2MM_MEM_HI, (uint32_t)(meta_pa >> 32));
    wr(OFF_S2MM_META + S2MM_SIZE,   META_WORDS);
    wr(OFF_S2MM_META + HLS_AP_CTRL, AP_START | AP_AUTO_RESTART);
    wr(OFF_PARSER + PARSER_UDP_PORT, udp_port);
    wr(OFF_PARSER + HLS_AP_CTRL,     AP_START | AP_AUTO_RESTART);

    // control packet must be queued before the frame it describes
    wr(OFF_MM2S_TXC + S2MM_MEM_LO, (uint32_t)TXC_PA);
    wr(OFF_MM2S_TXC + S2MM_MEM_HI, (uint32_t)(TXC_PA >> 32));
    wr(OFF_MM2S_TXC + S2MM_SIZE,   TXC_WORDS);
    wr(OFF_MM2S_TXC + HLS_AP_CTRL, AP_START);

    wr(OFF_MM2S_TXD + S2MM_MEM_LO, (uint32_t)TXD_PA);
    wr(OFF_MM2S_TXD + S2MM_MEM_HI, (uint32_t)(TXD_PA >> 32));
    wr(OFF_MM2S_TXD + S2MM_SIZE,   (uint32_t)(len / 4));
    wr(OFF_MM2S_TXD + HLS_AP_CTRL, AP_START);

    // wait for a metadata record to land
    uint64_t v = 0;
    int got = 0;
    for (int i = 0; i < 500; i++) {              // up to ~5 s
        usleep(10000);
        __sync_synchronize();
        v = ((uint64_t)mw[1] << 32) | mw[0];
        if (v) { got = 1; break; }
    }

    unsigned rx_frames = (unsigned)stat64(XAE_RX64BL);
    if (!got) {
        printf("txtest: FAIL - no metadata record after 5 s\n");
        printf("  txd ap_ctrl %s   txc ap_ctrl %s\n",
               hls_state(rd(OFF_MM2S_TXD + HLS_AP_CTRL)),
               hls_state(rd(OFF_MM2S_TXC + HLS_AP_CTRL)));
        printf("  parser ap_ctrl %s\n", hls_state(rd(OFF_PARSER + HLS_AP_CTRL)));
        printf("  MAC rx bytes=%llu  rx undersize=%llu  oversize=%llu\n",
               (unsigned long long)stat64(XAE_RXBL),
               (unsigned long long)stat64(XAE_RXUNDRL),
               (unsigned long long)stat64(XAE_RXOVRL));
        printf("  -> if txd/txc never leave 'done', the MAC is not draining TX\n");
        printf("  -> if rx bytes stayed 0, the loopback is not closing\n");
        return 1;
    }

    unsigned seq      =  v        & 0xffff;
    int      rssi     = (int8_t)((v >> 16) & 0xff);
    unsigned n_sub    = (v >> 24) & 0xffff;
    unsigned chanspec = (v >> 40) & 0xffff;
    unsigned core_sp  = (v >> 56) & 0xff;

    struct { const char *name; unsigned got, want; } chk[] = {
        {"seq",          seq,      TEST_SEQ},
        {"rssi",         (unsigned)(rssi & 0xff), (unsigned)(TEST_RSSI & 0xff)},
        {"n_sub",        n_sub,    TEST_N_SUB},
        {"chanspec",     chanspec, TEST_CHANSPEC},
        {"core_spatial", core_sp,  TEST_CORE_SP},
    };
    int bad = 0;
    printf("txtest: metadata raw=0x%016llx  (MAC rx frames=%u)\n",
           (unsigned long long)v, rx_frames);
    for (unsigned i = 0; i < sizeof chk / sizeof chk[0]; i++) {
        int ok = chk[i].got == chk[i].want;
        if (!ok) bad++;
        printf("  %-13s got 0x%04x  want 0x%04x  %s\n",
               chk[i].name, chk[i].got, chk[i].want, ok ? "ok" : "MISMATCH");
    }
    printf("txtest: %s\n", bad ? "FAIL" : "PASS - MAC TX -> loopback -> MAC RX -> "
                                          "parser -> DDR is bit-correct");
    return bad ? 1 : 0;
}

// Unattended self-test. Runs mac-init -> loopback -> txtest and leaves a result
// block in DDR at RESULT_PA.
//
// This exists because the board console (com0) is read-only to automation - see
// PROJECT_STATE.md section 10 - so an autorun service runs this at boot and the
// verdict is collected over JTAG with `xsdb ... mrd 0x70040000 12`, needing no
// login, no console input and no working Ethernet to the host.
static int cmd_selftest(unsigned long meta_pa, unsigned udp_port, unsigned mode) {
    size_t skew;
    volatile uint32_t *res = NULL;
    uint8_t *m = map_pa(RESULT_PA, 4096, &skew);
    if (m) res = (volatile uint32_t *)(m + skew);
    if (res) { for (int i = 0; i < 16; i++) res[i] = 0; res[0] = RESULT_MAGIC; res[1] = 0xffffffffu; }

    printf("=== csi_ctl selftest ===\n");
    unsigned stage = 1;

    // 1) MAC + PCS. In loopback the PCS negotiates with itself, which normally
    //    completes; if it has not after ~2 s, fall back to forcing the link.
    cmd_mac_init(1);
    usleep(2000000);
    uint16_t bmsr = 0;
    mdio_read(PCS_PHYADDR, MII_BMSR, &bmsr);
    mdio_read(PCS_PHYADDR, MII_BMSR, &bmsr);
    if (!(bmsr & BMSR_LSTATUS)) {
        printf("selftest: no link with autoneg (BMSR 0x%04x), retrying forced\n", bmsr);
        cmd_mac_init(0);
        usleep(1500000);
        mdio_read(PCS_PHYADDR, MII_BMSR, &bmsr);
        mdio_read(PCS_PHYADDR, MII_BMSR, &bmsr);
    }
    printf("selftest: PCS BMSR 0x%04x link=%s\n", bmsr,
           (bmsr & BMSR_LSTATUS) ? "UP" : "down");
    stage = 2;

    // 2) the actual loopback frame test
    int rc = cmd_txtest(meta_pa, udp_port, mode, 0);
    stage = 3;

    cmd_status();

    if (res) {
        size_t sk2;
        uint8_t *mm = map_pa(meta_pa, 4096, &sk2);
        uint32_t m0 = 0, m1 = 0;
        if (mm) { volatile uint32_t *w = (volatile uint32_t *)(mm + sk2); m0 = w[0]; m1 = w[1]; }
        res[2]  = stage;
        res[3]  = m0;
        res[4]  = m1;
        res[5]  = rd(OFF_ETH + XAE_RCW1);
        res[6]  = bmsr;
        res[7]  = (uint32_t)stat64(XAE_RX64BL);
        res[8]  = rd(OFF_PARSER + HLS_AP_CTRL);
        res[9]  = rd(OFF_MM2S_TXD + HLS_AP_CTRL);
        res[10] = rd(OFF_MM2S_TXC + HLS_AP_CTRL);
        res[11] = (uint32_t)stat64(XAE_RXBL);
        __sync_synchronize();
        res[1]  = rc ? 1u : 0u;              // written last: [1] valid => done
        __sync_synchronize();
    }
    printf("SELFTEST %s (result block at 0x%lx)\n", rc ? "FAIL" : "PASS", RESULT_PA);
    return rc;
}

static void usage(void) {
    fprintf(stderr,
        "csi_ctl - inline Arch-B bring-up (VCK190 WiFi-CSI)\n\n"
        "  csi_ctl status                     read-only dump: MAC, PCS link, RX counters, kernels\n"
        "  csi_ctl mac-init [--no-autoneg]    configure the MAC + internal PCS and enable RX\n"
        "  csi_ctl start [--port N] [--buf A] free-run the parser and the metadata writer\n"
        "  csi_ctl stop                       clear auto-restart\n"
        "  csi_ctl mux <0|1>                  AIE source: 0 = live parser, 1 = mm2s DDR replay\n"
        "  csi_ctl meta [--buf A]             decode the latest metadata record from DDR\n"
        "  csi_ctl loopback <mode>            GT loopback: 0 normal, 1 near-PCS, 2 near-PMA,\n"
        "                                     4 far-PMA, 6 far-PCS\n"
        "  csi_ctl txtest [--mode M]          SELF-TEST: push a synthetic nexmon frame out of\n"
        "                                     the MAC in loopback and verify it returns through\n"
        "                                     parser -> DDR (default mode 2, near-end PMA)\n"
        "  csi_ctl selftest                   unattended: mac-init + txtest, verdict written to\n"
        "                                     DDR 0x70040000 so it can be read back over JTAG\n\n"
        "  --port N  UDP port to capture (default 5500, the nexmon_csi port)\n"
        "  --buf  A  metadata physical address (default 0x%lx; must be reserved from Linux)\n",
        DEFAULT_META_PA);
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }

    unsigned long meta_pa = DEFAULT_META_PA;
    unsigned udp_port = 5500;
    int autoneg = 1;
    unsigned lb_mode = LB_NEAR_PMA;
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--buf")  && i + 1 < argc) meta_pa  = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--port") && i + 1 < argc) udp_port = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--mode") && i + 1 < argc) lb_mode = strtoul(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--no-autoneg")) autoneg = 0;
    }

    devmem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (devmem_fd < 0) { perror("open /dev/mem"); return 1; }
    pl = mmap(NULL, PL_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, devmem_fd, PL_BASE);
    if (pl == MAP_FAILED) { perror("mmap PL"); return 1; }

    int rc;
    if      (!strcmp(argv[1], "status"))   rc = cmd_status();
    else if (!strcmp(argv[1], "mac-init")) rc = cmd_mac_init(autoneg);
    else if (!strcmp(argv[1], "start"))    rc = cmd_start(meta_pa, udp_port);
    else if (!strcmp(argv[1], "stop"))     rc = cmd_stop();
    else if (!strcmp(argv[1], "meta"))     rc = cmd_meta(meta_pa);
    else if (!strcmp(argv[1], "mux") && argc > 2) rc = cmd_mux(strtoul(argv[2], NULL, 0));
    else if (!strcmp(argv[1], "loopback") && argc > 2) rc = cmd_loopback(strtoul(argv[2], NULL, 0));
    else if (!strcmp(argv[1], "txtest")) rc = cmd_txtest(meta_pa, udp_port, lb_mode, 0);
    else if (!strcmp(argv[1], "selftest")) rc = cmd_selftest(meta_pa, udp_port, lb_mode);
    else { usage(); rc = 1; }

    munmap((void *)pl, PL_SPAN);
    close(devmem_fd);
    return rc;
}
