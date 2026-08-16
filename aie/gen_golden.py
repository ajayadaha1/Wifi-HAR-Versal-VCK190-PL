#!/usr/bin/env python3
# Golden for the FIR->stats motion-energy chain: coeffs + input + {mean,var,power}.
import os
import numpy as np
from scipy.signal import firwin, lfilter

HERE = os.path.dirname(__file__)
N_TAPS, BLOCK, FS = 31, 256, 20.0

b = firwin(N_TAPS, [1.0, 3.0], pass_zero=False, fs=FS).astype(np.float32)
t = np.arange(BLOCK) / FS
rng = np.random.default_rng(0)
x = (np.sin(2 * np.pi * 0.3 * t)
     + 0.8 * np.sin(2 * np.pi * 2.0 * t)
     + 0.05 * rng.standard_normal(BLOCK)).astype(np.float32)
y = lfilter(b, 1.0, x).astype(np.float32)          # FIR band-pass
golden = np.array([y.mean(), y.var(), (y ** 2).mean()], dtype=np.float32)  # power = motion energy

os.makedirs(os.path.join(HERE, "data"), exist_ok=True)
os.makedirs(os.path.join(HERE, "src"), exist_ok=True)
with open(os.path.join(HERE, "src", "coeffs.h"), "w") as f:
    f.write(f"#pragma once\n#define N_TAPS {N_TAPS}\n#define BLOCK {BLOCK}\n")
    f.write("static const float COEFFS[N_TAPS] = {" + ", ".join(f"{c:.8e}f" for c in b) + "};\n")
np.savetxt(os.path.join(HERE, "data", "input.txt"), x, fmt="%.8e")
np.savetxt(os.path.join(HERE, "data", "golden.txt"), golden, fmt="%.8e")
print(f"wrote coeffs.h, input({BLOCK})/golden(3): motion_power={golden[2]:.6f}")
