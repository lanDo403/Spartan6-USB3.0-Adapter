#pragma once

#include <string>

// Redirect std::cout/std::cerr to console plus append-only log file.
bool InitLogFile(const std::string& path);
void ShutdownLogFile();

// Timestamp and data-file naming helpers share the same sortable format.
std::string MakeTimestampString();
std::string MakeDataFileName(const std::string& mode,
                             const std::string& direction,
                             const std::string& extension);

// Temporarily disables file logging for interactive prompts.
class LogSilenceGuard {
public:
    LogSilenceGuard();
    ~LogSilenceGuard();

private:
    bool previous_;
};
