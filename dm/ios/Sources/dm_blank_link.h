#pragma once
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#include <TargetConditionals.h>
#include <pthread.h>
#include <stdatomic.h>
#include "../../gfx/nvn/dm_present_schedule.h"
#include "../../gfx/nvn/dm_display_trace.h"
// No NVN/guest/resources/saves. Same display API, service60, latency1 (unless an
// explicit valid test override), render30 every other callback, and shared
// Scheduled direct presentation primitive as the game. Clear-only is NOT an
// equal-workload GPU benchmark; it isolates a minimal presentation path.
@interface DmBlankLinkRenderer : NSObject <CAMetalDisplayLinkDelegate>
- (instancetype)initWithLayer:(CAMetalLayer *)layer fps:(int)fps;
- (void)setActive:(BOOL)active;
- (uint64_t)presentedCount;
- (uint64_t)callbackCount;
@end
@implementation DmBlankLinkRenderer {
    CAMetalLayer *_layer;id<MTLCommandQueue> _queue;CAMetalDisplayLink *_link;
    CFRunLoopRef _runloop;pthread_mutex_t _mutex;BOOL _started;
    _Atomic int _active;_Atomic uint64_t _callbacks,_presents;uint64_t _encoded;
    int _fps;double _previous;
}
- (instancetype)initWithLayer:(CAMetalLayer *)layer fps:(int)fps {
    if((self=[super init])){_layer=layer;_queue=[layer.device newCommandQueue];_fps=fps==30?30:60;pthread_mutex_init(&_mutex,NULL);}
    return self;
}
- (uint64_t)presentedCount{return atomic_load_explicit(&_presents,memory_order_relaxed);}
- (uint64_t)callbackCount{return atomic_load_explicit(&_callbacks,memory_order_relaxed);}
- (void)run {
    @autoreleasepool {
        pthread_setname_np("blank-present-link");pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE,0);
        CAMetalDisplayLink *l=[[CAMetalDisplayLink alloc]initWithMetalLayer:_layer];
        l.preferredFrameRateRange=CAFrameRateRangeMake(60,60,60);
        int lat=getenv("DM_PRESENT_LATENCY")?atoi(getenv("DM_PRESENT_LATENCY")):1;l.preferredFrameLatency=lat==2?2:1;l.delegate=self;
        pthread_mutex_lock(&_mutex);_link=l;_runloop=CFRunLoopGetCurrent();CFRetain(_runloop);l.paused=!atomic_load_explicit(&_active,memory_order_acquire);pthread_mutex_unlock(&_mutex);
        [l addToRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];
        CFRunLoopRun(); // Session lifetime, paused on inactive/share. Never starts the game.
    }
}
- (void)setActive:(BOOL)active {
    atomic_store_explicit(&_active,active,memory_order_release);
    pthread_mutex_lock(&_mutex);
    if(active&&!_started){_started=YES;[NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];}
    CAMetalDisplayLink *l=_link;CFRunLoopRef loop=_runloop;
    if(loop){CFRunLoopPerformBlock(loop,kCFRunLoopDefaultMode,^{l.paused=!active;if(!active)dm_display_trace_flush();});CFRunLoopWakeUp(loop);}
    pthread_mutex_unlock(&_mutex);
}
- (void)metalDisplayLink:(CAMetalDisplayLink *)link needsUpdate:(CAMetalDisplayLinkUpdate *)update {
    const double now=CACurrentMediaTime();uint64_t tick=atomic_fetch_add_explicit(&_callbacks,1,memory_order_relaxed)+1;
    unsigned step=_fps==30?2:1;
    dm_display_context x={tick,0,0,now,update.targetTimestamp,update.targetPresentationTimestamp,link.preferredFrameLatency,link.preferredFrameRateRange.preferred,step};
    dm_display_trace_emit("callback",x,now,_previous>0?now-_previous:0,_layer.maximumDrawableCount,0);_previous=now;
    if(!atomic_load_explicit(&_active,memory_order_acquire)||tick%step){dm_display_trace_emit("skip",x,CACurrentMediaTime(),0,0,0);dm_display_trace_emit("return",x,CACurrentMediaTime(),0,0,0);return;}
    x.ticket=++_encoded;x.frame=x.ticket-1;
    id<CAMetalDrawable> dr=update.drawable;id<MTLCommandBuffer> cb=[_queue commandBuffer];
    if(!dr||!cb){dm_display_trace_emit("error",x,CACurrentMediaTime(),0,0,1);return;}
    MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=dr.texture;rp.colorAttachments[0].loadAction=MTLLoadActionClear;rp.colorAttachments[0].storeAction=MTLStoreActionStore;rp.colorAttachments[0].clearColor=MTLClearColorMake(50/255.0,50/255.0,50/255.0,1);
    [[cb renderCommandEncoderWithDescriptor:rp]endEncoding];
#if !TARGET_OS_SIMULATOR
    [dr addPresentedHandler:^(id<MTLDrawable> shown){double t=shown.presentedTime;if(t>0)atomic_fetch_add_explicit(&self->_presents,1,memory_order_relaxed);dm_display_trace_emit("display",x,CACurrentMediaTime(),t,0,t>0);}];
#endif
    [cb addCompletedHandler:^(id<MTLCommandBuffer> done){dm_display_trace_emit("gpu",x,CACurrentMediaTime(),done.GPUStartTime,done.GPUEndTime,(unsigned)done.status);}];
    dm_display_trace_emit("encoded",x,CACurrentMediaTime(),dr.texture.width,dr.texture.height,0);
    dm_present_schedule(cb,dr,^(double begin,double end){dm_display_trace_emit("present",x,end,begin,0,0);});
    dm_display_trace_emit("return",x,CACurrentMediaTime(),1,0,0);
}
@end
