// 同槽 last-write-wins 合并的行为验证（录制层，不依赖 Metal 设备）：
//  1) 同一槽相邻两次绑定：只留一条记录，值 = 后写的那次（回放只看最后值，等价）；
//  2) 中间夹一条屏障记录（屏障 / 绘制 / 拷贝）：两次绑定都保留，不得跨屏障合并；
//  3) 不同槽（不同 stage / index / 范围）永不合并；
//  4) 换段（命令内存滚动）后旧段的槽作废，不得跨段合并。
// 期望值手算：直接走命令内存里的记录序列，不调被测实现的统计。
// Behavioural verification of same-slot last-write-wins merging (recording layer, no Metal device needed):
//  1) two adjacent binds to the same slot: one record remains, holding the later value (replay only sees the last value, equivalent);
//  2) a barrier record in between (barrier / draw / copy): both binds survive, never merged across a barrier;
//  3) different slots (different stage / index / range) never merge;
//  4) after a segment rollover the old segment's slots are dead: no merge across segments.
// Expected values are hand-calculated by walking the record sequence in command memory, not by calling the implementation's counters.
#include "../nvn/hle_nvn.c"
int dm_guest_heap_stat(unsigned long long *t, unsigned long long *f, unsigned long long *m) { *t = *f = *m = 0; return 0; }   // 单测无客体堆 | no guest heap in this fixture
uint64_t g_t0_ns;
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
void crash_install(void);
uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec; }
static int g_fail, g_n;
#define EXPECT(name, want, got) do { long long w_ = (long long)(want), g_ = (long long)(got); g_n++; \
    printf("%-46s 期望 %-8lld → 真结果 %-8lld %s\n", name, w_, g_, w_ == g_ ? "✓" : "✗"); if (w_ != g_) g_fail++; } while (0)

