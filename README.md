# D2R Mobile: Experimental iOS 17 / A16 Metal Compatibility Layer

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017.0%2B%20%7C%20Apple%20A16%20Bionic-orange.svg)](docs/IOS17.md)

Unofficial compatibility layer and native host runtime for [jhaizhou-ops/d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile), specifically adapted and optimized for **Apple A16 Bionic (iPhone 14 Pro / 14 Pro Max / 15 / 15 Plus)** running **iOS 17.0+**.

[中文文档 (README.zh-CN.md)](README.zh-CN.md) | [Changelog](CHANGELOG.md) | [iOS 17 Details](docs/IOS17.md) | [Dependencies](docs/DEPENDENCIES.md) | [Upstream README](README.upstream.md)

---

## ❓ Can you build a playable game solely from the files in this repository?

> **Direct Answer:** **NO.** You cannot produce a runnable game IPA solely from the files in this repository.

### Why? (Architecture & Legal Boundaries)

1. **What THIS repository provides (Open Source Host Runtime & Translators)**:
   - **Host Runtime System**: Darwin/iOS native POSIX environment translation (Threads, System Calls, VFS, Memory Management, Input/HID).
   - **NVN-to-Metal 3 Translation Layer**: Full NVN graphics implementation (`hle_nvn.c`, `nvn_mtl.m`), shader reflection (`nvn_refl.m`), argument buffer caching, and speculative pipeline state compilation.
   - **Dynamic Resolution Scaling (DRS)**: Real-time GPU timestamp-gated dynamic 3D scale controller.
   - **Custom Mobile Touch HUD**: Native touchscreen controls with virtual thumbsticks, skill buttons, map/cube overlays, and haptic feedback.
   - **Automated Verification Test Suites**: Unit and integration test suites running on macOS Apple Silicon.

2. **What this repository DOES NOT provide (Proprietary Game Assets & Guest Binaries)**:
   - **Copyrighted Game Assets (~15+ GB)**: Models, textures, audio, level data, and strings belonging to Blizzard (`RomFS` data files `00-00000000.data` ~ `00-00000011.data`).
   - **Switch Encryption Keys**: Nintendo Switch console keys (`prod.keys` / `title.keys`).
   - **Guest Game Binaries**: Original Switch ARM64 binaries (`main`, `subsdk*` from the Switch ExeFS).

### When CAN you build a playable game?
If you legally own the Nintendo Switch version of Diablo II: Resurrected and dump your own `prod.keys`, ExeFS, and RomFS assets from your console, **you can achieve a complete, closed-loop build of the game IPA** using the scripts and toolchains in this repository.

---

## 🚀 How to Use & How to Build (Complete Guide)

### 1. Prerequisites

- **Host Machine**: Mac with Apple Silicon (M1/M2/M3/M4), macOS 14.0+ recommended.
- **Xcode & Command Line Tools**: Installed via `xcode-select --install` or Xcode 15/16.
- **Python**: Python 3.10+ with standard modules.
- **Target Device**: iPhone 14 Pro, iPhone 14 Pro Max, iPhone 15, or iPhone 15 Plus (Apple A16 Bionic recommended). System: **iOS 17.0+**.
- **Installation Tool**: **TrollStore** installed on iOS 17.0 (required for JIT and increased memory limits without jailbreak).

---

### 2. Preparing Game Assets

1. **Dump Keys**: Place your Nintendo Switch `prod.keys` in `~/.switch/prod.keys` or specify its path during extraction.
2. **Dump Game Package**: Obtain your legally owned D2R Switch package (`.xci` or `.nsp` with updates).
3. **Extract ExeFS and RomFS**:
   Using `hactool` or `hactoolnet`:
   - Extract the `ExeFS` partition to obtain the game binaries (`main`, `subsdk0`, `subsdk1`, etc.).
   - Extract the `RomFS` partition to obtain the game data files (`data/00-00000000.data` through `00-00000011.data`).
