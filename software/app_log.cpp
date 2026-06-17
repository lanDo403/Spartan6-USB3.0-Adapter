#include "app_log.h"

#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <streambuf>

namespace {

// Logging is process-global because the utility is a single interactive tool.
bool g_log_enabled = true;
std::ofstream g_log_file;
std::streambuf* g_cout_original = nullptr;
std::streambuf* g_cerr_original = nullptr;

// Stream buffer that mirrors console output into the session log.
class TeeStreambuf : public std::streambuf {
public:
    explicit TeeStreambuf(std::streambuf* console)
        : console_(console) {}

protected:
    int overflow(int ch) override {
        if (ch == traits_type::eof()) {
            return traits_type::not_eof(ch);
        }

        const char c = static_cast<char>(ch);
        if (console_ != nullptr) {
            console_->sputc(c);
        }
        if (g_log_enabled && g_log_file) {
            g_log_file.put(c);
        }
        return ch;
    }

    std::streamsize xsputn(const char* s, std::streamsize count) override {
        if (console_ != nullptr) {
            console_->sputn(s, count);
        }
        if (g_log_enabled && g_log_file) {
            g_log_file.write(s, count);
        }
        return count;
    }

    int sync() override {
        if (console_ != nullptr) {
            console_->pubsync();
        }
        if (g_log_file) {
            g_log_file.flush();
        }
        return 0;
    }

private:
    std::streambuf* console_;
};

std::unique_ptr<TeeStreambuf> g_cout_tee;
std::unique_ptr<TeeStreambuf> g_cerr_tee;

void SetLogEnabled(bool enabled) {
    g_log_enabled = enabled;
}

}  // namespace

bool InitLogFile(const std::string& path) {
    if (g_log_file.is_open()) {
        return true;
    }

    // Append sessions so one bench run keeps a continuous operation history.
    g_log_file.open(path.c_str(), std::ios::out | std::ios::app);
    if (!g_log_file) {
        return false;
    }

    g_cout_original = std::cout.rdbuf();
    g_cerr_original = std::cerr.rdbuf();

    g_cout_tee.reset(new TeeStreambuf(g_cout_original));
    g_cerr_tee.reset(new TeeStreambuf(g_cerr_original));

    std::cout.rdbuf(g_cout_tee.get());
    std::cerr.rdbuf(g_cerr_tee.get());

    std::cout << "\n=== ft601_test session " << MakeTimestampString()
              << " ===\n";
    return true;
}

void ShutdownLogFile() {
    // Restore standard streams before destroying the tee buffers.
    if (g_cout_original != nullptr) {
        std::cout.rdbuf(g_cout_original);
        g_cout_original = nullptr;
    }
    if (g_cerr_original != nullptr) {
        std::cerr.rdbuf(g_cerr_original);
        g_cerr_original = nullptr;
    }

    g_cout_tee.reset();
    g_cerr_tee.reset();

    if (g_log_file.is_open()) {
        g_log_file.flush();
        g_log_file.close();
    }
}

std::string MakeTimestampString() {
    const std::time_t now = std::time(nullptr);
    std::tm tm_value;
    std::tm* tm_ptr = std::localtime(&now);
    if (tm_ptr == nullptr) {
        return "unknown_time";
    }
    tm_value = *tm_ptr;

    std::ostringstream oss;
    oss << std::setfill('0')
        << std::setw(4) << (tm_value.tm_year + 1900)
        << std::setw(2) << (tm_value.tm_mon + 1)
        << std::setw(2) << tm_value.tm_mday
        << "_"
        << std::setw(2) << tm_value.tm_hour
        << std::setw(2) << tm_value.tm_min
        << std::setw(2) << tm_value.tm_sec;
    return oss.str();
}

std::string MakeDataFileName(const std::string& mode,
                             const std::string& direction,
                             const std::string& extension) {
    return MakeTimestampString() + "_" + mode + "_" + direction + "." +
           extension;
}

LogSilenceGuard::LogSilenceGuard()
    : previous_(g_log_enabled) {
    // Used for menus so log.txt contains actions/results, not repeated prompts.
    SetLogEnabled(false);
}

LogSilenceGuard::~LogSilenceGuard() {
    SetLogEnabled(previous_);
}
