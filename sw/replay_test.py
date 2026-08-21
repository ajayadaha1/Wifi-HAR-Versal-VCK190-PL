#!/usr/bin/env python3
"""replay_test.py - drive the CSI datapath from DDR, with no Ethernet involved.

The inline design has a replay injector precisely so the datapath can be tested
without a working link:

    mm2s_rx (0xA407_0000) -> rx_inj_dwidth 32->8 -> rx_mux S01 -> csi_udp_parser
                                                                       |
                                                          s2mm_meta -> DDR

rx_mux S00 is the live Ethernet RX path; S01 is this injector. Selecting S01
takes the MAC, the PCS and the GT out of the picture entirely, so a pass here
proves parser -> metadata -> DDR on silicon even while the PCS link is down.

Two things this deliberately does NOT use:
  - any BULK move to or from the mapping. The carve-out is `no-map` reserved
    memory, so /dev/mem returns it as Device-nGnRE, where arm64 forbids the
    unaligned/SIMD accesses that memcpy and memset emit. The fault surfaces as
    a bare SIGBUS with no message, and it is easy to misread: single 32-bit
    accesses succeed, so `csi_ctl status` and every register probe work fine
    while anything that lays down or slurps back a buffer dies instantly.
    Both directions matter - `bytes(dd[o:o+316])` is as fatal as memset.
    Everything here therefore moves 4 aligned bytes at a time.
  - csi_ctl. It predates the injector and has no register map for it.

Usage:  python3 replay_test.py [n_sub]
"""
import mmap
import os
import struct
import sys
import time

PL_BASE   = 0xA4000000
OFF_PARSER    = 0x00020000
OFF_S2MM_META = 0x00030000
OFF_MM2S_RX   = 0x00070000
OFF_RX_MUX    = 0x000F0000

HLS_AP_CTRL   = 0x00
PARSER_PORT   = 0x10
MEM_LO, MEM_HI, SIZE = 0x10, 0x14, 0x1C
AP_START, AP_DONE, AP_IDLE, AP_READY = 1, 2, 4, 8
AP_AUTO_RESTART = 0x80

SW_CTRL, SW_MI0 = 0x00, 0x40      # axi4stream_switch: commit reg, MI0 mux
SW_COMMIT       = 0x02            # CTRL bit1 = "Registers Update"
SW_DISABLE      = 0x80000000

META_PA, FRAME_PA = 0x70000000, 0x70020000
UDP_PORT, N_SUB = 5500, int(sys.argv[1]) if len(sys.argv) > 1 else 64

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
pl = mmap.mmap(fd, 0x100000, offset=PL_BASE)
dd = mmap.mmap(fd, 0x100000, offset=META_PA)          # whole 1 MB carve-out


def rd(off):
    return struct.unpack("<I", pl[off:off + 4])[0]


def wr(off, val):
    pl[off:off + 4] = struct.pack("<I", val & 0xFFFFFFFF)


def ddr_wr(pa, data):
    """Aligned 32-bit writes only - see the module docstring."""
    o = pa - META_PA
    pad = (-len(data)) % 4
    data = data + b"\x00" * pad
    for i in range(0, len(data), 4):
        dd[o + i:o + i + 4] = data[i:i + 4]


