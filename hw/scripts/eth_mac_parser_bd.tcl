
################################################################
# This is a generated script based on design: eth_mac_parser
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2025.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source eth_mac_parser_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xcvc1902-vsva2197-2MP-e-S
   set_property BOARD_PART xilinx.com:vck190:part0:2.2 [current_project]
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name eth_mac_parser

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:axi_ethernet:8.0\
xilinx.com:hls:csi_udp_parser:1.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set gmii_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gmii_rtl:1.0 gmii_0 ]

  set mdio_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mdio_rtl:1.0 mdio_0 ]

  set s_axi_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_0 ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {18} \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH {32} \
   CONFIG.HAS_BRESP {1} \
   CONFIG.HAS_BURST {0} \
   CONFIG.HAS_CACHE {0} \
   CONFIG.HAS_LOCK {0} \
   CONFIG.HAS_PROT {0} \
   CONFIG.HAS_QOS {0} \
   CONFIG.HAS_REGION {0} \
   CONFIG.HAS_RRESP {1} \
   CONFIG.HAS_WSTRB {1} \
   CONFIG.ID_WIDTH {0} \
   CONFIG.NUM_READ_OUTSTANDING {1} \
   CONFIG.NUM_READ_THREADS {1} \
   CONFIG.NUM_WRITE_OUTSTANDING {1} \
   CONFIG.NUM_WRITE_THREADS {1} \
   CONFIG.PROTOCOL {AXI4LITE} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   CONFIG.RUSER_BITS_PER_BYTE {0} \
   CONFIG.RUSER_WIDTH {0} \
   CONFIG.WUSER_BITS_PER_BYTE {0} \
   CONFIG.WUSER_WIDTH {0} \
   ] $s_axi_0

  set s_axis_txd_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis_txd_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {125000000} \
   CONFIG.HAS_TKEEP {1} \
   CONFIG.HAS_TLAST {1} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES {4} \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {0} \
   ] $s_axis_txd_0

  set s_axis_txc_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis_txc_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {125000000} \
   CONFIG.HAS_TKEEP {1} \
   CONFIG.HAS_TLAST {1} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES {4} \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {0} \
   ] $s_axis_txc_0

  set m_axis_rxs_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis_rxs_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {125000000} \
   ] $m_axis_rxs_0

  set csi_out_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 csi_out_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {125000000} \
   ] $csi_out_0

  set meta_out_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:acc_fifo_write_rtl:1.0 meta_out_0 ]

  set s_axi_ctrl_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_ctrl_0 ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {5} \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH {32} \
   CONFIG.FREQ_HZ {125000000} \
   CONFIG.HAS_BRESP {1} \
   CONFIG.HAS_BURST {0} \
   CONFIG.HAS_CACHE {0} \
   CONFIG.HAS_LOCK {0} \
   CONFIG.HAS_PROT {0} \
   CONFIG.HAS_QOS {0} \
   CONFIG.HAS_REGION {0} \
   CONFIG.HAS_RRESP {1} \
   CONFIG.HAS_WSTRB {1} \
   CONFIG.ID_WIDTH {0} \
   CONFIG.NUM_READ_OUTSTANDING {1} \
   CONFIG.NUM_READ_THREADS {1} \
   CONFIG.NUM_WRITE_OUTSTANDING {1} \
   CONFIG.NUM_WRITE_THREADS {1} \
   CONFIG.PROTOCOL {AXI4LITE} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   CONFIG.RUSER_BITS_PER_BYTE {0} \
   CONFIG.RUSER_WIDTH {0} \
   CONFIG.WUSER_BITS_PER_BYTE {0} \
   CONFIG.WUSER_WIDTH {0} \
   ] $s_axi_ctrl_0


  # Create ports
  set axis_aclk [ create_bd_port -dir I -type clk -freq_hz 125000000 axis_aclk ]
  set gtx_clk_0 [ create_bd_port -dir I -type clk -freq_hz 125000000 gtx_clk_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_TOLERANCE_HZ {1000000} \
   CONFIG.PHASE {0} \
 ] $gtx_clk_0
  set gmii_rx_clk_0 [ create_bd_port -dir I -type clk gmii_rx_clk_0 ]
  set gmii_tx_clk_0 [ create_bd_port -dir I -type clk gmii_tx_clk_0 ]
  set gmii_gtx_clk_0 [ create_bd_port -dir O -type clk gmii_gtx_clk_0 ]
  set s_axi_lite_clk_0 [ create_bd_port -dir I -type clk s_axi_lite_clk_0 ]
  set mdio_mdc_0 [ create_bd_port -dir O -type clk mdio_mdc_0 ]
  set phy_rst_n_0 [ create_bd_port -dir O -from 0 -to 0 -type rst phy_rst_n_0 ]
  set s_axi_lite_resetn_0 [ create_bd_port -dir I -type rst s_axi_lite_resetn_0 ]
  set axi_rxd_arstn_0 [ create_bd_port -dir I -type rst axi_rxd_arstn_0 ]
  set axi_rxs_arstn_0 [ create_bd_port -dir I -type rst axi_rxs_arstn_0 ]
  set axi_txc_arstn_0 [ create_bd_port -dir I -type rst axi_txc_arstn_0 ]
  set axi_txd_arstn_0 [ create_bd_port -dir I -type rst axi_txd_arstn_0 ]
  set ap_rst_n_0 [ create_bd_port -dir I -type rst ap_rst_n_0 ]
  set interrupt_0 [ create_bd_port -dir O -type intr interrupt_0 ]

  # Create instance: axi_eth_0, and set properties
  set axi_eth_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:8.0 axi_eth_0 ]

  # Create instance: csi_udp_parser_0, and set properties
  set csi_udp_parser_0 [ create_bd_cell -type ip -vlnv xilinx.com:hls:csi_udp_parser:1.0 csi_udp_parser_0 ]

  # Create interface connections
  connect_bd_intf_net -intf_net axi_eth_0_gmii [get_bd_intf_ports gmii_0] [get_bd_intf_pins axi_eth_0/gmii]
  connect_bd_intf_net -intf_net axi_eth_0_m_axis_rxd [get_bd_intf_pins axi_eth_0/m_axis_rxd] [get_bd_intf_pins csi_udp_parser_0/rx]
  connect_bd_intf_net -intf_net axi_eth_0_m_axis_rxs [get_bd_intf_ports m_axis_rxs_0] [get_bd_intf_pins axi_eth_0/m_axis_rxs]
  connect_bd_intf_net -intf_net axi_eth_0_mdio [get_bd_intf_ports mdio_0] [get_bd_intf_pins axi_eth_0/mdio]
  connect_bd_intf_net -intf_net csi_udp_parser_0_csi_out [get_bd_intf_ports csi_out_0] [get_bd_intf_pins csi_udp_parser_0/csi_out]
  connect_bd_intf_net -intf_net csi_udp_parser_0_meta_out [get_bd_intf_ports meta_out_0] [get_bd_intf_pins csi_udp_parser_0/meta_out]
  connect_bd_intf_net -intf_net s_axi_0_1 [get_bd_intf_ports s_axi_0] [get_bd_intf_pins axi_eth_0/s_axi]
  connect_bd_intf_net -intf_net s_axi_ctrl_0_1 [get_bd_intf_ports s_axi_ctrl_0] [get_bd_intf_pins csi_udp_parser_0/s_axi_ctrl]
  connect_bd_intf_net -intf_net s_axis_txc_0_1 [get_bd_intf_ports s_axis_txc_0] [get_bd_intf_pins axi_eth_0/s_axis_txc]
  connect_bd_intf_net -intf_net s_axis_txd_0_1 [get_bd_intf_ports s_axis_txd_0] [get_bd_intf_pins axi_eth_0/s_axis_txd]

  # Create port connections
  connect_bd_net -net ap_rst_n_0_1  [get_bd_ports ap_rst_n_0] \
  [get_bd_pins csi_udp_parser_0/ap_rst_n]
  connect_bd_net -net axi_eth_0_gmii_gtx_clk  [get_bd_pins axi_eth_0/gmii_gtx_clk] \
  [get_bd_ports gmii_gtx_clk_0]
  connect_bd_net -net axi_eth_0_mdio_mdc  [get_bd_pins axi_eth_0/mdio_mdc] \
  [get_bd_ports mdio_mdc_0]
  connect_bd_net -net axi_eth_0_phy_rst_n  [get_bd_pins axi_eth_0/phy_rst_n] \
  [get_bd_ports phy_rst_n_0]
  connect_bd_net -net axi_rxd_arstn_0_1  [get_bd_ports axi_rxd_arstn_0] \
  [get_bd_pins axi_eth_0/axi_rxd_arstn]
  connect_bd_net -net axi_rxs_arstn_0_1  [get_bd_ports axi_rxs_arstn_0] \
  [get_bd_pins axi_eth_0/axi_rxs_arstn]
  connect_bd_net -net axi_txc_arstn_0_1  [get_bd_ports axi_txc_arstn_0] \
  [get_bd_pins axi_eth_0/axi_txc_arstn]
  connect_bd_net -net axi_txd_arstn_0_1  [get_bd_ports axi_txd_arstn_0] \
  [get_bd_pins axi_eth_0/axi_txd_arstn]
  connect_bd_net -net axis_aclk_1  [get_bd_ports axis_aclk] \
  [get_bd_pins axi_eth_0/axis_clk] \
  [get_bd_pins csi_udp_parser_0/ap_clk]
  connect_bd_net -net csi_udp_parser_0_interrupt  [get_bd_pins csi_udp_parser_0/interrupt] \
  [get_bd_ports interrupt_0]
  connect_bd_net -net gmii_rx_clk_0_1  [get_bd_ports gmii_rx_clk_0] \
  [get_bd_pins axi_eth_0/gmii_rx_clk]
  connect_bd_net -net gmii_tx_clk_0_1  [get_bd_ports gmii_tx_clk_0] \
  [get_bd_pins axi_eth_0/gmii_tx_clk]
  connect_bd_net -net gtx_clk_0_1  [get_bd_ports gtx_clk_0] \
  [get_bd_pins axi_eth_0/gtx_clk]
  connect_bd_net -net s_axi_lite_clk_0_1  [get_bd_ports s_axi_lite_clk_0] \
  [get_bd_pins axi_eth_0/s_axi_lite_clk]
  connect_bd_net -net s_axi_lite_resetn_0_1  [get_bd_ports s_axi_lite_resetn_0] \
  [get_bd_pins axi_eth_0/s_axi_lite_resetn]

  # Create address segments


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


