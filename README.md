# D2R Mobile: experimental iOS 17 / A16 compatibility

Unofficial compatibility fork of [jhaizhou-ops/d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile), retaining upstream history, attribution and MIT license. The goal is to adapt the upstream M3 path to iOS 17, not reimplement the game or claim official Blizzard/upstream support.

## Selective upstream update — 2026-10-19 (source only)

Reviewed upstream v1.0.18 and main9393b00. Backported the merged minimap/layout lifetime fixes and audio mixing fix; independently tested the still-open PR85 timing-report correction. Retains the1705 input/render path and current private IPA, without claiming a full v1.0.18 merge, new A16 FPS/power gains or a new public release. See [imported, existing and deferred changes](docs/UPSTREAM_SYNC_20261019.md). Draft tvOS texture-pressure work is **not** applied to A16 without lifetime/correctness evidence.

## Current baseline: 1.0.17 / build 2026101705

This update synchronizes cumulative source changes through the locally selected **1705** play baseline, not1706 or unproven experimental patches.

- Retains per-encoder legacy Metal3 resource declarations, bloom/system-UI snapshot protection and direct presentation after GPU Scheduled.
- Retains the eco30 period correction and presentation-ticket identity. No frame generation; requested60Hz is not guaranteed OS callback delivery.
- Replaces the secondary input/UI `CADisplayLink` with a main-runloop60Hz `NSTimer`, independent of render30/60. This is not a hard-real-time or physical touch-latency guarantee.
- Normal play ignores stale diagnostic profiles unless `diagnostics_build.txt` matches the current build. No settings, resources or saves are deleted.
- Adds opt-in per-thread CPU-time and presentation/pass diagnostics. Normal mode does not activate the extra per-frame/thread/pass collectors.

**Experimental: residual30FPS stutter, latency and heat are not claimed fixed.** Manual1705 play feedback exists for A16/iOS17.0, not full-game certification. Other devices/17.x versions, long-session power, physical touch-to-photon latency and all scenes remain unverified. Host/mock/static checks are not A16 performance; summed GPU command durations are not utilization or whole-device watts.

## Build and distribution boundaries

**No playable IPA, proprietary game programs/resources, generated game tables/art/shaders, ASTC payloads, keys, saves, private logs or recordings are distributed.** Generate inputs locally from your own legally obtained game files; never upload them to issues.

[Chinese](README.zh-CN.md) | [Build/limitations](docs/IOS17.md) | [Changelog](CHANGELOG.md) | [Provenance](docs/IOS17_PROVENANCE.md) | [Upstream README](README.upstream.md)

The existing **preview.1** host build-input release remains tied to its original source commit; **it is not a1705 update**. This commit publishes source/docs only, does not replace existing release assets, and does not upload the private1705 IPA. Rebuild the1705 host and your private inputs according to the build notes.

Helpers do not install/launch a phone, change settings or migrate saves. Different bundle IDs use separate containers; signing/memory entitlements are not equivalent across installation methods. Keep private inputs/caches/IPAs outside the source tree and avoid multiple large staging copies.
