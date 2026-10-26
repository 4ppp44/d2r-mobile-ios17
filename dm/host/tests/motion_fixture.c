// Standalone harnesses use the real bounded recorder without linking all of diag.c.
#include "../dm_motion_store.h"
// These harnesses have no guest OE scale controller; -1 means unavailable.
__attribute__((weak)) float dm_3d_scale_cur(void) { return -1; }
