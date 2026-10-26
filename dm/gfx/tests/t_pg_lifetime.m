// 逐通道计时（DM_NVN_PASSGPU）的采样时刻数组生命周期：每次提交的完成回调各自 calloc 一份 used 个 uint64，
// 解析完必须释放。修复前每次提交泄漏 used*8 字节，长时间开测量会一路涨。
// 这里把 calloc / free 换成记账版本，走生产 rp_begin_ex / rp_end / mtl_sub_commit 真 Metal 提交：
// 先跑一次热身（初始化期的一次性分配落在这一步），记下当时未释放数；再跑 N 次，要求未释放数不变、且释放次数至少 N。
// 基线（本修复前）未释放数按 N 增长。像素仍按常量期望读回，证明通道确实跑了。
// Lifetime of the per-pass timestamp array (DM_NVN_PASSGPU): each submission's completion callback callocs its own array of `used`
// uint64 values and must release it after parsing. Before the fix every submission leaked used*8 bytes.
// calloc / free are replaced with accounting versions and the production rp_begin_ex / rp_end / mtl_sub_commit path is driven on real
// Metal: one warm-up submission (so one-time init allocations land there) records the outstanding count, then N submissions must leave
// that count unchanged and must have freed at least N arrays. On the pre-fix baseline the outstanding count grows by N. Pixels still
// read back the constant expectation, proving the passes really ran.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <pthread.h>

static pthread_mutex_t pg_mu = PTHREAD_MUTEX_INITIALIZER;
static void *pg_live[4096];
static unsigned pg_allocs, pg_frees, pg_outstanding;
static void *pg_calloc(size_t n, size_t s) {
    void *p = calloc(n, s);
    if (!p) return NULL;
    pthread_mutex_lock(&pg_mu);
    pg_allocs++;
    for (unsigned i = 0; i < 4096; i++) if (!pg_live[i]) { pg_live[i] = p; pg_outstanding++; break; }
    pthread_mutex_unlock(&pg_mu);
    return p;
}
static void pg_free(void *p) {
    if (p) {
        pthread_mutex_lock(&pg_mu);
        for (unsigned i = 0; i < 4096; i++) if (pg_live[i] == p) { pg_live[i] = NULL; pg_frees++; pg_outstanding--; break; }
        pthread_mutex_unlock(&pg_mu);
    }
    free(p);
}
#define calloc pg_calloc
#define free pg_free
#ifndef D2R_BACKEND_FILE
#define D2R_BACKEND_FILE "../nvn/nvn_mtl.m"
#endif
#include D2R_BACKEND_FILE
#undef calloc
#undef free

void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
int dm_guest_heap_stat(unsigned long long *t, unsigned long long *f, unsigned long long *m) { *t = *f = *m = 0; return 0; }

static int checks, failed;
#define CHECK(name, condition) do { int ok = (condition); checks++; failed += !ok; printf("%s %s\n", name, ok ? "PASS" : "FAIL"); } while (0)
static void counts(unsigned *a, unsigned *f, unsigned *live) { pthread_mutex_lock(&pg_mu); *a = pg_allocs; *f = pg_frees; *live = pg_outstanding; pthread_mutex_unlock(&pg_mu); }

// 生产路径清一张 4x4 贴图并提交一次；返回读回的第一个像素 R 字节
// Clear one 4x4 texture and submit once through the production path; returns the first pixel's R byte
static int clear_submit(tex_t *t, prog_t *pg, int draw_pass) {
    memset(&R, 0, sizeof R); R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = t;
    R.clear_c[0] = 1; R.cc[0] = MTLClearColorMake(0.5, 0.5, 0.5, 1);
    mtl_sub_begin();
    if (draw_pass) {
        state_reset(); S.prog = pg; R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = t;
        R.clear_c[0] = 1; R.cc[0] = MTLClearColorMake(0.5, 0.5, 0.5, 1);
        p_draw d = {NVN_DRAW_PRIMITIVE_TRIANGLES, 0, 3}; draw(&d, NULL); rp_end();
    } else { rp_begin_ex(1); rp_end(); }
    id<MTLBuffer> b = [g_dev newBufferWithLength:64 options:MTLResourceStorageModeShared]; res_add(b);
    [blit() copyFromTexture:tex_mtl(t) sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(4, 4, 1)
                   toBuffer:b destinationOffset:0 destinationBytesPerRow:16 destinationBytesPerImage:64];
    enc_b_end(g_blit); g_blit = nil;
    uint64_t f = mtl_sub_commit();
    if (!mtl_wait(f, 10000000000ull)) { failed++; printf("FAIL 提交未在 10 s 内完成\n"); return -1; }
    if (mtl_last_commit_error()) { failed++; printf("FAIL 提交反馈有错\n"); return -1; }
    return ((uint8_t *)b.contents)[0];
}

