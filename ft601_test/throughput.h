#pragma once

#include <cstdint>
#include <string>
#include <windows.h>

struct ThroughputTimePoint {
    LARGE_INTEGER value;
};

ThroughputTimePoint ThroughputNow();
double ThroughputSeconds(ThroughputTimePoint start, ThroughputTimePoint end);
void PrintThroughput(const std::string& label, uint64_t bytes, double seconds);
