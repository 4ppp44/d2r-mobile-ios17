// Real cached reflection -> production encode_args -> synthetic host Metal compute.
// Does not execute game shaders or establish iOS/device/visual causality.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void){return NULL;} module_t *module_of(const void *p){(void)p;return NULL;}
module_t g_mod[MAX_MOD]; int g_nmod; void svc_thread_dump(void){} uint64_t now_ns(void){return bp_now();}
static int checks, failed;
#define CK(n,c) do { int ok = !!(c); checks++; failed += !ok; printf("%s %s\n", n, ok ? "PASS" : "FAIL"); } while (0)
static int parse(NSDictionary *j, nvn_refl *r) { char err[256] = ""; int rc = nvn_refl_from_json(j, r, err, sizeof err); if (rc) printf("parse rejected: %s\n", err); return rc; }
static NSMutableDictionary *fixture(NSString *stage, NSArray *bindings, id reads) {
    NSMutableDictionary *j = [@{@"route": @"B", @"bindings": bindings} mutableCopy];
    if (stage) j[@"stage"] = stage; if (reads) j[@"drv_reads"] = reads; return j;
}
static void controls(void) {
    NSArray *bs = @[@{@"kind": @"drvcb", @"bank": @0, @"arg_id": @0}, @{@"kind": @"drvcb", @"bank": @2, @"arg_id": @1}];
    nvn_refl r;
    for (NSString *stage in @[@"vs", @"cs", @"hs", @"ds", @"gs", @"ps", @"unknown", @""]) {
        NSMutableDictionary *j = fixture(stage, bs, @{});
        CK("stage_parse", parse(j, &r) == 0);
        int want = [@[@"vs", @"cs", @"hs", @"ds", @"gs"] containsObject:stage];
        printf("stage=%s read=%u/%u\n", stage.UTF8String, r.drv_read[0], r.drv_read[2]);
        CK("stage_policy", r.drv_read[0] == want && r.drv_read[2] == want);
        CK("no_fabricated_offsets", r.drv_noff[0] == 0 && r.drv_noff[2] == 0);
    }
    CK("missing_stage_unchanged", !parse(fixture(nil, bs, @{}), &r) && !r.drv_read[0] && !r.drv_read[2]);
    CK("no_binding_no_fallback", !parse(fixture(@"cs", @[], @{}), &r) && !r.drv_read[0] && !r.drv_read[2]);
    CK("missing_metadata", !parse(fixture(@"cs", bs, nil), &r) && r.drv_read[0] && r.drv_read[2]);
    NSDictionary *precise = @{@"0": @{@"vec4_offsets": @[@784], @"dynamic": @NO}};
    CK("preserve_precise_fill_missing_bank", !parse(fixture(@"cs", bs, precise), &r) && r.drv_noff[0] == 1 && r.drv_off[0][0] == 784 && r.drv_read[2] && !r.drv_noff[2]);
    for (NSDictionary *entry in @[@{@"vec4_offsets": @[], @"dynamic": @YES}, @{@"vec4_offsets": @[@2560]}, @{@"vec4_offsets": @[@(-16)]}, @{@"vec4_offsets": @[@785]}, @{@"vec4_offsets": @[@0,@16,@32,@48,@64,@80,@96,@112,@128,@144,@160]}]) {
        CK("invalid_metadata_still_rejected", parse(fixture(@"cs", bs, @{@"0": entry}), &r) != 0);
    }
    NSMutableDictionary *uf = fixture(@"cs", bs, @{}); uf[@"drv_unfillable"] = @[@"c0+0x0"];
    CK("unfillable_still_rejected", parse(uf, &r) != 0);
    // A missing bank gets the fallback; the declared bank's metadata stays authoritative.
    CK("explicit_empty_entry", !parse(fixture(@"cs", bs, @{@"0": @{@"vec4_offsets": @[], @"dynamic": @NO}}), &r) && r.drv_read[0] && !r.drv_noff[0]);
}
int main(int argc, char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    controls(); mtl_init(); CK("Metal_device", g_dev != nil); if (!g_dev) return 2;
    printf("host_device=%s; synthetic compute, not iOS game proof\n", g_dev.name.UTF8String);
    const char *keys[] = {"fbc4a0eb955f5960_b", "fc85981c8d9148c9_b"};
    for (int k = 0; k < 2; k++) {
        NSString *path = [NSString stringWithFormat:@"%s/%s.json", argv[1], keys[k]];
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSDictionary *j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        CK("real_JSON_loaded", j != nil); if (!j) continue;
        CK("real_JSON_cs_empty_reads", [j[@"stage"] isEqual:@"cs"] && [j[@"drv_reads"] count] == 0);
        NvShader *sh = [NvShader new];
        CK("real_JSON_parse", parse(j, &sh->rf) == 0);
        CK("real_JSON_driver_read", sh->rf.drv_read[0] == 1);
        CK("real_JSON_no_invented_offsets", sh->rf.drv_noff[0] == 0);
        // Keep the complete real reflection and its arg IDs. Declare preceding pointer
        // members to preserve cp_c0's byte position; only cp_c0 is read by this kernel.
        int aid = -1; for (int i = 0; i < sh->rf.nb; i++) if (sh->rf.b[i].kind == NVN_RB_DRV0) aid = sh->rf.b[i].aid;
        CK("real_drvcb_binding", aid >= 0); if (aid < 0) continue;
        NSMutableString *members = [NSMutableString string];
        for (int i = 0; i < aid; i++) [members appendFormat:@"constant uint4 *unused%d [[id(%d)]];", i, i];
        NSString *src = [NSString stringWithFormat:@"#include <metal_stdlib>\nusing namespace metal;\nstruct A { %@ constant uint4 *c [[id(%d)]]; };\nkernel void probe(constant A&a [[buffer(0)]], device ulong*out [[buffer(1)]]) { uint4 x=a.c[49], y=a.c[50]; out[0]=as_type<ulong2>(x).x; out[1]=as_type<ulong2>(y).x; out[2]=x.z; out[3]=y.z; }\n", members, aid];
        NSError *err = nil; id<MTLLibrary> lib = [g_dev newLibraryWithSource:src options:nil error:&err];
        if (!lib) printf("compile: %s\n", err.description.UTF8String);
        CK("synthetic_compute_compiles", lib != nil); if (!lib) continue;
        sh->fn = [lib newFunctionWithName:@"probe"]; sh->ae = [sh->fn newArgumentEncoderWithBufferIndex:0];
        // Production memcpy emits the complete real argument table. Allocate enough for it,
        // including real bindings after cp_c0 that the synthetic kernel does not declare.
        sh->arg_len = MAX(sh->ae.encodedLength, (NSUInteger)sh->rf.nb * 8); sh->stage = 5;
        strlcpy(sh->key, keys[k], sizeof sh->key);
        id<MTLComputePipelineState> ps = [g_dev newComputePipelineStateWithFunction:sh->fn error:&err];
        CK("compute_pipeline", ps != nil); if (!ps) continue;
        void *mem[2]; for (int i = 0; i < 2; i++) {
            posix_memalign(&mem[i], getpagesize(), getpagesize()); memset(mem[i], 0, getpagesize()); mtl_pool_add(mem[i], getpagesize());
            S.ssbo[5][i] = (p_bind_buf){.stage=5,.index=i,.addr=(uint64_t)mem[i],.size=256 + i * 128};
        }
        S.ubo[5][3] = (p_bind_buf){.stage=5,.index=3,.addr=(uint64_t)mem[0],.size=256};
        id<MTLBuffer> out = [g_dev newBufferWithLength:32 options:MTLResourceStorageModeShared]; memset(out.contents, 0xff, 32);
        mtl_sub_begin(); args_touch(5); id<MTLComputeCommandEncoder> ce = enc_c_begin(NULL);
        [ce setComputePipelineState:ps]; CK("production_encode_args", encode_args(ce, sh, 5, 0));
        [ce setBuffer:out offset:0 atIndex:1]; [ce dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)]; enc_c_end(ce);
        CK("GPU_completed", mtl_wait(mtl_sub_commit(), 5000000000ull)); CK("GPU_no_error", mtl_last_commit_error() == 0);
        uint64_t *v = out.contents;
        printf("key=%s read=%u noff=%u GPU[310]=%#llx GPU[320]=%#llx expected=%#llx/%#llx sizes=%llu/%llu\n", keys[k], sh->rf.drv_read[0], sh->rf.drv_noff[0], v[0], v[1], (uint64_t)mem[0], (uint64_t)mem[1], v[2], v[3]);
        CK("GPU_0x310_nonzero_SSBO_address", v[0] != 0 && v[0] == (uint64_t)mem[0]);
        CK("GPU_0x320_nonzero_SSBO_address", v[1] != 0 && v[1] == (uint64_t)mem[1]);
        CK("GPU_SSBO_sizes", v[2] == 256 && v[3] == 384);
        for (int i = 0; i < 2; i++) { mtl_pool_del(mem[i]); free(mem[i]); }
    }
    printf("DRIVER_RUNTIME checks=%d failed=%d\n", checks, failed); return failed != 0;
} }
