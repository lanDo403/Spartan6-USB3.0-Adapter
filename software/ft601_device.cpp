#include "ft601_device.h"

#include "throughput.h"

#include <algorithm>
#include <atomic>
#include <conio.h>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <thread>

namespace {

// Raw reads use a short timeout so the user can stop an idle stream with 'q'.
constexpr ULONG RAW_READ_CHUNK_BYTES = 256u * 1024u;
constexpr ULONG RAW_READ_TIMEOUT_MS = 100u;
constexpr DWORD RAW_READ_STATS_PERIOD_MS = 1000u;
constexpr DWORD RAW_READ_STATS_POLL_MS = 100u;

// Keeps endpoint metadata together while validating the FT601 configuration.
struct PipeSummary {
    UCHAR interface_index;
    UCHAR pipe_index;
    FT_PIPE_INFORMATION info;
};

const char* StatusName(FT_STATUS st) {
    switch (st) {
        case FT_OK: return "FT_OK";
        case FT_INVALID_HANDLE: return "FT_INVALID_HANDLE";
        case FT_DEVICE_NOT_FOUND: return "FT_DEVICE_NOT_FOUND";
        case FT_DEVICE_NOT_OPENED: return "FT_DEVICE_NOT_OPENED";
        case FT_IO_ERROR: return "FT_IO_ERROR";
        case FT_INSUFFICIENT_RESOURCES: return "FT_INSUFFICIENT_RESOURCES";
        case FT_INVALID_PARAMETER: return "FT_INVALID_PARAMETER";
        case FT_INVALID_BAUD_RATE: return "FT_INVALID_BAUD_RATE";
        case FT_INVALID_ARGS: return "FT_INVALID_ARGS";
        case FT_NOT_SUPPORTED: return "FT_NOT_SUPPORTED";
        case FT_TIMEOUT: return "FT_TIMEOUT";
        case FT_OPERATION_ABORTED: return "FT_OPERATION_ABORTED";
        case FT_RESERVED_PIPE: return "FT_RESERVED_PIPE";
        case FT_IO_PENDING: return "FT_IO_PENDING";
        case FT_IO_INCOMPLETE: return "FT_IO_INCOMPLETE";
        case FT_HANDLE_EOF: return "FT_HANDLE_EOF";
        case FT_BUSY: return "FT_BUSY";
        case FT_DEVICE_LIST_NOT_READY: return "FT_DEVICE_LIST_NOT_READY";
        case FT_DEVICE_NOT_CONNECTED: return "FT_DEVICE_NOT_CONNECTED";
        case FT_INCORRECT_DEVICE_PATH: return "FT_INCORRECT_DEVICE_PATH";
        case FT_OTHER_ERROR: return "FT_OTHER_ERROR";
        default: return "FT_STATUS_UNKNOWN";
    }
}

std::string PipeTypeName(UCHAR pipe_type) {
    if (FT_IS_BULK_PIPE(pipe_type)) {
        return "BULK";
    }
    if (FT_IS_INTERRUPT_PIPE(pipe_type)) {
        return "INTERRUPT";
    }
    if (FT_IS_ISOCHRONOUS_PIPE(pipe_type)) {
        return "ISOCHRONOUS";
    }
    return "CONTROL";
}

bool LoadDeviceList(std::vector<FT_DEVICE_LIST_INFO_NODE>& devices,
                    std::string& err) {
    // The D3XX API requires a two-step enumerate-then-fill sequence.
    DWORD num_devices = 0;
    FT_STATUS st = FT_CreateDeviceInfoList(&num_devices);
    if (FT_FAILED(st)) {
        err = "FT_CreateDeviceInfoList failed: " + StatusToStr(st);
        return false;
    }

    if (num_devices == 0) {
        err = "No D3XX devices found";
        return false;
    }

    devices.resize(num_devices);
    std::memset(devices.data(), 0, devices.size() * sizeof(devices[0]));

    st = FT_GetDeviceInfoList(devices.data(), &num_devices);
    if (FT_FAILED(st)) {
        err = "FT_GetDeviceInfoList failed: " + StatusToStr(st);
        devices.clear();
        return false;
    }

    devices.resize(num_devices);
    return true;
}

void PrintSelectedDevice(const FT_DEVICE_LIST_INFO_NODE& device) {
    std::cout << "Selected device[" << DEVICE_INDEX << "]:\n";
    std::cout << "  Description : " << device.Description << "\n";
    std::cout << "  Serial      : " << device.SerialNumber << "\n";
    std::cout << "  Flags       : 0x" << std::hex << device.Flags << std::dec
              << "\n";
}

std::vector<PipeSummary> CollectPipes(FT_HANDLE h) {
    std::vector<PipeSummary> pipes;

    // Walk all interfaces because endpoint indexes are descriptor-local.
    FT_CONFIGURATION_DESCRIPTOR cfg;
    std::memset(&cfg, 0, sizeof(cfg));

    FT_STATUS st = FT_GetConfigurationDescriptor(h, &cfg);
    if (FT_FAILED(st)) {
        std::cout << "FT_GetConfigurationDescriptor failed: "
                  << StatusToStr(st) << "\n";
        return pipes;
    }

    std::cout << "Configuration reports "
              << static_cast<int>(cfg.bNumInterfaces)
              << " interface(s)\n";

    for (UCHAR interface_index = 0; interface_index < cfg.bNumInterfaces;
         ++interface_index) {
        FT_INTERFACE_DESCRIPTOR if_desc;
        std::memset(&if_desc, 0, sizeof(if_desc));

        st = FT_GetInterfaceDescriptor(h, interface_index, &if_desc);
        if (FT_FAILED(st)) {
            std::cout << "FT_GetInterfaceDescriptor failed for if="
                      << static_cast<int>(interface_index)
                      << ": " << StatusToStr(st) << "\n";
            continue;
        }

        std::cout << "Interface " << static_cast<int>(interface_index)
                  << " has " << static_cast<int>(if_desc.bNumEndpoints)
                  << " endpoint(s)\n";

        for (UCHAR pipe_index = 0; pipe_index < if_desc.bNumEndpoints;
             ++pipe_index) {
            FT_PIPE_INFORMATION info;
            std::memset(&info, 0, sizeof(info));

            st = FT_GetPipeInformation(h, interface_index, pipe_index, &info);
            if (FT_SUCCESS(st)) {
                pipes.push_back({interface_index, pipe_index, info});
            } else {
                std::cout << "FT_GetPipeInformation failed for if="
                          << static_cast<int>(interface_index)
                          << " pipe=" << static_cast<int>(pipe_index)
                          << ": " << StatusToStr(st) << "\n";
            }
        }
    }

    return pipes;
}

void PrintPipeSummary(const std::vector<PipeSummary>& pipes) {
    std::cout << "Detected pipes:\n";
    for (const PipeSummary& pipe : pipes) {
        std::cout << "  if=" << static_cast<int>(pipe.interface_index)
                  << " idx=" << static_cast<int>(pipe.pipe_index)
                  << " id=0x" << std::hex << std::setw(2)
                  << std::setfill('0')
                  << static_cast<int>(pipe.info.PipeId) << std::dec
                  << std::setfill(' ')
                  << " type=" << PipeTypeName(pipe.info.PipeType)
                  << " mps=" << pipe.info.MaximumPacketSize << "\n";
    }
}

bool VerifyRequiredPipes(FT_HANDLE h, std::string& err) {
    const std::vector<PipeSummary> pipes = CollectPipes(h);
    if (pipes.empty()) {
        err = "FT_GetPipeInformation returned no pipes";
        return false;
    }

    PrintPipeSummary(pipes);

    bool found_out = false;
    bool found_in = false;

    // Firmware and host utility both assume bulk OUT 0x02 and bulk IN 0x82.
    for (const PipeSummary& pipe : pipes) {
        const bool is_bulk = FT_IS_BULK_PIPE(pipe.info.PipeType);
        if (pipe.info.PipeId == OUT_PIPE && is_bulk &&
            FT_IS_WRITE_PIPE(pipe.info.PipeId)) {
            found_out = true;
        }
        if (pipe.info.PipeId == IN_PIPE && is_bulk &&
            FT_IS_READ_PIPE(pipe.info.PipeId)) {
            found_in = true;
        }
    }

    if (!found_out || !found_in) {
        err = "Required bulk pipe pair 0x02/0x82 not found";
        return false;
    }

    return true;
}

std::string IntervalLabel(uint64_t total_bytes) {
    std::ostringstream oss;
    oss << "Raw read interval (total " << total_bytes << " bytes)";
    return oss.str();
}

void RawReadStatsWorker(const std::atomic<bool>& stop_requested,
                        const std::atomic<uint64_t>& total_bytes) {
    uint64_t prev_bytes = total_bytes.load();
    ThroughputTimePoint prev_time = ThroughputNow();

    // Report interval throughput without blocking the read loop.
    while (!stop_requested.load()) {
        for (DWORD waited_ms = 0;
             waited_ms < RAW_READ_STATS_PERIOD_MS && !stop_requested.load();
             waited_ms += RAW_READ_STATS_POLL_MS) {
            Sleep(RAW_READ_STATS_POLL_MS);
        }
        if (stop_requested.load()) {
            break;
        }

        const ThroughputTimePoint now = ThroughputNow();
        const uint64_t current_bytes = total_bytes.load();
        const uint64_t interval_bytes =
            (current_bytes >= prev_bytes) ? (current_bytes - prev_bytes) : 0u;

        PrintThroughput(IntervalLabel(current_bytes),
                        interval_bytes,
                        ThroughputSeconds(prev_time, now));

        prev_bytes = current_bytes;
        prev_time = now;
    }
}

}  // namespace

