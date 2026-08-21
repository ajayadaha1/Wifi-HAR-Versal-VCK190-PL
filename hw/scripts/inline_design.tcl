# ---------------------------------------------------------------------------
# inline_design.tcl - THE inline Arch-B block design, end to end.
#
# Sourced by project_top.tcl, which is the only other tcl in this directory.
# Nothing here runs on source: it defines procs and exposes ONE entry point,
#
#     build_inline_bd
#
# which creates the block design and then closes out every dangling port.
#
# The file is in two halves:
#   1. create_root_design + its create_hier_cell_* helpers - the captured IPI
#      design: axi_ethernet -> rx_dwidth(32->8) -> csi_udp_parser -> ai_engine
#      -> s2mm -> DDR on CIPS+NoC. Machine-captured with write_bd_tcl, so it is
#      long and mechanical; treat it as generated.
#   2. add_eth_phy - the hand-written part: the SFP0 GTY front end, the TX
#      injection path, the CSI source mux, the metadata writer, clock-domain
#      crossings, AXI-Lite control and the address map. Read this half.
# ---------------------------------------------------------------------------


################################################################
# This is a generated script based on design: vitis_design
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
# source vitis_design_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xcvc1902-vsva2197-2MP-e-S
   set_property BOARD_PART xilinx.com:vck190:part0:3.4 [current_project]
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name vitis_design

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

   create_bd_design -bdsource Vitis $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

  # Add USER_COMMENTS on $design_name
  set_property USER_COMMENTS.comment0 "\t \t ======================= >>>>>>>>> An Example Versal Extensible Embedded Platform <<<<<<<<< =======================
			\t Note:
			\t --> Board preset applied to CIPS and memory controller settings
			\t --> AI Engine control path is connected to CIPS
			\t --> V++ will connect AI Engine data path automatically
			\t --> BD has VIPs on the accelerator SmartConnect IPs because IPI platform can't handle export with no slaves on SmartConnect IP.
			\t \t \t \t \t \t \t Hence VIPs are there to have at least one slave on a smart connect
			\t --> Execute TCL command : launch_simulation -scripts_only ,to establish the sim_1 source set hierarchy after successful design creation.
			\t --> For Next steps, Refer to README.md : https://github.com/Xilinx/XilinxCEDStore/tree/2025.2/ced/Xilinx/IPI/Versal_Extensible_Embedded_Platform/README.md" [get_bd_designs $design_name]

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
xilinx.com:ip:versal_cips:3.4\
xilinx.com:ip:axi_intc:4.1\
xilinx.com:inline_hdl:ilconcat:1.0\
xilinx.com:ip:clk_wizard:1.0\
xilinx.com:inline_hdl:ilconstant:1.0\
xilinx.com:ip:axi_noc:1.1\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:ai_engine:2.0\
xilinx.com:hls:csi_udp_parser:1.0\
xilinx.com:ip:axi_ethernet:8.0\
xilinx.com:ip:axis_dwidth_converter:1.1\
xilinx.com:ip:axi_vip:1.1\
xilinx.com:ip:smartconnect:1.0\
xilinx.com:hls:mm2s:1.0\
xilinx.com:hls:s2mm:1.0\
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


# Hierarchical cell: VitisRegion
proc create_hier_cell_VitisRegion { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_VitisRegion() - Empty argument(s)!"}
     return
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

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_control

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 m_axi_gmem

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 s

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_control1

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s1

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 m_axi_gmem1


  # Create pins
  create_bd_pin -dir O -from 0 -to 0 dout
  create_bd_pin -dir O -from 31 -to 0 dout1
  create_bd_pin -dir I -type clk ap_clk
  create_bd_pin -dir I -type rst ap_rst_n
  create_bd_pin -dir O -type clk ap_clk_bypass_m
  create_bd_pin -dir O -type rst ap_rst_n_bypass_m

  # Create instance: axi_intc_cascaded_1_intr_1_interrupt_concat, and set properties
  set axi_intc_cascaded_1_intr_1_interrupt_concat [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 axi_intc_cascaded_1_intr_1_interrupt_concat ]
  set_property CONFIG.NUM_PORTS {32} $axi_intc_cascaded_1_intr_1_interrupt_concat


  # Create instance: irq_const_tieoff, and set properties
  set irq_const_tieoff [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 irq_const_tieoff ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {1} \
  ] $irq_const_tieoff


  # Create instance: mm2s, and set properties
  set mm2s [ create_bd_cell -type ip -vlnv xilinx.com:hls:mm2s:1.0 mm2s ]

  # Create instance: s2mm, and set properties
  set s2mm [ create_bd_cell -type ip -vlnv xilinx.com:hls:s2mm:1.0 s2mm ]

  # Create interface connections
  connect_bd_intf_net -intf_net ai_engine_0_M00_AXIS [get_bd_intf_pins s1] [get_bd_intf_pins s2mm/s]
  connect_bd_intf_net -intf_net axi_smc_vip_hier_M01_AXI1 [get_bd_intf_pins s_axi_control1] [get_bd_intf_pins s2mm/s_axi_control]
  connect_bd_intf_net -intf_net axi_smc_vip_hier_M06_AXI [get_bd_intf_pins s_axi_control] [get_bd_intf_pins mm2s/s_axi_control]
  connect_bd_intf_net -intf_net mm2s_m_axi_gmem [get_bd_intf_pins m_axi_gmem] [get_bd_intf_pins mm2s/m_axi_gmem]
  connect_bd_intf_net -intf_net mm2s_s [get_bd_intf_pins s] [get_bd_intf_pins mm2s/s]
  connect_bd_intf_net -intf_net s2mm_m_axi_gmem [get_bd_intf_pins m_axi_gmem1] [get_bd_intf_pins s2mm/m_axi_gmem]

  # Create port connections
  connect_bd_net -net axi_intc_cascaded_1_intr_1_interrupt_concat_dout  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/dout] \
  [get_bd_pins dout1]
  connect_bd_net -net clk_wizard_0_clk_out1_o2  [get_bd_pins ap_clk] \
  [get_bd_pins s2mm/ap_clk] \
  [get_bd_pins mm2s/ap_clk] \
  [get_bd_pins ap_clk_bypass_m]
  connect_bd_net -net irq_const_tieoff_dout  [get_bd_pins irq_const_tieoff/dout] \
  [get_bd_pins dout] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In3] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In4] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In5] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In6] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In7] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In8] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In9] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In10] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In11] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In12] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In13] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In14] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In15] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In16] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In17] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In18] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In19] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In20] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In21] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In22] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In23] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In24] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In25] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In26] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In27] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In28] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In29] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In30] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In31] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In2]
  connect_bd_net -net mm2s_interrupt  [get_bd_pins mm2s/interrupt] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In1]
  connect_bd_net -net proc_sys_reset_1_peripheral_aresetn  [get_bd_pins ap_rst_n] \
  [get_bd_pins s2mm/ap_rst_n] \
  [get_bd_pins mm2s/ap_rst_n] \
  [get_bd_pins ap_rst_n_bypass_m]
  connect_bd_net -net s2mm_interrupt  [get_bd_pins s2mm/interrupt] \
  [get_bd_pins axi_intc_cascaded_1_intr_1_interrupt_concat/In0]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: axi_smc_vip_hier
