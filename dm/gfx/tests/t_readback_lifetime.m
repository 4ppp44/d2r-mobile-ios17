// Real Metal readback lifetime test: verify @autoreleasepool in mtl_read_texels prevents command buffer accumulation outside submission.
#include "../nvn/nvn_mtl.m"

void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

@interface WeakHolder : NSObject {
@public
    __weak id obj;
}
@end
@implementation WeakHolder
@end

@interface TrackQueue : NSProxy {
@public
    id<MTLCommandQueue> real;
    NSMutableArray<WeakHolder *> *tracked_cbs;
}
@end

@implementation TrackQueue
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [(NSObject *)real methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)i { [i invokeWithTarget:real]; }
- (id<MTLCommandBuffer>)commandBuffer {
    id<MTLCommandBuffer> cb = [real commandBuffer];
    WeakHolder *h = [WeakHolder new];
    h->obj = cb;
    [tracked_cbs addObject:h];
    return cb;
}
@end

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

        TrackQueue *tq = [TrackQueue alloc];
        tq->real = g_q;
        tq->tracked_cbs = [NSMutableArray array];
        g_q = (id<MTLCommandQueue>)tq;

        const int W = 16, H = 16;
        uint8_t ref[W * H * 4];
        for (int y = 0; y < H; y++) {
            for (int x = 0; x < W; x++) {
                int idx = (y * W + x) * 4;
                ref[idx + 0] = (uint8_t)((x * 17 + y * 23 + 0x3c) & 0xff);
                ref[idx + 1] = (uint8_t)((x * 31 + y * 11 + 0x7a) & 0xff);
                ref[idx + 2] = (uint8_t)((x * 7 + y * 41 + 0xb5) & 0xff);
                ref[idx + 3] = 255;
            }
        }

        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:W height:H mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        td.storageMode = MTLStorageModeShared;
        id<MTLTexture> mtex = [dev newTextureWithDescriptor:td];
        [mtex replaceRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0 withBytes:ref bytesPerRow:W * 4];

        tex_t tex = {.serial = 88001};
        tex.d.width = W; tex.d.height = H; tex.d.depth = 1; tex.d.levels = 1; tex.d.samples = 1;
        tex.d.target = NVN_TEXTURE_TARGET_2D; tex.d.format = NVN_FORMAT_RGBA8;
        serial_put(tex.serial, mtex);

        NVNcopyRegion region = { .xoffset = 0, .yoffset = 0, .zoffset = 0, .width = W, .height = H, .depth = 1 };
        uint8_t dst[W * H * 4];

        const int N = 32;
        // Loop runs without an inner @autoreleasepool. If mtl_read_texels lacks an internal
        // @autoreleasepool, each call's command buffer and buffers accumulate in the outer pool.
        for (int i = 0; i < N; i++) {
            memset(dst, 0, sizeof dst);
            mtl_read_texels(&tex, 0, 0, &region, dst, W * 4, W * H * 4);
        }

        int living_cbs = 0;
        for (WeakHolder *h in tq->tracked_cbs) {
            if (h->obj != nil) living_cbs++;
        }

        printf("READBACK_LIFETIME: calls=%d tracked=%lu living_cbs=%d (expected 0)\n", N, (unsigned long)tq->tracked_cbs.count, living_cbs);
        CHECK(tq->tracked_cbs.count >= (NSUInteger)N, "tracked_all_readback_command_buffers");
        CHECK(living_cbs == 0, "all_readback_cbs_released_via_internal_autoreleasepool");

        int bad_pixels = 0;
        for (int i = 0; i < W * H * 4; i++) {
            if (dst[i] != ref[i]) bad_pixels++;
        }
        CHECK(bad_pixels == 0, "readback_pixels_match_texture_exactly");

        printf("t_readback_lifetime checks=%d failures=%d\n", checks, failures);
        return failures ? 1 : 0;
    }
}
