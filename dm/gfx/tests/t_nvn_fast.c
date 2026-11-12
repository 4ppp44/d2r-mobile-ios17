// NVN 空设备单测：照游戏的用法从 nvnBootstrapLoader 取址，一路走到出图；期望值全部手算，不调被测实现。
// 编译运行见 dm/gfx/tests/Makefile（make -C dm/gfx/tests）。
// NVN null device unit tests: look up addresses from nvnBootstrapLoader the way the game does and go all the way to present; all expected values are hand-calculated, without calling the implementation under test.
// For build and run see dm/gfx/tests/Makefile (make -C dm/gfx/tests).
#include "../nvn/hle_nvn.c"
uint64_t g_t0_ns;   // 宿主 main.c 的进程起点（hle_nvn 逐帧 @t_s 用），单测替身 | process start time from host main.c (used by hle_nvn's per-frame @t_s); unit test stub
#include "../tex/nvn_deswizzle.h"
#include <time.h>
void *front_metal_layer(void) { return NULL; }   // 单测无窗口：出图只计数 | no window in unit tests: present only counts
module_t *module_of(const void *p) { (void)p; return NULL; }   // 单测无客体模块 | no guest modules in unit tests
module_t g_mod[MAX_MOD]; int g_nmod;                            // crash.c 依赖的宿主符号 | host symbols that crash.c depends on
void svc_thread_dump(void) {}
// 无客体堆的单测替身，输出未读到；不替代真实设备验证。
// No guest heap in this fixture; report unavailable, not device proof.
int dm_guest_heap_stat(unsigned long long *t,unsigned long long *f,unsigned long long *m){*t=*f=*m=0;return 0;}
void crash_install(void);
void nvn_present_config(int hz, int display_mode);
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec; }


#include <assert.h>
int main(int argc,char**argv){
 const char *mode=argc>1?argv[1]:"fast";unsetenv("DM_NVN_COUNT");unsetenv("DM_NVN_TSV");unsetenv("DM_NVN_TSV_CALLS");
 int counted=!strcmp(mode,"count")||!strcmp(mode,"tsv");
 if(!strcmp(mode,"count"))setenv("DM_NVN_COUNT","1",1);
 if(!strcmp(mode,"tsv")||!strcmp(mode,"timing"))setenv("DM_NVN_TSV","/tmp/nvn-fast-test-unused.tsv",1);
 if(!strcmp(mode,"timing"))setenv("DM_NVN_TSV_CALLS","0",1);
 const char *name="nvnDeviceBuilderSetDefaults";void *fn=nvn_lookup(name);unsigned i=0;while(strcmp(nvn_names[i],name))i++;
 assert(fn==(counted?nvn_thunk[i]:nvn_thunk_fast[i]));
 NVNdeviceBuilder b;memset(&b,0x55,sizeof b);((NVNT_nvnDeviceBuilderSetDefaults)fn)(&b);assert(nvn_slot[i].cnt==(counted?1:0));
 NVNdeviceBuilder c;memset(&c,0x55,sizeof c);((NVNT_nvnDeviceBuilderSetDefaults)nvn_thunk[i])(&c);assert(!memcmp(&b,&c,sizeof b));assert(nvn_slot[i].cnt==(counted?2:1));
 unsigned u=0;while(u<NVN_NFUNC&&nvn_slot[u].fn!=(void*)nvn_unimpl_entry)u++;assert(u<NVN_NFUNC);
 assert(((uint64_t(*)(void))nvn_thunk_fast[u])()==0);assert(nvn_slot[u].cnt==0);
 assert(((uint64_t(*)(void))nvn_thunk[u])()==0);assert(nvn_slot[u].cnt==1);
 printf("NVN_FAST mode=%s entries=523 PASS\n",mode);return 0;
}
