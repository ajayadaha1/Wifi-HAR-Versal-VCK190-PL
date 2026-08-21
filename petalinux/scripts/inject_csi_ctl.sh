#!/bin/bash
# ---------------------------------------------------------------------------
# inject_csi_ctl.sh - put csi_ctl into the petalinux rootfs ramdisk.
#
# Same technique as inject_aie_rootfs.sh (which see): `cpio -o -A` appends into
# ONE clean newc archive, root-owned, then mkimage re-wraps it. This exists
# because the petalinux image build is broken here - the shared sstate has
# broken native packages - so we never run petalinux-build for this.
#
# It also installs a systemd autorun service that runs `csi_ctl selftest` at
# boot. That is not a convenience: the board console (com0) is read-only to
# automation (PROJECT_STATE.md section 10), so without it there is no way to run
# anything on the target unattended. The verdict is left in DDR at 0x70040000
# and read back over JTAG, which needs no login and no working Ethernet.
#
# Writes images/linux/rootfs_inline.cpio.gz.u-boot, leaving the existing
# rootfs.cpio.gz.u-boot alone.
#
# Usage:  bash work/petalinux/inject_csi_ctl.sh
# ---------------------------------------------------------------------------
set -e
ROOT=/group/bcapps/ajayad/master_thesis_rebirth/work
cd "$ROOT/petalinux/petalinux"
IMG=images/linux
OV=/tmp/csi_ctl_overlay
OUT=$IMG/rootfs_inline.cpio.gz.u-boot
MKI=/proj/petalinux/2025.2/petalinux-v2025.2_11160223/tool/petalinux-v2025.2-final/sysroots/x86_64-petalinux-linux/usr/bin/mkimage

[ -x "$ROOT/sw/csi_ctl" ] || { echo "build it first: bash $ROOT/sw/build.sh" >&2; exit 1; }
file "$ROOT/sw/csi_ctl" | grep -q aarch64 || { echo "$ROOT/sw/csi_ctl is not aarch64" >&2; exit 1; }

echo "=== stage overlay ==="
rm -rf "$OV"; mkdir -p "$OV/home/root/inline" "$OV/etc/systemd/system/multi-user.target.wants"
cp "$ROOT/sw/csi_ctl" "$OV/home/root/inline/"
chmod +x "$OV/home/root/inline/csi_ctl"

cat > "$OV/home/root/inline/selftest-autorun.sh" <<'EOS'
#!/bin/sh
# Runs at boot. Echoes to the console for a human watching com0, and leaves the
# machine-readable verdict in DDR at 0x70040000 for JTAG collection.
exec >/dev/console 2>&1
echo "INLINE-SELFTEST: starting"
sleep 5
cd /home/root/inline || exit 1
./csi_ctl selftest
echo "INLINE-SELFTEST: rc=$?"
EOS
chmod +x "$OV/home/root/inline/selftest-autorun.sh"

cat > "$OV/etc/systemd/system/inline-selftest.service" <<'EOS'
[Unit]
Description=Inline Arch-B Ethernet loopback self-test
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/home/root/inline/selftest-autorun.sh
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOS
ln -sf ../inline-selftest.service \
    "$OV/etc/systemd/system/multi-user.target.wants/inline-selftest.service"
cat > "$OV/home/root/inline/README" <<'EOF'
Inline Arch-B bring-up (see PROJECT_STATE.md sections 11-12).

  ./csi_ctl status          read-only: MAC, PCS link, RX counters, kernel states
  ./csi_ctl mac-init        configure the MAC + internal PCS, enable RX
  ./csi_ctl status          expect link=UP once the SFP is connected
  ./csi_ctl mux 1           AIE source = mm2s (replay the golden DDR vector)
  ./csi_ctl mux 0           AIE source = live parser
  ./csi_ctl start           free-run the parser + metadata writer (UDP 5500)
  ./csi_ctl meta            decode the newest metadata record from DDR

The metadata buffer is 0x70000000, carved out by the reserved-memory node in
the device tree. If you move one, move the other (csi_ctl --buf).
EOF

echo "=== decompress base rootfs ==="
zcat "$IMG/rootfs.cpio.gz" > /tmp/csi_ctl_combined.cpio

echo "=== append overlay ==="
( cd "$OV" && find . | cpio -o -H newc --owner=0:0 -A -F /tmp/csi_ctl_combined.cpio 2>/dev/null )

echo "=== recompress + verify ==="
gzip -c /tmp/csi_ctl_combined.cpio > /tmp/csi_ctl_rootfs.cpio.gz
N=$(zcat /tmp/csi_ctl_rootfs.cpio.gz | cpio -t 2>/dev/null | grep -cE 'home/root/inline|inline-selftest')
echo "overlay entries: $N"
[ "$N" -ge 6 ] || { echo "INJECT_FAIL: overlay not present (got $N)"; exit 1; }

echo "=== re-wrap with mkimage ==="
"$MKI" -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "petalinux-image-minimal-xlnx-ver" \
       -d /tmp/csi_ctl_rootfs.cpio.gz "$OUT"
ls -l "$OUT"
echo "INJECT_DONE_OK  -> $OUT"
