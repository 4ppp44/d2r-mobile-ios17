// 设备本地 Metal 二进制归档的实现（见 nvn_pipeline_cache.h 的说明）。
// 线程模型：所有归档访问都在 cache_mu 下串行——MTLBinaryArchive 不是线程安全的，而管线可能在提交线程、
// 两条预编工作线程、预热后台队列上同时创建。普通编译刻意放在锁外，预编的并行度不受影响。
// 失败策略：归档只是加速，任何一步失败（目录、加载、序列化、空间不足）都退回普通编译，绝不改变实际管线描述符。
// Implementation of the device-local Metal binary archive (see nvn_pipeline_cache.h).
// Threading: every archive access is serialized under cache_mu - MTLBinaryArchive is not thread-safe, and pipelines may be
// created on the submit thread, both precompile workers and the warm-up background queue. Ordinary compilation deliberately
// stays outside the lock so precompile parallelism is unaffected.
// Failure policy: the archive is only an accelerator. Any failure (directory, load, serialization, free space) falls back to
// ordinary compilation and never changes the actual pipeline descriptor.
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <TargetConditionals.h>
#include <sys/sysctl.h>
#include <sys/statvfs.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include "nvn_pipeline_cache.h"
#include "dmsh_chain.h"

#define PCLOG(...) do { fprintf(stderr, "[pipeline-cache] " __VA_ARGS__); fputc('\n', stderr); } while (0)
// 描述符生成方式或工具着色器语义变化时才改它：改了等于让旧归档全部作废。
// Bump only when descriptor generation or utility shader semantics change: bumping invalidates every existing archive.
#define CACHE_ABI "d2r-ios17-pso-1"
#define CACHE_MAX_BYTES (256ull << 20)
#define CACHE_RESERVE_BYTES (128ull << 20)
static pthread_mutex_t cache_mu = PTHREAD_MUTEX_INITIALIZER;
static id<MTLBinaryArchive> archive;
static NSString *cache_file;
static nvn_pcache_status stats;
static int initialized, save_scheduled, flushing;   // flushing：正在序列化 / 写盘，避免两个刷盘同时跑 | a save is in flight, so two saves never overlap
static _Atomic uint64_t add_gen;   // 每收进一条新管线自增：刷盘只在「静默」时做，避免一局里反复序列化整份归档 | bumped per added pipeline: saves only happen when quiet, so a run does not re-serialize the whole archive repeatedly

