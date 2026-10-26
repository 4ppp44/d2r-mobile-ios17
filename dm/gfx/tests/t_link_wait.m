// Exercise the production waiter, including a callback racing the timeout deadline.
#include <pthread.h>
#include <stdint.h>
#include <errno.h>
static int wait_result, wait_calls;
static uint64_t wake_tick;
static int deadline_wait(pthread_cond_t *, pthread_mutex_t *, const struct timespec *);
#define pthread_cond_timedwait deadline_wait
#include "../nvn/nvn_mtl.m"
#undef pthread_cond_timedwait
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int deadline_wait(pthread_cond_t *cv, pthread_mutex_t *mu, const struct timespec *ts) {
    (void)cv; (void)mu; (void)ts;
    // POSIX permits the predicate to become true as a timed wait expires.
    g_link_tick_n = wake_tick; wait_calls++; return wait_result;
}
static int failed;
#define CHECK(label, cond) do { int ok = !!(cond); failed += !ok; printf("%s %s\n", label, ok ? "PASS" : "FAIL"); } while (0)
int main(void) { @autoreleasepool {
    g_link = (CAMetalDisplayLink *)[NSObject new]; g_dm_present_link = 1; g_link_mode = 3;
    g_link_tick_n = 100; wake_tick = 102; wait_result = ETIMEDOUT;
    CHECK("callback_at_timeout_is_success", mtl_link_wait_tick(66666666) == 1);
    g_link_tick_n = 104; int before = wait_calls;
    CHECK("next_due_frame_does_not_wait", mtl_link_wait_tick(66666666) == 1 && wait_calls == before);
    wake_tick = 104; wait_result = ETIMEDOUT;
    CHECK("missing_callback_reports_timeout", mtl_link_wait_tick(66666666) == 0);
    wake_tick = 106; wait_result = 0;
    CHECK("resumes_after_real_timeout", mtl_link_wait_tick(66666666) == 1);
    g_link_tick_n = 109; before = wait_calls;
    CHECK("one_callback_late_starts_immediately", mtl_link_wait_tick(66666666) == 1 && wait_calls == before);
    g_link_tick_n = 110; before = wait_calls;
    CHECK("late_wake_keeps_even_callback_phase", mtl_link_wait_tick(66666666) == 1 && wait_calls == before);

    // 60 fps pacing: 60 Hz display link (step = 1, period = 16.67 ms, timeout = 33.33 ms)
    g_dm_present_link = 1; g_link_mode = 1;
    g_link_tick_n = 200; wake_tick = 201; wait_result = 0;
    CHECK("mode1_60fps_wait_tick_success", mtl_link_wait_tick(33333333) == 1);
    g_link_tick_n = 202; before = wait_calls;
    CHECK("mode1_60fps_next_due_does_not_wait", mtl_link_wait_tick(33333333) == 1 && wait_calls == before);
    wake_tick = 202; wait_result = ETIMEDOUT;
    CHECK("mode1_60fps_missing_callback_timeout", mtl_link_wait_tick(33333333) == 0);
    g_link_tick_n = 205; before = wait_calls;
    CHECK("mode1_60fps_late_starts_immediately", mtl_link_wait_tick(33333333) == 1 && wait_calls == before);

    // 60 fps pacing on 120 Hz ProMotion display (step = 2, period = 16.67 ms, service = 120 Hz)
    g_dm_present_link = 2; g_link_mode = 2;
    g_link_tick_n = 300; wake_tick = 302; wait_result = 0;
    CHECK("mode2_120hz_step2_wait_tick_success", mtl_link_wait_tick(33333333) == 1);
    g_link_tick_n = 304; before = wait_calls;
    CHECK("mode2_120hz_next_due_does_not_wait", mtl_link_wait_tick(33333333) == 1 && wait_calls == before);

    // Timeout and safety deadlines must be retained: 100% margin (2 * period)
    CHECK("timeout_calc_60fps", nvn_link_timeout_ns(16666667, 60) == 33333334);
    CHECK("timeout_calc_30fps", nvn_link_timeout_ns(33333333, 60) == 66666666);
    CHECK("safety_stall_ns_preserved", STALL_NS == 100000000ull);
    CHECK("safety_rescue_ns_preserved", LINK_RESCUE_NS == 500000000ull);

    // Present discard multi-reason bitmask lifecycle
    mtl_present_discard_reason(0, 1);
    mtl_present_discard_reason(1, 1);
    CHECK("discard_reasons_both_active", atomic_load(&g_present_discard) == 3);
    mtl_present_discard_reason(0, 0);
    CHECK("discard_reason_0_cleared", atomic_load(&g_present_discard) == 2);
    mtl_present_discard_reason(1, 0);
    CHECK("discard_reason_1_cleared", atomic_load(&g_present_discard) == 0);

    printf("LINK_WAIT failed=%d\n", failed); return failed != 0;
} }
