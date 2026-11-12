# D2R Mobile: experimental iOS17 / A16 host

[简体中文](README.zh-CN.md) · [Complete changelog](CHANGELOG.md) · [1202 runtime review](docs/PERFORMANCE_1202.md) · [iOS17 build notes](docs/IOS17.md) · [Upstream README](README.upstream.md)

Unofficial Darwin host and NVN-to-Metal3 adaptation of [jhaizhou-ops/d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile). Source synchronized through local integration **1.0.19 /2026111202** on 2026-11-13. A build label identifies a local test baseline; it is not a promise of a downloadable playable IPA.

## Current status

**Cold-pipeline stutter remains.** A six-minute iPhone15,3/iOS17.0 report mostly samples near60fps at3D scale0.75, but region43/frame4222 takes608.8ms:582.7ms pipeline preparation, including3 new compiles/504.4ms. Read the [full review](docs/PERFORMANCE_1202.md) before interpreting average FPS.

1202 overlaps demanded-PSO construction with prediction decoding when speculative workers are idle and prioritizes primary attachment candidates. Several measured joins still consume almost the full compile duration. Earlier region42/703ms CPU spikes were not covered; region40/~219ms non-compile stalls were not reproduced and are not declared fixed. Buffer-copy prewarm is **not included**: warm-process feasibility checks are not a cold-start benefit test. QoS expresses scheduling intent, not guaranteed P-core affinity.

## Included source

Darwin threads/synchronization, VFS/memory/audio, iOS touch controls, Metal3 translation, shader reflection and argument caching, PSO learning/prediction, dynamic resolution, generation tools and tests. MIT licensing and attribution are retained; see [LICENSE](LICENSE) and[CONTRIBUTING](CONTRIBUTING.md).

The repository excludes guest executables, RomFS, keys, saves, compiled shader libraries, IPAs and original device logs. Game-derived HUD tables and artwork are generated locally, not committed. Pipeline/hash metadata is not a shader payload. The source alone does not assemble a playable game.

## Build prerequisites and private inputs

Use an Apple Silicon Mac, full Xcode/CLI tools, xcodegen and the upstream Python/translation dependencies. Follow[game-file requirements](docs/GAME_FILES.md),[dependencies](docs/DEPENDENCIES.md), and[upstream setup](README.upstream.md) with your own matching game files and3.3.94012/r44-touch outputs outside Git. Do not relabel old rewrites or shader chains.

```sh
python3 dm/gfx/tools/dmsh_chain.py --check-tools
```

Generate the complete ASTC legacy-device pack from your own resources; a small texture probe is not a replacement. See [legacy devices](docs/LEGACY_DEVICES.md), then build:

```sh
export DM_ROOT="$HOME/d2r-private-work"
export DM_OUT="$DM_ROOT/build/cache/dm/out/3.3.94012-r44-touch"
export DM_ASTC_PACK="$DM_ROOT/build/astc/pack"
export DM_BUNDLE_ID="your.own.bundle.identifier"
export DM_BUILD_NUMBER="2026111301" # choose an unused numeric YYYYMMDDNN
bash dm/ios/build_ios17.sh
```

`build_ios17.sh` generates private tables/assets/project and compiles an unsigned arm64 iPhone host targeting17.0. It does not sign, export an IPA, install or launch. `DM_ROMFS_SRC` may select your own update RomFS; default layout and toolchain regeneration are described in[IOS17](docs/IOS17.md). PNG icons need no simulator download; optional catalog mode requires an SDK-matched runtime.

A complete clean extraction/rebuild is not claimed for this source sync. Private-workspace `scripts/build_game.sh`/retained-package tools are not shipped here. Existing preview ZIPs remain tied to their original tags, not1202; do not mix older shells with the current host/chain.

## Installation and resource management

Use a signing/install method appropriate to your device and entitlements. The private iOS17.0 tests require the relevant memory/JIT capabilities; alternate signing, other OS versions, App Store or TestFlight behavior is not certified. Changing a bundle identifier creates another data container; it does not migrate saves. Preserve older working packages, saves and resources instead of uninstalling to update.

Keep multi-GB game resources separate from the IPA and import them through the application's validation flow. The[no-Xcode route](docs/NO_XCODE.md) uses its own matched source/build inputs and still needs your own game data.

## Power, quality and diagnostics

The power-saving switch changes actual30/60fps production cadence. DRS and quality settings affect scale; compare identical scenes, modes and cache state. Worker-QoS experiments do not bind cores. The `normal` measurement profile disables extra instrumentation, **not all logging**. Startup/performance diagnostics remain active; deleting a log does not stop its producer. Instrumented GPU profiles are not unperturbed performance scores.

## Validation

```sh
make -C dm/gfx/tests run
sh dm/ios/tests/run_input_profile.sh
```

Some reflection/resource tests require local generated shader fixtures; inspect their source/setup instead of claiming an asset-free pass. Real Metal checks use the Mac GPU; mock/contract checks have narrower scope. Before 1202 delivery,20 targeted real Mac Metal modes/184 checks, the full local GFX suite, and an iOS17 retained-input build/signature/ZIP check passed. The later A16 report still found609ms stutter. See [provenance](docs/IOS17_PROVENANCE.md) for public-export validation and its limits.

## Reporting issues and history

Report exact build/commit, model/OS, FPS/quality, region, first/repeated entry, loading visibility and representative frame metrics. Redact personal paths/device identifiers; do not attach keys, game resources, saves or original device logs publicly. The[changelog](CHANGELOG.md) retains earlier versions and corrections; later device findings supersede older claims of complete fixes or core pinning. Upstream documentation is retained in`README*.upstream.md`.
