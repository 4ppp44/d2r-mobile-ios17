// 真 Metal 单元测试：
// 1) 驱动常量段 c2 完整填充验证：
//    验证槽 0（0x168）、槽 15（480）、槽 16（488）、槽 127 以及采样器槽 0（0x568）、采样器槽 1（1392）的句柄内容与全段 0 填充。
// 2) 跨通道参数块复用时的资源声明容量扩充验证（>24 资源，例如 32 个贴图）：
//    验证全部 32 个资源在跨通道复用时均被重放声明到新编码器。
#ifndef D2R_BACKEND_FILE
#define D2R_BACKEND_FILE "../nvn/nvn_mtl.m"
#endif
#include D2R_BACKEND_FILE
void *front_metal_layer(void){return NULL;}module_t *module_of(const void *p){(void)p;return NULL;}module_t g_mod[MAX_MOD];int g_nmod;void svc_thread_dump(void){}uint64_t now_ns(void){return bp_now();}
static int checks, failed;
#define CK(n,c) do{int ok=(c);checks++;failed+=!ok;printf("%s %s\n",n,ok?"PASS":"FAIL");}while(0)

int main(void) { @autoreleasepool {
    mtl_init();
    NSError *err = nil;

    // --- 1. c2 驱动常量段完整填充测试 ---
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nstruct A{device float *x [[id(0)]];};\nfragment float4 f(constant A&a [[buffer(1)]]){return float4(a.x[0],0,0,1);}\n" options:nil error:&err];
    CK("library_compiled", lib != nil);

    NvShader *sh = [NvShader new];
    sh->fn = [lib newFunctionWithName:@"f"];
    sh->ae = [sh->fn newArgumentEncoderWithBufferIndex:1];
    sh->arg_len = sh->ae.encodedLength;
    sh->rf.abi = 1; sh->stage = 1;
    sh->rf.nb = 1; sh->rf.b[0] = (nvn_rbind){.kind = NVN_RB_DRV2, .reg = 0, .aid = 0};
    sh->rf.drv_read[2] = 1;
    // 即使反射带有 vec4_offsets 偏移记录，也必须全段完整填充，不得缺失偶数槽和采样器 0
    sh->rf.drv_noff[2] = 2; sh->rf.drv_off[2][0] = 480; sh->rf.drv_off[2][1] = 1456;
    strlcpy(sh->key, "c2_test", sizeof sh->key);

    // 设定测试句柄值
    S.tex[1][0] = 0xAA001122;    // Slot 0 (0x168 = 360)
    S.tex[1][1] = 0xBB003344;    // Slot 1 (0x170 = 368)
    S.tex[1][15] = 0xCC005566;   // Slot 15 (0x1e0 = 480)
    S.tex[1][16] = 0xDD007788;   // Slot 16 (0x1e8 = 488)
    S.tex[1][127] = 0xEE0099AA;  // Slot 127 (0x560 = 1376)
    S.samp[1][0] = 0x11AABBCC;   // Sampler Slot 0 (0x568 = 1384)
    S.samp[1][1] = 0x22CCDDEE;   // Sampler Slot 1 (0x570 = 1392)
    S.samp[1][127] = 0x33EEFFAA; // Sampler Slot 127 (0x960 = 2400)

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [g_dev newTextureWithDescriptor:td];
    MTLRenderPassDescriptor *pd = [MTLRenderPassDescriptor renderPassDescriptor];
    pd.colorAttachments[0].texture = tex; pd.colorAttachments[0].loadAction = MTLLoadActionClear; pd.colorAttachments[0].storeAction = MTLStoreActionStore;

    mtl_sub_begin(); g_pass.serial++;
    id<MTLRenderCommandEncoder> enc = enc_r_begin(pd);
    CK("encode_c2", encode_args(enc, sh, 1, 0));

    // 读取 c2 段的内存内容
    CK("c2_buffer_valid", sh->drv_blk[1].buf != nil);
    id<MTLBuffer> c2_buf = (id<MTLBuffer>)sh->drv_blk[1].buf;
    size_t c2_off = (size_t)(sh->drv_blk[1].gpu - c2_buf.gpuAddress);
    const uint8_t *d = (const uint8_t *)c2_buf.contents + c2_off;

    // 验证前置字节全 0
    int pre_zero = 1;
    for (int i = 0; i < 0x168; i++) { if (d[i] != 0) { pre_zero = 0; break; } }
    CK("c2_prefix_is_zero", pre_zero);

    // 验证关键贴图与采样器槽位
    uint32_t val_t0 = 0, val_t1 = 0, val_t15 = 0, val_t16 = 0, val_t127 = 0;
    uint32_t val_s0 = 0, val_s1 = 0, val_s127 = 0;
    memcpy(&val_t0, d + 0x168 + 8 * 0, 4);
    memcpy(&val_t1, d + 0x168 + 8 * 1, 4);
    memcpy(&val_t15, d + 0x168 + 8 * 15, 4);
    memcpy(&val_t16, d + 0x168 + 8 * 16, 4);
    memcpy(&val_t127, d + 0x168 + 8 * 127, 4);
    memcpy(&val_s0, d + 0x568 + 8 * 0, 4);
    memcpy(&val_s1, d + 0x568 + 8 * 1, 4);
    memcpy(&val_s127, d + 0x568 + 8 * 127, 4);

    CK("c2_tex_slot_0_correct", val_t0 == 0xAA001122);
    CK("c2_tex_slot_1_correct", val_t1 == 0xBB003344);
    CK("c2_tex_slot_15_correct", val_t15 == 0xCC005566);
    CK("c2_tex_slot_16_even_slot_correct", val_t16 == 0xDD007788);
    CK("c2_tex_slot_127_correct", val_t127 == 0xEE0099AA);
    CK("c2_samp_slot_0_correct", val_s0 == 0x11AABBCC);
    CK("c2_samp_slot_1_correct", val_s1 == 0x22CCDDEE);
    CK("c2_samp_slot_127_correct", val_s127 == 0x33EEFFAA);

    // 验证槽与槽之间的 padding 为 0
    uint32_t pad_t0 = 0, pad_t15 = 0;
    memcpy(&pad_t0, d + 0x168 + 8 * 0 + 4, 4);
    memcpy(&pad_t15, d + 0x168 + 8 * 15 + 4, 4);
    CK("c2_slot_padding_is_zero", pad_t0 == 0 && pad_t15 == 0);

    // --- 2. 验证多资源（>24 资源）参数块跨通道重放 ---
    NvShader *sh_large = [NvShader new];
    sh_large->fn = [lib newFunctionWithName:@"f"];
    sh_large->ae = [sh_large->fn newArgumentEncoderWithBufferIndex:1];
    sh_large->arg_len = sh_large->ae.encodedLength;
    sh_large->rf.abi = 1; sh_large->stage = 1;
    sh_large->rf.nb = 32;

    void *res_mem[32];
    for (int i = 0; i < 32; i++) {
        posix_memalign(&res_mem[i], getpagesize(), getpagesize());
        memset(res_mem[i], 0, getpagesize());
        mtl_pool_add(res_mem[i], getpagesize());
        if (i < 16) {
            sh_large->rf.b[i] = (nvn_rbind){.kind = NVN_RB_UBOP, .reg = (int16_t)i, .aid = (uint16_t)i};
            S.ubo[1][i] = (p_bind_buf){.stage = 1, .index = i, .addr = (uint64_t)res_mem[i], .size = 256};
        } else {
            sh_large->rf.b[i] = (nvn_rbind){.kind = NVN_RB_SBUFP, .reg = (int16_t)(i - 16), .aid = (uint16_t)i};
            S.ssbo[1][i - 16] = (p_bind_buf){.stage = 1, .index = i - 16, .addr = (uint64_t)res_mem[i], .size = 256};
        }
    }
    strlcpy(sh_large->key, "large_res", sizeof sh_large->key);

    // 首次在 enc 编码
    args_touch(1);
    CK("encode_large_initial", encode_args(enc, sh_large, 1, 0));
    printf("captured resources in large shader: %d\n", sh_large->ab_m3_n);
    CK("large_shader_captured_all_32_resources", sh_large->ab_m3_n == 32);
    CK("large_shader_not_overflowed", sh_large->ab_m3_overflow == 0);

    // 切换到新 render pass 编码器 enc2
    enc_r_end(enc);
    g_pass.serial++;
    pd.colorAttachments[0].loadAction = MTLLoadActionLoad;
    id<MTLRenderCommandEncoder> enc2 = enc_r_begin(pd);

    uint64_t rep_before = g_stat_args_m3_replay;
    CK("encode_large_reuse_cross_pass", encode_args(enc2, sh_large, 1, 0));
    uint64_t replayed = g_stat_args_m3_replay - rep_before;
    printf("replayed resources on new encoder: %llu\n", (unsigned long long)replayed);
    CK("replayed_all_32_resources_on_new_encoder", replayed == 32);

    for (int i = 0; i < 32; i++) {
        mtl_pool_del(res_mem[i]);
        free(res_mem[i]);
    }

    enc_r_end(enc2);
    CK("GPU_completed", mtl_wait(mtl_sub_commit(), 5000000000ull));
    CK("GPU_no_error", mtl_last_commit_error() == 0);

    printf("C2_FULL_TEST checks=%d failed=%d\n", checks, failed);
    return failed ? 1 : 0;
}}
