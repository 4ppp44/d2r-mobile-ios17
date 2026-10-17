#pragma once
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
// Shared by game and matched control. Never wait on the CPU for GPU completion.
// The completion block runs AFTER drawable.present, so diagnostics cannot delay it.
static inline void dm_present_schedule(id<MTLCommandBuffer> cb, id<MTLDrawable> drawable,
                                      void (^after)(double scheduled_s,double returned_s)) {
    [cb addScheduledHandler:^(id<MTLCommandBuffer> scheduled) {
        (void)scheduled;
        const double begin=after?CACurrentMediaTime():0;
        [drawable present];
        if(after)after(begin,CACurrentMediaTime());
    }];
    [cb commit];
}
