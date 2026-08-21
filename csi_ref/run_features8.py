#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# run_features8.py — P1 end-to-end: raw CSI -> ruview 8-features -> pretrained
# encoder -> 128-d embedding, for empty / breathing / walking. Confirms the
# feature packing matches the spec and that scenarios yield distinct embeddings.
# ---------------------------------------------------------------------------
import numpy as np

from synth_csi import generate
from features8 import build_features8, features8_from_csi
from encoder_v2 import CSIEmbedV2, PresenceHead

FS = 20.0
SCEN = [
    ("empty",                dict(breathing_depth_mm=0.0, motion=None)),
    ("stationary-breathing", dict(breathing_depth_mm=5.0, motion=None)),
    ("walking",              dict(breathing_depth_mm=5.0, motion=(0.0, 60.0))),
]


def main():
    # spec check: RSSI normalization must match the ruview recordings.
    f = build_features8(0, 0, 0, 0, 0, 0, False, -18.0)
    assert abs(f[7] - 0.82) < 1e-6, f[7]
    print(f"spec check: RSSI -18 dBm -> f7={f[7]:.3f} OK")

    enc, ph = CSIEmbedV2(), PresenceHead()
    embs, names = [], []
    for name, kw in SCEN:
        csi, _ = generate(n_frames=1200, fs=FS, **kw)
        feat = features8_from_csi(csi, FS, rssi_dbm=-30.0)
        z = enc.embed(feat)
        embs.append(z.ravel())
        names.append(name)
        print(f"{name:22s} feat8={np.round(feat, 2)} presence={ph.score(z).ravel()[0]:.2f}")

    E = np.stack(embs)
    print("\npairwise embedding cosine distance (1 - cos):")
    for i in range(len(E)):
        for j in range(i + 1, len(E)):
            d = 1.0 - float(E[i] @ E[j])
            print(f"  {names[i]:22s} vs {names[j]:22s} : {d:.4f}")

    seps = [1.0 - float(E[i] @ E[j]) for i in range(len(E)) for j in range(i + 1, len(E))]
    ok = min(seps) > 1e-3
    print("SELF-CHECK:", "PASS" if ok else "FAIL", "(distinct embeddings per activity)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
