# D2R Mobile: experimental iOS17 / A16 compatibility

Unofficial game-content-free host adaptation of [jhaizhou-ops/d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile), based on v1.0.17 (9de307e), including upstream Mac reflection-copy fix1784563. Upstream history, attribution and MIT license are retained. Not an official Blizzard release or upstream promise of iOS17 support.

Includes per-encoder legacy resource declarations, bloom/system-UI snapshot protection, direct presentation after GPU Scheduled, and eco60Hz service/two-callback native30FPS policy. No frame generation.

Experimental: no claim of stutter-free gameplay, power targets or full-game stability. A roughly one-minute A16/iOS17.0 private build2026101601 log reports later33.36ms intervals but earlyp99windows up to100ms. The fixed25ms dropped-frame threshold mislabels normal30FPS. Long-session thermals/power, physical touch latency and other models/OS versions are not certified. An independent unsigned device-SDK clean build now passes with Xcode and native PNG icon packaging; it is not a new A16 gameplay or power test, and is not claimed byte-identical to the private IPA.

No IPA, game programs/resources, generated game art/shaders, ASTC payloads, keys, saves, private logs or recordings are distributed. Generate private inputs from your own legally obtained game files. Do not upload those files to issues.

[Chinese](README.zh-CN.md) | [Build and limitations](docs/IOS17.md) | [Provenance](docs/IOS17_PROVENANCE.md) | [Upstream README](README.upstream.md)

The helper performs unsigned source builds only, not signing/export/install/device launch. Signing can affect memory entitlement limits; free signing is not claimed equivalent to TrollStore. A new bundleID does not migrate saves/resources.


## Shell build-input prerelease
A source-matched iOS17 host-only build-input ZIP is distributed through Releases. It is not a playable IPA: users generate game programs and derived resources locally from their own game files with `dm/tools/d2rm_pack.py`. No game payload is distributed. See [instructions](docs/NO_XCODE.md). New guest-dylib output minimum is17.0, not upstream26.0.
