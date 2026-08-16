#!/usr/bin/env python3
"""csi_feeder.py - Arch-A live CSI feeder for the VCK190 WiFi-CSI demo.

Receives nexmon_csi UDP frames from the Raspberry Pi, decodes CSI, and writes
the three AI-Engine input files that `host_3br --stream` re-reads each window:
    input.txt        256  motion   (mean-removed subcarrier amplitude)  -> FIR->stats
    breath_input.txt  64  breathing (amplitude, breathing window)       -> windowed-DFT
    phase_input.txt  256  phase    (detrended subcarrier phase)         -> stats

Chain:  Pi --UDP--> csi_feeder.py --> input files --> host_3br --stream (AIE) --> live_dashboard.py

This is the Arch-A path (PS Ethernet -> Linux -> DMA -> validated AIE); it needs
no inline PL parser. Pure Python 3 stdlib (no numpy).
"""
import argparse
import math
import os
import socket
import struct
import time
from collections import deque

NEX_HDR = 18  # nexmon CSI metadata header (see work/csi_capture/decode_csi.py)
MOT, BRT, PHS = 256, 64, 256


def parse_nexmon(payload, nsub_expect=0):
    """UDP payload -> (rssi, [(I,Q), ...]) or None. int16 LE I/Q, 4 bytes/subcarrier."""
    if len(payload) < NEX_HDR + 4:
        return None
    rssi = struct.unpack("b", payload[2:3])[0]
    csi_bytes = payload[NEX_HDR:]
    nsub = len(csi_bytes) // 4
    if nsub == 0 or (nsub_expect and nsub != nsub_expect):
        return None
    iq = struct.unpack("<%dh" % (nsub * 2), csi_bytes[:nsub * 4])
    return rssi, [(iq[2 * i], iq[2 * i + 1]) for i in range(nsub)]


def _atomic_write(path, vals):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join("%.8e" % v for v in vals) + "\n")
    os.replace(tmp, path)  # atomic: host_3br never sees a half-written file


def write_inputs(data_dir, amp, phase):
    m = sum(amp) / len(amp)
    _atomic_write(os.path.join(data_dir, "input.txt"), [x - m for x in amp][-MOT:])
    _atomic_write(os.path.join(data_dir, "breath_input.txt"), [x - m for x in amp][-BRT:])
    pm = sum(phase) / len(phase)
    _atomic_write(os.path.join(data_dir, "phase_input.txt"), [p - pm for p in phase][-PHS:])


def process_frame(csi, sub, amp, phase):
    """Append one subcarrier's amplitude + phase (or mean amplitude) to the buffers."""
    if sub == "mean":
        a = sum(math.hypot(i, q) for i, q in csi) / len(csi)
        k = len(csi) // 2
    else:
        k = int(sub) % len(csi)
        a = math.hypot(csi[k][0], csi[k][1])
    amp.append(a)
    phase.append(math.atan2(csi[k][1], csi[k][0]))


def main():
    ap = argparse.ArgumentParser(description="Arch-A live CSI feeder (Pi UDP -> AIE input files)")
    ap.add_argument("--port", type=int, default=5500, help="UDP CSI port from the Pi")
    ap.add_argument("--sub", default="mean", help="subcarrier index or 'mean'")
    ap.add_argument("--data", default=os.path.join(os.path.dirname(__file__), "..", "aie", "data"),
                    help="dir to write the AIE input files into")
    ap.add_argument("--nsub", type=int, default=0, help="expected subcarrier count (0 = auto)")
    ap.add_argument("--every", type=int, default=4, help="rewrite input files every N frames")
    args = ap.parse_args()

    os.makedirs(args.data, exist_ok=True)
    amp, phase = deque(maxlen=MOT), deque(maxlen=PHS)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", args.port))
    print("[csi_feeder] UDP :%d -> %s  (sub=%s)" % (args.port, args.data, args.sub), flush=True)

    n = 0
    while True:
        payload, _ = sock.recvfrom(65535)
        rec = parse_nexmon(payload, args.nsub)
        if not rec:
            continue
        process_frame(rec[1], args.sub, amp, phase)
        n += 1
        if len(amp) >= MOT and n % args.every == 0:
            write_inputs(args.data, list(amp), list(phase))


if __name__ == "__main__":
    main()
