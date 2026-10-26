// Included once by diag.c; standalone probes may include this same implementation.
#pragma once
#include "dm_motion.h"
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>

static pthread_mutex_t g_motion_mu = PTHREAD_MUTEX_INITIALIZER;
static dm_motion_row g_motion_rows[DM_MOTION_CAPACITY];
static uint64_t g_motion_accepted;
static _Atomic uint64_t g_motion_contended;
uint64_t now_ns(void);

void dm_motion_record(unsigned event, uint64_t frame, uint64_t ticket,
                      const double value[DM_MOTION_VALUES]) {
    if (pthread_mutex_trylock(&g_motion_mu)) {
        atomic_fetch_add_explicit(&g_motion_contended, 1, memory_order_relaxed);
        return;
    }
    uint64_t n = g_motion_accepted++;
    dm_motion_row *r = &g_motion_rows[n % DM_MOTION_CAPACITY];
    r->sequence = n + 1; r->time_ns = now_ns(); r->frame = frame;
    r->ticket = ticket; r->event = event;
    memcpy(r->value, value, sizeof r->value);
    pthread_mutex_unlock(&g_motion_mu);
}

size_t dm_motion_snapshot(dm_motion_row *rows, size_t capacity, dm_motion_stats *stats) {
    pthread_mutex_lock(&g_motion_mu);
    uint64_t end = g_motion_accepted;
    size_t kept = end < DM_MOTION_CAPACITY ? (size_t)end : DM_MOTION_CAPACITY;
    size_t n = capacity < kept ? capacity : kept;
    if (!rows) n = 0;
    for (size_t i = 0; i < n; i++) rows[i] = g_motion_rows[(end - n + i) % DM_MOTION_CAPACITY];
    if (stats) *stats = (dm_motion_stats){end, end - kept,
        atomic_load_explicit(&g_motion_contended, memory_order_relaxed), n};
    pthread_mutex_unlock(&g_motion_mu);
    return n;
}
