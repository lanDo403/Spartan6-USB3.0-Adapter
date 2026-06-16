#pragma once

#include <string>

bool InitLogFile(const std::string& path);
void ShutdownLogFile();

std::string MakeTimestampString();
std::string MakeDataFileName(const std::string& mode,
                             const std::string& direction,
                             const std::string& extension);

class LogSilenceGuard {
public:
    LogSilenceGuard();
    ~LogSilenceGuard();

private:
    bool previous_;
};
