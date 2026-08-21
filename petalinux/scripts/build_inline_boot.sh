#!/bin/bash
# ---------------------------------------------------------------------------
# build_inline_boot.sh - BOOT.BIN + device tree for the inline Arch-B design.
#
# Produces, in work/petalinux/petalinux/images/linux/:
#   system-inline.dtb   device tree from the inline XSA's SDT, plus the
#                       reserved-memory carve-out for the metadata buffer
#   BOOT_inline.BIN     PLM + PSM + inline.pdi + the AIE graph CDO + dtb +
#                       bl31 + u-boot
#
# Two things this has to get right, both learned the hard way (PROJECT_STATE #10):
#   1. The XSA's own PDI carries aie_subsys (the shim/NoC config) but NOT the
#      AIE graph, so the graph CDO is added here as a separate aie_image
#      partition. Without it the tiles stay gated and the datapath is dead.
#   2. The 1-branch CDO is the right one: this BD's ai_engine_0 has a single
#      AXIS in and out (it was captured from the 1-branch v++ link), so it pairs
#      with package/aie.merged.cdo.bin, not package_3br/.
#
# NOTE this design needs no XRT/zocl - it is a plain Vivado design with no
# xclbin - so the zocl `interrupts-extended` dtb patch from #10 does not apply.
#
# Usage:  bash work/petalinux/build_inline_boot.sh
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT=/group/bcapps/ajayad/master_thesis_rebirth/work
XSA=$ROOT/hw/inline_eth_hw/inline.xsa
SDT=$ROOT/petalinux/sdt_inline
IMG=$ROOT/petalinux/petalinux/images/linux
EXTRAS=$ROOT/petalinux/inline_extras.dtsi
WORK=$ROOT/petalinux/inline_boot
AIE_CDO=$ROOT/aie/feature_graph/package/aie.merged.cdo.bin

# settings64.sh reads unset variables (LD_LIBRARY_PATH and friends), so `set -u`
# kills the shell dead the moment it is sourced - shield it from -e and -u both.
set +eu
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1
set -eu
command -v bootgen >/dev/null || { echo "bootgen not on PATH after sourcing Vitis" >&2; exit 1; }

