// Store lookahead: a later supported whole-subresource ClearTexture overwrites every prior color byte.
// Production replay plus real Metal readback proves the overwrite uses DontCare, while partial clears,
// another mip, reads before overwrite, format views, depth/stencil, and copies stay conservative.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define EXPECT(name, want, got) do { uint64_t w_=(want), g_=(got); checks++; printf("%s 期望 %llu → 真结果 %llu %s\n", name, (unsigned long long)w_, (unsigned long long)g_, w_==g_?"✓":"✗"); failed += w_ != g_; } while (0)
typedef struct { uint8_t *p; size_t n; } code;
static code code_new(void) { code c={0}; if(posix_memalign((void **)&c.p,getpagesize(),65536))abort();memset(c.p,0,65536);mtl_pool_add(c.p,65536);return c; }
static void emit(code *c,unsigned op,const void *a,size_t n){size_t z=(8+n+7)&~7ull;op_hdr h={op,(uint32_t)z};memcpy(c->p+c->n,&h,8);if(n)memcpy(c->p+c->n+8,a,n);c->n+=z;}
static tex_t texture(uint64_t serial,int fmt,int levels){tex_t t={.serial=serial};t.d.width=t.d.height=8;t.d.depth=t.d.samples=1;t.d.levels=levels;t.d.target=NVN_TEXTURE_TARGET_2D;t.d.format=fmt;return t;}
static p_set_rt rt_color(tex_t *t,int level){p_set_rt r={.n=1};r.color[0]=t;r.has_cview[0]=1;r.cview[0].set_levels=1;r.cview[0].base_level=level;r.cview[0].nlevels=1;return r;}
static p_set_rt rt_depth(tex_t *t){p_set_rt r={.depth=t,.has_dview=1};r.dview.set_levels=1;r.dview.nlevels=1;return r;}
static void set_rt(code *c,p_set_rt r){emit(c,OP_SET_RT,&r,sizeof r);}
static void clear_color(code *c,float r,float g,float b){p_clear_color x={.index=0,.mask=15,.rgba={r,g,b,1}};emit(c,OP_CLEAR_COLOR,&x,sizeof x);}
static void clear_ds(code *c){p_clear_ds x={.depth=.25,.depth_mask=1,.stencil=0x5a,.stencil_mask=255};emit(c,OP_CLEAR_DS,&x,sizeof x);}
static void bind_prog(code *c,prog_t *p){p_bind_program x={p,3};emit(c,OP_BIND_PROGRAM,&x,sizeof x);}
static void bind_tex(code *c,int id){p_bind_handles x={.stage=1,.first=0,.n=1};x.h[0]=id;emit(c,OP_BIND_TEX,&x,sizeof x);}
static void draw_cmd(code *c){p_draw x={NVN_DRAW_PRIMITIVE_TRIANGLES,0,3};emit(c,OP_DRAW,&x,sizeof x);}
static void clear_tex_cmd(code *c,tex_t *t,int mode){p_clear_tex x={.tex=t,.mask=mode==1?7:15,.is_uint=0};x.has_view=1;x.view.set_levels=1;x.view.base_level=mode==2?1:0;x.view.nlevels=1;if(mode==3){x.view.set_format=1;x.view.format=NVN_FORMAT_RGBA8_SRGB;}x.r=(NVNcopyRegion){0,0,0,mode==1?4:8,mode==1?4:8,1};x.c.f[0]=x.c.f[1]=1;x.c.f[2]=0;x.c.f[3]=1;emit(c,OP_CLEAR_TEX,&x,sizeof x);}
static void copy_t2t_cmd(code *c, tex_t *src, tex_t *dst) { p_copy_t2t x={.src=src,.dst=dst}; x.sr=(NVNcopyRegion){0,0,0,8,8,1}; x.dr=x.sr; emit(c,OP_COPY_T2T,&x,sizeof x); }
static void seed_color(tex_t *t,MTLClearColor cc){mtl_sub_begin();RPD *p=[RPD new];p.colorAttachments[0].texture=tex_mtl(t);p.colorAttachments[0].loadAction=MTLLoadActionClear;p.colorAttachments[0].storeAction=MTLStoreActionStore;p.colorAttachments[0].clearColor=cc;enc_r_end(enc_r_begin(p));uint64_t f=mtl_sub_commit();if(!mtl_wait(f,5000000000ull))abort();}
static void read_color(tex_t *t,uint8_t out[256]){rp_flush();id<MTLBuffer>b=[g_dev newBufferWithLength:256 options:MTLResourceStorageModeShared];[blit()copyFromTexture:tex_mtl(t) sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(8,8,1) toBuffer:b destinationOffset:0 destinationBytesPerRow:32 destinationBytesPerImage:256];uint64_t f=mtl_sub_commit();EXPECT("提交完成",1,mtl_wait(f,5000000000ull));EXPECT("提交反馈无错误",0,mtl_last_commit_error());memcpy(out,b.contents,256);}
static void expect_rgba(const char *name,const uint8_t p[256],uint8_t r,uint8_t g,uint8_t b){int bad=0;for(int i=0;i<64;i++)bad+=p[4*i]!=r||p[4*i+1]!=g||p[4*i+2]!=b||p[4*i+3]!=255;EXPECT(name,0,bad);}
enum { FULL_CLEAR, PARTIAL_CLEAR, OTHER_MIP, READ_FIRST, FORMAT_VIEW, DEPTH_CLEAR, COPY_DEST };
typedef struct { uint64_t store; uint8_t color[256]; } result;
static result run_case(int mode,prog_t pg[2],int sample_base){
    static uint64_t ser=90000;tex_t dst=texture(ser++,mode==DEPTH_CLEAR?NVN_FORMAT_DEPTH32F_STENCIL8:NVN_FORMAT_RGBA8,2),src=texture(ser++,NVN_FORMAT_RGBA8,1),out=texture(ser++,NVN_FORMAT_RGBA8,1);code c=code_new();
    if(mode!=DEPTH_CLEAR)seed_color(&dst,MTLClearColorMake(0,0,1,1));seed_color(&src,MTLClearColorMake(0,1,0,1));seed_color(&out,MTLClearColorMake(0,0,0,1));int dst_id=sample_base+(int)(dst.serial-90000)+1;mtl_reg_tex(dst_id,&dst,NULL);
    state_reset();memset(&R,0,sizeof R);vis_clear();g_vis_on=g_vis_counting=0;
    if(mode==DEPTH_CLEAR){set_rt(&c,rt_depth(&dst));clear_ds(&c);bind_prog(&c,&pg[0]);draw_cmd(&c);}
    else{set_rt(&c,rt_color(&dst,0));clear_color(&c,1,0,0);bind_prog(&c,&pg[0]);draw_cmd(&c);}
    set_rt(&c,rt_color(&out,0));clear_color(&c,0,0,0);bind_prog(&c,&pg[0]);draw_cmd(&c);
    if(mode==READ_FIRST){set_rt(&c,rt_color(&out,0));bind_prog(&c,&pg[1]);bind_tex(&c,dst_id);draw_cmd(&c);}
    if(mode==COPY_DEST)copy_t2t_cmd(&c,&src,&dst);else if(mode==DEPTH_CLEAR){p_clear_tex x={.tex=&dst,.mask=15,.is_uint=0};x.has_view=1;x.view.set_levels=1;x.view.nlevels=1;x.r=(NVNcopyRegion){0,0,0,8,8,1};x.c.f[0]=.5f;emit(&c,OP_CLEAR_TEX,&x,sizeof x);}else clear_tex_cmd(&c,&dst,mode==PARTIAL_CLEAR?1:mode==OTHER_MIP?2:mode==FORMAT_VIEW?3:0);
    emit(&c,OP_END,NULL,0);mtl_sub_begin();uint64_t hh=(uint64_t)c.p;mtl_sub_index(&hh,1);uint64_t s0=g_bw_store;mtl_exec(c.p);rp_flush();result r={.store=g_bw_store-s0};if(mode==DEPTH_CLEAR){uint64_t f=mtl_sub_commit();EXPECT("提交完成",1,mtl_wait(f,5000000000ull));EXPECT("提交反馈无错误",0,mtl_last_commit_error());}else read_color(&dst,r.color);return r;
}
static NvProg *g_tkeep[256]; static int g_tnkeep;
int main(void){@autoreleasepool{setvbuf(stdout,NULL,_IONBF,0);setenv("DM_NVN_TBDR","1",1);setenv("DM_NVN_XV","0",1);mtl_init();NSError *e=nil;id<MTLLibrary>l=[g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;vertex float4 v(uint n[[vertex_id]]){float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[n],0,1);}\nfragment float4 blue(){return float4(0,0,1,1);}\nstruct A{texture2d<float> t[[id(0)]];};fragment float4 sample(constant A&a[[buffer(0)]]){return a.t.read(uint2(0));}\n" options:nil error:&e];if(!l){fprintf(stderr,"%s\n",e.localizedDescription.UTF8String);return 2;}static prog_t pg[2]={{.serial=91000},{.serial=91001}};for(int i=0;i<2;i++){NvProg*p=[NvProg new];p->sh[0]=[NvShader new];p->sh[0]->fn=[l newFunctionWithName:@"v"];p->sh[1]=[NvShader new];p->sh[1]->stage=1;p->sh[1]->fn=[l newFunctionWithName:i?@"sample":@"blue"];p->sh[1]->rf.color_mask=1;if(i){p->sh[1]->rf.nb=1;p->sh[1]->rf.b[0]=(nvn_rbind){.kind=NVN_RB_TEX,.reg=0,.dtt=MTLTextureType2D};p->sh[1]->ae=[p->sh[1]->fn newArgumentEncoderWithBufferIndex:0];}if(g_tnkeep<256)g_tkeep[g_tnkeep++]=p;serial_put(pg[i].serial,p);}int sample_base=2400;
    result full=run_case(FULL_CLEAR,pg,sample_base);expect_rgba("整级ClearTexture最终黄色",full.color,255,255,0);EXPECT("整级ClearTexture省前通道Store",256,full.store);
    result partial=run_case(PARTIAL_CLEAR,pg,sample_base);EXPECT("部分ClearTexture保守Store",512,partial.store);
    result mip=run_case(OTHER_MIP,pg,sample_base);EXPECT("另一mip ClearTexture保守Store",512,mip.store);
    result read=run_case(READ_FIRST,pg,sample_base);EXPECT("覆盖前有读取保守Store",512,read.store);
    result view=run_case(FORMAT_VIEW,pg,sample_base);EXPECT("换格式视图ClearTexture保守Store",512,view.store);
    result depth=run_case(DEPTH_CLEAR,pg,sample_base);EXPECT("深度模板ClearTexture保守Store",576,depth.store);
    result copy=run_case(COPY_DEST,pg,sample_base);expect_rgba("拷贝目标最终绿色",copy.color,0,255,0);EXPECT("拷贝目标仍保守Store",512,copy.store);
    printf("RT_STORE_OVERWRITE checks=%d failed=%d\n",checks,failed);return failed!=0;}}
