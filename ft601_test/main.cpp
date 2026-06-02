#include "app_log.h"
#include "ft601_device.h"
#include "payload_test.h"
#include "service_protocol.h"

#include <iomanip>
#include <iostream>
#include <limits>
#include <string>

namespace {

class ActionScope {
public:
    explicit ActionScope(const char* name) : name_(name) {
        std::cout << "\n--- " << MakeTimestampString()
                  << " START " << name_ << " ---\n";
    }

    ~ActionScope() {
        std::cout << "--- " << MakeTimestampString()
                  << " END   " << name_ << " ---\n";
    }

private:
    const char* name_;
};

int ReadMenuChoice() {
    LogSilenceGuard hide_menu_from_log;

    std::cout << "\nSelect action:\n";
    std::cout << "1) Write test payload (" << WRITE_WORD_COUNT << " words)\n";
    std::cout << "2) Read payload to file\n";
    std::cout << "3) Get FPGA status\n";
    std::cout << "4) Set loopback mode\n";
    std::cout << "5) Set normal mode\n";
    std::cout << "6) Clear service frame error\n";
    std::cout << "7) Reset FT601\n";
    std::cout << "8) Exit\n";
    std::cout << "Select: ";

    int choice = -1;
    if (!(std::cin >> choice)) {
        std::cin.clear();
        std::cin.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
        return -1;
    }

    return choice;
}

bool TryReopenAndRetry(FT_HANDLE& h,
                       FT_STATUS op_status,
                       std::string& err,
                       const char* retry_label,
                       bool (*operation)(FT_HANDLE, std::string&, FT_STATUS*)) {
    if (!IsRecoverablePipeStatus(op_status)) {
        return false;
    }

    if (!ReopenDevice(h, err)) {
        std::cerr << "REOPEN ERROR: " << err << "\n";
        return true;
    }

    std::cout << "Retrying " << retry_label << "...\n";
    FT_STATUS retry_status = FT_OK;
    if (!operation(h, err, &retry_status)) {
        std::cerr << retry_label << " ERROR after reopen: " << err << "\n";
    }

    return true;
}

void HandleWritePayload(FT_HANDLE& h) {
    ActionScope action("write_payload");
    std::string err;
    FT_STATUS op_status = FT_OK;

    std::cout << "Writing test payload...\n";
    if (!DoWriteTestPayload(h, err, &op_status)) {
        std::cerr << "WRITE ERROR: " << err << "\n";
        TryReopenAndRetry(h, op_status, err, "WRITE", DoWriteTestPayload);
    } else {
        std::cout << "WRITE OK.\n";
    }
}

void HandleReadToFile(FT_HANDLE& h) {
    ActionScope action("read_payload");
    std::string out_file;
    std::string err;
    uint64_t bytes = 0;
    FT_STATUS op_status = FT_OK;

    std::cout << "Reading payload from EP82. Press q to stop streaming read.\n";

    if (!DoReadTestPayload(h, out_file, bytes, err, &op_status)) {
        std::cerr << "READ ERROR: " << err << "\n";
        if (IsRecoverablePipeStatus(op_status) && ReopenDevice(h, err)) {
            std::cout << "Retrying read...\n";
            if (!DoReadTestPayload(h, out_file, bytes, err, &op_status)) {
                std::cerr << "READ ERROR after reopen: " << err << "\n";
            } else {
                if (bytes == 0) {
                    std::cout << "READ OK after reopen: no payload bytes "
                              << "received, file not created.\n";
                } else {
                    std::cout << "READ OK after reopen: saved " << bytes
                              << " bytes to " << out_file << "\n";
                }
            }
        } else if (IsRecoverablePipeStatus(op_status)) {
            std::cerr << "REOPEN ERROR: " << err << "\n";
        }
    } else {
        if (bytes == 0) {
            std::cout << "READ OK: no payload bytes received, file not created.\n";
        } else {
            std::cout << "READ OK: saved " << bytes << " bytes to "
                      << out_file << "\n";
        }
    }
}

void HandleGetStatus(FT_HANDLE& h) {
    ActionScope action("get_status");
    std::string err;
    FT_STATUS op_status = FT_OK;

    if (!DoGetStatus(h, err, &op_status)) {
        std::cerr << "STATUS ERROR: " << err << "\n";
        TryReopenAndRetry(h, op_status, err, "STATUS", DoGetStatus);
    }
}

void HandleServiceCommand(FT_HANDLE& h, uint32_t opcode, const char* label) {
    ActionScope action(label);
    std::string err;
    FT_STATUS op_status = FT_OK;

    std::cout << "Sending " << label << "...\n";
    if (!SendCommandFrame(h, opcode, err, &op_status)) {
        std::cerr << "COMMAND ERROR: " << err << "\n";
        if (IsRecoverablePipeStatus(op_status) && ReopenDevice(h, err)) {
            std::cout << "Retrying command...\n";
            if (!SendCommandFrame(h, opcode, err, &op_status)) {
                std::cerr << "COMMAND ERROR after reopen: " << err << "\n";
            }
        } else if (IsRecoverablePipeStatus(op_status)) {
            std::cerr << "REOPEN ERROR: " << err << "\n";
        }
    } else {
        std::cout << "COMMAND OK. Use menu item 4 to read FPGA status.\n";
    }
}

}  // namespace

int main() {
    FT_HANDLE h = nullptr;
    std::string err;

    if (!InitLogFile("log.txt")) {
        std::cerr << "ERROR: cannot open log.txt\n";
        return 1;
    }

    if (!OpenDevice(h, err)) {
        std::cerr << "ERROR: " << err << "\n";
        ShutdownLogFile();
        return 1;
    }

    std::cout << "Device opened. IN pipe=0x" << std::hex
              << static_cast<int>(IN_PIPE) << " OUT pipe=0x"
              << static_cast<int>(OUT_PIPE) << std::dec << "\n";

    while (true) {
        const int choice = ReadMenuChoice();
        if (choice == 8) {
            break;
        }

        switch (choice) {
            case 1:
                HandleWritePayload(h);
                break;
            case 2:
                HandleReadToFile(h);
                break;
            case 3:
                HandleGetStatus(h);
                break;
            case 4:
                HandleServiceCommand(h, CMD_SET_LOOPBACK, "SET_LOOPBACK");
                break;
            case 5:
                HandleServiceCommand(h, CMD_SET_NORMAL, "SET_NORMAL");
                break;
            case 6:
                HandleServiceCommand(h, CMD_CLR_SERVICE_ERROR, "CLR_SERVICE_ERROR");
                break;
            case 7:
                HandleServiceCommand(h, CMD_FT601_RESET, "FT601_RESET");
                break;
            default:
                std::cout << "Unknown option.\n";
                break;
        }
    }

    if (h != nullptr) {
        FT_Close(h);
    }

    std::cout << "Bye.\n";
    ShutdownLogFile();
    return 0;
}
