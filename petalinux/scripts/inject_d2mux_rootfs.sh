#!/bin/bash
# Bake the D1 aie-d2mux files + boot-time systemd auto-run into the petalinux rootfs
# ramdisk (same cpio-append trick as inject_3br_rootfs.sh). Produces
# images/linux/rootfs_d2mux.cpio.gz.u-boot with /home/root/aie-d2mux/{host,
# inline_cogen_d2mux.xclbin, input.txt, golden.txt, mux_set.py, d2mux-autorun.sh} +
# d2mux-validate.service so host auto-runs at boot and prints D1-VALIDATE to com0.
set -e
cd /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux
STAGE=/group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph/d2mux_stage
IMG=images/linux
OV=/tmp/d2mux_overlay
MKI=$(command -v mkimage || echo /proj/petalinux/2025.2/petalinux-v2025.2_11160223/tool/petalinux-v2025.2-final/sysroots/x86_64-petalinux-linux/usr/bin/mkimage)

rm -rf "$OV"; mkdir -p "$OV/home/root/aie-d2mux" "$OV/etc/systemd/system/multi-user.target.wants"
cp "$STAGE"/host "$STAGE"/inline_cogen_d2mux.xclbin "$STAGE"/input.txt "$STAGE"/golden.txt \
   "$STAGE"/mux_set.py "$STAGE"/mux_probe.py "$STAGE"/d2mux-autorun.sh "$OV/home/root/aie-d2mux/"
chmod +x "$OV/home/root/aie-d2mux/host" "$OV/home/root/aie-d2mux/d2mux-autorun.sh"
cp "$STAGE/d2mux-validate.service" "$OV/etc/systemd/system/d2mux-validate.service"
ln -sf ../d2mux-validate.service "$OV/etc/systemd/system/multi-user.target.wants/d2mux-validate.service"
# mask stale aie-validate + d1-validate services from prior rootfs baking
ln -sf /dev/null "$OV/etc/systemd/system/aie-validate.service"
ln -sf /dev/null "$OV/etc/systemd/system/d1-validate.service"
rm -f "$OV/etc/systemd/system/multi-user.target.wants/aie-validate.service" 2>/dev/null || true

zcat "$IMG/rootfs.cpio.gz" > /tmp/d2mux_combined.cpio
( cd "$OV" && find . | cpio -o -H newc --owner=0:0 -A -F /tmp/d2mux_combined.cpio 2>/dev/null )
gzip -c /tmp/d2mux_combined.cpio > /tmp/d2mux_rootfs.cpio.gz
N=$(zcat /tmp/d2mux_rootfs.cpio.gz | cpio -t 2>/dev/null | grep -cE 'aie-d2mux|d2mux-validate')
echo "overlay entries: $N"; zcat /tmp/d2mux_rootfs.cpio.gz | cpio -t 2>/dev/null | grep -E 'aie-d2mux|d2mux-validate' | head
[ "$N" -lt 6 ] && { echo "INJECT_FAIL"; exit 1; } || true
"$MKI" -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "petalinux-image-minimal-xlnx-ver" \
       -d /tmp/d2mux_rootfs.cpio.gz "$IMG/rootfs_d2mux.cpio.gz.u-boot"
ls -l "$IMG/rootfs_d2mux.cpio.gz.u-boot"; echo "INJECT_D2MUX_DONE_OK"
