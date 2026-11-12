// Real Metal readback through production OP_BIND_PROGRAM + resolved PSO.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void){return NULL;}
module_t *module_of(const void *p){return NULL;}
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void){}
uint64_t now_ns(void){return bp_now();}
static int failures,checks;
#define CK(n,x) do{int ok=!!(x);checks++;failures+=!ok;printf("%s %s\n",ok?"PASS":"FAIL",n);}while(0)
static void bind_pg(prog_t *p,int stages){p_bind_program b={p,stages};state_op(OP_BIND_PROGRAM,&b);}
static NvProg *resolved(void){return S.prog?prog_get(S.prog):nil;}
static void pixels(const char *name){
 NvProg *p=resolved(); id<MTLTexture> t=[g_dev newTextureWithDescriptor:({MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];d.usage=MTLTextureUsageRenderTarget;d.storageMode=MTLStorageModeShared;d;})];
 id<MTLCommandQueue> q=[g_dev newCommandQueue];id<MTLCommandBuffer> cb=[q commandBuffer];RPD *r=[RPD new];r.colorAttachments[0].texture=t;r.colorAttachments[0].loadAction=MTLLoadActionClear;r.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1);r.colorAttachments[0].storeAction=MTLStoreActionStore;
 id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:r];
 if(p->sh[0]&&p->sh[1]){MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];d.vertexFunction=p->sh[0]->fn;d.fragmentFunction=p->sh[1]->fn;d.colorAttachments[0].pixelFormat=t.pixelFormat;NSError *err=nil;id<MTLRenderPipelineState> ps=[g_dev newRenderPipelineStateWithDescriptor:d error:&err];CK("real PSO created",ps!=nil);if(ps){[e setRenderPipelineState:ps];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];}}
 [e endEncoding];[cb commit];[cb waitUntilCompleted];CK("Metal command completed",cb.status==MTLCommandBufferStatusCompleted);uint8_t b[64];[t getBytes:b bytesPerRow:16 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0];int good=1;for(int i=0;i<16;i++)good &= b[4*i]==255&&b[4*i+1]==0&&b[4*i+2]==0;printf("PIXEL %s rgba=%u,%u,%u,%u\n",name,b[0],b[1],b[2],b[3]);CK(name,good);
}
int main(void){@autoreleasepool{setvbuf(stdout,NULL,_IONBF,0);mtl_init();printf("DEVICE %s\n",g_dev.name.UTF8String);NSError *err=nil;id<MTLLibrary> l=[g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;vertex float4 v(uint i[[vertex_id]]){float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[i],0,1);}fragment float4 f(){return float4(1,0,0,1);}kernel void c(device uint *p[[buffer(0)]]){p[0]=123;}" options:nil error:&err];if(!l)return 2;
 NvShader *v=[NvShader new],*f=[NvShader new],*c=[NvShader new];v->fn=[l newFunctionWithName:@"v"];f->fn=[l newFunctionWithName:@"f"];f->stage=1;c->fn=[l newFunctionWithName:@"c"];c->stage=5;
 prog_t pg[4]={{.serial=990001},{.serial=990002},{.serial=990003},{.serial=990004}};NvProg *a=[NvProg new],*b=[NvProg new],*vs=[NvProg new],*fs=[NvProg new];a->sh[0]=v;a->sh[1]=f;b->sh[5]=c;vs->sh[0]=v;fs->sh[1]=f;serial_put(pg[0].serial,a);serial_put(pg[1].serial,b);serial_put(pg[2].serial,vs);serial_put(pg[3].serial,fs);
 state_reset();bind_pg(&pg[0],3);bind_pg(&pg[1],32);pixels("compute bind preserves graphics pixels");CK("compute retained",resolved()->sh[5]==c);bind_pg(&pg[0],3);CK("graphics bind preserves compute",resolved()->sh[5]==c);
 state_reset();bind_pg(&pg[2],1);bind_pg(&pg[3],2);pixels("independent VS FS pixels");
#ifdef T_BIND_STAGES_FIXED
 const prog_t *identity=S.prog;for(int i=0;i<1000;i++){bind_pg(&pg[2],1);bind_pg(&pg[3],2);}CK("stable composition identity",identity==S.prog);bind_pg(NULL,32);CK("unbinding compute preserves graphics",resolved()->sh[0]==v&&resolved()->sh[1]==f&&!resolved()->sh[5]);bind_pg(NULL,2);CK("explicit FS unbind",resolved()->sh[0]==v&&!resolved()->sh[1]);
#endif
 printf("BIND_STAGES checks=%d failures=%d\n",checks,failures);return failures!=0;}}
