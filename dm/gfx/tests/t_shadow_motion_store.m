// Real Metal production replay: moving depth mip/layer -> default-view clear ->
// read-only depth pass -> fragment sample_compare -> pixel/depth readback.
// CPU expectations are analytic; no GPU data is used to derive expected shadows.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed, linear_mode;
#define CK(label, cond) do { int ok_=(cond); checks++; if(!ok_) { failed++; printf("FAIL %s\n",label); } } while(0)
typedef struct { uint8_t *p; size_t n; } code;
static code code_new(void) {
    code c={0}; if(posix_memalign((void **)&c.p,getpagesize(),65536))abort();
    memset(c.p,0,65536); mtl_pool_add(c.p,65536); return c;
}
static void emit(code *c,unsigned op,const void *a,size_t n) {
    size_t z=(8+n+7)&~7ull; if(c->n+z>65536)abort();
    op_hdr h={op,(uint32_t)z}; memcpy(c->p+c->n,&h,8);
    if(n)memcpy(c->p+c->n+8,a,n); c->n+=z;
}
static tex_t texture(uint64_t serial,int depth) {
    tex_t t={.serial=serial}; t.d.width=t.d.height=16;
    t.d.depth=depth?2:1; t.d.levels=depth?2:1; t.d.samples=1;
    t.d.target=depth?NVN_TEXTURE_TARGET_2D_ARRAY:NVN_TEXTURE_TARGET_2D;
    t.d.format=depth?NVN_FORMAT_DEPTH32F:NVN_FORMAT_RGBA8; return t;
}
static p_set_rt depth_rt(tex_t *d,int lv,int sl,tex_t *color) {
    p_set_rt r={.depth=d,.has_dview=1};
    r.dview=(view_t){.set_levels=1,.base_level=lv,.nlevels=1,
                            .set_layers=1,.min_layer=sl,.nlayers=1};
    if(color){r.n=1;r.color[0]=color;} return r;
}
static void target(code *c,p_set_rt r) { emit(c,OP_SET_RT,&r,sizeof r); }
static void ds(code *c,int write) {
    ds_st s={.dt=1,.dw=write,.df=NVN_DEPTH_FUNC_LEQUAL};
    p_bind_state p={.kind=5}; memcpy(p.bytes,&s,sizeof s); emit(c,OP_BIND_STATE,&p,sizeof p);
}
static void bind_program_cmd(code *c,prog_t *p) { p_bind_program b={p,3};emit(c,OP_BIND_PROGRAM,&b,sizeof b); }
static void draw_cmd(code *c) { p_draw d={NVN_DRAW_PRIMITIVE_TRIANGLES,0,3};emit(c,OP_DRAW,&d,sizeof d); }
static void scissor(code *c,int x,int width,int height) {
    p_scissor s={x,0,width,height}; emit(c,OP_SCISSOR,&s,sizeof s);
}
static void clear_depth(code *c,float value) {
    p_clear_ds p={.depth=value,.depth_mask=1};emit(c,OP_CLEAR_DS,&p,sizeof p);
}
static void viewport(code *c,int size) {
    p_viewports p={.first=0,.n=1};p.v[0][2]=p.v[0][3]=size;
    emit(c,OP_VIEWPORTS,&p,sizeof p);
}
static NvProg *keep[3];
static int programs(prog_t pg[3]) {
    NSError *error=nil;
    NSString *src=@"#include <metal_stdlib>\nusing namespace metal;\n"
      "vertex float4 v(uint n[[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[n],.25,1); }\n"
      "fragment float4 blue(){return float4(0,0,1,1);}\n"
      "struct A{depth2d<float> t[[id(0)]];sampler s[[id(1)]];constant float4 *uv[[id(2)]];};\n"
      "fragment float4 scene(float4 p[[position]],constant A&a[[buffer(0)]]) { float v=a.t.sample_compare(a.s,p.xy/16.0+a.uv->xy,.5);return float4(v,1-v,0,1); }\n";
    id<MTLLibrary> l=[g_dev newLibraryWithSource:src options:nil error:&error];
    if(!l){fprintf(stderr,"MSL: %s\n",error.localizedDescription.UTF8String);return 0;}
    for(int i=0;i<3;i++) {
        NvProg *p=[NvProg new];keep[i]=p;
        p->sh[0]=[NvShader new];p->sh[0]->fn=[l newFunctionWithName:@"v"];
        if(i) {
            p->sh[1]=[NvShader new];p->sh[1]->stage=1;
            p->sh[1]->fn=[l newFunctionWithName:i==2?@"scene":@"blue"];
            p->sh[1]->rf.color_mask=1;
            if(i==2) {
                p->sh[1]->rf.nb=3;
                p->sh[1]->rf.b[0]=(nvn_rbind){.kind=NVN_RB_TEX,.reg=0,.aid=0,.dtt=MTLTextureType2D,.dpf=NVN_DPF_DEPTH};
                p->sh[1]->rf.b[1]=(nvn_rbind){.kind=NVN_RB_SAMP,.reg=0,.aid=1};
                p->sh[1]->rf.b[2]=(nvn_rbind){.kind=NVN_RB_CBUF,.reg=0,.aid=2};
                p->sh[1]->ae=[p->sh[1]->fn newArgumentEncoderWithBufferIndex:0];
            }
        }
        serial_put(pg[i].serial,p);
    }
    return 1;
}
// Integer positions avoid ambiguous raster edge / interpolation tolerances.
// Every non-default subresource has a distinct translating occluder interval.
static int left_edge(int phase,int lv,int sl) {
    // Linear mode also has adjacent phases with an unchanged caster and moving UV.
    int caster_phase=linear_mode?phase/3:phase;
    return 1+(caster_phase+lv+2*sl)%3;
}
static int caster_width(int lv,int sl) { return 3+sl-lv; }
static float expected_depth(int phase,int lv,int sl,int x,int y) {
    if(!lv&&!sl)return .75f; // no-view clear is exactly mip 0 / layer 0
    int left=left_edge(phase,lv,sl);
    int size=16>>lv;
    int covered_y=!linear_mode || (y>=2+sl && y<size-2);
    return x>=left && x<left+caster_width(lv,sl) && covered_y?.25f:1.f;
}
static float receiver_shift(int phase,int axis) {
    return linear_mode ? (axis ? ((phase*3)%9-4)/8.f : (phase%9-4)/8.f) : 0;
}
// Normalized Metal coordinates put texel centers at (i+.5)/size.
// Clamp each of the four taps, compare each depth, then interpolate comparisons.
static float cpu_shadow(int phase,int lv,int sl,int x,int y,int *wrong_order) {
    int size=16>>lv;
    float sx=(x+.5f)*size/16.f+receiver_shift(phase,0)-.5f;
    float sy=(y+.5f)*size/16.f+receiver_shift(phase,1)-.5f;
    if(!linear_mode) {
        int ix=MAX(0,MIN(size-1,(int)floorf(sx+.5f)));
        int iy=MAX(0,MIN(size-1,(int)floorf(sy+.5f)));
        return .5f<=expected_depth(phase,lv,sl,ix,iy);
    }
    int ix=(int)floorf(sx),iy=(int)floorf(sy);float ax=sx-ix,ay=sy-iy;
    float lit=0,average_depth=0;
    for(int j=0;j<2;j++)for(int i=0;i<2;i++) {
        int tx=MAX(0,MIN(size-1,ix+i)),ty=MAX(0,MIN(size-1,iy+j));
        float weight=(i?ax:1-ax)*(j?ay:1-ay),z=expected_depth(phase,lv,sl,tx,ty);
        lit+=weight*(.5f<=z);average_depth+=weight*z;
    }
    *wrong_order+=fabsf(lit-(.5f<=average_depth))>.01f;
    return lit;
}
int main(int argc,char **argv) { @autoreleasepool {
    linear_mode=argc>1 && !strcmp(argv[1],"linear");
    setvbuf(stdout,NULL,_IONBF,0);
    setenv("DM_NVN_TBDR","1",1);setenv("DM_NVN_XV","0",1);
    setenv("DM_NVN_UNWRITTEN_DC","1",1);
    mtl_init(); if(!g_dev){fprintf(stderr,"NO_METAL_DEVICE\n");return 2;}
    printf("device=%s mode=%s scope=host_real_Metal_not_iOS_not_game\n",g_dev.name.UTF8String,
           linear_mode?"linear_PCF_three_inflight":"nearest_serial");
    static prog_t pg[3]={{.serial=97000},{.serial=97001},{.serial=97002}};
    if(!programs(pg))return 2;
    tex_t depth=texture(97100,1),scratch=texture(97101,0),out[4];
    for(int k=0;k<4;k++)out[k]=texture(97110+k,0);
    for(int lv=0;lv<2;lv++)for(int sl=0;sl<2;sl++) {
        view_t v={.set_levels=1,.base_level=lv,.nlevels=1,.set_layers=1,.min_layer=sl,.nlayers=1,
                  .set_target=1,.target=NVN_TEXTURE_TARGET_2D};
        mtl_reg_tex(2800+lv*2+sl,&depth,&v);
    }
    samp_par sp={.minf=NVN_MIN_FILTER_NEAREST,.magf=NVN_MAG_FILTER_NEAREST,
                 .ws=NVN_WRAP_MODE_CLAMP_TO_EDGE,.wt=NVN_WRAP_MODE_CLAMP_TO_EDGE,
                 .cmp_mode=1,.cmp_func=NVN_COMPARE_FUNC_LEQUAL,.lod_max=16};
    if(linear_mode){sp.minf=NVN_MIN_FILTER_LINEAR;sp.magf=NVN_MAG_FILTER_LINEAR;}
    mtl_reg_samp(2800,&sp);
    // Consecutive identical phases are stationary; other transitions move casters.
    const int phases[]={0,1,2,3,4,4,4,5,6,7,7,7,6,5,4,3,2,1,0,0};
    uint8_t previous[4][1024]={0};int moving_changes=0,stationary_pairs=0;
    state_reset();memset(&R,0,sizeof R);vis_clear();g_vis_on=g_vis_counting=0;
    code uniform_pool=code_new();
    id<MTLBuffer> pixel_frames[20],depth_frames[20];uint64_t fences[20]={0};
    id<MTLSharedEvent> gate=[g_dev newSharedEvent];
    int batch_start=0,batch_size=linear_mode?3:1,three_inflight=0,wrong_order=0,fractional=0,receiver_only=0;
    float max_error=0;
    for(int frame=0;frame<(int)(sizeof phases/sizeof phases[0]);frame++) {
        int phase=phases[frame];code c=code_new();
        // Write all four subresources with real GPU rasterization every frame.
        for(int lv=0;lv<2;lv++)for(int sl=0;sl<2;sl++) {
            int size=16>>lv;target(&c,depth_rt(&depth,lv,sl,NULL));
            viewport(&c,size);scissor(&c,0,size,size);clear_depth(&c,1);ds(&c,1);bind_program_cmd(&c,&pg[0]);
            p_scissor caster={left_edge(phase,lv,sl),linear_mode?2+sl:0,
                              caster_width(lv,sl),linear_mode?size-4-sl:size};
            emit(&c,OP_SCISSOR,&caster,sizeof caster);draw_cmd(&c);
        }
        // The 2903 clear-default regression: must not discard stores for mip 1 or layer 1.
        target(&c,(p_set_rt){.depth=&depth});scissor(&c,0,16,16);clear_depth(&c,.75f);
        for(int lv=0;lv<2;lv++)for(int sl=0;sl<2;sl++) {
            int k=lv*2+sl,size=16>>lv;
            // Force a real separate pass with loaded, tested, unwritten depth.
            target(&c,depth_rt(&depth,lv,sl,&scratch));viewport(&c,size);scissor(&c,0,size,size);
            ds(&c,0);bind_program_cmd(&c,&pg[1]);draw_cmd(&c);
            p_set_rt scene={.n=1};scene.color[0]=&out[k];target(&c,scene);
            viewport(&c,16);scissor(&c,0,16,16);bind_program_cmd(&c,&pg[2]);
            p_bind_handles h={.stage=1,.first=0,.n=1};h.h[0]=2800+k;emit(&c,OP_BIND_TEX,&h,sizeof h);
            h.h[0]=(uint64_t)2800<<20;emit(&c,OP_BIND_SAMP,&h,sizeof h);
            // Unique, stable UBO ranges per draw/frame: no CPU overwrite while in flight.
            uint64_t addr=(uint64_t)uniform_pool.p+(frame*4+k)*256;
            struct {uint64_t dst,n;float uv[4];} update={addr,16,
                {receiver_shift(phase,0)/size,receiver_shift(phase,1)/size,0,0}};
            emit(&c,OP_UPDATE_UB,&update,sizeof update);
            p_bind_buf ub={.stage=1,.index=0,.addr=addr,.size=16};
            emit(&c,OP_BIND_UBO,&ub,sizeof ub);draw_cmd(&c);
        }
        emit(&c,OP_END,NULL,0);
        mtl_sub_begin();
#if DM_NVN_M3
        // A test-only GPU gate makes all three submissions genuinely unfinished.
        // Release on the CPU only after the batch has been committed.
        if(linear_mode)[g_cb encodeWaitForEvent:gate value:batch_start+1];
#else
#error This test's in-flight gate requires the production legacy Metal backend.
#endif
        uint64_t handle=(uint64_t)c.p;mtl_sub_index(&handle,1);mtl_exec(c.p);rp_flush();
        id<MTLBuffer> pixels=[g_dev newBufferWithLength:4096 options:MTLResourceStorageModeShared];
        id<MTLBuffer> depths=[g_dev newBufferWithLength:4096 options:MTLResourceStorageModeShared];
        for(int lv=0;lv<2;lv++)for(int sl=0;sl<2;sl++) {
            int k=lv*2+sl,size=16>>lv;
            [blit() copyFromTexture:tex_mtl(&out[k]) sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
                sourceSize:MTLSizeMake(16,16,1) toBuffer:pixels destinationOffset:k*1024 destinationBytesPerRow:64 destinationBytesPerImage:1024];
            [blit() copyFromTexture:tex_mtl(&depth) sourceSlice:sl sourceLevel:lv sourceOrigin:MTLOriginMake(0,0,0)
                sourceSize:MTLSizeMake(size,size,1) toBuffer:depths destinationOffset:k*1024 destinationBytesPerRow:size*4 destinationBytesPerImage:size*size*4];
        }
        pixel_frames[frame]=pixels;depth_frames[frame]=depths;
        fences[frame]=mtl_sub_commit();
        printf("SUBMIT frame=%d fence=%llu batch_start=%d UV_texels=(%g,%g)\n",frame,
               (unsigned long long)fences[frame],batch_start,receiver_shift(phase,0),receiver_shift(phase,1));
        if(frame-batch_start+1<batch_size && frame!=19)continue;
        if(linear_mode) {
            pthread_mutex_lock(&g_mu);uint64_t done=g_done;pthread_mutex_unlock(&g_mu);
            int pending=frame-batch_start+1;
            CK("gated batch still unfinished",done<fences[batch_start]);
            if(pending==3){CK("three distinct committed fences",fences[frame]-fences[batch_start]==2);three_inflight++;}
            printf("INFLIGHT count=%d completed_fence=%llu first=%llu last=%llu\n",pending,
                   (unsigned long long)done,(unsigned long long)fences[batch_start],(unsigned long long)fences[frame]);
            gate.signaledValue=batch_start+1;
        }
        CK("batch GPU completion",mtl_wait(fences[frame],5000000000ull));CK("GPU error",mtl_last_commit_error()==0);
        for(int checked=batch_start;checked<=frame;checked++) {
        int phase=phases[checked];
        id<MTLBuffer> pixels=pixel_frames[checked],depths=depth_frames[checked];
        int bad_depth=0,bad_color=0,changed=0;
        for(int lv=0;lv<2;lv++)for(int sl=0;sl<2;sl++) {
            int k=lv*2+sl,size=16>>lv;float *z=(float *)((uint8_t *)depths.contents+k*1024);
            uint8_t *p=(uint8_t *)pixels.contents+k*1024;
            for(int y=0;y<size;y++)for(int x=0;x<size;x++)bad_depth+=z[y*size+x]!=expected_depth(phase,lv,sl,x,y);
            for(int y=0;y<16;y++)for(int x=0;x<16;x++) {
                int n=(y*16+x)*4;float lit=cpu_shadow(phase,lv,sl,x,y,&wrong_order);
                float er=fabsf(p[n]/255.f-lit),eg=fabsf(p[n+1]/255.f-(1-lit));
                max_error=fmaxf(max_error,fmaxf(er,eg));
                // RGBA8 quantization plus comparison-filter fixed-point rounding.
                float tolerance=linear_mode?2.f/255.f:0;
                bad_color+=er>tolerance || eg>tolerance || p[n+2]!=0 || p[n+3]!=255;
                fractional+=p[n]>0 && p[n]<255;
            }
            if(checked)changed+=memcmp(previous[k],p,1024)!=0;
            memcpy(previous[k],p,1024);
        }
        CK("CPU analytic depth every texel",bad_depth==0);CK("CPU analytic comparison every pixel",bad_color==0);
        if(checked) {
            if(phase==phases[checked-1]){CK("stationary shadow exact",changed==0);stationary_pairs++;}
            else {
                CK("moving GPU shadow changes",changed>0);moving_changes+=changed;
                if(linear_mode && phase/3==phases[checked-1]/3) {
                    CK("UBO receiver-only motion changes GPU shadow",changed>0);receiver_only++;
                }
            }
        }
        printf("FRAME %02d phase=%d %s depth_bad=%d color_bad=%d changed_subresources=%d\n",checked,phase,
               checked&&phase==phases[checked-1]?"stationary":"moving",bad_depth,bad_color,changed);
        pixel_frames[checked]=nil;depth_frames[checked]=nil;
        }
        batch_start=frame+1;
    }
    if(linear_mode) {
        CK("multiple batches with three frames in flight",three_inflight>=2);
        CK("PCF fractional pixels observed",fractional>0);
        CK("receiver-only motion exercised repeatedly",receiver_only>=4);
        CK("filter-depth-then-compare negative control differs",wrong_order>0);
        printf("PCF max_error=%g tolerance=%g fractional_pixels=%d wrong_order_disagreements=%d three_inflight_batches=%d receiver_only_transitions=%d\n",
               max_error,2.f/255.f,fractional,wrong_order,three_inflight,receiver_only);
    }
    CK("stationary sequence exercised",stationary_pairs>=4);CK("dynamic updates exercised",moving_changes>0);
    printf("SHADOW_MOTION checks=%d failed=%d frames=%lu stationary_pairs=%d moving_changes=%d REAL_GPU\n",
           checks,failed,sizeof phases/sizeof phases[0],stationary_pairs,moving_changes);
    return failed?1:0;
} }
