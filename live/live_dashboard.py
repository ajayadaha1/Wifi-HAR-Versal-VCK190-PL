#!/usr/bin/env python3
"""live_dashboard.py - WiFi-CSI Human-Activity-Recognition live dashboard (VCK190).

Consumes the AI-Engine feature-extraction outputs and serves a live web
dashboard (Server-Sent Events + a small hand-written canvas renderer) viewable
from any browser on the network - no desktop/VNC needed on the target.

NO CDN, NO JAVASCRIPT LIBRARIES: the page is fully self-contained so it works on
a PetaLinux rootfs with no internet at all.  Routes:
    /            the dashboard page
    /stream      SSE: "init" (config + backlog), default events (feature windows),
                 "hb" (1 Hz heartbeat carrying the server-side data age)
    /api/state   JSON snapshot (status/age/count + last window) - handy for curl
    /healthz     one-line plain-text health check

The AIE emits three feature groups per window (as validated by host_3br):
    mot[3]  motion  : FIR->stats  -> mean, var, power
    brt[33] breathing: windowed-DFT magnitude bins
    phs[3]  phase-var: stats      -> mean, var, power
From these we derive presence / activity / breathing-rate / fall and the
ruview 8-feature vector (see work/csi_ref/features8.py).

Sources (--source):
    golden : replay the committed golden vectors with jitter (offline dev/test,
             NO board) so the dashboard can be built and demoed without hardware.
    exec   : run the on-target XRT host in a loop (--host ./host_3br --stream)
             and parse CSV feature lines "mot0,mot1,mot2,brt0..brt32,phs0,phs1,phs2".
    fifo   : read the same CSV feature lines from a named pipe / file (--fifo path).
    inline : the inline Arch-B datapath (SFP0 -> csi_udp_parser -> AIE -> DDR),
             read straight out of /dev/mem by inline_reader.py. That design is a
             plain Vivado design with no xclbin, so "exec"/XRT does not apply to
             it; it is also the only source that carries real RSSI metadata.
             Add --simulate to drive it with fabricated data, no board.

Pure Python 3 standard library only (http.server + SSE). No flask / numpy on target.
"""
import argparse
import json
import math
import os
import queue
import random
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import inline_reader

# The ruview 8-feature normalization is defined once, in work/csi_ref/features8.py
# (features8_vector() is deliberately stdlib-only) - do not fork it here. On the
# target, copy that one file next to this script; ../csi_ref is searched first.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "csi_ref"))
try:
    from features8 import MOTION_GAIN, PHASEVAR_NORM, PRESENCE_GAIN, features8_vector
except ImportError:
    sys.exit("live_dashboard: csi_ref/features8.py not found - copy it next to this script")

# --- calibratable thresholds (mirror work/csi_ref/har.py) ---------------------
MOTION_TH = 3.3e-3        # demo: synthetic still~0.0027 vs walking~0.004
BR_SNR_TH = 5.0         # breathing peak/noise-floor SNR -> breathing presence
RSSI_DBM = -30.0        # assumed RSSI when the source carries no metadata
FALL_WIN = 12           # samples of motion history for fall detection
FALL_HI = 0.05          # spike level
FALL_LO = 0.008         # stillness level after the spike
FALL_HOLD = 8.0         # s the FALL ALERT stays latched on screen after a hit
BR_LO_HZ = 0.10         # breathing search band, low  (6 bpm)
BR_HI_HZ = 0.60         # breathing search band, high (36 bpm)
BPM_SMOOTH = 5          # median window on the breathing-rate estimate

# --- presentation / liveness --------------------------------------------------
HISTORY = 180           # feature windows kept so a late browser is not blank
STALE_S = 2.5           # no window for this long -> the page shows NO DATA


def _clamp(x):
    return float(max(0.0, min(1.0, x)))


def _median(vals):
    s = sorted(vals)
    if not s:
        return 0.0
    h = len(s) // 2
    return s[h] if len(s) % 2 else 0.5 * (s[h - 1] + s[h])


def breathing_from_bins(brt, fs):
    """33 DFT magnitude bins -> (bpm, snr, peak bin, band_lo, band_hi, bin_hz).

    bpm is the in-band peak, refined to sub-bin resolution by the usual parabolic
    interpolation when the peak is an interior maximum (at fs=20 Hz / N=64 one bin
    is 18.75 bpm wide, so without it the reading is quantised).  The SNR is the
    peak against the median of the *out-of-band* bins, i.e. a real noise floor -
    an in-band median is meaningless when the band is only a couple of bins.
    """
    n = len(brt)
    nfft = 2 * (n - 1) if n > 1 else 64                     # 64-pt rfft -> 33 bins
    bin_hz = fs / nfft
    if n < 2 or not any(brt):                               # all-zero = branch absent
        return 0.0, 0.0, -1, 1, min(1, n - 1), bin_hz
    lo = max(1, int(math.ceil(BR_LO_HZ / bin_hz)))
    hi = min(n - 1, int(math.floor(BR_HI_HZ / bin_hz)))
    if hi < lo:
        lo = hi = min(1, n - 1)
    pk = max(range(lo, hi + 1), key=lambda i: brt[i])
    pos = float(pk)
    if lo < pk < hi:                                        # sub-bin refinement
        a, b, c = brt[pk - 1], brt[pk], brt[pk + 1]
        den = a - 2.0 * b + c
        if den < 0.0:
            pos += max(-0.5, min(0.5, 0.5 * (a - c) / den))
    floor = [brt[i] for i in range(1, n) if abs(i - pk) > 1]
    med = _median(floor) or _median(brt[1:]) or 1e-9
    return pos * bin_hz * 60.0, brt[pk] / med, pk, lo, hi, bin_hz


class _Rolling:
    """Cross-window presentation state the caller's `hist` list cannot carry:
    breathing-rate smoothing, the fall latch and the window counter.  One
    dashboard process serves one feature stream, so a single instance is enough.
    """
    def __init__(self):
        self.bpm = []
        self.fall_until = 0.0
        self.seq = 0


_ROLL = _Rolling()