int main(int argc, char **argv) { @autoreleasepool {
    setvbuf(stdout, NULL, _IONBF, 0);
    unsigned submissions = argc > 1 ? (unsigned)strtoul(argv[1], NULL, 10) : 8;
    if (!submissions || submissions > 512) return 2;
    char tsv[PATH_MAX];
    // 固定写到 /tmp：环境里的 TMPDIR 可能指向已删除的目录，那样打不开通道表、整条用例假红 | Write to /tmp unconditionally: the environment's TMPDIR can point at a deleted directory, which would fail to open the pass table and make the case falsely red
    snprintf(tsv, sizeof tsv, "/tmp/d2r_pg_lifetime_%d.tsv", (int)getpid());
    setenv("DM_NVN_PASSGPU", tsv, 1);
    mtl_init();
    CHECK("profiling_enabled", pg_on() == 1);
    if (pg_on() != 1) { unlink(tsv); return 2; }

    NSError *shader_error = nil;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal; vertex float4 pgv(uint i [[vertex_id]]) { float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],0,1); } fragment float4 pgf() { return float4(0.5); }" options:nil error:&shader_error];
    NvProg *program = [NvProg new]; program->sh[0] = [NvShader new]; program->sh[1] = [NvShader new];
    program->sh[0]->fn = [lib newFunctionWithName:@"pgv"]; program->sh[1]->fn = [lib newFunctionWithName:@"pgf"]; program->sh[1]->stage = 1; strlcpy(program->sh[1]->key, "pg-test-fs", sizeof program->sh[1]->key);
    prog_t pg = {.serial = 880002}; serial_put(pg.serial, program);
    CHECK("metadata_shader_compiles", lib && program->sh[0]->fn && program->sh[1]->fn);
    tex_t t = {.serial = 880001};
    t.d.width = t.d.height = 4; t.d.depth = t.d.levels = t.d.samples = 1; t.d.target = NVN_TEXTURE_TARGET_2D; t.d.format = NVN_FORMAT_RGBA8;
    int bad = clear_submit(&t, &pg, 1) != 128;
    unsigned a0, f0, live0; counts(&a0, &f0, &live0);   // 热身：一次性初始化分配已发生 | Warm-up: the one-time init allocations have happened
    for (unsigned i = 0; i < submissions; i++) { if (clear_submit(&t, &pg, 0) != 128) bad++; }
    // 与真机一致：主队列上再提交一次并等它完成，把前面各次提交的完成回调（含 pg_commit 的解析与释放）全部走完
    // Same as on device: commit one more buffer on the main queue and wait, so every earlier completion handler (including pg_commit parsing and release) has run
    id<MTLCommandBuffer> tail = [g_q commandBuffer]; [tail commit]; [tail waitUntilCompleted];
    unsigned a1, f1, live1; counts(&a1, &f1, &live1);
    CHECK("every_pass_pixels_exact", bad == 0);
    printf("PG_LIFETIME submissions=%u allocs=%u->%u frees=%u->%u outstanding=%u->%u\n", submissions, a0, a1, f0, f1, live0, live1);
    CHECK("outstanding_unchanged_over_submissions", live1 == live0);
    CHECK("every_submission_freed_its_array", f1 - f0 >= submissions);
    pthread_mutex_lock(&g_pg_mu); if (g_pg_f) fflush(g_pg_f); pthread_mutex_unlock(&g_pg_mu);
    FILE *f = fopen(tsv, "r"); int rows = 0, header = 0, meta = 0;
    if (f) { char line[512]; while (fgets(line, sizeof line, f)) { rows++; if (strstr(line, "\tc0_ser\td_ser\tfs_key")) header = 1; if (strstr(line, "\t880001\t0\tpg-test-fs")) meta = 1; } fclose(f); }
    unlink(tsv);
    CHECK("pass_table_rows_written", rows > (int)submissions);   // 表头 + 每次提交至少一行 | header + at least one row per submission
    CHECK("pass_table_metadata_header", header);
    CHECK("draw_pass_shader_and_attachment_identity", meta);
    printf("PG_LIFETIME_REAL_METAL submissions=%u checks=%d failed=%d rows=%d\n", submissions, checks, failed, rows);
    return failed != 0;
} }
