#include <stdio.h>
#include <stdatomic.h>
#include <stdint.h>
#include <time.h>
#include <pthread.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(cond, desc) do { \
    checks++; \
    if (cond) { pass++; } \
    else { fails++; printf("  [FAIL line %d] %s\n", __LINE__, desc); } \
} while (0)

typedef struct {
    _Atomic uint64_t max_ns;
    _Atomic uint64_t total_ns;
    _Atomic uint64_t calls;
    _Atomic uint64_t stalls;
    _Atomic uint64_t bytes;
    _Atomic uint64_t errors;
    _Atomic uint32_t last_errno;
} dm_io_role_stat_t;

static dm_io_role_stat_t g_stat_prod;
static dm_io_role_stat_t g_stat_file;
static dm_io_role_stat_t g_stat_mirror;
static dm_io_role_stat_t g_stat_fsync;

static void io_role_record(dm_io_role_stat_t *st, uint64_t dt_ns, ssize_t bytes, int err) {
    atomic_fetch_add_explicit(&st->calls, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&st->total_ns, dt_ns, memory_order_relaxed);
    if (bytes > 0) atomic_fetch_add_explicit(&st->bytes, (uint64_t)bytes, memory_order_relaxed);
    if (err) {
        atomic_fetch_add_explicit(&st->errors, 1, memory_order_relaxed);
        atomic_store_explicit(&st->last_errno, (uint32_t)err, memory_order_relaxed);
    }
    if (dt_ns > 5000000ull) {
        atomic_fetch_add_explicit(&st->stalls, 1, memory_order_relaxed);
        uint64_t cur = atomic_load_explicit(&st->max_ns, memory_order_relaxed);
        while (dt_ns > cur && !atomic_compare_exchange_weak_explicit(&st->max_ns, &cur, dt_ns, memory_order_relaxed, memory_order_relaxed)) {}
    }
}

static int stderr_pipe_cookie_writer(void *cookie, const char *buf, int size) {
    int fd = (int)(intptr_t)cookie;
    if (size <= 0) return 0;
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    ssize_t written = 0;
    const char *p = buf;
    size_t rem = (size_t)size;
    int err = 0;
    while (rem) {
        ssize_t w = write(fd, p, rem);
        if (w > 0) { p += w; rem -= (size_t)w; written += w; }
        else if (w < 0 && errno == EINTR) continue;
        else { err = w < 0 ? errno : EPIPE; break; }
    }
    uint64_t dt = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - t0;
    io_role_record(&g_stat_prod, dt, written, err);
    return (int)(written > 0 ? written : (err ? -1 : 0));
}

static void write_file_checked(int fd, const char *p, size_t n) {
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    size_t rem = n;
    ssize_t written = 0;
    int err = 0;
    while (rem) {
        ssize_t w = write(fd, p, rem);
        if (w > 0) { p += w; rem -= (size_t)w; written += w; }
        else if (w < 0 && errno == EINTR) continue;
        else { err = w < 0 ? errno : EPIPE; break; }
    }
    uint64_t dt = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - t0;
    io_role_record(&g_stat_file, dt, written, err);
}

static void log_fsync_checked(int fd) {
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    int r = fsync(fd);
    int err = (r == 0) ? 0 : errno;
    uint64_t dt = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - t0;
    io_role_record(&g_stat_fsync, dt, 0, err);
}

#define LOG(...) do { fprintf(stderr, "[dm] " __VA_ARGS__); fputc('\n', stderr); } while (0)

static int rfd;
static void *slow_reader(void *a) {
    (void)a;
    char b[4096];
    while (read(rfd, b, sizeof b) > 0) usleep(25000); // 25ms delay per read
    close(rfd);
    return NULL;
}

