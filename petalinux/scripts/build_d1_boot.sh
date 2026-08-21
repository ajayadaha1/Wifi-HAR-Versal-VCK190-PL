#!/bin/bash
# build_d1_boot.sh - BOOT_d1.BIN for the co-gen D1 XSA (csi_mux inserted).
# Mirrors build_inline_boot.sh but: D1 PDI (vpl_gen_fixed.pdi from inline_cogen_d1.xsa),
# D1 co-gen aie CDO (package_d1/aie.merged.cdo.bin), and the ZOCL dtb
# (system-default.dtb) because D1 is an XRT/zocl platform (unlike the plain inline).
set -euo pipefail
ROOT=/group/bcapps/ajayad/master_thesis_rebirth/work
IMG=$ROOT/petalinux/petalinux/images/linux
WORK=$ROOT/petalinux/d1_boot
XSA=$ROOT/aie/feature_graph/inline_cogen_d1.xsa
AIE_CDO=$ROOT/aie/feature_graph/package_d1/aie.merged.cdo.bin
DTB=$IMG/system-default.dtb
set +eu; source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1; set -eu
command -v bootgen >/dev/null || { echo "no bootgen"; exit 1; }
for f in "$XSA" "$AIE_CDO" "$IMG/plm.elf" "$IMG/psmfw.elf" "$IMG/bl31.elf" "$IMG/u-boot.elf" "$DTB"; do
  [ -f "$f" ] || { echo "missing: $f"; exit 1; }
done
mkdir -p "$WORK"
echo "== extract D1 PDI"
unzip -o -q "$XSA" vpl_gen_fixed.pdi -d "$WORK"
mv -f "$WORK/vpl_gen_fixed.pdi" "$WORK/d1.pdi"
ls -l "$WORK/d1.pdi"
cat > "$WORK/bootgen_d1.bif" <<EOF
the_ROM_image:
{
image {
        { type=bootimage, file=$WORK/d1.pdi }
        { type=bootloader, file=$IMG/plm.elf }
        { core=psm, file=$IMG/psmfw.elf }
}
image {
        name=aie_image, id=0x18800000
        { type=cdo, file=$AIE_CDO }
}
image {
        id = 0x1c000000, name=apu_subsystem
        { type=raw, load=0x1000, file=$DTB }
        { core=a72-0, exception_level=el-3, trustzone, file=$IMG/bl31.elf }
        { core=a72-0, exception_level=el-2, file=$IMG/u-boot.elf }
}
}
EOF
echo "== bootgen"
bootgen -arch versal -image "$WORK/bootgen_d1.bif" -w -o "$IMG/BOOT_d1.BIN"
ls -l "$IMG/BOOT_d1.BIN"
echo "BOOT_D1_DONE"
