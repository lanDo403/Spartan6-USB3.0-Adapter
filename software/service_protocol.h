#pragma once

#include <cstdint>
#include <string>
#include <FTD3XX.h>

// Service traffic is framed as two 32-bit words on the payload endpoints.
constexpr uint32_t CMD_MAGIC = 0xA55A5AA5u;
constexpr uint32_t STATUS_MAGIC = 0x5AA55AA5u;

// Opcodes must match cmd_decoder.v and SPECIFICATION.md.
constexpr uint32_t CMD_CLR_SERVICE_ERROR = 0x00000001u;
constexpr uint32_t CMD_SET_LOOPBACK = 0xA5A50004u;
constexpr uint32_t CMD_SET_NORMAL = 0xA5A50005u;
constexpr uint32_t CMD_GET_STATUS = 0xA5A50006u;
constexpr uint32_t CMD_FT601_RESET = 0xA5A50007u;

// Send one command frame: CMD_MAGIC followed by opcode.
bool SendCommandFrame(FT_HANDLE h,
                      uint32_t opcode,
                      std::string& err,
                      FT_STATUS* last_status);

// Find and decode one STATUS_MAGIC/status_word pair from the IN stream.
bool ReadStatusFrame(FT_HANDLE h,
                     uint32_t& status_word,
                     std::string& err,
                     FT_STATUS* last_status);

// Convenience helper for CMD_GET_STATUS plus status-frame readback.
bool RequestStatus(FT_HANDLE h,
                   uint32_t& status_word,
                   std::string& err,
                   FT_STATUS* last_status);

bool DoGetStatus(FT_HANDLE h, std::string& err, FT_STATUS* last_status);

void PrintStatusWord(uint32_t status_word);