def derive_metrics(mot, brt, phs, fs, hist, meta=None):
    """AIE feature groups (+ optional inline metadata) -> dashboard metrics."""
    now = time.time()
    _ROLL.seq += 1
    motion = abs(mot[2]) if len(mot) >= 3 else 0.0          # motion-band power
    phase_var = abs(phs[1]) if len(phs) >= 2 else 0.0       # phase variance
    brt = [abs(float(v)) for v in brt]

    bpm_raw, br_snr, pk, band_lo, band_hi, bin_hz = breathing_from_bins(brt, fs)
    breathing_ok = br_snr > BR_SNR_TH
    _ROLL.bpm.append(bpm_raw)
    del _ROLL.bpm[:-BPM_SMOOTH]
    bpm = _median(_ROLL.bpm) if breathing_ok else 0.0

    present = motion > MOTION_TH or breathing_ok

    hist.append(motion)
    if len(hist) > FALL_WIN:
        hist.pop(0)
    # spike, then stillness: latch the alert so a 1-window event cannot be missed
    if (max(hist) > FALL_HI) and (motion < FALL_LO) and (hist.index(max(hist)) < len(hist) - 2):
        _ROLL.fall_until = now + FALL_HOLD
    fall = now < _ROLL.fall_until

    if fall:
        activity = "FALL - person down"
    elif motion > MOTION_TH:
        activity = "active / walking"
    elif present:
        activity = "still - breathing"
    else:
        activity = "empty"

    # element 7 is (rssi+100)/100: real RSSI when the source carries metadata
    # (inline), the assumed constant otherwise.
    rssi = meta.rssi if meta is not None else RSSI_DBM
    raw8 = [
        PRESENCE_GAIN * (1.0 if present else 0.0),
        MOTION_GAIN * motion,
        bpm,
        0.0,                                          # n/a at CSI frame rate
        phase_var / PHASEVAR_NORM,
        1.0 if present else 0.0,
        1.0 if fall else 0.0,
        rssi,
    ]
    f8 = features8_vector(
        presence_score=raw8[0],
        motion=raw8[1],
        breathing_bpm=raw8[2],
        heartrate_bpm=raw8[3],
        phase_variance=raw8[4],
        person_count=raw8[5],
        fall=fall,
        rssi_dbm=raw8[7],
    )
    out = {
        "t": round(now, 3),
        "seq": _ROLL.seq,
        "presence": bool(present),
        "activity": activity,
        "motion": round(motion, 6),
        "motion_th": MOTION_TH,
        "bpm": round(bpm, 1),
        "bpm_raw": round(bpm_raw, 1),
        "breathing_ok": bool(breathing_ok),
        "br_snr": round(br_snr, 2),
        "phase_var": round(phase_var, 6),
        "fall": bool(fall),
        "fall_left": round(max(0.0, _ROLL.fall_until - now), 1),
        "rssi": rssi,
        "spectrum": [round(x, 4) for x in brt],
        "peak_bin": pk,
        "band": [band_lo, band_hi],
        "bin_hz": round(bin_hz, 5),
        "has_breathing": any(brt),
        "has_phase": any(abs(v) > 0.0 for v in phs),
        "mot": [round(float(v), 6) for v in mot[:3]],
        "phs": [round(float(v), 6) for v in phs[:3]],
        "features8": [round(x, 4) for x in f8],
        "features8_raw": [round(x, 3) for x in raw8],
    }
    if meta is not None:                              # inline metadata, per CSI frame
        out["meta"] = {"seq": meta.seq, "n_sub": meta.n_sub,
                       "chanspec": meta.chanspec, "core_spatial": meta.core_spatial}
    return out


# --- feature sources ----------------------------------------------------------
def _read_floats(path):
    try:
        with open(path) as f:
            return [float(x) for x in f.read().split()]
    except (OSError, ValueError):
        return []


