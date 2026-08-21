#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# synth_csi.py — synthetic raw CSI for P1 offline development (no Pi needed).
#
# Produces a [T, K] complex CSI stream that mimics what decode_csi.py yields
# from a real nexmon capture, with:
#   - a static multipath channel,
#   - a breathing-modulated reflection (known rate, for BR validation),
#   - an optional motion burst (1-3 Hz amplitude fluctuation, for activity),
#   - hardware impairments (CFO common phase + SFO linear slope) so the phase
#     sanitization stage has something real to remove.
#
# numpy-only (no scipy) so the generator stays lightweight.
# ---------------------------------------------------------------------------
import numpy as np

C = 3.0e8
DF = 312.5e3  # OFDM subcarrier spacing, 20 MHz 802.11


def _bandlimited(T, fs, lo, hi, rng):
    """Unit-variance noise band-limited to [lo, hi] Hz via FFT masking."""
    w = rng.standard_normal(T)
    W = np.fft.rfft(w)
    f = np.fft.rfftfreq(T, 1.0 / fs)
    W[(f < lo) | (f > hi)] = 0.0
    x = np.fft.irfft(W, n=T)
    return x / (x.std() + 1e-9)


def _multipath(kc, rng, n_paths=5, max_delay=80e-9):
    H = np.zeros(kc.size, complex)
    for _ in range(n_paths):
        g = (rng.standard_normal() + 1j * rng.standard_normal()) / np.sqrt(2)
        tau = rng.uniform(0, max_delay)
        H += g * np.exp(-1j * 2 * np.pi * kc * DF * tau)
    return H


def generate(n_frames=1200, n_sub=64, fs=20.0, fc=5.18e9,
             breathing_bpm=18.0, breathing_depth_mm=5.0,
             motion=(25.0, 40.0), snr_db=30.0,
             cfo_hz=200.0, sfo_ppm=20.0, seed=0):
    rng = np.random.default_rng(seed)
    t = np.arange(n_frames) / fs
    kc = np.arange(n_sub) - n_sub // 2
    lam = C / fc

    H = np.tile(_multipath(kc, rng), (n_frames, 1)).astype(complex)  # static channel

    # Breathing reflection: chest displacement -> common phase on one path.
    f_br = breathing_bpm / 60.0
    d = (breathing_depth_mm * 1e-3) * np.sin(2 * np.pi * f_br * t)
    g_br = 0.6 * (rng.standard_normal() + 1j * rng.standard_normal())
    br_path = g_br * np.exp(-1j * 2 * np.pi * kc * DF * rng.uniform(0, 80e-9))
    H += br_path[None, :] * np.exp(-1j * 4 * np.pi * d / lam)[:, None]

    # Motion burst: 1-3 Hz amplitude/phase fluctuation scaled by the channel.
    motion_win = None
    if motion is not None:
        t0, t1 = motion
        motion_win = (t0, t1)
        m = _bandlimited(n_frames, fs, 1.0, 3.0, rng)
        mask = ((t >= t0) & (t < t1)).astype(float)
        H += (0.5 * H) * (mask * m)[:, None]

    # Hardware impairments (pure phase): CFO common term + SFO linear slope.
    theta_cfo = 2 * np.pi * cfo_hz * t
    eps = (sfo_ppm * 1e-6) * np.sin(2 * np.pi * 0.05 * t)   # slowly drifting SFO
    H *= np.exp(1j * theta_cfo)[:, None]
    H *= np.exp(1j * 2 * np.pi * kc[None, :] * eps[:, None])

    # AWGN at the requested SNR.
    sig_p = np.mean(np.abs(H) ** 2)
    noise_p = sig_p / (10 ** (snr_db / 10.0))
    H += np.sqrt(noise_p / 2) * (rng.standard_normal(H.shape) + 1j * rng.standard_normal(H.shape))

    truth = dict(fs=fs, fc=fc, n_sub=n_sub, breathing_bpm=breathing_bpm,
                 breathing_hz=f_br, motion_window=motion_win, snr_db=snr_db)
    return H.astype(np.complex64), truth


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Write a synthetic raw-CSI .npy")
    ap.add_argument("-o", "--out", default="synth_csi.npy")
    ap.add_argument("-t", "--frames", type=int, default=1200)
    ap.add_argument("--bpm", type=float, default=18.0)
    a = ap.parse_args()
    csi, truth = generate(n_frames=a.frames, breathing_bpm=a.bpm)
    np.save(a.out, csi)
    print(f"wrote {a.out}: {csi.shape} {csi.dtype}; truth={truth}")
