#!/usr/bin/env python3
"""Locate enabled AI Engine cores by scanning Core_Status across the array.

AIE1 (VC1902): tile = 0x20000000000 + (col<<23) + (row<<18);
Core_Status is at offset 0x00032004. Bit0=Enable, Bit1=Reset.
Reads via /dev/mem, which works once Linux is up (JTAG from a halted A72 at
U-Boot cannot reach the array - the CCI/NoC path is not configured there).
"""
import mmap, os, struct, sys

BASE, CORE_STATUS = 0x20000000000, 0x32004
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
found, errs = [], 0
for col in range(50):
    for row in (1, 2):
        a = BASE + (col << 23) + (row << 18) + CORE_STATUS
        pg, off = a & ~0xFFF, a & 0xFFF
        try:
            m = mmap.mmap(fd, 4096, offset=pg, prot=mmap.PROT_READ)
            v = struct.unpack("<I", m[off:off + 4])[0]
            m.close()
        except Exception:
            errs += 1
            continue
        if v not in (0, 0xFFFFFFFF):
            found.append((col, row, v))
print(f"scanned 50 cols x 2 rows, {errs} unreadable")
for c, r, v in found:
    print(f"  col {c:2d} row {r}: Core_Status=0x{v:08x} enable={v&1} reset={(v>>1)&1}")
if not found:
    print("  NO enabled cores anywhere - the graph is not running")
