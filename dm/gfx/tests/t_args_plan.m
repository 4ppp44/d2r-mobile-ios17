// 绑定计划 / 驱动常量段块缓存 / 客体地址解析缓存的真实 Metal 验证（本机 M1，不是 A16 证据）。
// 三个不变量，逐条断言：
//  1) 同一提交内本阶段的绑定行没变：整块参数缓冲直接复用（不重编、不重填驱动段）。
//  2) 只有贴图 / 采样器行变化时：c0 驱动段（只读存储缓冲行）不得重建。
//  3) 存储缓冲行变化时：c0 驱动段必须重建，且新块里的地址 / 大小就是新绑定值。
// 另断言客体地址解析缓存命中（省掉池表线性扫描）且换地址后失效。
// Real-Metal verification of the binding plan / driver-segment block cache / guest address memo (this M1 host, not A16 evidence).
// Three invariants, each asserted:
//  1) within one submission with this stage's binding rows unchanged the whole argument block is reused (no re-encode, no refill).
//  2) when only the texture / sampler rows change, the c0 driver segment (which reads only the storage-buffer rows) must not rebuild.
//  3) when the storage-buffer rows change, the c0 segment must rebuild and the new block must hold the new address / size.
// Also asserted: the guest address memo hits (a pool-table scan avoided) and goes stale when the address changes.
#ifndef D2R_BACKEND_FILE
#define D2R_BACKEND_FILE "../nvn/nvn_mtl.m"
#endif
#include D2R_BACKEND_FILE
void *front_metal_layer(void){return NULL;}module_t *module_of(const void *p){(void)p;return NULL;}module_t g_mod[MAX_MOD];int g_nmod;void svc_thread_dump(void){}uint64_t now_ns(void){return bp_now();}
void mtl_drv_fill_stats(uint64_t *fills);
static int checks, failed;
#define CK(n,c) do{int ok=(c);checks++;failed+=!ok;printf("%s %s\n",n,ok?"PASS":"FAIL");}while(0)

