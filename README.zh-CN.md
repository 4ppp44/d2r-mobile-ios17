# D2R Mobile：iOS17 / A16 实验兼容层

[English](README.md) · [完整更新日志](CHANGELOG.md) · [1202实战复核](docs/PERFORMANCE_1202.md) · [iOS17构建说明](docs/IOS17.md) · [上游说明](README.zh-CN.upstream.md)

非官方宿主与NVN→Metal3适配分支，源自[jhaizhou-ops/d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile)。当前源码同步到本地集成标识 **1.0.19 /2026111202**，公开同步日期2026-11-13。构建号用于关联源码和私有测试，不代表GitHub提供对应可玩IPA。

## 当前状态：仍有冷编译长帧

1202在iPhone15,3、iOS17.0的约6分钟日志，多数采样接近60fps，3D比例0.75；但区域43仍有 **608.8ms** 长帧，管线准备582.7ms、新编3条504.4ms。不是已经全面流畅的版本。

- 1202改为必需PSO构建与未来预测解析重叠，主附件候选优先于备用候选；本局多次余等仍接近完整编译耗时，收益不能夸大。
- 原区域42/703ms主CPU尖峰未覆盖，尚未验收；原区域40/219ms非编译提交停顿未复现，不等于修复。
- 拷贝预热只完成热进程下的独立缓冲可行性验证，未完成冷启动收益对照，**未加入本包**。
- 本局无CRASH/红色错误记录不代表长局稳定、降温、泄漏或全游戏通关认证。QoS表达调度意图，不保证锁定大核。
- 详细帧数据、预测等待和测量限制见[实战复核](docs/PERFORMANCE_1202.md)。

## 仓库内容与边界

包含Darwin宿主（线程/同步/内存/VFS/音频）、iOS触控HUD、NVN/Metal3翻译、反射/参数块缓存、PSO学习与预测、动态分辨率、生成器和源码测试。

不分发游戏ExeFS/NSO、RomFS、密钥、存档、编译着色器、IPA或原始设备日志。宿主表头、触控技能表与美术等由生成器读取用户自己的游戏文件产生，生成结果不提交。哈希/管线键清单是元数据，不是着色器库。

本仓库单独下载后不能直接产出完整可运行游戏。请依照[游戏文件要求](docs/GAME_FILES.zh-CN.md)、[依赖](docs/DEPENDENCIES.zh-CN.md)和[上游构建流程](README.zh-CN.upstream.md)准备匹配的3.3.94012/r44-touch私有输出；不要仅重命名旧重写版本或旧着色器链。

## 从源码构建iOS17宿主

需要Apple Silicon Mac、完整Xcode及命令行工具、xcodegen和上游要求的Python/图形转换依赖。先核对工具链：

```sh
python3 dm/gfx/tools/dmsh_chain.py --check-tools
```

从自己的资源生成完整旧设备ASTC补充包，不能用少量探针贴图替代。游戏资源与IPA分开保管，见[旧设备说明](docs/LEGACY_DEVICES.zh-CN.md)。然后设置私有目录：

```sh
export DM_ROOT="$HOME/d2r-private-work"
export DM_OUT="$DM_ROOT/build/cache/dm/out/3.3.94012-r44-touch"
export DM_ASTC_PACK="$DM_ROOT/build/astc/pack"
export DM_BUNDLE_ID="your.own.bundle.identifier"
export DM_BUILD_NUMBER="2026111301" # choose an unused numeric YYYYMMDDNN
bash dm/ios/build_ios17.sh
```

`build_ios17.sh`生成资产/表头/工程并编译unsigned iPhone arm64宿主，目标iOS17.0；不自动签名、导出IPA、安装或启动。`DM_ROMFS_SRC`可显式指定自己的更新RomFS；其默认位置及完整要求见[IOS17](docs/IOS17.md)。PNG图标路径不要求下载模拟器；可选catalog模式需要与Xcode SDK匹配的运行时。

生成步骤依赖本地私有输入，本次公开同步没有验证从零重新提取全部游戏文件的完整构建。`scripts/build_game.sh`等本地归档工具不在此公开仓库中，不能照搬私有工作目录的命令。公开预览ZIP属于各自原始标签，不等于当前1202；不要混用旧壳和新链。

## 安装与资源

使用适合自己设备与系统的签名/安装流程。iOS17.0的私有测试采用具有所需内存/JIT权限的安装环境；公开源码并不保证任意签名方式、系统版本或App Store/TestFlight可用。变更bundle ID会创建独立数据容器，不会自动迁移存档。保留已有资源、存档与可用旧包，勿为更新直接卸载。

完整资源包独立放置并按应用资源校验要求导入，不将多GB资源重复嵌入IPA。[无Xcode流程](docs/NO_XCODE.zh-CN.md)是另一种源与生成输入配对方式，仍需要自己的游戏数据。

## 省电、画质与日志

省电开关控制实际30/60帧生产节拍；30帧不只是把显示回调间隔改成两次。DRS与画质选项会改变3D比例，同场景比较须固定帧率、画质、缓存状态及首次/再次进入条件。普通工作线程QoS对照不是锁核机制。

normal测量档只关闭额外细粒度采样，**不是日志总开关**；常规启动/性能诊断仍会输出。删除文件不会停止日志生产。诊断配置文件应按源码对应构建使用，保留版本信息；不要把GPU测量档当无干扰性能成绩。

## 测试与结果口径

```sh
make -C dm/gfx/tests run
sh dm/ios/tests/run_input_profile.sh
```

部分图形反射/资源测试需要按其源码提供本地生成的着色器cache；缺私有fixture不等于运行期失败，也不能伪造通过。真实Metal测试需要Mac GPU；mock/契约检查只证明相应范围。公开源码导出会单独核对新增依赖和本地回归，详见[来源记录](docs/IOS17_PROVENANCE.md)。

1202交付前：20组真实Mac Metal模式、184检查及完整GFX回归、iOS17编译/签名/ZIP校验通过。随后真机暴露609ms冷编译长帧，因此“构建成功”“Mac测试通过”均不等于A16性能验收。

## 反馈与开发

提交精确构建/源码提交、机型/OS、30或60帧、画质、区域、首次或重复进入、是否有加载遮罩及主要帧数据。先清除个人路径、设备标识等隐私；不要公开密钥、游戏资源、存档或原始设备日志。

贡献与许可见[CONTRIBUTING](CONTRIBUTING.zh-CN.md)和[MIT LICENSE](LICENSE)。上游文档保留在`README*.upstream.md`；旧版本记录在CHANGELOG中保留，但被后续真机结果推翻的“根治/锁核”结论以最新纠正为准。
