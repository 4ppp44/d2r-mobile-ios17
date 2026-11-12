// 整数顶点输入 × 归一化客体格式的真实 Metal 验证（本机 M1，不是 A16 证据）。
// 真机日志（build2026102803）反复出现：Cannot convert attribute from MTLAttributeFormatChar4Normalized to int4 or uint4，
// 每次都是一条管线建不出来、那次绘制被整个跳过（pso_get 返回 nil）。
// 语义依据：D3D 在输入签名是整数时忽略取数格式的归一化标志，按原始位模式当整数读；Metal 则要求格式与签名同类。
// 所以「整数输入 + 归一化格式」建管线失败时，换成同宽度的整数格式再试一次（字节数、偏移、步长都不变）。
// 断言：
//  1) pso_desc 本身不改格式（正常管线一个字节都不动）。
//  2) pso_desc_intfix 只动整数输入那几路：Char4Normalized→Char4、UShort4Normalized→UShort4，浮点那路保持归一化。
//  3) 换格式后偏移 / 步长不变，管线建得出来。
//  4) 全是浮点输入时 pso_desc_intfix 返回 nil（不产生多余的描述符、不多做一次编译）。
// 已知分歧（必须写明，不能当通过证据）：真机 iOS 17（A16）拒绝「归一化格式 + int4/uint4」，本机 macOS 26 的 Metal 接受这一对，
// 所以本机复现不了真机那次拒绝。真机是否因此不再报错，要下一次真机日志里的「整数顶点格式重试」计数确认。
// Real-Metal verification of integer vertex inputs against normalized guest formats (this M1 host, not A16 evidence).
// The build2026102803 device log repeats: Cannot convert attribute from MTLAttributeFormatChar4Normalized to int4 or uint4,
// and every occurrence is a pipeline that could not be built, so that draw was skipped entirely (pso_get returns nil).
// Semantics: D3D ignores the fetch format's normalization flag when the input signature is integer and reads the raw bits as
// integers, while Metal requires the format to match the signature class. So when "integer input + normalized format" fails to
// build, retry once with the same-width integer format (byte count, offset and stride unchanged).
// Asserted:
//  1) pso_desc itself never changes a format (a working pipeline is not touched at all).
//  2) pso_desc_intfix only touches the integer inputs: Char4Normalized->Char4, UShort4Normalized->UShort4, and leaves the float one normalized.
//  3) offsets / strides are unchanged after the swap and the pipeline builds.
//  4) with float-only inputs pso_desc_intfix returns nil (no extra descriptor, no extra compile).
// Known divergence (must be stated; it is not proof): iOS 17 on the device (A16) rejects "normalized format + int4/uint4", while
// this host's macOS 26 Metal accepts the pair, so the device rejection cannot be reproduced here. Whether the device stops
// reporting the error is confirmed by the "integer vertex format retry" counter in the next device log.
#ifndef D2R_BACKEND_FILE
#define D2R_BACKEND_FILE "../nvn/nvn_mtl.m"
#endif
#include D2R_BACKEND_FILE
void *front_metal_layer(void){return NULL;}module_t *module_of(const void *p){(void)p;return NULL;}module_t g_mod[MAX_MOD];int g_nmod;void svc_thread_dump(void){}uint64_t now_ns(void){return bp_now();}
static int checks, failed;
#define CK(n,c) do{int ok=(c);checks++;failed+=!ok;printf("%s %s\n",n,ok?"PASS":"FAIL");}while(0)

