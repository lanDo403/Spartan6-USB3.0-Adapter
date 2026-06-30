#include "service_protocol.h"

#include "ft601_device.h"

#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>

namespace {

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

    // 2 status words:
    // [0] STATUS_MAGIC
    // [1] status_word
    std::vector<uint32_t> frame(2u, 0u);

    ULONG got = 0;
    const ULONG expected_bytes = static_cast<ULONG>(frame.size() * sizeof(uint32_t));

    const FT_STATUS st = FT_ReadPipe(
        h,
        IN_PIPE,
        reinterpret_cast<PUCHAR>(frame.data()),
        expected_bytes,
        &got,
        nullptr
        );
    if (last_status != nullptr) {
        *last_status = st;
    }

    std::cout << "Status FT_ReadPipe: status=" << StatusToStr(st) << ", got=" << got << "/" << expected_bytes << " bytes\n";

    if (got >= sizeof(uint32_t)) {
        PrintHex32("Received status word[0]: ", frame[0]);
    }

    if (got >= 2u * sizeof(uint32_t)) {
        PrintHex32("Received status word[1]: ", frame[1]);
    }

    if (got == expected_bytes) {
        if (frame[0] != STATUS_MAGIC) {
            std::ostringstream oss;
            oss << "Protocol error: expected STATUS_MAGIC 0x" << std::hex << std::setw(8)
                << std::setfill('0') << STATUS_MAGIC << ", received 0x" << std::setw(8) << frame[0];
            err = oss.str();
            return false;
        }
        if (!LooksLikeStatusWord(frame[1])) {
            std::ostringstream oss;
            oss << "Protocol error: invalid status word 0x" << std::hex << std::setw(8) << std::setfill('0')
                << frame[1];
            err = oss.str();
            return false;
        }
        status_word = frame[1];
        return true;
    }

    std::ostringstream oss;
    oss << "Incomplete status response: status=" << StatusToStr(st) << ", received " << got << "/" << expected_bytes << " bytes";

    err = oss.str();
    return false;
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