static NSString *digest(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *s = [NSMutableString string];
    for (unsigned i = 0; i < sizeof hash; ++i) [s appendFormat:@"%02x", hash[i]];
    return s;
}
static NSString *file_digest(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    return d ? digest(d) : @"missing";
}
// 持 cache_mu 调用。归档身份刻意不含包版本号：同源更新可复用；游戏模块、着色器表、GPU、系统版本本身已把它们分开。
// Called under cache_mu. The archive identity deliberately omits the package version: compatible updates reuse it, while the
// game modules, shader tables, GPU and OS version already partition it.
static void cache_init(id<MTLDevice> device) {
    if (initialized) return;
    initialized = 1;
    const char *override = getenv("DM_PIPELINE_CACHE_DIR");
    const char *mode = getenv("DM_PIPELINE_CACHE");
    if (mode && !strcmp(mode, "off")) { stats.disabled = 1; return; }
#if TARGET_OS_IPHONE
    // 真机默认关。build2803 两次真机日志：loaded=1，但整个会话命中只有 5 次、未命中 900–1200 次；
    // 每次启动都要把约 1000 条管线收进归档、再序列化出 12 MB 文件。拿不到任何加速，却实打实花掉启动和落盘的 CPU。
    // 需要时在 Documents 放 dm_archive（内容含 1）打开，或本机测试用 DM_PIPELINE_CACHE=on。
    // Off by default on a device. Both build2803 device logs show loaded=1 with only 5 hits and 900-1200 misses for the whole
    // session, while every launch archived ~1000 pipelines and serialized a 12 MB file. That buys no speedup and spends real
    // CPU on archiving and saving. Put a dm_archive file (containing 1) into Documents to turn it on, or use
    // DM_PIPELINE_CACHE=on on the host.
    if (!(mode && !strcmp(mode, "on"))) {
        int on = 0;
        const char *sv = getenv("DM_SAVE");
        if (sv && *sv) {
            char dir[1024];
            snprintf(dir, sizeof dir, "%s", sv);
            char *slash = strrchr(dir, '/');
            if (slash && slash != dir) {
                *slash = 0;
                char path[1200];
                snprintf(path, sizeof path, "%s/dm_archive", dir);
                FILE *f = fopen(path, "rb");
                if (f) { char b[16]; size_t n = fread(b, 1, sizeof b, f); fclose(f); for (size_t i = 0; i < n; i++) if (b[i] == '1') { on = 1; break; } }
            }
        }
        if (!on) { stats.disabled = 1; PCLOG("device default off; Documents/dm_archive=1 enables it"); return; }
    }
#endif
#if !TARGET_OS_IPHONE
    if (!override) { stats.disabled = 1; return; }   // 宿主默认不写盘：只有显式给目录的测试/测量才用 | Host defaults to no persistence: only tests/measurements that pass a directory use it
#endif
    NSString *dm = getenv("DM_NVN_SHMAP") ? [@(getenv("DM_NVN_SHMAP")) stringByDeletingLastPathComponent] : nil;
    if (!dm) { stats.disabled = 1; return; }
    char osbuild[128] = {0}; size_t size = sizeof osbuild;
    sysctlbyname("kern.osversion", osbuild, &size, NULL, 0);
    NSMutableArray *identity = [NSMutableArray arrayWithArray:@[@CACHE_ABI, @DMSH_CHAIN,
        device.name ?: @"unknown", @(device.registryID), @(osbuild),
        NSProcessInfo.processInfo.operatingSystemVersionString]];
    NSArray *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dm error:nil] sortedArrayUsingSelector:@selector(compare:)];
    BOOL has_main = NO;
    for (NSString *name in files) if ([name hasSuffix:@".fixups.tsv"] || [@[@"shader_map.tsv", @"c1_full.tsv"] containsObject:name]) {
        [identity addObject:name]; [identity addObject:file_digest([dm stringByAppendingPathComponent:name])];
        if ([name isEqualToString:@"main.fixups.tsv"]) has_main = YES;
    }
#if TARGET_OS_IPHONE
    // 身份必须来自随包的模块表：缺了就无从判断旧归档是否还适用，直接停用（比错用旧归档安全）。
    // The identity must come from the bundled module table: without it there is no way to tell whether an old archive still
    // applies, so persistence is disabled (safer than using a stale archive).
    if (!has_main) { stats.disabled = 1; PCLOG("missing module identity; persistence disabled"); return; }
#else
    (void)has_main;
