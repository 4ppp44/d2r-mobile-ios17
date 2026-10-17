// Opt-in measurement only. No game resources/saves/settings are read or modified.
#pragma once
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>
static NSString *dm_measurement_profile(NSString *value) {
    NSString *s=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([s isEqualToString:@"detailed"] || [s isEqualToString:@"timing"]) return @"timing";
    for(NSString *x in @[@"gpu",@"blank30",@"blank60",@"display",@"linkblank30",@"linkblank60"]) if([s isEqualToString:x])return x;
    return @"normal";
}
#define DM_MEASUREMENT_BUILD_BOUND 1
// A normal-play upgrade must not inherit old high-overhead/blank test profiles.
// Explicit future diagnostics require a separate matching build marker. No file
// is deleted/rewritten; stale diagnostic settings are only ignored by this build.
static NSString *dm_measurement_requested_profile(NSString *doc,NSString *build) {
    NSString *marker=[[NSString stringWithContentsOfFile:[doc stringByAppendingPathComponent:@"diagnostics_build.txt"] encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!build.length||![marker isEqualToString:build])return @"normal";
    return dm_measurement_profile([NSString stringWithContentsOfFile:[doc stringByAppendingPathComponent:@"diagnostics_profile.txt"] encoding:NSUTF8StringEncoding error:nil]);
}
static BOOL dm_measurement_is_blank(NSString *p) {return [p hasPrefix:@"blank"]||[p hasPrefix:@"linkblank"];}
static void dm_measurement_boot_env(NSString *p) {
    if(dm_measurement_is_blank(p))setenv("DM_BLANK_FPS",[p hasSuffix:@"30"]?"30":"60",0);
    if([p hasPrefix:@"linkblank"])setenv("DM_BLANK_API","metal",0);
}
static NSDictionary *dm_measurement_names(void) { return @{@"frames":@"frames.tsv",@"threads":@"threads.tsv",@"passes":@"passes.tsv",@"heat":@"heat.tsv",@"display":@"display.tsv"}; }
static BOOL dm_measurement_inside(NSString *p,NSString *root) {
    NSString *r=[root.stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
    return [p.stringByResolvingSymlinksInPath hasPrefix:r];
}
static NSDictionary *dm_measurement_prepare(NSString *doc,NSString *profile,NSString *build,NSString *mode) {
    NSFileManager *fm=NSFileManager.defaultManager;BOOL blank=dm_measurement_is_blank(profile),trace=[profile isEqualToString:@"display"]||[profile hasPrefix:@"linkblank"],timing=[profile isEqualToString:@"timing"]||[profile isEqualToString:@"gpu"]||[profile isEqualToString:@"display"];
    NSString *session=NSUUID.UUID.UUIDString;NSString *relative=[@"Measurements" stringByAppendingPathComponent:session],*root=[doc stringByAppendingPathComponent:relative];
    NSMutableDictionary *files=[NSMutableDictionary dictionary],*external=[NSMutableDictionary dictionary];
    if((blank||timing)&&dm_measurement_inside(root,doc)&&[fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]) {
        NSDictionary *envNames=@{@"threads":@"DM_THRCPU",@"frames":@"DM_NVN_TSV",@"passes":@"DM_NVN_PASSGPU",@"heat":@"DM_HEAT",@"display":@"DM_DISPLAY_TRACE"};
        NSMutableArray *roles=[NSMutableArray arrayWithObjects:@"threads",@"heat",nil];if(trace)[roles addObject:@"display"];if(timing)[roles addObject:@"frames"];if([profile isEqualToString:@"gpu"])[roles addObject:@"passes"];
        for(NSString *role in roles) {
            NSString *rel=[relative stringByAppendingPathComponent:dm_measurement_names()[role]],*absolute=[doc stringByAppendingPathComponent:rel];
            NSString *base=[role isEqualToString:@"heat"]?rel:absolute; // DM_HEAT is Documents-relative in front_ios_heat_start
            NSString *spec=[@[@"threads",@"heat"] containsObject:role]?[base stringByAppendingString:@",10"]:base;
            NSString *key=envNames[role];setenv(key.UTF8String,spec.UTF8String,0);
            if(!strcmp(getenv(key.UTF8String),spec.UTF8String))files[role]=rel;else external[role]=@YES;
        }
        if(timing){setenv("DM_NVN_TSV_CALLS","0",0);setenv("DM_SLOWFRAME","1",0);setenv("DM_PRESENT_STAGE_EVERY",trace?"300":"1",0);}
        if(blank)dm_measurement_boot_env(profile);
    }
    NSMutableDictionary *m=[@{@"schema":@1,@"session":session,@"profile":profile,@"mode":mode?:@"boot",@"build":build?:@"unknown",@"files":files,@"external_overrides":external,@"instrumented":@(blank||timing),@"deterministic_clock":@(getenv("DM_DETCLOCK")!=NULL),@"host_start_uptime_s":@(NSProcessInfo.processInfo.systemUptime),@"thread_cpu_units":@"100_percent_equals_one_core",@"physical_input_latency_measured":@NO,@"energy_watts_measured":@NO} mutableCopy];
    m[@"present_counter_kind"]=blank?@"valid_presentedTime_callbacks":@"render_present_attempts_use_frames_for_actual_display";
    if(trace){m[@"display_trace_schema"]=@1;m[@"presentation_path"]=@"CAMetalDisplayLink_commit_Scheduled_direct_present";m[@"requested_service_hz"]=@60;m[@"requested_latency_default"]=@1;m[@"trace_is_instrumented_not_performance_score"]=@YES;}
    if(blank)m[@"configured_blank_hz"]=@(atoi(getenv("DM_BLANK_FPS")?:"60"));
    if(timing){m[@"tsv_calls"]=@(getenv("DM_NVN_TSV_CALLS")?:"unknown");m[@"present_stage_every"]=@(getenv("DM_PRESENT_STAGE_EVERY")?:"unknown");}
    NSData *data=[NSJSONSerialization dataWithJSONObject:m options:NSJSONWritingSortedKeys error:nil];
    BOOL ok=data&&[data writeToFile:[doc stringByAppendingPathComponent:@"measurement_current.json"] atomically:YES];m[@"manifest_written"]=@(ok);return m;
}
// Read only exact allowlisted files belonging to the current session. A stale or
// tampered manifest can never make sharing read a save/resource/arbitrary path.
static NSData *dm_measurement_manifest(NSString *doc) {
    NSString *p=[doc stringByAppendingPathComponent:@"measurement_current.json"];NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];
    if(![a[NSFileType] isEqualToString:NSFileTypeRegular] || [a[NSFileSize] unsignedLongLongValue]>65536 || !dm_measurement_inside(p,doc))return nil;
    return [NSData dataWithContentsOfFile:p options:NSDataReadingMappedIfSafe error:nil];
}
static NSArray<NSDictionary *> *dm_measurement_snapshot(NSString *doc,NSUInteger cap) {
    NSData *d=dm_measurement_manifest(doc);
    if(!d.length||d.length>65536)return @[];id x=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if(![x isKindOfClass:NSDictionary.class])return @[];
    NSDictionary *m=x;NSString *session=m[@"session"];if(![session isKindOfClass:NSString.class]||session.length!=36)return @[];
    NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef-"] invertedSet];if([session rangeOfCharacterFromSet:bad].location!=NSNotFound)return @[];
    NSDictionary *files=m[@"files"];if(![files isKindOfClass:NSDictionary.class])return @[];NSMutableArray *out=[NSMutableArray array];NSUInteger remaining=cap*3; // total cap, not unbounded mmap/copy
    for(NSString *role in @[@"threads",@"heat",@"display",@"frames",@"passes"]) {
        NSString *expected=[[@"Measurements" stringByAppendingPathComponent:session] stringByAppendingPathComponent:dm_measurement_names()[role]];
        if(![files[role] isKindOfClass:NSString.class]||![files[role] isEqualToString:expected])continue;
        NSString *p=[doc stringByAppendingPathComponent:expected];NSMutableDictionary *meta=[@{@"role":role,@"session":session,@"profile":m[@"profile"]?:@"unknown",@"relative_path":expected,@"snapshot_may_have_unflushed_tail":@YES} mutableCopy];
        if(!dm_measurement_inside(p,doc)||!remaining){meta[@"status"]=@"rejected_or_total_limit";[out addObject:meta];continue;}
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];if(![attrs[NSFileType] isEqualToString:NSFileTypeRegular]){meta[@"status"]=@"missing_or_not_regular";[out addObject:meta];continue;}
        uint64_t size=[attrs[NSFileSize] unsignedLongLongValue];NSUInteger n=(NSUInteger)MIN((uint64_t)MIN(cap,remaining),size);BOOL truncated=size>n;NSFileHandle *f=[NSFileHandle fileHandleForReadingAtPath:p];if(!f){meta[@"status"]=@"unreadable";[out addObject:meta];continue;}
        NSData *body=nil;@try{[f seekToFileOffset:truncated?size-n:0];body=[f readDataOfLength:n];[f closeFile];}@catch(NSException *e){(void)e;[f closeFile];}
        if(truncated){const uint8_t *b=body.bytes;NSUInteger i=0;while(i<body.length&&b[i]!='\n')i++;body=i<body.length?[body subdataWithRange:NSMakeRange(i+1,body.length-i-1)]:NSData.data;}
        if(![[NSString alloc]initWithData:body encoding:NSUTF8StringEncoding]){meta[@"status"]=@"non_utf8_rejected";[out addObject:meta];continue;}
        meta[@"status"]=@"snapshot";meta[@"source_bytes"]=@(size);meta[@"included_bytes"]=@(body.length);meta[@"truncated"]=@(truncated);meta[@"data"]=body?:NSData.data;remaining-=body.length;[out addObject:meta];
    }
    return out;
}
