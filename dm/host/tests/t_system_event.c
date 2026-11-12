// Service-event lifetimes through real binding / CloseHandle SVCs.
// Covers duplicate binding, rapid replacement beyond initial capacity without leak,
// storage & handle reuse with binding lifetime identity, rebind after destruction,
// and safe host thread signalling after event destruction while guest retains lazy creation.
#include "../hle_thread.c"
#include <assert.h>
#include <stdio.h>
#include <string.h>

struct dm_flags g_flag;
uint64_t g_t0_ns;
void crash_thread_init(void) {}
void guest_thread_init(void) {}
void dm_thread_enter(uint64_t entry, uint64_t arg, uint64_t sp) { (void)entry; (void)arg; (void)sp; abort(); }
module_t *module_of(const void *p) { (void)p; return NULL; }
void dm_prof_add(int id, uint64_t ns, uint64_t bytes) { (void)id; (void)ns; (void)bytes; }
#include <mach/mach_time.h>
uint64_t now_ns(void) { static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb); return mach_absolute_time() * tb.numer / tb.denom; }
uint64_t guest_ns(void) { return now_ns(); }
int dm_detclock_enabled(void) { return 0; }

typedef struct { uint32_t wh, rh; } test_event;

static uint32_t create_event(void *p, int mode, int interprocess) {
    (void)interprocess;
    test_event *ev = p;
    uint64_t r[8] = {0, 0, (uint64_t)mode};
    if (svc_thread(0x45, r) != 1) return 1;
    ev->wh = (uint32_t)r[1];
    ev->rh = (uint32_t)r[2];
    return 0;
}

static uint32_t writable_event(const void *p) {
    const test_event *ev = p;
    return ev->wh;
}

void *guest_sym(const char *name) {
    if (!strcmp(name, "_ZN2nn2os17CreateSystemEventEPNS0_15SystemEventTypeENS0_14EventClearModeEb")) return (void *)create_event;
    if (!strcmp(name, "_ZN2nn2os30GetWritableHandleOfSystemEventEPKNS0_15SystemEventTypeE")) return (void *)writable_event;
    return NULL;
}

static void destroy_event(test_event *ev) {
    uint64_t r[8];
    if (ev->wh) { r[0] = ev->wh; svc_thread(0x16, r); ev->wh = 0; }
    if (ev->rh) { r[0] = ev->rh; svc_thread(0x16, r); ev->rh = 0; }
}

static int signalled(test_event *ev) {
    pthread_mutex_lock(&G);
    event_t *e = h_get(ev->wh, O_EVENT_W);
    int s = e ? e->signaled : 0;
    pthread_mutex_unlock(&G);
    return s;
}

static void duplicate(void) {
    test_event ev = {0};
    hle_bind_system_event(&ev, 1);
    uint64_t b1 = hle_system_event_binding(&ev);
    assert(b1 != 0);
    assert(g_nse == 1);
    hle_bind_system_event(&ev, 1);
    uint64_t b2 = hle_system_event_binding(&ev);
    assert(b1 == b2);
    assert(g_nse == 1);
    destroy_event(&ev);
    assert(g_nse == 0);
}

static void capacity(void) {
    // Repeated fast replacement must unbind on CloseHandle and never leak or overflow g_se table
    test_event ev[16];
    memset(ev, 0, sizeof ev);
    for (unsigned i = 0; i < 16; i++) {
        hle_bind_system_event(&ev[i], 0);
        destroy_event(&ev[i]);
    }
    assert(g_nse == 0);
}

static void reuse(void) {
    test_event ev = {0};
    hle_bind_system_event(&ev, 0);
    uint64_t old_binding = hle_system_event_binding(&ev);
    assert(old_binding != 0);
    uint32_t old_wh = ev.wh;
    destroy_event(&ev);
    assert(g_nse == 0);

    // Rebind at the exact same address; slot recycling forces handle number reuse as well
    hle_bind_system_event(&ev, 0);
    assert(ev.wh == old_wh);
    uint64_t new_binding = hle_system_event_binding(&ev);
    assert(new_binding != 0 && new_binding != old_binding);

    // Stale binding ID must not signal the new event
    int ret1 = hle_signal_system_event_binding(old_binding);
    assert(!ret1);
    assert(!signalled(&ev));

    // New binding ID signals successfully
    int ret2 = hle_signal_system_event_binding(new_binding);
    assert(ret2 && signalled(&ev));
    destroy_event(&ev);
    assert(g_nse == 0);
}

static void rebind(void) {
    test_event ev = {0};
    hle_bind_system_event(&ev, 0);
    uint64_t b1 = hle_system_event_binding(&ev);
    destroy_event(&ev);
    hle_bind_system_event(&ev, 0);
    uint64_t b2 = hle_system_event_binding(&ev);
    assert(b1 != 0 && b2 != 0 && b1 != b2);
    assert(hle_signal_system_event_binding(b2));
    assert(signalled(&ev));
    destroy_event(&ev);
    assert(g_nse == 0);
}

static void host_signal(void) {
    test_event ev = {0};
    hle_bind_system_event(&ev, 0);
    void *guest = pthread_getspecific(g_keythr);
    pthread_setspecific(g_keythr, NULL);
    hle_signal_system_event(&ev);
    assert(signalled(&ev));
    destroy_event(&ev);

    // Host thread signalling a destroyed event must not die/abort, skipped safely
    hle_signal_system_event(&ev);
    hle_signal_system_event(&ev);
    assert(g_nse == 0);

    pthread_setspecific(g_keythr, guest);
    // Guest thread still lazy-binds service events not yet bound
    hle_signal_system_event(&ev);
    assert(signalled(&ev));
    destroy_event(&ev);
    assert(g_nse == 0);
}

int main(void) {
    svc_thread_main_init();
    duplicate();
    capacity();
    reuse();
    rebind();
    host_signal();
    printf("t_system_event: ok\n");
    return 0;
}
