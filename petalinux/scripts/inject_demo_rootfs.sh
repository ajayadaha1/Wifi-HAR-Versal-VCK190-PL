#!/bin/bash
set -e
cd /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux
STAGE=/group/bcapps/ajayad/master_thesis_rebirth/work/aie/feature_graph/demo_stage
IMG=images/linux
OV=/tmp/demo_overlay
MKI=$(command -v mkimage || echo /proj/petalinux/2025.2/petalinux-v2025.2_11160223/tool/petalinux-v2025.2-final/sysroots/x86_64-petalinux-linux/usr/bin/mkimage)
rm -rf "$OV"; mkdir -p "$OV/home/root" "$OV/etc/systemd/system/multi-user.target.wants"
cp -r "$STAGE/aie-d1" "$OV/home/root/"
cp -r "$STAGE/csi_ref" "$OV/home/root/"
chmod +x "$OV/home/root/aie-d1/host" "$OV/home/root/aie-d1/demo-autorun.sh"
cat > "$OV/etc/systemd/system/demo.service" <<'SVC'
[Unit]
Description=Live AIE CSI feature demo (single-shot host loop)
After=multi-user.target
[Service]
Type=simple
ExecStart=/home/root/aie-d1/demo-autorun.sh
StandardOutput=journal+console
StandardError=journal+console
[Install]
WantedBy=multi-user.target
SVC
ln -sf ../demo.service "$OV/etc/systemd/system/multi-user.target.wants/demo.service"
ln -sf /dev/null "$OV/etc/systemd/system/aie-validate.service"
ln -sf /dev/null "$OV/etc/systemd/system/d1-validate.service"
zcat "$IMG/rootfs.cpio.gz" > /tmp/demo_combined.cpio
( cd "$OV" && find . | cpio -o -H newc --owner=0:0 -A -F /tmp/demo_combined.cpio 2>/dev/null )
gzip -c /tmp/demo_combined.cpio > /tmp/demo_rootfs.cpio.gz
N=$(zcat /tmp/demo_rootfs.cpio.gz | cpio -t 2>/dev/null | grep -cE 'aie-d1/host|demo.service')
echo "overlay entries: $N"
"$MKI" -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "petalinux-image-minimal-xlnx-ver" \
       -d /tmp/demo_rootfs.cpio.gz "$IMG/rootfs_demo.cpio.gz.u-boot"
ls -l "$IMG/rootfs_demo.cpio.gz.u-boot"; echo "INJECT_DEMO_DONE_OK"
