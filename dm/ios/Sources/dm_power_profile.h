#pragma once
#include <stdint.h>
#include <string.h>
// Typed, local-only profile: native(default), balanced, conservative, native30, perf60.
static inline int dm_power_profile(const char *name) {
 return name && !strcmp(name,"balanced") ? 0 : name && !strcmp(name,"conservative") ? 2 : name && !strcmp(name,"native30") ? 3 : name && (!strcmp(name,"perf60") || !strcmp(name,"900p")) ? 4 : 1;
}
static inline uint64_t dm_power_dimensions(unsigned width,unsigned height,int profile) {
 if(!width || !height) return 0;
 if(profile == 0) { // balanced: 720p
  if(height <= 720) return (uint64_t)height<<32|width;
  unsigned w=(unsigned)(((uint64_t)width*720/height+4)/8*8);
  return (uint64_t)720<<32|w;
 }
 if(profile == 4) { // perf60 / 900p: capped to 900p output height while preserving aspect
  if(height <= 900) return (uint64_t)height<<32|width;
  unsigned w=(unsigned)(((uint64_t)width*900/height+4)/8*8);
  return (uint64_t)900<<32|w;
 }
 return (uint64_t)height<<32|width;
}
