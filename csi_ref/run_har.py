#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# run_har.py — P1 HAR self-check: three synthetic scenarios (empty / stationary
# breathing / walking) must classify correctly via the ruview-style rule
# classifier, with no weights and no training.
# ---------------------------------------------------------------------------
from synth_csi import generate
from har import presence_and_activity

FS = 20.0
SCENARIOS = [
    ("empty",                dict(breathing_depth_mm=0.0, motion=None),        "empty"),
    ("stationary-breathing", dict(breathing_depth_mm=5.0, motion=None),        "stationary-breathing"),
    ("walking",              dict(breathing_depth_mm=5.0, motion=(0.0, 60.0)), "active/walking"),
]


def main():
    ok = True
    for name, kw, expect in SCENARIOS:
        csi, _ = generate(n_frames=1200, fs=FS, **kw)
        r = presence_and_activity(csi, FS)
        hit = (r["label"] == expect)
        ok = ok and hit
        print(f"{name:22s} -> {r['label']:22s} "
              f"[motion={r['motion']:.2e} br_snr={r['br_snr']:.1f} bpm={r['bpm']:.1f}] "
              f"{'OK' if hit else 'MISMATCH (exp ' + expect + ')'}")
    print("SELF-CHECK:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
