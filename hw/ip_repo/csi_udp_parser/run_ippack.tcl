# ==============================================================
# Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
# Tool Version Limit: 2025.11
# Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
# Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
# 
# ==============================================================
source -notrace "/proj/gsd/vivado/2025.2/Vitis/common/scripts/ipxhls.tcl"
set ip_out_dir "/group/bcapps/ajayad/master_thesis_rebirth/work/udp_parser/csi_udp_parser_prj/sol1/impl/ip"
set data_file "/group/bcapps/ajayad/master_thesis_rebirth/work/udp_parser/csi_udp_parser_prj/sol1/sol1_data.json"
set src_dir [file dir $data_file]
set ip_types {vitis sysgen}
set ippack_opts_dict {}
if { [catch {::ipx::utils::package_hls_ip $ip_out_dir $data_file $ip_types $src_dir $ippack_opts_dict} res] } {
  puts "Caught error:\n$::errorInfo"
  error $res
}