proc create_hier_cell_axi_smc_vip_hier { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_axi_smc_vip_hier() - Empty argument(s)!"}
     return
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

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S00_AXI

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M00_AXI

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M01_AXI

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M06_AXI

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M01_AXI1


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: dummy_slave_0, and set properties
  set dummy_slave_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip:1.1 dummy_slave_0 ]
  set_property CONFIG.INTERFACE_MODE {SLAVE} $dummy_slave_0


  # Create instance: dummy_slave_1, and set properties
  set dummy_slave_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip:1.1 dummy_slave_1 ]
  set_property CONFIG.INTERFACE_MODE {SLAVE} $dummy_slave_1


  # Create instance: dummy_slave_2, and set properties
  set dummy_slave_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip:1.1 dummy_slave_2 ]
  set_property CONFIG.INTERFACE_MODE {SLAVE} $dummy_slave_2


  # Create instance: dummy_slave_3, and set properties
  set dummy_slave_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip:1.1 dummy_slave_3 ]
  set_property CONFIG.INTERFACE_MODE {SLAVE} $dummy_slave_3


  # Create instance: icn_ctrl, and set properties
  set icn_ctrl [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 icn_ctrl ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MI {7} \
    CONFIG.NUM_SI {1} \
  ] $icn_ctrl


  # Create instance: icn_ctrl_0, and set properties
  set icn_ctrl_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 icn_ctrl_0 ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MI {2} \
    CONFIG.NUM_SI {1} \
  ] $icn_ctrl_0


  # Create instance: icn_ctrl_1, and set properties
  set icn_ctrl_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 icn_ctrl_1 ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $icn_ctrl_1


  # Create instance: icn_ctrl_2, and set properties
  set icn_ctrl_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 icn_ctrl_2 ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $icn_ctrl_2


  # Create instance: icn_ctrl_3, and set properties
  set icn_ctrl_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 icn_ctrl_3 ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $icn_ctrl_3


  # Create interface connections
  connect_bd_intf_net -intf_net CIPS_0_M_AXI_GP0 [get_bd_intf_pins S00_AXI] [get_bd_intf_pins icn_ctrl/S00_AXI]
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins icn_ctrl/M06_AXI] [get_bd_intf_pins M06_AXI]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins icn_ctrl_0/M01_AXI] [get_bd_intf_pins M01_AXI1]
  connect_bd_intf_net -intf_net icn_ctrl_0_M00_AXI [get_bd_intf_pins dummy_slave_0/S_AXI] [get_bd_intf_pins icn_ctrl_0/M00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_1_M00_AXI [get_bd_intf_pins dummy_slave_1/S_AXI] [get_bd_intf_pins icn_ctrl_1/M00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_2_M00_AXI [get_bd_intf_pins dummy_slave_2/S_AXI] [get_bd_intf_pins icn_ctrl_2/M00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_3_M00_AXI [get_bd_intf_pins dummy_slave_3/S_AXI] [get_bd_intf_pins icn_ctrl_3/M00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_M00_AXI [get_bd_intf_pins M00_AXI] [get_bd_intf_pins icn_ctrl/M00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_M01_AXI [get_bd_intf_pins M01_AXI] [get_bd_intf_pins icn_ctrl/M01_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_M02_AXI [get_bd_intf_pins icn_ctrl/M02_AXI] [get_bd_intf_pins icn_ctrl_0/S00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_M03_AXI [get_bd_intf_pins icn_ctrl/M03_AXI] [get_bd_intf_pins icn_ctrl_1/S00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_M04_AXI [get_bd_intf_pins icn_ctrl/M04_AXI] [get_bd_intf_pins icn_ctrl_2/S00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_M05_AXI [get_bd_intf_pins icn_ctrl/M05_AXI] [get_bd_intf_pins icn_ctrl_3/S00_AXI]

  # Create port connections
  connect_bd_net -net clk_wizard_0_clk_out1_o2  [get_bd_pins aclk] \
  [get_bd_pins icn_ctrl/aclk] \
  [get_bd_pins icn_ctrl_0/aclk] \
  [get_bd_pins icn_ctrl_1/aclk] \
  [get_bd_pins dummy_slave_1/aclk] \
  [get_bd_pins icn_ctrl_2/aclk] \
  [get_bd_pins dummy_slave_2/aclk] \
  [get_bd_pins icn_ctrl_3/aclk] \
  [get_bd_pins dummy_slave_3/aclk] \
  [get_bd_pins dummy_slave_0/aclk]
  connect_bd_net -net proc_sys_reset_1_peripheral_aresetn  [get_bd_pins aresetn] \
  [get_bd_pins icn_ctrl_0/aresetn] \
  [get_bd_pins dummy_slave_1/aresetn] \
  [get_bd_pins icn_ctrl_1/aresetn] \
  [get_bd_pins dummy_slave_2/aresetn] \
  [get_bd_pins icn_ctrl_2/aresetn] \
  [get_bd_pins dummy_slave_3/aresetn] \
  [get_bd_pins icn_ctrl_3/aresetn] \
  [get_bd_pins icn_ctrl/aresetn] \
  [get_bd_pins dummy_slave_0/aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}


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
  set gt_refclk0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 gt_refclk0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {156250000} \
   ] $gt_refclk0

  set ddr4_dimm1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 ddr4_dimm1 ]

  set ddr4_dimm1_sma_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 ddr4_dimm1_sma_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {200000000} \
   ] $ddr4_dimm1_sma_clk

  set ch0_lpddr4_c0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:lpddr4_rtl:1.0 ch0_lpddr4_c0 ]

  set ch1_lpddr4_c0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:lpddr4_rtl:1.0 ch1_lpddr4_c0 ]

  set lpddr4_sma_clk1 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 lpddr4_sma_clk1 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {200321000} \
   ] $lpddr4_sma_clk1

  set ch0_lpddr4_c1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:lpddr4_rtl:1.0 ch0_lpddr4_c1 ]

  set ch1_lpddr4_c1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:lpddr4_rtl:1.0 ch1_lpddr4_c1 ]

  set lpddr4_sma_clk2 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 lpddr4_sma_clk2 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {200321000} \
   ] $lpddr4_sma_clk2

  # csi_udp_parser's meta_out was an HLS ap_fifo port; it is now a 64-bit AXIS
  # (one packed csi_meta_t per frame) so it can be written to DDR. This stays a
  # placeholder external port here and is re-targeted at the metadata writer by
  # add_eth_phy (hw/scripts/inline_eth_phy.tcl).
  set meta_out_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 meta_out_0 ]
  set_property CONFIG.FREQ_HZ {312500000} $meta_out_0

  set s_axi_ctrl_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_ctrl_0 ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {16} \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH {32} \
   CONFIG.FREQ_HZ {312500000} \
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

  set s_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 s_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {312500000} \
   ] $s_0

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
   CONFIG.FREQ_HZ {312500000} \
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
   CONFIG.FREQ_HZ {312500000} \
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
   CONFIG.FREQ_HZ {312500000} \
   ] $m_axis_rxs_0


  # Create ports
  set interrupt_0 [ create_bd_port -dir O -type intr interrupt_0 ]
  set gtx_clk_0 [ create_bd_port -dir I -type clk -freq_hz 125000000 gtx_clk_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_TOLERANCE_HZ {1000000} \
   CONFIG.PHASE {0} \
 ] $gtx_clk_0
  set gmii_rx_clk_0 [ create_bd_port -dir I -type clk -freq_hz 125000000 gmii_rx_clk_0 ]
  set gmii_tx_clk_0 [ create_bd_port -dir I -type clk -freq_hz 125000000 gmii_tx_clk_0 ]
  set gmii_gtx_clk_0 [ create_bd_port -dir O -type clk gmii_gtx_clk_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {125000000} \
 ] $gmii_gtx_clk_0
  set s_axi_lite_clk_0 [ create_bd_port -dir I -type clk s_axi_lite_clk_0 ]
  set mdio_mdc_0 [ create_bd_port -dir O -type clk mdio_mdc_0 ]
  set phy_rst_n_0 [ create_bd_port -dir O -from 0 -to 0 -type rst phy_rst_n_0 ]
  set s_axi_lite_resetn_0 [ create_bd_port -dir I -type rst s_axi_lite_resetn_0 ]
  set axi_rxd_arstn_0 [ create_bd_port -dir I -type rst axi_rxd_arstn_0 ]
  set axi_rxs_arstn_0 [ create_bd_port -dir I -type rst axi_rxs_arstn_0 ]
  set axi_txc_arstn_0 [ create_bd_port -dir I -type rst axi_txc_arstn_0 ]
  set axi_txd_arstn_0 [ create_bd_port -dir I -type rst axi_txd_arstn_0 ]

  # Create instance: CIPS_0, and set properties
  set CIPS_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 CIPS_0 ]
  set_property -dict [list \
    CONFIG.CLOCK_MODE {Custom} \
    CONFIG.DDR_MEMORY_MODE {Custom} \
    CONFIG.DEBUG_MODE {Custom} \
    CONFIG.PS_BOARD_INTERFACE {ps_pmc_fixed_io} \
    CONFIG.PS_PL_CONNECTIVITY_MODE {Custom} \
    CONFIG.PS_PMC_CONFIG { \
      CLOCK_MODE {Custom} \
      DDR_MEMORY_MODE {Custom} \
      DEBUG_MODE {Custom} \
      DESIGN_MODE {1} \
      PMC_CRP_PL0_REF_CTRL_FREQMHZ {99.999992} \
      PMC_GPIO0_MIO_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 0 .. 25}}} \
      PMC_GPIO1_MIO_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 26 .. 51}}} \
      PMC_MIO37 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA high} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_OSPI_PERIPHERAL {{ENABLE 0} {IO {PMC_MIO 0 .. 11}} {MODE Single}} \
      PMC_QSPI_COHERENCY {0} \
      PMC_QSPI_FBCLK {{ENABLE 1} {IO {PMC_MIO 6}}} \
      PMC_QSPI_PERIPHERAL_DATA_MODE {x4} \
      PMC_QSPI_PERIPHERAL_ENABLE {1} \
      PMC_QSPI_PERIPHERAL_MODE {Dual Parallel} \
      PMC_REF_CLK_FREQMHZ {33.3333} \
      PMC_SD1 {{CD_ENABLE 1} {CD_IO {PMC_MIO 28}} {POW_ENABLE 1} {POW_IO {PMC_MIO 51}} {RESET_ENABLE 0} {RESET_IO {PMC_MIO 12}} {WP_ENABLE 0} {WP_IO {PMC_MIO 1}}} \
      PMC_SD1_COHERENCY {0} \
      PMC_SD1_DATA_TRANSFER_MODE {8Bit} \
      PMC_SD1_PERIPHERAL {{CLK_100_SDR_OTAP_DLY 0x3} {CLK_200_SDR_OTAP_DLY 0x2} {CLK_50_DDR_ITAP_DLY 0x36} {CLK_50_DDR_OTAP_DLY 0x3} {CLK_50_SDR_ITAP_DLY 0x2C} {CLK_50_SDR_OTAP_DLY 0x4} {ENABLE 1} {IO\
{PMC_MIO 26 .. 36}}} \
      PMC_SD1_SLOT_TYPE {SD 3.0} \
      PMC_USE_PMC_NOC_AXI0 {1} \
      PS_BOARD_INTERFACE {ps_pmc_fixed_io} \
      PS_CAN1_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 40 .. 41}}} \
      PS_CRL_CAN1_REF_CTRL_FREQMHZ {160} \
      PS_ENET0_MDIO {{ENABLE 1} {IO {PS_MIO 24 .. 25}}} \
      PS_ENET0_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 0 .. 11}}} \
      PS_ENET1_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 12 .. 23}}} \
      PS_GEN_IPI0_ENABLE {1} \
      PS_GEN_IPI0_MASTER {A72} \
      PS_GEN_IPI1_ENABLE {1} \
      PS_GEN_IPI1_MASTER {A72} \
      PS_GEN_IPI2_ENABLE {1} \
      PS_GEN_IPI2_MASTER {A72} \
      PS_GEN_IPI3_ENABLE {1} \
      PS_GEN_IPI3_MASTER {A72} \
      PS_GEN_IPI4_ENABLE {1} \
      PS_GEN_IPI4_MASTER {A72} \
      PS_GEN_IPI5_ENABLE {1} \
      PS_GEN_IPI5_MASTER {A72} \
      PS_GEN_IPI6_ENABLE {1} \
      PS_GEN_IPI6_MASTER {A72} \
      PS_HSDP_INGRESS_TRAFFIC {AURORA} \
      PS_HSDP_MODE {HSDP0} \
      PS_I2C0_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 46 .. 47}}} \
      PS_I2C1_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 44 .. 45}}} \
      PS_IRQ_USAGE {{CH0 1} {CH1 0} {CH10 0} {CH11 0} {CH12 0} {CH13 0} {CH14 0} {CH15 0} {CH2 0} {CH3 0} {CH4 0} {CH5 0} {CH6 0} {CH7 0} {CH8 0} {CH9 0}} \
      PS_MIO19 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL disable} {SCHMITT 0} {SLEW slow} {USAGE Reserved}} \
      PS_MIO21 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL disable} {SCHMITT 0} {SLEW slow} {USAGE Reserved}} \
      PS_MIO7 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL disable} {SCHMITT 0} {SLEW slow} {USAGE Reserved}} \
      PS_MIO9 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL disable} {SCHMITT 0} {SLEW slow} {USAGE Reserved}} \
      PS_NUM_FABRIC_RESETS {1} \
      PS_PCIE_EP_RESET1_IO {PMC_MIO 38} \
      PS_PCIE_EP_RESET2_IO {PMC_MIO 39} \
      PS_PCIE_RESET {ENABLE 1} \
      PS_PL_CONNECTIVITY_MODE {Custom} \
      PS_TTC0_PERIPHERAL_ENABLE {1} \
      PS_UART0_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 42 .. 43}}} \
      PS_USB3_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 13 .. 25}}} \
      PS_USE_FPD_AXI_NOC0 {1} \
      PS_USE_FPD_AXI_NOC1 {1} \
      PS_USE_FPD_CCI_NOC {1} \
      PS_USE_M_AXI_FPD {1} \
      PS_USE_NOC_LPD_AXI0 {1} \
      PS_USE_PMCPL_CLK0 {1} \
      SMON_ALARMS {Set_Alarms_On} \
      SMON_ENABLE_TEMP_AVERAGING {0} \
      SMON_TEMP_AVERAGING_SAMPLES {0} \
    } \
    CONFIG.PS_PMC_CONFIG_APPLIED {1} \
  ] $CIPS_0


  set_property SELECTED_SIM_MODEL tlm  $CIPS_0

  # Create instance: axi_intc_cascaded_1, and set properties
  set axi_intc_cascaded_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_cascaded_1 ]
  set_property -dict [list \
    CONFIG.C_ASYNC_INTR {0xFFFFFFFF} \
    CONFIG.C_IRQ_CONNECTION {1} \
  ] $axi_intc_cascaded_1


  # Create instance: axi_intc_parent, and set properties
  set axi_intc_parent [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_parent ]
  set_property -dict [list \
    CONFIG.C_ASYNC_INTR {0xFFFFFFFF} \
    CONFIG.C_IRQ_CONNECTION {1} \
  ] $axi_intc_parent


  # Create instance: xlconcat_0, and set properties
  set xlconcat_0 [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 xlconcat_0 ]
  set_property -dict [list \
    CONFIG.IN0_WIDTH {1} \
    CONFIG.NUM_PORTS {32} \
  ] $xlconcat_0


  # Create instance: clk_wizard_0, and set properties
  set clk_wizard_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wizard_0 ]
  set_property -dict [list \
    CONFIG.CE_TYPE {HARDSYNC} \
    CONFIG.CLKOUT_DRIVES {MBUFGCE,BUFG,BUFG,BUFG,BUFG,BUFG,BUFG} \
    CONFIG.CLKOUT_DYN_PS {None,None,None,None,None,None,None} \
    CONFIG.CLKOUT_MATCHED_ROUTING {false,false,false,false,false,false,false} \
    CONFIG.CLKOUT_PORT {clk_out1,clk_out2,clk_out3,clk_out4,clk_out5,clk_out6,clk_out7} \
    CONFIG.CLKOUT_REQUESTED_DUTY_CYCLE {50.000,50.000,50.000,50.000,50.000,50.000,50.000} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {625.000,100,300.000,100.000,100.000,100.000,100.000} \
    CONFIG.CLKOUT_REQUESTED_PHASE {0.000,0.000,0.000,0.000,0.000,0.000,0.000} \
    CONFIG.CLKOUT_USED {true,true,false,false,false,false,false} \
    CONFIG.JITTER_SEL {Min_O_Jitter} \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.USE_PHASE_ALIGNMENT {true} \
  ] $clk_wizard_0


  # Create instance: xlconstant_0, and set properties
  set xlconstant_0 [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 xlconstant_0 ]

  # Create instance: cips_noc, and set properties
  set cips_noc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 cips_noc ]
  set_property -dict [list \
    CONFIG.MI_SIDEBAND_PINS {} \
    CONFIG.NUM_CLKS {10} \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_NMI {8} \
    CONFIG.NUM_NSI {0} \
    CONFIG.NUM_SI {8} \
    CONFIG.SI_SIDEBAND_PINS {} \
  ] $cips_noc


  set_property SELECTED_SIM_MODEL tlm  $cips_noc

  set_property -dict [ list \
   CONFIG.CATEGORY {aie} \
 ] [get_bd_intf_pins $cips_noc/M00_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {M04_INI {read_bw {128} write_bw {128}} M00_AXI {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}} M00_INI {read_bw {128} write_bw {128}}} \
   CONFIG.DEST_IDS {M00_AXI:0x80} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_cci} \
 ] [get_bd_intf_pins $cips_noc/S00_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {M01_INI {read_bw {128} write_bw {128}} M05_INI {read_bw {128} write_bw {128}} M00_AXI {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
   CONFIG.DEST_IDS {M00_AXI:0x80} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_cci} \
 ] [get_bd_intf_pins $cips_noc/S01_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {M02_INI {read_bw {128} write_bw {128}} M06_INI {read_bw {128} write_bw {128}} M00_AXI {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
   CONFIG.DEST_IDS {M00_AXI:0x80} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_cci} \
 ] [get_bd_intf_pins $cips_noc/S02_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {M07_INI {read_bw {128} write_bw {128}} M03_INI {read_bw {128} write_bw {128}} M00_AXI {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
   CONFIG.DEST_IDS {M00_AXI:0x80} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_cci} \
 ] [get_bd_intf_pins $cips_noc/S03_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {M00_INI {read_bw {5} write_bw {5}}} \
   CONFIG.DEST_IDS {} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_nci} \
 ] [get_bd_intf_pins $cips_noc/S04_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {M00_INI {read_bw {5} write_bw {5}}} \
   CONFIG.DEST_IDS {} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_nci} \
 ] [get_bd_intf_pins $cips_noc/S05_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {M00_INI {read_bw {5} write_bw {5}}} \
   CONFIG.DEST_IDS {} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_rpu} \
 ] [get_bd_intf_pins $cips_noc/S06_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {M04_INI {read_bw {5} write_bw {5}} M00_AXI {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}} M00_INI {read_bw {5} write_bw {5}}} \
   CONFIG.DEST_IDS {M00_AXI:0x80} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_pmc} \
 ] [get_bd_intf_pins $cips_noc/S07_AXI]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {} \
 ] [get_bd_pins $cips_noc/aclk0]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S00_AXI} \
 ] [get_bd_pins $cips_noc/aclk1]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S01_AXI} \
 ] [get_bd_pins $cips_noc/aclk2]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S02_AXI} \
 ] [get_bd_pins $cips_noc/aclk3]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S03_AXI} \
 ] [get_bd_pins $cips_noc/aclk4]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S04_AXI} \
 ] [get_bd_pins $cips_noc/aclk5]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S05_AXI} \
 ] [get_bd_pins $cips_noc/aclk6]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S06_AXI} \
 ] [get_bd_pins $cips_noc/aclk7]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S07_AXI} \
 ] [get_bd_pins $cips_noc/aclk8]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {M00_AXI} \
 ] [get_bd_pins $cips_noc/aclk9]

  # Create instance: noc_ddr4, and set properties
  set noc_ddr4 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 noc_ddr4 ]
  set_property -dict [list \
    CONFIG.CH0_DDR4_0_BOARD_INTERFACE {ddr4_dimm1} \
    CONFIG.MC_CHAN_REGION1 {DDR_LOW1} \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MCP {4} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_NSI {4} \
    CONFIG.NUM_SI {2} \
    CONFIG.sys_clk0_BOARD_INTERFACE {ddr4_dimm1_sma_clk} \
  ] $noc_ddr4


  set_property SELECTED_SIM_MODEL tlm  $noc_ddr4

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_1 {read_bw {1192} write_bw {1192} read_avg_burst {8} write_avg_burst {8}}} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {pl} \
 ] [get_bd_intf_pins $noc_ddr4/S00_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_0 {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
 ] [get_bd_intf_pins $noc_ddr4/S00_INI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_2 {read_bw {1192} write_bw {1192} read_avg_burst {8} write_avg_burst {8}}} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {pl} \
 ] [get_bd_intf_pins $noc_ddr4/S01_AXI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_1 {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
 ] [get_bd_intf_pins $noc_ddr4/S01_INI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_2 {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
 ] [get_bd_intf_pins $noc_ddr4/S02_INI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_3 {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
 ] [get_bd_intf_pins $noc_ddr4/S03_INI]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S00_AXI:S01_AXI} \
 ] [get_bd_pins $noc_ddr4/aclk0]

  # Create instance: proc_sys_reset_0, and set properties
  set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]

  # Create instance: proc_sys_reset_1, and set properties
  set proc_sys_reset_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_1 ]

  # Create instance: proc_sys_reset_2, and set properties
  set proc_sys_reset_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_2 ]

  # Create instance: proc_sys_reset_3, and set properties
  set proc_sys_reset_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_3 ]

  # Create instance: proc_sys_reset_4, and set properties
  set proc_sys_reset_4 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_4 ]

  # Create instance: ai_engine_0, and set properties
  set ai_engine_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ai_engine:2.0 ai_engine_0 ]
  # NOTE (PROJECT_STATE #17-#20): the datapath stall was NOT the column partition
  # (C_START_COLUMN, tried in #18, withdrawn in #19). The real cause is that this
  # hand-built BD never associated the AIE graph with ai_engine_0, so Vivado never
  # ran the AIE<->PL shim solution and the graph PLIO was placed on a shim the PL
  # AXIS ports do not drive -> S00_AXIS TREADY low -> whole chain stalls.
  # FIX (from the v++ link's own dr.bd.tcl, aie/feature_graph/_x/link/int):
  #   (1) HDL_ATTRIBUTE.ME_ANNOTATION {PLIO_in}/{PLIO_out} on S00_AXIS/M00_AXIS
  #       (set on the intf pins below), and
  #   (2) add_files libadf_motiononly.a SCOPED_TO_CELLS {ai_engine_0}
  #       (done in project_top.tcl after the BD validates).
  # Do NOT set C_START_COLUMN/C_NUM_COLUMN here: v++ does not, and the shim
  # solution places the PLIO itself once the graph is associated.
  set_property -dict [list \
    CONFIG.CLK_NAMES {aclk0,} \
    CONFIG.C_EN_EXT_RST {1} \
    CONFIG.NAME_MI_AXI {} \
    CONFIG.NAME_MI_AXIS {M00_AXIS,} \
    CONFIG.NAME_SI_AXI {S00_AXI,} \
    CONFIG.NAME_SI_AXIS {S00_AXIS,} \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MI_AXI {0} \
    CONFIG.NUM_MI_AXIS {1} \
    CONFIG.NUM_SI_AXI {1} \
    CONFIG.NUM_SI_AXIS {1} \
  ] $ai_engine_0


  set_property -dict [ list \
   CONFIG.TDATA_NUM_BYTES {4} \
   CONFIG.CATEGORY {PL} \
   CONFIG.IS_REGISTERED {true} \
   HDL_ATTRIBUTE.ME_ANNOTATION {PLIO_out} \
 ] [get_bd_intf_pins $ai_engine_0/M00_AXIS]

  set_property -dict [ list \
   CONFIG.CATEGORY {NOC} \
 ] [get_bd_intf_pins $ai_engine_0/S00_AXI]

  set_property -dict [ list \
   CONFIG.TDATA_NUM_BYTES {4} \
   CONFIG.CATEGORY {PL} \
   CONFIG.IS_REGISTERED {true} \
   HDL_ATTRIBUTE.ME_ANNOTATION {PLIO_in} \
 ] [get_bd_intf_pins $ai_engine_0/S00_AXIS]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {M00_AXIS:S00_AXIS} \
 ] [get_bd_pins $ai_engine_0/aclk0]

  # Create instance: noc_lpddr4, and set properties
  set noc_lpddr4 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 noc_lpddr4 ]
  set_property -dict [list \
    CONFIG.CH0_LPDDR4_0_BOARD_INTERFACE {ch0_lpddr4_c0} \
    CONFIG.CH0_LPDDR4_1_BOARD_INTERFACE {ch0_lpddr4_c1} \
    CONFIG.CH1_LPDDR4_0_BOARD_INTERFACE {ch1_lpddr4_c0} \
    CONFIG.CH1_LPDDR4_1_BOARD_INTERFACE {ch1_lpddr4_c1} \
    CONFIG.MC_CHAN_REGION0 {DDR_CH1} \
    CONFIG.NUM_CLKS {0} \
    CONFIG.NUM_MCP {4} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_NSI {4} \
    CONFIG.NUM_SI {0} \
    CONFIG.sys_clk0_BOARD_INTERFACE {lpddr4_sma_clk1} \
    CONFIG.sys_clk1_BOARD_INTERFACE {lpddr4_sma_clk2} \
  ] $noc_lpddr4


  set_property SELECTED_SIM_MODEL tlm  $noc_lpddr4

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_0 {read_bw {128} write_bw {128} read_avg_burst {4} write_avg_burst {4}}} \
 ] [get_bd_intf_pins $noc_lpddr4/S00_INI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_1 {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
 ] [get_bd_intf_pins $noc_lpddr4/S01_INI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_2 {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
 ] [get_bd_intf_pins $noc_lpddr4/S02_INI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS {MC_3 {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
 ] [get_bd_intf_pins $noc_lpddr4/S03_INI]

  # Create instance: axi_smc_vip_hier
  create_hier_cell_axi_smc_vip_hier [current_bd_instance .] axi_smc_vip_hier

  # Create instance: VitisRegion
  create_hier_cell_VitisRegion [current_bd_instance .] VitisRegion

  # Create instance: csi_udp_parser_0, and set properties
  set csi_udp_parser_0 [ create_bd_cell -type ip -vlnv xilinx.com:hls:csi_udp_parser:1.0 csi_udp_parser_0 ]

  # Create instance: axi_eth_0, and set properties
  set axi_eth_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:8.0 axi_eth_0 ]

  # Create instance: rx_dwidth, and set properties
  set rx_dwidth [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 rx_dwidth ]
  set_property CONFIG.M_TDATA_NUM_BYTES {1} $rx_dwidth


  # Create interface connections
  connect_bd_intf_net -intf_net CIPS_0_FPD_AXI_NOC_0 [get_bd_intf_pins CIPS_0/FPD_AXI_NOC_0] [get_bd_intf_pins cips_noc/S04_AXI]
  connect_bd_intf_net -intf_net CIPS_0_FPD_AXI_NOC_1 [get_bd_intf_pins CIPS_0/FPD_AXI_NOC_1] [get_bd_intf_pins cips_noc/S05_AXI]
  connect_bd_intf_net -intf_net CIPS_0_FPD_CCI_NOC_0 [get_bd_intf_pins CIPS_0/FPD_CCI_NOC_0] [get_bd_intf_pins cips_noc/S00_AXI]
  connect_bd_intf_net -intf_net CIPS_0_FPD_CCI_NOC_1 [get_bd_intf_pins CIPS_0/FPD_CCI_NOC_1] [get_bd_intf_pins cips_noc/S01_AXI]
  connect_bd_intf_net -intf_net CIPS_0_FPD_CCI_NOC_2 [get_bd_intf_pins CIPS_0/FPD_CCI_NOC_2] [get_bd_intf_pins cips_noc/S02_AXI]
  connect_bd_intf_net -intf_net CIPS_0_FPD_CCI_NOC_3 [get_bd_intf_pins CIPS_0/FPD_CCI_NOC_3] [get_bd_intf_pins cips_noc/S03_AXI]
  connect_bd_intf_net -intf_net CIPS_0_LPD_AXI_NOC_0 [get_bd_intf_pins CIPS_0/LPD_AXI_NOC_0] [get_bd_intf_pins cips_noc/S06_AXI]
  connect_bd_intf_net -intf_net CIPS_0_M_AXI_GP0 [get_bd_intf_pins CIPS_0/M_AXI_FPD] [get_bd_intf_pins axi_smc_vip_hier/S00_AXI]
  connect_bd_intf_net -intf_net CIPS_0_PMC_NOC_AXI_0 [get_bd_intf_pins CIPS_0/PMC_NOC_AXI_0] [get_bd_intf_pins cips_noc/S07_AXI]
  connect_bd_intf_net -intf_net VitisRegion_s [get_bd_intf_ports s_0] [get_bd_intf_pins VitisRegion/s]
  connect_bd_intf_net -intf_net ai_engine_0_M00_AXIS [get_bd_intf_pins ai_engine_0/M00_AXIS] [get_bd_intf_pins VitisRegion/s1]
  connect_bd_intf_net -intf_net axi_eth_0_gmii [get_bd_intf_ports gmii_0] [get_bd_intf_pins axi_eth_0/gmii]
  connect_bd_intf_net -intf_net axi_eth_0_m_axis_rxd [get_bd_intf_pins axi_eth_0/m_axis_rxd] [get_bd_intf_pins rx_dwidth/S_AXIS]
  connect_bd_intf_net -intf_net axi_eth_0_m_axis_rxs [get_bd_intf_ports m_axis_rxs_0] [get_bd_intf_pins axi_eth_0/m_axis_rxs]
  connect_bd_intf_net -intf_net axi_eth_0_mdio [get_bd_intf_ports mdio_0] [get_bd_intf_pins axi_eth_0/mdio]
  connect_bd_intf_net -intf_net axi_smc_vip_hier_M01_AXI1 [get_bd_intf_pins VitisRegion/s_axi_control1] [get_bd_intf_pins axi_smc_vip_hier/M01_AXI1]
  connect_bd_intf_net -intf_net axi_smc_vip_hier_M06_AXI [get_bd_intf_pins VitisRegion/s_axi_control] [get_bd_intf_pins axi_smc_vip_hier/M06_AXI]
  connect_bd_intf_net -intf_net cips_noc_M00_AXI [get_bd_intf_pins cips_noc/M00_AXI] [get_bd_intf_pins ai_engine_0/S00_AXI]
  connect_bd_intf_net -intf_net cips_noc_M00_INI [get_bd_intf_pins cips_noc/M00_INI] [get_bd_intf_pins noc_ddr4/S00_INI]
  connect_bd_intf_net -intf_net cips_noc_M01_INI [get_bd_intf_pins cips_noc/M01_INI] [get_bd_intf_pins noc_ddr4/S01_INI]
  connect_bd_intf_net -intf_net cips_noc_M02_INI [get_bd_intf_pins cips_noc/M02_INI] [get_bd_intf_pins noc_ddr4/S02_INI]
  connect_bd_intf_net -intf_net cips_noc_M03_INI [get_bd_intf_pins cips_noc/M03_INI] [get_bd_intf_pins noc_ddr4/S03_INI]
  connect_bd_intf_net -intf_net cips_noc_M04_INI [get_bd_intf_pins cips_noc/M04_INI] [get_bd_intf_pins noc_lpddr4/S00_INI]
  connect_bd_intf_net -intf_net cips_noc_M05_INI [get_bd_intf_pins cips_noc/M05_INI] [get_bd_intf_pins noc_lpddr4/S01_INI]
  connect_bd_intf_net -intf_net cips_noc_M06_INI [get_bd_intf_pins cips_noc/M06_INI] [get_bd_intf_pins noc_lpddr4/S02_INI]
  connect_bd_intf_net -intf_net cips_noc_M07_INI [get_bd_intf_pins cips_noc/M07_INI] [get_bd_intf_pins noc_lpddr4/S03_INI]
  connect_bd_intf_net -intf_net csi_udp_parser_0_csi_out [get_bd_intf_pins csi_udp_parser_0/csi_out] [get_bd_intf_pins ai_engine_0/S00_AXIS]
  connect_bd_intf_net -intf_net csi_udp_parser_0_meta_out [get_bd_intf_ports meta_out_0] [get_bd_intf_pins csi_udp_parser_0/meta_out]
  connect_bd_intf_net -intf_net ddr4_dimm1_sma_clk_1 [get_bd_intf_ports ddr4_dimm1_sma_clk] [get_bd_intf_pins noc_ddr4/sys_clk0]
  connect_bd_intf_net -intf_net gt_refclk0_0 [get_bd_intf_ports gt_refclk0] [get_bd_intf_pins CIPS_0/gt_refclk0]
  connect_bd_intf_net -intf_net icn_ctrl_M00_AXI [get_bd_intf_pins axi_intc_cascaded_1/s_axi] [get_bd_intf_pins axi_smc_vip_hier/M00_AXI]
  connect_bd_intf_net -intf_net icn_ctrl_M01_AXI [get_bd_intf_pins axi_intc_parent/s_axi] [get_bd_intf_pins axi_smc_vip_hier/M01_AXI]
  connect_bd_intf_net -intf_net lpddr4_sma_clk1_1 [get_bd_intf_ports lpddr4_sma_clk1] [get_bd_intf_pins noc_lpddr4/sys_clk0]
  connect_bd_intf_net -intf_net lpddr4_sma_clk2_1 [get_bd_intf_ports lpddr4_sma_clk2] [get_bd_intf_pins noc_lpddr4/sys_clk1]
  connect_bd_intf_net -intf_net mm2s_m_axi_gmem [get_bd_intf_pins VitisRegion/m_axi_gmem] [get_bd_intf_pins noc_ddr4/S00_AXI]
  connect_bd_intf_net -intf_net noc_ddr4_CH0_DDR4_0 [get_bd_intf_ports ddr4_dimm1] [get_bd_intf_pins noc_ddr4/CH0_DDR4_0]
  connect_bd_intf_net -intf_net noc_lpddr4_CH0_LPDDR4_0 [get_bd_intf_ports ch0_lpddr4_c0] [get_bd_intf_pins noc_lpddr4/CH0_LPDDR4_0]
  connect_bd_intf_net -intf_net noc_lpddr4_CH0_LPDDR4_1 [get_bd_intf_ports ch0_lpddr4_c1] [get_bd_intf_pins noc_lpddr4/CH0_LPDDR4_1]
  connect_bd_intf_net -intf_net noc_lpddr4_CH1_LPDDR4_0 [get_bd_intf_ports ch1_lpddr4_c0] [get_bd_intf_pins noc_lpddr4/CH1_LPDDR4_0]
  connect_bd_intf_net -intf_net noc_lpddr4_CH1_LPDDR4_1 [get_bd_intf_ports ch1_lpddr4_c1] [get_bd_intf_pins noc_lpddr4/CH1_LPDDR4_1]
  connect_bd_intf_net -intf_net rx_dwidth_M_AXIS [get_bd_intf_pins rx_dwidth/M_AXIS] [get_bd_intf_pins csi_udp_parser_0/rx]
  connect_bd_intf_net -intf_net s2mm_m_axi_gmem [get_bd_intf_pins VitisRegion/m_axi_gmem1] [get_bd_intf_pins noc_ddr4/S01_AXI]
  connect_bd_intf_net -intf_net s_axi_0_1 [get_bd_intf_ports s_axi_0] [get_bd_intf_pins axi_eth_0/s_axi]
  connect_bd_intf_net -intf_net s_axi_ctrl_0_1 [get_bd_intf_ports s_axi_ctrl_0] [get_bd_intf_pins csi_udp_parser_0/s_axi_ctrl]
  connect_bd_intf_net -intf_net s_axis_txc_0_1 [get_bd_intf_ports s_axis_txc_0] [get_bd_intf_pins axi_eth_0/s_axis_txc]
  connect_bd_intf_net -intf_net s_axis_txd_0_1 [get_bd_intf_ports s_axis_txd_0] [get_bd_intf_pins axi_eth_0/s_axis_txd]

  # Create port connections
  connect_bd_net -net CIPS_0_fpd_axi_noc_axi0_clk  [get_bd_pins CIPS_0/fpd_axi_noc_axi0_clk] \
  [get_bd_pins cips_noc/aclk5]
  connect_bd_net -net CIPS_0_fpd_axi_noc_axi1_clk  [get_bd_pins CIPS_0/fpd_axi_noc_axi1_clk] \
  [get_bd_pins cips_noc/aclk6]
  connect_bd_net -net CIPS_0_fpd_cci_noc_axi0_clk  [get_bd_pins CIPS_0/fpd_cci_noc_axi0_clk] \
  [get_bd_pins cips_noc/aclk1]
  connect_bd_net -net CIPS_0_fpd_cci_noc_axi1_clk  [get_bd_pins CIPS_0/fpd_cci_noc_axi1_clk] \
  [get_bd_pins cips_noc/aclk2]
  connect_bd_net -net CIPS_0_fpd_cci_noc_axi2_clk  [get_bd_pins CIPS_0/fpd_cci_noc_axi2_clk] \
  [get_bd_pins cips_noc/aclk3]
  connect_bd_net -net CIPS_0_fpd_cci_noc_axi3_clk  [get_bd_pins CIPS_0/fpd_cci_noc_axi3_clk] \
  [get_bd_pins cips_noc/aclk4]
  connect_bd_net -net CIPS_0_lpd_axi_noc_clk  [get_bd_pins CIPS_0/lpd_axi_noc_clk] \
  [get_bd_pins cips_noc/aclk7]
  connect_bd_net -net CIPS_0_pl_clk0  [get_bd_pins CIPS_0/pl0_ref_clk] \
  [get_bd_pins clk_wizard_0/clk_in1]
  connect_bd_net -net CIPS_0_pl_resetn1  [get_bd_pins CIPS_0/pl0_resetn] \
  [get_bd_pins clk_wizard_0/resetn] \
  [get_bd_pins proc_sys_reset_0/ext_reset_in] \
  [get_bd_pins proc_sys_reset_1/ext_reset_in] \
  [get_bd_pins proc_sys_reset_2/ext_reset_in] \
  [get_bd_pins proc_sys_reset_3/ext_reset_in] \
  [get_bd_pins proc_sys_reset_4/ext_reset_in]
  connect_bd_net -net CIPS_0_pmc_axi_noc_axi0_clk  [get_bd_pins CIPS_0/pmc_axi_noc_axi0_clk] \
  [get_bd_pins cips_noc/aclk8]
  connect_bd_net -net VitisRegion_ap_clk_bypass_m  [get_bd_pins VitisRegion/ap_clk_bypass_m] \
  [get_bd_pins noc_ddr4/aclk0] \
  [get_bd_pins ai_engine_0/aclk0] \
  [get_bd_pins csi_udp_parser_0/ap_clk] \
  [get_bd_pins axi_eth_0/axis_clk] \
  [get_bd_pins rx_dwidth/aclk]
  connect_bd_net -net VitisRegion_ap_rst_n_bypass_m  [get_bd_pins VitisRegion/ap_rst_n_bypass_m] \
  [get_bd_pins ai_engine_0/aresetn0] \
  [get_bd_pins csi_udp_parser_0/ap_rst_n] \
  [get_bd_pins rx_dwidth/aresetn]
  connect_bd_net -net ai_engine_0_s00_axi_aclk  [get_bd_pins ai_engine_0/s00_axi_aclk] \
  [get_bd_pins cips_noc/aclk9]
  connect_bd_net -net axi_eth_0_gmii_gtx_clk  [get_bd_pins axi_eth_0/gmii_gtx_clk] \
  [get_bd_ports gmii_gtx_clk_0]
  connect_bd_net -net axi_eth_0_mdio_mdc  [get_bd_pins axi_eth_0/mdio_mdc] \
  [get_bd_ports mdio_mdc_0]
  connect_bd_net -net axi_eth_0_phy_rst_n  [get_bd_pins axi_eth_0/phy_rst_n] \
  [get_bd_ports phy_rst_n_0]
  connect_bd_net -net axi_intc_0_irq  [get_bd_pins axi_intc_parent/irq] \
  [get_bd_pins CIPS_0/pl_ps_irq0]
  connect_bd_net -net axi_intc_cascaded_1_intr_1_interrupt_concat_dout  [get_bd_pins VitisRegion/dout1] \
  [get_bd_pins axi_intc_cascaded_1/intr]
  connect_bd_net -net axi_intc_cascaded_1_irq  [get_bd_pins axi_intc_cascaded_1/irq] \
  [get_bd_pins xlconcat_0/In31]
  connect_bd_net -net axi_rxd_arstn_0_1  [get_bd_ports axi_rxd_arstn_0] \
  [get_bd_pins axi_eth_0/axi_rxd_arstn]
  connect_bd_net -net axi_rxs_arstn_0_1  [get_bd_ports axi_rxs_arstn_0] \
  [get_bd_pins axi_eth_0/axi_rxs_arstn]
  connect_bd_net -net axi_txc_arstn_0_1  [get_bd_ports axi_txc_arstn_0] \
  [get_bd_pins axi_eth_0/axi_txc_arstn]
  connect_bd_net -net axi_txd_arstn_0_1  [get_bd_ports axi_txd_arstn_0] \
  [get_bd_pins axi_eth_0/axi_txd_arstn]
  connect_bd_net -net clk_wizard_0_clk_out1_o1  [get_bd_pins clk_wizard_0/clk_out1_o1] \
  [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
  connect_bd_net -net clk_wizard_0_clk_out1_o2  [get_bd_pins clk_wizard_0/clk_out1_o2] \
  [get_bd_pins cips_noc/aclk0] \
  [get_bd_pins proc_sys_reset_1/slowest_sync_clk] \
  [get_bd_pins axi_intc_cascaded_1/s_axi_aclk] \
  [get_bd_pins axi_intc_parent/s_axi_aclk] \
  [get_bd_pins axi_smc_vip_hier/aclk] \
  [get_bd_pins CIPS_0/m_axi_fpd_aclk] \
  [get_bd_pins VitisRegion/ap_clk]
  connect_bd_net -net clk_wizard_0_clk_out1_o3  [get_bd_pins clk_wizard_0/clk_out1_o3] \
  [get_bd_pins proc_sys_reset_2/slowest_sync_clk]
  connect_bd_net -net clk_wizard_0_clk_out1_o4  [get_bd_pins clk_wizard_0/clk_out1_o4] \
  [get_bd_pins proc_sys_reset_3/slowest_sync_clk]
  connect_bd_net -net clk_wizard_0_clk_out2  [get_bd_pins clk_wizard_0/clk_out2] \
  [get_bd_pins proc_sys_reset_4/slowest_sync_clk]
  connect_bd_net -net clk_wizard_0_locked  [get_bd_pins clk_wizard_0/locked] \
  [get_bd_pins proc_sys_reset_0/dcm_locked] \
  [get_bd_pins proc_sys_reset_1/dcm_locked] \
  [get_bd_pins proc_sys_reset_2/dcm_locked] \
  [get_bd_pins proc_sys_reset_3/dcm_locked] \
  [get_bd_pins proc_sys_reset_4/dcm_locked]
  connect_bd_net -net csi_udp_parser_0_interrupt  [get_bd_pins csi_udp_parser_0/interrupt] \
  [get_bd_ports interrupt_0]
  connect_bd_net -net gmii_rx_clk_0_1  [get_bd_ports gmii_rx_clk_0] \
  [get_bd_pins axi_eth_0/gmii_rx_clk]
  connect_bd_net -net gmii_tx_clk_0_1  [get_bd_ports gmii_tx_clk_0] \
  [get_bd_pins axi_eth_0/gmii_tx_clk]
  connect_bd_net -net gtx_clk_0_1  [get_bd_ports gtx_clk_0] \
  [get_bd_pins axi_eth_0/gtx_clk]
  connect_bd_net -net irq_const_tieoff_dout  [get_bd_pins VitisRegion/dout] \
  [get_bd_pins xlconcat_0/In0] \
  [get_bd_pins xlconcat_0/In1] \
  [get_bd_pins xlconcat_0/In2] \
  [get_bd_pins xlconcat_0/In3] \
  [get_bd_pins xlconcat_0/In4] \
  [get_bd_pins xlconcat_0/In5] \
  [get_bd_pins xlconcat_0/In6] \
  [get_bd_pins xlconcat_0/In7] \
  [get_bd_pins xlconcat_0/In8] \
  [get_bd_pins xlconcat_0/In9] \
  [get_bd_pins xlconcat_0/In10] \
  [get_bd_pins xlconcat_0/In11] \
  [get_bd_pins xlconcat_0/In12] \
  [get_bd_pins xlconcat_0/In13] \
  [get_bd_pins xlconcat_0/In14] \
  [get_bd_pins xlconcat_0/In15] \
  [get_bd_pins xlconcat_0/In16] \
  [get_bd_pins xlconcat_0/In17] \
  [get_bd_pins xlconcat_0/In18] \
  [get_bd_pins xlconcat_0/In19] \
  [get_bd_pins xlconcat_0/In20] \
  [get_bd_pins xlconcat_0/In21] \
  [get_bd_pins xlconcat_0/In22] \
  [get_bd_pins xlconcat_0/In23] \
  [get_bd_pins xlconcat_0/In24] \
  [get_bd_pins xlconcat_0/In25] \
  [get_bd_pins xlconcat_0/In26] \
  [get_bd_pins xlconcat_0/In27] \
  [get_bd_pins xlconcat_0/In28] \
  [get_bd_pins xlconcat_0/In29] \
  [get_bd_pins xlconcat_0/In30]
  connect_bd_net -net proc_sys_reset_1_peripheral_aresetn  [get_bd_pins proc_sys_reset_1/peripheral_aresetn] \
  [get_bd_pins axi_intc_cascaded_1/s_axi_aresetn] \
  [get_bd_pins axi_intc_parent/s_axi_aresetn] \
  [get_bd_pins axi_smc_vip_hier/aresetn] \
  [get_bd_pins VitisRegion/ap_rst_n]
  connect_bd_net -net s_axi_lite_clk_0_1  [get_bd_ports s_axi_lite_clk_0] \
  [get_bd_pins axi_eth_0/s_axi_lite_clk]
  connect_bd_net -net s_axi_lite_resetn_0_1  [get_bd_ports s_axi_lite_resetn_0] \
  [get_bd_pins axi_eth_0/s_axi_lite_resetn]
  connect_bd_net -net xlconcat_0_dout  [get_bd_pins xlconcat_0/dout] \
  [get_bd_pins axi_intc_parent/intr]
  connect_bd_net -net xlconstant_0_dout  [get_bd_pins xlconstant_0/dout] \
  [get_bd_pins clk_wizard_0/clk_out1_clr_n] \
  [get_bd_pins clk_wizard_0/clk_out1_ce]

  # Create address segments
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_AXI_NOC_0] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_AXI_NOC_0] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW1] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_AXI_NOC_1] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_AXI_NOC_1] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW1] -force
  assign_bd_address -offset 0x020000000000 -range 0x000100000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_0] [get_bd_addr_segs ai_engine_0/S00_AXI/AIE_ARRAY_0] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_0] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_0] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW1] -force
  assign_bd_address -offset 0x050000000000 -range 0x000200000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_0] [get_bd_addr_segs noc_lpddr4/S00_INI/C0_DDR_CH1x2] -force
  assign_bd_address -offset 0x020000000000 -range 0x000100000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_1] [get_bd_addr_segs ai_engine_0/S00_AXI/AIE_ARRAY_0] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_1] [get_bd_addr_segs noc_ddr4/S01_INI/C1_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_1] [get_bd_addr_segs noc_ddr4/S01_INI/C1_DDR_LOW1] -force
  assign_bd_address -offset 0x050000000000 -range 0x000200000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_1] [get_bd_addr_segs noc_lpddr4/S01_INI/C1_DDR_CH1x2] -force
  assign_bd_address -offset 0x020000000000 -range 0x000100000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_2] [get_bd_addr_segs ai_engine_0/S00_AXI/AIE_ARRAY_0] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_2] [get_bd_addr_segs noc_ddr4/S02_INI/C2_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_2] [get_bd_addr_segs noc_ddr4/S02_INI/C2_DDR_LOW1] -force
  assign_bd_address -offset 0x050000000000 -range 0x000200000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_2] [get_bd_addr_segs noc_lpddr4/S02_INI/C2_DDR_CH1x2] -force
  assign_bd_address -offset 0x020000000000 -range 0x000100000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_3] [get_bd_addr_segs ai_engine_0/S00_AXI/AIE_ARRAY_0] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_3] [get_bd_addr_segs noc_ddr4/S03_INI/C3_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_3] [get_bd_addr_segs noc_ddr4/S03_INI/C3_DDR_LOW1] -force
  assign_bd_address -offset 0x050000000000 -range 0x000200000000 -target_address_space [get_bd_addr_spaces CIPS_0/FPD_CCI_NOC_3] [get_bd_addr_segs noc_lpddr4/S03_INI/C3_DDR_CH1x2] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces CIPS_0/LPD_AXI_NOC_0] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces CIPS_0/LPD_AXI_NOC_0] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW1] -force
  assign_bd_address -offset 0xA4040000 -range 0x00010000 -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] [get_bd_addr_segs axi_intc_cascaded_1/S_AXI/Reg] -force
  assign_bd_address -offset 0xA4050000 -range 0x00010000 -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] [get_bd_addr_segs axi_intc_parent/S_AXI/Reg] -force
  assign_bd_address -offset 0xA4000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] [get_bd_addr_segs VitisRegion/mm2s/s_axi_control/Reg] -with_locktype global -force
  assign_bd_address -offset 0xA4010000 -range 0x00010000 -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] [get_bd_addr_segs VitisRegion/s2mm/s_axi_control/Reg] -with_locktype global -force
  assign_bd_address -offset 0x020000000000 -range 0x000100000000 -target_address_space [get_bd_addr_spaces CIPS_0/PMC_NOC_AXI_0] [get_bd_addr_segs ai_engine_0/S00_AXI/AIE_ARRAY_0] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces CIPS_0/PMC_NOC_AXI_0] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces CIPS_0/PMC_NOC_AXI_0] [get_bd_addr_segs noc_ddr4/S00_INI/C0_DDR_LOW1] -force
  assign_bd_address -offset 0x050000000000 -range 0x000200000000 -target_address_space [get_bd_addr_spaces CIPS_0/PMC_NOC_AXI_0] [get_bd_addr_segs noc_lpddr4/S00_INI/C0_DDR_CH1x2] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces VitisRegion/mm2s/Data_m_axi_gmem] [get_bd_addr_segs noc_ddr4/S00_AXI/C1_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces VitisRegion/mm2s/Data_m_axi_gmem] [get_bd_addr_segs noc_ddr4/S00_AXI/C1_DDR_LOW1] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces VitisRegion/s2mm/Data_m_axi_gmem] [get_bd_addr_segs noc_ddr4/S01_AXI/C2_DDR_LOW0] -force
  assign_bd_address -offset 0x000800000000 -range 0x000180000000 -target_address_space [get_bd_addr_spaces VitisRegion/s2mm/Data_m_axi_gmem] [get_bd_addr_segs noc_ddr4/S01_AXI/C2_DDR_LOW1] -force
  assign_bd_address -offset 0x00000000 -range 0x00000080 -target_address_space [get_bd_addr_spaces s_axi_ctrl_0] [get_bd_addr_segs csi_udp_parser_0/s_axi_ctrl/Reg] -force

  # Exclude Address Segments
  exclude_bd_addr_seg -offset 0xA4000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] [get_bd_addr_segs axi_smc_vip_hier/dummy_slave_0/S_AXI/Reg]
  exclude_bd_addr_seg -offset 0xA4010000 -range 0x00010000 -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] [get_bd_addr_segs axi_smc_vip_hier/dummy_slave_1/S_AXI/Reg]
  exclude_bd_addr_seg -offset 0xA4020000 -range 0x00010000 -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] [get_bd_addr_segs axi_smc_vip_hier/dummy_slave_2/S_AXI/Reg]
  exclude_bd_addr_seg -offset 0xA4030000 -range 0x00010000 -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] [get_bd_addr_segs axi_smc_vip_hier/dummy_slave_3/S_AXI/Reg]


  # Restore current instance
  current_bd_instance $oldCurInst

  # Create PFM attributes
  set_property PFM_NAME {xilinx.com:vck190:versal_extensible_platform_base:1.0} [get_files [current_bd_design].bd]


  validate_bd_design
  save_bd_design
}
# End of create_root_design()

