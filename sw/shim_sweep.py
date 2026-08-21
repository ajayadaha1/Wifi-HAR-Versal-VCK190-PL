#!/usr/bin/env python3
"""shim_sweep.py - find which shim slave port the PL channel actually drives.

Background (PROJECT_STATE #17-#20): the AIE graph runs, its core sits enabled
and stalled at (24,1), the shim stream switch in column 24 is configured
(master 18 <- slave 3), and the PL channel is placed in column 24 - and still
ai_engine_0/S00_AXIS never asserts TREADY. The one thing left unpinned is WHICH
physical shim slave port our PL channel feeds. In the Vitis flow that binding
is xclbin metadata (`<arg name="PLIO_in" port="S00_AXIS">`), and it did not
survive capturing the ai_engine IP into a plain Vivado BD.

The trick that makes this cheap: an HLS mover blocked on TREADY is blocked
MID-TRANSFER, not failed. It cannot be re-armed (ap_ctrl_hs latches ap_start
until ap_done) - but it does not need to be. If the routing is corrected while
it is stalled, TREADY finally asserts and the *same* transfer runs to
completion. So one boot can test every candidate port: start the mover once,
then walk the slave index feeding the core's master port and watch ap_ctrl.

A hit prints the port and stops. If nothing hits, the original value is
restored so the board is left as it was found.

Usage:  python3 shim_sweep.py [col] [master_port]        default 24, 18
"""
import mmap
import os
import struct
import sys
import time

BASE = 0x20000000000
SW_MASTER = 0x3F000                       # + 4*port
PL_BASE = 0xA4000000
OFF_MM2S, OFF_CSI_MUX, OFF_S2MM = 0x00000, 0x60000, 0x10000
AP_CTRL, MEM_LO, MEM_HI, SIZE = 0x00, 0x10, 0x14, 0x1C
SW_CTRL, SW_MI0, SW_COMMIT = 0x00, 0x40, 0x02
FRAME_PA, RESULTS_PA = 0x70020000, 0x70010000

col = int(sys.argv[1]) if len(sys.argv) > 1 else 24
mport = int(sys.argv[2]) if len(sys.argv) > 2 else 18

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
pl = mmap.mmap(fd, 0x100000, offset=PL_BASE)
dd = mmap.mmap(fd, 0x100000, offset=0x70000000)


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


mreg = BASE + (col << 23) + SW_MASTER + 4 * mport
orig = aie_rd(mreg)
print(f"col {col} master port {mport}: original = 0x{orig:08x}")

# payload: aligned 32-bit writes only (Device-nGnRE mapping, see replay_test.py)
for i in range(0, 256, 4):
    dd[(FRAME_PA - 0x70000000) + i:(FRAME_PA - 0x70000000) + i + 4] = \
        struct.pack("<I", 0x1000 + i)
for i in range(0, 64, 4):
    dd[(RESULTS_PA - 0x70000000) + i:(RESULTS_PA - 0x70000000) + i + 4] = b"\0\0\0\0"

# route csi_mux to the DDR replay source, drain the AIE result side
wr(OFF_CSI_MUX + SW_MI0, 1)
wr(OFF_CSI_MUX + SW_CTRL, SW_COMMIT)
wr(OFF_S2MM + MEM_LO, RESULTS_PA & 0xFFFFFFFF)
wr(OFF_S2MM + MEM_HI, RESULTS_PA >> 32)
wr(OFF_S2MM + SIZE, 16)
wr(OFF_S2MM + AP_CTRL, 0x81)

# start the mover; it is expected to stall immediately
wr(OFF_MM2S + MEM_LO, FRAME_PA & 0xFFFFFFFF)
wr(OFF_MM2S + MEM_HI, FRAME_PA >> 32)
wr(OFF_MM2S + SIZE, 32)
wr(OFF_MM2S + AP_CTRL, 0x01)
time.sleep(0.3)
print(f"mover armed: mm2s ap_ctrl = 0x{rd(OFF_MM2S + AP_CTRL):02x} (0x01 = stalled, as expected)")

hit = None
for s in range(0, 24):
    aie_wr(mreg, 0x80000000 | s)
    time.sleep(0.15)
    v = rd(OFF_MM2S + AP_CTRL)
    print(f"  slave {s:2d} -> master {mport}: mm2s ap_ctrl = 0x{v:02x}")
    if v & 0x02:                       # ap_done
        hit = s
        break

if hit is None:
    aie_wr(mreg, orig)
    print(f"NO PORT UNBLOCKED IT - restored 0x{orig:08x}")
else:
    print(f"*** UNBLOCKED by slave port {hit} ***")
    res = [struct.unpack('<I', bytes(dd[(RESULTS_PA - 0x70000000) + i:
                                        (RESULTS_PA - 0x70000000) + i + 4]))[0]
           for i in range(0, 32, 4)]
    print("AIE results:", " ".join(f"0x{x:08x}" for x in res))
