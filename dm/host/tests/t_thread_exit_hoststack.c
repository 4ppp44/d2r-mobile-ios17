// Real production entry.S stack switch and ExitThread; no device proof.
#include "../hle_thread.c"
#include <assert.h>
#include <unistd.h>
#include <mach/mach_time.h>
struct dm_flags g_flag;uint64_t g_t0_ns;
void crash_thread_init(void){}void guest_thread_init(void){}
void *guest_sym(const char*n){(void)n;return NULL;}module_t *module_of(const void*p){(void)p;return NULL;}
void dm_prof_add(int i,uint64_t n,uint64_t b){(void)i;(void)n;(void)b;}
uint64_t now_ns(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1000000000ull+t.tv_nsec;}
uint64_t guest_ns(void){return now_ns();}int dm_detclock_enabled(void){return 0;}
void unimpl_c(void){abort();}uint64_t gate_dispatch(uint64_t r,uint64_t*p){(void)r;(void)p;abort();}
static pthread_key_t cleanup_key;
static pthread_mutex_t mu=PTHREAD_MUTEX_INITIALIZER;static pthread_cond_t cv=PTHREAD_COND_INITIALIZER;
static int done,on_host;static uintptr_t low,high;static int go;
static void cleanup(void*p){(void)p;volatile char anchor;uintptr_t a=(uintptr_t)&anchor;pthread_mutex_lock(&mu);on_host=a<low||a>=high;done++;pthread_cond_signal(&cv);pthread_mutex_unlock(&mu);}
static void guest(uint64_t arg){(void)arg;pthread_setspecific(cleanup_key,(void*)1);while(!__atomic_load_n(&go,__ATOMIC_ACQUIRE))sched_yield();uint64_t regs[32]={0};svc_thread(0x0a,regs);abort();}
static void run(int close_first){
 size_t pg=getpagesize(),sz=65536;void*mem=mmap(NULL,sz+2*pg,PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0);assert(mem!=MAP_FAILED);assert(!mprotect((char*)mem+pg,sz,PROT_READ|PROT_WRITE));low=(uintptr_t)mem+pg;high=low+sz;done=on_host=go=0;
 uint64_t regs[32]={0,(uint64_t)guest,0,high,44,0};assert(svc_thread(0x08,regs)&&!regs[0]);uint32_t h=regs[1];regs[0]=h;assert(svc_thread(0x09,regs)&&!regs[0]);
 if(close_first){regs[0]=h;assert(svc_thread(0x16,regs)&&!regs[0]);}
 __atomic_store_n(&go,1,__ATOMIC_RELEASE);
 if(!close_first){regs[0]=0;regs[1]=(uint64_t)&h;regs[2]=1;regs[3]=2000000000;assert(svc_thread(0x18,regs)&&!regs[0]);}
 pthread_mutex_lock(&mu);struct timespec until;clock_gettime(CLOCK_REALTIME,&until);until.tv_sec+=2;while(!done)assert(pthread_cond_timedwait(&cv,&mu,&until)!=ETIMEDOUT);assert(done==1&&on_host);pthread_mutex_unlock(&mu);
 if(!close_first){regs[0]=h;assert(svc_thread(0x16,regs)&&!regs[0]);}
 munmap(mem,sz+2*pg);printf("EXIT_HOST_STACK close_first=%d PASS\n",close_first);
}
int main(void){assert(svc_thread_main_init()==0x1001);pthread_key_create(&cleanup_key,cleanup);run(0);run(1);return 0;}
