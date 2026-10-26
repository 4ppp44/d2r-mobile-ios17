#ifndef DM_LOG_RING_H
#define DM_LOG_RING_H

#include <stdint.h>

typedef struct {
    uint64_t capacity_bytes, queued_bytes, high_water_bytes;
    uint64_t offered_chunks, offered_bytes, accepted_chunks, accepted_bytes;
    uint64_t dropped_chunks, dropped_bytes;
    uint64_t contention_drops, overflow_drops, oversize_drops, unavailable_drops;
    uint64_t dequeued_bytes, completed_bytes, durable_bytes, raw_pipe_bytes;
    uint64_t producer_max_ns, producer_calls, producer_stalls;
    uint64_t file_bytes, file_errors, mirror_errors, client_errors, fsync_errors;
    uint32_t startup_errno, worker_ready;
} dm_log_buffer_stats_t;

void dm_log_buffer_stats_get(dm_log_buffer_stats_t *out);
/* Snapshot of accepted ring bytes only (raw fd 2 may still be in the pipe).
 * Waits at most min(timeout_ms, 2000) ms; 1 = durable, 0 = timed out,
 * -1 = startup or file/fsync failure. Never call from a frame callback. */
int dm_log_flush(unsigned timeout_ms);

#ifdef DM_LOG_RING_IMPLEMENTATION
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>

#define DM_LOG_RING_CAPACITY (2u * 1024u * 1024u)
#define DM_LOG_RING_CHUNK (16u * 1024u)
#define DM_LOG_RING_MAX_OFFER (64u * 1024u)

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t wake;
    unsigned char data[DM_LOG_RING_CAPACITY];
    size_t head, used;
    _Atomic uint64_t queued, high_water;
    _Atomic uint64_t offered_chunks, offered_bytes, accepted_chunks, accepted_bytes;
    _Atomic uint64_t dropped_chunks, dropped_bytes;
    _Atomic uint64_t contention_drops, overflow_drops, oversize_drops, unavailable_drops;
    _Atomic uint64_t dequeued_bytes, completed_bytes, durable_bytes, raw_pipe_bytes;
    _Atomic uint64_t flush_target;
    _Atomic uint32_t startup_errno, ready;
} dm_log_ring_t;

static dm_log_ring_t g_log_ring = {.mutex = PTHREAD_MUTEX_INITIALIZER, .wake = PTHREAD_COND_INITIALIZER};

/* Whole callback admission: a rejected callback is never partially queued.
 * Returning ENOBUFS is telemetry, not a request for stdio to retry a log. */
static int dm_log_ring_offer(const char *p, size_t n) {
    dm_log_ring_t *r = &g_log_ring;
    atomic_fetch_add_explicit(&r->offered_chunks, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&r->offered_bytes, n, memory_order_relaxed);
    int reason = 0;
    if (!atomic_load_explicit(&r->ready, memory_order_acquire)) {
        atomic_fetch_add_explicit(&r->unavailable_drops, 1, memory_order_relaxed);
        reason = ENXIO;
    } else if (n > DM_LOG_RING_MAX_OFFER) {
        atomic_fetch_add_explicit(&r->oversize_drops, 1, memory_order_relaxed);
        reason = EMSGSIZE;
    } else if (pthread_mutex_trylock(&r->mutex)) {
        atomic_fetch_add_explicit(&r->contention_drops, 1, memory_order_relaxed);
        reason = EBUSY;
    } else {
        if (n > DM_LOG_RING_CAPACITY - r->used) {
            atomic_fetch_add_explicit(&r->overflow_drops, 1, memory_order_relaxed);
            reason = ENOBUFS;
        } else {
            size_t tail = (r->head + r->used) % DM_LOG_RING_CAPACITY;
            size_t first = DM_LOG_RING_CAPACITY - tail;
            if (first > n) first = n;
            memcpy(r->data + tail, p, first);
            memcpy(r->data, p + first, n - first);
            r->used += n;
            atomic_store_explicit(&r->queued, r->used, memory_order_relaxed);
            if (r->used > atomic_load_explicit(&r->high_water, memory_order_relaxed))
                atomic_store_explicit(&r->high_water, r->used, memory_order_relaxed);
            atomic_fetch_add_explicit(&r->accepted_chunks, 1, memory_order_relaxed);
            atomic_fetch_add_explicit(&r->accepted_bytes, n, memory_order_release);
            if (r->used == n) pthread_cond_signal(&r->wake);
        }
        pthread_mutex_unlock(&r->mutex);
    }
    if (reason) {
        atomic_fetch_add_explicit(&r->dropped_chunks, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&r->dropped_bytes, n, memory_order_relaxed);
    }
    return reason;
}

/* Single consumer copies a bounded batch, then releases the lock before I/O. */
static size_t dm_log_ring_take(char *p, size_t capacity) {
    dm_log_ring_t *r = &g_log_ring;
    pthread_mutex_lock(&r->mutex);
    size_t n = r->used < capacity ? r->used : capacity;
    size_t first = DM_LOG_RING_CAPACITY - r->head;
    if (first > n) first = n;
    memcpy(p, r->data + r->head, first);
    memcpy(p + first, r->data, n - first);
    r->head = (r->head + n) % DM_LOG_RING_CAPACITY;
    r->used -= n;
    atomic_store_explicit(&r->queued, r->used, memory_order_relaxed);
    atomic_fetch_add_explicit(&r->dequeued_bytes, n, memory_order_relaxed);
    pthread_mutex_unlock(&r->mutex);
    return n;
}
#endif
#endif
