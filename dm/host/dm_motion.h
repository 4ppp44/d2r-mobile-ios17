#pragma once
#include <stdint.h>
#include <stddef.h>

// Bounded, allocation-free producers. Values are event-specific; never dereference
// guest pointers from the exporter or asynchronously sample mutable guest state.
enum { DM_MOTION_INPUT = 1, DM_MOTION_CLIENT, DM_MOTION_YAW, DM_MOTION_FRAME,
       DM_MOTION_GPU, DM_MOTION_ENQUEUE, DM_MOTION_DISPLAY, DM_MOTION_CAMERA };
#define DM_MOTION_CAPACITY 32768u
#define DM_MOTION_VALUES 12u
typedef struct {
    uint64_t sequence, time_ns, frame, ticket;
    unsigned event;
    double value[DM_MOTION_VALUES];
} dm_motion_row;
typedef struct {
    uint64_t accepted, overwritten, contended;
    size_t count;
} dm_motion_stats;
// The weak import keeps standalone graphics/input harnesses independent of host diagnostics.
void dm_motion_record(unsigned event, uint64_t frame, uint64_t ticket,
                      const double value[DM_MOTION_VALUES]) __attribute__((weak_import));
size_t dm_motion_snapshot(dm_motion_row *rows, size_t capacity, dm_motion_stats *stats);
#define DM_MOTION(event, frame, ticket, ...) do { \
    if (dm_motion_record) { const double dm_mv_[DM_MOTION_VALUES] = {__VA_ARGS__}; \
        dm_motion_record((event), (frame), (ticket), dm_mv_); } \
} while (0)
