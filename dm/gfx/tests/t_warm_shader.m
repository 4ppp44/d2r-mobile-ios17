// Verify that shader_get claims already-published warm shaders on cache miss
// without redundant newLibraryWithData calls or waiting for the remaining warm-up.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

static int library_calls;
@interface ProbeDevice : NSProxy { @public id<MTLDevice> real; int compute_calls; }
@end
@implementation ProbeDevice
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [(NSObject *)real methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)i { [i invokeWithTarget:real]; }
- (id<MTLLibrary>)newLibraryWithData:(dispatch_data_t)data error:(NSError **)error {
    library_calls++;
    return [real newLibraryWithData:data error:error];
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)f error:(NSError **)error {
    compute_calls++;
    return [real newComputePipelineStateWithFunction:f error:error];
}
@end

static int checks, failed;
#define CK(name, cond) do { checks++; int ok = !!(cond); failed += !ok; printf("%s %s\n", name, ok ? "PASS" : "FAIL"); } while (0)

static int run_mode(const char *mode, NSString *msl_dir, id<MTLDevice> dev, ProbeDevice *counter) {
    int render = !strcmp(mode, "render"), compute = !strcmp(mode, "compute");
    int published = !strcmp(mode, "published") || render || compute;
    int cached = !strcmp(mode, "cached"), unrelated = !strcmp(mode, "unrelated");

    // Reset probe counters and globals for this mode run
    library_calls = 0;
    counter->compute_calls = 0;
    g_dev = (id<MTLDevice>)counter;
    g_msl_dir = msl_dir;
    g_shcache = [NSMutableDictionary dictionary];
    g_warm_items = [NSMutableArray array];
    atomic_store(&g_warm_ready, 0);
    atomic_store(&g_warm_running, 0);

    NvShader *warmed = nil;
    id<MTLComputePipelineState> warmed_cps = nil;
    if (compute) {
        warmed = shader_load(@"probe_cs_b", 5);
        if (!warmed || !warmed->fn) return 1;
        NSError *error = nil;
        warmed_cps = [dev newComputePipelineStateWithFunction:warmed->fn error:&error];
        if (!warmed_cps) return 1;
        WarmItem *item = [WarmItem new]; item->kind = 2; item->key = @"probe_cs_b"; item->shader = warmed; item->object = warmed_cps;
        warm_enqueue(item);
        atomic_store(&g_warm_running, 1);
        int before_c = counter->compute_calls;
        id<MTLComputePipelineState> ps = cps_get(warmed);
        int new_c = counter->compute_calls - before_c;
        CK("compute_claimed_identity", ps == warmed_cps && ps != nil);
        CK("compute_no_new_pipeline_calls", new_c == 0);
        if (!ps) return 1;
        WarmItem *unrelated_item = [WarmItem new]; unrelated_item->kind = 0;
        unrelated_item->key = @"other_b"; unrelated_item->shader = shader_load(@"other_b", 1);
        warm_enqueue(unrelated_item);
        CK("compute_hot_hit_preserves_pending_work", cps_get(warmed) == ps && counter->compute_calls == before_c && atomic_load(&g_warm_ready));
        NvShader *cold_cs = [NvShader new]; cold_cs->fn = warmed->fn; strcpy(cold_cs->key, "cold_cs_b");
        id<MTLComputePipelineState> cold_ps = cps_get(cold_cs);
        CK("compute_unrelated_publication_falls_back_once", cold_ps != nil && counter->compute_calls == before_c + 1);
        CK("compute_cold_pipeline_cached", cps_get(cold_cs) == cold_ps && counter->compute_calls == before_c + 1);
        id<MTLBuffer> buf = [dev newBufferWithLength:64 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
        id<MTLCommandQueue> queue = [dev newCommandQueue]; id<MTLCommandBuffer> cb = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
        [enc setComputePipelineState:ps]; [enc setBuffer:buf offset:0 atIndex:0];
        [enc dispatchThreads:MTLSizeMake(64, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
        [enc endEncoding]; [cb commit]; [cb waitUntilCompleted];
        uint32_t *out = (uint32_t *)buf.contents; int bad = 0;
        for (unsigned i = 0; i < 64; i++) bad += out[i] != (0x5a000000u + i);
        CK("compute_gpu_exact_values", bad == 0 && cb.status == MTLCommandBufferStatusCompleted);
        return ps != warmed_cps || new_c != 0 || bad != 0 || cb.status != MTLCommandBufferStatusCompleted;
    }
    if (published || cached) {
        warmed = shader_load(@"probe_b", 1);
        if (!warmed || !warmed->fn) return 1;
        if (cached) { g_shcache[@"probe_b"] = warmed; atomic_fetch_add(&g_shcache_n, 1); }
    }
    if (published || cached || unrelated) {
        WarmItem *item = [WarmItem new]; item->kind = 0;
        item->key = cached || unrelated ? @"other_b" : @"probe_b";
        item->shader = cached || unrelated ? shader_load(@"other_b", 1) : warmed;
        if (!item->shader) return 1;
        if (render) {
            NSError *error = nil;
            id<MTLLibrary> lib = [dev newLibraryWithURL:[NSURL fileURLWithPath:[g_msl_dir stringByAppendingPathComponent:@"probe_b.metallib"]] error:&error];
            NvShader *vs = [NvShader new]; vs->fn = [lib newFunctionWithName:@"v"]; strcpy(vs->key, "probe_v");
            memset(&S, 0, sizeof S); S.chmask.mask = 15;
            memset(&g_pass, 0, sizeof g_pass); g_pass.cfmt[0] = MTLPixelFormatRGBA8Unorm; g_pass.samples = 1;
            item->kind = 1; item->vs_key = @"probe_v"; item->fs_key = @"probe_b"; item->vs = vs; item->fs = warmed;
            pso_key_fill(&item->pso, vs, warmed, g_pass.cfmt, 0, 0, 1, 0);
            item->object = [dev newRenderPipelineStateWithDescriptor:pso_desc(&item->pso, vs, warmed, nil, 0) error:&error];
            if (!item->object) return 1;
        }
        warm_enqueue(item);
    }
    atomic_store(&g_warm_running, 1); // Published while remaining warm-up is still marked running

    int before = library_calls;
    NvShader *got = shader_get(@"probe_b", 1);
    int new_calls = library_calls - before;

    int duplicate = published && (new_calls != 0 || got != warmed);
    int fallback_bad = !published && !cached && new_calls != 1;
    int hot_bad = cached && (new_calls != 0 || got != warmed || !atomic_load(&g_warm_ready));
    if (!got || !got->fn) return 1;

    NSError *error = nil;
    NSString *libpath = [g_msl_dir stringByAppendingPathComponent:@"probe_b.metallib"];
    id<MTLLibrary> lib = [dev newLibraryWithURL:[NSURL fileURLWithPath:libpath] error:&error];
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [lib newFunctionWithName:@"v"]; desc.fragmentFunction = got->fn;
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    id<MTLRenderPipelineState> ps = [dev newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!ps) return 1;

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];
    td.storageMode = MTLStorageModeShared; td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> texture = [dev newTextureWithDescriptor:td];
    id<MTLCommandQueue> queue = [dev newCommandQueue]; id<MTLCommandBuffer> cb = [queue commandBuffer];
    MTLRenderPassDescriptor *pd = [MTLRenderPassDescriptor renderPassDescriptor];
    pd.colorAttachments[0].texture = texture; pd.colorAttachments[0].loadAction = MTLLoadActionClear; pd.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pd];
    [enc setRenderPipelineState:ps]; [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [enc endEncoding];
    [cb commit]; [cb waitUntilCompleted];

    uint8_t pixels[256]; [texture getBytes:pixels bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0];
    int bad = 0; const uint8_t green[4] = {0,255,0,255};
    for (int i=0;i<64;i++) bad += memcmp(pixels+4*i, green,4) != 0;

    char lbl[128];
    snprintf(lbl, sizeof lbl, "%s_no_duplicate_or_fallback_error", mode);
    CK(lbl, !duplicate && !fallback_bad && !hot_bad);
    snprintf(lbl, sizeof lbl, "%s_gpu_exact_green_pixels", mode);
    CK(lbl, bad == 0 && cb.status == MTLCommandBufferStatusCompleted);
    return duplicate || fallback_bad || hot_bad || bad || cb.status != MTLCommandBufferStatusCompleted;
}

int main(void) { @autoreleasepool {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) { fprintf(stderr, "NO_METAL_DEVICE\n"); return 2; }
    ProbeDevice *counter = [ProbeDevice alloc]; counter->real = dev;

    char dir_tmpl[] = "/tmp/d2r-warm-test-XXXXXX";
    if (!mkdtemp(dir_tmpl)) { perror("mkdtemp"); return 2; }
    NSString *msl_dir = @(dir_tmpl);

    // Compile minimal probe metal source into metallib in temporary directory
    NSString *metal_src = @"#include <metal_stdlib>\nusing namespace metal;\nvertex float4 v(uint i [[vertex_id]]) { float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],0,1); }\nfragment float4 f() { return float4(0,1,0,1); }\nkernel void c(device uint *out [[buffer(0)]], uint id [[thread_position_in_grid]]) { out[id] = 0x5a000000u + id; }\n";
    NSString *metal_path = [msl_dir stringByAppendingPathComponent:@"probe.metal"];
    NSString *air_path = [msl_dir stringByAppendingPathComponent:@"probe.air"];
    NSString *lib_path = [msl_dir stringByAppendingPathComponent:@"probe_b.metallib"];
    NSString *other_lib_path = [msl_dir stringByAppendingPathComponent:@"other_b.metallib"];
    NSString *cs_lib_path = [msl_dir stringByAppendingPathComponent:@"probe_cs_b.metallib"];
    [metal_src writeToFile:metal_path atomically:YES encoding:NSUTF8StringEncoding error:nil];

    char cmd[1024];
    snprintf(cmd, sizeof cmd, "TMPDIR=/tmp xcrun metal -c '%s' -o '%s' && xcrun metallib '%s' -o '%s' && cp '%s' '%s' && cp '%s' '%s'",
             metal_path.fileSystemRepresentation, air_path.fileSystemRepresentation,
             air_path.fileSystemRepresentation, lib_path.fileSystemRepresentation,
             lib_path.fileSystemRepresentation, other_lib_path.fileSystemRepresentation,
             lib_path.fileSystemRepresentation, cs_lib_path.fileSystemRepresentation);
    if (system(cmd) != 0) {
        fprintf(stderr, "Failed to compile probe metal source\n");
        [NSFileManager.defaultManager removeItemAtPath:msl_dir error:nil];
        return 2;
    }

    for (NSString *key in @[@"probe_b", @"other_b"]) {
        NSDictionary *j = @{@"chain": @DMSH_CHAIN, @"route": @"B", @"bindings": @[], @"entry": @"f"};
        NSData *d = [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
        [d writeToFile:[msl_dir stringByAppendingPathComponent:[key stringByAppendingString:@".json"]] atomically:YES];
    }
    {
        NSDictionary *j = @{@"chain": @DMSH_CHAIN, @"route": @"B", @"bindings": @[], @"entry": @"c"};
        NSData *d = [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
        [d writeToFile:[msl_dir stringByAppendingPathComponent:@"probe_cs_b.json"] atomically:YES];
    }

    const char *modes[] = {"published", "render", "compute", "cached", "cold", "unrelated"};
    int mode_failures = 0;
    for (int i = 0; i < 6; i++) {
        mode_failures += run_mode(modes[i], msl_dir, dev, counter);
    }

    [NSFileManager.defaultManager removeItemAtPath:msl_dir error:nil];
    printf("WARM_SHADER checks=%d failed=%d\n", checks, failed);
    return failed != 0 || mode_failures != 0;
} }
