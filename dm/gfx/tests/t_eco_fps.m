// Production target selection, including live user changes and explicit overrides.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void){return NULL;}
module_t *module_of(const void *p){(void)p;return NULL;}
module_t g_mod[MAX_MOD];int g_nmod;void svc_thread_dump(void){}uint64_t now_ns(void){return bp_now();}
extern int fixture_user_fps;
#include <assert.h>
int main(int argc,char **argv){@autoreleasepool{
 int force=argc>1?atoi(argv[1]):0;
 unsetenv("DM_FPS");if(force)setenv("DM_FPS",argv[1],1);
 setenv("DM_PROFILE_FPS","60",1);fixture_user_fps=60;assert(mtl_fps_target()==(force?force:60));
 fixture_user_fps=30;assert(mtl_fps_target()==(force?force:30));
 assert(dm_pace_hz(120,mtl_fps_target())==(force?force:30));
 fixture_user_fps=60;assert(mtl_fps_target()==(force?force:60));
 setenv("DM_PROFILE_FPS","30",1);assert(mtl_fps_target()==(force?force:30));
 puts("ECO_FPS production live 60/30/60 + profile + override PASS (no GPU timing claim)");return 0;
}}
