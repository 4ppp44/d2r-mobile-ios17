// 出图节拍器（纯函数，Mac / iOS 共用；单测 tests/t_pace.c）。
// 语义同垂直同步：节拍点 = 上一节拍点 + 周期。早到 → 等到节拍点；迟到不足一个周期 → 立即出图、保持原相位；
// 落后一个周期以上（卡顿）→ 从当前时刻重新起拍，不连发追帧。周期 0 = 不等（节拍点跟随当前时刻）。
// Present pacer (pure function, shared by Mac / iOS; unit test tests/t_pace.c).
// Semantics as vsync: present slot = previous present slot + period. Early → wait until the present slot; late by less than one period → present immediately and keep the original phase;
// behind by one period or more (stutter) → restart the cadence from the current time, no burst of presents to catch up. Period 0 = no wait (the present slot follows the current time).
#pragma once
#include <stdint.h>

typedef struct { uint64_t target; } nvn_pacer;

// now：单调时钟（ns）；period：本帧周期（ns，0 = 不等）。返回需要等待的 ns（0 = 立即出图），并更新内部目标时刻。
// now: monotonic clock (ns); period: this frame's period (ns, 0 = no wait). Returns the ns to wait (0 = present immediately) and updates the internal target time.
static inline uint64_t nvn_pace(nvn_pacer *p, uint64_t now, uint64_t period) {
    if (!period || !p->target) { p->target = now; return 0; }
    uint64_t next = p->target + period;
    if (now <= next) { p->target = next; return next - now; }
    p->target = now - next < period ? next : now;
    return 0;
}

// 出图帧率 = 屏幕刷新率的整数分之一里不低于目标（60，省电模式 30）的最小一档：每帧在屏上停整数个刷新周期，没有交替抖动。
// 60 / 120 Hz 屏 → 60；144 → 72；165 → 82.5；100 → 100；240 → 60；省电 30：120 → 30、144 → 36。刷新率读不到（0）就按目标。
// 0.02 的余量让 119.88 / 59.94 这类 NTSC 档按 2 / 1 倍算
// Present frame rate = the smallest tier among integer fractions of the screen refresh rate that is not below the target (60, power saving mode 30): each frame stays on screen for an integer number of refresh cycles, with no alternating jitter.
// 60 / 120 Hz screen → 60; 144 → 72; 165 → 82.5; 100 → 100; 240 → 60; power saving 30: 120 → 30, 144 → 36. When the refresh rate cannot be read (0), the target is used.
// The 0.02 margin lets NTSC rates like 119.88 / 59.94 count as 2 / 1 times
static inline double nvn_pace_hz(double screen_hz, double floor_hz) {
    if (screen_hz <= 0 || floor_hz <= 0) return floor_hz;
    double k = (double)(long)(screen_hz / floor_hz + 0.02); return k >= 1 ? screen_hz / k : screen_hz;
}

// CAMetalDisplayLink 等待超时：必须留出至少一整帧的安全余量，防止调度抖动（0.01~5ms）导致频繁假超时
// 省电 30 帧（周期 33.33ms）超时为 2 * period = 66.67ms；60 帧（周期 16.67ms）超时为 33.33ms。
static inline uint64_t nvn_link_timeout_ns(uint64_t period_ns, double service_hz) {
    if (period_ns > 0) return 2 * period_ns;
    if (service_hz > 0) return (uint64_t)(4e9 / service_hz);
    return 66666666ull;
}

// 显示节拍取帧：给定「已取出」read 与「已入队」in（票号从 1 起），返回这一拍要出的票号；队列空返回 0。
// 一拍只出一帧、最多落后最新一帧：排队两帧时本拍先出旧帧、下一拍出新帧；三帧及以上才跳过更旧的帧。
// 旧行为（每拍直接取最新帧）在两帧落进同一刷新周期时把前一帧整帧丢掉、前前帧在屏上驻留 33 ms，正是 60 fps 下 16~17.5 ms 耗时浮动的常见微卡顿。
// Display-link frame pick: given "taken" read and "enqueued" in (tickets start at 1), returns the ticket to present this callback; 0 when the queue is empty.
// One frame per callback, at most one frame behind the newest: with two queued the older one goes out now and the newer one next callback; only three or more skip older frames.
// The old behaviour (always take the newest) threw away the previous frame outright when two landed in the same refresh cycle and left the one before it on screen for 33 ms -- exactly the common micro-stutter at 60 fps with 16-17.5 ms frame times.
static inline uint64_t nvn_link_pick(uint64_t read, uint64_t in) {
    if (in <= read) return 0;
    uint64_t first = read + 1;
    return in - first >= 2 ? in - 1 : first;
}

