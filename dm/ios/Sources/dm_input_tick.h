#pragma once
#import <Foundation/Foundation.h>
// Input/UI polling is independent of render-FPS and does not request a second
// display cadence. NSTimer skips missed fires rather than queueing stale ticks.
static NSTimer *dm_input_tick_start(id target,SEL selector) {
    NSCAssert(NSThread.isMainThread,@"UI polling must start on main thread");
    NSTimer *timer=[NSTimer timerWithTimeInterval:1.0/60.0 target:target selector:selector userInfo:nil repeats:YES];
    timer.tolerance=.001;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    return timer;
}
