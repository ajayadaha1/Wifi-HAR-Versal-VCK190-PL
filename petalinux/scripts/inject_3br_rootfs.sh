#!/bin/bash
# 3-branch variant of inject_aie_rootfs.sh: bake the 3-branch aie-validate files
# + boot-time systemd auto-run directly into the petalinux rootfs ramdisk,
# bypassing the (sstate-broken) petalinux image build. Bakes
# /home/root/aie-validate/{host_3br, feature_graph_3br.xclbin, 6 vectors,
# run_on_target.sh, aie-validate-autorun.sh} + aie-validate.service so host_3br
# auto-runs at boot and prints [mot]/[brt]/[phs] PASS/FAIL to com0.
# RUN ONLY when petalinux-build is NOT running (both write rootfs.cpio.gz.u-boot).
set -e
cd /group/bcapps/ajayad/master_thesis_rebirth/work/petalinux/petalinux
FILES=project-spec/meta-user/recipes-apps/aie-validate/files
IMG=images/linux
OV=/tmp/aie_overlay_3br
MKI=$(command -v mkimage || echo /proj/petalinux/2025.2/petalinux-v2025.2_11160223/tool/petalinux-v2025.2-final/sysroots/x86_64-petalinux-linux/usr/bin/mkimage)

echo "=== stage overlay tree (root-owned at pack time) ==="
rm -rf "$OV"; mkdir -p "$OV/home/root/aie-validate" "$OV/etc/systemd/system/multi-user.target.wants"
cp "$FILES"/host_3br "$FILES"/feature_graph_3br.xclbin \
   "$FILES"/input.txt "$FILES"/golden.txt \
   "$FILES"/breath_input.txt "$FILES"/breath_golden.txt \
   "$FILES"/phase_input.txt "$FILES"/phase_golden.txt \
   "$FILES"/run_on_target.sh "$FILES"/aie-validate-autorun.sh "$OV/home/root/aie-validate/"
chmod +x "$OV/home/root/aie-validate/host_3br" "$OV/home/root/aie-validate/run_on_target.sh" "$OV/home/root/aie-validate/aie-validate-autorun.sh"
cp "$FILES/aie-validate.service" "$OV/etc/systemd/system/aie-validate.service"
ln -sf ../aie-validate.service "$OV/etc/systemd/system/multi-user.target.wants/aie-validate.service"

echo "=== decompress base rootfs cpio ==="
zcat "$IMG/rootfs.cpio.gz" > /tmp/aie_combined_3br.cpio

echo "=== append overlay into the same archive (removes base trailer, adds ours) ==="
( cd "$OV" && find . | cpio -o -H newc --owner=0:0 -A -F /tmp/aie_combined_3br.cpio 2>/dev/null )

echo "=== recompress + verify overlay present ==="
gzip -c /tmp/aie_combined_3br.cpio > /tmp/aie_rootfs_3br.cpio.gz
N=$(zcat /tmp/aie_rootfs_3br.cpio.gz | cpio -t 2>/dev/null | grep -c 'aie-validate')
echo "overlay entries in combined archive: $N"
zcat /tmp/aie_rootfs_3br.cpio.gz | cpio -t 2>/dev/null | grep 'aie-validate' | head -20
if [ "$N" -lt 8 ]; then echo "INJECT_FAIL: overlay not fully present"; exit 1; fi

echo "=== re-wrap with mkimage (matching original header) ==="
"$MKI" -A arm64 -O linux -T ramdisk -C none -a 0 -e 0 -n "petalinux-image-minimal-xlnx-ver" \
       -d /tmp/aie_rootfs_3br.cpio.gz "$IMG/rootfs.cpio.gz.u-boot"
"$MKI" -l "$IMG/rootfs.cpio.gz.u-boot" | head -6
ls -l "$IMG/rootfs.cpio.gz.u-boot"
echo "INJECT_3BR_DONE_OK"
