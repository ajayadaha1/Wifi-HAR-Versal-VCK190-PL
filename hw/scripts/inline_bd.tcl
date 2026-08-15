# inline_bd.tcl — hand-authored IP Integrator design for the inline CSI datapath.
#
# Foundation (CIPS + NoC + DDR) via board automation, then the compute datapath:
#   DDR -> axi_dma MM2S -> csi_udp_parser (HLS IP) -> csi_out -> axi_dma S2MM -> DDR
# The AI Engine is added in a follow-up step. Saves the whole design via
# write_bd_tcl so the design is captured/reproducible in one script.
#
# Run: vivado -mode batch -source inline_bd.tcl

set part       xcvc1902-vsva2197-2MP-e-S
set board      xilinx.com:vck190:part0:2.2
set scripts    [file normalize [file dirname [info script]]]
set proj_dir   [file normalize $scripts/../inline_csi_hw]
set bd_name    inline_csi

create_project -force inline_csi $proj_dir -part $part
set_property board_part $board [current_project]
set_property ip_repo_paths [list [file normalize $scripts/../ip_repo]] [current_project]
update_ip_catalog

create_bd_design $bd_name

puts "STEP: CIPS + NoC + DDR (board automation)"
create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 versal_cips_0
apply_bd_automation -rule xilinx.com:bd_rule:cips -config \
  { board_preset {Yes} configure_noc {Add new AXI NoC} num_mc_ddr {1} \
    mc_type {DDR} pl_clocks {1} pl_resets {1} } [get_bd_cells versal_cips_0]
puts "CIPS_DONE noc=[get_bd_cells -quiet -filter {VLNV=~*axi_noc*}]"

puts "STEP: add axi_dma + csi_udp_parser"
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
  CONFIG.c_include_sg {0} \
  CONFIG.c_sg_include_stscntrl_strm {0} \
  CONFIG.c_include_mm2s {1} \
  CONFIG.c_include_s2mm {1} \
  CONFIG.c_m_axis_mm2s_tdata_width {8} \
  CONFIG.c_s_axis_s2mm_tdata_width {32} \
  CONFIG.c_mm2s_burst_size {8} \
  CONFIG.c_s2mm_burst_size {8} ] [get_bd_cells axi_dma_0]
create_bd_cell -type ip -vlnv xilinx.com:hls:csi_udp_parser:1.0 csi_udp_parser_0

puts "STEP: stream wiring DMA MM2S -> parser.rx ; parser.csi_out -> DMA S2MM"
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins csi_udp_parser_0/rx]
connect_bd_intf_net [get_bd_intf_pins csi_udp_parser_0/csi_out] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
# meta_out (per-frame metadata stream) -> expose as external for now
make_bd_intf_pins_external [get_bd_intf_pins csi_udp_parser_0/meta_out]

puts "STEP: AXI-Lite control (CIPS M_AXI -> dma + parser) via automation"
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config \
  { Master {/versal_cips_0/M_AXI_FPD} Clk {Auto} } [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config \
  { Master {/versal_cips_0/M_AXI_FPD} Clk {Auto} } [get_bd_intf_pins csi_udp_parser_0/s_axi_ctrl]

puts "STEP: DMA memory masters -> NoC -> DDR via automation"
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config \
  { Slave {/axi_noc_0/S00_AXI} Clk {Auto} } [get_bd_intf_pins axi_dma_0/M_AXI_MM2S]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config \
  { Slave {/axi_noc_0/S00_AXI} Clk {Auto} } [get_bd_intf_pins axi_dma_0/M_AXI_S2MM]

puts "STEP: assign addresses + validate"
assign_bd_address
regenerate_bd_layout
save_bd_design
set rc [catch {validate_bd_design} verr]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VALIDATE_ERR: $verr" }

write_bd_tcl -force $scripts/inline_csi_bd.tcl
puts "WROTE_TCL $scripts/inline_csi_bd.tcl"
puts "INLINE_BD_DONE"
