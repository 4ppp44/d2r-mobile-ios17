#pragma once
#include <stdint.h>
// A short spin for immediate completions, then bounded progressive sleeps.
// This is not an event wait: guest work may complete without a host notification.
static inline uint32_t dm_yield_sleep_ns(uint32_t consecutive) {
    if (consecutive <= 8) return 0;
    if (consecutive <= 32) return 50000;
    if (consecutive <= 96) return 100000;
    return 200000;
}
