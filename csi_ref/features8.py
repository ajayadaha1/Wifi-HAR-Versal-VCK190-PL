#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# features8.py — ruview 8-dim CSI feature vector (magic 0xC5110003).
#
# Exact normalization from the ruview user guide (docs/user-guide.md), verified
# against data/recordings (e.g. RSSI -18 -> 0.82). This is the interface the
# pretrained encoder (encoder_v2.py) consumes, and the vector our AIE/PL feature
# stage must emit on the live path:
#   0 presence/10  1 motion/10  2 bpm/30  3 hr/120
#   4 phase-var    5 persons/4  6 fall     7 (rssi+100)/100
#
# features8_vector() is the canonical packing and is deliberately pure stdlib:
# the live path (work/live/live_dashboard.py, inline_reader.py) runs on a
# minimal PetaLinux rootfs with no numpy and must not fork this normalization.
# numpy and the P1 pipeline are therefore imported lazily, inside the functions
# that need them, so `import features8` works on the target too.
# ---------------------------------------------------------------------------

# Calibration knobs mapping our DSP scales onto ruview's 0-10 internal scales.
MOTION_GAIN = 30.0
PRESENCE_GAIN = 10.0
PHASEVAR_NORM = 3.0


def _clamp(x):
    return float(max(0.0, min(1.0, x)))


def features8_vector(presence_score, motion, breathing_bpm, heartrate_bpm,
                     phase_variance, person_count, fall, rssi_dbm):
    """Pack raw metrics into the ruview 8-dim normalized feature vector (list)."""
    return [
        _clamp(presence_score / 10.0),
        _clamp(motion / 10.0),
        _clamp(breathing_bpm / 30.0),
        _clamp(heartrate_bpm / 120.0),
        _clamp(phase_variance),
        _clamp(person_count / 4.0),
        1.0 if fall else 0.0,
        _clamp((rssi_dbm + 100.0) / 100.0),
    ]


def build_features8(presence_score, motion, breathing_bpm, heartrate_bpm,
                    phase_variance, person_count, fall, rssi_dbm):
    """features8_vector() as a float32 array, for the offline P1 pipeline."""
    import numpy as np
    return np.array(features8_vector(presence_score, motion, breathing_bpm,
                                     heartrate_bpm, phase_variance, person_count,
                                     fall, rssi_dbm), np.float32)


def features8_from_csi(csi, fs, rssi_dbm=-30.0):
    """Derive the ruview 8-dim feature vector from one raw CSI window."""
    import numpy as np

    from csi_pipeline import (amplitude_phase, hampel, sanitize_phase_linear,
                              motion_energy, breathing_rate)
    from har import presence_and_activity

    amp, phase = amplitude_phase(csi)
    amp = hampel(amp)
    me = float(motion_energy(amp, fs).mean())
    br = breathing_rate(amp, fs)
    act = presence_and_activity(csi, fs)

    present = act["label"] != "empty"
    phase_san = sanitize_phase_linear(phase)
    topk = np.argsort(phase_san.var(0))[::-1][:8]
    phase_var = float(phase_san[:, topk].var(0).mean())

    return build_features8(
        presence_score=PRESENCE_GAIN * (1.0 if present else 0.0),
        motion=MOTION_GAIN * me,
        breathing_bpm=br["bpm_fft"] if present else 0.0,
        heartrate_bpm=0.0,                       # unreliable at 20 Hz CSI
        phase_variance=phase_var / PHASEVAR_NORM,
        person_count=1.0 if present else 0.0,
        fall=False,
        rssi_dbm=rssi_dbm,
    )
