#!/bin/bash
# Activate nexmon CSI on wlan0: monitor mode + configure the extractor.
# Usage: csi_start.sh [chanspec] [core] [nss]   (default 132/80 1 1)
CHANSPEC="${1:-132/80}"; CORE="${2:-1}"; NSS="${3:-1}"
NEXMON_ROOT="${NEXMON_ROOT:-/home/nexmon/nexmon}"
MCP="$NEXMON_ROOT/patches/bcm43455c0/7_45_189/nexmon_csi/utils/makecsiparams/makecsiparams"

# wait for wlan0 to appear (firmware/driver up)
for _ in $(seq 1 30); do [ -e /sys/class/net/wlan0 ] && break; sleep 1; done

nmcli dev set wlan0 managed no 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true
ip link set wlan0 up 2>/dev/null || true

P="$("$MCP" -c "$CHANSPEC" -C "$CORE" -N "$NSS")" || { echo "csi_start: makecsiparams failed"; exit 1; }
# The SET (-s500) applies cleanly on nexmon CSI firmware; timeout guards any ACK-wait.
timeout 8 nexutil -Iwlan0 -s500 -b -l34 -v"$P" >/dev/null 2>&1 || true
nexutil -Iwlan0 -m1 >/dev/null 2>&1 || true

echo "csi_start: chanspec=$(nexutil -Iwlan0 -k 2>/dev/null) monitor=$(nexutil -Iwlan0 -m 2>/dev/null)"
