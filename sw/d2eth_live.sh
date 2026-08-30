#!/bin/sh
# d2eth_live.sh - live CSI bring-up + streaming drain for the D2ETH-ILA image.
#
# THE LIVE PATH (Pi -> SFP0 -> GTY -> PCS -> MAC RX -> parser -> csi_mux -> AIE
# -> s2mm/s2mm_meta -> DDR). This script performs the two fixes from
# PROJECT_STATE.md #25/#26 in software:
#   Fix 1 (image): requires the v01.1 boot image whose dtb has the no-map
#          reserved-memory carve-out at 0x7000_0000 (validated on silicon:
#          "OF: reserved mem: 0x70000000..0x700fffff nomap ... csi-meta").
#          Do NOT run this on an image without it - s2mm_meta would DMA into
#          kernel RAM and panic (SError). Check first:  grep 7000 /proc/iomem
#   Fix 2 (drain): use inline_reader.py's auto-restart s2mm drain, NOT the golden
#          one-shot host (which stalls on a free-running live stream, #25.6).
#
# Copy pl_mac.py + inline_reader.py (+ optionally live_dashboard.py) next to this
# script on the board (e.g. /home/root), then:  sh d2eth_live.sh
set -e
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PL_BASE=0xA4000000        # csi_mux MI0 route @ +0x60040 (0=parser/live, 1=mm2s/DDR)

echo "== d2eth_live: verify the reserved-memory carve-out is present =="
if grep -qiE "7000.*csi-meta|csi-meta.*7000" /proc/iomem 2>/dev/null || \
   dmesg 2>/dev/null | grep -qiE "reserved mem: 0x0*70000000.*nomap"; then
    echo "   OK: 0x70000000 carve-out present"
else
    echo "   WARNING: could not confirm the 0x70000000 carve-out."
    echo "   If this image lacks it, s2mm_meta will PANIC the kernel. Aborting."
    echo "   (Boot the v01.1 image, or override with FORCE=1 if you are sure.)"
    [ "${FORCE:-0}" = "1" ] || exit 1
fi

echo "== stop the golden autorun loop (holds csi_mux=1/DDR + loops one-shot host) =="
pkill -9 -f d2eth-ila-autorun.sh 2>/dev/null || true
sleep 1

echo "== MAC init + bring the SFP0 link UP (force 1G, autoneg OFF) =="
# A copper SFP speaks SGMII, so clause-37 fiber autoneg never completes; disabling
# AN lets the 1.25G SerDes lock. Cable MUST be in SFP0 (bank 105, GTY ch2).
python3 "$HERE/pl_mac.py" check noan

echo "== route csi_mux -> live parser (MI0 = 0) =="
python3 - "$PL_BASE" <<'PY'
import sys, mmap, os, struct
base = int(sys.argv[1], 0)
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x100000, offset=base)
def w(off, val): m[off:off+4] = struct.pack("<I", val)
w(0x60040, 0)     # MI0 route select = 0 (parser/live)
w(0x60000, 0x2)   # commit
m.close(); os.close(fd)
print("   csi_mux MI0 -> 0 (live parser)")
PY

echo "== start the parser + s2mm_meta (SAFE: 0x70000000 is a no-map carve-out) =="
python3 "$HERE/pl_mac.py" start

echo "== stream-drain AIE results + CSI metadata from the carve-out =="
# inline_reader --arm programs the result s2mm (ap_start|auto_restart -> rewrites
# 0x70010000 every window) and reads metadata from 0x70000000. This is the live
# streaming drain that REPLACES the golden one-shot host.
if [ "${DASH:-0}" = "1" ] && [ -f "$HERE/live_dashboard.py" ]; then
    echo "   launching dashboard on http://<board-ip>:8080"
    exec python3 "$HERE/live_dashboard.py" --source inline --port 8080
else
    exec python3 "$HERE/inline_reader.py" --arm --loop --decode --hz 10
fi
