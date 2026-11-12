#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include "dm.h"
#include "../dm_yield_policy.h"
uint32_t svc_thread_main_init(void);
int svc_thread(int num, uint64_t *regs);
void dm_main_yield_stats_v2(uint64_t *,uint64_t *,uint64_t *);
int main(void) {
 assert(dm_yield_sleep_ns(8)==0);assert(dm_yield_sleep_ns(9)==50000);
 assert(dm_yield_sleep_ns(33)==100000);assert(dm_yield_sleep_ns(97)==200000);
 assert(dm_yield_sleep_ns(UINT32_MAX)==200000);
 assert(svc_thread_main_init()==0x1001);
 uint64_t regs[32]={0},n,ns,bo;
 for(int i=0;i<8;i++){regs[0]=0;svc_thread(0x0B,regs);}
 dm_main_yield_stats_v2(&n,&ns,&bo);assert(n==8 && bo==0);
 // A persistent poll stays backed off beyond 96 rather than returning to busy yield.
 for(int i=0;i<120;i++){regs[0]=0;svc_thread(0x0B,regs);}
 dm_main_yield_stats_v2(&n,&ns,&bo);assert(n==128 && bo==120);
 usleep(1500);regs[0]=0;svc_thread(0x0B,regs);
 dm_main_yield_stats_v2(&n,&ns,&bo);assert(n==129 && bo==120);
 puts("MAIN_YIELD bounded_backoff/reset PASS");return 0;
}
