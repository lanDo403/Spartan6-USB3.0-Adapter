/*
 * FT600 Data Streamer Demo App
 *
 * Copyright (C) 2016 FTDI Chip
 *
 */

#pragma once
#include <initguid.h>



#define DEVICE_VID							_T("0403")
#define DEFAULT_VALUE_OPENBY_DESC			"FTDI SuperSpeed-FIFO Bridge"
#define DEFAULT_VALUE_OPENBY_SERIAL			"000000000001"
#define DEFAULT_VALUE_OPENBY_INDEX			"0"

DEFINE_GUID(GUID_DEVINTERFACE_FOR_D3XX,
0x2AFDD907, 0xDFA5, 0x4D07, 0xBA, 0x68, 0xFC, 0x60, 0x86, 0x37, 0xF2, 0x8A);

#define FT600_VID   0x0403
#define FT600_PID   0x601E
#define FT601_PID   0x601F

