# Changelog

This log describes this experimental iOS17 fork, not upstream release promises. Build labels identify local integration baselines; they do not imply a public playable IPA.

## [Unreleased] — 2026-10-19

### Fixed
- Backport upstream minimap insertion-slot compaction and widget-settling guards, including the330-check production-source regression.
- Allow Playback audio to mix with other apps without replacing existing interruption handling.
- Independently adopt open upstream PR85's finite/positive presented-interval validation and windowed-trace denominator handling; add four synthetic regressions to normal tests.

### Validation and limitations
- Strict iOS17 deployment compilation of six runtime units; existing Foundation input/profile, selected native NVN/real-Mac-Metal and host regressions pass.
- Matched source baseline / modified / rollback reproduce121 /0 /121 minimap failures and3 /0 /3 analyzer-test failures respectively.
- Selective review through upstream main9393b00 after v1.0.18; not a full release merge.1705 IPA/resources unchanged; no A16 FPS, latency, energy or thermal gain is claimed. New controls, address-space/rewrite/packaging changes and unmerged tvOS texture-lifetime work are tracked separately.
- No new playable IPA or release asset is published by this source update.

## [1.0.17-ios17-build2026101705] — 2026-10-17

### Changed
- Synchronize cumulative runtime source changes through the selected1705 baseline; keep existing public iOS17 shell/guest-minOS and PNG-icon build integration.
- Poll input/UI with a main-runloop60Hz NSTimer instead of a secondary CADisplayLink; preserve the existing touch-body behavior and render pacing separation.
- Bind opt-in diagnostic profiles to the current build number, ignoring stale settings without deleting or rewriting them.
- Retain eco30 cycle correction, presentation-ticket identity, Scheduled direct presentation and iOS17 M3 resource/snapshot compatibility.
- Add optional per-thread CPU deltas, current-session diagnostic export, presentation timing and matched blank-control source. These collectors are not performance improvements by themselves.
- Include accumulated loader weak-binding, interaction diagnostics and checked copy-pitch regression coverage; no proprietary generated tables are added.

### Validation and limitations
- Add a standalone actual-Foundation timer/profile contract test and retain native/NVN/copy/loader tests. Public source checks are recorded separately from historic private integration results.
- Local1705 remains the selected baseline after mixed1706 feedback. Do not include the1706 wait-predicate experiment or rejected MRU2 lookup trial.
- Residual stutter/heat and physical input latency are unresolved; no watts, all-device compatibility or parity with another model is claimed.
- No public1705 IPA or new shell release is produced by this source update. Existing preview.1 assets are unchanged and not source-matched to this update.

## [1.0.17-ios17-preview.1] — 2026-10-16

### Added
- Initial experimental source fork, unsigned iOS17/A16 source-build helper and native PNG icon packaging path.
- Game-content-free host build-input prerelease and iOS17 minimum version for locally generated guest frameworks.
- Upstream attribution/license, source-build instructions and explicit private-input/distribution boundaries.
