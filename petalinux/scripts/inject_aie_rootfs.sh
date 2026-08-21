#!/bin/bash
# Inject the aie-validate files + boot-time systemd service directly into the
# petalinux rootfs ramdisk, bypassing the (sstate-broken) petalinux image build.
# Uses `cpio -o -A` to append into a single clean newc archive (root-owned),
# then re-wraps with mkimage using the SAME header as petalinux (-C none, gzip
# payload). Idempotent: always rebuilds from images/linux/rootfs.cpio.gz.
set -e
cd /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux
FILES=project-spec/meta-user/recipes-apps/aie-validate/files
IMG=images/linux
OV=/tmp/aie_overlay
MKI=/proj/petalinux/2025.2/petalinux-v2025.2_11160223/tool/petalinux-v2025.2-final/sysroots/x86_64-petalinux-linux/usr/bin/mkimage

echo "=== stage overlay tree (root-owned at pack time) ==="
rm -rf "$OV"; mkdir -p "$OV/home/root/aie-validate" "$OV/etc/systemd/system/multi-user.target.wants"
cp "$FILES"/host "$FILES"/feature_graph.xclbin "$FILES"/input.txt "$FILES"/golden.txt \
   "$FILES"/run_on_target.sh "$FILES"/aie-validate-autorun.sh "$OV/home/root/aie-validate/"
chmod +x "$OV/home/root/aie-validate/host" "$OV/home/root/aie-validate/run_on_target.sh" "$OV/home/root/aie-validate/aie-validate-autorun.sh"
cp "$FILES/aie-validate.service" "$OV/etc/systemd/system/aie-validate.service"
ln -sf ../aie-validate.service "$OV/etc/systemd/system/multi-user.target.wants/aie-validate.service"

echo "=== decompress base rootfs cpio ==="
zcat "$IMG/rootfs.cpio.gz" > /tmp/aie_combined.cpio

echo "=== append overlay into the same archive (removes base trailer, adds ours) ==="
( cd "$OV" && find . | cpio -o -H newc --owner=0:0 -A -F /tmp/aie_combined.cpio 2>/dev/null )

echo "=== recompress + verify overlay present (single archive, cpio -t lists all) ==="
gzip -c /tmp/aie_combined.cpio > /tmp/aie_rootfs_new.cpio.gz
N=$(zcat /tmp/aie_rootfs_new.cpio.gz | cpio -t 2>/dev/null | grep -c 'aie-validate')
echo "overlay entries found in combined archive: $N"
zcat /tmp/aie_rootfs_new.cpio.gz | cpio -t 2>/dev/null | grep 'aie-validate' | head
if [ "$N" -lt 6 ]; then echo "INJECT_FAIL: overlay not fully present"; exit 1; fi

echo "=== re-wrap with mkimage (matching original header) ==="
"$MKI" -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "petalinux-image-minimal-xlnx-ver" \
       -d /tmp/aie_rootfs_new.cpio.gz "$IMG/rootfs.cpio.gz.u-boot"
"$MKI" -l "$IMG/rootfs.cpio.gz.u-boot" | head -6
ls -l "$IMG/rootfs.cpio.gz.u-boot"
echo "INJECT_DONE_OK"
