// 同绘制去重的真实 Metal 验证（本机 M1，不是 A16 证据）：只断言"该跳的跳、不该跳的不跳"。
//  0) 缺省是关（开关只能靠环境变量或 Documents/dm_dup_draw 文件，真机上只有后者可用）；
//  1) 两次逐字节相同的绘制（同管线、同参数块、同几何、中间无记录）→ 第二次不发；
//  2) 中间插一条状态记录（换 UBO 地址，走真实回放循环）→ 不跳；
//  2b) 中间插一条**不改状态但改数据**的记录（屏障；UPDATE_UB / COPY_B2B / DISPATCH 同一类）→ 不跳；
//  3) 混合打开 → 不跳（写出的像素不再幂等）；
//  4) 遮挡查询计数进行中 → 不跳（计数会变）；
//  5) 程序有可写存储缓冲 → 不跳（可能有原子 / 侧写）。
// 2b 是这一版修掉的洞：判据原先用「状态代号」，而 OP_UPDATE_UB（CPU 数据上传进 UBO）、OP_COPY_B2B、OP_DISPATCH 都不改状态，
// 用状态代号判会把它们漏掉，把两次内容不同的绘制判成相同。
// 用法与 t_vis_retire 一致：伪造 prog_t + serial_put，用 R.rt 开通道，不碰真实着色器映射表。
// Real-Metal verification of duplicate-draw removal (this M1 host, not A16 evidence): asserts "skip what must be skipped, keep what
// must be kept".
//  1) two byte-identical draws (same pipeline, same argument blocks, same geometry, no state record in between) -> second not issued;
//  2) a state record in between (a different UBO address) -> not skipped;
//  3) blending on -> not skipped (the written pixels are no longer idempotent);
//  4) an occlusion query counting -> not skipped (the count would change);
//  5) a writable storage buffer in the program -> not skipped (possible atomics / side writes).
// Same harness as t_vis_retire: a fake prog_t + serial_put, R.rt opens the pass, the real shader map is never touched.
#ifndef D2R_BACKEND_FILE
#define D2R_BACKEND_FILE "../nvn/nvn_mtl.m"
#endif
#include D2R_BACKEND_FILE
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
void mtl_dup_draw_stats(uint64_t *dups);
static int checks, failed;
#define CK(n,c) do{int ok=(c);checks++;failed+=!ok;printf("%s %s\n",n,ok?"PASS":"FAIL");}while(0)
// 走真实回放循环跑一条记录（后面跟 OP_END）：测的是「记录代号」的接线，不是直接改计数器
// Run one record through the real replay loop (followed by OP_END): this tests the wiring of the record epoch, not a counter set by hand
static void exec_one(uint32_t op, const void *payload, size_t len) {
    uint32_t sz = (uint32_t)((8 + len + 7) & ~(size_t)7);
    uint8_t mem[512];
    op_hdr h = {op, sz};
    memcpy(mem, &h, 8);
    if (payload && len) memcpy(mem + 8, payload, len);
    memset(mem + 8 + len, 0, sz - 8 - len);
    op_hdr e = {OP_END, 8};
    memcpy(mem + sz, &e, 8);
    mtl_exec(mem);
}