#endif
    NSString *key = digest([NSJSONSerialization dataWithJSONObject:identity options:0 error:nil]);
    NSString *root = override ? @(override) : [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"DmPipelineCache"];
    NSString *dir = [root stringByAppendingPathComponent:key];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
        stats.disabled = stats.write_failed = 1; PCLOG("directory unavailable: %s", error.localizedDescription.UTF8String); return;
    }
    [[NSURL fileURLWithPath:root] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    cache_file = [dir stringByAppendingPathComponent:@"pipelines.metalarc"];
    MTLBinaryArchiveDescriptor *d = [MTLBinaryArchiveDescriptor new];
    NSDictionary *attr = [NSFileManager.defaultManager attributesOfItemAtPath:cache_file error:nil];
    if (attr && [attr fileSize] <= CACHE_MAX_BYTES) d.url = [NSURL fileURLWithPath:cache_file];
    archive = [device newBinaryArchiveWithDescriptor:d error:&error];
    if (!archive && d.url) {
        // 旧文件被系统拒绝（换了 GPU / 系统 / 表）：丢弃旧内容从头建，绝不带着坏归档继续
        // The old file was rejected (different GPU / OS / tables): start a fresh archive rather than carrying a bad one
        PCLOG("archive rejected; rebuilding safely: %s", error.localizedDescription.UTF8String);
        d.url = nil; error = nil; archive = [device newBinaryArchiveWithDescriptor:d error:&error];
    } else if (archive && d.url) stats.loaded = 1;
    if (!archive) { stats.disabled = 1; PCLOG("archive unavailable: %s", error.localizedDescription.UTF8String); }
    PCLOG("identity=%s loaded=%d disabled=%d", key.UTF8String, stats.loaded, stats.disabled);
}
// 带常量特化的函数在 iOS 18 / macOS 15 之前不能设备序列化：保守地让这些管线绕过归档，语义不变、只是没有加速。
// 注意 functionConstantsDictionary 在部分系统上并不填充（本机 macOS 26 实测为空），所以这里只是「尽量绕过」；真正拦住
// 坏归档的是 add_* 的失败计数加上 FailOnBinaryArchiveMiss：查不到就返回 nil，调用方照常普通编译，绝不会拿到错管线。
// Device serialization of specialized functions is only supported from iOS 18 / macOS 15: conservatively bypass functions
// that declare constants. Semantics are unchanged, the pipeline just gets no acceleration.
// Note that functionConstantsDictionary is not populated on every OS (measured empty on this macOS 26 host), so this is
// best-effort. What actually keeps a bad archive out is add_* counting the failure plus FailOnBinaryArchiveMiss: a lookup
// that finds nothing returns nil and the caller compiles normally, so a wrong pipeline is never handed out.
static BOOL can_archive(id<MTLFunction> function) {
    if (!function) return YES;
    if (@available(iOS 18.0, macOS 15.0, *)) return YES;
    return function.functionConstantsDictionary.count == 0;
}
static void save_tick(uint64_t gen, int round);
static void schedule_save_locked(void) {
    if (save_scheduled || !archive || stats.write_failed) return;
    save_scheduled = 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        save_tick(atomic_load_explicit(&add_gen, memory_order_relaxed), 0);
    });
}
// 静默 30 秒才落盘：这段时间里又出了新管线（说明还在跑）就再等一轮，最多 10 轮（5 分钟）；进后台 / 终止另有同步 / 异步刷盘。
// 刷盘本身已不占渲染线程（见 try_* / add_* 的 trylock），这里只是不再一局里反复做。
// Save only after 30 quiet seconds: if new pipelines appeared in that window (still playing), wait another round, at most 10 rounds
// (5 minutes); entering the background / terminating still saves on its own. A save no longer occupies the render thread (see the
// trylock in try_* / add_*), this only stops repeated saves within one run.
static void save_tick(uint64_t gen, int round) {
    uint64_t now_gen = atomic_load_explicit(&add_gen, memory_order_relaxed);
    if (now_gen != gen && round < 10) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            save_tick(now_gen, round + 1);
        });
        return;
    }
    nvn_pcache_flush();
    pthread_mutex_lock(&cache_mu); save_scheduled = 0; pthread_mutex_unlock(&cache_mu);
}
id<MTLRenderPipelineState> nvn_pcache_try_render(id<MTLDevice> device, MTLRenderPipelineDescriptor *desc) {
    if (!desc) return nil;
    // 拿不到锁就当未命中（记 busy）：归档只是加速，提交线程绝不等一次编译或一次落盘
    // Failing to take the lock counts as a miss (recorded as busy): the archive is only an accelerator, so the submit thread never
    // waits behind a compile or a save
    if (pthread_mutex_trylock(&cache_mu)) { __atomic_fetch_add(&stats.busy, 1, __ATOMIC_RELAXED); return nil; }
    cache_init(device);
    if (stats.disabled) { pthread_mutex_unlock(&cache_mu); return nil; }   // 停用：不查也不计数，免得把 bypassed 灌满 | disabled: neither query nor count, so bypassed stays meaningful
    id<MTLRenderPipelineState> result = nil;
    if (archive && can_archive(desc.vertexFunction) && can_archive(desc.fragmentFunction)) {
        MTLRenderPipelineDescriptor *d = [desc copy];
        d.binaryArchives = @[archive];
        result = [device newRenderPipelineStateWithDescriptor:d options:MTLPipelineOptionFailOnBinaryArchiveMiss reflection:nil error:nil];
        if (result) stats.hits++; else stats.misses++;
    } else stats.bypassed++;
    pthread_mutex_unlock(&cache_mu);
    return result;
}
void nvn_pcache_add_render(id<MTLDevice> device, MTLRenderPipelineDescriptor *desc) {
    if (!desc) return;
    if (pthread_mutex_trylock(&cache_mu)) { __atomic_fetch_add(&stats.busy, 1, __ATOMIC_RELAXED); return; }   // 忙就不收：这条管线本轮不入档，绝不让提交线程等 | busy -> not archived this time; the submit thread never waits
    cache_init(device);
    if (stats.disabled) { pthread_mutex_unlock(&cache_mu); return; }
    if (archive && can_archive(desc.vertexFunction) && can_archive(desc.fragmentFunction)) {
        MTLRenderPipelineDescriptor *d = [desc copy];   // 归档里存的必须是不带 binaryArchives 的原始描述符 | The archive must hold the plain descriptor without binaryArchives
        d.binaryArchives = nil; NSError *error = nil;
        if ([archive addRenderPipelineFunctionsWithDescriptor:d error:&error]) { stats.added++; atomic_fetch_add_explicit(&add_gen, 1, memory_order_relaxed); schedule_save_locked(); }
        else { stats.bypassed++; if (stats.bypassed < 5) PCLOG("render archive fallback: %s", error.localizedDescription.UTF8String); }
    }
    pthread_mutex_unlock(&cache_mu);
}
id<MTLComputePipelineState> nvn_pcache_try_compute(id<MTLDevice> device, id<MTLFunction> function) {
    if (!function) return nil;
    if (pthread_mutex_trylock(&cache_mu)) { __atomic_fetch_add(&stats.busy, 1, __ATOMIC_RELAXED); return nil; }
    cache_init(device);
    if (stats.disabled) { pthread_mutex_unlock(&cache_mu); return nil; }
    id<MTLComputePipelineState> result = nil;
    if (archive && can_archive(function)) {
        MTLComputePipelineDescriptor *d = [MTLComputePipelineDescriptor new];
        d.computeFunction = function; d.binaryArchives = @[archive];
        result = [device newComputePipelineStateWithDescriptor:d options:MTLPipelineOptionFailOnBinaryArchiveMiss reflection:nil error:nil];
        if (result) stats.hits++; else stats.misses++;
    } else stats.bypassed++;
    pthread_mutex_unlock(&cache_mu);
    return result;
}
void nvn_pcache_add_compute(id<MTLDevice> device, id<MTLFunction> function) {
    if (!function) return;
    if (pthread_mutex_trylock(&cache_mu)) { __atomic_fetch_add(&stats.busy, 1, __ATOMIC_RELAXED); return; }
    cache_init(device);
    if (stats.disabled) { pthread_mutex_unlock(&cache_mu); return; }
    if (archive && can_archive(function)) {
        MTLComputePipelineDescriptor *d = [MTLComputePipelineDescriptor new];
        d.computeFunction = function; NSError *error = nil;
        if ([archive addComputePipelineFunctionsWithDescriptor:d error:&error]) { stats.added++; atomic_fetch_add_explicit(&add_gen, 1, memory_order_relaxed); schedule_save_locked(); }
        else { stats.bypassed++; if (stats.bypassed < 5) PCLOG("compute archive fallback: %s", error.localizedDescription.UTF8String); }
    }
    pthread_mutex_unlock(&cache_mu);
}
void nvn_pcache_snapshot(nvn_pcache_status *out) {
    if (!out) return;
    // 界面轮询绝不能排在编译或落盘后面：拿不到锁就返回上一次的副本
    // UI polling must never wait behind a compile or a disk save: if the lock is busy, return the previous copy
    static _Thread_local nvn_pcache_status last;
    if (!pthread_mutex_trylock(&cache_mu)) { last = stats; pthread_mutex_unlock(&cache_mu); }
    *out = last;
}
void nvn_pcache_flush(void) {
    @autoreleasepool {
        // 持锁只做「序列化」这一步（只有它碰归档对象）；fsync / 改名 / 清理都在锁外，刷盘期间新建管线不会被挡。
        // 序列化期间置 flushing：两个刷盘不会同时跑。
        // The lock is held only for serialization (the only step that touches the archive object); fsync / rename / cleanup happen
        // outside it, so pipeline creation is never blocked by a save. The flushing flag keeps two saves from overlapping.
        NSString *dir = nil, *temp = nil, *file = nil;
        uint64_t added_now = 0;
        NSError *error = nil;
        BOOL ok = NO;
        pthread_mutex_lock(&cache_mu);
        if (!archive || stats.added == stats.saved || stats.write_failed || flushing || !cache_file) { pthread_mutex_unlock(&cache_mu); return; }
        file = cache_file;
        dir = file.stringByDeletingLastPathComponent;
        temp = [dir stringByAppendingPathComponent:@"pipelines.pending"];
        struct statvfs space;
        ok = !statvfs(dir.fileSystemRepresentation, &space) && (uint64_t)space.f_bavail * space.f_frsize > CACHE_MAX_BYTES + CACHE_RESERVE_BYTES;
        if (ok) ok = [archive serializeToURL:[NSURL fileURLWithPath:temp] error:&error];
        added_now = stats.added;   // 只记序列化时已经进去的：序列化期间新收的不在这个文件里 | only what was in at serialize time: later additions are not in this file
        if (ok) flushing = 1; else stats.write_failed = 1;
        pthread_mutex_unlock(&cache_mu);
        if (!ok) { PCLOG("persistence failed; previous archive retained: %s", error ? error.localizedDescription.UTF8String : "space/size/atomic write check"); return; }
        NSDictionary *attr = [NSFileManager.defaultManager attributesOfItemAtPath:temp error:nil];
        ok = attr && [attr fileSize] > 0 && [attr fileSize] <= CACHE_MAX_BYTES;
        if (ok) { int fd = open(temp.fileSystemRepresentation, O_RDONLY); ok = fd >= 0 && fsync(fd) == 0; if (fd >= 0) close(fd); }
        if (ok) ok = rename(temp.fileSystemRepresentation, file.fileSystemRepresentation) == 0;
        if (ok) { int fd = open(dir.fileSystemRepresentation, O_RDONLY); if (fd >= 0) { fsync(fd); close(fd); } }
        pthread_mutex_lock(&cache_mu);
        if (ok) stats.saved = added_now; else stats.write_failed = 1;
        flushing = 0;
        pthread_mutex_unlock(&cache_mu);
        if (ok) {
            PCLOG("saved added=%llu hits=%llu misses=%llu bypassed=%llu busy=%llu bytes=%llu", (unsigned long long)added_now, (unsigned long long)stats.hits,
                  (unsigned long long)stats.misses, (unsigned long long)stats.bypassed, (unsigned long long)stats.busy, (unsigned long long)[attr fileSize]);
            // 只保留当前与上一份身份目录；只删我们自己那两个固定文件名，绝不递归删除未知内容
            // Keep only the current and the immediately previous identity directory; only our two fixed file names are removed,
            // never recursively deleting unknown content
            NSString *parent = dir.stringByDeletingLastPathComponent;
            NSMutableArray<NSString *> *old = [NSMutableArray array];
            NSCharacterSet *nonhex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
            for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:parent error:nil])
                if (name.length == 64 && [name rangeOfCharacterFromSet:nonhex].location == NSNotFound && ![name isEqual:dir.lastPathComponent]) [old addObject:[parent stringByAppendingPathComponent:name]];
            [old sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                NSDate *da = [[NSFileManager.defaultManager attributesOfItemAtPath:[a stringByAppendingPathComponent:@"pipelines.metalarc"] error:nil] fileModificationDate] ?: NSDate.distantPast;
                NSDate *db = [[NSFileManager.defaultManager attributesOfItemAtPath:[b stringByAppendingPathComponent:@"pipelines.metalarc"] error:nil] fileModificationDate] ?: NSDate.distantPast;
                return [db compare:da];
            }];
            for (NSUInteger i = 1; i < old.count; ++i) {
                for (NSString *name in @[@"pipelines.metalarc", @"pipelines.pending"]) [NSFileManager.defaultManager removeItemAtPath:[old[i] stringByAppendingPathComponent:name] error:nil];
                rmdir(old[i].fileSystemRepresentation);
            }
        } else PCLOG("persistence failed; previous archive retained: %s", error ? error.localizedDescription.UTF8String : "space/size/atomic write check");
        [NSFileManager.defaultManager removeItemAtPath:temp error:nil];
    }
}
void nvn_pcache_flush_async(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ nvn_pcache_flush(); });
}
void nvn_pcache_log(const char *tag) {
    nvn_pcache_status s; nvn_pcache_snapshot(&s);
    PCLOG("%s: hits=%llu misses=%llu added=%llu saved=%llu bypassed=%llu loaded=%d write_failed=%d disabled=%d", tag ? tag : "-",
          s.hits, s.misses, s.added, s.saved, s.bypassed, s.loaded, s.write_failed, s.disabled);
}