#include <string.h>
#include <math.h>
#include <stdlib.h>

#define NVN_TWIN 300
#define NVN_PRES_LATCH_N 64

typedef struct {
    uint64_t ordinal[NVN_PRES_LATCH_N];
    double target_ms[NVN_PRES_LATCH_N];
} nvn_pres_latch_t;

static inline void nvn_pres_latch_record(nvn_pres_latch_t *l, uint64_t ordinal, double target_ms) {
    if (!l) return;
    unsigned idx = (unsigned)(ordinal % NVN_PRES_LATCH_N);
    l->ordinal[idx] = ordinal;
    l->target_ms[idx] = target_ms;
}

static inline double nvn_pres_latch_get(const nvn_pres_latch_t *l, uint64_t ordinal, double fallback_target_ms) {
    if (!l) return fallback_target_ms;
    unsigned idx = (unsigned)(ordinal % NVN_PRES_LATCH_N);
    if (l->ordinal[idx] == ordinal && l->target_ms[idx] > 0 && isfinite(l->target_ms[idx])) {
        return l->target_ms[idx];
    }
    return fallback_target_ms;
}

typedef struct {
    unsigned evaluated; // 有效上屏 + 丢弃
    unsigned valid;     // 有效正有限间隔帧数
    unsigned drop;      // 掉帧数（间隔 > 对应门限 或被系统丢弃）
    unsigned discard;   // 系统丢弃数（iv < 0）
    unsigned late_band; // 落在掉帧门限盲区（1.2–1.5 倍周期）的帧数：迟到明显但不够判掉帧，旧口径完全看不见 | frames in the drop-threshold blind band (1.2-1.5x period): clearly late but not enough to count as dropped, invisible to the old metric
    unsigned over_lim;  // 与 drop 同档的计数（间隔 > 1.5 倍周期），单列便于对照两个口径 | same band as drop (interval > 1.5x period), listed separately to compare the two metrics
    double drop_lim;    // 默认或最终判据门限（ms）
    double p5, p50, p95, p99;
} nvn_pres_summary_t;

static inline int nvn_pres_dcmp(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

static inline int nvn_calc_pres_summary(const double *iv, const double *target_ms, unsigned n, double fallback_period_ms, nvn_pres_summary_t *out) {
    if (!out) return 0;
    memset(out, 0, sizeof *out);
    double dflt_per = (fallback_period_ms > 0 && isfinite(fallback_period_ms)) ? fallback_period_ms : (1000.0 / 60.0);
    out->drop_lim = dflt_per * 1.5;
    unsigned k = 0, drop = 0, discard = 0, band = 0, over = 0;
    double v[NVN_TWIN];
    for (unsigned i = 0; i < n && i < NVN_TWIN; i++) {
        double x = iv[i];
        double per = (target_ms && target_ms[i] > 0 && isfinite(target_ms[i])) ? target_ms[i] : dflt_per;
        double lim = per * 1.5;
        if (x < 0 && isfinite(x)) {
            drop++;
            discard++;
        } else if (x > 0 && isfinite(x)) {
            v[k++] = x;
            drop += (x > lim);
            band += (x > per * 1.2 && x <= lim);
            over += (x > lim);
        }
    }
    out->evaluated = k + discard;
    out->valid = k;
    out->drop = drop;
    out->discard = discard;
    out->late_band = band;
    out->over_lim = over;
    if (k) {
        qsort(v, k, sizeof *v, nvn_pres_dcmp);
        out->p5 = v[(k * 5) / 100];
        out->p50 = v[k / 2];
        out->p95 = v[(k * 95) / 100 < k ? (k * 95) / 100 : k - 1];
        out->p99 = v[(k * 99) / 100 < k ? (k * 99) / 100 : k - 1];
    }
    return (k > 0 || discard > 0);
}
