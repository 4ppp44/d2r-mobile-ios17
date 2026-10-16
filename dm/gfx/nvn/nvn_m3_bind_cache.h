#pragma once
#include <stdint.h>
#include <string.h>
// Native M3 direct buffer binding cache: submit-thread owned, no retained resources.
// Only direct buffer bindings are cached; argument/resource declarations remain unchanged.
// Reset on EVERY new render encoder, including when encoder addresses are reused.
enum { DM_M3_BIND_SLOTS = 31 };
typedef struct { uint64_t gpu[2][DM_M3_BIND_SLOTS]; uint32_t valid[2]; } dm_m3_bind_cache;
static inline void dm_m3_bind_reset(dm_m3_bind_cache *c) { c->valid[0]=c->valid[1]=0; }
static inline int dm_m3_bind_seen(const dm_m3_bind_cache *c, int vertex, unsigned i, uint64_t gpu) {
 if(i>=DM_M3_BIND_SLOTS)return 0;
 unsigned s=vertex?0:1;uint32_t bit=UINT32_C(1)<<i;
 return (c->valid[s]&bit)&&c->gpu[s][i]==gpu;
}
static inline void dm_m3_bind_record(dm_m3_bind_cache *c, int vertex, unsigned i, uint64_t gpu) {
 if(i>=DM_M3_BIND_SLOTS)return;
 unsigned s=vertex?0:1;c->gpu[s][i]=gpu;c->valid[s]|=UINT32_C(1)<<i;
}
