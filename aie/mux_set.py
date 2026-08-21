#!/usr/bin/env python3
# Set csi_mux (axis_switch @0xA4060000) MI0 route before the AIE datapath runs.
# sel=1 -> S01 (mm2s/DDR replay, D1). Mirrors csi_ctl cmd_mux.
import mmap, os, struct, sys
BASE=0xA4060000; SEL=int(sys.argv[1]) if len(sys.argv)>1 else 1
f=os.open("/dev/mem", os.O_RDWR|os.O_SYNC)
m=mmap.mmap(f,0x1000,offset=BASE)
m[0x40:0x44]=struct.pack("<I", SEL&0x7)   # MI0 mux register
m[0x00:0x04]=struct.pack("<I", 0x2)        # commit (reg update)
sel=struct.unpack("<I", m[0x40:0x44])[0]&0x7
print(f"csi_mux MI0 select = {sel} ({'mm2s/DDR' if sel else 'parser/live'})")
m.close(); os.close(f)
