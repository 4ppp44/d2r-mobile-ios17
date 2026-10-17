# iOS17 source provenance and verification scope

- Upstream history, MIT license and attribution retained. Base release v1.0.17 / 9de307ecaff42b3c9d45e58992c848ee89b8f6a1; checkout also includes upstream Mac reflection-copy fix17845634d71341cca1debf43ad79ac25c6a3a97a.
- Compatibility sources copied from the current tested iOS17/A16 candidate: legacy resource declarations, snapshot protection, Scheduled direct presentation and eco60Hz-service/two-callback policy. No game programs, generated art/shader payloads, ASTC, keys, saves, private logs or recordings included in this change.
- The tracked translator lock/header identify tested chain980cf43345a9; actual tools and actual regeneration must match. Cache renaming is not validation. Upstream ASTC packaging algorithm retained unchanged.
- Existing private build2026101601 targets iOS17.0/A16 and uses this compatibility implementation. The public source-only unsigned build has independently passed clean/build using the deviceSDK, minimum17.0/A16/Metal3 flags and native PNG icon resources. The preceding catalog build65 error is preserved: iOS17runtime21A328 is incompatible with SDK23C57 actool. A native packaging fixture proved BASELINE65/MODIFIED0/ROLLBACK65; all17opaque iPhone/iPad icons and bundled declarations are verified. This is not new A16 gameplay evidence.
- Native policy BASELINE1508/MODIFIED17/ROLLBACK1508 all retain nominal30FPS (60Hz service/step2), exits0/0/0. Source rollback restored pristine hashes. This is not measured phoneFPS.
- Current-device1601 sample is about one minute on A16/iOS17.0: later reported intervals33.36ms, earlyp99up to100.08ms, thermal state0. Fixed25ms dropped threshold mislabels normal30FPS. No claim of sustained watts, touch latency or full-game correctness.
- Prior regression evidence includes31 changed production sources strictly compiled foriOS17,75NVN/32crop/23pace/32realMetal presentation cases and a10-entry Mac save/re-entry test with39ordered transitions. These are limited-scope tests, not A16 certification.
- Final exact-path privacy/source-hash verification is required before publication. No private artifacts may be committed.

- Shell preview follows upstream DM_SHELL/stubs/derived-manifest separation. iOS17 shell builder uses native PNG icons, direct deviceSDK target selection and debug/source-path stripping; guest framework writer minOS/plist both17.0. Shell game-content audit and local source-matched reconstruction are separate from earlier embedded1601 device observations; see Release for exact passed gates and untested scope. No full game IPA is a public asset.

## 2026-10-17 source synchronization:1705 baseline

Runtime source is synchronized to the privately retained1.0.17/build2026101705 baseline, with public build/guest-minOS17/PNG-wrapper fixes retained. No full latest-main merge is implied. Generated c1 runtime captures, skill/item/experience tables, Gen trees and private artifacts are excluded. The1706 timeout recheck and rejected MRU2 prototype are not included.

The core NVN source SHA256 is `650d3499c13cf7961cbe78396f34cf036188e2b5d4060c13717f4bfde9a3106b`. The source-only package is not claimed byte-identical to a private IPA: public toolchain/build wrappers, regenerated assets and signing differ. New checks are compile/native contracts, not A16 power or end-to-end latency acceptance. Residual30FPS stutter and heat remain.
