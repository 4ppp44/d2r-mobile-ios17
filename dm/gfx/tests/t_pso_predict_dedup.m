// Production predictor/getter + counted real Metal compilation + exact green readback.
#ifndef D2R_BACKEND_FILE
#define D2R_BACKEND_FILE "../nvn/nvn_mtl.m"
#endif
#include D2R_BACKEND_FILE
void *front_metal_layer(void){return NULL;}
module_t *module_of(const void *p){(void)p;return NULL;}
module_t g_mod[MAX_MOD];int g_nmod;
void svc_thread_dump(void){}
uint64_t now_ns(void){return bp_now();}
static _Atomic int builds, bg_active, bg_peak, bg_started, bg_before_demand, foreground_done, demand_timeout;
@interface CountDevice : NSProxy { @public id<MTLDevice> real; int fail_speculative; dispatch_semaphore_t gate, entered; } @end
@implementation CountDevice
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s{return [(NSObject *)real methodSignatureForSelector:s];}
- (void)forwardInvocation:(NSInvocation *)i{[i invokeWithTarget:real];}
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d error:(NSError **)e{
 atomic_fetch_add(&builds,1);int background=!pthread_main_np();
 if(background){
  int active=atomic_fetch_add(&bg_active,1)+1,peak=atomic_load(&bg_peak);
  while(active>peak&&!atomic_compare_exchange_weak(&bg_peak,&peak,active)){}
  atomic_fetch_add(&bg_started,1);
  if(!atomic_load(&foreground_done))atomic_store(&bg_before_demand,1);
  if(gate){dispatch_semaphore_signal(entered);dispatch_semaphore_wait(gate,DISPATCH_TIME_FOREVER);}
 }
 id<MTLRenderPipelineState> ps=nil;
 if(fail_speculative&&background){if(e)*e=[NSError errorWithDomain:@"metal" code:1 userInfo:nil];}
 else ps=[real newRenderPipelineStateWithDescriptor:d error:e];
 if(background)atomic_fetch_sub(&bg_active,1);else atomic_store(&foreground_done,1);
 return ps;
}
@end
// Publish completed warm work at future-program resolution, after the getter's first cache checks.
@interface PublishingMap : NSProxy { @public NSMutableDictionary *real; NSArray<WarmItem *> *items; } @end
@implementation PublishingMap
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s{return [real methodSignatureForSelector:s];}
- (void)forwardInvocation:(NSInvocation *)i{[i invokeWithTarget:real];}
- (id)objectForKeyedSubscript:(id)key{if(items){NSArray *publish=items;items=nil;for(WarmItem *item in publish)warm_enqueue(item);}return real[key];}
@end
static int checks,failed;
#define CK(name,cond) do{checks++;int ok=(cond);failed+=!ok;printf("%s %s\n",name,ok?"PASS":"FAIL");}while(0)
static void emit(uint8_t *b,size_t *n,int op,const void *p,size_t sz){op_hdr h={op,(uint32_t)((8+sz+7)&~7ull)};memcpy(b+*n,&h,8);if(sz)memcpy(b+*n+8,p,sz);*n+=h.size;}
// Hold two real background compiles at entry, then demand either a queued or running key.
// A watchdog releases the gate on failure so a scheduling regression reports instead of hanging.
static id<MTLRenderPipelineState> schedule_demand(NvProg *pr,CountDevice *counter,id<MTLRenderPipelineState> first,int running){
 int entered=1;for(int i=0;i<2;i++)entered&=dispatch_semaphore_wait(counter->entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0;
 CK("two_background_compiles_started",entered);
 if(!entered){for(int i=0;i<PSO_PEND_MAX;i++)dispatch_semaphore_signal(counter->gate);return first;}
 CK("background_concurrency_bounded",atomic_load(&bg_started)==2&&atomic_load(&bg_active)==2&&atomic_load(&bg_peak)==2);
 CK("first_demand_finishes_before_speculation",atomic_load(&bg_before_demand)==0);
 S.chmask.mask=running?31:79;
 pso_key key;pso_key_fill(&key,pr->sh[0],pr->sh[1],g_pass.cfmt,0,0,1,0);
 pthread_mutex_lock(&g_pp_mu);int at=pso_pend_find(&key),claimed=at>=0&&g_pp[at].running;pthread_mutex_unlock(&g_pp_mu);
 CK("demand_key_has_expected_ownership",at>=0&&claimed==running);
 uint64_t comp0=g_bp_pso_compile_n,wait0=g_bp_pso_wait_n;
 dispatch_semaphore_t finished=dispatch_semaphore_create(0),watched=dispatch_semaphore_create(0),gate=counter->gate;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
  if(running){
   uint64_t until=bp_now()+5*NSEC_PER_SEC;int paused=0;
   while(!paused&&bp_now()<until){pthread_mutex_lock(&g_pp_mu);paused=g_pp_paused;pthread_mutex_unlock(&g_pp_mu);if(!paused)usleep(1000);}
   if(!paused)atomic_store(&demand_timeout,1);
   // Both workers complete during the demand pause; resume must still drain the remaining keys.
   for(int i=0;i<PSO_PEND_MAX;i++)dispatch_semaphore_signal(gate);
  }else if(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))){
   atomic_store(&demand_timeout,1);for(int i=0;i<PSO_PEND_MAX;i++)dispatch_semaphore_signal(gate);
  }
  dispatch_semaphore_signal(watched);
 });
 id<MTLRenderPipelineState> ps=pso_get(pr,nil);dispatch_semaphore_signal(finished);
 int watched_ok=dispatch_semaphore_wait(watched,dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC))==0;
 CK("demand_completes_without_queue_stall",watched_ok&&!atomic_load(&demand_timeout)&&ps!=nil);
 CK("demand_cost_classified",g_bp_pso_compile_n==comp0+!running&&g_bp_pso_wait_n==wait0+running);
 CK("demand_published_in_cache",hm_get_id(&g_pso,&key)==ps&&ps!=nil);
 for(int i=0;i<PSO_PEND_MAX;i++)dispatch_semaphore_signal(counter->gate);
 return ps;
}
int main(int argc,char **argv){@autoreleasepool{
 const char *mode=argc>1?argv[1]:"repeat"; int harvest=!strcmp(mode,"harvest"), slot_fail=!strcmp(mode,"slot_fail"), repeated=strcmp(mode,"no_future")!=0, scissor=!strcmp(mode,"scissor"), other=!strcmp(mode,"other")||harvest||slot_fail||scissor, merged=!strcmp(mode,"merged"); int expected=other||merged?2:1;
 int publication=!strcmp(mode,"publication"),running=!strcmp(mode,"running"),scheduling=!strcmp(mode,"schedule")||running;if(scheduling)expected=5;
 char cache_dir[]="/tmp/d2r-pso-harvest-XXXXXX"; NSString *manifest=nil;
 if(harvest||scheduling){if(!mkdtemp(cache_dir))return 2;manifest=[@(cache_dir) stringByAppendingPathComponent:@"pso_user.tsv"];setenv("DM_PSO_USER",manifest.fileSystemRepresentation,1);pso_learning_start();}
 id<MTLDevice> dev=MTLCreateSystemDefaultDevice();if(!dev){fprintf(stderr,"NO_REAL_METAL_DEVICE\n");return 2;}
 CountDevice *counter=[CountDevice alloc];counter->real=dev;counter->fail_speculative=slot_fail;g_dev=(id<MTLDevice>)counter;
 if(scheduling){counter->gate=dispatch_semaphore_create(0);counter->entered=dispatch_semaphore_create(0);}
 NSError *err=nil;id<MTLLibrary> lib=[dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal; vertex float4 v(uint i [[vertex_id]]){float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[i],0,1);} fragment float4 f(){return float4(0,1,0,1);}" options:nil error:&err];CK("real_MSL_compiles",lib!=nil);if(!lib)return 2;
 NvProg *pr=[NvProg new];pr->sh[0]=[NvShader new];pr->sh[1]=[NvShader new];pr->sh[0]->fn=[lib newFunctionWithName:@"v"];pr->sh[1]->fn=[lib newFunctionWithName:@"f"];pr->sh[1]->stage=1;strcpy(pr->sh[0]->key,"dedup-v");strcpy(pr->sh[1]->key,"dedup-f");
 prog_t pg={.serial=710001};serial_put(pg.serial,pr);memset(&S,0,sizeof S);S.prog=&pg;S.chmask.mask=15;memset(&g_pass,0,sizeof g_pass);g_pass.cfmt[0]=MTLPixelFormatRGBA8Unorm;g_pass.samples=1;if(scissor){R.sc=(p_scissor){0,0,8,8};R.has_sc=1;}
 uint8_t control[2][0x880]={0};control[1][0]=1;prog_t future_pg={.nstage=2,.serial=710002};future_pg.sd[0].control=control[0];future_pg.sd[1].control=control[1];
 id<MTLRenderPipelineState> warmed=nil;
 if(publication){
  NSString *keys[2];for(int i=0;i<2;i++){uint8_t md[32];CC_SHA256(control[i],sizeof control[i],md);keys[i]=[NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x",md[0],md[1],md[2],md[3],md[4],md[5],md[6],md[7]];}
  WarmItem *item=[WarmItem new];item->kind=1;item->vs=pr->sh[0];item->fs=pr->sh[1];item->vs_key=@"dedup-v";item->fs_key=@"dedup-f";
  pso_key_fill(&item->pso,item->vs,item->fs,g_pass.cfmt,0,0,1,0);item->object=[g_dev newRenderPipelineStateWithDescriptor:pso_desc(&item->pso,item->vs,item->fs,nil,0) error:&err];warmed=item->object;if(!warmed)return 2;
  WarmItem *future=[WarmItem new];future->kind=0;future->key=[keys[0] stringByAppendingString:@"_b"];future->shader=pr->sh[0];
  PublishingMap *map=[PublishingMap alloc];map->real=[@{keys[0]:@"顶点",keys[1]:@"像素"} mutableCopy];map->items=@[item,future];g_shmap=(id)map;
  g_shcache=[NSMutableDictionary dictionary];g_shcache[[keys[1] stringByAppendingString:@"_b"]]=pr->sh[1];g_warm_items=[NSMutableArray array];atomic_store(&g_warm_ready,0);atomic_store(&g_warm_running,1);
 }
 uint8_t ops[1024]={0};size_t n=0;p_draw dw={NVN_DRAW_PRIMITIVE_TRIANGLES,0,3};
 if(scheduling){for(int i=1;i<=4;i++){p_bind_state st={.kind=2};typeof(S.chmask) mask=S.chmask;mask.mask=15+16*i;memcpy(st.bytes,&mask,sizeof mask);emit(ops,&n,OP_BIND_STATE,&st,sizeof st);emit(ops,&n,OP_DRAW,&dw,sizeof dw);}}
 else{if(other){p_bind_state st={.kind=2};typeof(S.chmask) mask=S.chmask;mask.mask=harvest?255:7;memcpy(st.bytes,&mask,sizeof mask);emit(ops,&n,OP_BIND_STATE,&st,sizeof st);}if(scissor){p_scissor fsc={0,0,1,1};emit(ops,&n,OP_SCISSOR,&fsc,sizeof fsc);}if(publication){p_bind_program bind={.prog=&future_pg};emit(ops,&n,OP_BIND_PROGRAM,&bind,sizeof bind);}if(repeated)emit(ops,&n,OP_DRAW,&dw,sizeof dw);}
 emit(ops,&n,OP_END,NULL,0);g_exec_next=ops;g_sub_serial=1;uint8_t lmap[8]={0,1,2,3,4,5,6,7};if(merged){g_pso_lmap=lmap;g_pso_fsfn=pr->sh[1]->fn;}
 id<MTLRenderPipelineState> ps=pso_get(pr,nil);CK("production_PSO_created",ps!=nil);if(scissor){CK("scissor_preserved",R.sc.w==8&&R.sc.h==8&&R.has_sc==1);}
 if(publication){CK("predictor_claimed_pipeline_reused",ps==warmed);CK("unfinished_warmup_not_waited",atomic_load(&g_warm_running)==1);}
 if(scheduling)ps=schedule_demand(pr,counter,ps,running);
 // Wait for every speculative job before counting, independent of driver scheduling.
 pthread_mutex_lock(&g_pp_mu);for(int i=0;i<PSO_PEND_MAX;i++)while(g_pp[i].used&&!g_pp[i].done)pthread_cond_wait(&g_pp_cv,&g_pp_mu);pthread_mutex_unlock(&g_pp_mu);pso_pend_harvest();
 int count=atomic_load(&builds);printf("compile_calls=%d expected=%d mode=%s\n",count,expected,mode);CK("exact_key_compile_count",count==expected);
 CK("cache_hit_identity",pso_get(pr,nil)==ps);CK("cache_hit_no_compile",atomic_load(&builds)==count);
 if(harvest){
  S.chmask.mask=255;id<MTLRenderPipelineState> predicted=pso_get(pr,nil);
  CK("predicted_pipeline_reused_without_compilation",predicted!=nil&&atomic_load(&builds)==count);
  ps=predicted;pso_learning_join_quiescent();
  NSString *text=[NSString stringWithContentsOfFile:manifest encoding:NSUTF8StringEncoding error:nil];
  int rows=0,found=0;for(NSString *row in [text componentsSeparatedByString:@"\n"]){if(![row hasPrefix:@"R\t"])continue;rows++;pso_skey sk;
   if(!pso_skey_parse([row substringFromIndex:2].UTF8String,&sk)&&!strcmp(sk.vs,"dedup-v")&&!strcmp(sk.fs,"dedup-f")&&sk.k.chmask==255&&sk.k.cfmt[0]==MTLPixelFormatRGBA8Unorm&&!sk.k.vs&&!sk.k.fs&&!sk.k.fsfn)found++;
  }
  CK("both_runtime_pipelines_persisted",rows==2);CK("harvested_key_usable_for_next_launch",found==1);
  [NSFileManager.defaultManager removeItemAtPath:@(cache_dir) error:nil];
 }
 if(scheduling){
  CK("background_limit_held_after_resume",atomic_load(&bg_peak)<=PSO_PEND_WORKERS);
  int leaked=0;for(int i=0;i<PSO_PEND_MAX;i++)if(g_pp[i].used)leaked++;CK("all_pending_slots_reclaimed",leaked==0);
  pso_learning_join_quiescent();NSString *text=[NSString stringWithContentsOfFile:manifest encoding:NSUTF8StringEncoding error:nil];int rows=0,demand_rows=0;
  for(NSString *row in [text componentsSeparatedByString:@"\n"]){if(![row hasPrefix:@"R\t"])continue;rows++;pso_skey sk;if(!pso_skey_parse([row substringFromIndex:2].UTF8String,&sk)&&sk.k.chmask==(running?31:79))demand_rows++;}
  CK("all_exact_keys_learned_once",rows==5&&demand_rows==1);
  [NSFileManager.defaultManager removeItemAtPath:@(cache_dir) error:nil];
 }
 if(slot_fail){
  int leaked=0;for(int i=0;i<PSO_PEND_MAX;i++)if(g_pp[i].used)leaked++;
  CK("failed_speculative_slot_reclaimed",leaked==0);
 }
 MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModeShared;id<MTLTexture> tex=[dev newTextureWithDescriptor:td];id<MTLCommandQueue> q=[dev newCommandQueue];id<MTLCommandBuffer> cb=[q commandBuffer];MTLRenderPassDescriptor *pd=[MTLRenderPassDescriptor renderPassDescriptor];pd.colorAttachments[0].texture=tex;pd.colorAttachments[0].loadAction=MTLLoadActionClear;pd.colorAttachments[0].storeAction=MTLStoreActionStore;
 id<MTLRenderCommandEncoder> enc=[cb renderCommandEncoderWithDescriptor:pd];[enc setRenderPipelineState:ps];if(R.has_sc){long x0=R.sc.x<0?0:R.sc.x,y0=R.sc.y<=0?0:R.sc.y,x1=(long)R.sc.x+R.sc.w,y1=(long)R.sc.y+R.sc.h;if(x1>8)x1=8;if(y1>8)y1=8;if(x1>x0&&y1>y0)[enc setScissorRect:(MTLScissorRect){(NSUInteger)x0,(NSUInteger)y0,(NSUInteger)(x1-x0),(NSUInteger)(y1-y0)}];}[enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[enc endEncoding];[cb commit];[cb waitUntilCompleted];CK("real_GPU_completed",cb.status==MTLCommandBufferStatusCompleted);
 uint8_t out[256];[tex getBytes:out bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0];int bad=0;uint8_t green[4]={0,255,0,255};for(int i=0;i<64;i++)bad+=memcmp(out+i*4,green,4)!=0;CK("all_64_texels_exact_green",bad==0);
 printf("PSO_DEDUP_REAL_METAL checks=%d failed=%d speculative_kicked=%llu taken=%llu\n",checks,failed,(unsigned long long)g_pp_kicked,(unsigned long long)g_pp_taken);return failed?1:0;
}}
