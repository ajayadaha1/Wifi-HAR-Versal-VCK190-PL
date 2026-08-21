#!/usr/bin/env python3
"""shim_probe.py - dump the AIE shim stream switch config for a column.

The PL->AIE path only works if the shim tile's stream switch is configured to
carry the PL port into the core. That configuration comes from the graph CDO.
Reading it tells us whether the CDO programmed anything at all for our column,
and which ports it enabled - as opposed to inferring from a stalled TREADY.

AIE1 (VC1902): tile = 0x20000000000 + (col<<23) + (row<<18); shim is row 0.
Stream switch config lives around 0x3F000 (masters) / 0x3F100 (slaves). Rather
than decode exact bitfields (which differ between AIE generations and are easy
to get wrong), this dumps the window and reports every NON-ZERO word: a shim
that was never configured reads back all zeros, which is an unambiguous answer.

Must run under Linux - the array is unreadable over JTAG from a halted A72 at
U-Boot because the CCI/NoC path is not up there.

Usage:  python3 shim_probe.py [col ...]      (default: 24, and 11 for contrast)
"""
import mmap
import os
import struct
import sys

BASE = 0x20000000000
WINDOWS = [("stream_switch_master", 0x3F000, 0x80),
           ("stream_switch_slave",  0x3F100, 0x80),
           ("stream_switch_slot",   0x3F200, 0x100)]
CORE_STATUS = 0x32004

cols = [int(a) for a in sys.argv[1:]] or [24, 11]
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)


def rd(addr):
    pg, off = addr & ~0xFFF, addr & 0xFFF
    try:
        m = mmap.mmap(fd, 4096, offset=pg, prot=mmap.PROT_READ)
        v = struct.unpack("<I", m[off:off + 4])[0]
        m.close()
        return v
    except Exception:
        return None


for col in cols:
    tile = BASE + (col << 23)                      # row 0 = shim
    print(f"===== AIE column {col} (shim tile @ 0x{tile:011x}) =====")
    core = rd(BASE + (col << 23) + (1 << 18) + CORE_STATUS)
    print(f"  core(row1) Core_Status = "
          f"{'unreadable' if core is None else f'0x{core:08x}'}")
    for name, off, size in WINDOWS:
        nz = []
        for i in range(0, size, 4):
            v = rd(tile + off + i)
            if v not in (None, 0):
                nz.append((off + i, v))
        if nz:
            print(f"  {name}: {len(nz)} non-zero")
            for a, v in nz[:12]:
                print(f"      +0x{a:05x} = 0x{v:08x}   (port {(a - off)//4})")
        else:
            print(f"  {name}: ALL ZERO  <- nothing configured here")
