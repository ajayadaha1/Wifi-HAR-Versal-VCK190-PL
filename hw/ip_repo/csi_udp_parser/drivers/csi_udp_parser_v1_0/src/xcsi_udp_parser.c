// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
// Tool Version Limit: 2025.11
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
/***************************** Include Files *********************************/
#include "xcsi_udp_parser.h"

/************************** Function Implementation *************************/
#ifndef __linux__
int XCsi_udp_parser_CfgInitialize(XCsi_udp_parser *InstancePtr, XCsi_udp_parser_Config *ConfigPtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(ConfigPtr != NULL);

    InstancePtr->Ctrl_BaseAddress = ConfigPtr->Ctrl_BaseAddress;
    InstancePtr->IsReady = XIL_COMPONENT_IS_READY;

    return XST_SUCCESS;
}
#endif

void XCsi_udp_parser_Start(XCsi_udp_parser *InstancePtr) {
    u32 Data;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL) & 0x80;
    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL, Data | 0x01);
}

u32 XCsi_udp_parser_IsDone(XCsi_udp_parser *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL);
    return (Data >> 1) & 0x1;
}

u32 XCsi_udp_parser_IsIdle(XCsi_udp_parser *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL);
    return (Data >> 2) & 0x1;
}

u32 XCsi_udp_parser_IsReady(XCsi_udp_parser *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL);
    // check ap_start to see if the pcore is ready for next input
    return !(Data & 0x1);
}

void XCsi_udp_parser_Continue(XCsi_udp_parser *InstancePtr) {
    u32 Data;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL) & 0x80;
    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL, Data | 0x10);
}

void XCsi_udp_parser_EnableAutoRestart(XCsi_udp_parser *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL, 0x80);
}

void XCsi_udp_parser_DisableAutoRestart(XCsi_udp_parser *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_AP_CTRL, 0);
}

void XCsi_udp_parser_Set_udp_port(XCsi_udp_parser *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_UDP_PORT_DATA, Data);
}

u32 XCsi_udp_parser_Get_udp_port(XCsi_udp_parser *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_UDP_PORT_DATA);
    return Data;
}

void XCsi_udp_parser_InterruptGlobalEnable(XCsi_udp_parser *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_GIE, 1);
}

void XCsi_udp_parser_InterruptGlobalDisable(XCsi_udp_parser *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_GIE, 0);
}

void XCsi_udp_parser_InterruptEnable(XCsi_udp_parser *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_IER);
    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_IER, Register | Mask);
}

void XCsi_udp_parser_InterruptDisable(XCsi_udp_parser *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_IER);
    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_IER, Register & (~Mask));
}

void XCsi_udp_parser_InterruptClear(XCsi_udp_parser *InstancePtr, u32 Mask) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XCsi_udp_parser_WriteReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_ISR, Mask);
}

u32 XCsi_udp_parser_InterruptGetEnabled(XCsi_udp_parser *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_IER);
}

u32 XCsi_udp_parser_InterruptGetStatus(XCsi_udp_parser *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XCsi_udp_parser_ReadReg(InstancePtr->Ctrl_BaseAddress, XCSI_UDP_PARSER_CTRL_ADDR_ISR);
}

