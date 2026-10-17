#import <Foundation/Foundation.h>
#include "dm_measurement.h"
#include <stdio.h>
#include <string.h>
#if __has_include("dm_input_tick.h")
#include "dm_input_tick.h"
#endif
static int n,bad;
#define C(name,x) do{n++;BOOL pass=(x);bad+=!pass;printf("PLAY %s %s\n",name,pass?"PASS":"FAIL");}while(0)
static NSString *actual(NSString *doc,NSString *build){
#if DM_MEASUREMENT_BUILD_BOUND
 return dm_measurement_requested_profile(doc,build);
#else
 return dm_measurement_profile([NSString stringWithContentsOfFile:[doc stringByAppendingPathComponent:@"diagnostics_profile.txt"] encoding:NSUTF8StringEncoding error:nil]);
#endif
}
@interface Counter:NSObject
@property NSUInteger ticks;
- (void)tick:(NSTimer *)timer;
@end
@implementation Counter
- (void)tick:(NSTimer *)timer{(void)timer;self.ticks++;}
@end
int main(int argc,char **argv){@autoreleasepool{if(argc!=2)return 2;NSString *doc=@(argv[1]);NSFileManager *fm=NSFileManager.defaultManager;[fm createDirectoryAtPath:doc withIntermediateDirectories:YES attributes:nil error:nil];NSString *profile=[doc stringByAppendingPathComponent:@"diagnostics_profile.txt"],*marker=[doc stringByAppendingPathComponent:@"diagnostics_build.txt"];
 // Fixture files only, never the phone's files/resources/saves.
 [@"OLD_BUILD\n" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
 for(NSString*p in @[@"display",@"timing",@"gpu",@"linkblank60",@"linkblank30"]){[p writeToFile:profile atomically:YES encoding:NSUTF8StringEncoding error:nil];C(p.UTF8String,[actual(doc,@"2026101705")isEqual:@"normal"]);}
 [@"2026101705\n" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];[@"display" writeToFile:profile atomically:YES encoding:NSUTF8StringEncoding error:nil];C("explicit-current-diagnostics-retained",[actual(doc,@"2026101705")isEqual:@"display"]);C("future-build-not-inherited",[actual(doc,@"2026101706")isEqual:@"normal"]);C("input-files-untouched",[[NSString stringWithContentsOfFile:profile encoding:NSUTF8StringEncoding error:nil]isEqual:@"display"]&&[[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil]isEqual:@"2026101705\n"]);
#if __has_include("dm_input_tick.h")
 Counter*c=[Counter new];NSTimer*t=dm_input_tick_start(c,@selector(tick:));C("main-runloop-timer-valid",t.valid&&NSThread.isMainThread);C("render30-and60-input60",fabs(t.timeInterval-1.0/60)<1e-9);C("timer-leeway-1ms",t.tolerance<=.00101);
 NSDate*end=[NSDate dateWithTimeIntervalSinceNow:1.2];while([end timeIntervalSinceNow]>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:end];[t invalidate];printf("ACTUAL_FOUNDATION_INPUT_TIMER ticks=%lu seconds=1.2 scope=Mac_timer_not_A16\n",(unsigned long)c.ticks);C("actual-timer-not-stalled",c.ticks>=40&&c.ticks<=90);
#else
 C("main-runloop-timer-valid",NO);C("render30-and60-input60",NO);C("timer-leeway-1ms",NO);C("actual-timer-not-stalled",NO);
#endif
 printf("PLAY_CONTRACT checks=%d failed=%d scope=build-bound-collector-and-actualFoundation-timer-not-A16\n",n,bad);return bad!=0;}}