# ---------------------------------------------------------------------------
# inline_eth_phy.tcl - implements add_eth_phy for build_inline_xsa.tcl (todo #5).
#
# inline_full_bd.tcl builds the inline Arch-B chain
#     axi_eth_0 -> rx_dwidth(32->8) -> csi_udp_parser_0 -> ai_engine_0 -> s2mm -> DDR
# but leaves the MAC's PHY side, its AXI-Lite control, and several datapath
# stubs as dangling external ports, so the design can synthesise but not
# implement. This file closes all of them.
#
# WHAT GETS ADDED
#   PHY (SFP0, 1000BASE-X):  axi_eth_0 is reconfigured from GMII to 1000BaseX on
#     an external GTY, and hw/hdl/eth_gt_phy.v supplies that GTY. axi_ethernet
#     8.0 cannot contain its own transceiver (CONFIG.GTinEx is locked true), and
#     it no longer exposes the bundled gt_tx_interface / gt_rx_interface that the
#     2024.1 AMD reference design connects a gt_quad_base to - only ~30 discrete
#     GT pins - so the PHY is a Verilog wrapper around the gtwiz_versal IP,
#     modelled on the IP's own example design. See hw/hdl/eth_gt_phy.v,
#     hw/ip/csi_eth_gtwiz.xci and hw/ref_axi_eth_example/.
#
#     Do NOT be tempted by CONFIG.USE_BOARD_FLOW: the only VCK190 board
#     interface for this IP is typed sgmii_rtl and silently forces
#     ENABLE_LVDS=true, which builds an LVDS PHY whose IO pblock collides with
#     LPDDR4 (impl dies in opt_design, "[Mig 66-103] ... PBlock issue").
#
#   CLOCKING:  the MAC and everything on its side run in the 100 MHz domain
#     (clk_wizard_0/clk_out2, reset proc_sys_reset_4 - previously unused). The
#     CSI datapath stays at clk_out1_o2 (~312.5 MHz). 32-bit AXIS at 100 MHz is
#     400 MB/s, comfortably above the 125 MB/s a 1G line needs, and it keeps the
#     MAC off the fast clock where it would be a timing risk. rx_cdc_fifo does
#     the 100 -> 312.5 MHz crossing BEFORE the 32->8 width conversion, because
#     8-bit at 100 MHz would only be 100 MB/s and would under-run the line.
#
#   TX / RX-STATUS:  the CSI datapath is RX-only, but TX is populated anyway -
#     from DDR, via two more instances of the packaged mm2s mover (mm2s_txd for
#     the frame, mm2s_txc for the MAC's 5-word control packet) crossing into the
#     MAC's clock through async FIFOs. That is what makes the design
#     self-testable: with eth_loopback_gpio putting the PHY in near-end loopback,
#     software can push a synthetic nexmon CSI frame and have it return through
#     the whole real chain with no Pi and no optics. m_axis_rxs is drained by
#     axis_sink, because an unconsumed status stream back-pressures and stalls RX.
#     No axi_dma is instantiated: the Linux axienet driver is therefore not used,
#     and the MAC is brought up by writing its AXI-Lite registers directly. That
#     keeps the PS out of the CSI datapath, which is the point of Arch-B.
#
#   CSI SOURCE MUX:  csi_mux (axis_switch, control-register routing) selects the
#     AIE's input between csi_udp_parser_0 (live Ethernet) and VitisRegion/s
#     (the mm2s DDR mover). The mm2s stream was orphaned when the parser took
#     over the AIE input; muxing it back in keeps the validated DDR->AIE->DDR
#     golden test runnable on this same bitstream.
#
#   METADATA:  csi_udp_parser_0/meta_out is now a 64-bit AXIS (one packed
#     csi_meta_t per frame - see udp_parser/csi_udp_parser.hpp). It is narrowed
#     to 32 bits and written to DDR by s2mm_meta, a third instance of the
#     packaged s2mm mover. Run it with size=2 and auto-restart and DDR holds the
#     latest {seq, rssi, n_sub, chanspec, core_spatial}; rssi is element 7 of the
#     ruview 8-feature vector, so the host needs it.
#
# The proc is deliberately failure-tolerant per step: every action goes through
# `_step`, which records rather than aborts, so one Vivado run reports ALL the
# problems instead of stopping at the first. add_eth_phy still errors out at the
# end if anything failed, so no half-wired XSA can be written.
# ---------------------------------------------------------------------------

