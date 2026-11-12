// 设备本地 Metal 二进制归档（MTLBinaryArchive）：把已编好的管线二进制存到磁盘，下次启动直接命中，省掉冷启动的整段编译。
// 只用传统 Metal 3 接口（iOS 17 / A16 可用）；不涉及 Metal 4 参数表，也不序列化任何游戏状态。
// Device-local Metal binary archive (MTLBinaryArchive): stores compiled pipeline binaries on disk so a later launch hits them
// instead of paying the whole cold-start compile again. Traditional Metal 3 API only (available on iOS 17 / A16); no Metal 4
// argument tables and no game state are serialized.
#pragma once
#include <stdint.h>
// 命中 / 未命中 / 不适用 / 新增 / 已落盘 / 因归档忙而跳过，以及加载成功、写盘失败、整体停用三种状态
// hits / misses / bypassed / added / saved / busy-skips, plus loaded, write_failed and disabled states
typedef struct {
    uint64_t hits, misses, bypassed, added, saved, busy;
    int loaded, write_failed, disabled;
} nvn_pcache_status;
void nvn_pcache_snapshot(nvn_pcache_status *out);   // 任意线程可调；不等待编译或落盘 | Callable from any thread; never waits behind a compile or a save
void nvn_pcache_flush(void);                        // 只在工作线程上调：临时文件 + 原子改名，保留上一份可用文件 | Worker thread only: temp file + atomic rename keeps the last good file
void nvn_pcache_flush_async(void);
void nvn_pcache_log(const char *tag);               // 打一行累计计数（启动 / 进局等低频位置） | Log one line of cumulative counters (low-frequency sites such as launch / entering a run)
#ifdef __OBJC__
#import <Metal/Metal.h>
// 先在归档里找；返回 nil 表示没命中、该管线不适用、或归档正忙（调用方照常普通编译，编译成功后调 add_* 收进归档）。
// 不修改传入的描述符：命中查询用副本。
// 三条路径都不阻塞：拿不到归档锁就当未命中 / 不收录，绝不占着提交线程等一次落盘（归档只是加速）。
// Look in the archive first; nil means a miss, an ineligible pipeline, or the archive is busy (the caller compiles normally and then calls add_*).
// The descriptor passed in is never modified: the hit query uses a copy.
// None of the three paths blocks: failing to take the archive lock counts as a miss / skips archiving, so the submit thread never
// waits behind a save (the archive is only an accelerator).
id<MTLRenderPipelineState> nvn_pcache_try_render(id<MTLDevice> device, MTLRenderPipelineDescriptor *desc);
id<MTLComputePipelineState> nvn_pcache_try_compute(id<MTLDevice> device, id<MTLFunction> function);
void nvn_pcache_add_render(id<MTLDevice> device, MTLRenderPipelineDescriptor *desc);
void nvn_pcache_add_compute(id<MTLDevice> device, id<MTLFunction> function);
#endif
