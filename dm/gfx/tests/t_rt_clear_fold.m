// Pending clear + exact same-target SET_RT: production replay must fold only the adjacent safe case.
// Real Metal pixels/planes and pass/bandwidth counters cover same/different target/view, copy/read ordering,
// sampled attachment fallback, submit-only/no-draw clears, packed D32S8 single-plane clears, and DM_NVN_TBDR=0.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
// The preserved baseline has no fold state; build it with -DT_CLEAR_FOLD_NO_STATE to prove this fixture fails there.
#ifdef T_CLEAR_FOLD_NO_STATE
#define RESET_FOLD() ((void)0)
#else
#define RESET_FOLD() (g_clear_fold_pending = g_clear_fold_ready = 0)
#endif
static int checks, failed;
#define EXPECT(name, want, got) do { uint64_t w_=(want), g_=(got); checks++; printf("%s 期望 %llu → 真结果 %llu %s\n", name, (unsigned long long)w_, (unsigned long long)g_, w_==g_?"✓":"✗"); failed += w_ != g_; } while (0)
typedef struct { uint8_t b[16384]; size_t n; } code;
static void emit(code *c, unsigned op, const void *a, size_t n) { size_t z=(8+n+7)&~7ull; op_hdr h={op,(uint32_t)z}; memcpy(c->b+c->n,&h,8); if(n)memcpy(c->b+c->n+8,a,n); c->n+=z; }
static tex_t texture(uint64_t serial, int fmt) { tex_t t={.serial=serial}; t.d.width=t.d.height=8; t.d.depth=t.d.levels=t.d.samples=1; t.d.target=NVN_TEXTURE_TARGET_2D; t.d.format=fmt; return t; }
static p_set_rt rt_color(tex_t *t, int view) { p_set_rt r={.n=1}; r.color[0]=t; if(view){r.has_cview[0]=1;r.cview[0].set_levels=1;r.cview[0].base_level=0;r.cview[0].nlevels=1;} return r; }
static p_set_rt rt_depth(tex_t *t) { p_set_rt r={.depth=t,.has_dview=1}; r.dview.set_levels=1;r.dview.base_level=0;r.dview.nlevels=1; return r; }
static void set_rt(code *c, p_set_rt r) { emit(c,OP_SET_RT,&r,sizeof r); }
static void clear_color(code *c, float r, float g, float b) { p_clear_color x={.index=0,.mask=15,.rgba={r,g,b,1}}; emit(c,OP_CLEAR_COLOR,&x,sizeof x); }
static void bind_prog(code *c, prog_t *p) { p_bind_program x={p,3}; emit(c,OP_BIND_PROGRAM,&x,sizeof x); }
static void bind_tex(code *c, int id) { p_bind_handles x={.stage=1,.first=0,.n=1}; x.h[0]=id; emit(c,OP_BIND_TEX,&x,sizeof x); }
static void draw_cmd(code *c) { p_draw x={NVN_DRAW_PRIMITIVE_TRIANGLES,0,3}; emit(c,OP_DRAW,&x,sizeof x); }
static void copy_cmd(code *c, tex_t *s, tex_t *d) { p_copy_t2t x={.src=s,.dst=d}; x.sr=(NVNcopyRegion){0,0,0,8,8,1}; x.dr=x.sr; emit(c,OP_COPY_T2T,&x,sizeof x); }
static void read_color(tex_t *t, uint8_t out[256]) { rp_flush(); id<MTLBuffer> b=[g_dev newBufferWithLength:256 options:MTLResourceStorageModeShared]; [blit() copyFromTexture:tex_mtl(t) sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(8,8,1) toBuffer:b destinationOffset:0 destinationBytesPerRow:32 destinationBytesPerImage:256]; uint64_t f=mtl_sub_commit(); EXPECT("提交完成",1,mtl_wait(f,5000000000ull)); EXPECT("提交反馈无错误",0,mtl_last_commit_error()); memcpy(out,b.contents,256); }
static void read_ds(tex_t *t, float depth[64], uint8_t stencil[64]) { rp_flush(); id<MTLBuffer> db=[g_dev newBufferWithLength:256 options:MTLResourceStorageModeShared], sb=[g_dev newBufferWithLength:64 options:MTLResourceStorageModeShared]; BENC b=blit(); [b copyFromTexture:tex_mtl(t) sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(8,8,1) toBuffer:db destinationOffset:0 destinationBytesPerRow:32 destinationBytesPerImage:256 options:MTLBlitOptionDepthFromDepthStencil]; [b copyFromTexture:tex_mtl(t) sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(8,8,1) toBuffer:sb destinationOffset:0 destinationBytesPerRow:8 destinationBytesPerImage:64 options:MTLBlitOptionStencilFromDepthStencil]; uint64_t f=mtl_sub_commit(); EXPECT("平面提交完成",1,mtl_wait(f,5000000000ull)); EXPECT("平面提交无错误",0,mtl_last_commit_error()); memcpy(depth,db.contents,256);memcpy(stencil,sb.contents,64); }
static void seed_color(tex_t *t, MTLClearColor cc) { mtl_sub_begin(); RPD *p=[RPD new];p.colorAttachments[0].texture=tex_mtl(t);p.colorAttachments[0].loadAction=MTLLoadActionClear;p.colorAttachments[0].storeAction=MTLStoreActionStore;p.colorAttachments[0].clearColor=cc;enc_r_end(enc_r_begin(p));uint64_t f=mtl_sub_commit();if(!mtl_wait(f,5000000000ull))abort(); }
static void seed_ds(tex_t *t) { mtl_sub_begin();RPD *p=[RPD new];p.depthAttachment.texture=p.stencilAttachment.texture=tex_mtl(t);p.depthAttachment.loadAction=p.stencilAttachment.loadAction=MTLLoadActionClear;p.depthAttachment.storeAction=p.stencilAttachment.storeAction=MTLStoreActionStore;p.depthAttachment.clearDepth=.75;p.stencilAttachment.clearStencil=0x2d;enc_r_end(enc_r_begin(p));uint64_t f=mtl_sub_commit();if(!mtl_wait(f,5000000000ull))abort(); }
typedef struct { uint64_t passes, load, store; uint8_t color[256]; } result;
static result run_color(int mode, prog_t pg[2], int sample_id) {
    static uint64_t ser=70000; tex_t a=texture(ser++,NVN_FORMAT_RGBA8), other=texture(ser++,NVN_FORMAT_RGBA8), copied=texture(ser++,NVN_FORMAT_RGBA8); code c={0};
    seed_color(&a,MTLClearColorMake(0,0,1,1)); seed_color(&other,MTLClearColorMake(0,1,0,1));
    state_reset();memset(&R,0,sizeof R);vis_clear();g_vis_on=g_vis_counting=0;RESET_FOLD();
    p_set_rt first=rt_color(&a,0), second=first; if(mode==1)second=rt_color(&other,0); if(mode==2)second=rt_color(&a,1);
    int attached_sample_id=0;if(mode==6){static int id=2000;attached_sample_id=id++;mtl_reg_tex(attached_sample_id,&a,NULL);}
    set_rt(&c,first); clear_color(&c,1,0,0); if(mode==3)copy_cmd(&c,&a,&copied); set_rt(&c,second);
    if(mode!=4){ bind_prog(&c,&pg[mode>=5?1:0]); if(mode==5)bind_tex(&c,sample_id);if(mode==6)bind_tex(&c,attached_sample_id); draw_cmd(&c); } emit(&c,OP_END,NULL,0);
    mtl_sub_begin();uint64_t p0=g_stat_pass,l0=g_bw_load,s0=g_bw_store;mtl_exec(c.b);rp_flush();result r={.passes=g_stat_pass-p0,.load=g_bw_load-l0,.store=g_bw_store-s0};read_color(mode==1?&other:&a,r.color);return r;
}
static void expect_rgba(const char *name, const uint8_t p[256], uint8_t r, uint8_t g, uint8_t b) { int bad=0;for(int i=0;i<64;i++)bad+=p[4*i]!=r||p[4*i+1]!=g||p[4*i+2]!=b||p[4*i+3]!=255;EXPECT(name,0,bad); }
static void plane_case(int stencil_only, int disabled) { static uint64_t ser=80000; tex_t ds=texture(ser++,NVN_FORMAT_DEPTH32F_STENCIL8);seed_ds(&ds);state_reset();memset(&R,0,sizeof R);RESET_FOLD();code c={0};set_rt(&c,rt_depth(&ds));p_clear_ds x={.depth=.25,.depth_mask=!stencil_only,.stencil=0x5a,.stencil_mask=stencil_only?255:0};emit(&c,OP_CLEAR_DS,&x,sizeof x);emit(&c,OP_END,NULL,0);mtl_sub_begin();uint64_t p0=g_stat_pass,l0=g_bw_load,s0=g_bw_store;mtl_exec(c.b);float d[64];uint8_t s[64];read_ds(&ds,d,s);int bd=0,bs=0;for(int i=0;i<64;i++){bd+=d[i]!=(stencil_only?.75f:.25f);bs+=s[i]!=(stencil_only?0x5a:0x2d);}EXPECT(stencil_only?"模板单清保持深度":"深度单清落地",0,bd);EXPECT(stencil_only?"模板单清落地":"深度单清保持模板",0,bs);EXPECT("单平面清除一个pass",1,g_stat_pass-p0);EXPECT("单平面清除Load字节",disabled?(stencil_only?256:64):0,g_bw_load-l0);EXPECT("单平面Store字节",disabled?320:stencil_only?64:256,g_bw_store-s0); }
int main(int argc,char **argv){@autoreleasepool{setvbuf(stdout,NULL,_IONBF,0);int disabled=argc>1&&!strcmp(argv[1],"--disabled");setenv("DM_NVN_TBDR",disabled?"0":"1",1);mtl_init();NSError *e=nil;id<MTLLibrary> l=[g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;vertex float4 v(uint n[[vertex_id]]){float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[n],0,1);}\nfragment float4 blue(){return float4(0,0,1,1);}\nstruct A{texture2d<float> t[[id(0)]];};fragment float4 sample(constant A&a[[buffer(0)]]){return a.t.read(uint2(0));}\n" options:nil error:&e];if(!l){fprintf(stderr,"%s\n",e.localizedDescription.UTF8String);return 2;}static prog_t pg[2]={{.serial=81000},{.serial=81001}};for(int i=0;i<2;i++){NvProg *p=[NvProg new];p->sh[0]=[NvShader new];p->sh[0]->fn=[l newFunctionWithName:@"v"];p->sh[1]=[NvShader new];p->sh[1]->stage=1;p->sh[1]->fn=[l newFunctionWithName:i?@"sample":@"blue"];p->sh[1]->rf.color_mask=1;if(i){p->sh[1]->rf.nb=1;p->sh[1]->rf.b[0]=(nvn_rbind){.kind=NVN_RB_TEX,.reg=0,.dtt=MTLTextureType2D};p->sh[1]->ae=[p->sh[1]->fn newArgumentEncoderWithBufferIndex:0];}serial_put(pg[i].serial,p);}tex_t sampled=texture(89999,NVN_FORMAT_RGBA8);seed_color(&sampled,MTLClearColorMake(0,1,0,1));mtl_reg_tex(1900,&sampled,NULL);
    result same=run_color(0,pg,1900);expect_rgba("同目标清后绘制蓝",same.color,0,0,255);EXPECT(disabled?"关闭开关保持两pass":"同目标折为一pass",disabled?2:1,same.passes);EXPECT("同目标Store字节",disabled?512:256,same.store);EXPECT(disabled?"关闭开关第二pass读入":"折叠无Load",disabled?256:0,same.load);
    result different=run_color(1,pg,1900);expect_rgba("不同目标绘制蓝",different.color,0,0,255);EXPECT("不同目标不折叠",2,different.passes);
    result view=run_color(2,pg,1900);expect_rgba("不同view绘制蓝",view.color,0,0,255);EXPECT("不同view不折叠",2,view.passes);
    result copy=run_color(3,pg,1900);expect_rgba("copy后同目标绘制蓝",copy.color,0,0,255);EXPECT("copy顺序障碍不折叠",2,copy.passes);
    result submit=run_color(4,pg,1900);expect_rgba("submit-only清除红",submit.color,255,0,0);EXPECT("无draw清除仍落地",1,submit.passes);
    result sample=run_color(5,pg,1900);expect_rgba("后续采样独立绿色贴图",sample.color,0,255,0);EXPECT(disabled?"关闭开关采样路径两pass":"安全折叠允许采样非附件",disabled?2:1,sample.passes);
    result attached=run_color(6,pg,1900);expect_rgba("采样附件读到已落地红清除",attached.color,255,0,0);EXPECT("采样附件回退两pass",2,attached.passes);
    plane_case(0,disabled);plane_case(1,disabled);printf("RT_CLEAR_FOLD mode=%s checks=%d failed=%d\n",disabled?"disabled":"enabled",checks,failed);return failed!=0;}}