std::string StatusToStr(FT_STATUS st) {
    return std::string(StatusName(st)) + " (" +
           std::to_string(static_cast<int>(st)) + ")";
}

bool IsDisconnectStatus(FT_STATUS st) {
    return st == FT_DEVICE_NOT_CONNECTED || st == FT_DEVICE_NOT_FOUND ||
           st == FT_INVALID_HANDLE;
}

bool IsRecoverablePipeStatus(FT_STATUS st) {
    // FT_OTHER_ERROR is commonly observed after aborted/failed bulk transfers.
    return IsDisconnectStatus(st) || st == FT_OTHER_ERROR;
}

void AbortPipeBestEffort(FT_HANDLE h, UCHAR pipe_id) {
    // Cleanup errors are intentionally ignored so the original error survives.
    if (h != nullptr) {
        FT_AbortPipe(h, pipe_id);
    }
}

bool OpenDevice(FT_HANDLE& h, std::string& err) {
    h = nullptr;

    // Only one board is expected during manual tests; DEVICE_INDEX selects it.
    std::vector<FT_DEVICE_LIST_INFO_NODE> devices;
    if (!LoadDeviceList(devices, err)) {
        return false;
    }

    if (DEVICE_INDEX >= devices.size()) {
        err = "DEVICE_INDEX is out of range";
        return false;
    }

    PrintSelectedDevice(devices[DEVICE_INDEX]);

    FT_STATUS st = FT_Create(
        reinterpret_cast<PVOID>(static_cast<uintptr_t>(DEVICE_INDEX)),
        FT_OPEN_BY_INDEX,
        &h);
    if (FT_FAILED(st) || h == nullptr) {
        err = "FT_Create failed: " + StatusToStr(st);
        h = nullptr;
        return false;
    }

    if (!VerifyRequiredPipes(h, err)) {
        FT_Close(h);
        h = nullptr;
        return false;
    }

    st = FT_SetPipeTimeout(h, IN_PIPE, TIMEOUT_MS);
    if (FT_FAILED(st)) {
        err = "FT_SetPipeTimeout(IN) failed: " + StatusToStr(st);
        FT_Close(h);
        h = nullptr;
        return false;
    }

    st = FT_SetPipeTimeout(h, OUT_PIPE, TIMEOUT_MS);
    if (FT_FAILED(st)) {
        err = "FT_SetPipeTimeout(OUT) failed: " + StatusToStr(st);
        FT_Close(h);
        h = nullptr;
        return false;
    }

    return true;
}