4. **Organize Asset Directory**:
   Place the extracted RomFS data files into:
   ```text
   releases/resources/D2R Mobile Resources/data/
   ```
   *(To keep the installed IPA small ~146 MB, game resources are maintained separately and copied to the app's documents folder on the phone).*

---

### 3. Building the IPA

#### Option A: Full Build from Extracted Switch Inputs
Run the build script with a unique build identifier (`YYYYMMDDNN`):
```bash
./scripts/build_game.sh 2026102601
```
The script will:
1. Apply binary rewriting and translation hooks to the guest ARM64 NSO binaries via `dm/tools/patch_nso.py`.
2. Compile the Metal 3 translation layer and native iOS host app (`DmIOS`).
3. Package the native application shell, codesign ad-hoc, and output the final IPA to `releases/D2R-iOS17-v1.0.18-build2026102601.ipa`.

#### Option B: Rebuilding Host from a Retained Private IPA
If you already possess a previously verified private build and wish to update only the Metal translation layer and host runtime:
```bash
D2R_RETAINED_INPUT="releases/D2R-iOS17-v1.0.18-build2026102410.ipa" ./scripts/build_game.sh 2026102601
```
The script will extract and preserve the byte-identical guest game module from the retained IPA while cleanly recompiling and linking the latest host runtime.

---

### 4. Installation & Playing on iOS Device

1. **Install IPA via TrollStore**:
   - Transfer the generated `.ipa` to your iPhone (via AirDrop, iCloud Drive, or local server).
   - Open the IPA in **TrollStore** and tap **Install**.
   - *Why TrollStore?* It automatically applies `com.apple.developer.kernel.extended-virtual-addressing` and `com.apple.developer.kernel.increased-memory-limit` entitlements required by the 64-bit translation runtime.
2. **Place Game Data on the Phone**:
   - Open the **Files (文件)** app on iOS.
   - Navigate to: `On My iPhone (我的 iPhone) -> D2R Mobile -> data/`.
   - Copy the 18 RomFS data files (`00-00000000.data` ... `00-00000011.data`) into this `data/` folder.
   - Alternatively, place pre-packed ASTC texture packs in the game resources folder for faster texture loading and reduced memory footprint.
3. **Launch the Game**:
   - Tap the game icon on your home screen.
   - First launch will index shader libraries and load the camp scene.

---

### 5. Controls & In-Game Configuration

#### Mobile Touch HUD Layout
- **Left Thumb Area**: Floating virtual analog stick for character movement.
- **Right Thumb Area**: Primary attack and skill buttons (supports touch-and-drag directional aiming).
- **HUD Overlays**:
  - Potion pouch quick-drink slots along the bottom.
  - Interactive minimap toggle in the upper right.
  - Inventory, character stats, and skill tree tabs along the top bar.

#### Diagnostics & Tuning Switches (`Documents/` Folder)
Place plain text files in the app's `Documents/` directory (accessible via the iOS Files app):

| File | Default | Purpose / Effect |
| :--- | :--- | :--- |
| `dm_sample.txt` | `10` | CPU backtrace sampler interval in ms. Set `0` or `off` to disable background sampling for cleanest performance. |
| `log_sync_profile.txt` | Batched | Set to `baseline` for synchronous per-line logging; default uses a lock-free ring buffer. |
| `diagnostics_profile.txt` | Disabled | Diagnostic profiling mode (`gpu`, `timing`, `display`). Must be accompanied by matching `diagnostics_build.txt`. |

---

## ⚡ Current Baseline: 1.0.18 (Build 2026102501)

Key architectural advancements in the current release:

- **GPU-Gated Dynamic Resolution Scaling (DRS)**:
  - Replaced legacy heuristic downscaling with a real per-frame Metal GPU timestamp feedback loop (`nvn_gpu_recent_mean()`).
  - The controller now downscales only when the 60-frame rolling GPU mean reaches $\ge 75\%$ of the 16.67 ms frame budget.
  - Recovers image resolution within 4 seconds when GPU headroom exists, while preventing false downscaling caused by temporary CPU stalls.
  - Default 3D scale floor raised to **0.60** to maintain crisp image quality.
- **Speculative Pipeline Compilation Throttling**:
  - Background speculative PSO worker threads capped at 2.
  - Speculative workers immediately pause and yield when the main rendering thread encounters a synchronous pipeline compile request, eliminating 180 ms+ presentation stalls.
- **Cross-Pass Argument Block Reuse**:
  - Reuses Metal 3 resource argument blocks across multiple render passes within the same command buffer submission, eliminating redundant GPU encoder declarations.
- **Lock-Free Pool Address Lookup**:
  - Seqlock generation protocol (`pool_snap_publish` / `pool_snap_find`) enables thread-safe, lock-free memory pool translation.

---

## 🧪 Verification & Unit Testing

You can run the full suite of host and graphics unit tests directly on any Apple Silicon Mac without an iOS device or private game files:

```bash
# 1. Run Host OE & DRS Dynamic Scaling Tests (68/68 passed)
cd dm/host/tests && make build/t_oe && build/t_oe

# 2. Run NVN to Metal Graphics State & Memory Tests (82/82 passed)
cd dm/gfx/tests && make t_nvn && ./t_nvn

# 3. Run Real-Metal Speculative Pipeline Deduplication Tests (10/10 passed)
cd dm/gfx/tests && make t_pso_predict_dedup && ./t_pso_predict_dedup
```

---

## ⚖️ License & Notice

- Source code is licensed under the [MIT License](LICENSE).
- Diablo II: Resurrected is a registered trademark of Blizzard Entertainment, Inc.
- Nintendo Switch is a registered trademark of Nintendo Co., Ltd.
- This project is an independent open-source research and compatibility initiative; it is neither affiliated with, authorized, nor endorsed by Blizzard Entertainment or Nintendo.
