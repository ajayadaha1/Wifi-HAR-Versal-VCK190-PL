#!/usr/bin/env python3
"""mux_sweep.py - is the AIE shim taking its stream from the NoC instead of PL?

Where this comes from (PROJECT_STATE #17-#21). Everything else checks out:
  * PL datapath proven good (a non-matching UDP port lets the whole path finish)
  * graph loaded, core enabled and stalled at (24,1)
  * shim stream switch in column 24 configured: master 18 <- slave 3
  * BOTH AIE_PL channels placed at AIE_PL_X23Y0, i.e. AIE column 24
  * re-pointing master 18 at all 24 slave ports in turn changes NOTHING
That last result is the informative one: if rerouting inside the switch cannot
help, the data is not reaching the switch to begin with.

On Versal each shim stream can be sourced from the NoC *or* from the PL, chosen
by the shim mux/demux registers. The CDO sets these from the platform's PL
connections - metadata that was lost when the ai_engine IP was captured out of
the v++ flow. If the mux is still selecting NoC, the PL channel is simply not
connected, which matches every observation above.

Same stall trick as shim_sweep.py: a mover blocked on TREADY is blocked
mid-transfer, so correcting the mux while it is stalled lets that same transfer
complete. One boot tests every candidate; the originals are restored on a miss.

Usage:  python3 mux_sweep.py [col]        default 24
"""
import mmap
import os
import struct
import sys
import time

BASE = 0x20000000000
# Shim mux/demux live just above the stream-switch block. Dump a window rather
# than trusting one offset - the exact address differs between AIE generations.
MUX_WINDOW = (0x3FF00, 0x40)
PL_BASE = 0xA4000000
OFF_MM2S, OFF_CSI_MUX, OFF_S2MM = 0x00000, 0x60000, 0x10000
AP_CTRL, MEM_LO, MEM_HI, SIZE = 0x00, 0x10, 0x14, 0x1C
SW_CTRL, SW_MI0, SW_COMMIT = 0x00, 0x40, 0x02
FRAME_PA, RESULTS_PA = 0x70020000, 0x70010000

col = int(sys.argv[1]) if len(sys.argv) > 1 else 24
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
pl = mmap.mmap(fd, 0x100000, offset=PL_BASE)
dd = mmap.mmap(fd, 0x100000, offset=0x70000000)
tile = BASE + (col << 23)


def rd(o):
    return struct.unpack("<I", pl[o:o + 4])[0]


def wr(o, v):
    pl[o:o + 4] = struct.pack("<I", v & 0xFFFFFFFF)


def aie_rd(a):
    pg, off = a & ~0xFFF, a & 0xFFF
    m = mmap.mmap(fd, 4096, offset=pg)
    v = struct.unpack("<I", m[off:off + 4])[0]
    m.close()
    return v


def aie_wr(a, v):
    pg, off = a & ~0xFFF, a & 0xFFF
    m = mmap.mmap(fd, 4096, offset=pg)
    m[off:off + 4] = struct.pack("<I", v & 0xFFFFFFFF)
    m.close()


off0, size = MUX_WINDOW
print(f"=== shim mux window col {col} (0x{off0:05x}..0x{off0+size-1:05x}) ===")
orig = {}
for i in range(0, size, 4):
    v = aie_rd(tile + off0 + i)
    orig[off0 + i] = v
    if v:
        print(f"  +0x{off0+i:05x} = 0x{v:08x}")
if not any(orig.values()):
    print("  entire window reads 0 - nothing selecting PL")

# stimulus in DDR, aligned 32-bit writes only (Device-nGnRE mapping)
for i in range(0, 256, 4):
    dd[(FRAME_PA - 0x70000000) + i:(FRAME_PA - 0x70000000) + i + 4] = struct.pack("<I", 0x2000 + i)

wr(OFF_CSI_MUX + SW_MI0, 1)
wr(OFF_CSI_MUX + SW_CTRL, SW_COMMIT)
wr(OFF_S2MM + MEM_LO, RESULTS_PA & 0xFFFFFFFF)
wr(OFF_S2MM + MEM_HI, RESULTS_PA >> 32)
wr(OFF_S2MM + SIZE, 16)
wr(OFF_S2MM + AP_CTRL, 0x81)
wr(OFF_MM2S + MEM_LO, FRAME_PA & 0xFFFFFFFF)
wr(OFF_MM2S + MEM_HI, FRAME_PA >> 32)
wr(OFF_MM2S + SIZE, 32)
wr(OFF_MM2S + AP_CTRL, 0x01)
time.sleep(0.3)
print(f"mover armed: ap_ctrl = 0x{rd(OFF_MM2S + AP_CTRL):02x}")

hit = None
for a in sorted(orig):
    for val in (0xFFFFFFFF, 0x00000000):
        aie_wr(a, val)
        time.sleep(0.12)
        v = rd(OFF_MM2S + AP_CTRL)
        if v & 0x02:
            hit = (a, val)
            break
        aie_wr(a, orig[a])
    print(f"  tried +0x{a:05x}: ap_ctrl = 0x{rd(OFF_MM2S + AP_CTRL):02x}")
    if hit:
        break

if hit is None:
    for a, v in orig.items():
        aie_wr(tile + 0, 0) if False else aie_wr(a, v)
    print("NO MUX SETTING UNBLOCKED IT - originals restored")
else:
    a, val = hit
    print(f"*** UNBLOCKED by writing 0x{val:08x} to +0x{a:05x} ***")
