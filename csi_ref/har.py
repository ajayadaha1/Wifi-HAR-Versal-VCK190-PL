#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# har.py — activity/presence classification the ruview way (P1).
#
# ruview classifies discrete activity from DSP features (motion-band power +
# breathing presence), NOT a spectrogram-image CNN. This module provides:
#   - presence_and_activity(): a rule classifier over the pipeline features
#     (works now, no weights, no training) — ruview's motion.rs approach;
#   - CSIEncoder: a numpy forward-only 128-d temporal encoder scaffold for the
#     learned path (ruview AETHER), pretrained-weight load pending clean format.
# ---------------------------------------------------------------------------
import numpy as np

from csi_pipeline import amplitude_phase, hampel, motion_energy, breathing_rate

# Thresholds tuned on synthetic CSI — revisit on real captures.
MOTION_TH = 5e-3
BR_SNR_TH = 5.0


def _breathing_snr(sig, fs, band=(0.1, 0.5)):
    F = np.abs(np.fft.rfft(sig * np.hanning(sig.size)))
    f = np.fft.rfftfreq(sig.size, 1.0 / fs)
    m = (f >= band[0]) & (f <= band[1])
    return float(F[m].max() / (np.median(F[m]) + 1e-9))


def presence_and_activity(csi, fs):
    """Return {label, motion, bpm, br_snr} for one CSI window/stream."""
    amp, _ = amplitude_phase(csi)
    amp = hampel(amp)
    me = float(motion_energy(amp, fs).mean())
    br = breathing_rate(amp, fs)
    br_snr = _breathing_snr(br["signal"], fs)

    if me > MOTION_TH:
        label = "active/walking"
    elif br_snr > BR_SNR_TH:
        label = "stationary-breathing"
    else:
        label = "empty"
    return dict(label=label, motion=me, bpm=br["bpm_fft"], br_snr=br_snr)


class CSIEncoder:
    """ruview-style temporal encoder -> 128-d L2-normalized embedding.

    Forward-only numpy scaffold (random init). load_weights() will accept the
    pretrained ruview AETHER weights once the HF format is sorted; until then
    the working HAR path is presence_and_activity() above.
    """

    def __init__(self, n_sub=64, hidden=64, emb=128, seed=0):
        rng = np.random.default_rng(seed)
        self.w1 = rng.standard_normal((n_sub, hidden)) * 0.1
        self.w2 = rng.standard_normal((hidden, emb)) * 0.1

    def embed(self, window):
        x = np.abs(window)                              # [W, K] amplitude
        x = (x - x.mean(0)) / (x.std(0) + 1e-6)
        h = np.tanh(x @ self.w1).mean(0)                # temporal pool -> [hidden]
        z = h @ self.w2
        return z / (np.linalg.norm(z) + 1e-9)

    def load_weights(self, path):
        raise NotImplementedError("ruview pretrained load pending clean HF format")


def window_csi(csi, win, hop):
    T = csi.shape[0]
    return np.stack([csi[i:i + win] for i in range(0, T - win + 1, hop)])
