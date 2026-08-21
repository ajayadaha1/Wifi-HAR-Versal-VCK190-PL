#!/bin/bash
# Bake the D1 aie-d1 files + boot-time systemd auto-run into the petalinux rootfs
# ramdisk (same cpio-append trick as inject_3br_rootfs.sh). Produces
# images/linux/rootfs_d1.cpio.gz.u-boot with /home/root/aie-d1/{host,
# inline_cogen_d1.xclbin, input.txt, golden.txt, mux_set.py, d1-autorun.sh} +
# d1-validate.service so host auto-runs at boot and prints D1-VALIDATE to com0.
set -e
cd /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux
STAGE=/group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph/d1_stage
IMG=images/linux
OV=/tmp/d1_overlay
MKI=$(command -v mkimage || echo /proj/petalinux/2025.2/petalinux-v2025.2_11160223/tool/petalinux-v2025.2-final/sysroots/x86_64-petalinux-linux/usr/bin/mkimage)

rm -rf "$OV"; mkdir -p "$OV/home/root/aie-d1" "$OV/etc/systemd/system/multi-user.target.wants"
cp "$STAGE"/host "$STAGE"/inline_cogen_d1.xclbin "$STAGE"/input.txt "$STAGE"/golden.txt \
   "$STAGE"/mux_set.py "$STAGE"/d1-autorun.sh "$OV/home/root/aie-d1/"
chmod +x "$OV/home/root/aie-d1/host" "$OV/home/root/aie-d1/d1-autorun.sh"
cp "$STAGE/d1-validate.service" "$OV/etc/systemd/system/d1-validate.service"
ln -sf ../d1-validate.service "$OV/etc/systemd/system/multi-user.target.wants/d1-validate.service"
# mask stale aie-validate service from the base rootfs
ln -sf /dev/null "$OV/etc/systemd/system/aie-validate.service"
rm -f "$OV/etc/systemd/system/multi-user.target.wants/aie-validate.service" 2>/dev/null || true

zcat "$IMG/rootfs.cpio.gz" > /tmp/d1_combined.cpio
( cd "$OV" && find . | cpio -o -H newc --owner=0:0 -A -F /tmp/d1_combined.cpio 2>/dev/null )
gzip -c /tmp/d1_combined.cpio > /tmp/d1_rootfs.cpio.gz
N=$(zcat /tmp/d1_rootfs.cpio.gz | cpio -t 2>/dev/null | grep -cE 'aie-d1|d1-validate')
echo "overlay entries: $N"; zcat /tmp/d1_rootfs.cpio.gz | cpio -t 2>/dev/null | grep -E 'aie-d1|d1-validate' | head
[ "$N" -lt 6 ] && { echo "INJECT_FAIL"; exit 1; } || true
"$MKI" -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "petalinux-image-minimal-xlnx-ver" \
       -d /tmp/d1_rootfs.cpio.gz "$IMG/rootfs_d1.cpio.gz.u-boot"
ls -l "$IMG/rootfs_d1.cpio.gz.u-boot"; echo "INJECT_D1_DONE_OK"
