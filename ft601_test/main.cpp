#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

#include <FTD3XX.h>

namespace {

constexpr UCHAR OUT_PIPE = 0x02;
constexpr UCHAR IN_PIPE = 0x82;
constexpr ULONG TIMEOUT_MS = 2000;
constexpr ULONG CHUNK_BYTES = 1u << 20;  // 1 MiB
constexpr DWORD DEVICE_INDEX = 0;
constexpr uint32_t WRITE_WORD_COUNT = 10000;

bool OpenDevice(FT_HANDLE& h, std::string& err);

// FT status codes
const char* StatusName(FT_STATUS st) {
    switch (st) {
        case FT_OK: return "FT_OK";                                             // 0
        case FT_INVALID_HANDLE: return "FT_INVALID_HANDLE";                     // 1
        case FT_DEVICE_NOT_FOUND: return "FT_DEVICE_NOT_FOUND";                 // 2  
        case FT_DEVICE_NOT_OPENED: return "FT_DEVICE_NOT_OPENED";               // 3
        case FT_IO_ERROR: return "FT_IO_ERROR";                                 // 4
        case FT_INSUFFICIENT_RESOURCES: return "FT_INSUFFICIENT_RESOURCES";     // 5
        case FT_INVALID_PARAMETER: return "FT_INVALID_PARAMETER";               // 6
        case FT_INVALID_BAUD_RATE: return "FT_INVALID_BAUD_RATE";               // 7
        case FT_INVALID_ARGS: return "FT_INVALID_ARGS";                         // 16
        case FT_NOT_SUPPORTED: return "FT_NOT_SUPPORTED";                       // 17
        case FT_TIMEOUT: return "FT_TIMEOUT";                                   // 19
        case FT_OPERATION_ABORTED: return "FT_OPERATION_ABORTED";               // 20
        case FT_RESERVED_PIPE: return "FT_RESERVED_PIPE";                       // 21
        case FT_IO_PENDING: return "FT_IO_PENDING";                             // 24
        case FT_IO_INCOMPLETE: return "FT_IO_INCOMPLETE";                       // 25
        case FT_HANDLE_EOF: return "FT_HANDLE_EOF";                             // 26
        case FT_BUSY: return "FT_BUSY";                                         // 27
        case FT_DEVICE_LIST_NOT_READY: return "FT_DEVICE_LIST_NOT_READY";       // 29
        case FT_DEVICE_NOT_CONNECTED: return "FT_DEVICE_NOT_CONNECTED";         // 30
        case FT_INCORRECT_DEVICE_PATH: return "FT_INCORRECT_DEVICE_PATH";       // 31
        case FT_OTHER_ERROR: return "FT_OTHER_ERROR";                           // 32
        default: return "FT_STATUS_UNKNOWN";                                    // 1
    }
}

// Перевод статуса в строку
std::string StatusToStr(FT_STATUS st) {
    return std::string(StatusName(st)) + " (" +
           std::to_string(static_cast<int>(st)) + ")";
}

// Проверка статуса на наличие подключения
bool IsDisconnectStatus(FT_STATUS st) {
    return st == FT_DEVICE_NOT_CONNECTED || st == FT_DEVICE_NOT_FOUND ||
           st == FT_INVALID_HANDLE;
}

// Попытка повторного установления подключения
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

// Установка подключения с устройством
bool OpenDevice(FT_HANDLE& h, std::string& err) {
    h = nullptr;

    // Получение количества подключенных D3XX устройств
    DWORD num = 0;
    FT_STATUS st = FT_CreateDeviceInfoList(&num);
    if (st != FT_OK) {
        err = "FT_CreateDeviceInfoList failed: " + StatusToStr(st);
        return false;
    }
    if (num == 0) {
        err = "No device found";
        return false;
    }

    // Открывает устройство
    st = FT_Create(reinterpret_cast<PVOID>(static_cast<uintptr_t>(DEVICE_INDEX)),
                   FT_OPEN_BY_INDEX,
                   &h);
    if (st != FT_OK || !h) {
        err = "FT_Create failed: " + StatusToStr(st);
        h = nullptr;
        return false;
    }

    // Пауза на IN_PIPE
    st = FT_SetPipeTimeout(h, IN_PIPE, TIMEOUT_MS);
    if (st != FT_OK) {
        err = "FT_SetPipeTimeout(IN) failed: " + StatusToStr(st);
        FT_Close(h);
        h = nullptr;
        return false;
    }

    // Пауза на OUT_PIPE
    st = FT_SetPipeTimeout(h, OUT_PIPE, TIMEOUT_MS);
    if (st != FT_OK) {
        err = "FT_SetPipeTimeout(OUT) failed: " + StatusToStr(st);
        FT_Close(h);
        h = nullptr;
        return false;
    }

    return true;
}

// Запись счетчика в устройство
bool DoWriteCounter(FT_HANDLE h, std::string& err, FT_STATUS* last_status) {
    if (last_status != nullptr) {
        *last_status = FT_OK;
    }

    // Счетчик
    std::vector<uint32_t> data(WRITE_WORD_COUNT);
    for (uint32_t i = 0; i < data.size(); ++i) {
        data[i] = i + 1;
    }

    // Счетчик в байтах
    const auto* bytes = reinterpret_cast<const uint8_t*>(data.data());
    const ULONG total_bytes =
        static_cast<ULONG>(data.size() * sizeof(uint32_t));

    // Цикл отправки счетчика на устройство
    ULONG sent = 0; 
    while (sent < total_bytes) {
        ULONG want = std::min(CHUNK_BYTES, total_bytes - sent);

        ULONG written = 0;
        FT_STATUS st = FT_WritePipe(
            h,
            OUT_PIPE,
            const_cast<PUCHAR>(bytes + sent),
            want,
            &written,
            nullptr);

        if (st != FT_OK) {
            if (last_status != nullptr) {
                *last_status = st;
            }
            FT_AbortPipe(h, OUT_PIPE);
            err = "FT_WritePipe failed: " + StatusToStr(st);
            return false;
        }

        if (written == 0) {
            err = "FT_WritePipe wrote 0 bytes";
            return false;
        }

        sent += written;
    }

    return true;
}

// Чтение с устройства
bool DoReadToFile(FT_HANDLE h,
                  const std::string& path,
                  std::string& err,
                  uint64_t& outBytes,
                  FT_STATUS* last_status) {
    if (last_status != nullptr) {
        *last_status = FT_OK;
    }

    // Для записи в файл
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        err = "Cannot open file: " + path;
        return false;
    }

