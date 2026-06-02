#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <FTD3XX.h>

constexpr uint32_t WRITE_WORD_COUNT = 64;

bool DoWriteTestPayload(FT_HANDLE h, std::string& err, FT_STATUS* last_status);

bool DoReadTestPayload(FT_HANDLE h,
                       std::string& out_file,
                       uint64_t& out_bytes,
                       std::string& err,
                       FT_STATUS* last_status);
