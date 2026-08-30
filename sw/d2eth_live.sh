#!/bin/sh
# d2eth_live.sh (v1.2) - live CSI bring-up + XRT-managed-buffer drain.
#
# v1.2 fix (PROJECT_STATE #27): the fixed 0x7000_0000 /dev/mem drain Async-SErrors
# because 0x70000000 sits in a firewalled/reserved DDR aperture the NoC rejects.
# host_live instead drains the AIE features through an XRT-managed DDR buffer
# (bo.address(), NoC-valid - the SAME mechanism the golden mm2s->AIE->s2mm path
# uses with zero SError) and arms s2mm_meta into an XRT buffer too. No fixed PA,
# no /dev/mem DDR access.
#
# Put host_live + inline_cogen_d2eth_ila.xclbin + input.txt + golden.txt together
# (they ship in /home/root/aie-d2eth-ila on the v1.2 image) and run:  sh d2eth_live.sh
set -e
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
XCLBIN=${XCLBIN:-inline_cogen_d2eth_ila.xclbin}

echo "== stop the golden autorun loop (holds csi_mux=1/DDR + loops the golden host) =="
pkill -9 -f d2eth-ila-autorun.sh 2>/dev/null || true
sleep 1

echo "== MAC init + bring the SFP0 link UP (force 1G, autoneg OFF) =="
# A copper SFP speaks SGMII, so clause-37 fiber autoneg never completes; disabling
# AN lets the 1.25G SerDes lock. Cable MUST be in SFP0 (bank 105, GTY ch2).
python3 "$HERE/pl_mac.py" check noan || true

echo "== self-test the XRT-bo drain first (proves the datapath, no Pi needed) =="
"$HERE/host_live" --selftest "$HERE/$XCLBIN" --in "$HERE/input.txt" --gold "$HERE/golden.txt" --iters 3 || true

echo "== LIVE: csi_mux=0 (parser) + parser/s2mm_meta armed; drain AIE features via XRT bo =="
if [ "${DASH:-0}" = "1" ] && [ -f "$HERE/live_dashboard.py" ]; then
    echo "   dashboard on http://<board-ip>:8080  (source=exec -> host_live --live)"
    exec python3 "$HERE/live_dashboard.py" --source exec --host "$HERE/host_live" --live --port 8080
else
    exec "$HERE/host_live" --live "$HERE/$XCLBIN"
fi