# --- clock / reset nets of the existing design (see inline_full_bd.tcl) ------
# CSI datapath domain (~312.5 MHz), shared with icn_ctrl and the Vitis region.
set ::FAST_CLK   {VitisRegion/ap_clk_bypass_m}
set ::FAST_RSTN  {VitisRegion/ap_rst_n_bypass_m}
# MAC / PHY control domain (100 MHz).
set ::SLOW_CLK   {clk_wizard_0/clk_out2}
set ::SLOW_RSTN  {proc_sys_reset_4/peripheral_aresetn}

set ::ETH_ERRORS {}

proc _step {desc script} {
    if {[catch {uplevel 1 $script} err]} {
        lappend ::ETH_ERRORS "$desc: $err"
        puts "ETH_PHY_FAIL  $desc\n              $err"
    } else {
        puts "ETH_PHY_OK    $desc"
    }
}

# Connect a set of pins into one net. The pin paths are resolved in a single
# get_bd_pins call: connect_bd_net needs real BD objects, and routing them
# through `eval` would flatten them to plain strings, which it rejects.
proc _net {name args} {
    connect_bd_net -net $name [get_bd_pins $args]
}

proc _intf {name a b} {
    connect_bd_intf_net -intf_net $name [get_bd_intf_pins $a] [get_bd_intf_pins $b]
}

