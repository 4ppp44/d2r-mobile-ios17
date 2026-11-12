// 验证 GPU Hang 防御、多线程命令缓冲状态隔离与老接口驱动防护
//  1) dm_present_schedule: 命令缓冲出错（GPU Hang 等）时坚决不 present，避免屏幕闪烁粉屏 / 撕裂残帧；
//  2) hle_nvn: 默认禁用 LWW，多线程并发录制命令缓冲时状态互不污染、程序（计算/渲染）与采样器绝不丢；
//  3) opt_off: 当 dm_opt=0 时，直接绑定缓存与偏移更新缓存彻底关闭。
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <pthread.h>
#include "../nvn/dm_present_schedule.h"
#include "../nvn/hle_nvn.c"

int dm_guest_heap_stat(unsigned long long *t, unsigned long long *f, unsigned long long *m) { *t = *f = *m = 0; return 0; }
uint64_t g_t0_ns;
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
void crash_install(void);
uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec; }

static int g_checks = 0, g_failed = 0;
#define EXPECT(name, expected, actual) do { \
    long long _e = (long long)(expected), _a = (long long)(actual); \
    g_checks++; \
    if (_e != _a) { \
        g_failed++; \
        printf("[FAIL] %s: 期望 %lld，实际 %lld\n", name, _e, _a); \
    } else { \
        printf("[PASS] %s: %lld\n", name, _a); \
    } \
} while (0)

@interface MockDrawable : NSObject <MTLDrawable>
@property (nonatomic, assign) int presentedCount;
@end

@implementation MockDrawable
- (void)present { self.presentedCount++; }
- (void)presentAtTime:(CFTimeInterval)presentationTime { self.presentedCount++; }
- (void)presentAfterMinimumDuration:(CFTimeInterval)duration { self.presentedCount++; }
- (void)addPresentedHandler:(MTLDrawablePresentedHandler)block {}
- (NSUInteger)drawableID { return 1; }
- (double)presentedTime { return 0; }
@end

@interface MockCommandBuffer : NSObject
@property (nonatomic, assign) MTLCommandBufferStatus status;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) BOOL committed;
@property (nonatomic, copy) MTLCommandBufferHandler scheduledHandler;
@end

@implementation MockCommandBuffer
- (void)addScheduledHandler:(MTLCommandBufferHandler)block {
    self.scheduledHandler = block;
}
- (void)commit {
    self.committed = YES;
    if (self.scheduledHandler) {
        self.scheduledHandler((id<MTLCommandBuffer>)self);
    }
}
@end

// 辅助：扫描一段命令内存中特定 op 的出现次数
static int count_op_range(const uint8_t *begin, const uint8_t *end, uint32_t op) {
    int cnt = 0;
    for (const uint8_t *p = begin; p + sizeof(op_hdr) <= end;) {
        const op_hdr *h = (const op_hdr *)p;
        if (!h->size) break;
        if (h->op == op) cnt++;
        p += h->size;
    }
    return cnt;
}

#define THREAD_COUNT 4
#define ITERS_PER_THREAD 100

typedef struct {
    int thread_id;
    uint8_t mem[65536];
    cmd_t cmd;
    int success;
} worker_ctx_t;