bool ReopenDevice(FT_HANDLE& h, std::string& err) {
    if (h != nullptr) {
        FT_Close(h);
        h = nullptr;
    }

    std::string reopen_err;
    if (!OpenDevice(h, reopen_err)) {
        err = "Reopen failed: " + reopen_err;
        return false;
    }

    std::cout << "Device reopened.\n";
    return true;
}

bool WriteWords(FT_HANDLE h,
                const std::vector<uint32_t>& words,
                std::string& err,
                FT_STATUS* last_status) {
    if (last_status != nullptr) {
        *last_status = FT_OK;
    }

    if (words.empty()) {
        return true;
    }

    const auto* bytes = reinterpret_cast<const uint8_t*>(words.data());
    const ULONG total_bytes =
        static_cast<ULONG>(words.size() * sizeof(uint32_t));

    ULONG sent = 0;
    while (sent < total_bytes) {
        // Bound each transfer so large payloads do not depend on one D3XX call.
        const ULONG want = std::min(CHUNK_BYTES, total_bytes - sent);
        ULONG written = 0;
        FT_STATUS st = FT_WritePipe(
            h,
            OUT_PIPE,
            const_cast<PUCHAR>(bytes + sent),
            want,
            &written,
            nullptr);

        if (FT_FAILED(st)) {
            if (last_status != nullptr) {
                *last_status = st;
            }
            AbortPipeBestEffort(h, OUT_PIPE);
            err = "FT_WritePipe(0x02) failed after " +
                  std::to_string(sent) + "/" +
                  std::to_string(total_bytes) +
                  " bytes: " + StatusToStr(st);
            return false;
        }

        if (written == 0) {
            if (last_status != nullptr) {
                *last_status = FT_OTHER_ERROR;
            }
            AbortPipeBestEffort(h, OUT_PIPE);
            err = "FT_WritePipe(0x02) wrote 0 bytes after " +
                  std::to_string(sent) + "/" +
                  std::to_string(total_bytes) + " bytes";
            return false;
        }

        sent += written;
    }

    return true;
}

