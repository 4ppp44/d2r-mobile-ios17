// 上屏掉帧口径单测：直接测试生产头文件 nvn_pace.h 的 nvn_calc_pres_summary 与 nvn_pres_latch 实现
#include "../nvn/nvn_pace.h"
#include <stdio.h>
#include <math.h>
#include <string.h>

static int checks, fails;
#define CHECK(cond, desc) do { \
    checks++; \
    int pass_ = !!(cond); \
    if (!pass_) fails++; \
    printf("[%s] %s\n", pass_ ? "PASS" : "FAIL", desc); \
} while (0)

int main(void) {
    printf("== 测试生产 nvn_calc_pres_summary 与 nvn_pres_latch 上屏统计 ==\n");

    // 0. 负对照（旧逻辑基线复现）：如果使用写死 25.0ms 门限，30 帧 33.36ms 稳帧会全部被判为掉帧
    {
        double iv[300];
        for (int i = 0; i < 300; i++) iv[i] = 33.36;
        unsigned old_drop = 0;
        for (int i = 0; i < 300; i++) if (iv[i] > 25.0) old_drop++;
        CHECK(old_drop == 300, "负对照：旧写死 25ms 逻辑将 300 帧 33.36ms 满额误报为 300 掉帧");
    }

    // 1. 30 帧档（周期 33.3333 ms，门限 50.0 ms）：300 帧 33.36 ms 全部合格，掉帧 0
    {
        double iv[300];
        for (int i = 0; i < 300; i++) iv[i] = 33.36;
        nvn_pres_summary_t ps;
        int ok = nvn_calc_pres_summary(iv, NULL, 300, 1000.0 / 30.0, &ps);
        CHECK(ok == 1, "30 帧档计算成功");
        CHECK(ps.valid == 300 && ps.evaluated == 300, "30 帧档有效帧 300");
        CHECK(ps.drop == 0, "生产代码：30 帧档 33.36 ms 不被算作掉帧 (drop == 0)");
        CHECK(ps.discard == 0, "30 帧档丢弃 0");
        CHECK(fabs(ps.p50 - 33.36) < 1e-4, "30 帧档 p50 正确");
    }

    // 2. 60 帧档（周期 16.6667 ms，门限 25.0 ms）：300 帧 33.36 ms 全部超预算，掉帧 300
    {
        double iv[300];
        for (int i = 0; i < 300; i++) iv[i] = 33.36;
        nvn_pres_summary_t ps;
        int ok = nvn_calc_pres_summary(iv, NULL, 300, 1000.0 / 60.0, &ps);
        CHECK(ok == 1, "60 帧档计算成功");
        CHECK(ps.valid == 300 && ps.evaluated == 300, "60 帧档有效帧 300");
        CHECK(ps.drop == 300, "60 帧档 33.36 ms 全部算作超预算 (drop == 300)");
    }

    // 3. 60 帧档正常 16.68 ms：掉帧 0
    {
        double iv[300];
        for (int i = 0; i < 300; i++) iv[i] = 16.68;
        nvn_pres_summary_t ps;
        nvn_calc_pres_summary(iv, NULL, 300, 1000.0 / 60.0, &ps);
        CHECK(ps.drop == 0, "60 帧档 16.68 ms 掉帧 0");
    }

    // 4. 边界条件测试：恰好在门限上不掉，微超门限计掉帧
    {
        double iv[4] = {25.0, 25.001, 50.0, 50.001};
        nvn_pres_summary_t ps60, ps30;
        nvn_calc_pres_summary(iv, NULL, 2, 1000.0 / 60.0, &ps60);
        CHECK(ps60.drop == 1, "60 帧档边界：25.0 合格，25.001 超预算");

        nvn_calc_pres_summary(iv + 2, NULL, 2, 1000.0 / 30.0, &ps30);
        CHECK(ps30.drop == 1, "30 帧档边界：50.0 合格，50.001 超预算");
    }

    // 5. 窗口内动态切换目标帧率测试（前半窗 60fps，后半窗 30fps，间隔均为 33.36ms）
    {
        double iv[300], target[300];
        for (int i = 0; i < 150; i++) {
            iv[i] = 33.36;
            target[i] = 1000.0 / 60.0; // 60fps 目标 -> 33.36ms 掉帧
        }
        for (int i = 150; i < 300; i++) {
            iv[i] = 33.36;
            target[i] = 1000.0 / 30.0; // 30fps 目标 -> 33.36ms 合格
        }
        nvn_pres_summary_t ps;
        nvn_calc_pres_summary(iv, target, 300, 1000.0 / 60.0, &ps);
        CHECK(ps.evaluated == 300, "混合窗口评估 300 帧");
        CHECK(ps.drop == 150, "窗口内切档：前 150 帧按 60fps 算掉帧，后 150 帧按 30fps 不算掉帧 (drop == 150)");
    }

    // 6. 系统丢弃 (-1) 与无效样本 (0, NaN, Inf, -Inf) 处理
    {
        double iv[8] = {-1.0, 0.0, 33.36, -1.0, NAN, INFINITY, -INFINITY, 0.0};
        nvn_pres_summary_t ps;
        nvn_calc_pres_summary(iv, NULL, 8, 1000.0 / 30.0, &ps);
        CHECK(ps.valid == 1, "仅有限正数算入 valid (valid == 1)");
        CHECK(ps.discard == 2, "有限负数算入 discard (discard == 2)");
        CHECK(ps.evaluated == 3, "evaluated == valid + discard == 3");
        CHECK(ps.drop == 2, "drop == 2 (全部来自系统丢弃，33.36ms 不掉)");
    }

    // 7. 全丢弃无有效间隔 (valid == 0, discard > 0)
    {
        double iv[5] = {-1.0, -1.0, -1.0, -1.0, -1.0};
        nvn_pres_summary_t ps;
        int ok = nvn_calc_pres_summary(iv, NULL, 5, 1000.0 / 30.0, &ps);
        CHECK(ok == 1, "全丢弃时返回 1");
        CHECK(ps.valid == 0 && ps.discard == 5, "valid == 0, discard == 5");
        CHECK(ps.drop == 5, "drop == 5");
    }

    // 8. 全无读数 (valid == 0, discard == 0)
    {
        double iv[3] = {0.0, NAN, 0.0};
        nvn_pres_summary_t ps;
        int ok = nvn_calc_pres_summary(iv, NULL, 3, 1000.0 / 30.0, &ps);
        CHECK(ok == 0, "全无读数返回 0");
        CHECK(ps.evaluated == 0 && ps.valid == 0, "evaluated == 0");
    }

    // 9. 生产采样路径：30 -> 60 切换滞后 8 帧测试（审查员 R2 缺陷复现与修复验证）
    {
        nvn_pres_latch_t latch;
        memset(&latch, 0, sizeof latch);
        // 呈现 1..20 在 30fps (33.333ms) 提交
        for (uint64_t p = 1; p <= 20; p++) {
            nvn_pres_latch_record(&latch, p, 1000.0 / 30.0);
        }
        // 呈现 21 切换为 60fps (16.667ms) 提交
        for (uint64_t p = 21; p <= 30; p++) {
            nvn_pres_latch_record(&latch, p, 1000.0 / 60.0);
        }

        // 当出图线程在呈现 24 (当前为 60fps 阶段，当前周期 16.667ms) 取滞后 8 次的样本 n = 24 - 8 = 16
        uint64_t n = 16;
        double current_target_ms = 1000.0 / 60.0;
        double hist_target_ms = nvn_pres_latch_get(&latch, n, current_target_ms);
        CHECK(fabs(hist_target_ms - (1000.0 / 30.0)) < 1e-4, "30->60 切换时滞后 8 帧取回历史目标：期望 33.33ms");

        // 负对照验证：若错误使用当前目标 (16.667ms)，33.36ms 样本会误判为掉帧 (exit 1 复现)
        double iv_sample = 33.36;
        nvn_pres_summary_t ps_buggy, ps_fixed;
        nvn_calc_pres_summary(&iv_sample, &current_target_ms, 1, current_target_ms, &ps_buggy);
        CHECK(ps_buggy.drop == 1, "R2 负对照复现：错配当前目标时 33.36ms 误报掉帧");

        // 正对照：使用锁存的历史目标 (hist_target_ms)
        nvn_calc_pres_summary(&iv_sample, &hist_target_ms, 1, hist_target_ms, &ps_fixed);
        CHECK(ps_fixed.drop == 0, "R2 正对照修复：历史 30fps 目标下 33.36ms 正确判定合格 (drop == 0)");
    }

    // 10. 生产采样路径：60 -> 30 切换滞后 8 帧测试（防止新 30fps 目标掩盖 60fps 阶段的超预算）
    {
        nvn_pres_latch_t latch;
        memset(&latch, 0, sizeof latch);
        for (uint64_t p = 1; p <= 20; p++) {
            nvn_pres_latch_record(&latch, p, 1000.0 / 60.0);
        }
        for (uint64_t p = 21; p <= 30; p++) {
            nvn_pres_latch_record(&latch, p, 1000.0 / 30.0);
        }
        // 在呈现 24 取滞后 8 次的样本 n = 16 (60fps 阶段的超预算帧 33.36ms)
        uint64_t n = 16;
        double current_target_ms = 1000.0 / 30.0;
        double hist_target_ms = nvn_pres_latch_get(&latch, n, current_target_ms);
        CHECK(fabs(hist_target_ms - (1000.0 / 60.0)) < 1e-4, "60->30 切换时滞后 8 帧取回历史目标：期望 16.67ms");

        double iv_slow = 33.36;
        nvn_pres_summary_t ps;
        nvn_calc_pres_summary(&iv_slow, &hist_target_ms, 1, hist_target_ms, &ps);
        CHECK(ps.drop == 1, "60fps 阶段的 33.36ms 样本不被新的 30fps 目标掩盖，正确判定掉帧");
    }

    // 11. 环形复用与槽位过期安全测试
    {
        nvn_pres_latch_t latch;
        memset(&latch, 0, sizeof latch);
        nvn_pres_latch_record(&latch, 5, 33.333);
        // 写入 5 + 64 = 69，槽位 5 % 64 被新序号覆盖
        nvn_pres_latch_record(&latch, 69, 16.667);
        double fallback = 25.0;
        double res = nvn_pres_latch_get(&latch, 5, fallback);
        CHECK(res == fallback, "槽位已被覆盖时：序号不匹配安全退回 fallback 周期");
        double cur = nvn_pres_latch_get(&latch, 69, fallback);
        CHECK(fabs(cur - 16.667) < 1e-4, "当前有效序号读取正确");
    }

    // 12. 掉帧门限盲区：33.4-50.0 ms 这一档 drop 完全看不见，late_band 必须看见
    // 用两局真实 300 帧窗口的形状：一局 15 帧晚到 45.87 ms，另一局全部 33.36 ms
    {
        double clean[300], hitched[300];
        for (int i = 0; i < 300; i++) { clean[i] = 33.36; hitched[i] = i < 15 ? 45.87 : 33.36; }
        nvn_pres_summary_t a, b;
        nvn_calc_pres_summary(clean, NULL, 300, 1000.0 / 30.0, &a);
        nvn_calc_pres_summary(hitched, NULL, 300, 1000.0 / 30.0, &b);
        CHECK(a.late_band == 0 && a.over_lim == 0, "全 33.36 ms 窗口：盲区计数与超限计数都是 0");
        CHECK(b.late_band == 15, "15 帧晚到 45.87 ms 的窗口：盲区计数为 15");
        CHECK(b.over_lim == 0, "45.87 ms 未达 1.5 倍门限（50.0 ms），超限计数仍为 0");
        CHECK(a.drop == 0 && b.drop == 0, "负对照：两个窗口的 drop 都是 0，旧判据无法区分这两局");
        CHECK(b.late_band != a.late_band, "盲区计数能区分旧判据无法区分的两局（这就是新增它的理由）");
        CHECK(fabs(a.p95 - 33.36) < 1e-4 && fabs(b.p95 - 45.87) < 1e-4,
              "p95 在 5% 迟到时正好落在迟到值上（b 为 45.87）：这也是实测 001049 出现 p95 45.87 的来源");
    }

    // 13. 盲区边界：1.2 倍周期不含、恰在 1.5 倍门限上仍算盲区（超限才归 over_lim）
    {
        double iv[] = {40.0, 40.01, 50.0, 50.01};
        nvn_pres_summary_t ps;
        nvn_calc_pres_summary(iv, NULL, 4, 1000.0 / 30.0, &ps);
        CHECK(ps.late_band == 2, "40.0（恰 1.2 倍）不计，40.01 与 50.0 计入盲区，共 2 帧");
        CHECK(ps.over_lim == 1 && ps.drop == 1, "50.01 计入超限与 drop，各 1 帧");
    }

    // 14. 60 帧档同样适用：1.2 倍 = 20.0 ms，1.5 倍 = 25.0 ms
    {
        double iv[300];
        for (int i = 0; i < 300; i++) iv[i] = i < 30 ? 22.0 : 16.68;
        nvn_pres_summary_t ps;
        nvn_calc_pres_summary(iv, NULL, 300, 1000.0 / 60.0, &ps);
        CHECK(ps.late_band == 30, "60 帧档 30 帧 22.0 ms（1.32 倍）计入盲区");
        CHECK(ps.drop == 0, "同一批帧 drop 为 0（未达 25.0 ms）");
    }


    printf("== 测试结果：%d 项通过，%d 项失败 ==\n", checks - fails, fails);
    return fails != 0;
}
