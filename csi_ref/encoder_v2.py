#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# encoder_v2.py — ruview pretrained CSI embedding encoder (numpy forward).
#
# Loads the real ruview weights (csi-embed-v2.safetensors) and runs the exact
# architecture from the model card (csi-embed-v2.py):
#   feat8 -> Linear(8,64) -> BN -> GELU -> Linear(64,128) -> BN -> L2  (9,280 params)
# Plus the linear presence head (presence-head.json) over the 128-d embedding.
#
# numpy-only forward (no torch): this is the classifier the AI Engine will run
# after the DSP feature stage. Input = the 8-dim ruview feature vector.
# ---------------------------------------------------------------------------
import json
import os
import struct
import numpy as np
from scipy.special import erf

_HERE = os.path.dirname(__file__)
_MODELS = os.path.join(_HERE, "models")
_EPS = 1e-5  # torch BatchNorm default


def load_safetensors(path):
    dt = {"F64": np.float64, "F32": np.float32, "F16": np.float16, "I64": np.int64}
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        hdr = json.loads(f.read(n))
        blob = f.read()
    out = {}
    for k, v in hdr.items():
        if k == "__metadata__":
            continue
        a, b = v["data_offsets"]
        out[k] = np.frombuffer(blob[a:b], dtype=dt[v["dtype"]]).reshape(v["shape"])
    return out


def _gelu(x):
    return 0.5 * x * (1.0 + erf(x / np.sqrt(2.0)))


def _bn(x, w, b, mean, var):
    return (x - mean) / np.sqrt(var + _EPS) * w + b


class CSIEmbedV2:
    def __init__(self, safetensors=None):
        w = load_safetensors(safetensors or os.path.join(_MODELS, "csi-embed-v2.safetensors"))
        self.w = w

    def embed(self, feat8):
        x = np.atleast_2d(np.asarray(feat8, np.float32))       # [B, 8]
        w = self.w
        h = x @ w["w1.weight"].T + w["w1.bias"]                # Linear(8->64)
        h = _bn(h, w["bn1.weight"], w["bn1.bias"], w["bn1.running_mean"], w["bn1.running_var"])
        h = _gelu(h)
        z = h @ w["w2.weight"].T + w["w2.bias"]                # Linear(64->128)
        z = _bn(z, w["bn2.weight"], w["bn2.bias"], w["bn2.running_mean"], w["bn2.running_var"])
        return z / (np.linalg.norm(z, axis=-1, keepdims=True) + 1e-9)  # L2


class PresenceHead:
    def __init__(self, path=None):
        d = json.load(open(path or os.path.join(_MODELS, "presence-head.json")))
        w = np.asarray(d["weights"], np.float32)
        if "bias" in d:
            self.w, self.b = w, float(d["bias"])
        elif w.size == 129:
            self.w, self.b = w[:128], float(w[128])
        else:
            self.w, self.b = w[:128], 0.0

    def score(self, emb):
        z = np.atleast_2d(emb) @ self.w + self.b
        return 1.0 / (1.0 + np.exp(-z))
