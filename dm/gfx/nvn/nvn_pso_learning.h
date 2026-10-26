/* Candidate for review: learning CACHE only, never game saves.
 * Include after g_shmap_path and pso_user_path. Start before any shader loads.
 * Producer: fixed-size formatting/copy and at most four CAS attempts; no I/O,
 * ObjC allocations, waiting, thread creation, or logging. One worker owns FILE
 * and dedup set. Queue pressure explicitly loses rebuildable learning rows.
 * Shutdown must quiesce producers first; never join on a game/display callback.
 */
#ifndef NVN_PSO_LEARNING_H
#define NVN_PSO_LEARNING_H
#include <stdatomic.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#ifndef PSOL_CAP
#define PSOL_CAP 64u
#endif
#define PSOL_LINE 8192u
_Static_assert(PSOL_CAP >= 2 && !(PSOL_CAP & (PSOL_CAP - 1)), "queue capacity must be power of two");
typedef struct { _Atomic uint64_t seq; size_t len; char line[PSOL_LINE]; } psol_slot;
static struct {
    _Atomic uint64_t head, attempted, accepted, dropped, invalid, consumed;
    _Atomic uint64_t written, duplicates, failed, io_errors, input_errors;
    _Atomic uint64_t settled, repairs, repaired_bytes;
    _Atomic int accepting, stop, last_errno, enabled;
    uint64_t tail; /* consumer only */
    psol_slot slots[PSOL_CAP];
    pthread_t thread;
    int started;
} g_psol;
static NSString *g_psol_path, *g_psol_seed;
#ifndef PSOL_FOPEN
#define PSOL_FOPEN fopen
#endif
#ifndef PSOL_FPUTS
#define PSOL_FPUTS fputs
#endif
#ifndef PSOL_FFLUSH
#define PSOL_FFLUSH fflush
#endif
static void psol_io_error(void) {
    atomic_fetch_add(&g_psol.io_errors, 1);
    atomic_store(&g_psol.last_errno, errno ? errno : EIO);
}
static int psol_pop(char *line) {
    uint64_t pos = g_psol.tail;
    psol_slot *s = &g_psol.slots[pos & (PSOL_CAP - 1)];
    if (atomic_load_explicit(&s->seq, memory_order_acquire) != pos + 1) return 0;
    memcpy(line, s->line, s->len + 1);
    atomic_store_explicit(&s->seq, pos + PSOL_CAP, memory_order_release);
    g_psol.tail = pos + 1;
    atomic_fetch_add(&g_psol.consumed, 1);
    return 1;
}
/* Only this consumer owns the cache. Repair an interrupted previous append
 * before reading it for dedup. Never apply this policy to game saves. */
