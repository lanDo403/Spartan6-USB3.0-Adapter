#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <FTD3XX.h>

// Small deterministic payload used by the interactive write test.
constexpr uint32_t WRITE_WORD_COUNT = 64;

// Generate, send, and save the raw TX test pattern.
bool DoWriteTestPayload(FT_HANDLE h, std::string& err, FT_STATUS* last_status);

// Stream EP82 payload data to a timestamped binary file until the user stops it.
bool DoReadTestPayload(FT_HANDLE h,
                       std::string& out_file,
                       uint64_t& out_bytes,
                       std::string& err,
                       FT_STATUS* last_status);
