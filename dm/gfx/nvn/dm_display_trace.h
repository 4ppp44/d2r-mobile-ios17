#pragma once
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
typedef struct {
    uint64_t callback_id,ticket,frame;
    double callback_s,deadline_s,target_s,latency,requested_hz;
    unsigned step;
} dm_display_context;
static FILE *dm_display_trace_file;
static pthread_once_t dm_display_trace_once=PTHREAD_ONCE_INIT;
static _Atomic uint64_t dm_display_trace_rows;
static void dm_display_trace_open(void) {
    const char *p=getenv("DM_DISPLAY_TRACE");
    if(!p||!*p)return;
    dm_display_trace_file=fopen(p,"w");if(!dm_display_trace_file)return;
    fprintf(dm_display_trace_file,"event\tcallback_id\tticket\tframe\tt_s\tdeadline_s\ttarget_s\tlatency\trequested_hz\tproducer_step\ta\tb\tflags\n");fflush(dm_display_trace_file);
}
static int dm_display_trace_enabled(void) { pthread_once(&dm_display_trace_once,dm_display_trace_open);return dm_display_trace_file!=NULL; }
static void dm_display_trace_emit(const char *event,dm_display_context x,double t,double a,double b,unsigned flags) {
    if(!dm_display_trace_enabled())return;
    fprintf(dm_display_trace_file,"%s\t%llu\t%llu\t%llu\t%.9f\t%.9f\t%.9f\t%.3f\t%.3f\t%u\t%.9f\t%.9f\t%u\n",event,(unsigned long long)x.callback_id,(unsigned long long)x.ticket,(unsigned long long)x.frame,t,x.deadline_s,x.target_s,x.latency,x.requested_hz,x.step,a,b,flags);
    if(atomic_fetch_add_explicit(&dm_display_trace_rows,1,memory_order_relaxed)%60==59)fflush(dm_display_trace_file);
}
static void dm_display_trace_flush(void) { if(dm_display_trace_file)fflush(dm_display_trace_file); }
