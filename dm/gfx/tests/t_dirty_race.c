// 脏页跟踪「设只读」与「写前解保护」的次序竞态。
// 现场：线程甲 nvn_dirty_protect 已把页的状态记成「受保护」、攒批的 mprotect 还没落地；线程乙这时来 prep_write（宿主往客体内存写之前的解保护，
// 例如读盘把文件读进贴图存储）。旧实现：乙把状态改回「无」，随后甲的 mprotect 落地 ⇒ 页只读而状态「无」——
//   宿主再往里读文件：prep_write 看状态「无」跳过，系统调用不走缺页处理，直接 EFAULT；游戏线程直接写：缺页处理只回「重执行」，永远空转。
// 造法：把 nvn_dirty.c 里的 mprotect 换成这里的 t_mprotect——甲设只读的那一次调用落地之前，先放乙进来并等 100 毫秒，次序是确定的。
// 期望值不靠被测实现：乙的 prep_write 返回之后，这一页必须真的可写（往里 read 16 字节得 16；直接写一个字节不卡、读回是写进去的值），
// 且这次写要被记成脏（nvn_dirty_since 对设只读之前取的戳返回 1）。
// Ordering race between "set read-only" and "unprotect before write" in dirty-page tracking.
// Scene: thread A, in nvn_dirty_protect, has already recorded the page state as "protected" while the batched mprotect has not landed yet; thread B now arrives with prep_write (the unprotect done before the host writes into guest memory,
// for example a disk read putting a file into texture storage). Old implementation: B sets the state back to "none", then A's mprotect lands => the page is read-only while its state is "none" --
//   when the host reads a file into it again: prep_write sees state "none" and skips, the system call does not go through the page-fault handler and fails with EFAULT; when the game thread writes directly: the page-fault handler only returns "re-execute" and spins forever.
// How it is staged: the mprotect in nvn_dirty.c is replaced by t_mprotect here -- before the call with which A sets read-only lands, B is let in and given 100 ms, so the order is deterministic.
// Expected values do not depend on the implementation under test: after B's prep_write returns, this page must really be writable (reading 16 bytes into it gives 16; writing one byte directly does not hang and reads back as written),
// and this write must be recorded as dirty (nvn_dirty_since returns 1 for a stamp taken before the page was set read-only).
#include <stdatomic.h>
static void t_before_store(const volatile void *object);
// Observe the clock increment before its value reaches the page generation, at the real publication seam in both unprotect paths.
#undef atomic_store
#define atomic_store(object, desired) do { \
    __auto_type object_ = (object); \
    __auto_type desired_ = (desired); \
    t_before_store(object_); \
    __c11_atomic_store(object_, desired_, __ATOMIC_SEQ_CST); \
} while (0)
#define mprotect t_mprotect
#include "../nvn/nvn_dirty.c"
#undef mprotect
int mprotect(void *, size_t, int);
#include <fcntl.h>
#include <errno.h>

module_t g_mod[MAX_MOD];
int g_nmod;
module_t *module_of(const void *p) { (void)p; return NULL; }
void crash_install(void);

static int g_fail;
#define EXPECT(name, want, got) do { \
    long long want_ = (long long)(want), got_ = (long long)(got); \
    printf("%-58s 期望 %-4lld → 真结果 %-4lld %s\n", name, want_, got_, want_ == got_ ? "✓" : "✗"); \
    if (want_ != got_) g_fail++; \
} while (0)

static uint8_t *g_page; static _Atomic int g_armed, g_go, g_b_done;
static void *thread_b(void *arg) { (void)arg; while (!atomic_load(&g_go)) usleep(200); prep_write(g_page, 16); atomic_store(&g_b_done, 1); return NULL; }
int t_mprotect(void *a, size_t n, int prot) {
    if (prot == PROT_READ && atomic_exchange(&g_armed, 0)) { atomic_store(&g_go, 1); usleep(100000); }   // 甲的 mprotect 落地前：放乙进来，等它跑到头或卡在等待上 | Before A's mprotect lands: let B in and wait until it runs to the end or gets stuck waiting
    return mprotect(a, n, prot);
}
static int g_publish_armed, g_observed_clean;
static uint8_t *g_publish_page;
static const volatile void *g_publish_gen;
static size_t g_publish_len;
static uint64_t g_publish_stamp, g_observed_now;
static void t_before_store(const volatile void *object) {
    if (!g_publish_armed || object != g_publish_gen) return;
    g_publish_armed = 0;
    g_observed_now = nvn_dirty_now();
    g_observed_clean = !nvn_dirty_since(g_publish_page, g_publish_len, g_publish_stamp);
}