def golden_dir(data_dir):
    """First directory that actually holds golden.txt.

    The committed vectors live in aie/feature_graph/data; the on-target SD stage
    keeps a copy next to the host binary.  Falling back instead of crashing means
    `--source golden` always comes up, which is the whole point of that mode.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    for d in (data_dir,
              os.path.join(here, "..", "aie", "data"),
              os.path.join(here, "..", "aie", "feature_graph", "data"),
              os.path.join(here, "..", "aie", "feature_graph", "sd_stage_3br"),
              here, "."):
        if d and os.path.exists(os.path.join(d, "golden.txt")):
            return d
    return data_dir


def source_golden(data_dir, fs, period, fall_demo=0.0):
    """Replay golden motion/breathing/phase vectors with jitter (offline test).

    fall_demo > 0 drives a motion spike followed by stillness every `fall_demo`
    seconds.  The fall detector itself is untouched - this only shapes the input,
    so the FALL ALERT path can be shown on stage without a volunteer on the floor.
    """
    d = golden_dir(data_dir)
    mot0 = _read_floats(os.path.join(d, "golden.txt"))[:3] or [0, 0, 0.02]
    brt0 = _read_floats(os.path.join(d, "breath_golden.txt"))[:33]
    phs0 = _read_floats(os.path.join(d, "phase_golden.txt"))[:3] or [0, 0.3, 0.3]
    if not any(brt0):                        # keep the spectrum panel meaningful
        brt0 = [4.0 / (1.0 + 3.0 * abs(i - 2)) for i in range(33)]
    brt0 = (brt0 + [0.0] * 33)[:33]
    phase, t0 = 0.0, time.time()
    while True:
        phase += 0.15
        breathe = 0.5 * (1.0 + math.sin(phase))               # fake "live" breathing swell
        j = lambda v, s=0.15: v * (1.0 + random.uniform(-s, s))
        scale = 0.4 + breathe
        if fall_demo > 0:
            ph = (time.time() - t0) % fall_demo
            if ph < 0.6:                                      # impact
                scale = 12.0
            elif ph < 0.45 * fall_demo:                       # motionless on the floor
                scale = 0.004
        mot = [mot0[0], mot0[1], max(0.0, j(mot0[2]) * scale)]
        brt = [max(0.0, j(v)) for v in brt0]
        phs = [phs0[0], j(phs0[1]), j(phs0[2])]
        yield mot, brt, phs
        time.sleep(period)


def _parse_feature_line(line):
    """CSV feature line -> (mot, brt, phs, meta). `meta` is only present when the
    writer appended the inline metadata tail (inline_reader.format_csv)."""
    parts = [p for p in line.replace(",", " ").split() if p]
    try:
        vals = [float(p) for p in parts]
    except ValueError:
        return None
    if len(vals) < 39:
        return None
    meta = None
    if len(vals) >= 39 + len(inline_reader.META_NAMES):
        meta = inline_reader.Meta(*[int(v) for v in vals[39:44]], raw=0)
    return vals[0:3], vals[3:36], vals[36:39], meta


def source_exec(cmd, fs, period, restart=True):
    """Run the on-target XRT host and parse CSV feature lines from its stdout.

    The child is restarted if it dies, so a crashed host stalls the page (which
    then says NO DATA) instead of ending the demo.
    """
    while True:
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, bufsize=1)
        except OSError as exc:
            print("[live_dashboard] cannot start %r: %s" % (cmd, exc), file=sys.stderr)
            proc = None
        if proc is not None:
            try:
                for line in proc.stdout:
                    parsed = _parse_feature_line(line)
                    if parsed:
                        yield parsed
            finally:
                proc.terminate()
        if not restart:
            return
        print("[live_dashboard] feature host exited - restarting", file=sys.stderr)
        time.sleep(max(0.5, period))


def source_fifo(path, fs, period):
    """Read CSV feature lines from a named pipe / file the host writes to."""
    while not os.path.exists(path):
        time.sleep(0.2)
    with open(path) as f:
        while True:
            line = f.readline()
            if not line:
                time.sleep(period)
                continue
            parsed = _parse_feature_line(line)
            if parsed:
                yield parsed


def source_inline(reader, hz, new_only=False):
    """Inline Arch-B: AIE results + CSI metadata straight out of DDR.

    Missing AIE branches (the current inline BD builds the 1-branch graph) come
    back zero-filled, so the dashboard degrades to motion-only rather than
    failing. The metadata rides along and supplies the real RSSI.
    """
    for frame in inline_reader.frames(reader, hz, new_only):
        mot, brt, phs = inline_reader.branch_lists(frame)
        yield mot, brt, phs, frame.meta


# --- SSE web server -----------------------------------------------------------
class Hub:
    """Fan-out of the latest metric to all connected SSE clients.

    Also the liveness bookkeeping: a backlog so a browser that connects (or
    reloads, or reconnects after the server was down) is never blank, plus the
    age of the newest window so the page can say NO DATA instead of quietly
    freezing on a stale chart.
    """
    def __init__(self, source="", fs=20.0, period=0.25):
        self.clients = set()
        self.lock = threading.Lock()
        self.last = None
        self.history = []
        self.count = 0
        self.last_t = 0.0
        self.started = time.time()
        self.source = source
        self.fs = fs
        self.period = period
        self.status = "waiting"          # waiting | live | stalled | down
        self.note = "waiting for the first feature window"

    def set_status(self, status, note=""):
        self.status, self.note = status, note

    def state(self):
        """Liveness snapshot - the client trusts this over its own clock."""
        age = (time.time() - self.last_t) if self.last_t else None
        status = self.status
        if status == "live" and age is not None and age > STALE_S:
            status = "stalled"
        return {"status": status, "note": self.note, "age": None if age is None else round(age, 2),
                "count": self.count, "source": self.source, "fs": self.fs,
                "uptime": round(time.time() - self.started, 1)}

    def publish(self, msg):
        self.last = msg
        self.count += 1
        self.last_t = time.time()
        self.status, self.note = "live", ""
        self.history.append(msg)
        del self.history[:-HISTORY]
        with self.lock:
            dead = []
            for q in self.clients:
                try:
                    q.put_nowait(msg)
                except queue.Full:
                    dead.append(q)
            for q in dead:
                self.clients.discard(q)

    def subscribe(self):
        q = queue.Queue(maxsize=8)
        with self.lock:
            self.clients.add(q)
        return q                       # the backlog goes out as the "init" event

    def unsubscribe(self, q):
        with self.lock:
            self.clients.discard(q)


def _slim(msg):
    """Backlog copy without the 33-bin spectrum (only the newest one is drawn)."""
    d = dict(msg)
    d.pop("spectrum", None)
    return d


def make_handler(hub, html):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, body, ctype):
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            try:
                self._route()
            except (BrokenPipeError, ConnectionResetError):
                pass                      # browser tab closed mid-response

        def _route(self):
            if self.path in ("/", "/index.html"):
                self._send(html.encode(), "text/html; charset=utf-8")
            elif self.path.startswith("/api/state"):
                st = hub.state()
                st["last"] = hub.last
                self._send(json.dumps(st).encode(), "application/json")
            elif self.path.startswith("/healthz"):
                st = hub.state()
                line = "status=%s age=%s count=%d source=%s note=%s\n" % (
                    st["status"], st["age"], st["count"], st["source"], st["note"] or "-")
                self._send(line.encode(), "text/plain; charset=utf-8")
            elif self.path == "/stream":
                self._stream()
            else:
                self.send_error(404)

        def _write_event(self, name, payload):
            head = ("event: %s\n" % name) if name else ""
            self.wfile.write((head + "data: " + json.dumps(payload) + "\n\n").encode())
            self.wfile.flush()

        def _stream(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("X-Accel-Buffering", "no")
            self.end_headers()
            q = hub.subscribe()
            try:
                self.wfile.write(b"retry: 1500\n\n")      # fast browser reconnect
                hist = list(hub.history)
                self._write_event("init", {
                    "state": hub.state(),
                    "cfg": {"source": hub.source, "fs": hub.fs, "period": hub.period,
                            "stale": STALE_S, "history": HISTORY, "motion_th": MOTION_TH,
                            "br_snr_th": BR_SNR_TH, "fall_hold": FALL_HOLD},
                    "history": [_slim(m) for m in hist[:-1]] + hist[-1:],
                })
                while True:
                    try:
                        msg = q.get(timeout=1.0)
                    except queue.Empty:
                        # heartbeat: keeps the socket warm AND tells the page how
                        # old the newest window is, so a dead source is visible.
                        self._write_event("hb", hub.state())
                        continue
                    self._write_event("", msg)
            except (BrokenPipeError, ConnectionResetError, OSError, ValueError):
                pass
            finally:
                hub.unsubscribe(q)
    return H


HTML = """<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>VCK190 WiFi-CSI HAR - live</title>
<style>
:root{--bg:#0b0e14;--panel:#12161d;--line:#232a36;--ink:#fff;--ink2:#c8d0dc;--mut:#8b93a1;
 --blue:#3987e5;--aqua:#199e70;--orange:#d95926;--good:#0ca30c;--warn:#fab219;--crit:#d03b3b}
*{box-sizing:border-box}
[hidden]{display:none!important}
body{margin:0;background:var(--bg);color:var(--ink);font-size:16px;
 font-family:ui-sans-serif,system-ui,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased}
header{display:flex;align-items:center;justify-content:space-between;gap:16px;
 padding:12px 22px;background:var(--panel);border-bottom:1px solid var(--line)}
h1{margin:0;font-size:clamp(17px,1.7vw,26px);font-weight:650}
.sub{color:var(--mut);font-size:clamp(12px,1vw,15px);margin-top:3px}
.live{display:flex;align-items:center;gap:14px;text-align:right}
.pill{font-size:clamp(13px,1.1vw,17px);font-weight:700;letter-spacing:.08em;padding:6px 14px;
 border-radius:999px;border:2px solid;white-space:nowrap}
.pill.good{color:var(--good);border-color:var(--good)}
.pill.warn{color:var(--warn);border-color:var(--warn)}
.pill.crit{color:#fff;background:var(--crit);border-color:var(--crit)}
.meta{color:var(--mut);font-size:clamp(11px,.95vw,14px);font-family:ui-monospace,Menlo,Consolas,monospace}
.banner,.alert{display:flex;align-items:center;gap:14px;padding:10px 22px;font-weight:700;
 letter-spacing:.06em;font-size:clamp(15px,1.5vw,22px)}
.banner{background:#3a2c07;color:#ffd98a;border-bottom:1px solid #6b520f}
.banner.crit{background:#3a0f0f;color:#ffc9c9;border-bottom-color:#7a2020}
.alert{background:var(--crit);color:#fff;font-size:clamp(20px,2.6vw,40px);letter-spacing:.1em}
.alert .ico{font-size:1.15em;line-height:1}
.alert .as{font-weight:500;letter-spacing:.02em;opacity:.92;font-size:.5em;margin-left:auto}
@media (prefers-reduced-motion:no-preference){.alert{animation:pulse 1.1s steps(1) infinite}}
@keyframes pulse{50%{background:#8f1f1f}}
main{padding:16px 22px 22px;display:flex;flex-direction:column;gap:16px}
.tiles{display:grid;grid-template-columns:repeat(4,1fr);gap:16px}
.tile{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 18px}
.tile .k{font-size:clamp(11px,1vw,15px);text-transform:uppercase;letter-spacing:.12em;color:var(--mut);font-weight:600}
.tile .v{font-size:clamp(26px,3.4vw,54px);font-weight:700;line-height:1.12;margin-top:6px;
 white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tile .v.sm{font-size:clamp(19px,2.3vw,36px)}
.tile .u{font-size:.42em;color:var(--mut);font-weight:600;margin-left:.3em}
.tile .s{margin-top:4px;color:var(--mut);font-size:clamp(11px,.95vw,14px);
 font-family:ui-monospace,Menlo,Consolas,monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#falltile.on{background:var(--crit);border-color:#ff9e9e}
#falltile.on .k,#falltile.on .s{color:#ffe3e3}
#falltile.on .v{color:#fff}
.ok{color:var(--good)}.no{color:var(--mut)}
.row2{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.row3{display:grid;grid-template-columns:3fr 2fr;gap:16px}
.panel{margin:0;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:12px 14px 10px}
figcaption,.phead{display:flex;align-items:baseline;gap:10px;padding-bottom:6px;
 font-size:clamp(14px,1.25vw,19px);font-weight:650}
.sub2{font-weight:400;color:var(--mut);font-size:.78em}
.nw{white-space:nowrap}
figcaption b,.phead b{margin-left:auto;font-family:ui-monospace,Menlo,Consolas,monospace;font-weight:700}
.cwrap{position:relative;height:22vh;min-height:150px}
.cwrap.tall{height:30vh;min-height:200px}
canvas{position:absolute;inset:0;width:100%;height:100%}
table{width:100%;border-collapse:collapse;font-size:clamp(12px,1.05vw,16px)}
td{padding:3px 6px;border-top:1px solid var(--line)}
tr:first-child td{border-top:0}
td.i{color:var(--mut);font-family:ui-monospace,Menlo,Consolas,monospace;width:1.4em}
td.l{white-space:nowrap;font-weight:600}
td.n{color:var(--mut);font-size:.84em;white-space:nowrap;font-family:ui-monospace,Menlo,Consolas,monospace}
td.b{width:32%}
td.v{text-align:right;font-family:ui-monospace,Menlo,Consolas,monospace;font-weight:700;width:5.2em}
.bar{height:12px;border-radius:3px;background:#1d2530;overflow:hidden}
.bar i{display:block;height:100%;border-radius:3px;background:var(--blue);width:0}
tr.on .bar i{background:var(--crit)}
tr.on td.v{color:#ff9c9c}
.aie{margin-top:10px;padding-top:8px;border-top:1px solid var(--line);color:var(--mut);
 font-family:ui-monospace,Menlo,Consolas,monospace;font-size:clamp(11px,.95vw,14px);line-height:1.7}
.aie b{color:var(--ink2);font-weight:600}
body.stale .tiles,body.stale .row2,body.stale .row3{opacity:.45;filter:saturate(.3)}
</style></head><body>
<header>
 <div>
  <h1>VCK190 &middot; WiFi-CSI Human Activity Recognition</h1>
  <div class=sub>AI Engine DSP (motion FIR&rarr;stats &middot; breathing DFT &middot; phase stats) &rarr; ruview 8-feature vector &rarr; tiny MLP</div>
 </div>
 <div class=live><span id=pill class="pill warn">CONNECTING</span><span id=meta class=meta></span></div>
</header>
<div id=alert class=alert hidden><span class=ico>&#9888;</span><span>FALL ALERT</span><span id=alertsub class=as></span></div>
<div id=banner class=banner hidden></div>
<main>
 <section class=tiles>
  <div class=tile><div class=k>Presence</div><div class=v id=presence>&mdash;</div><div class=s id=presence_s>&nbsp;</div></div>
  <div class=tile><div class=k>Activity</div><div class="v sm" id=activity>&mdash;</div><div class=s id=activity_s>&nbsp;</div></div>
  <div class=tile><div class=k>Breathing rate</div><div class=v><span id=bpm>&mdash;</span><span class=u>bpm</span></div><div class=s id=bpm_s>&nbsp;</div></div>
  <div class=tile id=falltile><div class=k>Fall</div><div class=v id=fall>&mdash;</div><div class=s id=fall_s>&nbsp;</div></div>
 </section>
 <section class=row2>
  <figure class=panel>
   <figcaption>Motion power<span class=sub2>mot[2] &middot; FIR band-pass &rarr; stats</span><b id=v_motion>&mdash;</b></figcaption>
   <div class=cwrap><canvas id=cMotion></canvas></div>
  </figure>
  <figure class=panel>
   <figcaption>Breathing rate<span class=sub2>DFT peak, 5-window median</span><b id=v_bpm>&mdash;</b></figcaption>
   <div class=cwrap><canvas id=cBpm></canvas></div>
  </figure>
 </section>
 <section class=row3>
  <figure class=panel>
   <figcaption>Breathing spectrum<span class=sub2 id=specsub>33 windowed-DFT magnitude bins</span><b id=v_peak>&mdash;</b></figcaption>
   <div class="cwrap tall"><canvas id=cSpec></canvas></div>
  </figure>
  <section class=panel>
   <div class=phead><span class=nw>ruview 8-feature vector</span><span class=sub2>magic 0xC5110003 &middot; input to the 9,280-parameter MLP</span></div>
   <table id=f8tab></table>
   <div class=aie id=aieline>&nbsp;</div>
  </section>
 </section>
</main>
<script>
var C={panel:'#12161d',grid:'#232a36',ink:'#e9eef6',mut:'#8b93a1',dim:'#39445a',
       blue:'#3987e5',aqua:'#199e70',orange:'#d95926'};
var MONO='ui-monospace,Menlo,Consolas,monospace';
function $(id){return document.getElementById(id);}
function fmt(v){
 var a=Math.abs(v);
 if(a===0)return '0';
 if(a>=1000||a<0.01)return v.toExponential(1);
 if(a>=100)return v.toFixed(0);
 if(a>=10)return v.toFixed(1);
 if(a>=1)return v.toFixed(2);
 return v.toFixed(3);
}

class Base{
 constructor(id){this.cv=$(id);this.ctx=this.cv.getContext('2d');this.stale=false;this.fit();
  var self=this;
  if(window.ResizeObserver)new ResizeObserver(function(){self.fit();self.draw();}).observe(this.cv);
  else window.addEventListener('resize',function(){self.fit();self.draw();});}
 fit(){var r=this.cv.getBoundingClientRect(),d=window.devicePixelRatio||1;
  this.w=Math.max(60,r.width||320);this.h=Math.max(50,r.height||160);
  this.cv.width=Math.round(this.w*d);this.cv.height=Math.round(this.h*d);
  this.ctx.setTransform(d,0,0,d,0,0);}
 begin(){var x=this.ctx;x.clearRect(0,0,this.w,this.h);x.globalAlpha=this.stale?0.3:1;}
 end(){var x=this.ctx;x.globalAlpha=1;
  if(this.stale){x.fillStyle=C.mut;x.font='700 16px '+MONO;x.textAlign='center';x.textBaseline='middle';
   x.fillText('NO DATA',this.w/2,this.h/2);}}
}

class TS extends Base{
 constructor(id,o){super(id);
  this.o=Object.assign({n:180,color:C.blue,min:null,max:null,ref:null,refLabel:'',fmt:fmt},o);
  this.d=[];this.hs=null;}
 clear(){this.d=[];this.hs=null;}
 push(v){this.d.push((v==null||!isFinite(v))?null:v);if(this.d.length>this.o.n)this.d.shift();}
 draw(){
  var o=this.o,x=this.ctx,W=this.w,H=this.h,PL=64,PR=16,PT=12,PB=22,i,g,p,s;
  this.begin();
  var iw=W-PL-PR,ih=H-PT-PB;
  if(iw<20||ih<20){this.end();return;}
  var vals=this.d.filter(function(v){return v!=null;});
  var lo=(o.min!=null)?o.min:(vals.length?Math.min.apply(null,vals):0);
  var hi=(o.max!=null)?o.max:(vals.length?Math.max.apply(null,vals):1);
  if(o.min==null)lo=Math.min(lo,0);
  if(o.max==null){
   if(o.ref!=null)hi=Math.max(hi,o.ref*1.8);
   hi=hi+(hi-lo)*0.15;
   this.hs=(this.hs==null)?hi:Math.max(hi,this.hs*0.92+hi*0.08);
   hi=this.hs;}
  if(!(hi>lo))hi=lo+1;
  var X=function(k){return PL+(o.n<2?0:(k*iw)/(o.n-1));};
  var Y=function(v){return PT+ih-((v-lo)/(hi-lo))*ih;};
  x.lineWidth=1;x.font='12px '+MONO;x.textAlign='right';x.textBaseline='middle';
  for(g=0;g<=3;g++){var gv=lo+(hi-lo)*g/3,gy=Math.round(Y(gv))+0.5;
   x.strokeStyle=C.grid;x.beginPath();x.moveTo(PL,gy);x.lineTo(W-PR,gy);x.stroke();
   x.fillStyle=C.mut;x.fillText(o.fmt(gv),PL-8,gy);}
  if(o.ref!=null&&o.ref>lo&&o.ref<hi){var ry=Math.round(Y(o.ref))+0.5;
   x.save();x.setLineDash([5,4]);x.strokeStyle='#606b7d';x.beginPath();
   x.moveTo(PL,ry);x.lineTo(W-PR,ry);x.stroke();x.restore();
   x.textAlign='left';x.textBaseline='bottom';x.fillStyle=C.mut;x.fillText(o.refLabel,PL+6,ry-3);}
  var off=o.n-this.d.length,segs=[],cur=[];
  for(i=0;i<this.d.length;i++){var v=this.d[i];
   if(v==null){if(cur.length)segs.push(cur);cur=[];}
   else cur.push([X(i+off),Y(Math.max(lo,Math.min(hi,v)))]);}
  if(cur.length)segs.push(cur);
  var grad=x.createLinearGradient(0,PT,0,PT+ih);
  grad.addColorStop(0,o.color+'59');grad.addColorStop(1,o.color+'00');
  for(s=0;s<segs.length;s++){var sg=segs[s];
   if(sg.length>1){x.beginPath();x.moveTo(sg[0][0],PT+ih);
    for(i=0;i<sg.length;i++)x.lineTo(sg[i][0],sg[i][1]);
    x.lineTo(sg[sg.length-1][0],PT+ih);x.closePath();x.fillStyle=grad;x.fill();}
   x.beginPath();
   for(i=0;i<sg.length;i++){if(i)x.lineTo(sg[i][0],sg[i][1]);else x.moveTo(sg[i][0],sg[i][1]);}
   x.strokeStyle=o.color;x.lineWidth=2.5;x.lineJoin='round';x.lineCap='round';x.stroke();}
  var lastSeg=segs[segs.length-1];
  if(lastSeg&&lastSeg.length){p=lastSeg[lastSeg.length-1];
   x.beginPath();x.arc(p[0],p[1],4.5,0,6.2832);x.fillStyle=o.color;x.fill();
   x.lineWidth=2;x.strokeStyle=C.panel;x.stroke();}
  x.font='12px '+MONO;x.fillStyle=C.mut;x.textBaseline='top';
  x.textAlign='left';x.fillText('-'+o.n+' windows',PL,PT+ih+5);
  x.textAlign='right';x.fillText('now',W-PR,PT+ih+5);
  this.end();}
}

class Bars extends Base{
 constructor(id){super(id);this.v=[];this.pk=-1;this.band=[1,1];this.binHz=0.3125;this.hs=null;}
 set(v,pk,band,binHz){this.v=v||[];this.pk=(pk==null?-1:pk);
  this.band=band||[1,1];this.binHz=binHz||0.3125;}
 draw(){
  var x=this.ctx,W=this.w,H=this.h,PL=64,PR=16,PT=14,PB=32,i;
  this.begin();
  var n=this.v.length||33,iw=W-PL-PR,ih=H-PT-PB;
  if(iw<20||ih<20){this.end();return;}
  var hi=0;
  for(i=0;i<this.v.length;i++)if(this.v[i]>hi)hi=this.v[i];
  if(!(hi>0))hi=1;
  this.hs=(this.hs==null)?hi:Math.max(hi,this.hs*0.9+hi*0.1);
  var top=this.hs*1.15,bw=iw/n,gap=Math.min(3,bw*0.3);
  var b0=Math.max(0,this.band[0]),b1=Math.min(n-1,this.band[1]);
  if(b1>=b0){
   x.fillStyle='#161d2a';x.fillRect(PL+b0*bw,PT,(b1-b0+1)*bw,ih);
   x.save();x.setLineDash([4,4]);x.strokeStyle='#33405a';x.lineWidth=1;
   x.beginPath();x.moveTo(Math.round(PL+b0*bw)+0.5,PT);x.lineTo(Math.round(PL+b0*bw)+0.5,PT+ih);
   x.moveTo(Math.round(PL+(b1+1)*bw)+0.5,PT);x.lineTo(Math.round(PL+(b1+1)*bw)+0.5,PT+ih);
   x.stroke();x.restore();}
  x.font='12px '+MONO;x.textAlign='right';x.textBaseline='middle';x.lineWidth=1;
  for(i=0;i<=2;i++){var gv=top*i/2,gy=Math.round(PT+ih-(gv/top)*ih)+0.5;
   x.strokeStyle=C.grid;x.beginPath();x.moveTo(PL,gy);x.lineTo(W-PR,gy);x.stroke();
   x.fillStyle=C.mut;x.fillText(fmt(gv),PL-8,gy);}
  for(i=0;i<n;i++){
   var v=Math.max(0,this.v[i]||0),bh=Math.max(1,(v/top)*ih),inb=(i>=b0&&i<=b1);
   x.fillStyle=(i===this.pk)?C.orange:(inb?C.blue:C.dim);
   var bx=PL+i*bw+gap/2,by=PT+ih-bh,bwid=Math.max(1,bw-gap);
   x.beginPath();
   if(x.roundRect)x.roundRect(bx,by,bwid,bh,[4,4,0,0]);else x.rect(bx,by,bwid,bh);
   x.fill();}
  if(this.pk>=0&&this.pk<n){
   var pv=Math.max(0,this.v[this.pk]||0),px=PL+this.pk*bw+bw/2,py=PT+ih-(pv/top)*ih;
   var right=(px>W*0.7),lab='in-band peak '+(this.pk*this.binHz*60).toFixed(1)+' bpm';
   x.font='700 13px '+MONO;
   var lw=x.measureText(lab).width,lx=right?(px-9-lw):(px+9),ly=Math.max(PT+13,py-6);
   x.fillStyle='rgba(18,22,29,.88)';                     // chip so it never collides
   if(x.roundRect){x.beginPath();x.roundRect(lx-5,ly-14,lw+10,18,4);x.fill();}
   else x.fillRect(lx-5,ly-14,lw+10,18);
   x.fillStyle=C.ink;x.textBaseline='alphabetic';x.textAlign='left';x.fillText(lab,lx,ly);}
  x.font='11px '+MONO;x.fillStyle=C.mut;x.textBaseline='top';x.textAlign='center';
  for(i=0;i<n;i+=4)x.fillText(String(i),PL+i*bw+bw/2,PT+ih+6);
  x.textAlign='left';x.fillText('DFT bin',PL,PT+ih+20);
  x.textAlign='right';x.fillText('shaded = breathing band',W-PR,PT+ih+20);
  this.end();}
}

var F8=[['presence','presence/10'],['motion','30*power/10'],['breathing','bpm/30'],
        ['heart rate','bpm/120'],['phase var','var/3'],['persons','count/4'],
        ['fall','0 or 1'],['rssi','(dBm+100)/100']];
var RAWU=['','','bpm','bpm','','','','dBm'];
var tab=$('f8tab');
(function(){for(var i=0;i<8;i++){
 var tr=document.createElement('tr');
 tr.innerHTML='<td class=i>'+i+'</td><td class=l>'+F8[i][0]+'</td><td class=n>'+F8[i][1]+
  '</td><td class=b><div class=bar><i></i></div></td><td class=v>&mdash;</td>';
 tab.appendChild(tr);}})();

var tsM=new TS('cMotion',{color:C.blue,min:0,ref:null,refLabel:'presence threshold'});
var tsB=new TS('cBpm',{color:C.aqua,min:0,max:30,fmt:function(v){return v.toFixed(0);}});
var spec=new Bars('cSpec');

var cfg={source:'?',fs:20,stale:2.5,motion_th:0.005,history:180};
var connected=false,latest=null,lastRx=0,srv=null,rate=0,rxt=[];

function setF8(d){
 var v=d.features8||[],r=d.features8_raw||[],i;
 for(i=0;i<8;i++){
  var tr=tab.rows[i];if(!tr)continue;
  var val=(v[i]==null)?0:v[i];
  var raw=(r[i]==null)?null:r[i];
  tr.cells[2].textContent=F8[i][1]+(raw==null?'':'  <- '+raw.toFixed(i===7?0:2)+(RAWU[i]?' '+RAWU[i]:''));
  tr.cells[3].firstChild.firstChild.style.width=Math.max(0,Math.min(100,val*100))+'%';
  tr.cells[4].textContent=val.toFixed(4);
  if(i===6&&val>0.5)tr.className='on';else tr.className='';}
}

function setAie(d){
 var m=d.mot||[0,0,0],p=d.phs||[0,0,0],v=d.features8||[];
 $('aieline').innerHTML=
  '<b>f8</b> ['+v.map(function(z){return z.toFixed(2);}).join(' ')+']'+
  '<br><b>mot[3]</b> mean '+fmt(m[0])+'  var '+fmt(m[1])+'  power '+fmt(m[2])+
  '<br><b>phs[3]</b> mean '+fmt(p[0])+'  var '+fmt(p[1])+'  power '+fmt(p[2])+
  (d.has_phase?'':'  (branch idle)')+
  '<br><b>brt[33]</b> peak bin '+d.peak_bin+'  SNR '+(d.br_snr==null?'-':d.br_snr.toFixed(1))+
  '  bin width '+((d.bin_hz||0)*60).toFixed(1)+' bpm'+(d.has_breathing?'':'  (branch idle)')+
  (d.meta?('<br><b>CSI</b> seq '+d.meta.seq+'  '+d.meta.n_sub+' subcarriers  rssi '+d.rssi+' dBm'):'');
}

function apply(d,replay){
 if(!d)return;
 if(!replay){lastRx=Date.now();rxt.push(lastRx);if(rxt.length>16)rxt.shift();
  if(rxt.length>2)rate=(rxt.length-1)/((rxt[rxt.length-1]-rxt[0])/1000);}
 tsM.push(d.motion);
 tsB.push(d.breathing_ok?d.bpm:null);
 if(d.spectrum)spec.set(d.spectrum,d.peak_bin,d.band,d.bin_hz);
 latest=d;
}

function render(){
 var age=lastRx?(Date.now()-lastRx)/1000:null;
 var stale=(!connected)||(age==null)||(age>(cfg.stale||2.5));
 document.body.classList.toggle('stale',stale);
 var pill=$('pill'),ban=$('banner'),note=(srv&&srv.note)?srv.note:'';
 if(!connected){
  pill.textContent='OFFLINE';pill.className='pill crit';
  ban.hidden=false;ban.className='banner crit';
  ban.textContent='DISCONNECTED - cannot reach the dashboard server. Reconnecting automatically...';
 }else if(age==null){
  pill.textContent='WAITING';pill.className='pill warn';
  ban.hidden=false;ban.className='banner';
  ban.textContent='WAITING FOR DATA - '+(note||'no feature window received yet');
 }else if(stale){
  pill.textContent='NO DATA';pill.className='pill warn';
  ban.hidden=false;ban.className='banner';
  ban.textContent='NO DATA - last feature window '+age.toFixed(1)+' s ago'+(note?' ('+note+')':'')+
   ' - the display resumes by itself when the source comes back';
 }else{pill.textContent='LIVE';pill.className='pill good';ban.hidden=true;}
 var m='source '+(cfg.source||'?')+'   fs '+(cfg.fs||0)+' Hz   windows '+((srv&&srv.count)||0);
 if(rate>0)m+='   '+rate.toFixed(1)+'/s';
 if(age!=null)m+='   age '+age.toFixed(1)+' s';
 $('meta').textContent=m;
 var d=latest;
 if(d){
  var falling=!!d.fall&&!stale;
  $('presence').textContent=d.presence?'PRESENT':'EMPTY';
  $('presence').className='v '+(d.presence?'ok':'no');
  $('presence_s').textContent='motion '+d.motion.toExponential(2)+'  threshold '+
   (cfg.motion_th||0).toExponential(0);
  $('activity').textContent=(d.activity||'-').toUpperCase();
  $('activity_s').textContent='phase var '+(d.phase_var||0).toFixed(4)+(d.has_phase?'':'  (branch idle)');
  $('bpm').textContent=d.breathing_ok?d.bpm.toFixed(1):'--';
  $('bpm_s').textContent=d.has_breathing
   ?('peak bin '+d.peak_bin+'  SNR '+(d.br_snr||0).toFixed(1)+(d.breathing_ok?'':'  below threshold'))
   :'breathing branch idle';
  $('fall').textContent=falling?'FALL':'NO FALL';
  $('fall').className=falling?'v':'v ok';
  $('fall_s').textContent=falling?('clears in '+d.fall_left+' s'):'watching for spike then stillness';
  if(falling)$('falltile').className='tile on';else $('falltile').className='tile';
  $('v_motion').textContent=d.motion.toExponential(3);
  $('v_bpm').textContent=d.breathing_ok?(d.bpm.toFixed(1)+' bpm'):'--';
  $('v_peak').textContent=d.has_breathing?((d.peak_bin*(d.bin_hz||0)*60).toFixed(1)+' bpm'):'--';
  $('specsub').textContent='33 bins, '+((d.bin_hz||0)*60).toFixed(1)+' bpm per bin';
  setF8(d);setAie(d);
  $('alert').hidden=!falling;
  if(falling)$('alertsub').textContent='motion spike then stillness - clears in '+d.fall_left+' s';
 }else{$('alert').hidden=true;}
 tsM.stale=stale;tsB.stale=stale;spec.stale=stale;
 tsM.draw();tsB.draw();spec.draw();
}

var es=new EventSource('/stream');
es.onopen=function(){connected=true;render();};
es.onerror=function(){connected=false;render();};
es.addEventListener('init',function(e){
 var d=JSON.parse(e.data);
 if(d.cfg){for(var k in d.cfg)cfg[k]=d.cfg[k];}
 tsM.o.n=cfg.history||180;tsB.o.n=tsM.o.n;
 tsM.o.ref=cfg.motion_th;
 tsM.clear();tsB.clear();rxt=[];rate=0;latest=null;
 var h=d.history||[];
 for(var i=0;i<h.length;i++)apply(h[i],true);
 srv=d.state||null;
 lastRx=(srv&&srv.age!=null)?(Date.now()-srv.age*1000):0;
 connected=true;render();});
es.addEventListener('hb',function(e){srv=JSON.parse(e.data);connected=true;render();});
es.onmessage=function(e){apply(JSON.parse(e.data),false);render();};
setInterval(render,200);
render();
</script></body></html>"""


def _urls(port):
    """Reachable URLs to read out at the demo (the board's DHCP address)."""
    import socket
    out = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            url = "http://%s:%d/" % (ip, port)
            if not ip.startswith("127.") and url not in out:
                out.append(url)
    except OSError:
        pass
    return out


def main():
    ap = argparse.ArgumentParser(description="VCK190 WiFi-CSI HAR live dashboard")
    ap.add_argument("--source", choices=["golden", "exec", "fifo", "inline"], default="golden")
    ap.add_argument("--data", default=os.path.join(os.path.dirname(__file__), "..", "aie", "data"),
                    help="golden vectors dir (for --source golden)")
    ap.add_argument("--host", nargs="+", default=["./host_3br", "--stream"],
                    help="command for --source exec")
    ap.add_argument("--fifo", default="/tmp/aie_features.csv", help="path for --source fifo")
    ap.add_argument("--fs", type=float, default=20.0, help="CSI frame rate [Hz]")
    ap.add_argument("--period", type=float, default=0.25, help="golden replay period [s]")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--fall-demo", type=float, default=0.0, metavar="SEC",
                    help="golden: drive a spike-then-stillness pattern every SEC seconds "
                         "so the (unmodified) fall detector fires - proves the alert path")
    # --- --source inline (see inline_reader.py for the address map) -----------
    ap.add_argument("--simulate", action="store_true",
                    help="inline: fabricate data instead of reading /dev/mem (no board)")
    ap.add_argument("--inline-hz", type=float, default=10.0, help="inline: DDR poll rate")
    ap.add_argument("--branches", type=int, default=None,
                    help="inline: AIE branches present, 1 or 3 "
                         "(default 1 on hardware, 3 with --simulate)")
    ap.add_argument("--meta-buf", type=lambda s: int(s, 0),
                    default=inline_reader.DEFAULT_META_PA, help="inline: metadata phys addr")
    ap.add_argument("--results-buf", type=lambda s: int(s, 0),
                    default=inline_reader.DEFAULT_RESULTS_PA, help="inline: AIE result phys addr")
    ap.add_argument("--arm", action="store_true",
                    help="inline: program and free-run the AIE result s2mm on startup")
    ap.add_argument("--new-only", action="store_true",
                    help="inline: only publish when the metadata sequence advances")
    args = ap.parse_args()

    tag = args.source + (" (simulated)" if args.source == "inline" and args.simulate else "")
    hub = Hub(source=tag, fs=args.fs, period=args.period)

    if args.source == "golden":
        src = source_golden(args.data, args.fs, args.period, args.fall_demo)
    elif args.source == "exec":
        src = source_exec(args.host, args.fs, args.period)
    elif args.source == "inline":
        reader = inline_reader.make_reader(
            simulate=args.simulate, branches=args.branches, meta_pa=args.meta_buf,
            results_pa=args.results_buf, arm=args.arm, fs=args.fs)
        src = source_inline(reader, args.inline_hz, args.new_only)
    else:
        src = source_fifo(args.fifo, args.fs, args.period)

    def pump():
        # Nothing in here may kill the thread quietly: the page must be able to
        # say WHY it went dark, and the web server must keep serving either way.
        hist = []
        try:
            for item in src:
                mot, brt, phs = item[:3]                   # sources may append metadata
                meta = item[3] if len(item) > 3 else None
                try:
                    hub.publish(derive_metrics(mot, brt, phs, args.fs, hist, meta))
                except Exception as exc:                   # one bad window, keep going
                    hub.set_status("live", "bad feature window: %s" % exc)
                    print("[live_dashboard] bad window: %r" % (exc,), file=sys.stderr)
        except Exception as exc:
            hub.set_status("down", "%s source failed: %s" % (args.source, exc))
            print("[live_dashboard] source failed: %r" % (exc,), file=sys.stderr)
        else:
            hub.set_status("down", "%s source ended" % args.source)
        print("[live_dashboard] feature source stopped - page shows NO DATA", file=sys.stderr)

    threading.Thread(target=pump, daemon=True).start()

    srv = ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(hub, HTML))
    print(f"[live_dashboard] source={tag}  http://0.0.0.0:{args.port}/  (Ctrl-C to stop)", flush=True)
    for url in _urls(args.port):
        print(f"[live_dashboard]   {url}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