    std::vector<uint8_t> buf(CHUNK_BYTES);
    uint64_t total = 0;

    // Цикл чтения из устройства
    while (true) {
        ULONG got = 0;
        FT_STATUS st = FT_ReadPipe(
            h, IN_PIPE, buf.data(), static_cast<ULONG>(buf.size()), &got, nullptr);

        if (st == FT_TIMEOUT) {
            break;
        }

        if (st != FT_OK) {
            if (last_status != nullptr) {
                *last_status = st;
            }
            FT_AbortPipe(h, IN_PIPE);
            err = "FT_ReadPipe failed: " + StatusToStr(st);
            return false;
        }

        if (got > 0) {
            out.write(reinterpret_cast<const char*>(buf.data()),
                      static_cast<std::streamsize>(got));
            if (!out) {
                err = "File write error";
                return false;
            }

            total += got;
            std::cout << "\rReceived: " << total << " bytes" << std::flush;
        }
    }

    std::cout << "\n";
    outBytes = total;
    return true;
}

int ReadMenuChoice() {
    std::cout << "\nSelect action:\n";
    std::cout << "1) Write counter 1..10000\n";
    std::cout << "2) Read to file\n";
    std::cout << "3) Exit\n";
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
        system("pause");
        return 1;
    }

    std::cout << "Device opened. IN pipe=0x" << std::hex
              << static_cast<int>(IN_PIPE) << " OUT pipe=0x"
              << static_cast<int>(OUT_PIPE) << std::dec << "\n";

    while (true) {
        const int choice = ReadMenuChoice();
        if (choice == 3) {
            break;
        }

        if (choice == 1) {
            std::cout << "Writing counter 1..10000...\n";
            FT_STATUS op_status = FT_OK;
            if (!DoWriteCounter(h, err, &op_status)) {
                std::cerr << "WRITE ERROR: " << err << "\n";
                if (IsDisconnectStatus(op_status)) {
                    std::cerr << "Device disconnected, trying reopen...\n";
                    if (ReopenDevice(h, err)) {
                        std::cout << "Retrying write...\n";
                        if (!DoWriteCounter(h, err, &op_status)) {
                            std::cerr << "WRITE ERROR after reopen: " << err
                                      << "\n";
                        } else {
                            std::cout
                                << "WRITE OK after reopen: counter sent.\n";
                        }
                    } else {
                        std::cerr << "REOPEN ERROR: " << err << "\n";
                    }
                }
            } else {
                std::cout << "WRITE OK: counter sent successfully.\n";
            }
            continue;
        }

        if (choice == 2) {
            const std::string out_file = "rx_dump.bin";
            std::cout << "Reading until timeout (" << TIMEOUT_MS
                      << " ms) -> " << out_file << "\n";

            uint64_t bytes = 0;
            FT_STATUS op_status = FT_OK;
            if (!DoReadToFile(h, out_file, err, bytes, &op_status)) {
                std::cerr << "READ ERROR: " << err << "\n";
                if (IsDisconnectStatus(op_status)) {
                    std::cerr << "Device disconnected, trying reopen...\n";
                    if (ReopenDevice(h, err)) {
                        std::cout << "Retrying read...\n";
                        if (!DoReadToFile(h, out_file, err, bytes, &op_status)) {
                            std::cerr << "READ ERROR after reopen: " << err
                                      << "\n";
                        } else {
                            std::cout << "READ OK after reopen: saved " << bytes
                                      << " bytes to " << out_file << "\n";
                        }
                    } else {
                        std::cerr << "REOPEN ERROR: " << err << "\n";
                    }
                }
            } else {
                std::cout << "READ OK: saved " << bytes << " bytes to "
                          << out_file << "\n";
            }
            continue;
        }

        std::cout << "Unknown option.\n";
    }

    FT_Close(h);
    std::cout << "Bye.\n";
    return 0;
}