// 另一线程正在解保护的页（已 mprotect 成可写并写入新代号，状态仍为 BUSY）必须被 nvn_dirty_protect 等到解完并重新保护：
// 若跳过，该页保持可写且其代号被调用方的戳覆盖，后续写入永不缺页而导致贴图常旧（MacNativeGames a166602，字形缓存缺字）。线程丙延迟 50 毫秒走完解保护的最后一步
// A page another thread is unprotecting (its mprotect to writable done and the new generation stored, the state still BUSY) must be waited out by nvn_dirty_protect and
// protected again: skipped, it stayed writable with a generation the caller's stamp covers, and later writes to it were never seen (MacNativeGames a166602, missing letters
// in a glyph cache). Thread C plays the last step of that unprotect 50 ms late
static _Atomic uint8_t *g_c_state;
static void *thread_c(void *arg) { (void)arg; usleep(50000); atomic_store(g_c_state, PG_NONE); return NULL; }
static void busy_protect(size_t pg) {
    uint8_t *page = mmap(NULL, pg, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED) { perror("mmap"); g_fail++; return; }
    nvn_dirty_add_range(page, pg);
    range_t *r = find((uintptr_t)page); uintptr_t i = r ? ((uintptr_t)page - r->base) >> g_shift : 0;
    nvn_dirty_protect(page, pg);
    uint8_t st = PG_PROT;
    if (!r || !atomic_compare_exchange_strong(&r->state[i], &st, PG_BUSY)) { printf("busy page: not protected\n"); g_fail++; return; }
    mprotect(page, pg, PROT_READ | PROT_WRITE);   // unprotect_page 在写入代号前做的事情 | what unprotect_page does before it stores the generation
    atomic_store(&r->gen[i], atomic_fetch_add(&g_now, 1) + 1);
    g_c_state = &r->state[i];
    pthread_t tc; pthread_create(&tc, NULL, thread_c, NULL);
    uint64_t stamp = nvn_dirty_now();   // 上传者先取戳再设保护 | an uploader's stamp, then its protect
    nvn_dirty_protect(page, pg);
    pthread_join(tc, NULL);
    EXPECT("protect waits out a page being unprotected (state PROT)", PG_PROT, atomic_load(&r->state[i]));
    EXPECT("no write after the stamp yet: clean", 0, nvn_dirty_since(page, 16, stamp));
    page[0] = 7;
    EXPECT("a later write to that page is seen", 1, nvn_dirty_since(page, 16, stamp));
    nvn_dirty_remove_range(page); munmap(page, pg);
}
// 为何上传必须在 nvn_dirty_protect 之前取戳：在保护期间或读取期间发生缺页的写入获得大于先前戳的代号，并使页面保持可写；
// 保护后取戳则会覆盖该代号，导致该次及后续写入被遗漏（第二项为旧次序，预期遗漏）
// Why the uploads take their stamp before nvn_dirty_protect: a write that faults while the pages are protected or read gets a generation above a stamp taken before and
// leaves its page writable; a stamp taken after covers it, so that write and every later one are missed (the second check is the old order, expected to miss)
static void stamp_order(size_t pg) {
    uint8_t *page = mmap(NULL, pg, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED) { perror("mmap"); g_fail++; return; }
    nvn_dirty_add_range(page, pg);
    uint64_t before = nvn_dirty_now();
    nvn_dirty_protect(page, pg);
    page[0] = 1;   // 上传期间缺页 | faults during the upload
    uint64_t after = nvn_dirty_now();
    page[0] = 2;   // 读取后写入：无缺页，页面可写 | after the read: no fault, the page is writable
    EXPECT("stamp before protect: the writes are seen", 1, nvn_dirty_since(page, 16, before));
    EXPECT("stamp after protect (the old order): the writes are missed", 0, nvn_dirty_since(page, 16, after));
    nvn_dirty_remove_range(page); munmap(page, pg);
}

