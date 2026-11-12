// ReadFile 写前解保护（dm_guest_write_prepare）与内核 EFAULT 的单测：直接包含 hle_fs.c，pread 换成可编排的假实现。
// 现场：图形层把贴图池的页设成只读做脏页跟踪；宿主读盘把文件读进贴图存储前先解保护。
//   若解保护之后、pread 真正落到内核之前那一页又被重新设成只读（后台上传完成后重新保护），pread 返回 EFAULT —— 内核往只读页写不会走缺页处理，
//   旧实现直接把失败回给游戏（贴图加载失败 / 内容为空）。现在对未读完的部分重新解保护并续读。
// 期望值不靠被测实现算：
//   ① 首次 EFAULT、随后成功 → ReadFile 成功、字节数等于请求长度、内容正确、解保护共 2 次（开读一次 + 续读一次）；
//   ② 一直 EFAULT → 失败，解保护 9 次（1 + 最多 8 次重试）后放弃，不死循环；
//   ③ 先短读 100 字节、再 EFAULT → 续读的解保护只覆盖剩下的 sz-100 字节，最终内容完整。
// Unit test for the pre-write unprotect (dm_guest_write_prepare) and the kernel EFAULT in ReadFile: includes hle_fs.c directly, with pread replaced by a scriptable fake.
// Scene: the graphics layer sets texture-pool pages read-only for dirty tracking; the host unprotects before reading a file into texture storage.
//   If that page is made read-only again between the unprotect and the pread reaching the kernel (re-protected after a background upload completes), pread returns EFAULT -- a kernel write to a read-only page does not go through the page-fault handler,
//   and the old implementation returned that failure to the game (texture load fails / content empty). Now the unread remainder is unprotected again and the read continues.
// Expected values are not computed by the implementation under test:
//   (1) first EFAULT then success -> ReadFile succeeds, byte count equals the request, content correct, 2 unprotects (one at the start, one for the continuation);
//   (2) EFAULT forever -> failure after 9 unprotects (1 + at most 8 retries), no infinite loop;
//   (3) short read of 100 bytes, then EFAULT -> the continuation's unprotect covers only the remaining sz-100 bytes and the final content is complete.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
static ssize_t fake_pread(int fd, void *buf, size_t n, off_t off);
#define pread fake_pread
#include "../hle_fs.c"
#undef pread
ssize_t pread(int, void *, size_t, off_t);

struct dm_flags g_flag; uint64_t g_t0_ns; uint64_t now_ns(void) { return 0; }
void dm_prof_add(int id, uint64_t ns, uint64_t b) { (void)id; (void)ns; (void)b; }

static int g_prep_calls, g_pread_calls, g_mode;
static size_t g_last_prep_len;
static void *g_last_prep_addr;
void dm_guest_write_prepare(void *a, size_t n) { g_prep_calls++; g_last_prep_len = n; g_last_prep_addr = a; }

// mode 0：照常读；1：第一次 EFAULT；2：一直 EFAULT；3：第一次只给 100 字节，第二次 EFAULT
// mode 0: read normally; 1: EFAULT on the first call; 2: EFAULT forever; 3: first call returns 100 bytes, second EFAULT
static ssize_t fake_pread(int fd, void *buf, size_t n, off_t off) {
    g_pread_calls++;
    if (g_mode == 1 && g_pread_calls == 1) { errno = EFAULT; return -1; }
    if (g_mode == 2) { errno = EFAULT; return -1; }
    if (g_mode == 3) {
        if (g_pread_calls == 1 && n > 100) n = 100;
        else if (g_pread_calls == 2) { errno = EFAULT; return -1; }
    }
    return pread(fd, buf, n, off);
}

static int fails, checks;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("  ✗ "); } else printf("  ✓ "); printf(__VA_ARGS__); printf("\n"); } while (0)

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);   // 卡住时也能看到进度；必须在任何输出之前设置 | progress stays visible even if a case hangs; must be set before any output
    enum { N = 4096 };
    char path[] = "/tmp/dm-efault.XXXXXX";
    int tfd = mkstemp(path); if (tfd < 0) { perror("mkstemp"); return 2; }
    static uint8_t want[N]; for (int i = 0; i < N; i++) want[i] = (uint8_t)(i * 37 + 11);
    if (write(tfd, want, N) != N) { perror("write"); return 2; }
    int fd = open(path, O_RDONLY); if (fd < 0) { perror("open"); return 2; }
    static uint8_t got[N + 64];

    printf("① 首次 EFAULT、随后成功\n");
    g_mode = 1; g_prep_calls = g_pread_calls = 0;
    memset(got, 0xAA, sizeof got); size_t out = 0;
    Result r = h_fs_ReadFile(&out, (uint64_t)fd, 0, got, N);
    CHECK(r == RES_OK, "ReadFile 成功（真结果 %#x）", r);
    CHECK(out == N, "字节数 = 请求的 %d（真结果 %zu）", N, out);
    CHECK(!memcmp(got, want, N), "内容逐字节等于文件");
    CHECK(g_prep_calls == 2, "解保护 2 次（开读 + 续读；真结果 %d）", g_prep_calls);

    printf("② 一直 EFAULT\n");
    g_mode = 2; g_prep_calls = g_pread_calls = 0; out = 12345;
    r = h_fs_ReadFile(&out, (uint64_t)fd, 0, got, N);
    CHECK(r == RES_FAIL, "ReadFile 返回失败（真结果 %#x）", r);
    CHECK(g_prep_calls == 9, "解保护 9 次（1 + 最多 8 次重试）后放弃（真结果 %d）", g_prep_calls);
    CHECK(g_pread_calls == 9, "pread 试 9 次后放弃，不死循环（真结果 %d）", g_pread_calls);
    CHECK(out == 12345, "失败时不动 *out（真结果 %zu）", out);

    printf("③ 先短读 100 字节、再 EFAULT\n");
    g_mode = 3; g_prep_calls = g_pread_calls = 0;
    memset(got, 0xAA, sizeof got); out = 0;
    r = h_fs_ReadFile(&out, (uint64_t)fd, 0, got, N);
    CHECK(r == RES_OK, "ReadFile 成功（真结果 %#x）", r);
    CHECK(out == N, "字节数 = %d（真结果 %zu）", N, out);
    CHECK(!memcmp(got, want, N), "内容逐字节等于文件（含短读的前 100 字节）");
    CHECK(g_prep_calls == 2, "解保护 2 次（真结果 %d）", g_prep_calls);
    CHECK(g_last_prep_len == N - 100, "续读的解保护只覆盖剩下的 %d 字节（真结果 %zu）", N - 100, g_last_prep_len);
    CHECK(g_last_prep_addr == got + 100, "续读的解保护从已读到的位置开始");

    close(fd); unlink(path);
    printf("== %d 项，失败 %d ==\n", checks, fails);
    return fails != 0;
}
