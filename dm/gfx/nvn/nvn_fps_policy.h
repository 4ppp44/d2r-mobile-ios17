#pragma once
// Explicit measurement overrides remain explicit; a profile is only a default.
static inline int nvn_fps_select(int forced, int profile, int user) {
    if (forced == 30 || forced == 60) return forced;
    if (user == 30 || profile == 30) return 30;
    return 60;
}