// 客体属性号 → 游戏给的格式：0 = 0x26 Char4Normalized（uint4 输入）、1 = 0x2A UShort4Normalized（int4 输入）、
// 2 = 0x26 Char4Normalized（float4 输入，必须保持归一化）
// Guest attribute number -> the format the game supplies: 0 = 0x26 Char4Normalized (uint4 input), 1 = 0x2A
// UShort4Normalized (int4 input), 2 = 0x26 Char4Normalized (float4 input, must stay normalized)
static NvShader *vattr_shader(id<MTLLibrary> l, int all_float) {
    NvShader *s = [NvShader new];
    s->fn = [l newFunctionWithName:@"vs0"];
    s->stage = 0;
    s->rf.nv = 3;
    s->rf.v[0] = (typeof(s->rf.v[0])){.loc = 0, .ct = all_float ? NVN_CT_FLOAT : NVN_CT_UINT, .nvn = 0};
    s->rf.v[1] = (typeof(s->rf.v[1])){.loc = 1, .ct = all_float ? NVN_CT_FLOAT : NVN_CT_INT, .nvn = 1};
    s->rf.v[2] = (typeof(s->rf.v[2])){.loc = 2, .ct = NVN_CT_FLOAT, .nvn = 2};
    strlcpy(s->key, "vattr_int", sizeof s->key);
    return s;
}
static void key_fill(pso_key *k, NvShader *vs) {
    memset(k, 0, sizeof *k);
    k->vs = (__bridge void *)vs;
    k->samples = 1;
    k->cfmt[0] = MTLPixelFormatRGBA8Unorm;
    for (int a = 0; a < 3; a++) { k->attr[a].fmt = a == 1 ? 0x2A : 0x26; k->attr[a].stream = (uint32_t)a; k->attr[a].offset = (uint32_t)(a * 4); }
    for (int s = 0; s < 3; s++) { k->stream[s].stride = 16; k->stream[s].divisor = 0; }
}
int main(void) { @autoreleasepool {
    mtl_init();
    NSError *err = nil;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:
        @"#include <metal_stdlib>\nusing namespace metal;\n"
         "struct V { uint4 a [[attribute(0)]]; int4 b [[attribute(1)]]; float4 p [[attribute(2)]]; };\n"
         "vertex float4 vs0(V in [[stage_in]]) { return float4(in.p.xyz + float(in.a.x) * 0.0, 1.0); }\n"
         "fragment float4 fs0() { return float4(1.0); }\n" options:nil error:&err];
    CK("着色器编译", lib != nil);
    if (!lib) { printf("库编译失败：%s\n", err.localizedDescription.UTF8String); return 1; }
    NvShader *fs = [NvShader new]; fs->fn = [lib newFunctionWithName:@"fs0"]; fs->stage = 1;

    // 1) 描述符生成：uint4 映射为 UChar4（无符号），int4 映射为 Short4（有符号），float4 保持归一化
    NvShader *vs = vattr_shader(lib, 0);
    pso_key k; key_fill(&k, vs);
    MTLRenderPipelineDescriptor *d = pso_desc(&k, vs, fs, nil, 0);
    CK("pso_desc uint4 映射为无符号 UChar4", d.vertexDescriptor.attributes[0].format == MTLVertexFormatUChar4);
    CK("pso_desc int4 映射为有符号 Short4", d.vertexDescriptor.attributes[1].format == MTLVertexFormatShort4);
    CK("pso_desc float4 保持归一化 Char4Normalized", d.vertexDescriptor.attributes[2].format == MTLVertexFormatChar4Normalized);

    // 2) 重试描述符：输入全浮点描述符与带整数反射的 key 时，只动整数输入那两路
    pso_key k_raw; key_fill(&k_raw, vs);
    MTLRenderPipelineDescriptor *d_raw = [MTLRenderPipelineDescriptor new];
    d_raw.vertexFunction = vs->fn; d_raw.fragmentFunction = fs->fn;
    MTLVertexDescriptor *vd_raw = [MTLVertexDescriptor vertexDescriptor];
    vd_raw.attributes[0].format = MTLVertexFormatChar4Normalized; vd_raw.attributes[0].offset = 0; vd_raw.attributes[0].bufferIndex = 16;
    vd_raw.attributes[1].format = MTLVertexFormatUShort4Normalized; vd_raw.attributes[1].offset = 4; vd_raw.attributes[1].bufferIndex = 16;
    vd_raw.attributes[2].format = MTLVertexFormatChar4Normalized; vd_raw.attributes[2].offset = 8; vd_raw.attributes[2].bufferIndex = 16;
    vd_raw.layouts[16].stride = 16;
    d_raw.vertexDescriptor = vd_raw;
    d_raw.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;

    MTLRenderPipelineDescriptor *fix = pso_desc_intfix(&k_raw, d_raw);
    CK("重试描述符生成", fix != nil);
    if (fix) {
        CK("uint4 那路 → UChar4 (无符号)", fix.vertexDescriptor.attributes[0].format == MTLVertexFormatUChar4);
        CK("int4 那路 → Short4 (有符号)", fix.vertexDescriptor.attributes[1].format == MTLVertexFormatShort4);
        CK("float4 那路保持归一化", fix.vertexDescriptor.attributes[2].format == MTLVertexFormatChar4Normalized);
        // 3) 偏移 / 步长不变，管线建得出来 | offsets / strides unchanged and the pipeline builds
        CK("偏移未改动", fix.vertexDescriptor.attributes[0].offset == d_raw.vertexDescriptor.attributes[0].offset &&
                        fix.vertexDescriptor.attributes[1].offset == d_raw.vertexDescriptor.attributes[1].offset);
        CK("步长未改动", fix.vertexDescriptor.layouts[16].stride == 16);
        CK("原始描述符未被就地改动", d_raw.vertexDescriptor.attributes[0].format == MTLVertexFormatChar4Normalized);
        err = nil;
        id<MTLRenderPipelineState> fps = [g_dev newRenderPipelineStateWithDescriptor:fix error:&err];
        CK("换格式后管线建成", fps != nil);
        if (!fps) printf("建成失败：%s\n", err.localizedDescription.UTF8String);
    }

    // 统一入口：宿主上第一次就建成（不触发重试），真机上才会走重试 | the single entry point: on the host the first attempt already
    // builds so the retry is not used; on the device it is
    err = nil;
    id<MTLRenderPipelineState> ps = pso_build(&k, pso_desc(&k, vs, fs, nil, 0), &err);
    CK("pso_build 建成管线", ps != nil);
    if (!ps) printf("pso_build 失败：%s\n", err.localizedDescription.UTF8String);

    // 4) 全是浮点输入：不该产生重试描述符 | float-only inputs must not produce a retry descriptor
    NvShader *vsf = vattr_shader(lib, 1);
    pso_key kf; key_fill(&kf, vsf);
    MTLRenderPipelineDescriptor *df = pso_desc(&kf, vsf, fs, nil, 0);
    CK("全浮点输入不产生重试描述符", pso_desc_intfix(&kf, df) == nil);
    CK("没有顶点描述符时返回 nil", pso_desc_intfix(&kf, nil) == nil);

    printf("VARINT_REAL_METAL checks=%d failed=%d\n", checks, failed);
    return failed ? 1 : 0;
} }
