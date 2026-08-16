#!/usr/bin/env python3
"""live_dashboard.py - WiFi-CSI Human-Activity-Recognition live dashboard (VCK190).

Consumes the AI-Engine feature-extraction outputs and serves a live web
dashboard (Server-Sent Events + Chart.js) viewable from any browser on the
network - no desktop/VNC needed on the target.

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

# --- calibratable thresholds (mirror work/csi_ref/har.py + features8.py) ------
MOTION_TH = 5e-3        # motion-band power -> presence/activity
BR_SNR_TH = 5.0         # breathing peak/median SNR -> breathing presence
MOTION_GAIN = 30.0      # DSP motion power -> ruview 0-10 scale
PHASEVAR_NORM = 3.0
RSSI_DBM = -30.0
FALL_WIN = 12           # samples of motion history for fall detection
FALL_HI = 0.05          # spike level
FALL_LO = 0.008         # stillness level after the spike


def _clamp(x):
    return float(max(0.0, min(1.0, x)))


def derive_metrics(mot, brt, phs, fs, hist):
    """AIE feature groups -> dashboard metrics + ruview 8-feature vector."""
    motion = abs(mot[2]) if len(mot) >= 3 else 0.0          # motion-band power
    phase_var = abs(phs[1]) if len(phs) >= 2 else 0.0       # phase variance

    n = len(brt)                                            # 33 bins
    nfft = 2 * (n - 1) if n > 1 else 64                     # 64-pt rfft
    band = [i for i in range(n) if 0.1 <= i * fs / nfft <= 0.6]
    if band:
        pk = max(band, key=lambda i: brt[i])
        bpm = (pk * fs / nfft) * 60.0
        ordered = sorted(brt[i] for i in band)
        med = ordered[len(ordered) // 2] or 1e-9
        br_snr = brt[pk] / med
    else:
        bpm, br_snr = 0.0, 0.0

    present = motion > MOTION_TH or br_snr > BR_SNR_TH
    if motion > MOTION_TH:
        activity = "active / walking"
    elif present:
        activity = "stationary - breathing"
    else:
        activity = "empty"

    hist.append(motion)
    if len(hist) > FALL_WIN:
        hist.pop(0)
    fall = (max(hist) > FALL_HI) and (motion < FALL_LO) and (hist.index(max(hist)) < len(hist) - 2)

    f8 = [
        _clamp((10.0 if present else 0.0) / 10.0),   # presence/10
        _clamp(MOTION_GAIN * motion / 10.0),          # motion/10
        _clamp(bpm / 30.0),                           # bpm/30
        0.0,                                          # hr/120 (n/a at CSI rate)
        _clamp(phase_var / PHASEVAR_NORM),            # phase-var
        _clamp((1.0 if present else 0.0) / 4.0),      # persons/4
        1.0 if fall else 0.0,                         # fall
        _clamp((RSSI_DBM + 100.0) / 100.0),           # (rssi+100)/100
    ]
    return {
        "t": round(time.time(), 3),
        "presence": bool(present),
        "activity": activity,
        "motion": round(motion, 6),
        "bpm": round(bpm, 1),
        "br_snr": round(br_snr, 2),
        "phase_var": round(phase_var, 6),
        "fall": bool(fall),
        "spectrum": [round(x, 4) for x in brt],
        "features8": [round(x, 4) for x in f8],
    }


# --- feature sources ----------------------------------------------------------
def _read_floats(path):
    with open(path) as f:
        return [float(x) for x in f.read().split()]


def source_golden(data_dir, fs, period):
    """Replay golden motion/breathing/phase vectors with jitter (offline test)."""
    mot0 = _read_floats(os.path.join(data_dir, "golden.txt"))[:3] or [0, 0, 0.02]
    brt0 = _read_floats(os.path.join(data_dir, "breath_golden.txt"))[:33]
    phs0 = _read_floats(os.path.join(data_dir, "phase_golden.txt"))[:3] or [0, 0.3, 0.3]
    brt0 = (brt0 + [0.0] * 33)[:33]
    phase = 0.0
    while True:
        phase += 0.15
        breathe = 0.5 * (1.0 + math.sin(phase))               # fake "live" breathing swell
        j = lambda v, s=0.15: v * (1.0 + random.uniform(-s, s))
        mot = [mot0[0], mot0[1], max(0.0, j(mot0[2]) * (0.4 + breathe))]
        brt = [max(0.0, j(v)) for v in brt0]
        phs = [phs0[0], j(phs0[1]), j(phs0[2])]
        yield mot, brt, phs
        time.sleep(period)


def _parse_feature_line(line):
    parts = [p for p in line.replace(",", " ").split() if p]
    try:
        vals = [float(p) for p in parts]
    except ValueError:
        return None
    if len(vals) < 39:
        return None
    return vals[0:3], vals[3:36], vals[36:39]


def source_exec(cmd, fs, period):
    """Run the on-target XRT host and parse CSV feature lines from its stdout."""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, bufsize=1)
    try:
        for line in proc.stdout:
            parsed = _parse_feature_line(line)
            if parsed:
                yield parsed
    finally:
        proc.terminate()


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


# --- SSE web server -----------------------------------------------------------
class Hub:
    """Fan-out of the latest metric to all connected SSE clients."""
    def __init__(self):
        self.clients = set()
        self.lock = threading.Lock()
        self.last = None

    def publish(self, msg):
        self.last = msg
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
        if self.last:
            q.put_nowait(self.last)
        return q

    def unsubscribe(self, q):
        with self.lock:
            self.clients.discard(q)


def make_handler(hub, html):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            if self.path in ("/", "/index.html"):
                body = html.encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif self.path == "/stream":
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.end_headers()
                q = hub.subscribe()
                try:
                    while True:
                        msg = q.get()
                        self.wfile.write(f"data: {json.dumps(msg)}\n\n".encode())
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    pass
                finally:
                    hub.unsubscribe(q)
            else:
                self.send_error(404)
    return H


HTML = """<!doctype html><html><head><meta charset=utf-8>
<title>VCK190 WiFi-CSI HAR</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<style>
 body{font-family:system-ui,sans-serif;margin:0;background:#0e1116;color:#e6edf3}
 header{padding:14px 20px;background:#161b22;border-bottom:1px solid #30363d}
 h1{font-size:18px;margin:0}
 .cards{display:flex;gap:14px;flex-wrap:wrap;padding:16px 20px}
 .card{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:14px 18px;min-width:150px}
 .k{font-size:12px;color:#8b949e;text-transform:uppercase;letter-spacing:.05em}
 .v{font-size:26px;font-weight:600;margin-top:4px}
 .fall-on{color:#f85149} .fall-off{color:#3fb950}
 .charts{display:grid;grid-template-columns:1fr 1fr;gap:16px;padding:0 20px 24px}
 .chart{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:12px}
 canvas{max-height:240px}
</style></head><body>
<header><h1>VCK190 - WiFi CSI Human Activity Recognition (AI Engine live)</h1></header>
<div class=cards>
 <div class=card><div class=k>Presence</div><div class=v id=presence>-</div></div>
 <div class=card><div class=k>Activity</div><div class=v id=activity>-</div></div>
 <div class=card><div class=k>Breathing</div><div class=v><span id=bpm>-</span> <small>bpm</small></div></div>
 <div class=card><div class=k>Fall</div><div class=v id=fall>-</div></div>
 <div class=card><div class=k>Motion</div><div class=v id=motion>-</div></div>
</div>
<div class=charts>
 <div class=chart><canvas id=motionChart></canvas></div>
 <div class=chart><canvas id=specChart></canvas></div>
 <div class=chart><canvas id=featChart></canvas></div>
</div>
<script>
const F8=["presence","motion","bpm","hr","phase-var","persons","fall","rssi"];
const mk=(id,type,labels,cfg)=>new Chart(document.getElementById(id),{type,data:{labels,datasets:[Object.assign({data:[]},cfg)]},options:{animation:false,plugins:{legend:{display:false}},scales:{x:{ticks:{color:'#8b949e'}},y:{ticks:{color:'#8b949e'}}}}});
const N=60, tl=Array.from({length:N},(_,i)=>i-N+1);
const motionChart=mk('motionChart','line',tl,{label:'motion',borderColor:'#58a6ff',pointRadius:0,tension:.25});
const specChart=mk('specChart','bar',Array.from({length:33},(_,i)=>i),{label:'breathing spectrum',backgroundColor:'#3fb950'});
const featChart=mk('featChart','bar',F8,{label:'8-feature',backgroundColor:'#d29922'});
motionChart.options.plugins.title={display:true,text:'motion power (live)',color:'#e6edf3'};
specChart.options.plugins.title={display:true,text:'breathing DFT (33 bins)',color:'#e6edf3'};
featChart.options.plugins.title={display:true,text:'ruview 8-feature vector',color:'#e6edf3'};
const mhist=Array(N).fill(0);
const es=new EventSource('/stream');
es.onmessage=(e)=>{const d=JSON.parse(e.data);
 presence.textContent=d.presence?'PRESENT':'empty';
 activity.textContent=d.activity; bpm.textContent=d.bpm.toFixed(1);
 motion.textContent=d.motion.toExponential(2);
 fall.textContent=d.fall?'FALL':'ok'; fall.className='v '+(d.fall?'fall-on':'fall-off');
 mhist.push(d.motion); mhist.shift(); motionChart.data.datasets[0].data=mhist.slice(); motionChart.update();
 specChart.data.datasets[0].data=d.spectrum; specChart.update();
 featChart.data.datasets[0].data=d.features8; featChart.update();
};
</script></body></html>"""


def main():
    ap = argparse.ArgumentParser(description="VCK190 WiFi-CSI HAR live dashboard")
    ap.add_argument("--source", choices=["golden", "exec", "fifo"], default="golden")
    ap.add_argument("--data", default=os.path.join(os.path.dirname(__file__), "..", "aie", "data"),
                    help="golden vectors dir (for --source golden)")
    ap.add_argument("--host", nargs="+", default=["./host_3br", "--stream"],
                    help="command for --source exec")
    ap.add_argument("--fifo", default="/tmp/aie_features.csv", help="path for --source fifo")
    ap.add_argument("--fs", type=float, default=20.0, help="CSI frame rate [Hz]")
    ap.add_argument("--period", type=float, default=0.25, help="golden replay period [s]")
    ap.add_argument("--port", type=int, default=8080)
    args = ap.parse_args()

    hub = Hub()

    if args.source == "golden":
        src = source_golden(args.data, args.fs, args.period)
    elif args.source == "exec":
        src = source_exec(args.host, args.fs, args.period)
    else:
        src = source_fifo(args.fifo, args.fs, args.period)

    def pump():
        hist = []
        for mot, brt, phs in src:
            hub.publish(derive_metrics(mot, brt, phs, args.fs, hist))

    threading.Thread(target=pump, daemon=True).start()

    srv = ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(hub, HTML))
    print(f"[live_dashboard] source={args.source}  http://0.0.0.0:{args.port}/  (Ctrl-C to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
