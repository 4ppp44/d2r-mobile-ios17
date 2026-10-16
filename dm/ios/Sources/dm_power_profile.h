#pragma once
#include <stdint.h>
#include <string.h>
// Typed, local-only profile: native(default), balanced, conservative.
static inline int dm_power_profile(const char *name) {
 return name && !strcmp(name,"balanced") ? 0 : name && !strcmp(name,"conservative") ? 2 : name && !strcmp(name,"native30") ? 3 : 1;
}
static inline uint64_t dm_power_dimensions(unsigned width,unsigned height,int profile) {
 if(profile || height<=720 || !width || !height)return (uint64_t)height<<32|width;
 unsigned w=(unsigned)(((uint64_t)width*720/height+4)/8*8);
 return (uint64_t)720<<32|w;
}
