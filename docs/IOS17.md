# iOS17 build notes / 构建与限制

## Prerequisites
Use an Apple-silicon Mac with Xcode, command-line tools, xcodegen and upstream Python/tool dependencies. The unsigned direct-install helper defaults to native opaque PNG icons (`DM_IOS17_ICON_MODE=png`), generated from the tracked upstream icon and declared using Apple's `CFBundleIcons` / `CFBundleIconFiles`. All game sources and resources are still compiled and linked; this is not an icon-less or partial game build. It is not an App Store/TestFlight icon submission path.

No simulator download is required for PNG icons. Optional `DM_IOS17_ICON_MODE=catalog` keeps the upstream asset catalog path, which needs a simulator runtime compatible with the selected Xcode SDK: an installed iOS17.0 runtime did NOT satisfy Xcode's SDK23C57 actool requirement in the observed catalog build. This host constraint does not change the iPhone deployment target17.0. Nothing is downloaded automatically. Follow upstream setup with your own game files/keys outside the repository; generated private inputs are not published.

1. Follow [upstream setup](../README.upstream.md) and [game-file requirements](GAME_FILES.md). Generate real r44-touch outputs; do not rename an earlier rewrite generation.
2. Generate the complete legacy ASTC pack from your own resources as described in [legacy-device instructions](LEGACY_DEVICES.md). The 8-texture probe is not a complete pack. Keep the pack separate from the IPA and preserve its matching `pack.json`.
3. Set private local environment variables (never commit them):

```sh
export DM_ROOT="$HOME/d2r-private-work"
export DM_OUT="$DM_ROOT/build/cache/dm/out/3.3.94012-r44-touch"
export DM_ASTC_PACK="$DM_ROOT/build/astc/pack"
export DM_BUNDLE_ID="your.own.bundle.identifier"
export DM_BUILD_NUMBER="YYYYMMDDNN" # replace with an unused numeric ten-digit build
bash dm/ios/build_ios17.sh
```

This invokes generation and an unsigned iOS17/A16 source build only. It deliberately does not install/launch apps, change phone settings, sign an app, or package/distribute game binaries. Use your own signing/installation process. A changed bundle ID uses a separate data container: do not uninstall the existing app or expect saves/resources to migrate automatically.

Generation may be expensive and uses private game-derived headers/art/shaders. No pre-generated substitute is shipped. Asset generation must succeed; a source/unit-test check is not proof a fully assembled game package exists.

## Known limitations
- Only iPhone14ProMax/A16 iOS17.0 has reported manual play feedback (including the1705 baseline). iOS17.x generally, other models, long sessions, act transitions and full-game completion are not certified.
- Occasional ~50ms and longer presentation intervals remain. The old log's fixed25ms drop threshold incorrectly labels normal30FPS intervals as dropped. Conditional FPS averages can omit discarded-ticket gaps. Neither should be used alone as a pass criterion.
- A request for60Hz callbacks is not a guarantee the OS delivers exactly60; device recordings/logs are still required.
- Whole-device watts and physical touch-to-photon latency are not measured here. Do not reuse upstream's different-model results as A16 evidence.
- Memory entitlements depend on signing and installation. Removing them for a free-account build may change memory limits and stability; this is not equivalence to TrollStore.
- iCloud/background-assets extensions are excluded by the free-account source-build path. Do not treat this as an App Store/TestFlight package.
- The tracked shader lock identifies the tested toolchain, not a portable precompiled shader download. See the regeneration steps below.

## Safe feedback
Report model, exactOS, source commit/build, 30/60 mode, quality, scenario and whether this is first/second entry. Redact usernames, paths and device identifiers. Do not upload raw saves, keys, assets or proprietary binaries. Keep your saves/resources and older packages.

## Shader chain integrity
After building the upstream translator from this checkout, verify the tools:
```sh
python3 dm/gfx/tools/dmsh_chain.py --check-tools
```
If your Xcode/spirv-cross/translator fingerprints differ, rebuild the translator from the tracked source first, then regenerate rather than relabel old caches:
```sh
python3 dm/gfx/tools/dmsh_chain.py --update-lock
python3 dm/gfx/tools/dmsh_chain.py --header
J=4 IOSOUT="$DM_ROOT/build/ios/dmsh_b" python3 dm/gfx/tools/dmsh_build.py \
  "$DM_ROOT/build/cache/dm/dmsh" "$DM_ROOT/build/gfx/dmsh_b"
```
The input directory must contain shaders extracted from your own game by upstream setup. All translated libraries/reflection records must match the new chain. Never rename a pre-existing b-* directory to bypass validation.

## Shell releases
Use the same release-tag source with the iOS17 shell build-input ZIP; see [NO_XCODE](NO_XCODE.md). The ZIP is not installable and contains no guest program or game-derived payloads. Guest Mach-O/plist minOS is17.0. This dynamic-guest loading route is distinct from the earlier private embedded1601 test; local reconstruction and build tests are not new A16 gameplay proof.

## Source update through1705

See [CHANGELOG](../CHANGELOG.md). The normal-play build ignores diagnostic profiles from other build identities; ordinary play does not require managing profile files. The60Hz Foundation timer decouples input/UI polling from display refresh requests, not a physical latency guarantee.

Run the asset-free contract on macOS:
```sh
sh dm/ios/tests/run_input_profile.sh
```
It creates only a disposable fixture folder and checks actual Foundation timer callbacks and build-matched profile selection. It does not operate a phone.

No full new IPA or independent full clean game build is claimed for this source update. Strict17 compile/native/source regression checks are narrower than assembled-game/device proof. Existing preview.1 ZIPs belong to their original tagged source, not1705. Build1705 from the current source with locally generated private assets; do not mix an old host ZIP with new runtime expectations.

### Checks executed for this source sync (2026-10-17)
- Six runtime translation units compile for arm64/A16 with deployment target17.0 and unguarded-availability errors enabled. This used existing privately generated headers; those headers are not published and this is not a clean full-game rebuild.
- The actual-Foundation input/profile contract passes12 checks. The previous public source predates the new contract headers; the baseline and restored-copy runner report unavailable (exit1), not an A16 runtime failure.
- Native NVN75, crop32, pacing23, deswizzle15, texture-range19 and mip303 checks pass. Depth-readonly4 is explicitly mock/no-GPU; copy-pitch invalid/overflow cases pass. Metal checks run on the Mac, not the iPhone.
- Host touch29, interaction18 and weak-loader contracts pass. Public build/shell/test script syntax passes.
- Self-contained rollback restores source and documentation on a separate copy; the patch reconstructs every changed file byte-for-byte. No new game IPA, device install, A16 gameplay run, energy reading or complete-game validation is claimed.
