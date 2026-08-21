#!/bin/bash
# ---------------------------------------------------------------------------
# inject_inline_rootfs.sh - build the on-target payload for the inline design.
#
# Supersedes inject_csi_ctl.sh, which only carried csi_ctl. Same technique
# (cpio -o -A appends into ONE clean newc archive, root-owned, then mkimage
# re-wraps it) - the petalinux image build is unusable here because the shared
# sstate has broken native packages, so petalinux-build is never run.
#
# Carries four things:
#   csi_ctl          the /dev/mem control tool, with the DDR aligned-access fix
#   replay_test.py   drives mm2s_rx -> parser -> DDR with no Ethernet involved
#   inline_reader.py + live_dashboard.py   the dashboard, hosted ON the board
#
# Why the dashboard runs on the target: both files are stdlib-only (checked),
# and the board has python3.12, so nothing needs installing. Reading the AIE
# results straight out of /dev/mem is the whole point - serving the same page
# from a workstation off golden vectors proves much less. Expose it with
# `tcpforward 8090 8090` at the Systest prompt.
#
# NOTE `--source golden` is NOT usable on the target: it loads an .npz and
# needs numpy, which is not in this rootfs. `--source inline` is stdlib-only.
#
# The autorun service matters because interactive login is not available to
# automation: the petalinux account forces a password change on first boot, and
# setting a device credential from a script (into a console that is piped to a
# plaintext log) is not something to do unattended. Running as root at boot
# sidesteps the question entirely and prints straight to the console.
#
# Usage:  bash work/petalinux/inject_inline_rootfs.sh
# ---------------------------------------------------------------------------
set -e
ROOT=/group/bcapps/ajayad/master_thesis_rebirth/work
cd "$ROOT/petalinux/petalinux"
IMG=images/linux
OV=/tmp/inline_overlay
OUT=$IMG/rootfs_inline.cpio.gz.u-boot
MKI=/proj/petalinux/2025.2/petalinux-v2025.2_11160223/tool/petalinux-v2025.2-final/sysroots/x86_64-petalinux-linux/usr/bin/mkimage

[ -x "$ROOT/sw/csi_ctl" ] || { echo "build it first: (cd $ROOT/sw && bash build.sh)" >&2; exit 1; }
file "$ROOT/sw/csi_ctl" | grep -q aarch64 || { echo "csi_ctl is not aarch64" >&2; exit 1; }

echo "=== stage overlay ==="
rm -rf "$OV"; mkdir -p "$OV/home/root/inline" "$OV/etc/systemd/system/multi-user.target.wants"
cp "$ROOT/sw/csi_ctl"          "$OV/home/root/inline/"
cp "$ROOT/sw/replay_test.py" "$ROOT/sw/aie_scan.py" "$ROOT/sw/shim_probe.py" "$ROOT/sw/shim_sweep.py" "$ROOT/sw/mux_sweep.py" \
   "$OV/home/root/inline/"
cp "$ROOT/live/inline_reader.py" "$ROOT/live/live_dashboard.py" "$OV/home/root/inline/"
chmod +x "$OV/home/root/inline/csi_ctl"

cat > "$OV/home/root/inline/autorun.sh" <<'EOS'
#!/bin/sh
# Runs as root at boot. Everything goes to the console so it can be read over
# com0 with no login (see inject_inline_rootfs.sh for why there is no login).
exec >/dev/console 2>&1
cd /home/root/inline || exit 1
echo "================ INLINE AUTORUN ================"

echo "--- AIE aperture (geometry tells us the column partition) ---"
dmesg | grep -i aie || echo "  (no aie lines)"

echo "--- PL register state ---"
./csi_ctl status 2>&1 | sed 's/^/  /'

echo "--- AIE core scan: is the graph running, and where? ---"
python3 aie_scan.py 2>&1 | sed 's/^/  /'

echo "--- AIE shim stream switch: did the CDO configure our column? ---"
python3 shim_probe.py 24 11 2>&1 | sed 's/^/  /'

echo "--- shim MUX: is the shim sourcing from NoC instead of PL? ---"
python3 mux_sweep.py 24 2>&1 | sed 's/^/  /'

echo "--- replay test: DDR -> parser -> metadata, no Ethernet ---"
python3 replay_test.py 2>&1 | sed 's/^/  /'
echo "INLINE-REPLAY rc=$?"

echo "--- network ---"
ip -o -4 addr show 2>/dev/null | awk '{print "  "$2" "$4}'

echo "--- dashboard on :8090 (expose with: tcpforward 8090 8090) ---"
nohup python3 live_dashboard.py --source inline --port 8090 \
      > /home/root/inline/dashboard.log 2>&1 &
sleep 3
echo "  dashboard pid $! ; log /home/root/inline/dashboard.log"
echo "================ AUTORUN DONE =================="
EOS
chmod +x "$OV/home/root/inline/autorun.sh"

cat > "$OV/etc/systemd/system/inline-autorun.service" <<'EOS'
[Unit]
Description=Inline Arch-B bring-up: replay test + on-board dashboard
After=multi-user.target network.target
[Service]
Type=oneshot
ExecStart=/home/root/inline/autorun.sh
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOS
ln -sf ../inline-autorun.service \
    "$OV/etc/systemd/system/multi-user.target.wants/inline-autorun.service"

echo "=== decompress base rootfs ==="
zcat "$IMG/rootfs.cpio.gz" > /tmp/inline_combined.cpio

echo "=== append overlay ==="
( cd "$OV" && find . | cpio -o -H newc --owner=0:0 -A -F /tmp/inline_combined.cpio 2>/dev/null )

echo "=== recompress + verify ==="
gzip -c /tmp/inline_combined.cpio > /tmp/inline_rootfs.cpio.gz
N=$(zcat /tmp/inline_rootfs.cpio.gz | cpio -t 2>/dev/null | grep -cE 'home/root/inline|inline-autorun')
echo "overlay entries: $N"
[ "$N" -ge 8 ] || { echo "INJECT_FAIL: overlay incomplete (got $N)"; exit 1; }

echo "=== re-wrap with mkimage ==="
"$MKI" -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "petalinux-image-minimal-xlnx-ver" \
       -d /tmp/inline_rootfs.cpio.gz "$OUT"
ls -l "$OUT"
echo "INJECT_DONE_OK  -> $OUT"