# Drop an interface/scalar port together with whatever net hangs off it.
proc _drop_intf_port {p} {
    set port [get_bd_intf_ports -quiet $p]
    if {$port eq ""} { return }
    set net [get_bd_intf_nets -quiet -of_objects $port]
    if {$net ne ""} { delete_bd_objs $net }
    delete_bd_objs $port
}

proc _drop_port {p} {
    set port [get_bd_ports -quiet $p]
    if {$port eq ""} { return }
    set net [get_bd_nets -quiet -of_objects $port]
    if {$net ne ""} { delete_bd_objs $net }
    delete_bd_objs $port
}

proc _drop_intf_net {n} {
    set net [get_bd_intf_nets -quiet $n]
    if {$net ne ""} { delete_bd_objs $net }
}


proc add_eth_phy {} {
    current_bd_instance /
    set ::ETH_ERRORS {}

    # ---------------------------------------------------------------------
    # 1) remove the graft placeholders
    # ---------------------------------------------------------------------
    _step "drop placeholder interface ports" {
        foreach p {gmii_0 mdio_0 s_axi_0 s_axis_txd_0 s_axis_txc_0 m_axis_rxs_0
                   meta_out_0 s_0 s_axi_ctrl_0} {
            _drop_intf_port $p
        }
    }
    _step "drop placeholder scalar ports" {
        foreach p {interrupt_0 gtx_clk_0 gmii_rx_clk_0 gmii_tx_clk_0 gmii_gtx_clk_0
                   mdio_mdc_0 phy_rst_n_0 s_axi_lite_clk_0 s_axi_lite_resetn_0
                   axi_rxd_arstn_0 axi_rxs_arstn_0 axi_txc_arstn_0 axi_txd_arstn_0} {
            _drop_port $p
        }
    }
    # axis_clk was tied to the fast domain by the graft; the MAC moves to 100 MHz.
    _step "detach axi_eth_0 from the fast clock" {
        disconnect_bd_net [get_bd_nets -of_objects [get_bd_pins axi_eth_0/axis_clk]] \
                          [get_bd_pins axi_eth_0/axis_clk]
    }

    # ---------------------------------------------------------------------
    # 2) MAC: GMII external PHY -> internal 1000BASE-X PCS/PMA on a GTY
    # ---------------------------------------------------------------------
    # NOTE: do NOT set USE_BOARD_FLOW / ETHERNET_BOARD_INTERFACE here. The only
    # VCK190 board interface for this IP (bank105_gty2_axi_eth) is typed
    # sgmii_rtl and silently forces ENABLE_LVDS=true, which builds an LVDS PHY
    # whose IO pblock collides with LPDDR4 (impl dies in opt_design with
    # "[Mig 66-103] Regeneration failed because of PBlock issue").
    _step "reconfigure axi_eth_0 as 1000BaseX on an external GTY" {
        set_property -dict [list \
            CONFIG.PHYADDR      {2} \
            CONFIG.PHY_TYPE     {1000BaseX} \
            CONFIG.ENABLE_LVDS  {false} \
            CONFIG.gt_type      {GTY} \
            CONFIG.gtlocation   {X0Y3} \
            CONFIG.gtrefclkrate {156.25} \
        ] [get_bd_cells axi_eth_0]
        foreach p {PHY_TYPE ENABLE_LVDS GTinEx gtlocation gtrefclkrate} {
            puts "              axi_eth_0.$p = [get_property CONFIG.$p [get_bd_cells axi_eth_0]]"
        }
        if {[get_property CONFIG.ENABLE_LVDS [get_bd_cells axi_eth_0]] ne "false"} {
            error "axi_eth_0 fell back to the LVDS PHY - impl will fail on an IO pblock clash"
        }
    }

    # ---------------------------------------------------------------------
    # 3) take the MAC's serial side out to the board-constrained SFP0 pins
    # ---------------------------------------------------------------------
    # The MAC's ref_clk is its 50 MHz DRP/PMA-timing reference (CONFIG.drpclkrate
    # = 50.0; the IP's own example design feeds it a 50 MHz BUFG output). The
    # platform clk_wizard_0 has no 50 MHz tap, so derive one from CIPS
    # pl0_ref_clk - the same source clk_wizard_0 uses - rather than cascading
    # off one of its BUFG outputs.
    _step "generate the MAC's 50 MHz ref_clk" {
        set cw [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 eth_ref_clk_wiz]
        set_property -dict [list \
            CONFIG.CLKOUT_USED {true,false,false,false,false,false,false} \
            CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {50,100.000,100.000,100.000,100.000,100.000,100.000} \
            CONFIG.USE_LOCKED {false} \
            CONFIG.USE_RESET  {true} \
            CONFIG.RESET_TYPE {ACTIVE_LOW} \
        ] $cw
        set cnet [get_bd_nets -of_objects [get_bd_pins CIPS_0/pl0_ref_clk]]
        connect_bd_net -net $cnet [get_bd_pins eth_ref_clk_wiz/clk_in1]
        set rnet [get_bd_nets -of_objects [get_bd_pins CIPS_0/pl0_resetn]]
        connect_bd_net -net $rnet [get_bd_pins eth_ref_clk_wiz/resetn]
    }

    _step "add the GTY front end and take SFP0 out to the pins" {
        create_bd_cell -type module -reference eth_gt_phy eth_gt_phy_0
        foreach p {mgt_clk_p mgt_clk_n sfp_rxp sfp_rxn sfp_txp sfp_txn} {
            make_bd_pins_external -name $p [get_bd_pins eth_gt_phy_0/$p]
        }
        _net eth_ref_clk eth_ref_clk_wiz/clk_out1 axi_eth_0/ref_clk eth_gt_phy_0/ref_clk
        # freerun_clk / resetn join the 100 MHz clock and reset nets further
        # down - proc_sys_reset_4's outputs are still unconnected at this point,
        # so there is no net to attach to yet.
    }

    # axi_ethernet 8.0 presents the GT side as ~30 discrete pins rather than the
    # bundled gt_tx_interface / gt_rx_interface of 7.2, so they are wired one by
    # one. The pairing is taken from the IP's own example design - see
    # hw/ref_axi_eth_example/eth_ex_support.v and PROJECT_STATE.md section 11.
    _step "wire axi_eth_0 to the GTY front end" {
        # {net name}  {eth_gt_phy pin}  {axi_eth_0 pin}
        foreach {net phy mac} {
            eth_gt_pma_reset        pma_reset               pma_reset
            eth_gt_mmcm_locked      mmcm_locked             mmcm_locked
            eth_gt_userclk          userclk                 userclk
            eth_gt_userclk2         userclk2                userclk2
            eth_gt_rxuserclk        rxuserclk               rxuserclk
            eth_gt_rxuserclk2       rxuserclk2              rxuserclk2
            eth_gt_powergood        gtpowergood             gtpowergood_in
            eth_gt_cplllock         cplllock                cplllock_in
            eth_gt_tx_done          gtwiz_reset_tx_done     gtwiz_reset_tx_done_in
            eth_gt_rx_done          gtwiz_reset_rx_done     gtwiz_reset_rx_done_in
            eth_gt_userdata_tx      gtwiz_userdata_tx       gtwiz_userdata_tx_out
            eth_gt_userdata_rx      gtwiz_userdata_rx       gtwiz_userdata_rx_in
            eth_gt_txctrl0          txctrl0                 txctrl0_out
            eth_gt_txctrl1          txctrl1                 txctrl1_out
            eth_gt_txctrl2          txctrl2                 txctrl2_out
            eth_gt_rxctrl0          rxctrl0                 rxctrl0_in
            eth_gt_rxctrl1          rxctrl1                 rxctrl1_in
            eth_gt_rxctrl2          rxctrl2                 rxctrl2_in
            eth_gt_rxctrl3          rxctrl3                 rxctrl3_in
            eth_gt_rxclkcorcnt      rxclkcorcnt             rxclkcorcnt_in
            eth_gt_txbufstatus      txbufstatus             txbufstatus_in
            eth_gt_rxbufstatus      rxbufstatus             rxbufstatus_in
            eth_gt_txpd             txpd                    txpd_out
            eth_gt_rxpd             rxpd                    rxpd_out
            eth_gt_txelecidle       txelecidle              txelecidle_out
            eth_gt_txresetdone      txresetdone             txresetdone_in
            eth_gt_rxresetdone      rxresetdone             rxresetdone_in
            eth_gt_txpmaresetdone   txpmaresetdone          txpmaresetdone_in
            eth_gt_rxpmaresetdone   rxpmaresetdone          rxpmaresetdone_in
            eth_gt_rst_tx_datapath  gtwiz_reset_tx_datapath gtwiz_reset_tx_datapath_out
            eth_gt_rst_rx_datapath  gtwiz_reset_rx_datapath gtwiz_reset_rx_datapath_out
            eth_gt_rxpcommaalignen  rxpcommaalignen         rxpcommaalignen_out
        } {
            _net $net eth_gt_phy_0/$phy axi_eth_0/$mac
        }
        # Left dangling on purpose (the PCS does not need them fed back, and the
        # example design leaves them open too): rx8b10ben_out, tx8b10ben_out,
        # rxcommadeten_out, rxmcommaalignen_out, mmcm_reset_out, status_vector.
    }

    _step "tie off the MAC's PHY status inputs" {
        # SFP loss-of-signal is not wired to the FPGA on the VCK190, so the PCS
        # is told the optical signal is always present. (mmcm_locked comes from
        # eth_gt_phy, which ties it high - there is no MMCM in this path.)
        set c1 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 eth_tieoff_high]
        set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $c1
        _net eth_tieoff_high_dout eth_tieoff_high/dout axi_eth_0/signal_detect
    }

    # ---------------------------------------------------------------------
    # 4) datapath: RX clock crossing, CSI source mux, metadata to DDR
    # ---------------------------------------------------------------------
    _step "insert the RX clock-domain-crossing FIFO" {
        set f [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 rx_cdc_fifo]
        set_property -dict [list \
            CONFIG.FIFO_DEPTH        {2048} \
            CONFIG.IS_ACLK_ASYNC     {1} \
            CONFIG.FIFO_MEMORY_TYPE  {block} \
        ] $f
        _drop_intf_net axi_eth_0_m_axis_rxd
        _intf axi_eth_0_m_axis_rxd axi_eth_0/m_axis_rxd rx_cdc_fifo/S_AXIS
        _intf rx_cdc_fifo_M_AXIS   rx_cdc_fifo/M_AXIS   rx_dwidth/S_AXIS
    }

    _step "add the CSI source mux (parser vs mm2s)" {
        set sw [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_switch:1.1 csi_mux]
        set_property -dict [list \
            CONFIG.NUM_SI       {2} \
            CONFIG.NUM_MI       {1} \
            CONFIG.ROUTING_MODE {1} \
            CONFIG.DECODER_REG  {1} \
        ] $sw
        _drop_intf_net csi_udp_parser_0_csi_out
        _intf csi_mux_S00_AXIS csi_udp_parser_0/csi_out csi_mux/S00_AXIS
        _intf csi_mux_S01_AXIS VitisRegion/s            csi_mux/S01_AXIS
        _intf csi_mux_M00_AXIS csi_mux/M00_AXIS         ai_engine_0/S00_AXIS
    }

    _step "add the metadata path to DDR" {
        set dw [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 meta_dwidth]
        set_property CONFIG.M_TDATA_NUM_BYTES {4} $dw
        create_bd_cell -type ip -vlnv xilinx.com:hls:s2mm:1.0 s2mm_meta

        _intf meta_dwidth_S_AXIS csi_udp_parser_0/meta_out meta_dwidth/S_AXIS
        _intf s2mm_meta_s        meta_dwidth/M_AXIS        s2mm_meta/s

        set_property CONFIG.NUM_SI {3} [get_bd_cells noc_ddr4]
        set_property -dict [list \
            CONFIG.CONNECTIONS {MC_0 {read_bw {5} write_bw {100} read_avg_burst {4} write_avg_burst {4}}} \
            CONFIG.NOC_PARAMS {} \
            CONFIG.CATEGORY {pl} \
        ] [get_bd_intf_pins noc_ddr4/S02_AXI]
        set_property CONFIG.ASSOCIATED_BUSIF {S00_AXI:S01_AXI:S02_AXI} [get_bd_pins noc_ddr4/aclk0]
        _intf s2mm_meta_m_axi_gmem s2mm_meta/m_axi_gmem noc_ddr4/S02_AXI
    }

    # The CSI datapath is RX-only, but a transmit path is what makes the design
    # self-testable: with the PHY in internal loopback, software can push a
    # synthetic nexmon CSI frame out of the MAC and have it come back through
    # the *entire* real chain - MAC RX, parser, AIE, DDR - with no Pi and no
    # optics. So instead of tying TX off, feed it from DDR.
    #
    # No new HLS is needed: the packaged mm2s mover already is a DDR->AXIS
    # engine that raises TLAST on the last word, which is exactly a frame
    # injector. Two instances:
    #   mm2s_txd  the Ethernet frame itself. A nexmon CSI frame is
    #             14+20+8+18 = 60 bytes of headers plus 4 bytes per subcarrier,
    #             so it is always a whole number of 32-bit words and mm2s's
    #             all-lanes-valid TKEEP is correct with no padding.
    #   mm2s_txc  the MAC's per-frame TX control packet: 5 words (APP0..APP4,
    #             XAXIDMA_LAST_APPWORD = 4), all zero when checksum offload is
    #             off, which it is (CONFIG.TXCSUM = None).
    # They run in the fast domain with the rest of the movers and cross into the
    # MAC's 100 MHz domain through async FIFOs - the mirror of rx_cdc_fifo -
    # which keeps noc_ddr4 single-clock.
    _step "add the TX injection path and drain RX status" {
        create_bd_cell -type module -reference axis_sink rxs_sink
        _intf axi_eth_0_m_axis_rxs axi_eth_0/m_axis_rxs rxs_sink/s_axis

        foreach {inst depth} {mm2s_txd 4096 mm2s_txc 64} {
            create_bd_cell -type ip -vlnv xilinx.com:hls:mm2s:1.0 $inst
            set f [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 ${inst}_cdc]
            set_property -dict [list \
                CONFIG.FIFO_DEPTH       $depth \
                CONFIG.IS_ACLK_ASYNC    {1} \
                CONFIG.FIFO_MEMORY_TYPE {block} \
            ] $f
            _intf ${inst}_s $inst/s ${inst}_cdc/S_AXIS
        }
        _intf axi_eth_0_s_axis_txd mm2s_txd_cdc/M_AXIS axi_eth_0/s_axis_txd
        _intf axi_eth_0_s_axis_txc mm2s_txc_cdc/M_AXIS axi_eth_0/s_axis_txc

        # two more NoC slave ports for the injectors' DDR reads
        set_property CONFIG.NUM_SI {5} [get_bd_cells noc_ddr4]
        foreach si {S03_AXI S04_AXI} {
            set_property -dict [list \
                CONFIG.CONNECTIONS {MC_0 {read_bw {100} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
                CONFIG.NOC_PARAMS {} \
                CONFIG.CATEGORY {pl} \
            ] [get_bd_intf_pins noc_ddr4/$si]
        }
        _intf mm2s_txd_m_axi_gmem mm2s_txd/m_axi_gmem noc_ddr4/S03_AXI
        _intf mm2s_txc_m_axi_gmem mm2s_txc/m_axi_gmem noc_ddr4/S04_AXI
        # NOTE: aclk0's ASSOCIATED_BUSIF is deliberately NOT set here - see the
        # dedicated step near the end. Connecting an interface to a NoC slave
        # port re-derives it and wipes whatever was set beforehand.
    }

    # A frame injector on the PARSER'S INPUT, not just on the MAC's.
    #
    # This exists for two reasons. It lets a captured or synthetic nexmon frame
    # be replayed through the real parser -> AIE -> DDR chain from DDR, with no
    # Pi, no optics and no MAC involved - which is the only way to test the CSI
    # ingest logic on silicon independently of Ethernet bring-up. And it is
    # useful in its own right for replaying recorded pcaps through the inline
    # pipeline.
    #
    # rx_mux selects what the parser sees:
    #   S00 = rx_dwidth  (live, from the MAC)
    #   S01 = mm2s_rx    (replay, from DDR)
    _step "add the parser-input replay injector" {
        create_bd_cell -type ip -vlnv xilinx.com:hls:mm2s:1.0 mm2s_rx

        set dw [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 rx_inj_dwidth]
        set_property CONFIG.M_TDATA_NUM_BYTES {1} $dw

        set sw [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_switch:1.1 rx_mux]
        set_property -dict [list \
            CONFIG.NUM_SI       {2} \
            CONFIG.NUM_MI       {1} \
            CONFIG.ROUTING_MODE {1} \
            CONFIG.DECODER_REG  {1} \
        ] $sw

        # re-route the parser input through the mux
        _drop_intf_net rx_dwidth_M_AXIS
        _intf rx_mux_S00_AXIS rx_dwidth/M_AXIS      rx_mux/S00_AXIS
        _intf mm2s_rx_s       mm2s_rx/s             rx_inj_dwidth/S_AXIS
        _intf rx_mux_S01_AXIS rx_inj_dwidth/M_AXIS  rx_mux/S01_AXIS
        _intf rx_mux_M00_AXIS rx_mux/M00_AXIS       csi_udp_parser_0/rx

        # one more NoC slave port for the replay mover's DDR reads
        set_property CONFIG.NUM_SI {6} [get_bd_cells noc_ddr4]
        set_property -dict [list \
            CONFIG.CONNECTIONS {MC_0 {read_bw {100} write_bw {5} read_avg_burst {4} write_avg_burst {4}}} \
            CONFIG.NOC_PARAMS {} \
            CONFIG.CATEGORY {pl} \
        ] [get_bd_intf_pins noc_ddr4/S05_AXI]
        _intf mm2s_rx_m_axi_gmem mm2s_rx/m_axi_gmem noc_ddr4/S05_AXI
    }

    # Loopback depth has to be selectable at run time to be useful as a test:
    # near-end PMA closes the loop inside the transceiver (no optics needed),
    # while 000 is the normal path once a Pi is plugged in.
    _step "add the GT loopback control register" {
        set g [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 eth_loopback_gpio]
        set_property -dict [list \
            CONFIG.C_GPIO_WIDTH    {3} \
            CONFIG.C_ALL_OUTPUTS   {1} \
            CONFIG.C_IS_DUAL       {1} \
            CONFIG.C_GPIO2_WIDTH   {32} \
            CONFIG.C_ALL_INPUTS_2  {1} \
            CONFIG.C_DOUT_DEFAULT  {0x00000000} \
        ] $g
        _net eth_gt_loopback eth_loopback_gpio/gpio_io_o eth_gt_phy_0/loopback
        # channel 2 is read-only status from the PHY (GPIO2_DATA at +0x08)
        _net eth_gt_status eth_gt_phy_0/status eth_loopback_gpio/gpio2_io_i
    }

    # ---------------------------------------------------------------------
    # 5) AXI-Lite control: four new masters off icn_ctrl
    #      M07 -> slow_ctrl_smc -> axi_eth_0/s_axi  (100 MHz domain)
    #      M08 -> csi_udp_parser_0/s_axi_ctrl
    #      M09 -> s2mm_meta/s_axi_control
    #      M10 -> csi_mux/S_AXI_CTRL
    #      M11 -> mm2s_txd/s_axi_control
    #      M12 -> mm2s_txc/s_axi_control
    #      M13 -> eth_loopback_gpio/S_AXI
    #      M14 -> mm2s_rx/s_axi_control
    #      M15 -> rx_mux/S_AXI_CTRL
    # ---------------------------------------------------------------------
    _step "widen icn_ctrl and expose the new masters" {
        set_property CONFIG.NUM_MI {16} [get_bd_cells axi_smc_vip_hier/icn_ctrl]
        foreach m {M07 M08 M09 M10 M11 M12 M13 M14 M15} {
            create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 \
                axi_smc_vip_hier/${m}_AXI
            _intf icn_ctrl_${m}_AXI axi_smc_vip_hier/icn_ctrl/${m}_AXI \
                                    axi_smc_vip_hier/${m}_AXI
        }
    }

    _step "add the 312.5 -> 100 MHz control bridge" {
        set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 slow_ctrl_smc]
        set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {2}] $smc
        _intf slow_ctrl_smc_S00_AXI axi_smc_vip_hier/M07_AXI slow_ctrl_smc/S00_AXI
        _intf axi_eth_0_s_axi       slow_ctrl_smc/M00_AXI    axi_eth_0/s_axi
        # aclk1's ASSOCIATED_BUSIF is read-only on smartconnect: it is derived
        # from whichever clock the MI port's peer is on, so simply wiring aclk1
        # to the 100 MHz net (below) is what puts M00 in the slow domain.
    }

    _step "connect the remaining control masters" {
        _intf csi_udp_parser_0_s_axi_ctrl axi_smc_vip_hier/M08_AXI csi_udp_parser_0/s_axi_ctrl
        _intf s2mm_meta_s_axi_control     axi_smc_vip_hier/M09_AXI s2mm_meta/s_axi_control
        _intf csi_mux_S_AXI_CTRL          axi_smc_vip_hier/M10_AXI csi_mux/S_AXI_CTRL
        _intf mm2s_txd_s_axi_control      axi_smc_vip_hier/M11_AXI mm2s_txd/s_axi_control
        _intf mm2s_txc_s_axi_control      axi_smc_vip_hier/M12_AXI mm2s_txc/s_axi_control
        _intf eth_loopback_gpio_S_AXI     axi_smc_vip_hier/M13_AXI eth_loopback_gpio/S_AXI
        _intf mm2s_rx_s_axi_control       axi_smc_vip_hier/M14_AXI mm2s_rx/s_axi_control
        _intf rx_mux_S_AXI_CTRL           axi_smc_vip_hier/M15_AXI rx_mux/S_AXI_CTRL
    }

    # ---------------------------------------------------------------------
    # 6) clocks and resets for everything added above
    # ---------------------------------------------------------------------
    _step "attach the 100 MHz MAC/PHY clock" {
        set net [get_bd_nets -of_objects [get_bd_pins $::SLOW_CLK]]
        connect_bd_net -net $net [get_bd_pins $::SLOW_CLK] \
            [get_bd_pins axi_eth_0/s_axi_lite_clk] \
            [get_bd_pins axi_eth_0/axis_clk] \
            [get_bd_pins slow_ctrl_smc/aclk1] \
            [get_bd_pins eth_gt_phy_0/freerun_clk] \
            [get_bd_pins rx_cdc_fifo/s_axis_aclk] \
            [get_bd_pins mm2s_txd_cdc/m_axis_aclk] \
            [get_bd_pins mm2s_txc_cdc/m_axis_aclk] \
            [get_bd_pins rxs_sink/aclk]
    }

    _step "attach the 100 MHz MAC/PHY reset" {
        connect_bd_net -net eth_slow_aresetn [get_bd_pins $::SLOW_RSTN] \
            [get_bd_pins axi_eth_0/s_axi_lite_resetn] \
            [get_bd_pins axi_eth_0/axi_rxd_arstn] \
            [get_bd_pins axi_eth_0/axi_rxs_arstn] \
            [get_bd_pins axi_eth_0/axi_txc_arstn] \
            [get_bd_pins axi_eth_0/axi_txd_arstn] \
            [get_bd_pins eth_gt_phy_0/resetn] \
            [get_bd_pins rx_cdc_fifo/s_axis_aresetn] \
            [get_bd_pins rxs_sink/aresetn]
    }


    _step "attach the fast datapath clock" {
        set net [get_bd_nets -of_objects [get_bd_pins $::FAST_CLK]]
        connect_bd_net -net $net [get_bd_pins $::FAST_CLK] \
            [get_bd_pins rx_cdc_fifo/m_axis_aclk] \
            [get_bd_pins mm2s_txd/ap_clk] \
            [get_bd_pins mm2s_txc/ap_clk] \
            [get_bd_pins mm2s_txd_cdc/s_axis_aclk] \
            [get_bd_pins mm2s_txc_cdc/s_axis_aclk] \
            [get_bd_pins eth_loopback_gpio/s_axi_aclk] \
            [get_bd_pins mm2s_rx/ap_clk] \
            [get_bd_pins rx_inj_dwidth/aclk] \
            [get_bd_pins rx_mux/aclk] \
            [get_bd_pins rx_mux/s_axi_ctrl_aclk] \
            [get_bd_pins csi_mux/aclk] \
            [get_bd_pins csi_mux/s_axi_ctrl_aclk] \
            [get_bd_pins meta_dwidth/aclk] \
            [get_bd_pins s2mm_meta/ap_clk]
    }

    # axis_data_fifo in async mode has only s_axis_aresetn - the master side is
    # reset from the slave side internally - so there is no m_axis_aresetn here.
    _step "attach the fast datapath reset" {
        set net [get_bd_nets -of_objects [get_bd_pins $::FAST_RSTN]]
        connect_bd_net -net $net [get_bd_pins $::FAST_RSTN] \
            [get_bd_pins mm2s_txd/ap_rst_n] \
            [get_bd_pins mm2s_txc/ap_rst_n] \
            [get_bd_pins mm2s_txd_cdc/s_axis_aresetn] \
            [get_bd_pins mm2s_txc_cdc/s_axis_aresetn] \
            [get_bd_pins eth_loopback_gpio/s_axi_aresetn] \
            [get_bd_pins mm2s_rx/ap_rst_n] \
            [get_bd_pins rx_inj_dwidth/aresetn] \
            [get_bd_pins rx_mux/aresetn] \
            [get_bd_pins rx_mux/s_axi_ctrl_aresetn] \
            [get_bd_pins csi_mux/aresetn] \
            [get_bd_pins csi_mux/s_axi_ctrl_aresetn] \
            [get_bd_pins meta_dwidth/aresetn] \
            [get_bd_pins s2mm_meta/ap_rst_n]
    }

    # -----------------------------------------------------------------------
    # Debug: see TVALID/TREADY on the replay path directly.
    #
    # Bring-up is stuck on a stall that every register-level probe can only
    # infer: the HLS movers latch ap_start and clear ap_idle (so their clock and
    # reset are demonstrably live) but never reach ap_done, and no data arrives.
    # Registers cannot distinguish "producer never asserts TVALID" from
    # "consumer never asserts TREADY", and those have completely different
    # fixes. One capture settles it, so probe both ends of the injector path:
    #
    #   SLOT_0 = mm2s_rx -> rx_inj_dwidth   does the mover produce at all?
    #   SLOT_1 = rx_mux  -> parser          does the parser accept?
    #
    # Set INLINE_ILA=0 in the environment to build without it once the answer
    # is known - it is debug scaffolding, not part of the design.
    # Mark the nets and let Vivado's debug automation insert the core. Do NOT
    # hand-instantiate system_ila here: it is a 7-series/UltraScale core and
    # Vivado rejects it on this part outright -
    #   ERROR: [BD 5-683] VLNV <xilinx.com:ip:system_ila:1.1> is not supported
    #                     for the current part
    # Versal wants axis_ila instead, but its ports are generated rather than
    # declared in component.xml, so the slot/clock pin names cannot be relied
    # on from the outside. The automation rule picks the part-correct core and
    # wires its clock for us, which is both shorter and version-proof.
    if {![info exists ::env(INLINE_ILA)] || $::env(INLINE_ILA) ne "0"} {
        _step "mark the replay path for debug and insert an ILA" {
            # The dict key is AXIS_ILA, not SYSTEM_ILA: on Versal the debug rule
            # dispatches to get_axis_ila, which looks up that key and dies with
            # `key "AXIS_ILA" not known in dictionary` if it is missing.
            set opts [list AXIS_SIGNALS {Data and Trigger} \
                           CLK_SRC $::FAST_CLK \
                           AXIS_ILA {Auto} APC_EN {0}]
            foreach n {mm2s_rx_s rx_mux_M00_AXIS} {
                set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets $n]
            }
            apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
                [get_bd_intf_nets mm2s_rx_s]       $opts \
                [get_bd_intf_nets rx_mux_M00_AXIS] $opts \
            ]
        }
    }

    _step "clock/reset the control bridge from the fast domain" {
        set cnet [get_bd_nets -of_objects [get_bd_pins axi_smc_vip_hier/aclk]]
        set rnet [get_bd_nets -of_objects [get_bd_pins axi_smc_vip_hier/aresetn]]
        connect_bd_net -net $cnet [get_bd_pins slow_ctrl_smc/aclk]
        connect_bd_net -net $rnet [get_bd_pins slow_ctrl_smc/aresetn]
    }

    # ---------------------------------------------------------------------
    # 7) addresses
    # ---------------------------------------------------------------------
    # This has to happen AFTER every NoC slave interface is connected. Setting it
    # earlier looks like it works - get_property reads back the right thing - but
    # connecting an interface to a NoC slave port re-derives the association and
    # silently blanks it, and the built design ends up with an EMPTY
    # ASSOCIATED_BUSIF. The NoC then does not know which clock drives S02..S04,
    # and those ports are dead in hardware: mm2s_txd hung on a single-word DDR
    # read while mm2s on S00 completed. Nothing in the build flags it, so the
    # value is asserted below.
    _step "associate the NoC slave ports with aclk0" {
        set want {S00_AXI:S01_AXI:S02_AXI:S03_AXI:S04_AXI:S05_AXI}
        set_property CONFIG.ASSOCIATED_BUSIF $want [get_bd_pins noc_ddr4/aclk0]
        set got [get_property CONFIG.ASSOCIATED_BUSIF [get_bd_pins noc_ddr4/aclk0]]
        if {$got ne $want} {
            error "noc_ddr4/aclk0 ASSOCIATED_BUSIF is '$got', expected '$want'"
        }
        puts "              noc_ddr4/aclk0 ASSOCIATED_BUSIF = $got"
    }

    # PIN these. Bare assign_bd_address hands out offsets in whatever order it
    # walks the design, so adding a single IP silently renumbers everything -
    # adding the TX injectors moved s2mm_meta 0xA403->0xA407 and csi_mux
    # 0xA406->0xA40C, which would have quietly broken sw/csi_ctl.c and
    # live/inline_reader.py. Software depends on this map; it is documented in
    # PROJECT_STATE.md section 12. Only add to the end of the list.
    _step "assign addresses for the new slaves" {
        foreach {seg off rng} {
            csi_udp_parser_0/s_axi_ctrl/Reg 0xA4020000 0x10000
            s2mm_meta/s_axi_control/Reg     0xA4030000 0x10000
            csi_mux/S_AXI_CTRL/Reg          0xA4060000 0x10000
            axi_eth_0/s_axi/Reg0            0xA4080000 0x40000
            mm2s_txd/s_axi_control/Reg      0xA40C0000 0x10000
            mm2s_txc/s_axi_control/Reg      0xA40D0000 0x10000
            eth_loopback_gpio/S_AXI/Reg     0xA40E0000 0x10000
            mm2s_rx/s_axi_control/Reg       0xA4070000 0x10000
            rx_mux/S_AXI_CTRL/Reg           0xA40F0000 0x10000
        } {
            assign_bd_address -offset $off -range $rng \
                -target_address_space [get_bd_addr_spaces CIPS_0/M_AXI_FPD] \
                [get_bd_addr_segs $seg] -force
        }
        # the movers' DDR views can be auto-assigned; they all just see DDR
        assign_bd_address
        # ...and prove the pinned offsets are all actually occupied. Checked by
        # offset rather than by segment name: SEG_mm2s_* is ambiguous now that
        # there are three mm2s instances.
        set seen {}
        foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces CIPS_0/M_AXI_FPD]] {
            lappend seen [format 0x%08x [get_property OFFSET $seg]]
        }
        foreach off {0xa4020000 0xa4030000 0xa4060000 0xa4080000
                     0xa40c0000 0xa40d0000 0xa40e0000 0xa4070000 0xa40f0000} {
            if {[lsearch -exact $seen $off] < 0} {
                error "pinned address $off is not in the M_AXI_FPD map: $seen"
            }
        }
        puts "---- inline address map ----"
        foreach sp [get_bd_addr_spaces] {
            foreach seg [get_bd_addr_segs -of_objects $sp] {
                puts [format "  %-40s %-14s %s" $sp \
                        [get_property OFFSET $seg] [get_property NAME $seg]]
            }
        }
        puts "---- end address map ----"
    }

    if {[llength $::ETH_ERRORS]} {
        puts "\nadd_eth_phy: [llength $::ETH_ERRORS] step(s) failed:"
        foreach e $::ETH_ERRORS { puts "  - $e" }
        return -code error "add_eth_phy: [llength $::ETH_ERRORS] step(s) failed (see above)"
    }
    puts "add_eth_phy: all steps OK"
}


##################################################################
# ENTRY POINT
##################################################################
# Build the block design and close it out. project_top.tcl calls this and then
# validates, wraps, and runs synthesis/implementation.
proc build_inline_bd {} {
    create_root_design ""
    add_eth_phy
}
