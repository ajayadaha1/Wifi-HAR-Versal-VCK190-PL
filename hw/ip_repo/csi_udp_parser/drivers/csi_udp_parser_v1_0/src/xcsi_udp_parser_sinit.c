// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
// Tool Version Limit: 2025.11
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef __linux__

#include "xstatus.h"
#ifdef SDT
#include "xparameters.h"
#endif
#include "xcsi_udp_parser.h"

extern XCsi_udp_parser_Config XCsi_udp_parser_ConfigTable[];

#ifdef SDT
XCsi_udp_parser_Config *XCsi_udp_parser_LookupConfig(UINTPTR BaseAddress) {
	XCsi_udp_parser_Config *ConfigPtr = NULL;

	int Index;

	for (Index = (u32)0x0; XCsi_udp_parser_ConfigTable[Index].Name != NULL; Index++) {
		if (!BaseAddress || XCsi_udp_parser_ConfigTable[Index].Ctrl_BaseAddress == BaseAddress) {
			ConfigPtr = &XCsi_udp_parser_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XCsi_udp_parser_Initialize(XCsi_udp_parser *InstancePtr, UINTPTR BaseAddress) {
	XCsi_udp_parser_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XCsi_udp_parser_LookupConfig(BaseAddress);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XCsi_udp_parser_CfgInitialize(InstancePtr, ConfigPtr);
}
#else
XCsi_udp_parser_Config *XCsi_udp_parser_LookupConfig(u16 DeviceId) {
	XCsi_udp_parser_Config *ConfigPtr = NULL;

	int Index;

	for (Index = 0; Index < XPAR_XCSI_UDP_PARSER_NUM_INSTANCES; Index++) {
		if (XCsi_udp_parser_ConfigTable[Index].DeviceId == DeviceId) {
			ConfigPtr = &XCsi_udp_parser_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XCsi_udp_parser_Initialize(XCsi_udp_parser *InstancePtr, u16 DeviceId) {
	XCsi_udp_parser_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XCsi_udp_parser_LookupConfig(DeviceId);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XCsi_udp_parser_CfgInitialize(InstancePtr, ConfigPtr);
}
#endif

#endif

