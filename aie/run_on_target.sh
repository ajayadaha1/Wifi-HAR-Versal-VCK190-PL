#!/bin/sh
# run_on_target.sh — on the VCK190 (PetaLinux), validate the DDR->AIE->DDR path.
# Loads feature_graph.xclbin, streams data/input.txt through mm2s->AIE->s2mm,
# and compares the {mean,var,power} result against data/golden.txt.
#
# Staged onto the SD card by package.sh (--package.sd_dir). Run it from wherever
# the SD boot partition mounts (e.g. /mnt/sd-mmcblk0p1 or /run/media/mmcblk0p1).
set -e
cd "$(dirname "$0")"

XCLBIN="${1:-}"
if [ -z "$XCLBIN" ]; then
  for c in ./feature_graph.xclbin \
           /mnt/sd-mmcblk0p1/feature_graph.xclbin \
           /run/media/mmcblk0p1/feature_graph.xclbin \
           /media/sd-mmcblk0p1/feature_graph.xclbin; do
    [ -f "$c" ] && XCLBIN="$c" && break
  done
fi
[ -n "$XCLBIN" ] && [ -f "$XCLBIN" ] || { echo "ERROR: feature_graph.xclbin not found (pass path as arg1)"; exit 2; }

IN="${2:-input.txt}"
GOLD="${3:-golden.txt}"
[ -f "$IN" ]   || { echo "ERROR: $IN not found"; exit 2; }
[ -f "$GOLD" ] || echo "WARN: $GOLD not found; running without golden compare"

echo "xclbin : $XCLBIN"
echo "input  : $IN"
echo "golden : $GOLD"
echo "--- xbutil examine (device present?) ---"
xbutil examine 2>/dev/null | head -20 || echo "(xbutil not available)"
echo "--- host run ---"
./host "$XCLBIN" "$IN" "$GOLD"
