#pragma once

#include <cstdint>
#include <string>
#include <windows.h>

// Thin wrapper around QueryPerformanceCounter for portable call sites.
struct ThroughputTimePoint {
    LARGE_INTEGER value;
};

// Helpers used by payload write/read throughput reports.
ThroughputTimePoint ThroughputNow();
double ThroughputSeconds(ThroughputTimePoint start, ThroughputTimePoint end);
void PrintThroughput(const std::string& label, uint64_t bytes, double seconds);
