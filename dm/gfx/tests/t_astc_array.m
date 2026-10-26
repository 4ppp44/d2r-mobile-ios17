// ASTC 数组保留与 RGBA 展开验证：轴对齐、逐层逐级拷贝保留、真实 GPU 采样、不兼容写入展开与在途安全。
// 每个 (源, mip) 用不同纯色：切片或 mip 串位时读回颜色立刻不同；展开后逐 (切片, mip) 全部读回核对。
// Verification of ASTC array preservation and RGBA expansion: axis alignment, slice/mip copy preservation,
// real Metal shader sampling, incompatible write expansion, and in-flight GPU safety.
// Every (source, mip) gets its own flat colour, so a slice or mip mix-up changes the readback colour, and every
// (slice, mip) pair is read back after expansion.
#include "../nvn/nvn_mtl.m"

void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

static int checks, failures;
#define CHECK(c, name) do { checks++; if (!(c)) { failures++; fprintf(stderr, "FAIL: %s\n", name); } } while (0)

enum { SLICES = 2, LEVELS = 5, SIDE = 16, ROW = 64 };   // ROW：读回行距（16 像素 × 4 字节） | readback row pitch

// 构造一个简单的 ASTC 4x4 块数据：所有像素为单色
// Construct raw ASTC 4x4 block payload (solid color block)
// In ASTC, a void-extent (constant color) block has a specific encoding:
// header bits [0..8] = 0x1fc (void-extent marker), [9] = 0 (LDR), [10..11] = extent, RGBA uint16.
static void make_astc_void_extent(uint8_t *block, uint16_t r, uint16_t g, uint16_t b, uint16_t a) {
    // 规范 void-extent 头取自 ARM astcenc symbolic_to_physical()：SYM_BTYPE_CONST_U16 写 FC FD FF FF FF FF FF FF。
    // 字节 1 必须是 0xFD：bit 9 = 0（LDR unorm16），bit 10 = 1，bits 11..63 全 1 表示覆盖整块。
    // 早先的写法给 0x01，把 bits 10..63 全清成 0 —— 那不是合法的 void-extent，硬件按 0 解码，
    // 于是"读回全绿"的旧断言只是比较了两条同样错误的路径，掩盖了 fixture 本身无效。
    // Canonical void-extent header from ARM astcenc symbolic_to_physical(): SYM_BTYPE_CONST_U16 writes
    // FC FD FF FF FF FF FF FF. Byte 1 must be 0xFD: bit 9 = 0 (LDR unorm16), bit 10 = 1, bits 11..63 all ones
    // meaning the extent covers the whole block. The earlier 0x01 cleared bits 10..63 to zero, which is not a
    // valid void-extent: hardware decodes it as black, so the old "reads back green" assertion only compared two
    // equally wrong paths and hid the invalid fixture.
    static const uint8_t cbytes[8] = { 0xFC, 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    memcpy(block, cbytes, 8);
    // 颜色：8 位值 × 257 正好是 unorm16 全范围还原 | Colours: 8-bit value x 257 is the exact unorm16 round trip
    *(uint16_t *)(block + 8) = r;
    *(uint16_t *)(block + 10) = g;
    *(uint16_t *)(block + 12) = b;
    *(uint16_t *)(block + 14) = a;
}

// 每个 (源, mip) 一个不同纯色。编码值 = 8 位值 × 257，解码回 8 位时正好还原（65535 = 255 × 257），
// 所以期望值就是下面的 r/g/b/a 本身，不需要允许误差。
// One distinct flat colour per (source, mip). The encoded 16-bit value is the 8-bit value × 257, which decodes back
// to exactly that 8-bit value (65535 = 255 × 257), so the expected pixel is r/g/b/a with no tolerance.
static void astc_color(int source, int level, uint8_t block[16], uint8_t px[4]) {
    int idx = source * LEVELS + level + 1;          // 1..10，每个组合唯一 | 1..10, unique per combination
    uint8_t r = (uint8_t)(idx * 20), g = (uint8_t)(255 - idx * 20), b = (uint8_t)(idx * 10), a = 255;
    make_astc_void_extent(block, (uint16_t)(r * 257), (uint16_t)(g * 257), (uint16_t)(b * 257), (uint16_t)(a * 257));
    px[0] = r; px[1] = g; px[2] = b; px[3] = a;
}

static void test_axis_alignment(void) {
    CHECK(nvn_astc_copy_axis(0, 0, 256, 256, 256), "axis: 256x256 aligned");
    CHECK(nvn_astc_copy_axis(0, 0, 2, 2, 2), "axis: small 2x2 mip edge");
    CHECK(nvn_astc_copy_axis(0, 0, 1, 1, 1), "axis: small 1x1 mip edge");
    CHECK(nvn_astc_copy_axis(4, 8, 3, 7, 11), "axis: partial final block at edge");
    CHECK(!nvn_astc_copy_axis(4, 8, 3, 7, 12), "axis: partial final block not at dst edge");
    CHECK(!nvn_astc_copy_axis(1, 0, 4, 8, 8), "axis: unaligned src origin");
    CHECK(!nvn_astc_copy_axis(0, 2, 4, 8, 8), "axis: unaligned dst origin");
    CHECK(!nvn_astc_copy_axis(-4, 0, 4, 8, 8), "axis: negative src origin");
    CHECK(!nvn_astc_copy_axis(0, 0, 0, 8, 8), "axis: zero count");
    CHECK(!nvn_astc_copy_axis(0, 0, 9, 8, 8), "axis: count exceeds extent");
    CHECK(!nvn_astc_copy_axis(0x7ffffffc, 0, 8, 0x7fffffff, 8), "axis: overflow protection");
}

// 把某个 (切片, mip) 读回共享缓冲，返回 0 = GPU 出错
// Read one (slice, mip) back into a shared buffer; 0 = GPU error
static int read_slice_level(id<MTLTexture> t, int slice, int level, id<MTLBuffer> rb, NSUInteger w, NSUInteger h) {
    mtl_sub_begin();
    [blit() copyFromTexture:t sourceSlice:(NSUInteger)slice sourceLevel:(NSUInteger)level sourceOrigin:MTLOriginMake(0, 0, 0)
                 sourceSize:MTLSizeMake(w, h, 1) toBuffer:rb destinationOffset:0
        destinationBytesPerRow:ROW destinationBytesPerImage:ROW * SIDE];
    uint64_t fence = mtl_sub_commit();
    return mtl_wait(fence, 5000000000ull);
}

int main(void) {
    @autoreleasepool {
        setenv("DM_TEST_NO_BC", "1", 0);
        mtl_init();
        test_axis_alignment();

        // 1. 两张 ASTC 4x4 源纹理 (2D, 16x16, 5 mips: 16x16, 8x8, 4x4, 2x2, 1x1)，每级一色
        // Two ASTC 4x4 sources (2D, 16x16, 5 mips), one colour per level
        id<MTLTexture> stex[SLICES];
        tex_t src_t[SLICES];
        for (int k = 0; k < SLICES; k++) {
            MTLTextureDescriptor *sdesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatASTC_4x4_LDR width:SIDE height:SIDE mipmapped:YES];
            sdesc.usage = MTLTextureUsageShaderRead | MTLTextureUsagePixelFormatView;
            stex[k] = [g_dev newTextureWithDescriptor:sdesc];
            CHECK(stex[k] != nil, "ASTC source texture created");
            res_add(stex[k]);
            CHECK(stex[k].mipmapLevelCount == LEVELS, "ASTC source has 5 mip levels");

            for (NSUInteger l = 0; l < stex[k].mipmapLevelCount; l++) {
                NSUInteger w = MAX(stex[k].width >> l, 1u), h = MAX(stex[k].height >> l, 1u);
                NSUInteger bw = (w + 3) / 4, bh = (h + 3) / 4;
                uint8_t block[16], px[4];
                astc_color(k, (int)l, block, px);
                uint8_t *lvl_data = calloc(bw * bh, 16);
                for (NSUInteger b = 0; b < bw * bh; b++) memcpy(lvl_data + b * 16, block, 16);
                [stex[k] replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:l withBytes:lvl_data bytesPerRow:bw * 16];
                free(lvl_data);
            }

            // 模拟客体纹理描述符：源是 ASTC (serial 8101 / 8105)
            // Guest-side texture descriptor: ASTC sources on serials 8101 / 8105
            memset(&src_t[k], 0, sizeof src_t[k]);
            src_t[k].serial = 8101 + (uint64_t)k * 4;
            src_t[k].d.width = src_t[k].d.height = SIDE;
            src_t[k].d.depth = 1; src_t[k].d.levels = (unsigned)stex[k].mipmapLevelCount; src_t[k].d.samples = 1;
            src_t[k].d.target = NVN_TEXTURE_TARGET_2D; src_t[k].d.format = 0x44; // NVN_FORMAT_RGBA_DXT5
            serial_put(src_t[k].serial, stex[k]);
        }

        // 2. 模拟目标：2DArray BC3 (serial=8102, 2 层, 5 级)
        // Destination: 2DArray BC3 (serial 8102, 2 slices, 5 levels)
        tex_t dst_t = {.serial = 8102};
        dst_t.d.width = dst_t.d.height = SIDE;
        dst_t.d.depth = SLICES;
        dst_t.d.levels = LEVELS; dst_t.d.samples = 1;
        dst_t.d.target = NVN_TEXTURE_TARGET_2D_ARRAY;
        dst_t.d.format = 0x44; // NVN_FORMAT_RGBA_DXT5

        mtl_sub_begin();

        // 3. 逐层逐级通过 copy_t2t 拷贝：切片 0 取自源 0，切片 1 取自源 1
        // Copy every slice/mip through copy_t2t: slice 0 from source 0, slice 1 from source 1
        for (unsigned slice = 0; slice < SLICES; slice++) {
            for (unsigned lvl = 0; lvl < dst_t.d.levels; lvl++) {
                int w = (int)MAX((unsigned)SIDE >> lvl, 1u), h = (int)MAX((unsigned)SIDE >> lvl, 1u);
                p_copy_t2t c = {
                    .src = &src_t[slice], .dst = &dst_t,
                    .sr = {.xoffset = 0, .yoffset = 0, .zoffset = 0, .width = w, .height = h, .depth = 1},
                    .dr = {.xoffset = 0, .yoffset = 0, .zoffset = (int)slice, .width = w, .height = h, .depth = 1},
                    .has_sv = 1, .sv = {.set_levels = 1, .base_level = lvl, .nlevels = 1, .set_layers = 1, .min_layer = 0, .nlayers = 1},
                    .has_dv = 1, .dv = {.set_levels = 1, .base_level = lvl, .nlevels = 1, .set_layers = 1, .min_layer = 0, .nlayers = SLICES},
                    .flags = 0
                };
                copy_t2t(&c);
            }
        }

        // 4. 验证目标纹理成功保留为 ASTC_4x4_LDR (未被展开为 RGBA8)
        id<MTLTexture> dtex = serial_get(dst_t.serial);
        CHECK(dtex != nil, "destination texture allocated");
        CHECK(dtex.pixelFormat == MTLPixelFormatASTC_4x4_LDR, "destination preserved as ASTC_4x4_LDR");
        CHECK(dtex.textureType == MTLTextureType2DArray, "destination is MTLTextureType2DArray");
        CHECK(dtex.arrayLength == SLICES, "destination arrayLength is 2");
        CHECK(dtex.mipmapLevelCount == LEVELS, "destination mipmapLevelCount is 5");
        CHECK(astc_array_backed(&dst_t, dtex), "destination recognized as astc_array_backed");

        // 5. 登记该贴图并在着色器描述符中读取验证
        mtl_reg_tex(50, &dst_t, NULL);
        pthread_mutex_lock(&g_rmu);
        id<MTLTexture> bound_view = tex_by_id(50);
        pthread_mutex_unlock(&g_rmu);
        CHECK(bound_view != nil, "tex_by_id returned valid texture");
        CHECK(bound_view.pixelFormat == MTLPixelFormatASTC_4x4_LDR, "bound view kept ASTC_4x4_LDR format");

        // 6. 在途 GPU 读取：直接解切片 0 / 级 0，确认 ASTC 数组本身存的确实是那一格的颜色
        // In-flight GPU read: decode slice 0 / level 0 directly, proving the ASTC array itself holds that cell's colour
        id<MTLBuffer> astc_readback = [g_dev newBufferWithLength:ROW * SIDE options:MTLResourceStorageModeShared];
        res_add(astc_readback);
        MTLTextureDescriptor *tdesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:SIDE height:SIDE mipmapped:NO];
        tdesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        id<MTLTexture> temp_rgba = [g_dev newTextureWithDescriptor:tdesc];
        res_add(temp_rgba);
        CHECK(copy_t2t_astc(dtex, temp_rgba, 0, 0, 0, 0, 0, 0, 0, 0, SIDE, SIDE), "copy_t2t_astc from preserved array slice 0");
        [blit() copyFromTexture:temp_rgba sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(SIDE,SIDE,1)
                      toBuffer:astc_readback destinationOffset:0 destinationBytesPerRow:ROW destinationBytesPerImage:ROW * SIDE];

        // 7. 触发 RGBA 展开 (例如 clear_tex 或 attach 或不兼容拷贝)
        // 验证展开后格式变为 RGBA8，且先前的 ASTC 像素被完整保留
        uint64_t prev_gen = g_reg_gen;
        id<MTLTexture> expanded = astc_array_expand(&dst_t, dtex);
        CHECK(expanded != nil, "astc_array_expand returned valid texture");
        CHECK(expanded.pixelFormat == MTLPixelFormatRGBA8Unorm, "expanded texture is RGBA8Unorm");
        CHECK(expanded.arrayLength == SLICES, "expanded texture kept 2 slices");
        CHECK(expanded.mipmapLevelCount == LEVELS, "expanded texture kept 5 mips");
        CHECK(g_reg_gen > prev_gen, "generation bumped after expand");
        CHECK(serial_get(dst_t.serial) == expanded, "serial_put updated to expanded texture");

        // 8. 验证 tex_by_id 缓存失效并更新为 expanded 纹理
        pthread_mutex_lock(&g_rmu);
        id<MTLTexture> new_view = tex_by_id(50);
        pthread_mutex_unlock(&g_rmu);
        CHECK(new_view != nil, "new_view exists");
        CHECK(new_view.pixelFormat == MTLPixelFormatRGBA8Unorm, "tex_by_id returned expanded RGBA8Unorm texture");

        // 9. 展开后的整块读回（级 0 / 切片 0），与第 6 步解出的内容逐像素对照
        // Full readback of the expanded level 0 / slice 0, compared pixel-exactly with step 6
        id<MTLBuffer> expanded_readback = [g_dev newBufferWithLength:ROW * SIDE options:MTLResourceStorageModeShared];
        res_add(expanded_readback);
        [blit() copyFromTexture:expanded sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(SIDE,SIDE,1)
                      toBuffer:expanded_readback destinationOffset:0 destinationBytesPerRow:ROW destinationBytesPerImage:ROW * SIDE];

        // 10. 提交本次提交并在 GPU 上执行
        uint64_t fence = mtl_sub_commit();
        CHECK(mtl_wait(fence, 5000000000ull), "GPU wait passed");
        CHECK(!mtl_last_commit_error(), "no GPU execution errors");

        // 11. 逐像素对比：在途 ASTC 采样与展开后的 RGBA 采样像素一致
        const uint8_t *p_astc = astc_readback.contents;
        const uint8_t *p_exp = expanded_readback.contents;
        int pixels_match = 1;
        for (int i = 0; i < SIDE * SIDE * 4; i++) {
            if (p_astc[i] != p_exp[i]) { pixels_match = 0; break; }
        }
        CHECK(pixels_match, "content validation: all 256 pixels x 4 channels match exactly between ASTC and expanded RGBA");

        // 12. 逐 (切片, mip) 读回展开后的 RGBA：10 个组合各自颜色必须原样保留
        //     （原测试只查切片 0 级 0 与切片 1 级 0，且全部级同色，串位查不出来）
        // Read back every (slice, mip) of the expanded RGBA: all 10 combinations must keep their own colour
        // (the old test only checked slice 0 / level 0 and slice 1 / level 0, with every level the same colour,
        //  so a slice or mip mix-up could not show up)
        int cell_bad = 0;
        for (int slice = 0; slice < SLICES; slice++)
            for (int level = 0; level < LEVELS; level++) {
                uint8_t block[16], want[4];
                astc_color(slice, level, block, want);
                NSUInteger w = MAX((NSUInteger)SIDE >> level, 1u), h = MAX((NSUInteger)SIDE >> level, 1u);
                id<MTLBuffer> rb = [g_dev newBufferWithLength:ROW * SIDE options:MTLResourceStorageModeShared];
                res_add(rb);
                CHECK(read_slice_level(expanded, slice, level, rb, w, h), "slice/mip readback GPU wait passed");
                const uint8_t *p = rb.contents;
                for (NSUInteger y = 0; y < h && !cell_bad; y++)
                    for (NSUInteger x = 0; x < w && !cell_bad; x++) {
                        const uint8_t *q = p + y * ROW + x * 4;
                        if (q[0] != want[0] || q[1] != want[1] || q[2] != want[2] || q[3] != want[3]) {
                            fprintf(stderr, "mismatch slice %d level %d at %lux%lu: got %u,%u,%u,%u want %u,%u,%u,%u\n",
                                    slice, level, (unsigned long)x, (unsigned long)y, q[0], q[1], q[2], q[3], want[0], want[1], want[2], want[3]);
                            cell_bad++;
                        }
                    }
            }
        CHECK(cell_bad == 0, "content validation: every slice x mip keeps its own colour through expansion");

        // 13. 开关对照测试：设置 DM_ASTC_ARRAYS=0 后新建目标，应直接回退到 RGBA8
        setenv("DM_ASTC_ARRAYS", "0", 1);
        tex_t dst_off = {.serial = 8104};
        dst_off.d = dst_t.d;
        mtl_sub_begin();
        p_copy_t2t c_off = {
            .src = &src_t[0], .dst = &dst_off,
            .sr = {.xoffset = 0, .yoffset = 0, .zoffset = 0, .width = SIDE, .height = SIDE, .depth = 1},
            .dr = {.xoffset = 0, .yoffset = 0, .zoffset = 0, .width = SIDE, .height = SIDE, .depth = 1},
            .has_sv = 1, .sv = {.set_levels = 1, .base_level = 0, .nlevels = 1, .set_layers = 1, .min_layer = 0, .nlayers = 1},
            .has_dv = 1, .dv = {.set_levels = 1, .base_level = 0, .nlevels = 1, .set_layers = 1, .min_layer = 0, .nlayers = SLICES},
            .flags = 0
        };
        copy_t2t(&c_off);
        id<MTLTexture> off_tex = serial_get(dst_off.serial);
        CHECK(off_tex != nil, "DM_ASTC_ARRAYS=0 allocated destination");
        CHECK(off_tex.pixelFormat == MTLPixelFormatRGBA8Unorm, "DM_ASTC_ARRAYS=0 directly fell back to RGBA8Unorm baseline");
        mtl_sub_commit();

        printf("t_astc_array: %d checks, %d failures\n", checks, failures);
        return failures != 0;
    }
}
