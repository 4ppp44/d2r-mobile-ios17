// 节拍器单测：给定时钟序列，期望等待时长手算。周期 16.666 ms 记为 P = 16666667 ns。
// Pacer unit tests: given a clock sequence, the expected wait durations are hand-calculated. The period 16.666 ms is written as P = 16666667 ns.
#include "../nvn/nvn_pace.h"
#include <stdio.h>

int main(void) {
    const uint64_t P = 16666667, MS = 1000000;
    struct { uint64_t now, period, want; const char *why; } c[] = {
        {1000 * MS, P, 0, "首帧：起拍，不等"},
        {1005 * MS, P, 1000 * MS + P - 1005 * MS, "早到 5 ms：等到 1000+P"},
        {1000 * MS + 2 * P - 2 * MS, P, 2 * MS, "第三帧早 2 ms：等 2 ms"},
        {1000 * MS + 3 * P + 3 * MS, P, 0, "迟到 3 ms（不足一周期）：立即出图，节拍点仍为 1000+3P"},
        {1000 * MS + 4 * P - 1 * MS, P, 1 * MS, "下一帧早 1 ms：按原相位等到 1000+4P"},
        {1000 * MS + 7 * P, P, 0, "落后两个周期（卡顿）：重新起拍于当时，不连发追帧"},
        {1000 * MS + 7 * P + 4 * MS, P, P - 4 * MS, "重新起拍后的下一帧：等到新目标"},
        {1000 * MS + 9 * P, 0, 0, "周期 0（DM_PRESENT_HZ=0）：不等"},
        {1000 * MS + 9 * P + 1 * MS, 2 * P, 2 * P - 1 * MS, "切回间隔 2：节拍点 = 上帧时刻 9P + 2P"},
        {1000 * MS + 11 * P + 3 * MS, 2 * P, 2 * P - 3 * MS, "间隔 2 下一帧：节拍点 13P"},
    };
    nvn_pacer p = {0}; int fail = 0, n = sizeof c / sizeof *c;
    for (int i = 0; i < n; i++) {
        uint64_t got = nvn_pace(&p, c[i].now, c[i].period);
        int ok = got == c[i].want;
        printf("%-52s 期望等 %8.3f ms → 真结果 %8.3f ms %s\n", c[i].why, c[i].want / 1e6, got / 1e6, ok ? "✓" : "✗");
        fail += !ok;
    }
    // 显示节拍取帧：一拍一帧、最多落后最新一帧（期望值手算：read=已取出，in=已入队，票号从 1 起）
    // Display-link frame pick: one frame per callback, at most one behind the newest (expected values hand-computed: read = taken, in = enqueued, tickets from 1)
    struct { uint64_t read, in, want; const char *why; } lk[] = {
        {0, 0, 0, "队列空：这一拍不出图"},
        {0, 1, 1, "只排了 1 帧：出这帧"},
        {1, 2, 2, "排了 1 帧：出这帧"},
        {0, 2, 1, "两帧落进同一刷新周期：先出旧帧（旧逻辑丢它、再驻留 33 ms）"},
        {0, 3, 2, "三帧积压：跳过最旧一帧，出第 2 帧（最多落后最新一帧）"},
        {5, 9, 8, "四帧积压：只出 in-1，其余按丢弃记账"},
        {7, 7, 0, "已取到最新：这一拍空转"},
        {3, 4, 4, "节拍恢复后追上一帧"},
    };
    for (int i = 0; i < (int)(sizeof lk / sizeof *lk); i++) {
        uint64_t got = nvn_link_pick(lk[i].read, lk[i].in); int ok = got == lk[i].want;
        printf("%-52s 期望票 %2llu → 真结果 %2llu %s\n", lk[i].why, (unsigned long long)lk[i].want, (unsigned long long)got, ok ? "✓" : "✗");
        fail += !ok; n++;
    }
    // 出图帧率：屏幕刷新率 ÷ k，取不低于目标的最小一档（期望值按 刷新率 ÷ floor(刷新率 ÷ 目标) 手算）
    // Present frame rate: screen refresh rate ÷ k, taking the smallest tier not below the target (expected values computed by hand as refresh rate ÷ floor(refresh rate ÷ target))
    struct { double scr, floor, want; const char *why; } h[] = {
        {60, 60, 60, "60 Hz 屏：60（与原先相同）"}, {120, 60, 60, "120 Hz 屏：60（与原先相同）"}, {144, 60, 72, "144 Hz 屏：72（144 ÷ 2）"},
        {165, 60, 82.5, "165 Hz 屏：82.5（165 ÷ 2）"}, {100, 60, 100, "100 Hz 屏：100（÷ 1）"}, {240, 60, 60, "240 Hz 屏：60（÷ 4）"},
        {119.88, 60, 59.94, "119.88 Hz：59.94（÷ 2，NTSC 档）"}, {59.94, 60, 59.94, "59.94 Hz：59.94（÷ 1）"}, {50, 60, 50, "50 Hz 屏：50（低于目标也只能 ÷ 1）"},
        {0, 60, 60, "读不到刷新率：按目标 60"}, {120, 30, 30, "省电 30，120 Hz 屏：30"}, {144, 30, 36, "省电 30，144 Hz 屏：36（÷ 4）"}, {60, 30, 30, "省电 30，60 Hz 屏：30"},
    };
    for (int i = 0; i < (int)(sizeof h / sizeof *h); i++) {
        double got = nvn_pace_hz(h[i].scr, h[i].floor); int ok = got > h[i].want - 1e-9 && got < h[i].want + 1e-9;
        printf("%-52s 期望 %7.3f Hz → 真结果 %7.3f Hz %s\n", h[i].why, h[i].want, got, ok ? "✓" : "✗"); fail += !ok; n++;
    }
    // CAMetalDisplayLink 超时时长测试：必须满足 100% 安全余量（2 * period），防止调度抖动假超时
    struct { uint64_t period; double service; uint64_t want; const char *why; } to[] = {
        {33333333ull, 60.0, 66666666ull, "省电 30 帧（周期 33.33 ms）：超时 66.67 ms（留 33.33 ms 余量）"},
        {16666667ull, 60.0, 33333334ull, "正常 60 帧（周期 16.67 ms）：超时 33.33 ms（留 16.67 ms 余量）"},
        {0, 60.0, 66666666ull, "周期为 0、服务 60 Hz：兜底 66.67 ms"},
        {0, 0, 66666666ull, "周期为 0、无服务频率：默认兜底 66.67 ms"},
    };
    for (int i = 0; i < (int)(sizeof to / sizeof *to); i++) {
        uint64_t got = nvn_link_timeout_ns(to[i].period, to[i].service);
        int ok = got == to[i].want;
        printf("%-52s 期望等 %8.3f ms → 真结果 %8.3f ms %s\n", to[i].why, to[i].want / 1e6, got / 1e6, ok ? "✓" : "✗");
        fail += !ok; n++;
    }
    printf("== %d 项，失败 %d ==\n", n, fail);
    return fail != 0;
}
