// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2025.2 (64-bit)
// Tool Version Limit: 2025.11
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef XCSI_UDP_PARSER_H
#define XCSI_UDP_PARSER_H

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files *********************************/
#ifndef __linux__
#include "xil_types.h"
#include "xil_assert.h"
#include "xstatus.h"
#include "xil_io.h"
#else
#include <stdint.h>
#include <assert.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stddef.h>
#endif
#include "xcsi_udp_parser_hw.h"

/**************************** Type Definitions ******************************/
#ifdef __linux__
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
#else
typedef struct {
#ifdef SDT
    char *Name;
#else
    u16 DeviceId;
#endif
    u64 Ctrl_BaseAddress;
} XCsi_udp_parser_Config;
#endif

typedef struct {
    u64 Ctrl_BaseAddress;
    u32 IsReady;
} XCsi_udp_parser;

typedef u32 word_type;

/***************** Macros (Inline Functions) Definitions *********************/
#ifndef __linux__
#define XCsi_udp_parser_WriteReg(BaseAddress, RegOffset, Data) \
    Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))
#define XCsi_udp_parser_ReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))
#else
#define XCsi_udp_parser_WriteReg(BaseAddress, RegOffset, Data) \
    *(volatile u32*)((BaseAddress) + (RegOffset)) = (u32)(Data)
#define XCsi_udp_parser_ReadReg(BaseAddress, RegOffset) \
    *(volatile u32*)((BaseAddress) + (RegOffset))

#define Xil_AssertVoid(expr)    assert(expr)
#define Xil_AssertNonvoid(expr) assert(expr)

#define XST_SUCCESS             0
#define XST_DEVICE_NOT_FOUND    2
#define XST_OPEN_DEVICE_FAILED  3
#define XIL_COMPONENT_IS_READY  1
#endif

/************************** Function Prototypes *****************************/
#ifndef __linux__
#ifdef SDT
int XCsi_udp_parser_Initialize(XCsi_udp_parser *InstancePtr, UINTPTR BaseAddress);
XCsi_udp_parser_Config* XCsi_udp_parser_LookupConfig(UINTPTR BaseAddress);
#else
int XCsi_udp_parser_Initialize(XCsi_udp_parser *InstancePtr, u16 DeviceId);
XCsi_udp_parser_Config* XCsi_udp_parser_LookupConfig(u16 DeviceId);
#endif
int XCsi_udp_parser_CfgInitialize(XCsi_udp_parser *InstancePtr, XCsi_udp_parser_Config *ConfigPtr);
#else
int XCsi_udp_parser_Initialize(XCsi_udp_parser *InstancePtr, const char* InstanceName);
int XCsi_udp_parser_Release(XCsi_udp_parser *InstancePtr);
#endif

void XCsi_udp_parser_Start(XCsi_udp_parser *InstancePtr);
u32 XCsi_udp_parser_IsDone(XCsi_udp_parser *InstancePtr);
u32 XCsi_udp_parser_IsIdle(XCsi_udp_parser *InstancePtr);
u32 XCsi_udp_parser_IsReady(XCsi_udp_parser *InstancePtr);
void XCsi_udp_parser_Continue(XCsi_udp_parser *InstancePtr);
void XCsi_udp_parser_EnableAutoRestart(XCsi_udp_parser *InstancePtr);
void XCsi_udp_parser_DisableAutoRestart(XCsi_udp_parser *InstancePtr);

void XCsi_udp_parser_Set_udp_port(XCsi_udp_parser *InstancePtr, u32 Data);
u32 XCsi_udp_parser_Get_udp_port(XCsi_udp_parser *InstancePtr);

void XCsi_udp_parser_InterruptGlobalEnable(XCsi_udp_parser *InstancePtr);
void XCsi_udp_parser_InterruptGlobalDisable(XCsi_udp_parser *InstancePtr);
void XCsi_udp_parser_InterruptEnable(XCsi_udp_parser *InstancePtr, u32 Mask);
void XCsi_udp_parser_InterruptDisable(XCsi_udp_parser *InstancePtr, u32 Mask);
void XCsi_udp_parser_InterruptClear(XCsi_udp_parser *InstancePtr, u32 Mask);
u32 XCsi_udp_parser_InterruptGetEnabled(XCsi_udp_parser *InstancePtr);
u32 XCsi_udp_parser_InterruptGetStatus(XCsi_udp_parser *InstancePtr);

#ifdef __cplusplus
}
#endif

#endif
