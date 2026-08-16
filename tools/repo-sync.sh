#!/bin/sh
# repo-sync.sh — mirror hand-edited SOURCE from the live build tree into this
# (source-only) repo, ready to commit + push. Prebuilt binaries and build
# outputs are excluded here AND by .gitignore; regenerate them per the README.
# Uses rsync WITHOUT --delete, so it never removes files already in the repo.
# Add more source areas below as they start changing.
set -eu
WORK=/group/bcapps/ajayad/master_thesis_rebirth/work
REPO=/group/bcapps/ajayad/master_thesis_rebirth/Wifi-HAR-Versal-VCK190-PL

# Build / tool outputs never belong in the source repo (mirrors .gitignore).
# NOTE: host binaries are caught by .gitignore at commit time; we do NOT exclude a
# bare "host" here because that would also drop the aie/host/ SOURCE directory.
EXC="--exclude=.Xil/ --exclude=.srcs/ --exclude=*.jou --exclude=*.log --exclude=*.str --exclude=*.backup* \
--exclude=*.cache/ --exclude=*.hw/ --exclude=*.runs/ --exclude=*.gen/ --exclude=*.sim/ --exclude=*.ip_user_files/ \
--exclude=_x/ --exclude=_x*/ --exclude=Work/ --exclude=Work_hw*/ --exclude=package/ --exclude=package_*/ --exclude=sd_stage*/ \
--exclude=*.xsa --exclude=*.xclbin --exclude=*.pdi --exclude=*.xo --exclude=*.o --exclude=*.a --exclude=*.ltx --exclude=.ipcache/ \
--exclude=*.cpio.gz* --exclude=*.ext4 --exclude=*.img --exclude=BOOT*.BIN --exclude=Image \
--exclude=__pycache__/ --exclude=*.pyc \
--exclude=*_prj/ --exclude=*_summary --exclude=*simulator_output/ --exclude=analyzer_input/ --exclude=*.db --exclude=*_Report.csv --exclude=PING.txt"

# 1) PetaLinux meta-user layer: recipes (.bb), systemd unit, autorun script, text vectors.
rsync -a $EXC "$WORK/petalinux/petalinux/project-spec/meta-user/" \
             "$REPO/petalinux/project-spec/meta-user/"
# 2) PetaLinux configs (config, rootfs_config) — pin image + rootfs selections.
rsync -a $EXC "$WORK/petalinux/petalinux/project-spec/configs/" \
             "$REPO/petalinux/project-spec/configs/"
# 3) XSA -> SDT generator.
cp -f "$WORK/petalinux/sdt.tcl" "$REPO/petalinux/sdt.tcl" 2>/dev/null || true
# 4) AIE: graph + movers + host source + cfg + build scripts + golden vectors (no build outputs).
rsync -a $EXC "$WORK/aie/feature_graph/" "$REPO/aie/"
# 5) HLS UDP/CSI parser source.
rsync -a $EXC "$WORK/udp_parser/" "$REPO/hls/"
# 6) HW: BD/build TCLs, constraints, HDL, and the pre-packaged csi_udp_parser IP.
rsync -a $EXC "$WORK/hw/scripts/"     "$REPO/hw/scripts/"
rsync -a $EXC "$WORK/hw/constraints/" "$REPO/hw/constraints/"
rsync -a $EXC "$WORK/hw/hdl/"         "$REPO/hw/hdl/"
rsync -a $EXC "$WORK/hw/ip_repo/"     "$REPO/hw/ip_repo/"
# 7) Live dashboard app (pure-Python 3 stdlib; served on-target).
rsync -a $EXC "$WORK/live/" "$REPO/live/"

echo "repo-sync: mirrored meta-user + configs + aie + hls + hw + live (source only)."
