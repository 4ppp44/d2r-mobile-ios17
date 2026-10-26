# Changelog

This log describes this experimental iOS17 fork, not upstream release promises. Build labels identify local integration baselines; they do not imply a public playable IPA.

## [1.0.18-ios17-build2026102501] — 2026-10-25

Cumulative updates across builds 2026102409, 2026102410, and 2026102501.

### Added
- **GPU-Gated Dynamic 3D Scale (DRS) Controller** (build 2026102410 & 2026102501).
  - Implemented `xbg_recent_gpu_ms` and `nvn_gpu_recent_mean()` in `hle_nvn.c`: replaced the hardcoded `-1.0` stub with real Metal per-frame GPU execution durations.
  - O(1) 60-frame rolling window calculation with 0.5 s expiration and NaN/negative rejection.
  - Controller downscales only when mean GPU time exceeds 75% of the frame budget (12.5 ms for 60 fps). When frames drop due to host CPU load while the GPU has headroom, resolution is locked and will not falsely degrade.
  - Early quality recovery: climbs one level back up every 4 seconds when GPU headroom exists, rather than waiting for 30 seconds of zero-drop windows.
  - Persistent-CPU-stall resilience and 90-second upscale retry cooldown to prevent scale oscillations.
- **Speculative Pipeline Compilation Throttling & Priority Yielding** (build 2026102501).
  - Background speculative PSO worker threads capped at 2 (`PSO_PEND_MAX_WORKERS = 2`).
  - Speculative compile workers immediately yield/pause when the presentation thread initiates a synchronous pipeline state compilation (`pso_pend_pause` / `pso_pend_resume`), eliminating multi-hundred-millisecond presentation stalls.
- **Cross-Pass Argument Block Reuse** (build 2026102409).
  - Extended argument buffer reuse across render passes within the same command submission (`ab_sub == g_sub_serial && !ab_ui_patched && memcmp`).
  - Automatically replays resource usage declarations for Metal 3 encoders across passes.

### Changed
- **Default Dynamic 3D Scale Floor Raised to 0.60** (build 2026102501).
  - Baseline floor raised from 0.55 back to 0.60 default (`S3_FLOOR_DEF = 0.60f`), eliminating blurriness reported by users.
  - Enabled by the GPU-gated controller, which prevents unnecessary descent into low-resolution states during CPU-bound scenes. 0.55 and 0.65 remain selectable via `DM_3D_SCALE_FLOOR`.

### Validation
- Unit test coverage:
  - `t_oe` test suite expanded to 68/68 passed (verifying GPU gate, early recovery, failed-upscale cooldown, and 0.60 default floor).
  - `t_nvn` test suite expanded to 82/82 passed (verifying 60-frame rolling mean, rollover arithmetic, and 0.5 s expiration).
  - `t_pso_predict_dedup` passed 10/10 modes with real Metal shader compilation and pixel readback.
- Packaged build: `releases/D2R-iOS17-v1.0.18-build2026102501.ipa` (146,077,977 bytes, SHA-256 `ee48e8c57afce22f0c6c0a4029e3ed212fe56345e59a593961fca179c12aa7c3`).

## [1.0.18-ios17-build2026102408] — 2026-10-24

Version bump to 1.0.18; the runtime source is the device-verified build 2026102406 state (the 2407/2408 labels differ only in the embedded version string).

### Added
- **Precise driver-segment constant fill** (build 2026102404). The offline reflection (`nvn_refl`) now parses `drv_reads.vec4_offsets` from the per-shader JSON and the command-encoding hot path fills only the vec4 slots a shader actually reads (constant indices, up to 10) instead of zero-filling the whole 0xA00-byte driver segment and copying 272 table rows per launch. Of the library's 6,927 shaders, 2,795 read the driver segment — all constant-indexed, 1–10 slots each. Shaders whose JSON predates the offsets fall back to whole-table fill. `t_refl` gained assertions for both paths (97/97).
- **Lock-free memory-pool address lookup** (build 2026102405, fixed in 2026102406). `mtl_addr`/`mtl_gpu_addr` previously took the global pool lock and linearly scanned every registered pool on each call (tens of thousands of calls per frame). A seqlock snapshot (`pool_snap_publish` even/odd generation protocol, `pool_snap_find` reader with generation re-check) makes steady-state lookups lock-free.
- Diagnostics switches documented in the README: `dm_sample.txt` (sampler off/interval), `diagnostics_profile.txt` gated on `diagnostics_build.txt` matching the running build, `log_sync_profile.txt`.

### Changed
- **Dynamic 3D-scale floor lowered from 0.60 to 0.55** (build 2026102403), closing the device level sweep: in heavy combat the 0.60 level still left the GPU at 18–20.5 ms against a 16.7 ms budget. The controller only descends to 0.55 when 0.60 keeps dropping frames and climbs back automatically; UI and text scale are untouched. `t_oe` grew a default-floor level-table check (55/55).
- The sideload packaging path (`build_retained_game.py`) now generates the Xcode project from a single-target spec (DmIOS only) with direct-install PNG icons via `tools/ios17_png_icons.py`. The App Store asset-catalog compilation (actool) is not part of the sideload line — on Xcode 26.3 with an iOS 17 disk-image simulator runtime it fails spuriously (`No simulator runtime version … available`), and every previously shipped sideload IPA already used plain PNG icons.

