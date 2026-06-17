#include "app_log.h"
#include "payload_test.h"

#include "ft601_device.h"
#include "service_protocol.h"
#include "throughput.h"

#include <fstream>
#include <iostream>
#include <vector>

namespace {

bool SaveWordsBinary(const std::string& path,
                     const std::vector<uint32_t>& words,
                     std::string& err) {
    // Save exactly the host-side words that were submitted to FT_WritePipe.
    std::ofstream out(path.c_str(), std::ios::binary);
    if (!out) {
        err = "Cannot create binary file: " + path;
        return false;
    }

    if (!words.empty()) {
        out.write(reinterpret_cast<const char*>(words.data()),
                  static_cast<std::streamsize>(words.size() *
                                               sizeof(uint32_t)));
    }

    if (!out) {
        err = "Binary file write failed: " + path;
        return false;
    }

    return true;
}

uint32_t BuildRawTestWord(uint32_t word_index) {
    // Produce byte-visible counters in the same order as raw USB dumps.
    const uint32_t counter = word_index + 1u;
    return ((counter & 0x000000FFu) << 24u) |
           ((counter & 0x0000FF00u) << 8u) |
           ((counter & 0x00FF0000u) >> 8u) |
           ((counter & 0xFF000000u) >> 24u);
}

}  // namespace

bool DoWriteTestPayload(FT_HANDLE h, std::string& err, FT_STATUS* last_status) {
    std::vector<uint32_t> payload(WRITE_WORD_COUNT);
    for (uint32_t i = 0; i < payload.size(); ++i) {
        payload[i] = BuildRawTestWord(i);
    }

    const uint64_t bytes = static_cast<uint64_t>(payload.size()) *
                           sizeof(uint32_t);
    std::cout << "Generated raw TX pattern: " << payload.size()
              << " words, " << bytes << " bytes.\n";

    const ThroughputTimePoint start = ThroughputNow();
    if (!WriteWords(h, payload, err, last_status)) {
        return false;
    }

    const double seconds = ThroughputSeconds(start, ThroughputNow());
    PrintThroughput("Write payload throughput", bytes, seconds);

    const std::string tx_file = MakeDataFileName("raw", "tx", "bin");
    if (!SaveWordsBinary(tx_file, payload, err)) {
        return false;
    }
    std::cout << "TX payload saved to " << tx_file << "\n";
    return true;
}

bool DoReadTestPayload(FT_HANDLE h,
                       std::string& out_file,
                       uint64_t& out_bytes,
                       std::string& err,
                       FT_STATUS* last_status) {
    // File creation is delayed inside DoReadToFile until first payload bytes.
    out_file = MakeDataFileName("raw", "rx", "bin");

    if (!DoReadToFile(h, out_file, err, out_bytes, last_status)) {
        out_file.clear();
        out_bytes = 0;
        return false;
    }

    if (out_bytes == 0) {
        out_file.clear();
    }
    return true;
}
