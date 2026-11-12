// Contract regressions for production store decisions and sampler retirement.
// The encoder below records actions only; this is not an iOS pixel test.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define E(label, want, got) do { uint64_t w=(want), v=(got); checks++; printf("%s want=%llu got=%llu %s\n", label,(unsigned long long)w,(unsigned long long)v,w==v?"PASS":"FAIL"); failed+=w!=v; } while(0)
@interface StoreRecorder : NSObject { @public MTLStoreAction depth, stencil, color[8]; } @end
@implementation StoreRecorder
- (void)setDepthStoreAction:(MTLStoreAction)a { depth=a; }
- (void)setStencilStoreAction:(MTLStoreAction)a { stencil=a; }
- (void)setColorStoreAction:(MTLStoreAction)a atIndex:(NSUInteger)i { color[i]=a; }
@end
typedef struct { uint8_t b[8192]; size_t n; } code;
static void emit(code *c,int op,const void *a,size_t n) { size_t z=(8+n+7)&~7ull;op_hdr h={op,(uint32_t)z};memcpy(c->b+c->n,&h,8);if(n)memcpy(c->b+c->n+8,a,n);c->n+=z; }
static uint8_t decide(code *c, tex_t *t, int plane, int level, int slice) {
    uint64_t h=(uint64_t)c->b; mtl_sub_index(&h,1);
    g_exec_cur=c->b;g_exec_seq=1;
    g_nsd=1;g_sd[0]=(sd_att){.ser=t->serial,.depth=plane,.lv=level,.sl=slice,.idx=plane?-1:0};
    uint8_t result[16]={0}; E("index available",1,sdx_decide(result));return result[0];
}
static tex_t tex(uint64_t serial) { tex_t t={.serial=serial};t.d.width=t.d.height=8;t.d.depth=t.d.samples=1;t.d.levels=2;t.d.target=NVN_TEXTURE_TARGET_2D;t.d.format=NVN_FORMAT_DEPTH32F_STENCIL8;return t; }
static void clear_depth_scope(int plane, int level, int slice) {
    tex_t t=tex(100000+plane*100+level*10+slice);p_set_rt r={.depth=&t};code c={0};
    emit(&c,OP_BARRIER,NULL,0);emit(&c,OP_SET_RT,&r,sizeof r);
    p_clear_ds cl={.depth=.75,.depth_mask=plane==1,.stencil_mask=plane==2?255:0};emit(&c,OP_CLEAR_DS,&cl,sizeof cl);emit(&c,OP_END,NULL,0);
    E("default-view clear only overwrites base subresource",level||slice?20:2,decide(&c,&t,plane,level,slice));
}
static void color_scissor(int partial) {
    tex_t t=tex(101000+partial);t.d.format=NVN_FORMAT_RGBA8;p_set_rt r={.n=1};r.color[0]=&t;code c={0};
    emit(&c,OP_BARRIER,NULL,0);emit(&c,OP_SET_RT,&r,sizeof r);
    p_scissor sc={0,0,partial?4:8,8};emit(&c,OP_SCISSOR,&sc,sizeof sc);
    p_clear_color cl={.index=0,.mask=15,.rgba={1,0,0,1}};emit(&c,OP_CLEAR_COLOR,&cl,sizeof cl);emit(&c,OP_END,NULL,0);
    uint8_t result=decide(&c,&t,0,0,0);
    E("only executable full-scissor clear proves overwrite",partial?1:0,result!=2);
}
static void color_scissor_inheritance(int mode) {
    tex_t t=tex(103000+mode);t.d.format=NVN_FORMAT_RGBA8;p_set_rt rt={.n=1};rt.color[0]=&t;
    code c={0},sub={0};p_scissor sc={0,0,4,8};p_clear_color cl={.index=0,.mask=15};
    emit(&c,OP_BARRIER,NULL,0);emit(&c,OP_SET_RT,&rt,sizeof rt);
    if(mode==0) { emit(&sub,OP_SCISSOR,&sc,sizeof sc);emit(&sub,OP_END,NULL,0); }
    if(mode==1) { emit(&c,OP_SCISSOR,&sc,sizeof sc);emit(&sub,OP_CLEAR_COLOR,&cl,sizeof cl);emit(&sub,OP_END,NULL,0); }
    if(mode<2) { uint64_t h=(uint64_t)sub.b;emit(&c,OP_CALL,&h,sizeof h); }
    if(mode==2) { R.has_sc=1;R.sc=sc; }
    if(mode!=1) emit(&c,OP_CLEAR_COLOR,&cl,sizeof cl);
    emit(&c,OP_END,NULL,0);E("partial scissor inherited across call or submit",1,decide(&c,&t,0,0,0)!=2);R.has_sc=0;
}
static void readonly_store(int plane, int future_clear) {
    tex_t t=tex(102000+plane*100+future_clear);p_set_rt r={.depth=&t};code c={0};emit(&c,OP_BARRIER,NULL,0);
    if(future_clear) { emit(&c,OP_SET_RT,&r,sizeof r);p_clear_ds cl={.depth_mask=plane==1,.stencil_mask=plane==2?255:0};emit(&c,OP_CLEAR_DS,&cl,sizeof cl); }
    emit(&c,OP_END,NULL,0);decide(&c,&t,plane,0,0);
    StoreRecorder *rec=[StoreRecorder new];g_enc=(id)rec;g_sd[0].load=1;g_sd[0].wrote=0;
    sd_finish();E("readonly attachment preserved unless overwritten",future_clear?MTLStoreActionDontCare:MTLStoreActionStore,plane==1?rec->depth:rec->stencil);g_enc=nil;
}
static void sampler_retirement(void) {
    // Deliberately use an ordinary NSObject so Metal's own object caches cannot mask a lost reference.
    // It stands for an already encoded sampler; no GPU behavior is claimed by this lifetime check.
    samp_par p={.cmp_mode=1,.cmp_func=NVN_COMPARE_FUNC_LEQUAL,.lod_max=16};mtl_reg_samp(900,&p);
    __weak id weak;
    @autoreleasepool { id old=[NSObject new];weak=old;g_sview[900]=(void *)CFBridgingRetain(old);g_srid[900]=123;p.cmp_func=NVN_COMPARE_FUNC_LESS;mtl_reg_samp(900,&p); }
    E("replaced sampler retained for in-flight work",1,weak!=nil);
    E("new sampler must rebuild RID",0,g_srid[900]);
    E("retirement queued",1,g_deferred.count>0);
    if(g_deferred.count) { NvDeferredRelease *d=g_deferred.lastObject;E("retirement covers recording submission",g_fence+1,d->fence); }
    defer_drain();E("unfinished fence does not release sampler",1,weak!=nil);
    g_done=g_fence+1;defer_drain();E("completed fence releases sampler",1,weak==nil);
}
int main(void) { @autoreleasepool {
    setenv("DM_NVN_XV","0",1);setenv("DM_NVN_UNWRITTEN_DC","1",1);state_reset();memset(&R,0,sizeof R);
    E("all legal attachment planes fit",1,sizeof g_sd/sizeof g_sd[0]>=10);
    for(int p=1;p<=2;p++) { clear_depth_scope(p,0,0);clear_depth_scope(p,1,0);clear_depth_scope(p,0,1);readonly_store(p,0);readonly_store(p,1); }
    color_scissor(0);color_scissor(1);for(int m=0;m<3;m++)color_scissor_inheritance(m);g_nsd=0;sampler_retirement();
    printf("SHADOW_STORE checks=%d failed=%d CONTRACT_NO_GPU\n",checks,failed);return failed!=0;
} }