### Fixed
- **Build 2405 purple screen** (device: full-screen purple, unplayable). Root cause: the lock-free fast path returned a pool hit on first lookup, skipping `pool_res()` — which is also responsible for registering the pool buffer into the old-API bind table (`m3_bufs`) and committing it to the residency arena. With registration skipped, old-API vertex/index/compute binds all failed (three one-shot `【红】` lines in boot.txt: 老接口绑定/绘制/计算绑定). The fix requires the pool to have completed the locked slow path once (`res != 0`) before the fast path accepts it, and changes the snapshot to a fixed 1024-entry array: a `realloc` move while a lock-free reader is mid-scan is use-after-free; exceeding the cap invalidates the snapshot and everyone takes the slow path. Device verification of 2406: zero `【红】` lines.

### Validation and limitations
- Regression suites at 2406/2408: host `make run` all-green (oe 55, HID script 37, touch host 29, fs 68/51/14/13/20 classes); graphics t_nvn 75/75, t_stage_reuse real-Metal 10/10, t_refl 97/97 (with `DM_ROOT`), t_pace 35/35, t_pres_drop 40/40, t_present_crop 32/32, t_warm_shader 16/16, t_link_wait clean.
- Device: build 2403 same-route A/B measured present drops 3.54% vs the 8.4–8.8% baseline (worst 10 s window 15.3% vs 63.7%; heavy combat 58.7–60 fps; GPU p95 9.8–14.9 ms). Build 2406 confirmed the purple-screen fix (zero fatal binding lines) with per-frame submit CPU down (≈2.7 ms vs ≈5.2 ms median in that session) and GPU p95 tail improved (10.9–12.0 ms vs 11.9–14.9 ms), **but** the 2406 session ran heavier scenes at the 0.75 level for its first half (process CPU 231% vs 205%), so its headline 8.63% drop rate is not directly comparable to 2403's 3.54%; a same-route A/B remains open. Two anomalies remain unexplained and unattributed: the main-thread yield total-time accounting (33.4 s over 9.9 M yields in 2406 vs 5.6 s over 15.3 M in 2403, while the startup mega-frame is cheaper per yield in 2406) and the scene-confounded drop-rate comparison.
- Build 2405's failed device run is preserved as failure evidence; no package was installed automatically at any point.

## [1.0.17-ios17-build2026102402] — 2026-10-24

### Changed
- Guest main-thread `SleepThread(0)` polling yields normally for 32 consecutive calls, then requests 20 µs sleeps. Other SVCs, positive/negative sleeps and a >200 µs gap reset the sequence; deterministic-clock mode bypasses backoff. `DM_YIELD_BACKOFF=0` restores yielding. Actual host wake latency may exceed 20 µs.
- Predicted Metal pipeline creation uses a dedicated concurrent USER_INTERACTIVE queue. Descriptor, cache, drawing and required-pipeline wait semantics remain intact; device wait-time benefit is unmeasured.
- Diagnostics now include `pso_user.tsv` and atomic cumulative yield/backoff counters, allowing device-learned keys to be harvested for the seed manifest. The seed has not been expanded without device data; unsupported specialization kinds remain skipped.

### Validation and limitations
- New yield boundary regression passed. Real host polling completed with backoff enabled (32 yields, 208 sleeps, 6.280 ms) and disabled (31,556 yields, 6.292 ms); these runs are functional smoke, not an A16 performance comparison.
- Rebuilt prediction tests: all 8 modes passed with GPU pixel readback; warm shader 16/16, NVN 75/75, crop 32/32, pace 35/35, link wait 19/19. Host condition variable 1/1, thread lifetime 3/3, OE 55/55 passed. Actual export formatter body passed a Foundation smoke with platform readings substituted; UIKit share UI was not exercised.
- Published build2402: 145,721,488 bytes; SHA-256 `bb7ec47feb772e1f47efa74f38155d54d39c848e9049dc5f93208ce8e4b1a308`. Codesign/ZIP CRC passed; guest sections byte-identical to retained build2306. Both memory expansion entitlements remain true. The later device log is recorded under the 1.0.18 entry above; no package was installed automatically.
- Build2401 remains immutable and is superseded by2402 after correcting unproven specialization reinterpretation, counter data races and yield boundaries. Four-role evidence: `artifacts/ios17-feasibility/build2026102402-verification.json`; rollback binary: build2306.

## [1.0.17-ios17-build2026102305] — 2026-10-23

### Added
- Guest main-thread PC/backtrace sampling diagnostics enabled for device investigation:
  - Enhanced `crash_sample_self()` in `diag.c`: on iOS devices, checks for `Documents/dm_sample.txt` to override interval or disable (`0`/`off`).
  - Defaults to 10 ms interval on the guest main thread (`SIGUSR2` timer) when unconfigured, capturing program counter and frame pointer backtraces into a lock-free ring buffer directly to `stderr`/`boot.txt`.
  - Enables offline symbol aggregation with `ios17/dm/tools/sampagg.py` to identify hot C++ guest functions during 300–500 ms main-thread CPU freezes.
  - Regenerated `dm_i18n_tab.h` matching the updated `ui_text.tsv` string table.

### Validation and limitations
- Host test suites passed: `t_oe` 55/55 passed; fast graphics `t_pace` 35/35 and `t_link_wait` 19/19 passed.
- Packaged via `D2R_RETAINED_INPUT=releases/D2R-iOS17-v1.0.17-build2026102304.ipa ./scripts/build_game.sh 2026102305`.
- Published `releases/D2R-iOS17-v1.0.17-build2026102305.ipa`: 145,720,389 bytes, SHA-256 `6f89ea2f6f2a41703902d0959088f7e0ebd7ac9bfda672bb7ff60c31cbf881f5`; codesign valid, ZIP CRC verified, minimum OS 17.0, bundle ID `com.ericqin.d2r.ios17`.