// 一个只读驱动段 c0 的片元着色器：argument buffer 里 id(0) 是设备指针，反射声明 DRV0 读一个槽（0x510 = 片元阶段存储缓冲表基址）
// A fragment shader that reads driver segment c0 only: id(0) of the argument buffer is a device pointer, and the reflection declares
// DRV0 reading one slot (0x510 = base of the fragment-stage storage-buffer table)
static NvShader *drv_shader(id<MTLLibrary> l) {
    NvShader *s = [NvShader new];
    s->fn = [l newFunctionWithName:@"f"]; s->ae = [s->fn newArgumentEncoderWithBufferIndex:1];
    s->arg_len = s->ae.encodedLength; s->rf.abi = 1; s->stage = 1;
    s->rf.nb = 1; s->rf.b[0] = (nvn_rbind){.kind = NVN_RB_DRV0, .reg = 0, .aid = 0};
    s->rf.drv_read[0] = 1; s->rf.drv_noff[0] = 1; s->rf.drv_off[0][0] = 0x510;
    strlcpy(s->key, "drv0", sizeof s->key);
    return s;
}
int main(void) { @autoreleasepool {
    mtl_init();
    NSError *err = nil;
    // 片元着色器只声明一个设备指针：反射里由 DRV0 提供 | The fragment declares only a device pointer, supplied by DRV0 in the reflection
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nstruct A{device float *x [[id(0)]];};\nfragment float4 f(constant A&a [[buffer(1)]]){return float4(a.x[0],0,0,1);}\n" options:nil error:&err];
    NvShader *sh = drv_shader(lib);
    // 池与绑定：两块客体内存，用来观察地址解析缓存与驱动段重建 | Pools and bindings: two guest allocations, to observe the address memo and the segment rebuild
    void *mem[2]; for (int i = 0; i < 2; i++) { posix_memalign(&mem[i], getpagesize(), getpagesize()); memset(mem[i], 0, getpagesize()); *(float *)mem[i] = (float)(i + 1); mtl_pool_add(mem[i], getpagesize()); }
    S.ssbo[1][0] = (p_bind_buf){.stage = 1, .index = 0, .addr = (uint64_t)mem[0], .size = 256};   // 片元阶段存储缓冲行 = 驱动段 c0 的数据来源 | the fragment-stage storage-buffer row feeds driver segment c0
    S.ubo[0][0] = (p_bind_buf){.stage = 0, .index = 0, .addr = (uint64_t)mem[0], .size = 256};
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [g_dev newTextureWithDescriptor:td];
    MTLRenderPassDescriptor *pd = [MTLRenderPassDescriptor renderPassDescriptor];
    pd.colorAttachments[0].texture = tex; pd.colorAttachments[0].loadAction = MTLLoadActionClear; pd.colorAttachments[0].storeAction = MTLStoreActionStore;
    mtl_sub_begin(); g_pass.serial++;
    id<MTLRenderCommandEncoder> enc = enc_r_begin(pd);
    uint64_t f0 = 0, m0 = 0; mtl_drv_fill_stats(&f0); m0 = g_stat_addr_memo;
    // 1) 首次编码：驱动段建一次 | First encode: the segment is built once
    CK("encode_1", encode_args(enc, sh, 1, 0));
    uint64_t f1 = 0; mtl_drv_fill_stats(&f1);
    CK("first_encode_builds_segment", f1 - f0 == 1);
    uint64_t gpu1 = sh->drv_blk[0].gpu;
    // 2) 只有贴图行变化：整块必须重编，但 c0 段不得重建 | Only the texture row changes: the block must re-encode, but the c0 segment must not rebuild
    uint64_t before = g_stat_args_enc; S.tex[1][0] = 12345; args_touch_row(1, 2);
    CK("encode_2", encode_args(enc, sh, 1, 0));
    uint64_t f2 = 0; mtl_drv_fill_stats(&f2);
    CK("tex_row_change_reencodes_block", g_stat_args_enc - before == 1);
    CK("tex_row_change_keeps_c0_segment", f2 == f1);
    CK("tex_row_change_keeps_same_block_address", sh->drv_blk[0].gpu == gpu1);
    // 3) 存储缓冲行变化：c0 段必须重建，且块里就是新地址 | The storage-buffer row changes: the c0 segment must rebuild, holding the new address
    p_bind_buf nb = {.stage = 1, .index = 0, .addr = (uint64_t)mem[1], .size = 512};
    state_op(OP_BIND_SSBO, &nb);
    CK("encode_3", encode_args(enc, sh, 1, 0));
    uint64_t f3 = 0; mtl_drv_fill_stats(&f3);
    CK("ssbo_row_change_rebuilds_c0_segment", f3 == f2 + 1);
    uint64_t gpu3 = sh->drv_blk[0].gpu;
    CK("segment_block_address_changed", gpu3 != gpu1);
    {
        // 段块内容：0x510 起的 16 字节 = 地址（64 位）+ 大小（32 位） | Segment content: 16 bytes from 0x510 = address (64 bits) + size (32 bits)
        uint8_t *base = (uint8_t *)((id<MTLBuffer>)sh->drv_blk[0].buf).contents;
        size_t off = (size_t)(gpu3 - ((id<MTLBuffer>)sh->drv_blk[0].buf).gpuAddress);
        uint64_t a = 0; uint32_t n = 0; memcpy(&a, base + off + 0x510, 8); memcpy(&n, base + off + 0x518, 4);
        printf("segment addr=%#llx size=%u expected=%#llx/512\n", (unsigned long long)a, n, (unsigned long long)(uint64_t)mem[1]);
        CK("segment_holds_new_binding", a == (uint64_t)mem[1] && n == 512);
    }
    // 4) 客体地址解析缓存：同一地址第二次编码命中缓存；换地址后重新解析 | Address memo: the same address hits the cache on the next encode, a new address re-resolves
    {
        NvShader *cbs = [NvShader new];
        cbs->fn = [lib newFunctionWithName:@"f"]; cbs->ae = [cbs->fn newArgumentEncoderWithBufferIndex:1];
        cbs->arg_len = cbs->ae.encodedLength; cbs->rf.abi = 1; cbs->stage = 1;
        cbs->rf.nb = 1; cbs->rf.b[0] = (nvn_rbind){.kind = NVN_RB_CBUF, .reg = 0, .aid = 0};
        strlcpy(cbs->key, "cbuf", sizeof cbs->key);
        uint64_t a0 = g_stat_addr_memo;
        CK("cbuf_encode_1", encode_args(enc, cbs, 0, 1));
        args_touch(0);   // 强制重编，地址不变 → 缓存命中 | force a re-encode with the same address -> memo hit
        CK("cbuf_encode_2", encode_args(enc, cbs, 0, 1));
        uint64_t a1 = g_stat_addr_memo;
        CK("address_memo_hits", a1 - a0 == 1);
        S.ubo[0][0] = (p_bind_buf){.stage = 0, .index = 0, .addr = (uint64_t)mem[1], .size = 256};
        args_touch(0);
        CK("cbuf_encode_3", encode_args(enc, cbs, 0, 1));
        CK("address_memo_revalidates", g_stat_addr_memo == a1);
    }
    // Regression: argument-block reuse must declare once per encoder, and
    // must still declare a stronger usage and redeclare in a new encoder.
    CK("replay_prepare", encode_args(enc, sh, 1, 0));
    CK("replay_resources_present", sh->ab_m3_n > 0);
    uint64_t replay0 = g_stat_args_m3_replay, reused0 = g_stat_args_reuse;
    for (int i=0;i<100;i++) encode_args(enc, sh, 1, 0);
    CK("same_encoder_100_reuses", g_stat_args_reuse == reused0+100);
    CK("same_encoder_no_duplicate_declarations", g_stat_args_m3_replay == replay0);
    enc_r_end(enc); g_pass.serial++;
    enc = enc_r_begin(pd);
    CK("new_encoder_reuses_block", encode_args(enc, sh, 1, 0));
    CK("new_encoder_redeclares_resources", g_stat_args_m3_replay == replay0+(uint64_t)sh->ab_m3_n);
    replay0 = g_stat_args_m3_replay;
    sh->ab_m3_u[0] |= MTLResourceUsageWrite;
    encode_args(enc, sh, 1, 0);
    CK("stronger_usage_is_declared", g_stat_args_m3_replay == replay0+1);
    encode_args(enc, sh, 1, 0);
    CK("stronger_usage_then_deduplicates", g_stat_args_m3_replay == replay0+1);
    // Identical sampler registration must not retire live handles or invalidate
    // all stage argument caches. A descriptor change must still do both.
    samp_par sp={.cmp_mode=1,.cmp_func=NVN_COMPARE_FUNC_LEQUAL,.lod_max=16,.aniso=1};
    mtl_reg_samp(1900,&sp);
    id<MTLSamplerState> sampler=samp_by_id(1900);
    CK("sampler_created", sampler!=nil);
    uint64_t rid=g_srid[1900], gen=g_reg_gen;
    args_sync_dirty(); uint64_t epoch=g_args_epoch[1];
    for(int i=0;i<500;i++) mtl_reg_samp(1900,&sp);
    args_sync_dirty();
    CK("same_sampler_keeps_view",g_sview[1900]==(__bridge void*)sampler);
    CK("same_sampler_keeps_rid",g_srid[1900]==rid);
    CK("same_sampler_keeps_generation",g_reg_gen==gen);
    CK("same_sampler_keeps_args_epoch",g_args_epoch[1]==epoch);
    sp.cmp_func=NVN_COMPARE_FUNC_LESS; mtl_reg_samp(1900,&sp);
    CK("changed_sampler_invalidates_view",g_sview[1900]==NULL && g_srid[1900]==0);
    CK("changed_sampler_advances_generation",g_reg_gen==gen+1);
    args_sync_dirty(); CK("changed_sampler_invalidates_args",g_args_epoch[1]>epoch);
    CK("changed_sampler_rebuilds",samp_by_id(1900)!=nil && g_sreg[1900].cmp_func==NVN_COMPARE_FUNC_LESS);
    enc_r_end(enc);
    CK("GPU_completed", mtl_wait(mtl_sub_commit(), 5000000000ull));
    CK("GPU_no_error", mtl_last_commit_error() == 0);
    for (int i = 0; i < 2; i++) { mtl_pool_del(mem[i]); free(mem[i]); }
    printf("ARGS_PLAN_REAL_METAL checks=%d failed=%d\n", checks, failed);
    return failed ? 1 : 0;
} }