// 记录序列扫描：按 op_hdr.size 走，数某个操作码的记录条数 | Walk the record sequence by op_hdr.size, counting records of one opcode
static int count_op(const uint8_t *begin, const uint8_t *end, uint32_t op, p_bind_buf *last) {
    int n = 0;
    for (const uint8_t *p = begin; p + sizeof(op_hdr) <= end;) {
        const op_hdr *h = (const op_hdr *)p;
        if (!h->size) break;
        if (h->op == op) { n++; if (last) *last = *(const p_bind_buf *)(p + 8); }
        p += h->size;
    }
    return n;
}
static uint8_t g_mem[2][4096];
static int g_seg;
static void mem_cb(NVNcommandBuffer *c, NVNcommandBufferMemoryEvent ev, size_t minsz, void *data) {
    (void)c; (void)data;
    if (ev != NVN_COMMAND_BUFFER_MEMORY_EVENT_OUT_OF_COMMAND_MEMORY) return;
    if (g_seg >= 2) die("测试命令内存用完");
    cmd_t *o = CB(c);
    o->cur = g_mem[g_seg]; o->end = g_mem[g_seg] + sizeof g_mem[0]; g_seg++;
    lww_barrier();   // 与生产 cmd_new_segment 一致：换段即作废待合并槽 | same as production cmd_new_segment: a rollover drops pending slots
}
int main(void) {
    crash_install();

    // 0) 默认安全模式（DM_NVN_LWW 缺省为 0）：不进行任何同槽合并，每条绑定皆保留（保障多线程录制安全与无丢着色器）
    // Default safe mode (DM_NVN_LWW default 0): no same-slot merging, every bind preserved
    {
        dm_nvn_lww_set(0);
        cmd_t o_safe; memset(&o_safe, 0, sizeof o_safe);
        o_safe.cb = mem_cb; o_safe.cur = g_mem[0]; o_safe.end = g_mem[0] + sizeof g_mem[0];
        NVNcommandBuffer *c_safe = (NVNcommandBuffer *)&o_safe;
        o_safe.recording = 1;
        uint8_t *p_safe = cmd_alloc(&o_safe, 8); put_hdr(p_safe, OP_BEGIN, 8); o_safe.begin = p_safe;
        h_nvnCommandBufferBindUniformBuffer(c_safe, NVN_SHADER_STAGE_FRAGMENT, 0, (NVNbufferAddress)0x1000, 256);
        h_nvnCommandBufferBindUniformBuffer(c_safe, NVN_SHADER_STAGE_FRAGMENT, 0, (NVNbufferAddress)0x2000, 512);
        EXPECT("默认安全模式下相邻绑定均保留不合并", 2, count_op(o_safe.begin, o_safe.end, OP_BIND_UBO, NULL));
    }

    // 显式开启 LWW 实验项，验证 LWW 逻辑与阶段隔离
    dm_nvn_lww_set(1);
    memset(g_mem, 0, sizeof g_mem); g_seg = 0;
    cmd_t o; memset(&o, 0, sizeof o);
    o.cb = mem_cb; o.cur = g_mem[0]; o.end = g_mem[0] + sizeof g_mem[0];
    NVNcommandBuffer *c = (NVNcommandBuffer *)&o;
    o.recording = 1;
    uint8_t *p = cmd_alloc(&o, 8); put_hdr(p, OP_BEGIN, 8); o.begin = p;

    // 1) 相邻两次同槽绑定 → 只留一条，值 = 后一次 | Two adjacent binds to one slot -> one record, the later value
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 0, (NVNbufferAddress)0x1000, 256);
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 0, (NVNbufferAddress)0x2000, 512);
    p_bind_buf last = {0};
    EXPECT("相邻同槽只留一条记录", 1, count_op(o.begin, o.end, OP_BIND_UBO, &last));
    EXPECT("留下的值是后写的那次地址", 0x2000, (long long)last.addr);
    EXPECT("留下的值是后写的那次长度", 512, (long long)last.size);

    // 2) 中间夹屏障 → 两条都留 | A barrier in between -> both records survive
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 1, (NVNbufferAddress)0x3000, 256);
    h_nvnCommandBufferBarrier(c, 0);
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 1, (NVNbufferAddress)0x4000, 256);
    EXPECT("屏障两侧同槽不合并", 3, count_op(o.begin, o.end, OP_BIND_UBO, NULL));

    // 3) 不同槽不合并 | Different slots never merge
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_VERTEX, 2, (NVNbufferAddress)0x5000, 256);
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 2, (NVNbufferAddress)0x6000, 256);
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 3, (NVNbufferAddress)0x7000, 256);
    EXPECT("不同槽各自成记录", 6, count_op(o.begin, o.end, OP_BIND_UBO, NULL));

    // 4) 绘制是屏障：绘制后的同槽绑定不得与前一条合并 | A draw is a barrier: a bind after it must not merge with the one before
    h_nvnCommandBufferBindStorageBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 0, (NVNbufferAddress)0x8000, 64);
    h_nvnCommandBufferDrawArrays(c, NVN_DRAW_PRIMITIVE_TRIANGLES, 0, 3);
    h_nvnCommandBufferBindStorageBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 0, (NVNbufferAddress)0x9000, 64);
    EXPECT("绘制两侧同槽不合并", 2, count_op(o.begin, o.end, OP_BIND_SSBO, NULL));

    // 5) 换段后旧段槽作废：新段里的同槽绑定不得合并到旧段 | After a rollover the old slot is dead: a same-slot bind in the new segment must not merge into it
    uint8_t *old_begin = o.cur; (void)old_begin;
    mem_cb(c, NVN_COMMAND_BUFFER_MEMORY_EVENT_OUT_OF_COMMAND_MEMORY, 4096, NULL);   // 切到第二段 | switch to the second segment
    uint8_t *seg2 = o.cur;
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 9, (NVNbufferAddress)0xA000, 256);
    h_nvnCommandBufferBindUniformBuffer(c, NVN_SHADER_STAGE_FRAGMENT, 9, (NVNbufferAddress)0xB000, 256);
    p_bind_buf l2 = {0};
    EXPECT("新段内相邻同槽仍可合并", 1, count_op(seg2, o.cur, OP_BIND_UBO, &l2));
    EXPECT("新段合并后值是后一次", 0xB000, (long long)l2.addr);
    uint64_t merged = 0; dm_nvn_lww_stats(&merged, NULL);
    EXPECT("累计合并条数（1 + 1）", 2, (long long)merged);

    // 6) 程序绑定阶段隔离：计算阶段程序与渲染阶段程序不得合并（防止丢失着色器导致 GPU Hang）
    NVNprogram p1, p2; memset(&p1, 0, sizeof p1); memset(&p2, 0, sizeof p2);
    h_nvnCommandBufferBindProgram(c, &p1, NVN_SHADER_STAGE_COMPUTE_BIT);
    h_nvnCommandBufferBindProgram(c, &p2, NVN_SHADER_STAGE_VERTEX_BIT | NVN_SHADER_STAGE_FRAGMENT_BIT);
    int prog_ops = 0;
    for (const uint8_t *q = seg2; q + sizeof(op_hdr) <= o.cur;) {
        const op_hdr *h = (const op_hdr *)q;
        if (!h->size) break;
        if (h->op == OP_BIND_PROGRAM) prog_ops++;
        q += h->size;
    }
    EXPECT("计算程序与渲染程序互不合并（均保留）", 2, prog_ops);

    printf("LWW_RECORD checks=%d failed=%d\n", g_n, g_fail);
    return g_fail ? 1 : 0;
}
