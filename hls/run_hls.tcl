# ---------------------------------------------------------------------------
# run_hls.tcl — build the CSI UDP parser with Vitis HLS 2025.2.
#   vitis-run --mode hls --tcl run_hls.tcl      (2025.x)
#   vitis_hls -f run_hls.tcl                     (classic invocation)
# ---------------------------------------------------------------------------
open_project -reset csi_udp_parser_prj
set_top csi_udp_parser
add_files csi_udp_parser.cpp
add_files -tb csi_udp_parser_tb.cpp

open_solution -reset sol1 -flow_target vitis
set_part {xcvc1902-vsva2197-2MP-e-S}
create_clock -period 8 -name default   ;# 125 MHz, matches 1G MAC RX AXIS

csim_design
csynth_design
cosim_design
export_design -format ip_catalog -rtl verilog
exit
