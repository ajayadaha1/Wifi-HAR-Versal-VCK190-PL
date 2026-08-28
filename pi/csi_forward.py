#!/usr/bin/env python3
"""Forward nexmon CSI UDP frames from the monitor interface (wlan0) out to Ethernet (eth0).

nexmon_csi injects Channel-State-Information as UDP:5500 broadcast frames onto wlan0
(src 10.10.10.10 -> 255.255.255.255). Those frames never leave the Pi on their own.
This service captures them at layer 2 and re-emits the nexmon payload as a fresh UDP
datagram on eth0, so the Versal VCK190's `csi_udp_parser` (which keys off standard
header offsets: ethertype@12, proto@23, dport@36, nexmon@42, CSI@60) receives a
byte-correct frame.

Config via environment (see csi-forward.service):
  CSI_SRC_IF  monitor interface to capture on   (default wlan0)
  CSI_DST_IF  ethernet interface to send out     (default eth0)
  CSI_DST_IP  destination IP                      (default 255.255.255.255 = broadcast)
  CSI_PORT    UDP port                            (default 5500)
"""
import os
import socket
import struct
import sys
import signal

SRC_IF = os.environ.get("CSI_SRC_IF", "wlan0")
DST_IF = os.environ.get("CSI_DST_IF", "eth0")
DST_IP = os.environ.get("CSI_DST_IP", "255.255.255.255")
PORT = int(os.environ.get("CSI_PORT", "5500"))

ETH_HLEN, IP_HLEN, UDP_HLEN = 14, 20, 8
PAYLOAD_OFF = ETH_HLEN + IP_HLEN + UDP_HLEN  # 42: nexmon magic sits here
PORT_BE = struct.pack("!H", PORT)
ETH_P_ALL = 0x0003


def main():
    rx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    rx.bind((SRC_IF, 0))

    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tx.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        tx.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, DST_IF.encode())
    except (PermissionError, OSError):
        pass  # falls back to routing table

    print(f"[csi_forward] {SRC_IF} udp/{PORT} -> {DST_IP}:{PORT} via {DST_IF}", flush=True)
    n = 0
    while True:
        frame = rx.recv(4096)
        if len(frame) < PAYLOAD_OFF:
            continue
        # IPv4 + IHL=5 (no options) + UDP + dport == PORT
        if frame[12:14] != b"\x08\x00" or frame[14] != 0x45:
            continue
        if frame[23] != 17 or frame[36:38] != PORT_BE:
            continue
        # exact UDP payload length (guards against trailing FCS / padding)
        udp_len = struct.unpack("!H", frame[38:40])[0]
        plen = udp_len - UDP_HLEN
        payload = frame[PAYLOAD_OFF:PAYLOAD_OFF + plen]
        if not payload:
            continue
        tx.sendto(payload, (DST_IP, PORT))
        n += 1
        if n % 500 == 0:
            print(f"[csi_forward] forwarded {n} CSI frames", flush=True)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    main()