for f in "$XSA" "$AIE_CDO" "$IMG/plm.elf" "$IMG/psmfw.elf" "$IMG/bl31.elf" "$IMG/u-boot.elf"; do
    [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
[ -d "$SDT" ] || { echo "missing SDT: $SDT (run: xsct $ROOT/petalinux/sdt.tcl $XSA $SDT)" >&2; exit 1; }

mkdir -p "$WORK"

# --- 1) the PDI out of the XSA ---------------------------------------------
echo "== extracting inline.pdi"
unzip -o -q "$XSA" inline.pdi -d "$WORK"
ls -l "$WORK/inline.pdi"

# --- 2) device tree ---------------------------------------------------------
# An SDT is not a Linux device tree. It describes EVERY processor domain on the
# part - APU, RPU, and both MicroBlazes - and has to be reduced to one domain's
# view before Linux sees it. That reduction is lopper's job.
#
# This was hand-rolled first, and it cost three separate hardware boot failures
# to discover three things lopper does that were not obvious (the RPU's GICv2,
# the interrupt multiplexer, and OCM being listed as system RAM - see
# check_linux_dtb.py for the full post-mortem of each). Use the supported tool.
#
# Two things the invocation needs and the defaults do not give:
#   - `-- gen_domain_dts psv_cortexa72_0 linux_dt` selects the APU Linux view;
#     without it you get the whole multi-domain tree back.
#   - `-i lop-a72-imux.dts` resolves /axi/interrupt-multiplex, moves the GIC out
#     of /apu-bus, and repoints its ~60 referrers (including /timer) at the GIC.
#     gen_domain_dts alone does NOT do this, and the resulting tree boots to a
#     kernel with no timer.
echo "== building system-inline.dtb (lopper)"
LOPS=/proj/gsd/vivado/2025.2/Vivado/bin/unwrapped/lnx64.o/lopper/depends/lopper/lops
[ -f "$LOPS/lop-a72-imux.dts" ] || { echo "missing lop: $LOPS/lop-a72-imux.dts" >&2; exit 1; }
command -v lopper >/dev/null || { echo "lopper not on PATH after sourcing Vitis" >&2; exit 1; }

rm -rf "$WORK/lop"; mkdir -p "$WORK/lop"
( cd "$SDT" && lopper -f --enhanced -O "$WORK/lop" -i "$LOPS/lop-a72-imux.dts" \
      system-top.dts system-linux.dts -- gen_domain_dts psv_cortexa72_0 linux_dt )
[ -s "$WORK/lop/system-linux.dts" ] || { echo "lopper produced no output" >&2; exit 1; }

# Our own additions (the metadata carve-out), plus any debug bootargs.
cp "$WORK/lop/system-linux.dts" "$WORK/system-top-linux.dts"
{ echo; echo '/* --- appended by build_inline_boot.sh --- */'; cat "$EXTRAS"; } \
    >> "$WORK/system-top-linux.dts"
if [ -n "${EXTRA_BOOTARGS:-}" ]; then
    python3 - "$WORK/system-top-linux.dts" "$EXTRA_BOOTARGS" <<'PY'
import re, sys
path, extra = sys.argv[1], sys.argv[2]
t = open(path).read()
m = re.search(r'bootargs = "([^"]*)"', t)
if not m:
    raise SystemExit("FAIL: no /chosen bootargs to extend")
new = (m.group(1).rstrip() + " " + extra).strip()
open(path, "w").write(t[:m.start()] + 'bootargs = "' + new + '"' + t[m.end():])
print(f"   bootargs: {new}")
PY
fi

dtc -q -I dts -O dtb -o "$IMG/system-inline.dtb" "$WORK/system-top-linux.dts"

# Fail loudly rather than boot a device tree that is missing the datapath, or
# one that will panic. Decompile once and check that file - piping dtc into a
# chain of greps under `set -e` is needlessly fragile.
dtc -q -I dtb -O dts -o "$WORK/system-inline.check.dts" "$IMG/system-inline.dtb"
for node in ethernet@a4080000 csi_udp_parser@a4020000 s2mm@a4030000 \
            axis_switch@a4060000 gpio@a40e0000 csi-meta@70000000; do
    grep -q "$node" "$WORK/system-inline.check.dts" \
        || { echo "device tree is missing $node" >&2; exit 1; }
done
# Everything that decides whether Linux boots at all - one check per hardware
# boot failure hit during bring-up. See check_linux_dtb.py for the post-mortems.
python3 "$ROOT/petalinux/check_linux_dtb.py" "$WORK/system-inline.check.dts"
echo "   dtb OK: $(ls -l "$IMG/system-inline.dtb" | awk '{print $5}') bytes"

# --- 3) BOOT.BIN ------------------------------------------------------------
echo "== writing the BIF"
cat > "$WORK/bootgen_inline.bif" <<EOF
the_ROM_image:
{
image {
        { type=bootimage, file=$WORK/inline.pdi }
        { type=bootloader, file=$IMG/plm.elf }
        { core=psm, file=$IMG/psmfw.elf }
}
image {
        name=aie_image, id=0x18800000
        { type=cdo, file=$AIE_CDO }
}
image {
        id = 0x1c000000, name=apu_subsystem
        { type=raw, load=0x1000, file=$IMG/system-inline.dtb }
        { core=a72-0, exception_level=el-3, trustzone, file=$IMG/bl31.elf }
        { core=a72-0, exception_level=el-2, file=$IMG/u-boot.elf }
}
}
EOF

echo "== bootgen"
bootgen -arch versal -image "$WORK/bootgen_inline.bif" -w -o "$IMG/BOOT_inline.BIN"
ls -l "$IMG/BOOT_inline.BIN"
echo
echo "BOOT_inline.BIN and system-inline.dtb are ready in:"
echo "  $IMG"
echo "Boot it the same way as #10 (JTAG: xsdb device program, then load Image/rootfs)."
