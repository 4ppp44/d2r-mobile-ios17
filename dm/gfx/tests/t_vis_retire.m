// Real occlusion-query overflow: exact counts/pixels, fence retention, address-map retirement.
#ifndef D2R_BACKEND_FILE
#define D2R_BACKEND_FILE "../nvn/nvn_mtl.m"
#endif
#include D2R_BACKEND_FILE
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(name, condition) do { int ok = (condition); checks++; failed += !ok; printf("%s %s\n", name, ok ? "PASS" : "FAIL"); } while (0)
static void counter_reset(void) {
    struct { op_hdr h; uint64_t type; op_hdr end; } c = {
        {OP_RESET_COUNTER, 16}, NVN_COUNTER_TYPE_SAMPLES_PASSED, {OP_END, 8}
    };
    mtl_exec((const uint8_t *)&c);
}
int main(int argc, char **argv) { @autoreleasepool {
    unsigned passes = argc > 1 ? (unsigned)strtoul(argv[1], NULL, 10) : VIS_SLOTS + 1;
    if (!passes || passes > 2 * VIS_SLOTS + 1) return 2;
    mtl_init();
    NSError *error = nil;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal; vertex float4 v(uint i [[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],0,1); } fragment float4 f() { return float4(0,1,0,1); }" options:nil error:&error];
    CHECK("real_shader_compiled", lib != nil); if (!lib) return 2;
    NvProg *pr = [NvProg new]; pr->sh[0] = [NvShader new]; pr->sh[1] = [NvShader new];
    pr->sh[0]->fn = [lib newFunctionWithName:@"v"]; pr->sh[1]->fn = [lib newFunctionWithName:@"f"]; pr->sh[1]->stage = 1;
    prog_t pg = {.serial = 750001}; serial_put(pg.serial, pr);
    tex_t target = {.serial = 750002}; target.d.width = target.d.height = 8;
    target.d.depth = target.d.levels = target.d.samples = 1;
    target.d.target = NVN_TEXTURE_TARGET_2D; target.d.format = NVN_FORMAT_RGBA8;
    id<MTLBuffer> observed = nil;
    uint64_t retired_gpu = 0, report[2] = {0};
    mtl_sub_begin(); counter_reset(); S.prog = &pg; S.chmask.mask = 15;
    memset(&R, 0, sizeof R); R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = &target;
    S.vp[0][2] = S.vp[0][3] = 8; S.has_vp = 1;
    p_draw triangle = {NVN_DRAW_PRIMITIVE_TRIANGLES, 0, 3};
    for (unsigned i = 0; i < passes; i++) {
        draw(&triangle, NULL); rp_end();
    }
    CHECK("every_pass_drawn", g_stat_draw == passes);
    CHECK("expected_overflow_boundary", vis_in_ring(g_vis) == (passes <= VIS_SLOTS));
    if (passes > VIS_SLOTS) {
        observed = g_vis; retired_gpu = observed.gpuAddress;
        CHECK("overflow_registered_before_commit", [g_res_objects containsObject:observed]);
    }
    post((post_op){3, NULL, 0, 0, (uint64_t)report, NVN_COUNTER_TYPE_SAMPLES_PASSED, vis_snapshot()});
    id<MTLBuffer> pixels = [g_dev newBufferWithLength:256 options:MTLResourceStorageModeShared];
    [blit() copyFromTexture:tex_mtl(&target) sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(8,8,1) toBuffer:pixels destinationOffset:0 destinationBytesPerRow:32 destinationBytesPerImage:256];
    CHECK("query_GPU_completed", mtl_wait(mtl_sub_commit(), 10000000000ull));
    CHECK("query_GPU_no_error", !mtl_last_commit_error());
    CHECK("all_query_samples_exact", report[0] == (uint64_t)passes * 64);
    uint8_t green[4] = {0,255,0,255}; int bad = 0;
    for (int i = 0; i < 64; i++) bad += memcmp((uint8_t *)pixels.contents + i * 4, green, 4) != 0;
    CHECK("all_pixels_exact_green", bad == 0);
    mtl_sub_begin(); counter_reset();
    CHECK("ring_reselected", vis_in_ring(g_vis));
    if (observed) {
        defer_drain(); // This submission has not completed: retirement must still retain the object.
        CHECK("overflow_retained_until_retirement_fence", [g_res_objects containsObject:observed]);
    }
    id<MTLCommandBuffer> retirement_cb = g_cb;
    uint64_t f = mtl_sub_commit(); CHECK("retirement_GPU_completed", mtl_wait(f, 5000000000ull));
    // The public fence wakes before deferred cleanup at the end of its completion handler.
    // 原生等待也等完成处理器结束，避免在它摘表到撤驻留之间抢读。
    [retirement_cb waitUntilCompleted];
    defer_drain();
    if (observed) {
        CHECK("overflow_removed_from_registry", ![g_res_objects containsObject:observed]);
        NSUInteger off = 0;
        CHECK("retired_GPU_address_unresolvable", m3_buf(retired_gpu, &off) == nil);
        observed = nil;
    }
    // Drain Metal's completed-command-buffer bookkeeping through the real queue.
    mtl_drain();
    for (int i = 0; i < g_vis_ring_n; i++) CHECK("ring_remains_registered", [g_res_objects containsObject:g_vis_ring[i].buf]);
    printf("VIS_RETIRE_REAL_METAL passes=%u checks=%d failed=%d query=%llu\n", passes, checks, failed, (unsigned long long)report[0]);
    return failed != 0;
} }
