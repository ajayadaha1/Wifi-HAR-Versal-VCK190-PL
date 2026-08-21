# sdt.tcl — generate a System Device Tree (SDT) from an XSA for the VCK190.
# Usage: xsct sdt.tcl <design.xsa> <sdt_outdir>
set xsa    [lindex $argv 0]
set outdir [lindex $argv 1]
exec rm -rf $outdir
sdtgen set_dt_param -xsa $xsa -dir $outdir -board_dts versal-vck190-reva-x-ebm-01-reva
sdtgen generate_sdt
