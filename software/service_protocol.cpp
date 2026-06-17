#include "service_protocol.h"

#include "ft601_device.h"

#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>

namespace {

// Bound the scan so a missing status frame becomes a controlled error.
constexpr size_t STATUS_SCAN_WORD_LIMIT = 4096u;

// Current RTL uses only bits [5:0] in status_word.
constexpr uint32_t STATUS_RESERVED_MASK = 0xFFFFFFC0u;

void PrintHex32(const char* label, uint32_t value) {
    std::cout << label << "0x" << std::hex << std::setw(8) << std::setfill('0')
              << value << std::dec << std::setfill(' ') << "\n";
}

bool LooksLikeStatusWord(uint32_t value) {
    return (value & STATUS_RESERVED_MASK) == 0u;
}

}  // namespace

bool SendCommandFrame(FT_HANDLE h,
                      uint32_t opcode,
                      std::string& err,
                      FT_STATUS* last_status) {
    // The FPGA command decoder consumes exactly CMD_MAGIC then opcode.
    const std::vector<uint32_t> frame = {CMD_MAGIC, opcode};
    return WriteWords(h, frame, err, last_status);
}

bool ReadStatusFrame(FT_HANDLE h,
                     uint32_t& status_word,
                     std::string& err,
                     FT_STATUS* last_status) {
    size_t discarded_words = 0;

    // Payload or stale words can be ahead of the service response in EP82.
    while (discarded_words < STATUS_SCAN_WORD_LIMIT) {
        std::vector<uint32_t> word;
        if (!ReadExactWords(h, 1, word, err, last_status)) {
            return false;
        }

        if (word[0] != STATUS_MAGIC) {
            ++discarded_words;
            continue;
        }

        std::vector<uint32_t> status;
        if (!ReadExactWords(h, 1, status, err, last_status)) {
            return false;
        }

        if (!LooksLikeStatusWord(status[0])) {
            // Treat a false STATUS_MAGIC hit as stale data and keep scanning.
            discarded_words += 2u;
            continue;
        }

        if (discarded_words != 0u) {
            std::cout << "WARNING: discarded " << discarded_words
                      << " stale word(s) before STATUS_MAGIC.\n";
        }

        status_word = status[0];
        return true;
    }

    {
        if (last_status != nullptr) {
            *last_status = FT_OTHER_ERROR;
        }
        AbortPipeBestEffort(h, IN_PIPE);
        std::ostringstream oss;
        oss << "Protocol error: STATUS_MAGIC 0x" << std::hex
            << std::setw(8) << std::setfill('0') << STATUS_MAGIC
            << " was not found within " << std::dec
            << STATUS_SCAN_WORD_LIMIT << " words";
        err = oss.str();
        return false;
    }
}

bool RequestStatus(FT_HANDLE h,
                   uint32_t& status_word,
                   std::string& err,
                   FT_STATUS* last_status) {
    if (!SendCommandFrame(h, CMD_GET_STATUS, err, last_status)) {
        return false;
    }

    return ReadStatusFrame(h, status_word, err, last_status);
}

bool DoGetStatus(FT_HANDLE h, std::string& err, FT_STATUS* last_status) {
    uint32_t status_word = 0;
    if (!RequestStatus(h, status_word, err, last_status)) {
        return false;
    }
    PrintStatusWord(status_word);
    return true;
}

void PrintStatusWord(uint32_t status_word) {
    PrintHex32("Status word: ", status_word);
    std::cout << "  mode              : "
              << ((status_word & (1u << 0)) ? "loopback" : "normal") << "\n";
    std::cout << "  service_frame_error: "
              << ((status_word & (1u << 1)) ? "1" : "0") << "\n";
    std::cout << "  tx_fifo_empty     : "
              << ((status_word & (1u << 2)) ? "1" : "0") << "\n";
    std::cout << "  tx_fifo_full      : "
              << ((status_word & (1u << 3)) ? "1" : "0") << "\n";
    std::cout << "  loopback_empty    : "
              << ((status_word & (1u << 4)) ? "1" : "0") << "\n";
    std::cout << "  loopback_full     : "
              << ((status_word & (1u << 5)) ? "1" : "0") << "\n";
}