bool ReadExactWords(FT_HANDLE h,
                    size_t count,
                    std::vector<uint32_t>& words,
                    std::string& err,
                    FT_STATUS* last_status) {
    if (last_status != nullptr) {
        *last_status = FT_OK;
    }

    words.assign(count, 0u);
    if (count == 0) {
        return true;
    }

    auto* bytes = reinterpret_cast<PUCHAR>(words.data());
    const ULONG total_bytes = static_cast<ULONG>(count * sizeof(uint32_t));

    ULONG received = 0;
    while (received < total_bytes) {
        // Status/control reads require an exact word count, not "some bytes".
        ULONG got = 0;
        FT_STATUS st = FT_ReadPipe(
            h,
            IN_PIPE,
            bytes + received,
            total_bytes - received,
            &got,
            nullptr);

        if (FT_FAILED(st)) {
            if (last_status != nullptr) {
                *last_status = st;
            }
            AbortPipeBestEffort(h, IN_PIPE);
            err = "FT_ReadPipe(0x82) failed after " +
                  std::to_string(received) + "/" +
                  std::to_string(total_bytes) +
                  " bytes: " + StatusToStr(st);
            return false;
        }

        if (got == 0) {
            if (last_status != nullptr) {
                *last_status = FT_TIMEOUT;
            }
            AbortPipeBestEffort(h, IN_PIPE);
            err = "FT_ReadPipe(0x82) returned 0 bytes before full read: got " +
                  std::to_string(received) + "/" +
                  std::to_string(total_bytes) + " bytes";
            return false;
        }

        received += got;
    }

    return true;
}