static int psol_repair_tail(FILE *f) {
    if (fseeko(f, 0, SEEK_END)) return -1;
    off_t end = ftello(f), keep = end;
    if (end < 0) return -1;
    while (keep > 0) {
        if (fseeko(f, keep - 1, SEEK_SET)) return -1;
        int c = fgetc(f); if (c == EOF) return -1;
        if (c == '\n') break;
        keep--;
    }
    if (keep != end) {
        if (ftruncate(fileno(f), keep)) return -1;
        atomic_fetch_add(&g_psol.repairs, 1);
        atomic_fetch_add(&g_psol.repaired_bytes, (uint64_t)(end - keep));
    }
    clearerr(f); return fseeko(f, 0, SEEK_END);
}
static void psol_disable_after_error(FILE **file, off_t good_end) {
    /* fclose can retry a failed buffered append. Close first, then roll back
     * the entire uncertain batch to the last confirmed complete boundary. */
    if (*file && fclose(*file)) psol_io_error();
    *file = NULL;
    int fd = open(g_psol_path.fileSystemRepresentation, O_WRONLY);
    if (fd < 0) { psol_io_error(); return; }
    if (ftruncate(fd, good_end)) psol_io_error();
    if (close(fd)) psol_io_error();
    /* Do not append more this session. Next launch repairs an interrupted tail
     * if rollback also failed. Loss is explicit and cache is rebuildable. */
}
static void *psol_worker(void *unused) {
    (void)unused;
    @autoreleasepool {
        FILE *f = PSOL_FOPEN(g_psol_path.fileSystemRepresentation, "a+");
        if (!f) psol_io_error();
        if (f && psol_repair_tail(f)) { psol_io_error(); fclose(f); f = NULL; }
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (NSString *path in @[g_psol_seed ?: @"", g_psol_path ?: @""]) {
            if (!path.length) continue;
            NSError *error = nil;
            NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
            if (!txt && error && !([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSFileReadNoSuchFileError)) atomic_fetch_add(&g_psol.input_errors, 1);
            for (NSString *row in [txt componentsSeparatedByString:@"\n"]) if (row.length && ![row hasPrefix:@"#"]) [seen addObject:row];
        }
        char line[PSOL_LINE];
        for (;;) {
            @autoreleasepool {
                NSMutableArray<NSString *> *pending = [NSMutableArray arrayWithCapacity:16];
                NSMutableSet<NSString *> *batch = [NSMutableSet setWithCapacity:16];
                off_t good_end = f ? ftello(f) : 0; int batch_bad = 0;
                if (f && good_end < 0) { psol_io_error(); fclose(f); f = NULL; }
                for (unsigned i = 0; i < 16 && psol_pop(line); i++) {
                    size_t n = strlen(line);
                    NSString *row = [[NSString alloc] initWithBytes:line length:n - 1 encoding:NSUTF8StringEncoding];
                    if (!row) { atomic_fetch_add(&g_psol.failed, 1); continue; }
                    if ([seen containsObject:row] || [batch containsObject:row]) { atomic_fetch_add(&g_psol.duplicates, 1); continue; }
                    if (!f || batch_bad) { atomic_fetch_add(&g_psol.failed, 1); continue; }
                    if (PSOL_FPUTS(line, f) < 0) { psol_io_error(); batch_bad = 1; atomic_fetch_add(&g_psol.failed, 1); continue; }
                    [pending addObject:row]; [batch addObject:row];
                }
                if (pending.count && !batch_bad && PSOL_FFLUSH(f) != 0) { psol_io_error(); batch_bad = 1; }
                if (batch_bad) {
                    atomic_fetch_add(&g_psol.failed, pending.count);
                    psol_disable_after_error(&f, good_end);
                } else { [seen addObjectsFromArray:pending]; atomic_fetch_add(&g_psol.written, pending.count); }
                atomic_store_explicit(&g_psol.settled, g_psol.tail, memory_order_release);
                /* Stop is requested only after producers quiesce, including any
                 * producer that reserved head before publishing its slot. */
                if (atomic_load(&g_psol.stop) && g_psol.tail == atomic_load(&g_psol.head)) break;
                struct timespec pause = {0, 2000000}; nanosleep(&pause, NULL);
            }
        }
        if (f && fclose(f)) psol_io_error();
    }
    return NULL;
}
static void pso_learning_start(void) {
    if (g_psol.started) return;
    g_psol.started = 1;
    for (uint64_t i = 0; i < PSOL_CAP; i++) atomic_init(&g_psol.slots[i].seq, i);
    g_psol_path = [pso_user_path() copy];
    g_psol_seed = g_shmap_path ? [[g_shmap_path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"pso_manifest.tsv"] : nil;
    if (!g_psol_path) { atomic_store(&g_psol.last_errno, ENOENT); return; }
    if (!atomic_is_lock_free(&g_psol.head) || !atomic_is_lock_free(&g_psol.slots[0].seq)) { atomic_store(&g_psol.last_errno, ENOTSUP); return; }
    int rc = pthread_create(&g_psol.thread, NULL, psol_worker, NULL);
    if (rc) { atomic_store(&g_psol.last_errno, rc); return; }
    atomic_store(&g_psol.enabled, 1);
    atomic_store_explicit(&g_psol.accepting, 1, memory_order_release);
}
static void pso_user_record(const char *fmt, ...) {
    atomic_fetch_add_explicit(&g_psol.attempted, 1, memory_order_relaxed);
    if (!atomic_load_explicit(&g_psol.accepting, memory_order_acquire)) { atomic_fetch_add(&g_psol.dropped, 1); return; }
    char line[PSOL_LINE]; va_list ap; va_start(ap, fmt); int n = vsnprintf(line, sizeof line, fmt, ap); va_end(ap);
    /* Existing S/R/C callers emit exactly one newline-terminated row. Reject
     * malformed/overlong rows instead of silently persisting truncated keys. */
    if (n <= 1 || (size_t)n >= sizeof line || line[n - 1] != '\n' || memchr(line, '\0', (size_t)n) || memchr(line, '\n', (size_t)n - 1)) { atomic_fetch_add(&g_psol.invalid, 1); return; }
    for (unsigned retry = 0; retry < 4; retry++) {
        uint64_t pos = atomic_load_explicit(&g_psol.head, memory_order_relaxed);
        if (pos >= UINT64_MAX - 2 * (uint64_t)PSOL_CAP) break;
        psol_slot *s = &g_psol.slots[pos & (PSOL_CAP - 1)];
        if (atomic_load_explicit(&s->seq, memory_order_acquire) != pos) continue;
        if (!atomic_compare_exchange_strong_explicit(&g_psol.head, &pos, pos + 1, memory_order_relaxed, memory_order_relaxed)) continue;
        s->len = (size_t)n; memcpy(s->line, line, (size_t)n + 1);
        atomic_store_explicit(&s->seq, pos + 1, memory_order_release);
        atomic_fetch_add_explicit(&g_psol.accepted, 1, memory_order_relaxed); return;
    }
    atomic_fetch_add_explicit(&g_psol.dropped, 1, memory_order_relaxed);
}
/* Nonblocking live snapshot: fields are individual atomic observations, not a
 * transactional snapshot. reserved_frontier includes unpublished reservations;
 * settled_frontier is the FIFO prefix whose write/duplicate/error outcomes are
 * known. Export may wait asynchronously for a captured frontier, with a timeout
 * and explicit pending status; it must never join on UIKit/render threads. */
typedef struct {
    uint64_t reserved_frontier, settled_frontier, attempted, accepted, dropped;
    uint64_t invalid, written, duplicates, failed, io_errors, input_errors;
    uint64_t repairs, repaired_bytes;
    int enabled, accepting, last_errno;
} pso_learning_stats;
static __attribute__((unused)) pso_learning_stats pso_learning_snapshot(void) {
    pso_learning_stats s = {0};
    s.reserved_frontier = atomic_load_explicit(&g_psol.head, memory_order_acquire);
    s.settled_frontier = atomic_load_explicit(&g_psol.settled, memory_order_acquire);
#define PSOL_COPY(field) s.field = atomic_load_explicit(&g_psol.field, memory_order_relaxed)
    PSOL_COPY(attempted); PSOL_COPY(accepted); PSOL_COPY(dropped); PSOL_COPY(invalid);
    PSOL_COPY(written); PSOL_COPY(duplicates); PSOL_COPY(failed); PSOL_COPY(io_errors);
    PSOL_COPY(input_errors); PSOL_COPY(repairs); PSOL_COPY(repaired_bytes);
    PSOL_COPY(enabled); PSOL_COPY(accepting); PSOL_COPY(last_errno);
#undef PSOL_COPY
    return s;
}
/* Candidate integration point for background lifecycle/export drain. The owner
 * must first stop/join all producers; normal render code must never call it. */
static __attribute__((unused)) int pso_learning_drain_timeout(uint64_t timeout_ms) {
    if (!atomic_load(&g_psol.enabled)) return 0;
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    uint64_t limit_ns = timeout_ms * 1000000ULL;
    while (atomic_load_explicit(&g_psol.settled, memory_order_acquire) !=
           atomic_load_explicit(&g_psol.head, memory_order_acquire)) {
        if (clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - t0 > limit_ns) return -1;
        struct timespec pause = {0, 1000000}; // 1ms
        nanosleep(&pause, NULL);
    }
    return 0;
}
static __attribute__((unused)) void pso_learning_join_quiescent(void) {
    atomic_store(&g_psol.accepting, 0);
    if (!atomic_load(&g_psol.enabled)) return;
    atomic_store(&g_psol.stop, 1); pthread_join(g_psol.thread, NULL);
    atomic_store(&g_psol.enabled, 0);
}
#endif