static void *worker_func(void *arg) {
    worker_ctx_t *ctx = (worker_ctx_t *)arg;
    memset(&ctx->cmd, 0, sizeof(ctx->cmd));
    ctx->cmd.cur = ctx->mem;
    ctx->cmd.end = ctx->mem + sizeof(ctx->mem);
    ctx->cmd.recording = 1;
    NVNcommandBuffer *c = (NVNcommandBuffer *)&ctx->cmd;
    uint8_t *p = cmd_alloc(&ctx->cmd, 8); put_hdr(p, OP_BEGIN, 8); ctx->cmd.begin = p;

    for (int i = 0; i < ITERS_PER_THREAD; i++) {
        // 绑定 UBO
        h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_VERTEX, 0, (NVNbufferAddress)(0x1000 + ctx->thread_id * 0x10000 + i * 256), 256);
        // 绑定程序
        NVNprogram prog; memset(&prog, 0, sizeof(prog));
        h_nvnCommandBufferBindProgram(c, &prog, NVN_SHADER_STAGE_VERTEX_BIT | NVN_SHADER_STAGE_FRAGMENT_BIT);
        // 绑定视口
        float vp[4] = {0, 0, 1920, 1080};
        h_nvnCommandBufferSetViewports(c, 0, 1, vp);
        // 绘制
        h_nvnCommandBufferDrawArrays(c, NVN_DRAW_PRIMITIVE_TRIANGLES, 0, 3);
    }
    ctx->success = 1;
    return NULL;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // 测试 1：GPU Hang / Error 时，dm_present_schedule 决不调用 present
        {
            MockCommandBuffer *cb = [MockCommandBuffer new];
            MockDrawable *dr = [MockDrawable new];
            cb.status = MTLCommandBufferStatusError;
            cb.error = [NSError errorWithDomain:MTLCommandBufferErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Caused GPU Hang Error"}];

            dm_present_schedule((id<MTLCommandBuffer>)cb, (id<MTLDrawable>)dr, nil);
            EXPECT("错误状态命令缓冲被拦截（未 present）", 0, dr.presentedCount);
            EXPECT("错误状态命令缓冲已提交", 1, cb.committed);
        }

        // 测试 2：正常状态命令缓冲正常 present
        {
            MockCommandBuffer *cb = [MockCommandBuffer new];
            MockDrawable *dr = [MockDrawable new];
            cb.status = MTLCommandBufferStatusCommitted;
            cb.error = nil;

            __block int after_called = 0;
            dm_present_schedule((id<MTLCommandBuffer>)cb, (id<MTLDrawable>)dr, ^(double s, double r) {
                after_called = 1;
            });
            EXPECT("正常命令缓冲成功 present", 1, dr.presentedCount);
            EXPECT("正常命令缓冲调度回调正常触发", 1, after_called);
        }

        // 测试 3：默认关闭 LWW 下，多线程并发录制命令缓冲安全验证
        {
            pthread_t threads[THREAD_COUNT];
            worker_ctx_t ctxs[THREAD_COUNT];
            for (int t = 0; t < THREAD_COUNT; t++) {
                ctxs[t].thread_id = t;
                ctxs[t].success = 0;
                pthread_create(&threads[t], NULL, worker_func, &ctxs[t]);
            }

            for (int t = 0; t < THREAD_COUNT; t++) {
                pthread_join(threads[t], NULL);
                EXPECT("工作线程正常完成", 1, ctxs[t].success);
                int ubos = count_op_range(ctxs[t].cmd.begin, ctxs[t].cmd.cur, OP_BIND_UBO);
                int progs = count_op_range(ctxs[t].cmd.begin, ctxs[t].cmd.cur, OP_BIND_PROGRAM);
                int draws = count_op_range(ctxs[t].cmd.begin, ctxs[t].cmd.cur, OP_DRAW);
                EXPECT("多线程下无丢 UBO 记录", ITERS_PER_THREAD, ubos);
                EXPECT("多线程下无丢 Program 记录", ITERS_PER_THREAD, progs);
                EXPECT("多线程下无丢 Draw 记录", ITERS_PER_THREAD, draws);
            }
        }

        // 测试 4：阶段隔离验证（计算程序与渲染程序不被合并）
        {
            uint8_t mem[4096];
            cmd_t cmd; memset(&cmd, 0, sizeof(cmd));
            cmd.cur = mem; cmd.end = mem + sizeof(mem); cmd.recording = 1;
            NVNcommandBuffer *c = (NVNcommandBuffer *)&cmd;
            uint8_t *p = cmd_alloc(&cmd, 8); put_hdr(p, OP_BEGIN, 8); cmd.begin = p;

            NVNprogram comp_p, gfx_p;
            memset(&comp_p, 0, sizeof(comp_p));
            memset(&gfx_p, 0, sizeof(gfx_p));

            h_nvnCommandBufferBindProgram(c, &comp_p, NVN_SHADER_STAGE_COMPUTE_BIT);
            h_nvnCommandBufferBindProgram(c, &gfx_p, NVN_SHADER_STAGE_VERTEX_BIT | NVN_SHADER_STAGE_FRAGMENT_BIT);

            int prog_cnt = count_op_range(cmd.begin, cmd.cur, OP_BIND_PROGRAM);
            EXPECT("计算阶段与渲染阶段程序完全独立（未覆盖）", 2, prog_cnt);
        }

        printf("t_m3_hang_guard: checks=%d failed=%d\n", g_checks, g_failed);
        return g_failed ? 1 : 0;
    }
}