bool DoReadToFile(FT_HANDLE h,
                  const std::string& path,
                  std::string& err,
                  uint64_t& out_bytes,
                  FT_STATUS* last_status) {
    if (last_status != nullptr) {
        *last_status = FT_OK;
    }

    // Enable D3XX stream mode only for raw payload capture.
    FT_STATUS st = FT_SetStreamPipe(
        h,
        FALSE,
        FALSE,
        IN_PIPE,
        RAW_READ_CHUNK_BYTES);
    if (FT_FAILED(st)) {
        if (last_status != nullptr) {
            *last_status = st;
        }
        err = "FT_SetStreamPipe(0x82) failed: " + StatusToStr(st);
        return false;
    }

    st = FT_SetPipeTimeout(h, IN_PIPE, RAW_READ_TIMEOUT_MS);
    if (FT_FAILED(st)) {
        FT_ClearStreamPipe(h, FALSE, FALSE, IN_PIPE);
        if (last_status != nullptr) {
            *last_status = st;
        }
        err = "FT_SetPipeTimeout(0x82, raw read) failed: " + StatusToStr(st);
        return false;
    }

    uint64_t total = 0;
    bool got_payload = false;
    bool stop_requested = false;
    ThroughputTimePoint active_start = ThroughputNow();
    ThroughputTimePoint active_end = active_start;

    std::cout << "Raw read chunk size: " << RAW_READ_CHUNK_BYTES
              << " bytes. Press 'q' to stop streaming read.\n";

    std::ofstream out;
    std::vector<uint8_t> buffer(RAW_READ_CHUNK_BYTES);
    std::atomic<bool> stats_stop(false);
    std::atomic<uint64_t> stats_total_bytes(0);
    std::thread stats_thread(RawReadStatsWorker,
                             std::ref(stats_stop),
                             std::ref(stats_total_bytes));

    while (!stop_requested) {
        if (_kbhit()) {
            const int ch = _getch();
            if (ch == 'q' || ch == 'Q') {
                stop_requested = true;
                std::cout << "Read stop requested by user.\n";
                break;
            }
        }

        ULONG got = 0;
        const ThroughputTimePoint read_start = ThroughputNow();
        const FT_STATUS read_status = FT_ReadPipe(
            h,
            IN_PIPE,
            buffer.data(),
            static_cast<ULONG>(buffer.size()),
            &got,
            nullptr);
        const ThroughputTimePoint read_end = ThroughputNow();

        if (read_status == FT_TIMEOUT) {
            // Idle stream is not an error; keep polling until the user stops it.
            continue;
        }

        if (FT_FAILED(read_status)) {
            if (last_status != nullptr) {
                *last_status = read_status;
            }
            AbortPipeBestEffort(h, IN_PIPE);
            err = "FT_ReadPipe(0x82) failed during raw dump after " +
                  std::to_string(total) + " bytes: " +
                  StatusToStr(read_status);
            break;
        }

        if (got == 0) {
            Sleep(1);
            continue;
        }

        if (!out.is_open()) {
            // Avoid creating empty dump files when no payload arrives.
            out.open(path.c_str(), std::ios::binary);
            if (!out) {
                err = "Cannot open file: " + path;
                if (last_status != nullptr) {
                    *last_status = FT_OTHER_ERROR;
                }
                break;
            }
        }

        out.write(reinterpret_cast<const char*>(buffer.data()),
                  static_cast<std::streamsize>(got));
        if (!out) {
            err = "File write error";
            if (last_status != nullptr) {
                *last_status = FT_OTHER_ERROR;
            }
            break;
        }

        total += got;
        stats_total_bytes.store(total);
        if (!got_payload) {
            active_start = read_start;
            got_payload = true;
        }
        active_end = read_end;
    }

    stats_stop.store(true);
    if (stats_thread.joinable()) {
        stats_thread.join();
    }

    if (out.is_open()) {
        out.close();
        if (!out && err.empty()) {
            err = "File close error: " + path;
            if (last_status != nullptr) {
                *last_status = FT_OTHER_ERROR;
            }
        }
    }

    // Restore the default blocking timeout for later service/status commands.
    FT_ClearStreamPipe(h, FALSE, FALSE, IN_PIPE);
    const FT_STATUS timeout_status = FT_SetPipeTimeout(h, IN_PIPE, TIMEOUT_MS);
    if (FT_FAILED(timeout_status) && err.empty()) {
        if (last_status != nullptr) {
            *last_status = timeout_status;
        }
        err = "FT_SetPipeTimeout(0x82, default) failed: " +
              StatusToStr(timeout_status);
    }

    if (!err.empty()) {
        return false;
    }

    out_bytes = total;
    if (got_payload) {
        PrintThroughput("Raw read throughput",
                        total,
                        ThroughputSeconds(active_start, active_end));
        if (stop_requested) {
            std::cout << "Raw read stopped by user after " << total
                      << " bytes.\n";
        }
    } else {
        std::cout << "Raw read: no payload bytes received.\n";
    }
    return true;
}
