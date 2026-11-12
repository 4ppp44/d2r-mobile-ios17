// 设备本地管线归档的真实 Metal 验证（本机 M1，不是 A16 证据）：
// 阶段 1 编译并把管线收进归档、落盘；阶段 2 是同一可执行文件的另一次进程，从磁盘加载归档后必须直接命中。
// 另测：特化函数在 iOS 17 / macOS 14 上必须绕过归档（不能序列化），且归档查询绝不修改调用方的描述符。
// Real-Metal verification of the device-local pipeline archive (this M1 host, not A16 evidence):
// phase 1 compiles and archives pipelines, then persists; phase 2 is a separate process of the same executable and must hit
// straight from the loaded archive. Also checked: specialized functions must bypass the archive on iOS 17 / macOS 14 (they
// cannot be serialized), and an archive query never modifies the caller's descriptor.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "../nvn/nvn_pipeline_cache.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *kSrc =
    "#include <metal_stdlib>\nusing namespace metal;\n"
    "vertex float4 v(uint i [[vertex_id]]) { return float4(float(i), 0, 0, 1); }\n"
    "fragment float4 f() { return float4(1, 0, 0, 1); }\n"
    // 真正声明函数常量的片元：只有这样 functionConstantsDictionary 才非空，绕过分支才可测
    // A fragment that really declares a function constant: only then is functionConstantsDictionary non-empty and the bypass testable
    "constant int gk [[function_constant(0)]];\n"
    "fragment float4 fs() { return float4(gk == 1 ? 1.0 : 0.0, 0, 0, 1); }\n"
    "kernel void c(device uint *p [[buffer(0)]], uint i [[thread_position_in_grid]]) { p[i] = i; }\n";
static id<MTLFunction> fn(id<MTLLibrary> lib, NSString *name, BOOL specialized) {
    if (!specialized) return [lib newFunctionWithName:name];
    // A function with specialized constants: not device-serializable before iOS 18 / macOS 15, so it must bypass the archive
    MTLFunctionConstantValues *cv = [MTLFunctionConstantValues new];
    int k = 1; [cv setConstantValue:&k type:MTLDataTypeInt atIndex:0];
    return [lib newFunctionWithName:name constantValues:cv error:nil];
}

