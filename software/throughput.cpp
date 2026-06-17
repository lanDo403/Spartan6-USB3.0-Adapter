#include "throughput.h"

#include <iomanip>
#include <iostream>
#include <sstream>

ThroughputTimePoint ThroughputNow() {
    ThroughputTimePoint point = {};
    QueryPerformanceCounter(&point.value);
    return point;
}

double ThroughputSeconds(ThroughputTimePoint start, ThroughputTimePoint end) {
    LARGE_INTEGER frequency = {};
    QueryPerformanceFrequency(&frequency);
    if (frequency.QuadPart == 0) {
        // Defensive fallback; Windows normally provides this counter.
        return 0.0;
    }

    return static_cast<double>(end.value.QuadPart - start.value.QuadPart) /
           static_cast<double>(frequency.QuadPart);
}

void PrintThroughput(const std::string& label, uint64_t bytes, double seconds) {
    if (bytes == 0) {
        // Avoid presenting meaningless rates for empty reads.
        std::cout << label << ": 0 bytes, throughput not measured."
                  << std::endl;
        return;
    }

    if (seconds <= 0.0) {
        // Very small transfers can round to zero at timer resolution limits.
        std::cout << label << ": " << bytes
                  << " bytes, elapsed time is too small to measure."
                  << std::endl;
        return;
    }

    const double mib = static_cast<double>(bytes) / (1024.0 * 1024.0);
    const double mib_per_sec = mib / seconds;
    const double mibits_per_sec = (static_cast<double>(bytes) * 8.0) /
                                  (seconds * 1024.0 * 1024.0);

    std::ostringstream oss;
    oss << label << ": " << bytes << " bytes in "
        << std::fixed << std::setprecision(6) << seconds << " s, "
        << std::setprecision(2) << mib_per_sec << " MiB/s, "
        << mibits_per_sec << " Mib/s";

    std::cout << oss.str() << std::endl;
}
