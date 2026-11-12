// Deterministic production-waiter regression. No device timing claim.
#include <pthread.h>
#include <time.h>
#include <stdint.h>
#include <errno.h>
static uint64_t fake_ns=1000000000ull, tick_period=21000000, next_tick=1021000000ull;
static int stopped;
static int fake_clock(clockid_t c,struct timespec *ts){(void)c;ts->tv_sec=fake_ns/1000000000ull;ts->tv_nsec=fake_ns%1000000000ull;return 0;}
static int fake_wait(pthread_cond_t *,pthread_mutex_t *,const struct timespec *);
static int fake_relative_wait(pthread_cond_t *,pthread_mutex_t *,const struct timespec *);
#define clock_gettime fake_clock
#define pthread_cond_timedwait fake_wait
#define pthread_cond_timedwait_relative_np fake_relative_wait
#include "../nvn/nvn_mtl.m"
#undef clock_gettime
#undef pthread_cond_timedwait
#undef pthread_cond_timedwait_relative_np
void *front_metal_layer(void){return NULL;}module_t *module_of(const void*p){(void)p;return NULL;}
module_t g_mod[MAX_MOD];int g_nmod;void svc_thread_dump(void){}uint64_t now_ns(void){return fake_ns;}
static int fake_wait(pthread_cond_t*c,pthread_mutex_t*m,const struct timespec*t){(void)c;(void)m;
 uint64_t until=t->tv_sec*1000000000ull+t->tv_nsec;
 if(!stopped&&next_tick<=until){fake_ns=next_tick;next_tick+=tick_period;g_link_tick_ns=fake_ns;g_link_tick_n++;return 0;}
 fake_ns=until;return ETIMEDOUT;
}
static int fake_relative_wait(pthread_cond_t*c,pthread_mutex_t*m,const struct timespec*t){
 uint64_t until=fake_ns+t->tv_sec*1000000000ull+t->tv_nsec;
 struct timespec abs={(time_t)(until/1000000000ull),(long)(until%1000000000ull)};return fake_wait(c,m,&abs);
}
static int failed,checks;
#define E(n,c) do{checks++;if(!(c)){failed++;printf("FAIL %s\n",n);}}while(0)
int main(void){@autoreleasepool{
 g_link=(id)[NSObject new];g_dm_present_link=1;g_link_mode=3;g_link_tick_ns=fake_ns;
 setenv("DM_PROFILE_FPS","30",1);unsetenv("DM_FPS");
 E("initial frame",mtl_link_wait_tick(66666666));uint64_t start=fake_ns;
 // 47.6Hz callbacks would cap the old two-tick producer at 23.8fps.
 for(int i=1;i<=60;i++){fake_ns+=6000000;E("clock wait success",mtl_link_wait_tick(66666666));E("deadline not callback count",fake_ns==start+i*33333333ull);}
 fake_ns+=100000000;g_link_tick_ns=fake_ns;next_tick=fake_ns+tick_period;
 uint64_t late=fake_ns;E("late frame immediate",mtl_link_wait_tick(66666666)&&fake_ns==late);
 fake_ns+=6000000;E("resume cadence",mtl_link_wait_tick(66666666)&&fake_ns==late+33333333);
 stopped=1;fake_ns+=100000000;E("stopped callback fails safely",!mtl_link_wait_tick(66666666));
 g_link_tick_ns=fake_ns;next_tick=fake_ns+tick_period;stopped=0;E("recover",mtl_link_wait_tick(66666666));
 uint64_t recovered=fake_ns;fake_ns+=6000000;
 E("recovery second frame keeps interval",mtl_link_wait_tick(66666666)&&fake_ns==recovered+33333333);
 // Callback stops during an established deadline, not just before entry.
 g_link_tick_ns=fake_ns;stopped=1;fake_ns+=6000000;
 E("fresh callback may finish current deadline",mtl_link_wait_tick(66666666));
 E("next deadline reaches stale guard",!mtl_link_wait_tick(66666666));
 stopped=0;g_link_tick_ns=fake_ns;next_tick=fake_ns+tick_period;
 E("recover from inside wait",mtl_link_wait_tick(66666666));
 g_link_mode=1;g_dm_present_link=1;g_link_tick_n=1000;
 E("switch to60",mtl_link_wait_tick(33333333));
 g_link_mode=3;uint64_t switched=fake_ns;
 E("switch back resets phase",mtl_link_wait_tick(66666666)&&fake_ns==switched);
 fake_ns+=6000000;E("switch back clock interval",mtl_link_wait_tick(66666666)&&fake_ns==switched+33333333);
 g_link=nil;E("inactive returns fallback",!mtl_link_wait_tick(66666666));
 printf("ECO_CLOCK checks=%d failed=%d SIMULATED_CALLBACKS\n",checks,failed);return failed!=0;
}}
