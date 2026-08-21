#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# csi_pipeline.py — ruview-aligned CSI DSP reference (P1 golden model).
#
# Mirrors the ruview signal crate stage-for-stage on raw CSI [T, K] complex:
#   amplitude/phase -> linear phase sanitization -> Hampel -> subcarrier
#   selection -> STFT spectrogram -> motion-band power -> breathing rate ->
#   Doppler/BVP. These are the exact ops we later map to the AI Engine; this
#   module is the bit-accuracy target for the AIE kernels (see plan.md P2/P3).
#
# NOT a CNN and NOT image classification — this is the raw-CSI DSP + light
# feature path ruview uses. The classifier head (ruview 128-d encoder) plugs in
# after this. Deps: numpy, scipy.
# ---------------------------------------------------------------------------
import numpy as np
from scipy.signal import butter, sosfiltfilt, stft

C = 3.0e8


def amplitude_phase(csi):
    return np.abs(csi), np.angle(csi)


def sanitize_phase_linear(phase, kc=None):
    """Per-packet linear de-trend across subcarriers -> removes CFO (intercept)
    and SFO/packet-delay (slope). Amplitude is impairment-immune and untouched."""
    T, K = phase.shape
    if kc is None:
        kc = np.arange(K) - K // 2
    A = np.vstack([kc, np.ones(K)]).T
    out = np.empty_like(phase)
    for t in range(T):
        u = np.unwrap(phase[t])
        coef, *_ = np.linalg.lstsq(A, u, rcond=None)
        out[t] = u - A @ coef
    return out


def hampel(x, window=7, n_sigma=3.0):
    """Median/MAD outlier rejection along time (axis 0), per subcarrier."""
    x = np.asarray(x, float)
    T = x.shape[0]
    out = x.copy()
    half = window // 2
    for t in range(T):
        lo, hi = max(0, t - half), min(T, t + half + 1)
        med = np.median(x[lo:hi], axis=0)
        mad = 1.4826 * np.median(np.abs(x[lo:hi] - med), axis=0) + 1e-9
        bad = np.abs(x[t] - med) > n_sigma * mad
        out[t, bad] = med[bad]
    return out


def subcarrier_sensitivity(amp, fs, band=(0.1, 0.5)):
    """Rank subcarriers by band-limited temporal variance (motion/vitals energy)."""
    sos = butter(2, band, btype="band", fs=fs, output="sos")
    bp = sosfiltfilt(sos, amp - amp.mean(0), axis=0)
    return np.argsort(bp.var(0))[::-1]


def stft_spectrogram(sig, fs, nperseg=64, noverlap=48):
    """Per-signal STFT magnitude in dB -> [freq, time] (the AIE STFT target)."""
    f, tt, Z = stft(sig, fs=fs, nperseg=nperseg, noverlap=noverlap, window="hann")
    return f, tt, 20 * np.log10(np.abs(Z) + 1e-9)


def motion_energy(amp, fs, band=(1.0, 3.0), smooth_s=1.0):
    """1-3 Hz amplitude-fluctuation power over time -> activity energy [T]."""
    sos = butter(4, band, btype="band", fs=fs, output="sos")
    bp = sosfiltfilt(sos, amp - amp.mean(0), axis=0)
    e = (bp ** 2).mean(1)
    w = max(1, int(smooth_s * fs))
    return np.convolve(e, np.ones(w) / w, mode="same")


def breathing_rate(amp, fs, band=(0.1, 0.5)):
    """BR from the most sensitive subcarrier's amplitude (impairment-immune).
    Returns dict with FFT-peak and zero-crossing BPM estimates."""
    sc = int(subcarrier_sensitivity(amp, fs, band)[0])
    sig = amp[:, sc] - amp[:, sc].mean()
    sos = butter(2, band, btype="band", fs=fs, output="sos")
    bp = sosfiltfilt(sos, sig)

    T = bp.size
    F = np.abs(np.fft.rfft(bp * np.hanning(T)))
    f = np.fft.rfftfreq(T, 1.0 / fs)
    m = (f >= band[0]) & (f <= band[1])
    bpm_fft = float(f[m][np.argmax(F[m])] * 60.0)

    zc = np.sum(np.abs(np.diff(np.sign(bp))) > 0) / 2.0
    bpm_zc = float(zc / (T / fs) * 60.0)
    return dict(subcarrier=sc, bpm_fft=bpm_fft, bpm_zc=bpm_zc, signal=bp)


def bvp_doppler(csi, fs, nperseg=64, noverlap=56, fc=5.18e9):
    """Velocity-time profile via STFT of the subcarrier-summed complex CSI.
    NOTE: meaningful Doppler needs fs >~ 200 Hz (Widar); at 20 Hz this is a
    placeholder that becomes real once fast-rate capture is available."""
    s = csi.sum(1)
    f, tt, Z = stft(s, fs=fs, nperseg=nperseg, noverlap=noverlap,
                    window="hann", return_onesided=False)
    vel = np.fft.fftshift(f) * (C / fc) / 2.0
    return vel, tt, np.fft.fftshift(np.abs(Z), axes=0)


def run_pipeline(csi, fs, fc=5.18e9):
    amp, phase = amplitude_phase(csi)
    amp = hampel(amp)
    phase_san = sanitize_phase_linear(phase)
    br = breathing_rate(amp, fs)
    f, tt, spec = stft_spectrogram(amp[:, br["subcarrier"]], fs)
    me = motion_energy(amp, fs)
    return dict(amp=amp, phase_san=phase_san, br=br,
                spec=(f, tt, spec), motion_energy=me)
