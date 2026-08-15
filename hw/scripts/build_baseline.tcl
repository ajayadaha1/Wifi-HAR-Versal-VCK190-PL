# ---------------------------------------------------------------------------
# build_baseline.tcl — batch synth + impl + XSA export of the copied VCK190
# design, to validate the 2025.2 port (P0) and produce the baseline platform.
#   vivado -mode batch -source build_baseline.tcl -tclargs <project.xpr>
# ---------------------------------------------------------------------------
set prj [lindex $argv 0]
open_project $prj
update_compile_order -fileset sources_1

set missing [get_files -quiet -filter {IS_AVAILABLE == 0}]
if {[llength $missing]} { puts "ABORT_MISSING_SOURCES: $missing"; exit 2 }

puts "TOP [get_property TOP [current_fileset]]  PART [get_property PART [current_project]]"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "SYNTH_FAILED"; exit 3 }
puts "SYNTH_OK"

launch_runs impl_1 -to_step write_device_image -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "IMPL_FAILED"; exit 4 }
puts "IMPL_OK"

set xsa [file join [file dirname [file normalize $prj]] ps_emio_basex_baseline.xsa]
write_hw_platform -fixed -include_bit -force $xsa
puts "WROTE_XSA $xsa"
puts "BUILD_DONE"