int main(void) { @autoreleasepool {
    unsetenv("DM_NVN_DUP_DRAW"); unsetenv("DM_SAVE");
    CK("default_off", dup_switch() == 0);   // 缺省关：判据覆盖不到客体原地写 | off by default: the test cannot cover guest in-place writes
    setenv("DM_NVN_DUP_DRAW", "1", 1);      // 本测试显式打开（真机上用 Documents/dm_dup_draw） | enabled explicitly here (a device uses Documents/dm_dup_draw)
    mtl_init();
    // 先空跑一次回放循环：它首次调用会 state_reset，必须先于下面搭的状态 | run the replay loop once first: its first call does state_reset, so it must precede the state set up below
    { op_hdr e = {OP_END, 8}; mtl_exec((const uint8_t *)&e); }
    NSError *error = nil;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:
        @"#include <metal_stdlib>\nusing namespace metal;\n"
         "vertex float4 v(uint i [[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],0,1); }\n"
         "fragment float4 f() { return float4(0,1,0,1); }\n" options:nil error:&error];
    CK("real_MSL", lib != nil); if (!lib) return 2;
    NvProg *pr = [NvProg new]; pr->sh[0] = [NvShader new]; pr->sh[1] = [NvShader new];
    pr->sh[0]->fn = [lib newFunctionWithName:@"v"]; pr->sh[1]->fn = [lib newFunctionWithName:@"f"]; pr->sh[1]->stage = 1;
    prog_t pg = {.serial = 760001}; serial_put(pg.serial, pr);
    tex_t target = {.serial = 760002}; target.d.width = target.d.height = 16;
    target.d.depth = target.d.levels = target.d.samples = 1;
    target.d.target = NVN_TEXTURE_TARGET_2D; target.d.format = NVN_FORMAT_RGBA8;
    mtl_sub_begin(); S.prog = &pg; S.chmask.mask = 15;
    memset(&R, 0, sizeof R); R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = &target;
    S.vp[0][2] = S.vp[0][3] = 16; S.has_vp = 1;
    p_draw dw = {NVN_DRAW_PRIMITIVE_TRIANGLES, 0, 3};
    uint64_t ps_ = 0, d0 = 0, draws0 = 0;
    mtl_dup_draw_stats(&d0); mtl_stats(&ps_, &draws0);
    draw(&dw, NULL);   // 首次：必须发 | first: must be issued
    draw(&dw, NULL);   // 逐字节相同：必须跳 | byte-identical: must be skipped
    uint64_t d1 = 0, draws1 = 0; mtl_dup_draw_stats(&d1); mtl_stats(&ps_, &draws1);
    CK("identical_second_draw_skipped", d1 - d0 == 1);
    CK("only_one_draw_issued", draws1 - draws0 == 1);
    // 2) 中间插状态记录 → 不跳 | a state record in between -> not skipped
    p_bind_buf ub = {.stage = 0, .index = 0, .addr = 0x1000, .size = 256};
    exec_one(OP_BIND_UBO, &ub, sizeof ub);
    draw(&dw, NULL);
    uint64_t d2 = 0, draws2 = 0; mtl_dup_draw_stats(&d2); mtl_stats(&ps_, &draws2);
    CK("state_record_prevents_skip", d2 == d1 && draws2 - draws1 == 1);
    // 2b) 中间插一条不改状态、但会改数据的记录（屏障；UPDATE_UB / COPY_B2B / DISPATCH 同一类）→ 不跳
    // a record that changes no state but does change the data (a barrier; UPDATE_UB / COPY_B2B / DISPATCH are the same class) -> not skipped
    draw(&dw, NULL);   // 让上一次身份就位 | establish the previous identity
    uint64_t d2b0 = 0, draws2b0 = 0; mtl_dup_draw_stats(&d2b0); mtl_stats(&ps_, &draws2b0);
    int bits = 0x1f; exec_one(OP_BARRIER, &bits, sizeof bits);
    draw(&dw, NULL);
    uint64_t d2b = 0, draws2b = 0; mtl_dup_draw_stats(&d2b); mtl_stats(&ps_, &draws2b);
    CK("nonstate_record_prevents_skip", d2b == d2b0 && draws2b - draws2b0 == 1);
    // 3) 混合打开 → 不跳 | blending on -> not skipped
    draw(&dw, NULL);   // 让上一次身份就位 | establish the previous identity
    uint64_t d3 = 0, draws3 = 0; mtl_dup_draw_stats(&d3); mtl_stats(&ps_, &draws3);
    S.color.blend_en = 1;
    draw(&dw, NULL);
    uint64_t d4 = 0, draws4 = 0; mtl_dup_draw_stats(&d4); mtl_stats(&ps_, &draws4);
    CK("blend_prevents_skip", d4 == d3 && draws4 - draws3 == 1);
    S.color.blend_en = 0;
    // 4) 遮挡计数进行中 → 不跳 | an occlusion query counting -> not skipped
    g_vis_counting = 1;
    uint64_t d5 = 0, draws5 = 0; mtl_dup_draw_stats(&d5); mtl_stats(&ps_, &draws5);
    draw(&dw, NULL); draw(&dw, NULL);
    uint64_t d6 = 0, draws6 = 0; mtl_dup_draw_stats(&d6); mtl_stats(&ps_, &draws6);
    CK("visibility_counting_prevents_skip", d6 == d5 && draws6 - draws5 == 2);
    g_vis_counting = 0;
    // 5) 可写存储缓冲 → 不跳 | a writable storage buffer -> not skipped
    pr->fl_ok = 0; pr->sh[1]->rf.nb = 1; pr->sh[1]->rf.b[0] = (nvn_rbind){.kind = NVN_RB_SBUFP, .reg = 0, .aid = 0, .rw = 1};
    draw(&dw, NULL); draw(&dw, NULL);
    uint64_t d7 = 0, draws7 = 0; mtl_dup_draw_stats(&d7); mtl_stats(&ps_, &draws7);
    CK("writable_buffer_prevents_skip", d7 == d6 && draws7 - draws6 == 2);
    rp_end();
    CK("GPU_completed", mtl_wait(mtl_sub_commit(), 5000000000ull));
    CK("GPU_no_error", mtl_last_commit_error() == 0);
    printf("DUP_DRAW_REAL_METAL checks=%d failed=%d\n", checks, failed);
    return failed ? 1 : 0;
} }
