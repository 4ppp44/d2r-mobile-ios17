// Streaming upload budget test:
// 64 streaming uploads (>128 MiB) inside an open render pass; prove staging buffers
// are retired on completion (idle <= 96 MiB) while render pass is uncommitted, and verify pixels.
#include "../nvn/nvn_mtl.m"

void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

static int checks, failures;
#define CHECK(c, name) do { checks++; if (!(c)) { failures++; printf("FAIL: %s\n", name); } else { printf("PASS: %s\n", name); } } while (0)

int main(void) {
    @autoreleasepool {
        mtl_init();
        id<MTLDevice> dev = g_dev;
        if (!dev) {
            fprintf(stderr, "NO_REAL_METAL_DEVICE\n");
            return 2;
        }

        const int NUM_TEX = 64;
        const uint32_t TEX_W = 768, TEX_H = 768;
        nvn_texdesc d = {
            .width = TEX_W, .height = TEX_H, .depth = 1, .levels = 1, .samples = 1,
            .target = NVN_TEXTURE_TARGET_2D, .format = NVN_FORMAT_RGBA8
        };
        nvn_texlayout layout;
        nvn_tex_layout(&d, &layout);

        void *host_mems[NUM_TEX];
        tex_t texs[NUM_TEX];
        size_t page_sz = getpagesize();
        size_t alloc_sz = (layout.size + page_sz - 1) & ~(page_sz - 1);

        uint8_t *linear = malloc(TEX_W * TEX_H * 4);
        for (int i = 0; i < NUM_TEX; i++) {
            posix_memalign(&host_mems[i], page_sz, alloc_sz);
            uint32_t *px = (uint32_t *)linear;
            uint32_t val = (uint32_t)(0xff000000 | ((i & 0xff) << 16) | (((i * 7) & 0xff) << 8) | ((i * 13) & 0xff));
            for (size_t p = 0; p < TEX_W * TEX_H; p++) px[p] = val;
            nvn_swizzle(&d, 0, 0, linear, TEX_W * 4, host_mems[i]);
            mtl_pool_add(host_mems[i], layout.size);

            memset(&texs[i], 0, sizeof(tex_t));
            texs[i].serial = 92000 + i;
            texs[i].d = d;
            texs[i].has_layout = 1;
            texs[i].L = layout;
            texs[i].mem = host_mems[i];
        }
        free(linear);

        // 1. Begin main render submission and open a render pass.
        mtl_sub_begin();
        MTLTextureDescriptor *rt_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:64 height:64 mipmapped:NO];
        rt_desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        rt_desc.storageMode = MTLStorageModeShared;
        id<MTLTexture> rt_tex = [dev newTextureWithDescriptor:rt_desc];
        res_add(rt_tex);

        RPD *rpd = [RPD new];
        rpd.colorAttachments[0].texture = rt_tex;
        rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
        rpd.colorAttachments[0].storeAction = MTLStoreActionStore;
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        id<MTLRenderCommandEncoder> renc = enc_r_begin(rpd);
        CHECK(renc != nil, "render_pass_encoder_open");

        // 2. Perform 64 streaming uploads (>128 MiB total) while render pass is open and uncommitted.
        for (int i = 0; i < NUM_TEX; i++) {
            id<MTLTexture> mt = tex_mtl(&texs[i]);
            if (!mt) {
                printf("FAIL: tex_mtl(%d) returned nil\n", i);
                failures++;
            }
        }
        // Flush any remaining staging in the current upload batch.
        up_flush();

        // 3. Wait for upload command buffers to finish executing on the GPU.
        while (atomic_load(&g_up_pending)) usleep(1000);

        // 4. Measure staging memory still held in residency while render pass remains open and uncommitted.
        pthread_mutex_lock(&g_res_mu);
        size_t staging_res_bytes = 0;
        int staging_blocks = 0;
        for (id obj in g_res_objects) {
            if ([obj conformsToProtocol:@protocol(MTLBuffer)]) {
                id<MTLBuffer> b = (id<MTLBuffer>)obj;
                if (b.length >= UP_BLOCK_SIZE) {
                    staging_res_bytes += b.length;
                    staging_blocks++;
                }
            }
        }
        pthread_mutex_unlock(&g_res_mu);

        printf("STREAMING_UPLOAD: uploaded=%d textures (144 MiB), open render pass uncommitted, staging_res_bytes=%zu (%zu MB in %d blocks)\n",
               NUM_TEX, staging_res_bytes, staging_res_bytes >> 20, staging_blocks);
        // Under 7dc250e2, completed upload staging buffers are retired independently of the main render fence.
        // The earlier batch was retired upon upload completion, leaving only the active batch (<= 32 MiB, well <= 96 MiB).
        // On baseline, all staging buffers were tied to the main render fence and remain deferred (> 128 MiB).
        CHECK(staging_res_bytes <= 96u * 1024u * 1024u, "staging_retired_while_render_pass_uncommitted");

        // 5. Close render pass encoder, commit main submission, and verify GPU execution.
        enc_r_end(renc);
        uint64_t fence = mtl_sub_commit();
        CHECK(mtl_wait(fence, 5000000000ull), "main_submission_gpu_wait");
        CHECK(!mtl_last_commit_error(), "main_submission_no_error");

        // 6. Verify pixel content of uploaded textures (first, middle, last).
        int test_indices[3] = {0, 31, 63};
        int all_pixels_ok = 1;
        for (int t = 0; t < 3; t++) {
            int idx = test_indices[t];
            uint32_t expected = (uint32_t)(0xff000000 | ((idx & 0xff) << 16) | (((idx * 7) & 0xff) << 8) | ((idx * 13) & 0xff));
            NVNcopyRegion r = { .xoffset = 0, .yoffset = 0, .zoffset = 0, .width = 16, .height = 16, .depth = 1 };
            uint32_t readback[16 * 16];
            mtl_read_texels(&texs[idx], 0, 0, &r, (uint8_t *)readback, 16 * 4, 16 * 16 * 4);
            int bad = 0;
            for (int p = 0; p < 256; p++) {
                if (readback[p] != expected) bad++;
            }
            if (bad) {
                printf("FAIL: tex %d had %d bad texels (expected 0x%08x, got 0x%08x)\n", idx, bad, expected, readback[0]);
                all_pixels_ok = 0;
            }
        }
        CHECK(all_pixels_ok, "all_sampled_texture_pixels_exact");

        for (int i = 0; i < NUM_TEX; i++) free(host_mems[i]);

        printf("t_upload_budget checks=%d failures=%d\n", checks, failures);
        return failures ? 1 : 0;
    }
}
