#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# run_golden.py — P1 self-check: generate synthetic CSI, run the ruview-aligned
# pipeline, verify it recovers the injected breathing rate and motion window,
# and freeze stage-by-stage golden vectors for later AIE bit-accuracy checks.
# ---------------------------------------------------------------------------
import os
import numpy as np

from synth_csi import generate
from csi_pipeline import run_pipeline

OUT = os.path.join(os.path.dirname(__file__), "golden")


def main():
    os.makedirs(OUT, exist_ok=True)
    csi, truth = generate(n_frames=1200, fs=20.0, breathing_bpm=18.0, motion=(25.0, 40.0))
    fs = truth["fs"]
    r = run_pipeline(csi, fs)

    # --- breathing check ---
    br = r["br"]
    err = abs(br["bpm_fft"] - truth["breathing_bpm"])
    print(f"breathing: injected={truth['breathing_bpm']:.1f}  "
          f"fft={br['bpm_fft']:.2f}  zc={br['bpm_zc']:.2f}  BPM (sub #{br['subcarrier']})")

    # --- motion check: energy inside window vs outside ---
    t = np.arange(csi.shape[0]) / fs
    t0, t1 = truth["motion_window"]
    me = r["motion_energy"]
    inside = me[(t >= t0) & (t < t1)].mean()
    outside = me[(t < t0) | (t >= t1)].mean()
    ratio = inside / (outside + 1e-12)
    print(f"motion:    inside={inside:.3e}  outside={outside:.3e}  ratio={ratio:.1f}x")

    # --- save golden vectors (small) ---
    f, tt, spec = r["spec"]
    np.savez_compressed(
        os.path.join(OUT, "golden_stage_vectors.npz"),
        csi=csi, amp=r["amp"], phase_san=r["phase_san"],
        spec_f=f, spec_t=tt, spec_db=spec.astype(np.float32),
        motion_energy=me, br_signal=br["signal"],
        truth=np.array(str(truth)),
    )
    print(f"saved goldens -> {os.path.join(OUT, 'golden_stage_vectors.npz')}")

    ok = (err < 2.0) and (ratio > 3.0)
    print("SELF-CHECK:", "PASS" if ok else "FAIL",
          f"(BR err={err:.2f} BPM, motion ratio={ratio:.1f}x)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