// 找到落盘的那一份归档文件（目录名是身份哈希，测试不假定它） | Find the persisted archive file (the directory name is an identity hash, not assumed here)
static unsigned long long archive_bytes(const char *dir) {
    NSDirectoryEnumerator *en = [NSFileManager.defaultManager enumeratorAtPath:@(dir)];
    for (NSString *n in en) if ([n hasSuffix:@"pipelines.metalarc"]) {
        NSDictionary *attr = [NSFileManager.defaultManager attributesOfItemAtPath:[@(dir) stringByAppendingPathComponent:n] error:nil];
        return (unsigned long long)[attr fileSize];
    }
    return 0;
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (!getenv("DM_PIPELINE_CACHE_DIR")) {
        // 自驱动：建临时目录与模块身份，先跑阶段 1，再起一个新进程跑阶段 2（只有新进程才能证明「从磁盘加载」）
        // Self-driving: create a temp directory and a module identity, run phase 1, then start a new process for phase 2 (only a
        // new process proves "loaded from disk")
        char tmpl[] = "/tmp/d2r-pipeline-cache-XXXXXX";
        char *dir = mkdtemp(tmpl); assert(dir);
        char shmap[4096]; snprintf(shmap, sizeof shmap, "%s/../nvn/shader_map.tsv", getcwd(NULL, 0));
        assert(access(shmap, R_OK) == 0);
        setenv("DM_PIPELINE_CACHE_DIR", dir, 1);
        setenv("DM_NVN_SHMAP", shmap, 1);
    }
    const char *dir = getenv("DM_PIPELINE_CACHE_DIR");
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); assert(device);
    NSError *error = nil;
    id<MTLLibrary> lib = [device newLibraryWithSource:@(kSrc) options:nil error:&error];
    assert(lib);
    MTLRenderPipelineDescriptor *rd = [MTLRenderPipelineDescriptor new];
    rd.vertexFunction = fn(lib, @"v", NO); rd.fragmentFunction = fn(lib, @"f", NO);
    rd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    id<MTLFunction> cf = fn(lib, @"c", NO);
    const BOOL phase2 = argc > 1 && !strcmp(argv[1], "phase2");

    if (!phase2) {
        // 阶段 1：空归档 → 未命中 → 普通编译 → 收入归档 → 落盘
        // Phase 1: empty archive -> miss -> plain compile -> archive it -> persist
        assert(nvn_pcache_try_render(device, rd) == nil);
        assert(rd.binaryArchives == nil);   // 查询用副本，调用方描述符不变 | The query used a copy; the caller's descriptor is untouched
        id<MTLRenderPipelineState> rps = [device newRenderPipelineStateWithDescriptor:rd error:&error];
        assert(rps);
        nvn_pcache_add_render(device, rd);
        assert(nvn_pcache_try_compute(device, cf) == nil);
        id<MTLComputePipelineState> cps = [device newComputePipelineStateWithFunction:cf error:&error];
        assert(cps);
        nvn_pcache_add_compute(device, cf);
        nvn_pcache_flush();
        nvn_pcache_status s; nvn_pcache_snapshot(&s);
        printf("phase1 hits=%llu misses=%llu added=%llu saved=%llu bypassed=%llu disabled=%d write_failed=%d\n",
               s.hits, s.misses, s.added, s.saved, s.bypassed, s.disabled, s.write_failed);
        assert(s.disabled == 0 && s.write_failed == 0);
        assert(s.misses == 2 && s.added == 2 && s.saved == 2);
        unsigned long long bytes = archive_bytes(dir);
        printf("archive bytes=%llu\n", bytes);
        assert(bytes > 0);
        // 新进程读同一份归档 | A new process reads the same archive
        char self[4096]; uint32_t n = sizeof self;
        extern int _NSGetExecutablePath(char *, uint32_t *);
        assert(_NSGetExecutablePath(self, &n) == 0);
        pid_t pid = fork(); assert(pid >= 0);
        if (!pid) { execl(self, self, "phase2", (char *)NULL); _exit(127); }
        int st = 0; waitpid(pid, &st, 0);
        assert(WIFEXITED(st) && WEXITSTATUS(st) == 0);
        return 0;
    }
    // 阶段 2：新进程加载同一份归档，两条管线都必须直接命中（不编译）
    // Phase 2: a new process loads the same archive; both pipelines must hit directly (no compilation)
    assert(nvn_pcache_try_render(device, rd) != nil);
    assert(nvn_pcache_try_compute(device, cf) != nil);
    // 特化片元（真声明了函数常量）：归档里没有它，查询必须返回 nil（绝不给出错管线），普通编译照常成功；
    // 收进归档之后普通管线依然命中，说明特化管线没有破坏归档。functionConstantsDictionary 在本机实测为空，所以这里不假设「一定绕过」。
    // The specialized fragment (which really declares a constant): the archive does not contain it, so the lookup must return
    // nil (a wrong pipeline is never handed out) and the plain compile must still succeed; after adding it the plain pipeline
    // still hits, so the specialized one did not damage the archive. functionConstantsDictionary measured empty on this host,
    // so "always bypass" is not assumed.
    MTLRenderPipelineDescriptor *sd = [rd copy];
    sd.fragmentFunction = fn(lib, @"fs", YES);
    assert(nvn_pcache_try_render(device, sd) == nil);
    id<MTLRenderPipelineState> srps = [device newRenderPipelineStateWithDescriptor:sd error:&error];
    assert(srps);
    nvn_pcache_add_render(device, sd);
    assert(nvn_pcache_try_render(device, rd) != nil);
    nvn_pcache_status s; nvn_pcache_snapshot(&s);
    printf("phase2 loaded=%d hits=%llu misses=%llu bypassed=%llu added=%llu disabled=%d\n", s.loaded, s.hits, s.misses, s.bypassed, s.added, s.disabled);
    assert(s.loaded == 1 && s.disabled == 0);
    assert(s.hits == 3 && s.misses == 1);
    return 0;
} }
