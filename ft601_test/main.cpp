#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <fstream>
#include <limits>
#include <string>
#include <vector>

#include <FTD3XX.h>

namespace {

constexpr UCHAR OUT_PIPE = 0x02;
constexpr UCHAR IN_PIPE = 0x82;
constexpr ULONG TIMEOUT_MS = 2000;
constexpr ULONG CHUNK_BYTES = 1u << 20;
constexpr DWORD DEVICE_INDEX = 0;
constexpr uint32_t WRITE_WORD_COUNT = 64;
constexpr UCHAR MAX_INTERFACE_PROBE = 4;
constexpr UCHAR MAX_PIPE_PROBE = 8;

constexpr uint32_t CMD_MAGIC = 0xA55A5AA5u;
constexpr uint32_t STATUS_MAGIC = 0x5AA55AA5u;
constexpr uint32_t CMD_CLR_TX_ERROR = 0x00000001u;
constexpr uint32_t CMD_CLR_RX_ERROR = 0x00000002u;
constexpr uint32_t CMD_CLR_ALL_ERROR = 0x00000003u;
constexpr uint32_t CMD_SET_LOOPBACK = 0xA5A50004u;
constexpr uint32_t CMD_SET_NORMAL = 0xA5A50005u;
constexpr uint32_t CMD_GET_STATUS = 0xA5A50006u;

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

std::string StatusToStr(FT_STATUS st) {
    return std::string(StatusName(st)) + " (" +
           std::to_string(static_cast<int>(st)) + ")";
}

bool IsDisconnectStatus(FT_STATUS st) {
    return st == FT_DEVICE_NOT_CONNECTED || st == FT_DEVICE_NOT_FOUND ||
           st == FT_INVALID_HANDLE;
}

void AbortPipeBestEffort(FT_HANDLE h, UCHAR pipe_id) {
    if (h != nullptr) {
        FT_AbortPipe(h, pipe_id);
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

void PrintHex32(const char* label, uint32_t value) {
    std::cout << label << "0x" << std::hex << std::setw(8) << std::setfill('0')
              << value << std::dec << std::setfill(' ') << "\n";
}

bool LoadDeviceList(std::vector<FT_DEVICE_LIST_INFO_NODE>& devices,
                    std::string& err) {
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

    devices.assign(num_devices, FT_DEVICE_LIST_INFO_NODE{});
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

    for (UCHAR interface_index = 0; interface_index < MAX_INTERFACE_PROBE;
         ++interface_index) {
        for (UCHAR pipe_index = 0; pipe_index < MAX_PIPE_PROBE; ++pipe_index) {
            FT_PIPE_INFORMATION info = {};
            FT_STATUS st = FT_GetPipeInformation(
                h, interface_index, pipe_index, &info);
            if (FT_SUCCESS(st)) {
                pipes.push_back({interface_index, pipe_index, info});
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

bool OpenDevice(FT_HANDLE& h, std::string& err) {
    h = nullptr;

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

    if (!VerifyRequiredPipes(h, err)) {
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
            err = "FT_WritePipe failed: " + StatusToStr(st);
            return false;
        }

        if (written == 0) {
            if (last_status != nullptr) {
                *last_status = FT_OTHER_ERROR;
            }
            AbortPipeBestEffort(h, OUT_PIPE);
            err = "FT_WritePipe wrote 0 bytes";
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
            err = "FT_ReadPipe failed: " + StatusToStr(st);
            return false;
        }

        if (got == 0) {
            if (last_status != nullptr) {
                *last_status = FT_TIMEOUT;
            }
            AbortPipeBestEffort(h, IN_PIPE);
            err = "FT_ReadPipe returned 0 bytes before full frame";
            return false;
        }

        received += got;
    }

    return true;
}

bool SendCommandFrame(FT_HANDLE h,
                      uint32_t opcode,
                      std::string& err,
                      FT_STATUS* last_status) {
    const std::vector<uint32_t> frame = {CMD_MAGIC, opcode};
    return WriteWords(h, frame, err, last_status);
}

bool ReadStatusFrame(FT_HANDLE h,
                     uint32_t& status_word,
                     std::string& err,
                     FT_STATUS* last_status) {
    std::vector<uint32_t> frame;
    if (!ReadExactWords(h, 2, frame, err, last_status)) {
        return false;
    }

    if (frame[0] != STATUS_MAGIC) {
        if (last_status != nullptr) {
            *last_status = FT_OTHER_ERROR;
        }
        AbortPipeBestEffort(h, IN_PIPE);
        err = "Protocol error: expected STATUS_MAGIC";
        return false;
    }

    status_word = frame[1];
    return true;
}

void PrintStatusWord(uint32_t status_word) {
    PrintHex32("Status word: ", status_word);
    std::cout << "  mode              : "
              << ((status_word & (1u << 0)) ? "loopback" : "normal") << "\n";
    std::cout << "  tx_error          : "
              << ((status_word & (1u << 1)) ? "1" : "0") << "\n";
    std::cout << "  rx_error          : "
              << ((status_word & (1u << 2)) ? "1" : "0") << "\n";
    std::cout << "  tx_fifo_empty     : "
              << ((status_word & (1u << 3)) ? "1" : "0") << "\n";
    std::cout << "  tx_fifo_full      : "
              << ((status_word & (1u << 4)) ? "1" : "0") << "\n";
    std::cout << "  loopback_empty    : "
              << ((status_word & (1u << 5)) ? "1" : "0") << "\n";
    std::cout << "  loopback_full     : "
              << ((status_word & (1u << 6)) ? "1" : "0") << "\n";
}

bool DoWriteTestPayload(FT_HANDLE h, std::string& err, FT_STATUS* last_status) {
    std::vector<uint32_t> payload(WRITE_WORD_COUNT);
    for (uint32_t i = 0; i < payload.size(); ++i) {
        payload[i] = i + 1;
    }

    return WriteWords(h, payload, err, last_status);
}

bool DoReadToFile(FT_HANDLE h,
                  const std::string& path,
                  std::string& err,
                  uint64_t& out_bytes,
                  FT_STATUS* last_status) {
    if (last_status != nullptr) {
        *last_status = FT_OK;
    }

    std::ofstream out(path, std::ios::binary);
    if (!out) {
        err = "Cannot open file: " + path;
        return false;
    }

    std::vector<uint8_t> buffer(CHUNK_BYTES);
    uint64_t total = 0;

    while (true) {
        ULONG got = 0;
        FT_STATUS st = FT_ReadPipe(
            h,
            IN_PIPE,
            buffer.data(),
            static_cast<ULONG>(buffer.size()),
            &got,
            nullptr);

        if (st == FT_TIMEOUT) {
            break;
        }

        if (FT_FAILED(st)) {
            if (last_status != nullptr) {
                *last_status = st;
            }
            AbortPipeBestEffort(h, IN_PIPE);
            err = "FT_ReadPipe failed: " + StatusToStr(st);
            return false;
        }

        if (got > 0) {
            out.write(reinterpret_cast<const char*>(buffer.data()),
                      static_cast<std::streamsize>(got));
            if (!out) {
                if (last_status != nullptr) {
                    *last_status = FT_OTHER_ERROR;
                }
                err = "File write error";
                return false;
            }

            total += got;
            std::cout << "\rReceived: " << total << " bytes" << std::flush;
        }
    }

    std::cout << "\n";
    out_bytes = total;
    return true;
}

bool DoGetStatus(FT_HANDLE h, std::string& err, FT_STATUS* last_status) {
    if (!SendCommandFrame(h, CMD_GET_STATUS, err, last_status)) {
        return false;
    }

    uint32_t status_word = 0;
    if (!ReadStatusFrame(h, status_word, err, last_status)) {
        return false;
    }

    PrintStatusWord(status_word);
    return true;
}

bool DoCommandAndGetStatus(FT_HANDLE h,
                           uint32_t opcode,
                           std::string& err,
                           FT_STATUS* last_status) {
    if (!SendCommandFrame(h, opcode, err, last_status)) {
        return false;
    }

    return DoGetStatus(h, err, last_status);
}

int ReadMenuChoice() {
    std::cout << "\nSelect action:\n";
    std::cout << "1) Write test payload (" << WRITE_WORD_COUNT << " words)\n";
    std::cout << "2) Read payload to file\n";
    std::cout << "3) Get FPGA status\n";
    std::cout << "4) Set loopback mode\n";
    std::cout << "5) Set normal mode\n";
    std::cout << "6) Clear TX error\n";
    std::cout << "7) Clear RX error\n";
    std::cout << "8) Clear all errors\n";
    std::cout << "9) Exit\n";
    std::cout << "Select: ";

    int choice = -1;
    if (!(std::cin >> choice)) {
        std::cin.clear();
        std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
        return -1;
    }

    return choice;
}

}  // namespace

int main() {
    FT_HANDLE h = nullptr;
    std::string err;

    if (!OpenDevice(h, err)) {
        std::cerr << "ERROR: " << err << "\n";
        return 1;
    }

    std::cout << "Device opened. IN pipe=0x" << std::hex
              << static_cast<int>(IN_PIPE) << " OUT pipe=0x"
              << static_cast<int>(OUT_PIPE) << std::dec << "\n";

    while (true) {
        const int choice = ReadMenuChoice();
        if (choice == 9) {
            break;
        }

        FT_STATUS op_status = FT_OK;

        if (choice == 1) {
            std::cout << "Writing test payload...\n";
            if (!DoWriteTestPayload(h, err, &op_status)) {
                std::cerr << "WRITE ERROR: " << err << "\n";
                if (IsDisconnectStatus(op_status) && ReopenDevice(h, err)) {
                    std::cout << "Retrying write...\n";
                    if (!DoWriteTestPayload(h, err, &op_status)) {
                        std::cerr << "WRITE ERROR after reopen: " << err
                                  << "\n";
                    } else {
                        std::cout << "WRITE OK after reopen.\n";
                    }
                } else if (IsDisconnectStatus(op_status)) {
                    std::cerr << "REOPEN ERROR: " << err << "\n";
                }
            } else {
                std::cout << "WRITE OK.\n";
            }
            continue;
        }

        if (choice == 2) {
            const std::string out_file = "rx_dump.bin";
            uint64_t bytes = 0;
            std::cout << "Reading raw payload until timeout (" << TIMEOUT_MS
                      << " ms) -> " << out_file << "\n";
            if (!DoReadToFile(h, out_file, err, bytes, &op_status)) {
                std::cerr << "READ ERROR: " << err << "\n";
                if (IsDisconnectStatus(op_status) && ReopenDevice(h, err)) {
                    std::cout << "Retrying read...\n";
                    if (!DoReadToFile(h, out_file, err, bytes, &op_status)) {
                        std::cerr << "READ ERROR after reopen: " << err
                                  << "\n";
                    } else {
                        std::cout << "READ OK after reopen: saved " << bytes
                                  << " bytes to " << out_file << "\n";
                    }
                } else if (IsDisconnectStatus(op_status)) {
                    std::cerr << "REOPEN ERROR: " << err << "\n";
                }
            } else {
                std::cout << "READ OK: saved " << bytes << " bytes to "
                          << out_file << "\n";
            }
            continue;
        }

        if (choice == 3) {
            if (!DoGetStatus(h, err, &op_status)) {
                std::cerr << "STATUS ERROR: " << err << "\n";
                if (IsDisconnectStatus(op_status) && ReopenDevice(h, err)) {
                    std::cout << "Retrying status request...\n";
                    if (!DoGetStatus(h, err, &op_status)) {
                        std::cerr << "STATUS ERROR after reopen: " << err
                                  << "\n";
                    }
                } else if (IsDisconnectStatus(op_status)) {
                    std::cerr << "REOPEN ERROR: " << err << "\n";
                }
            }
            continue;
        }

        if (choice == 4 || choice == 5 || choice == 6 || choice == 7 ||
            choice == 8) {
            uint32_t opcode = 0;
            const char* label = "";

            if (choice == 4) {
                opcode = CMD_SET_LOOPBACK;
                label = "SET_LOOPBACK";
            } else if (choice == 5) {
                opcode = CMD_SET_NORMAL;
                label = "SET_NORMAL";
            } else if (choice == 6) {
                opcode = CMD_CLR_TX_ERROR;
                label = "CLR_TX_ERROR";
            } else if (choice == 7) {
                opcode = CMD_CLR_RX_ERROR;
                label = "CLR_RX_ERROR";
            } else {
                opcode = CMD_CLR_ALL_ERROR;
                label = "CLR_ALL_ERROR";
            }

            std::cout << "Sending " << label << " and requesting status...\n";
            if (!DoCommandAndGetStatus(h, opcode, err, &op_status)) {
                std::cerr << "COMMAND ERROR: " << err << "\n";
                if (IsDisconnectStatus(op_status) && ReopenDevice(h, err)) {
                    std::cout << "Retrying command...\n";
                    if (!DoCommandAndGetStatus(h, opcode, err, &op_status)) {
                        std::cerr << "COMMAND ERROR after reopen: " << err
                                  << "\n";
                    }
                } else if (IsDisconnectStatus(op_status)) {
                    std::cerr << "REOPEN ERROR: " << err << "\n";
                }
            }
            continue;
        }

        std::cout << "Unknown option.\n";
    }

    if (h != nullptr) {
        FT_Close(h);
    }

    std::cout << "Bye.\n";
    return 0;
}