// 查询可能在页代号写入前读到新时钟并缓存「干净」结果。走完任一解保护路径都必须使该缓存结果失效。
// A lookup can see the new clock before the page generation is stored and cache a clean result. Completing either unprotect path must invalidate that cached clock.
static void generation_publish(size_t pg, int batch) {
    size_t len = batch ? 2 * pg : pg;
    uint8_t *page = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page == MAP_FAILED) { perror("mmap"); g_fail++; return; }
    nvn_dirty_add_range(page, len);
    g_publish_page = page + len - pg; g_publish_len = pg; g_publish_stamp = nvn_dirty_now();
    range_t *r = find((uintptr_t)page);
    g_publish_gen = &r->gen[((uintptr_t)g_publish_page - r->base) >> g_shift];
    nvn_dirty_protect(page, len);
    g_observed_clean = 0; g_publish_armed = 1;
    if (batch) prep_write(page, len); else on_fault(page, 1, NULL);
    page[0] = 3;
    if (batch) page[pg] = 4;
    printf("generation publication (%s):\n", batch ? "host pre-write, batched pages" : "page fault");
    EXPECT("observer ran before the generation was stored", 1, g_observed_clean);
    EXPECT("publication invalidates the observer's cached clock", 1, nvn_dirty_now() != g_observed_now);
    EXPECT("lookup using the cached clock detects the write", 0,
           nvn_dirty_now() == g_observed_now || !nvn_dirty_since(g_publish_page, pg, g_publish_stamp));
    nvn_dirty_remove_range(page); munmap(page, len);
}

int main(void) {
    crash_install();
    size_t pg = (size_t)getpagesize();
    g_page = mmap(NULL, 2 * pg, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (g_page == MAP_FAILED) { perror("mmap"); return 2; }
    nvn_dirty_add_range(g_page, 2 * pg);
    uint64_t stamp = nvn_dirty_now();
    pthread_t tb; pthread_create(&tb, NULL, thread_b, NULL);
    atomic_store(&g_armed, 1);
    nvn_dirty_protect(g_page, 2 * pg);                       // 甲：置状态 → （乙插进来）→ mprotect 落地 | A: set the state -> (B cuts in) -> mprotect lands
    for (int i = 0; i < 2000 && !atomic_load(&g_b_done); i++) usleep(1000);
    EXPECT("乙的写前解保护在 2 秒内返回", 1, atomic_load(&g_b_done));
    if (!atomic_load(&g_b_done)) { printf("t_dirty_race：乙没返回，后面的项不测\n"); return 1; }
    pthread_join(tb, NULL);
    int fd = open("/dev/zero", O_RDONLY); g_page[pg] = 0;     // 第二页没人解过保护，这一写走缺页处理（对照：正常路径是通的） | Nobody has unprotected the second page, so this write goes through the page-fault handler (control: the normal path works)
    ssize_t r = read(fd, g_page, 16);                        // 乙接下来要做的那次宿主写：系统调用直接写进页里 | The host write that B is about to make: a system call writing straight into the page
    EXPECT("乙解完保护后往这页读文件：读到的字节数 = 请求的 16", 16, r);
    if (r == 16) { ((volatile uint8_t *)g_page)[1] = 0x5a; EXPECT("直接写这页不卡、读回是写进去的值", 0x5a, g_page[1]); }
    else { printf("  （read 失败 errno=%d；页只读而状态为「无」，直接写会在缺页处理里空转，这一项不执行）\n", errno); g_fail++; }
    EXPECT("这次写被记成脏（对设只读前的戳）", 1, nvn_dirty_since(g_page, 16, stamp));
    close(fd);
    busy_protect(pg);
    stamp_order(pg);
    generation_publish(pg, 0);
    generation_publish(pg, 1);
    printf("t_dirty_race：%s\n", g_fail ? "不通" : "全通"); return g_fail != 0;
}
