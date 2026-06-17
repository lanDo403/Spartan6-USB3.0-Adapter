#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include <FTD3XX.h>

// Fixed D3XX bulk endpoints used by the FT601 245 FIFO firmware.
constexpr UCHAR OUT_PIPE = 0x02;
constexpr UCHAR IN_PIPE = 0x82;

// Default command/status timeout. Raw streaming reads temporarily override it.
constexpr ULONG TIMEOUT_MS = 2000;
constexpr ULONG CHUNK_BYTES = 1u << 20;
constexpr DWORD DEVICE_INDEX = 0;

// D3XX status helpers keep retry decisions readable at call sites.
std::string StatusToStr(FT_STATUS st);
bool IsDisconnectStatus(FT_STATUS st);
bool IsRecoverablePipeStatus(FT_STATUS st);
void AbortPipeBestEffort(FT_HANDLE h, UCHAR pipe_id);

// Open/reopen verifies the expected bulk pipe pair before normal operations.
bool OpenDevice(FT_HANDLE& h, std::string& err);
bool ReopenDevice(FT_HANDLE& h, std::string& err);

// Word helpers transfer little-endian host uint32_t data over the bulk pipes.
bool WriteWords(FT_HANDLE h,
                const std::vector<uint32_t>& words,
                std::string& err,
                FT_STATUS* last_status);

bool ReadExactWords(FT_HANDLE h,
                    size_t count,
                    std::vector<uint32_t>& words,
                    std::string& err,
                    FT_STATUS* last_status);

// Streaming dump helper used by the interactive "read payload" action.
bool DoReadToFile(FT_HANDLE h,
                  const std::string& path,
                  std::string& err,
                  uint64_t& out_bytes,
                  FT_STATUS* last_status);
