# D2R Mobile: 实验性 iOS 17 / A16 Metal 兼容层与原生运行时

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/平台-iOS%2017.0%2B%20%7C%20Apple%20A16%20Bionic-orange.svg)](docs/IOS17.zh-CN.md)

本项目是基于 [jhaizhou-ops/d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile) 的非官方实验性兼容分支，专门针对 **Apple A16 Bionic 芯片（iPhone 14 Pro / 14 Pro Max / 15 / 15 Plus）** 与 **iOS 17.0+ 系统** 进行 Metal 3 原生指令翻译与性能调优。

[English Documentation (README.md)](README.md) | [更新日志 (CHANGELOG.md)](CHANGELOG.md) | [iOS 17 说明](docs/IOS17.zh-CN.md) | [依赖说明](docs/DEPENDENCIES.zh-CN.md) | [上游项目说明](README.zh-CN.upstream.md)

---

## ❓ 按照现在 GitHub 上开源的文件，能做出来游戏吗？

> **明确结论：仅凭本仓库开源的文件，【不能】直接生成可运行的游戏 IPA。** 用户必须自行提供合法拥有的 Switch 原版游戏资产与解密密钥。

### 为什么？（架构边界与版权合规）

1. **本开源仓库包含的内容（运行环境与翻译层 / Host Runtime & Translator）**：
   - **Host 宿主系统**：基于 iOS/Darwin 的 POSIX 系统调用翻译层（线程管理、文件系统 VFS、HID 输入映射、内存管理）。
   - **NVN 转 Metal 3 图形翻译层**：完备的 NVN 图形 API 模拟（`hle_nvn.c`、`nvn_mtl.m`）、着色器管线离线反射（`nvn_refl.m`）、参数块跨 Pass 复用与投机管线预编译。
   - **DRS 动态分辨率控制器**：基于 GPU 实时真实耗时门控的 3D 渲染比例控制器。
   - **移动端自研触控 HUD**：原生虚拟摇杆、技能轮盘触控、背包/储物箱/地图原生触控界面与触感反馈。
   - **自动化验证测试集**：完全可在 Mac 本机脱机运行的图形与系统调用单元测试。

2. **本开源仓库【严禁且不包含】的内容（游戏专有版权资产与客体核心 / Proprietary Assets）**：
   - **暴雪版权游戏数据（约 15+ GB）**：包含全套音频、三维模型、贴图、关卡与文案数据的 `RomFS` 分块文件（`00-00000000.data` 至 `00-00000011.data`）。
   - **Switch 硬件解密密钥**：`prod.keys` / `title.keys`。
   - **客体原版可执行文件（Guest Binaries）**：暴雪原版 Switch ARM64 二进制文件（`main`、`subsdk*`）。

### 什么时候可以做出来游戏？
只要用户持有正版 Nintendo Switch 游戏卡带或数字版，并在合法拥有的设备上提取出 `prod.keys`、ExeFS（包含 `main`）与 RomFS 资源，**配合本仓库提供的重写工具、Metal 翻译层与打包脚本，即可完全闭环编译构建出在 iOS 17 (A16) 真机上流畅运行的游戏 IPA 安装包**。

---

## 🚀 完整构建与使用指南 (How to Use & Build)

### 1. 环境准备 (Prerequisites)

- **构建机器**：搭载 Apple Silicon (M1/M2/M3/M4) 的 Mac 电脑，推荐 macOS 14.0 或更高版本。
- **编译工具链**：安装 Xcode Command Line Tools（执行 `xcode-select --install`）或完整 Xcode 15/16。
- **Python 环境**：Python 3.10+。
- **目标真机**：iPhone 14 Pro / 14 Pro Max / 15 / 15 Plus（Apple A16 Bionic 芯片），系统需为 **iOS 17.0+**。
- **安装工具**：手机端需安装 **TrollStore（巨魔商店）**（由于 64 位翻译层需要大虚拟地址空间与内存上限扩充权限，通过巨魔安装可自动赋予必要 Entitlements）。

---

### 2. 准备 Switch 原始游戏资产

1. **提取密钥**：将 Switch 解密密钥文件放置于 `~/.switch/prod.keys`。
2. **提取游戏镜像**：从正版 Switch 导出游戏包（`.xci` 或 `.nsp`，需含更新补丁）。
3. **解包 ExeFS 与 RomFS**：
   使用 `hactool` 或 `hactoolnet` 解包：
   - 提取 `ExeFS` 分区，获得游戏原生二进制（`main`、`subsdk0`、`subsdk1` 等）。
   - 提取 `RomFS` 分区，获得游戏数据分块文件（`data/00-00000000.data` 至 `00-00000011.data`）。
4. **归档资源目录**：
   将 RomFS 解出的 `data/` 目录放置于：
   ```text
   releases/resources/D2R Mobile Resources/data/
   ```
   *(为保证 IPA 体积小巧且打包敏捷，生成的 IPA 仅约 146 MB，不内置大文件资源；资源通过外部文件夹放入手机)*。

---

### 3. 执行编译打包生成 IPA

#### 方式 A：从完整原始提取物全新编译
指定唯一的构建批次号（格式 `YYYYMMDDNN`，例如 `2026102601`）：
```bash
./scripts/build_game.sh 2026102601
```
脚本将自动完成：
1. 调用 `dm/tools/patch_nso.py` 对原版 Switch ARM64 `main` 程序进行静态重写与翻译桩注入；
2. 使用 Clang/Metal 工具链编译原生宿主运行时及 Metal 3 图形翻译层（生成 `DmIOS` 原生可执行程序）；
3. 组装 IPA 容器结构，执行 ad-hoc 签名与 ZIP CRC 校验，产出 `releases/D2R-iOS17-v1.0.18-build2026102601.ipa`。

