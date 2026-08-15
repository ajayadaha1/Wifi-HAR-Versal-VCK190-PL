# Copyright 2021 Xilinx Inc.
# Copyright (C) 2022, Advanced Micro Devices, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



########################################################
###
### XDC for Axi Ethernet Subsystem design for VCK190
###
########################################################


##### GTY Bank 200 - QSFP
#set_property PACKAGE_PIN AF2 [get_ports {gt_rxp_in_0[0]}]
#set_property PACKAGE_PIN AF1 [get_ports {gt_rxn_in_0[0]}]
#set_property PACKAGE_PIN AF7 [get_ports {gt_txp_out_0[0]}]
#set_property PACKAGE_PIN AF6 [get_ports {gt_txn_out_0[0]}]
#set_property PACKAGE_PIN AE4 [get_ports {gt_rxp_in_0[1]}]
#set_property PACKAGE_PIN AE3 [get_ports {gt_rxn_in_0[1]}]
#set_property PACKAGE_PIN AE9 [get_ports {gt_txp_out_0[1]}]
#set_property PACKAGE_PIN AE8 [get_ports {gt_txn_out_0[1]}]
#set_property PACKAGE_PIN AD2 [get_ports {gt_rxp_in_0[2]}]
#set_property PACKAGE_PIN AD1 [get_ports {gt_rxn_in_0[2]}]
#set_property PACKAGE_PIN AD7 [get_ports {gt_txp_out_0[2]}]
#set_property PACKAGE_PIN AD6 [get_ports {gt_txn_out_0[2]}]
#set_property PACKAGE_PIN AC4 [get_ports {gt_rxp_in_0[3]}]
#set_property PACKAGE_PIN AC3 [get_ports {gt_rxn_in_0[3]}]
#set_property PACKAGE_PIN AC9 [get_ports {gt_txp_out_0[3]}]
#set_property PACKAGE_PIN AC8 [get_ports {gt_txn_out_0[3]}]
#### GTREFCLK 0 Configured as Output (Recovered Clock) which connects to 8A34001 CLK1_IN
#set_property PACKAGE_PIN AF11 [get_ports {RX_REC_CLK_out_p_0}]
#set_property PACKAGE_PIN AF10 [get_ports {RX_REC_CLK_out_n_0}]
#### GTREFCLK 1 ( Driven by 8A34001 Q1 )
#set_property PACKAGE_PIN AD11 [get_ports {CLK_IN_D_clk_p}]
#set_property PACKAGE_PIN AD10 [get_ports {CLK_IN_D_clk_n}]

#
# SFP0_TX_DISABLE to gpio
#
set_property IOSTANDARD LVCMOS33 [get_ports SFP0_TX_DISABLE]
set_property PACKAGE_PIN G21 [get_ports SFP0_TX_DISABLE]


##### GTY Bank 105 - SFP0 interface pin
set_property PACKAGE_PIN K46 [get_ports {gt_rxp_in_0[2]}]
set_property PACKAGE_PIN K47 [get_ports {gt_rxn_in_0[2]}]
set_property PACKAGE_PIN H41 [get_ports {gt_txp_out_0[2]}]
set_property PACKAGE_PIN H42 [get_ports {gt_txn_out_0[2]}]
### GTREFCLK 0 ( Driven by SI570 )
set_property PACKAGE_PIN L39 [get_ports {CLK_IN_D_clk_p}]
set_property PACKAGE_PIN L40 [get_ports {CLK_IN_D_clk_n}]

##### LED Outputs
set_property PACKAGE_PIN L35     [get_ports {rx_clk_led}]
set_property IOSTANDARD LVCMOS18 [get_ports {rx_clk_led}]
set_property PACKAGE_PIN K36     [get_ports {mgt_clk_led}]
set_property IOSTANDARD LVCMOS18 [get_ports {mgt_clk_led}]
set_property PACKAGE_PIN J33     [get_ports {axi_lite_clk_led}]
set_property IOSTANDARD LVCMOS18 [get_ports {axi_lite_clk_led}]
set_property PACKAGE_PIN H34     [get_ports {axil_reset_led}]
set_property IOSTANDARD LVCMOS18 [get_ports {axil_reset_led}]

####################################################################################
# Timing 
####################################################################################
create_clock -period 6.400 -name {CLK_IN_D_clk_p} -waveform {0.000 3.200} [get_ports {CLK_IN_D_clk_p}]

