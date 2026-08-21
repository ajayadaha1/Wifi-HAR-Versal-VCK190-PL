#!/usr/bin/env python3
# Synthetic CSI "recording" for the live AIE demo: a sequence of 256-sample
# windows whose motion-band content mimics activities. The FIR->stats AIE graph
# turns each window into {mean,var,power}; power tracks motion.
import math, random
random.seed(7)
N=256
def win(amp, f=0.0):
    # baseline + optional slow modulation (breathing-ish) + motion noise of scale amp
    out=[]
    for n in range(N):
        base=1.0
        breath=0.02*math.sin(2*math.pi*(0.3)*n/100.0) if f>0 else 0.0
        motion=amp*(random.random()-0.5)
        out.append(base+breath+motion)
    return out
segments=[]
# 8 still, 10 walking, 8 still, 10 breathing (low motion + modulation)
for _ in range(8):  segments.append(win(0.02))          # STILL (low power)
for _ in range(10): segments.append(win(0.35))          # WALKING (high power)
for _ in range(8):  segments.append(win(0.02))          # STILL
for _ in range(10): segments.append(win(0.05, f=0.3))   # BREATHING (low motion, modulated)
with open("demo_windows.txt","w") as fp:
    for w in segments:
        fp.write(" ".join(f"{x:.6f}" for x in w)+"\n")
print(f"wrote demo_windows.txt: {len(segments)} windows x {N} samples")
