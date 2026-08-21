#!/usr/bin/env python3
# Prove the csi_mux control-AXI at 0xA4060000 RESPONDS (does not hang) - the crux
# of the D2 fix. Read MI0 route reg, the commit reg, and a scratch read of 0x00.
import mmap, os, struct, sys
BASE = 0xA4060000
f = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(f, 0x1000, offset=BASE)
mi0 = struct.unpack("<I", m[0x40:0x44])[0]
ctl = struct.unpack("<I", m[0x00:0x04])[0]
print(f"csi_mux @0x{BASE:08x} RESPONDS: MI0=0x{mi0:08x} CTRL=0x{ctl:08x}")
# 0x80000000 on MI0 == 'disabled' (reset default) -> proves a real read, not a hang
m.close(); os.close(f)
