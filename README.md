# D2R Mobile: experimental iOS 17 / A16 compatibility

Unofficial compatibility fork of [jhaizhou-ops/d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile), retaining upstream history, attribution and MIT license. The goal is to adapt the upstream M3 path to iOS 17, not reimplement the game or claim official Blizzard/upstream support.

## Current baseline: 1.0.18 / build 2026102408

This update synchronizes the cumulative iOS17/A16 runtime work through the locally verified **build 2026102406** device run, and bumps the version to 1.0.18.

### Performance work in this sync (device-verified on iPhone 14 Pro Max, iOS 17.0)

- **Dynamic 3D-scale floor lowered to 0.55** (build 2026102403). In heavy combat the previous 0.60 floor still left the GPU at 18–20.5 ms against a 16.7 ms budget; the controller now descends to 0.55 only when 0.60 keeps dropping frames, and climbs back automatically. Device A/B on the same route: present drops **8.4–8.8% → 3.54%**, worst 10 s window **63.7% → 15.3%**, heavy-combat frame rate 58.7–60 fps, GPU p95 9.8–14.9 ms. UI and text scale are untouched.
- **Precise driver-segment constant fill** (build 2026102404). The command translator used to zero-fill a whole 0xA00-byte driver segment plus 272 table copies per shader launch. The offline reflection (`nvn_refl`) now records which vec4 slots each shader actually reads (`drv_reads` in the shader JSON, up to 10 constant-indexed slots); the hot path fills only those. Across the library's 6,927 shaders, 2,795 read the driver segment — all with constant indices, 1–10 slots each. Old JSON without offsets falls back to whole-table fill.
- **Lock-free pool address lookup** (build 2026102405, fixed in 2026102406). `mtl_addr`/`mtl_gpu_addr` previously took the global pool lock and linearly scanned every pool for each lookup (tens of thousands per frame). A seqlock snapshot (`pool_snap_publish`/`pool_snap_find`: even generation = complete, odd = writing) lets steady-state lookups run lock-free. Build 2405 shipped a fast path that skipped first-touch residency registration and produced a purple screen on device; 2406 requires the pool to have gone through the locked slow path once (residency set + old-API bind-table registration + arena commit) before the fast path accepts it, and the snapshot is a fixed 1024-entry array (a realloc move while a lock-free reader is mid-scan would be use-after-free; overflow invalidates the snapshot instead).
- **Device verification of 2406**: zero fatal `【红】` binding lines (the 2405 purple-screen evidence class). Submit-CPU per frame dropped vs the 2403 baseline (median ≈2.7 ms vs ≈5.2 ms in that session) and GPU p95 tail improved (10.9–12.0 ms vs 11.9–14.9 ms). The 2406 session spent its first half in heavier scenes at scale 0.75 (process CPU 231% vs 205% in the 2403 run), so the two sessions' headline drop percentages are **not** directly comparable; a same-route A/B is still the honest comparison and remains open.

### Diagnostics switches (files in the app's `Documents/`, visible in the Files app)

| File | Effect |
|---|---|
| `dm_sample.txt` | Main-thread PC/backtrace sampler. `0`/`off` disables; a number sets the interval in ms (default: on, 10 ms). The sampler signals the guest main thread every interval — turn it off (`0`) for clean performance measurements. |
| `diagnostics_profile.txt` + `diagnostics_build.txt` | Measurement profile (`timing`/`gpu`/`display`/…). Ignored — and normal play resumes — unless the build-number file matches the currently running build. |
| `log_sync_profile.txt` | `baseline` = per-line synchronous log flush; anything else = the default batched ring buffer. |

### Retained from earlier syncs

- Per-encoder legacy Metal3 resource declarations, bloom/system-UI snapshot protection and direct presentation after GPU Scheduled.
- Eco30 period correction and presentation-ticket identity. No frame generation; requested 60 Hz is not guaranteed OS callback delivery.
- Main-runloop 60 Hz `NSTimer` input/UI polling, independent of render 30/60.
- Opt-in per-thread CPU-time and presentation/pass diagnostics; normal mode does not activate extra collectors.

**Experimental: residual 30 fps stutter, latency and heat are not claimed fixed.** The 2403/2406 numbers above are from single-device runs on an iPhone 14 Pro Max (A16, iOS 17.0) under normal thermal state (level 0); other devices, long sessions and all scenes remain unverified. Host/mock/static checks are not A16 performance; summed GPU command durations are not utilization or whole-device watts.

## Build and distribution boundaries

**No playable IPA, proprietary game programs/resources, generated game tables/art/shaders, ASTC payloads, keys, saves, private logs or recordings are distributed.** Generate inputs locally from your own legally obtained game files; never upload them to issues.

[Chinese](README.zh-CN.md) | [Build/limitations](docs/IOS17.md) | [Changelog](CHANGELOG.md) | [Provenance](docs/IOS17_PROVENANCE.md) | [Upstream README](README.upstream.md)

This repository publishes source and documentation only. It does not replace existing release assets or upload private IPAs. Rebuild the host and your private inputs according to the build notes.

Helpers do not install/launch a phone, change settings or migrate saves. Different bundle IDs use separate containers; signing/memory entitlements are not equivalent across installation methods. Keep private inputs/caches/IPAs outside the source tree and avoid multiple large staging copies.
