#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# run_encoder.py — P1 check for the pretrained ruview encoder.
#
# Loads real ruview 8-dim feature recordings, runs the pretrained encoder, and
# verifies (a) embeddings are unit-norm, (b) the contrastive property holds:
# temporally-adjacent frames are MORE similar than random pairs, and the
# encoder amplifies that gap vs the raw features (what the 82.3% number means).
# ---------------------------------------------------------------------------
import argparse
import json
import os
import numpy as np

from encoder_v2 import CSIEmbedV2, PresenceHead

REC = ("/group/bcapps/ajayad/master_thesis_rebirth/Versal-Ethernet/VCK190-Ethernet/"
       "2022.1/ps_emio_basex_1g/Software/ruview/data/recordings/pretrain-1775182186.csi.jsonl")


def load_features(path, node_id=1, limit=4000):
    feats = []
    with open(path) as f:
        for line in f:
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            if r.get("type") == "feature" and r.get("node_id") == node_id:
                feats.append(r["features"])
                if len(feats) >= limit:
                    break
    return np.asarray(feats, np.float32)


def adj_vs_random(emb, seed=0):
    a = np.mean(np.sum(emb[:-1] * emb[1:], axis=1))                 # adjacent cosine (unit-norm)
    rng = np.random.default_rng(seed)
    j = rng.integers(0, len(emb), size=len(emb))
    r = np.mean(np.sum(emb * emb[j], axis=1))
    return a, r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rec", default=REC)
    ap.add_argument("--node", type=int, default=1)
    a = ap.parse_args()

    feat = load_features(a.rec, a.node)
    print(f"features: {feat.shape} from node {a.node}")

    enc = CSIEmbedV2()
    emb = enc.embed(feat)
    norms = np.linalg.norm(emb, axis=1)
    print(f"embeddings: {emb.shape}  L2 norm mean={norms.mean():.4f} (want 1.0)")

    # raw features L2-normalized for a fair adjacency comparison
    rawn = feat / (np.linalg.norm(feat, axis=1, keepdims=True) + 1e-9)
    ra, rr = adj_vs_random(rawn)
    ea, er = adj_vs_random(emb)
    print(f"raw     : adjacent={ra:.4f} random={rr:.4f} gap={ra - rr:+.4f}")
    print(f"encoder : adjacent={ea:.4f} random={er:.4f} gap={ea - er:+.4f}")

    ph = PresenceHead()
    sc = ph.score(emb).ravel()
    print(f"presence: n={sc.size} mean={sc.mean():.3f} min={sc.min():.3f} max={sc.max():.3f}")

    ok = (abs(norms.mean() - 1.0) < 1e-3) and ((ea - er) > (ra - rr)) and ((ea - er) > 0)
    print("SELF-CHECK:", "PASS" if ok else "FAIL",
          "(unit-norm + encoder amplifies temporal structure)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
