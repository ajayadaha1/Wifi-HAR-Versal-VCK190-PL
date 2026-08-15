
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

  set meta_out_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:acc_fifo_write_rtl:1.0 meta_out_0 ]

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
 ] [get_bd_intf_pins $ai_engine_0/M00_AXIS]

  set_property -dict [ list \
   CONFIG.CATEGORY {NOC} \
 ] [get_bd_intf_pins $ai_engine_0/S00_AXI]

  set_property -dict [ list \
   CONFIG.TDATA_NUM_BYTES {4} \
   CONFIG.CATEGORY {PL} \
   CONFIG.IS_REGISTERED {true} \
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


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