def ddr_rd(pa, n):
    """Word-at-a-time for the same reason as ddr_wr. A bulk `bytes(dd[o:o+n])`
    is one big memcpy and faults exactly like memset does - that is what made
    this script SIGBUS on its first run while every 4-byte probe passed."""
    o = pa - META_PA
    out = bytearray()
    for i in range(0, (n + 3) // 4 * 4, 4):
        out += dd[o + i:o + i + 4]
    return bytes(out[:n])


def build_frame(udp_port, n_sub):
    """Byte-for-byte the frame csi_udp_parser_tb.cpp builds (which passes csim
    and C/RTL co-sim), so a parse failure here is a hardware result, not a
    disagreement about the wire format."""
    f = bytearray()
    f += b"\xff" * 6 + b"\x02" * 6 + struct.pack(">H", 0x0800)   # eth, 14
    f += b"\x45\x00" + struct.pack(">H", 20 + 8 + 18 + 4 * n_sub)
    f += b"\x00" * 4 + b"\x40" + bytes([17]) + b"\x00" * 2
    f += bytes([10]) * 4 + bytes([20]) * 4                       # ipv4, 20
    f += struct.pack(">HHHH", 12345, udp_port, 8 + 18 + 4 * n_sub, 0)  # udp, 8
    f += struct.pack("<H", 0x1111) + bytes([0xC0, 0x08]) + b"\xAA" * 6
    f += struct.pack("<HHHH", 0x1234, 0x0001, 0xE02A, 0x02D2)    # nexmon, 18
    for i in range(n_sub):                                       # int16 LE I/Q
        f += struct.pack("<hh", i, -i)
    return bytes(f)


def unpack_meta(w):
    return dict(seq=w & 0xFFFF,
                rssi=struct.unpack("b", bytes([(w >> 16) & 0xFF]))[0],
                n_sub=(w >> 24) & 0xFFFF,
                chanspec=(w >> 40) & 0xFFFF,
                core_spatial=(w >> 56) & 0xFF)


def ap(name, off):
    v = rd(off + HLS_AP_CTRL)
    flags = [n for b, n in ((AP_START, "start"), (AP_DONE, "done"),
                            (AP_IDLE, "idle"), (AP_READY, "ready")) if v & b]
    return f"{name}=0x{v:02x}[{','.join(flags) or '-'}]"


frame = build_frame(UDP_PORT, N_SUB)
words = len(frame) // 4
print(f"frame {len(frame)} bytes = {words} words, {N_SUB} subcarriers, udp {UDP_PORT}")

ddr_wr(FRAME_PA, frame)
back = ddr_rd(FRAME_PA, len(frame))
print("DDR write/readback:", "OK" if back == frame else "MISMATCH")
if back != frame:
    sys.exit(1)

ddr_wr(META_PA, b"\x00" * 16)                       # clear the metadata slot

print("rx_mux MI0 before:", hex(rd(OFF_RX_MUX + SW_MI0)))
wr(OFF_RX_MUX + SW_MI0, 1)                          # S01 = the DDR injector
wr(OFF_RX_MUX + SW_CTRL, SW_COMMIT)
time.sleep(0.05)
print("rx_mux MI0 after :", hex(rd(OFF_RX_MUX + SW_MI0)))

wr(OFF_S2MM_META + MEM_LO, META_PA & 0xFFFFFFFF)
wr(OFF_S2MM_META + MEM_HI, META_PA >> 32)
wr(OFF_S2MM_META + SIZE, 2)
wr(OFF_S2MM_META + HLS_AP_CTRL, AP_START | AP_AUTO_RESTART)

wr(OFF_PARSER + PARSER_PORT, UDP_PORT)
wr(OFF_PARSER + HLS_AP_CTRL, AP_START | AP_AUTO_RESTART)

print("armed:", ap("parser", OFF_PARSER), ap("s2mm_meta", OFF_S2MM_META))

wr(OFF_MM2S_RX + MEM_LO, FRAME_PA & 0xFFFFFFFF)
wr(OFF_MM2S_RX + MEM_HI, FRAME_PA >> 32)
wr(OFF_MM2S_RX + SIZE, words)
wr(OFF_MM2S_RX + HLS_AP_CTRL, AP_START)             # single shot

for i in range(20):
    time.sleep(0.1)
    w = struct.unpack("<Q", ddr_rd(META_PA, 8))[0]
    if w:
        m = unpack_meta(w)
        print(f"META 0x{w:016x} -> {m}")
        exp = dict(seq=0x1234, rssi=-64, n_sub=N_SUB,
                   chanspec=0xE02A, core_spatial=0x01)
        bad = {k: (m[k], v) for k, v in exp.items() if m[k] != v}
        print("REPLAY TEST PASS" if not bad else f"REPLAY TEST FAIL got/want {bad}")
        print("  ", ap("mm2s_rx", OFF_MM2S_RX), ap("parser", OFF_PARSER),
              ap("s2mm_meta", OFF_S2MM_META))
        sys.exit(0 if not bad else 1)

print("REPLAY TEST FAIL: no metadata after 2 s")
print("  ", ap("mm2s_rx", OFF_MM2S_RX), ap("parser", OFF_PARSER),
      ap("s2mm_meta", OFF_S2MM_META))
sys.exit(1)
