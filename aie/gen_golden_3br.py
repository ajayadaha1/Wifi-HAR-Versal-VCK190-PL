#!/usr/bin/env python3
# Generate breathing + phase golden for the 3-branch on-target host, from the
# feature_graph per-branch inputs (motion golden already exists as golden.txt).
#   breathing: |rfft(hann * breath_input)|  (N=64 -> 33 bins), matches dft_mag_core
#   phase-var: [mean, population var, mean-square] of phase_input (L=256), matches stats_core
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
data = os.path.join(HERE, "data")


def load(path):
    with open(path) as f:
        return [float(t) for t in f.read().split()]


# breathing: |DFT(hann*x)| bins 0..N/2 — matches dft_mag_core / np.fft.rfft(hann*x)
N, NB = 64, 33
xb = load(os.path.join(data, "breath_input.txt"))[:N]
hann = [0.5 - 0.5 * math.cos(2 * math.pi * n / (N - 1)) for n in range(N)]
breath_golden = []
for k in range(NB):
    re = im = 0.0
    for n in range(N):
        xw = xb[n] * hann[n]
        ang = 2 * math.pi * k * n / N
        re += xw * math.cos(ang)
        im -= xw * math.sin(ang)
    breath_golden.append(math.sqrt(re * re + im * im))
with open(os.path.join(data, "breath_golden.txt"), "w") as f:
    f.write("\n".join(f"{v:.8e}" for v in breath_golden) + "\n")

# phase-var: [mean, population var, mean-square] of L samples — matches stats_core
L = 256
xp = load(os.path.join(data, "phase_input.txt"))[:L]
mean = sum(xp) / L
var = sum((v - mean) ** 2 for v in xp) / L
power = sum(v * v for v in xp) / L
with open(os.path.join(data, "phase_golden.txt"), "w") as f:
    f.write(f"{mean:.8e}\n{var:.8e}\n{power:.8e}\n")

print("breath_golden(33) first3:", breath_golden[:3])
print("phase_golden(3):", [mean, var, power])