#### 方式 B：复用已有历史包快速重编译最新 Host 翻译层
如果您已有之前成功构建的私有 IPA，只需升级最新的 Metal 翻译层与宿主修复：
```bash
D2R_RETAINED_INPUT="releases/D2R-iOS17-v1.0.18-build2026102410.ipa" ./scripts/build_game.sh 2026102601
```
脚本将直接从保留包中复用字节完全匹配的客体游戏段，仅重新编译开源宿主并快速组装新包。

---

### 4. 手机端安装与运行指南

1. **通过 TrollStore 安装 IPA**：
   - 将生成的 `.ipa` 文件通过隔空投送 (AirDrop)、iCloud 云盘或本地传输至 iPhone；
   - 在手机端点击 IPA 并选择用 **TrollStore** 打开安装；
   - *说明*：TrollStore 安装会自动注入 `com.apple.developer.kernel.extended-virtual-addressing` 与 `com.apple.developer.kernel.increased-memory-limit` 权限，避免被系统误杀。
2. **导入游戏数据资源**：
   - 在 iPhone 上打开系统自带的 **文件 (Files)** App；
   - 进入路径：`我的 iPhone -> D2R Mobile -> data/`；
   - 将之前解出的 18 个 RomFS 数据文件（`00-00000000.data` ~ `00-00000011.data`）完整复制进该 `data/` 文件夹；
   - *(可选)*：亦可导入预处理好的 ASTC 纹理包，大幅加速移动端贴图解压速度并降低瞬时显存开销。
3. **启动游戏**：
   - 点击桌面图标启动；首次运行会自动预编译着色器并进入罗格营地。

---

### 5. 移动端操作与运行配置

#### 触控操作布局
- **左侧屏幕区域**：动态虚拟摇杆，控制人物全向平滑移动。
- **右侧屏幕区域**：主攻击与技能轮盘按键，支持拖拽定向施法指示器。
- **界面辅助功能**：
  - 屏幕底栏：药水快捷腰带；
  - 屏幕右上角：小地图半透明快速切换；
  - 屏幕顶栏：快捷打开物品栏、人物属性与技能树面板。

#### 诊断与性能开关配置 (`Documents/` 目录)
通过 iOS 文件 App 在应用 `Documents/` 根目录放置纯文本文件即可动态控制：

| 配置文件 | 默认状态 | 功能说明 |
| :--- | :--- | :--- |
| `dm_sample.txt` | `10` | 主线程采样器采样周期 (ms)。写入 `0` 或 `off` 可彻底关闭后台采样信号，获取极致纯净帧率。 |
| `log_sync_profile.txt` | 环形缓冲批处理 | 写入 `baseline` 切换为每行同步 fsync 刷盘；默认使用无锁环形异步日志。 |
| `diagnostics_profile.txt`| 关闭 | 专用诊断模式（配合 `diagnostics_build.txt` 使用）。 |

---

## ⚡ 当前版本基准：1.0.18 (Build 2026102501)

当前最新代码版本包含的重大核心演进：

- **GPU 真实负载门控的 DRS (动态分辨率缩放)**：
  - 彻底淘汰盲目根据掉帧降画质的机制，接入 Metal 原生 GPU 逐帧耗时均值反馈（`nvn_gpu_recent_mean()`）；
  - 仅当近 60 帧 GPU 滚动均值超标（$\ge 16.67\text{ ms} \times 75\%$）时才触发降档；CPU 瞬时卡顿时锁死画质不降，且 GPU 负载恢复后 4 秒内迅速回升分辨率；
  - 默认 3D 渲染缩放下限从 0.55 抬升至 **0.60**，大幅消除画面模糊感。
- **投机管线预编译限速与让步调度器**：
  - 限制后台 PSO 投机编译工作线程数最多为 2 条；
  - 只要主渲染线程发起同步管线编译请求，投机工作线程立刻无条件让步挂起，彻底消除了重战斗场景下长达 180 ms+ 的前台呈现卡顿。
- **跨 Render Pass 的参数块复用**：
  - 将参数块（Argument Block）复用边界扩展至同一次提交的所有 Pass，避免每个 Pass 结束强制重新编码，自动重放 Metal 3 资源声明。
- **无锁内存池地址检索**：
  - 引入 Seqlock 偶数/奇数代际协议，使每帧数万次的内存池地址查询在稳态下实现纯无锁快速路径。

---

## 🧪 自动化测试与验证

无需真机与版权资产，可在任何搭载 Apple Silicon 的 Mac 电脑直接运行单元测试集：

```bash
# 1. 运行系统调用与 DRS 动态缩放逻辑测试 (68/68 全通过)
cd dm/host/tests && make build/t_oe && build/t_oe

# 2. 运行 NVN 转 Metal 图形状态与内存测试 (82/82 全通过)
cd dm/gfx/tests && make t_nvn && ./t_nvn

# 3. 运行 Metal 真机 PSO 预编译与像素回读测试 (10/10 模式全通过)
cd dm/gfx/tests && make t_pso_predict_dedup && ./t_pso_predict_dedup
```

---

## ⚖️ 知识产权与法律声明

- 本项目源码采用 [MIT License](LICENSE) 授权开源。
- Diablo II: Resurrected 为暴雪娱乐（Blizzard Entertainment, Inc.）之注册商标。
- Nintendo Switch 为任天堂（Nintendo Co., Ltd.）之注册商标。
- 本项目为独立的非官方开源研究与兼容性测试项目，与暴雪娱乐及任天堂无任何关联、授权或商业合作关系。
