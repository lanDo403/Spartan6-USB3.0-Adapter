// stdafx.h : include file for standard system include files,
// or project specific include files that are used frequently, but
// are changed infrequently
//

#pragma once

#include "targetver.h"

#include <stdio.h>
#include <tchar.h>
#include <stdlib.h>
#include <Windows.h>
#include "..\sources\FTD3XX_Test.h"
#include "..\sources\FTD3XX_Logger.h"




//
// Include D3XX library
//
#include "..\..\..\WU_FTD3XXLib\Lib\FTD3XX.h"


#include <initguid.h>
DEFINE_GUID(GUID_DEVINTERFACE_FOR_D3XX,
	0x2AFDD907, 0xDFA5, 0x4D07, 0xBA, 0x68, 0xFC, 0x60, 0x86, 0x37, 0xF2, 0x8A);

