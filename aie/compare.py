#!/usr/bin/env python3
# Compare AIE/host output against the numpy golden. Optional argv[3] = abs tol.
import sys
import numpy as np

o = np.loadtxt(sys.argv[1]).ravel()
g = np.loadtxt(sys.argv[2]).ravel()
tol = float(sys.argv[3]) if len(sys.argv) > 3 else 1e-4
n = min(o.size, g.size)
o, g = o[:n], g[:n]
err = float(np.max(np.abs(o - g))) if n else float("inf")
rel = err / (float(np.max(np.abs(g))) + 1e-12)
print(f"n={n} max_abs_err={err:.3e} max_rel={rel:.3e}")
ok = n > 0 and (err < tol or rel < 1e-4)
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