int main(void) {
    int checks = 0, pass = 0, fails = 0;

    // 1. Setup pipe and slow reader
    int pp[2];
    if (pipe(pp) != 0) { printf("pipe failed\n"); return 1; }
    rfd = pp[0];
    int saved_stderr_fd = dup(2);
    if (saved_stderr_fd < 0 || dup2(pp[1], 2) < 0) { printf("dup2 failed\n"); return 1; }
    close(pp[1]);

    FILE *saved_stderr = stderr;
    FILE *hooked = funopen((void *)(intptr_t)2, NULL, stderr_pipe_cookie_writer, NULL, NULL);
    setvbuf(hooked, NULL, _IONBF, 0);
    stderr = hooked;

    pthread_t th;
    if (pthread_create(&th, NULL, slow_reader, NULL) != 0) { printf("pthread_create failed\n"); return 1; }

    // Test 1: LOG writes pass through hook and detect pipe backpressure stalls
    char big[1024];
    memset(big, 'x', sizeof big - 1);
    big[sizeof big - 1] = 0;
    for (int i = 0; i < 128; i++) {
        LOG("%s", big);
    }
    fflush(stderr);
    dup2(saved_stderr_fd, 2);
    close(saved_stderr_fd);
    pthread_join(th, NULL);
    stderr = saved_stderr;

    uint64_t prod_stalls = atomic_load(&g_stat_prod.stalls);
    double prod_max_ms = (double)atomic_load(&g_stat_prod.max_ns) / 1e6;
    uint64_t prod_bytes = atomic_load(&g_stat_prod.bytes);

    CHECK(prod_stalls > 0, "LOG with slow pipe must record write stalls");
    CHECK(prod_max_ms >= 20.0, "LOG max write stall must be >= 20ms");
    CHECK(prod_bytes >= 128 * 1024, "LOG must record correct bytes written");

    // Test 2: Unrelated fd write does NOT affect prod or file stats
    uint64_t pre_calls = atomic_load(&g_stat_prod.calls);
    uint64_t pre_file_calls = atomic_load(&g_stat_file.calls);
    int dummy_pipe[2];
    pipe(dummy_pipe);
    write(dummy_pipe[1], "hello unrelated fd", 18);
    close(dummy_pipe[0]);
    close(dummy_pipe[1]);

    CHECK(atomic_load(&g_stat_prod.calls) == pre_calls, "Unrelated write must NOT increment prod calls");
    CHECK(atomic_load(&g_stat_file.calls) == pre_file_calls, "Unrelated write must NOT increment file calls");

    // Test 3: fsync error handling on bad fd
    log_fsync_checked(-1);
    CHECK(atomic_load(&g_stat_fsync.errors) == 1, "fsync on -1 must record 1 error");
    CHECK(atomic_load(&g_stat_fsync.last_errno) == EBADF, "fsync error errno must be EBADF");

    // Test 4: File writer isolation
    FILE *tmp = tmpfile();
    int tmpfd = fileno(tmp);
    write_file_checked(tmpfd, "disk log line\n", 14);
    log_fsync_checked(tmpfd);
    fclose(tmp);

    CHECK(atomic_load(&g_stat_file.bytes) == 14, "write_file_checked must record file bytes");
    CHECK(atomic_load(&g_stat_file.calls) == 1, "write_file_checked must record file calls");
    CHECK(atomic_load(&g_stat_prod.calls) == pre_calls, "write_file_checked must NOT increment prod calls");
    // Test 5: Mirror writer isolation
    int mirror_p[2];
    pipe(mirror_p);
    io_role_record(&g_stat_mirror, 12000000ull, 24, 0);
    close(mirror_p[0]); close(mirror_p[1]);
    CHECK(atomic_load(&g_stat_mirror.stalls) == 1, "mirror stall recorded");
    CHECK(atomic_load(&g_stat_mirror.bytes) == 24, "mirror bytes recorded");

    printf("t_log_io_separate: %d checks, %d passed, %d failures\n", checks, pass, fails);
    return fails == 0 ? 0 : 1;
}
