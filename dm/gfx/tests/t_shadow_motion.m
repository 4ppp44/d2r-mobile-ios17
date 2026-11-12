// Real Metal depth-bias readback and moving/subpixel comparison sampling.
// Includes the production encoder wrapper/state replay; does not run the game.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void){return NULL;}
module_t *module_of(const void *p){(void)p;return NULL;}
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void){} uint64_t now_ns(void){return bp_now();}
static int checks,failed;
#define CK(label,cond) do{int ok=(cond);checks++;failed+=!ok;if(!ok)printf("FAIL %s\n",label);}while(0)
static id<MTLDevice> dev;static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> ps;static id<MTLComputePipelineState> cs;
static id<MTLDepthStencilState> ds;static id<MTLSamplerState> sampler;
static id<MTLTexture> depth;static id<MTLBuffer> output;
// x=edge in texels; y=base depth; z=depth slope per texel; w=receiver sampling motion.
static float result[8192];
static void render(float edge,float base,float slope,float motion,float units,float factor,float clamp){
    float p[4]={edge,base,slope,motion};
    id<MTLCommandBuffer> cb=[queue commandBuffer];
    MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];
    rp.depthAttachment.texture=depth;rp.depthAttachment.loadAction=MTLLoadActionClear;
    rp.depthAttachment.storeAction=MTLStoreActionStore;rp.depthAttachment.clearDepth=1;
    id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:rp];
    [e setRenderPipelineState:ps];[e setDepthStencilState:ds];[e setVertexBytes:&p length:sizeof p atIndex:0];
    // Exact production API adapter; parameters replayed through production state_op.
    p_poly_offset po={factor,units,clamp};state_op(OP_POLY_OFFSET,&po);
    enc_r_depth_bias(e,S.po.units,S.po.factor,S.po.clamp);
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];[e endEncoding];
    id<MTLComputeCommandEncoder> c=[cb computeCommandEncoder];[c setComputePipelineState:cs];
    [c setTexture:depth atIndex:0];[c setSamplerState:sampler atIndex:0];[c setBuffer:output offset:0 atIndex:0];
    [c setBytes:&p length:sizeof p atIndex:1];[c dispatchThreads:MTLSizeMake(64,64,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];[c endEncoding];
    [cb commit];[cb waitUntilCompleted];CK("GPU completion",cb.status==MTLCommandBufferStatusCompleted);
    memcpy(result,output.contents,sizeof result);
}
static float compare_at(int x,int y,float ref){x=MAX(0,MIN(63,x));y=MAX(0,MIN(63,y));return ref<=result[y*64+x]?1:0;}
int main(int argc,char **argv){@autoreleasepool{
    MTLPixelFormat format=argc>1&&!strcmp(argv[1],"d32s8")?MTLPixelFormatDepth32Float_Stencil8:MTLPixelFormatDepth32Float;
    _Static_assert(NVN_POLYGON_OFFSET_ENABLE_FILL==4,"draw fill bit");
    _Static_assert(NVN_POLYGON_OFFSET_ENABLE_POINT==1 && NVN_POLYGON_OFFSET_ENABLE_LINE==2,"independent enables");
    dev=MTLCreateSystemDefaultDevice();if(!dev){fprintf(stderr,"NO_METAL_DEVICE\n");return 2;}queue=[dev newCommandQueue];
    printf("device=%s format=%lu scope=Mac_real_Metal_not_iOS_not_game\n",dev.name.UTF8String,(unsigned long)format);
    g_dev=dev;
    int guest_formats[]={NVN_FORMAT_DEPTH16,NVN_FORMAT_DEPTH24,NVN_FORMAT_DEPTH32F,NVN_FORMAT_DEPTH24_STENCIL8,NVN_FORMAT_DEPTH32F_STENCIL8};
    MTLPixelFormat mapped[]={MTLPixelFormatDepth16Unorm,MTLPixelFormatDepth32Float,MTLPixelFormatDepth32Float,MTLPixelFormatDepth32Float_Stencil8,MTLPixelFormatDepth32Float_Stencil8};
    for(int i=0;i<5;i++){tex_t t={0};t.d.width=t.d.height=64;t.d.depth=t.d.levels=t.d.samples=1;t.d.target=NVN_TEXTURE_TARGET_2D;t.d.format=guest_formats[i];MTLTextureDescriptor *desc=tex_desc(&t,0);CK("production depth format mapping",desc.pixelFormat==mapped[i]);printf("FORMAT guest=%d metal=%lu\n",guest_formats[i],(unsigned long)desc.pixelFormat);}
    NSString *src=@"#include <metal_stdlib>\nusing namespace metal;\n"
    "vertex float4 v(uint i[[vertex_id]],constant float4&p[[buffer(0)]]){float2 q[6]={float2(0,0),float2(1,0),float2(0,1),float2(0,1),float2(1,0),float2(1,1)};float x=q[i].x*p.x;return float4(x/32-1,q[i].y*2-1,p.y+p.z*x,1);}\n"
    "kernel void k(depth2d<float,access::sample> t[[texture(0)]],sampler s[[sampler(0)]],device float*out[[buffer(0)]],constant float4&p[[buffer(1)]],uint2 g[[thread_position_in_grid]]){uint n=g.y*64+g.x;out[n]=t.read(g);out[4096+n]=t.sample_compare(s,(float2(g)+.5+float2(p.w,0))/64,.6);}";
    NSError *err=nil;id<MTLLibrary> lib=[dev newLibraryWithSource:src options:nil error:&err];
    if(!lib){fprintf(stderr,"%s\n",err.localizedDescription.UTF8String);return 2;}
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"v"];pd.depthAttachmentPixelFormat=format;
    ps=[dev newRenderPipelineStateWithDescriptor:pd error:&err];cs=[dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k"] error:&err];
    if(!ps||!cs){fprintf(stderr,"%s\n",err.localizedDescription.UTF8String);return 2;}
    MTLDepthStencilDescriptor *dd=[MTLDepthStencilDescriptor new];dd.depthCompareFunction=MTLCompareFunctionAlways;dd.depthWriteEnabled=YES;ds=[dev newDepthStencilStateWithDescriptor:dd];
    MTLSamplerDescriptor *sd=[MTLSamplerDescriptor new];sd.minFilter=sd.magFilter=MTLSamplerMinMagFilterLinear;sd.compareFunction=MTLCompareFunctionLessEqual;sd.sAddressMode=sd.tAddressMode=MTLSamplerAddressModeClampToEdge;sampler=[dev newSamplerStateWithDescriptor:sd];
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:64 height:64 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;td.storageMode=MTLStorageModePrivate;depth=[dev newTextureWithDescriptor:td];output=[dev newBufferWithLength:sizeof result options:MTLResourceStorageModeShared];
    for(int b=0;b<3;b++)for(int u=0;u<3;u++){
        float z=(float[]){.125,.5,.875}[b],units=(float[]){0,1,16}[u];render(64,z,0,0,units,0,0);
        float delta=result[32*64+32]-z;printf("BIAS base=%.9g units=%g depth=%.9g delta=%.9g ulps=%g\n",z,units,result[2080],delta,delta/(nextafterf(z,1)-z));
        CK("flat depth finite",isfinite(delta));if(!u)CK("zero bias exact",delta==0);else CK("units match primitive float ULP",delta==units*(nextafterf(z,1)-z));
    }
    render(64,.125,.01,0,0,0,0);float slope_base=result[2080];
    render(64,.125,.01,0,16,0,0);float slope_delta=result[2080]-slope_base;
    CK("units use maximum primitive exponent rather than local fragment exponent",fabsf(slope_delta-16*0x1p-24f)<0x1p-25f);
    printf("PRIMITIVE_EXPONENT delta=%.9g expected=%.9g\n",slope_delta,16*0x1p-24f);
    for(int sign=-1;sign<=1;sign+=2){render(64,.25,.001,0,0,sign*2,sign*.0005);float wanted=.25+.001*32.5+sign*.0005;CK("signed slope/clamp",fabsf(result[2080]-wanted)<2e-6);printf("CLAMP sign=%d got=%.9g expected=%.9g\n",sign,result[2080],wanted);}
    float first[4096],repeat[8192];double maxerr=0;int changed=0,nearest_disagrees=0;float previous[4096]={0};
    for(int phase=0;phase<=16;phase++){
        float shift=phase/8.f;render(24+shift,.3,0,shift,16,0,0);memcpy(repeat,result,sizeof result);
        int baddepth=0;double errmax=0;for(int y=0;y<64;y++)for(int x=0;x<64;x++){
            int n=y*64+x;float z=result[n];if(x+.5<24+shift)baddepth+=fabsf(z-.3f)>2e-6;else if(x+.5>24+shift)baddepth+=z!=1;
            float sx=x+shift;int lo=floorf(sx);float a=sx-lo;
            float expected=(1-a)*compare_at(lo,y,.6)+a*compare_at(lo+1,y,.6);nearest_disagrees+=fabsf(compare_at((int)roundf(sx),y,.6)-result[4096+n])>.01f;errmax=fmax(errmax,fabs(expected-result[4096+n]));
            if(phase)changed+=previous[n]!=result[4096+n];previous[n]=result[4096+n];
        }
        CK("moving caster analytic coverage",baddepth==0);CK("PCF agrees with CPU bilinear comparison",errmax<.002);maxerr=fmax(maxerr,errmax);
        if(!phase)memcpy(first,result+4096,sizeof first);
        if(phase==8||phase==16)CK("integer translated scene same interior shadow",memcmp(first,result+4096,sizeof first)==0);
        render(24+shift,.3,0,shift,16,0,0);CK("identical phase deterministic depth and shadow",memcmp(repeat,result,sizeof result)==0);
        printf("MOTION phase=%d texels=%g bad_depth=%d PCF_max_error=%g\n",phase,shift,baddepth,errmax);
    }
    CK("nearest filter negative control differs",nearest_disagrees>0);
    CK("subpixel comparison responds to movement",changed>0);printf("SHADOW_MOTION checks=%d failed=%d changed_samples=%d max_PCF_error=%g\n",checks,failed,changed,maxerr);return failed?1:0;
}}
