# Changelog

Source history for this experimental iOS17 fork. Build labels identify private integration baselines, not public IPA downloads. All original earlier public entries remain below; new entries through 1202 are included in full. Local `artifacts/` evidence references refer to private validation archives and are not distributed here; the public runtime summary is [PERFORMANCE_1202](docs/PERFORMANCE_1202.md).

## [Unreleased] — runtime review2026-11-13

### Validation / 真机复核
- 1202 still records a608.8ms region43 frame with582.7ms pipeline preparation and3 compiles/504.4ms. All observed prediction waits are0, but remaining-join measurements show limited overlap in several cases. No complete performance fix is claimed.
- 35 FPS samples58.1–60.0 at scale0.75; no current-boot CRASH/red marker. Original region42 CPU and region40 non-compile-submit problems remain unverified. Copy prewarm is excluded pending cold-start evidence.

### Historical corrections / 历史结论纠正
- QoS does not guarantee P-core placement. Older2905 explanations attributing complete stutter removal to core pinning or kernel punishment are withdrawn; code changes remain experimental scheduling/backpressure adjustments.
- Older “根治/彻底消除/完整闭环” wording below records the intended fix or limited local test, not full A16 runtime certification.2902 shadow classification was later contradicted by user feedback. Later1201/1202 cold-compile spikes supersede earlier claims that speculation limits eliminated hundreds-of-ms stalls.
- Host/mock/real-Mac-GPU tests, private package integrity and A16 device play are separate evidence levels. No raw device logs or private game-generated assets are published.

## [1.0.19-ios17-build2026111202] — 2026-11-12

### Changed
- 预测worker空闲、普通非merged且无待发布预热时，当前必需PSO提前构建，与后续状态解析重叠；异步失败仍同步回退。
- 当前需求发布前暂停未来领取；主附件候选优先于备用挂法，旧备用同键可提升优先级，保留精确键去重与全部绘制。

### Verification
- 20组真实Mac Metal模式184检查通过，完整GFX回归及iOS17构建/签名/CRC通过。新增overlap/priority回归原实现失败、修复后通过。
- A16实战收益尚待验证；拷贝预热未完成冷启动对照，因此未加入本包。未自动安装。详见artifacts/predict-early-20261112/REPORT.zh-CN.md。


## [1.0.19-ios17-build2026111201] — 2026-11-12

### Fixed
- 完全相同的采样器描述符重复登记时保留native sampler/RID及参数块缓存；变化时仍失效并保留在途资源生命周期。
- 将0903日志本局新增5条shader、13条PSO记录原样补入启动预热种子，覆盖区域56/60/43的已知新组合。

### Verification
- 新回归原实现失败5项，修改后真实Mac Metal/Validation 34项通过；完整GFX回归、iOS17构建、签名和CRC通过。
- 区域42主CPU703ms尖峰仍需同次调用栈；上述缓存优化尚未证明解释全部484ms提交空档。未安装手机，未宣称三类卡顿已根治。见artifacts/fix-stutters-20261112/REPORT.zh-CN.md。


## [1.0.19-ios17-build2026110903] — 2026-11-09

### Fixed
- 参数块复用使用按渲染编码器/用途的资源声明去重；新编码器及用途升级仍声明。
- 将优化开关的冷初始化分离，缓存命中路径省去大栈帧与栈保护检查。

### Verification
- 新增真实Mac Metal回归：原0902失败3项，修改后25项通过；iOS17构建、签名与CRC通过。
- 完整图形回归及证据见 artifacts/fix-0902-20261109；0903手机性能尚待实测，未宣称829ms尖峰已解决。


## [1.0.19-ios17-build2026110902] — 2026-11-09

### Changed
- 移植 D2R #226：摇杆使用独立图层、控件按需刷新、HUD 局部刷新与技能检查缓存。
- NVN 普通入口移除逐调用原子计数，显式诊断计数仍可开启。

### Fixed
- 同步等待持有对象引用并锁存信号完成结果，覆盖句柄关闭复用与信号立即清除场景。
- 移植 #183：致命崩溃先输出基础现场，详细导出超过 3 秒退出；客体线程在宿主栈执行 pthread 清理。

### Verification
- 同步七组、NVN 四模式、真实 entry.S 退出、崩溃三场景、完整图形/宿主及触控回归通过；iOS17 编译/签名/CRC 与客体字节校验通过。
- 完整结果与失败记录见 artifacts/port-four-20261109；手机性能、温度及 UIKit 外观尚待运行验证。


## [1.0.19-ios17-build2026110702] — 2026-11-07

### Changed
- 省电生产节拍由单调时钟控制，解除“两显示回调一帧”的依赖；保留回调停滞保护和60帧路径。
- 最近回调时刻使用原子访问，30帧条件等待使用相对超时。
- 追加0601相对2905仅新学到的粒子广告板shader及一条PSO，前移冷加载工作到现有预热。

### Verification
- 最终模拟节拍133项及目标回归通过；iOS17构建、签名/CRC、包内清单及资源存在校验通过。
- 0701为复核前中间产物，原字节保留；最终0702。A16稳定30帧与区域42长帧收益未测量。


## [1.0.19-ios17-build2026110601] — 2026-11-06

### Fixed
- 性能档默认帧率与显式测试覆盖分离，perf60下省电开关实际切换生产帧节拍30/60。
- 主线程持续等待使用有上限渐进睡眠，减少短周期自旋与轮询。

### Added
- 普通工作线程USER_INITIATED可选对照；默认及关键线程策略不变。

### Corrected
- 撤回QoS保证锁定P核的说法。真机降温、GPU提交量与地牢延迟尚待对照验证。


## [1.0.19-ios17-build2026102905] — 2026-10-30

正式生成已闭环验证的测试构建包，交付针对阴影移动闪烁（着色器跨阶段踩踏）与地牢 59 区 744ms 严重卡顿（实时配额超限能效核流放与翻译回压）的完整修复：

### Fixed

历史纠正：本节早先的调度因果解释和“完整根治”验收结论已撤回。以下保留代码改动历史；Mac回归不是A16性能证明。

- **多阶段着色器阶段隔离与复合 Program 缓存（`nvn_mtl.m`）**：
  - 根源：NVN `OP_BIND_PROGRAM` 回放时旧逻辑无视 `stages` 掩码直接无条件将 `S.prog` 覆盖为新对象，导致计算着色器（Stage 5）覆盖图形着色器（Stages 0–1），或独立顶点/片元着色器互相覆盖，破坏阴影渲染状态。
  - 修复：在状态结构中引入 `S.stage_prog[6]` 严格按掩码槽位分别记录，并通过 `prog_compose()` 机制基于 48 字节复合键在线性哈希表中复用合成的复合 `NvProg` 对象。同步加固前瞻预测（`pso_predict_rest`、`sdx_walk`、`defer_try`、`fz_plan`）。
- **客体主线程 Fallback QoS 提升与实时约束防流放加固（`hle_thread.c`, `hle_nvn.c`）**：
  - 根源：主线程因静态场景收敛导致 `computation` 配额压低至 6.28 ms，地牢（Area 59）突发过载突破配额被 XNU 判定超时惩罚并剥夺实时资格。主线程缺乏 Fallback QoS（QoS 0），被 Darwin 调度器流放到能效核（E-cores c0–c3）且主频压至 1.18~1.40 GHz，酿成 744ms 严重停顿。
  - 修复：主线程初始化与实时约束设置时显式配置 `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`，表达回退调度优先级意图（不保证核心绑定；原锁核解释已撤回）；在 `rt_comp_tick` 中设置 `0.4 * period_ns`（6.67 ms）保底防收缩水位，初始配额设为 `0.5 * period_ns`（8.33 ms）。
- **翻译队列扩容平抑突发回压（`hle_nvn.c`）**：
  - 将翻译队列深度 `XQ` 从 32 扩容至 128（4 倍深度），彻底消除地牢重负载下主线程在 `x_push` 频繁陷入条件等待的问题。

### Verification
- **着色器阶段隔离测试（`t_bind_stages.m`）**：在真实 Metal 管线下验证 11 项断言（含计算与渲染阶段互保、独立 VS/FS 像素着色、1000 次复合绑定稳定性、显式 unbind）100% 全部通过。
- **真实 Metal 多帧离屏阴影运动测试（`t_shadow_motion_store.m`）**：20 帧连贯位移读回，Nearest 与三缓冲在途 Linear PCF 100% PASS（0 深度/颜色错误，静止对 0 差分）。
- **全量回归套件**：GFX 单测套件 303+ 项与 Host 单测套件全部通过，Metal Debug Layer 0 错误。
- **发布构建**：使用受保护的 retained 流程生成正式测试包 `releases/D2R-iOS17-v1.0.19-build2026102905.ipa` 与硬链接 `.ip`。


## [1.0.19-ios17-build2026102904] — 2026-10-29

彻底排查并根治阴影运动闪烁的跨阶段 Program 踩踏缺陷，以及地牢 59 区主线程实时约束失控流放能效核引发的 744ms 严重卡顿掉帧：

### Fixed
- **多阶段着色器阶段隔离与复合 Program 缓存（`nvn_mtl.m`）**：
  - 根源：NVN `OP_BIND_PROGRAM` 回放时旧逻辑无视 `stages` 掩码直接无条件将 `S.prog` 覆盖为新对象，导致计算着色器（Stage 5）覆盖图形着色器（Stages 0–1），或独立顶点/片元着色器互相覆盖，破坏阴影渲染状态。
  - 修复：在状态结构中引入 `S.stage_prog[6]` 严格按掩码槽位分别记录，并通过 `prog_compose()` 机制基于 48 字节复合键在线性哈希表中复用合成的复合 `NvProg` 对象。同步加固前瞻预测（`pso_predict_rest`、`sdx_walk`、`defer_try`、`fz_plan`）。
- **客体主线程 Fallback QoS 提升与实时约束防流放加固（`hle_thread.c`, `hle_nvn.c`）**：
  - 根源：主线程因静态场景收敛导致 `computation` 配额压低至 6.28 ms，地牢（Area 59）突发过载突破配额被 XNU 判定超时惩罚并剥夺实时资格。主线程缺乏 Fallback QoS（QoS 0），被 Darwin 调度器流放到能效核（E-cores c0–c3）且主频压至 1.18~1.40 GHz，酿成 744ms 严重停顿。
  - 修复：主线程初始化与实时约束设置时显式配置 `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`，表达回退调度优先级意图（不保证核心绑定；原锁核解释已撤回）；在 `rt_comp_tick` 中设置 `0.4 * period_ns`（6.67 ms）保底防收缩水位，初始配额设为 `0.5 * period_ns`（8.33 ms）。
- **翻译队列扩容平抑突发回压（`hle_nvn.c`）**：
  - 将翻译队列深度 `XQ` 从 32 扩容至 128（4 倍深度），彻底消除地牢重负载下主线程在 `x_push` 频繁陷入条件等待的问题。

### Verification
- **着色器阶段隔离测试（`t_bind_stages.m`）**：在真实 Metal 管线下验证 11 项断言（含计算与渲染阶段互保、独立 VS/FS 像素着色、1000 次复合绑定稳定性、显式 unbind）100% 全部通过。
- **真实 Metal 多帧离屏阴影运动测试（`t_shadow_motion_store.m`）**：20 帧连贯位移读回，Nearest 与三缓冲在途 Linear PCF 100% PASS（0 深度/颜色错误，静止对 0 差分）。
- **全量回归套件**：GFX 单测套件 303+ 项与 Host 单测套件全部通过，Metal Debug Layer 0 错误。
- **发布构建**：使用受保护的 retained 流程生成 `releases/D2R-iOS17-v1.0.19-build2026102904.ipa` 与硬链接 `.ip`。遵循只读诊断与非侵扰原则，不向用户推送测试包或索取真机日志。

### Fixed
- 深度/模板默认层清除误丢其他 mip/layer 的写回；M1 真 Metal 反例从 16 个错像素恢复为 0。
- 只读附件无覆盖证明时保留内容；剪裁预扫描与可执行清除保持一致。
- 旧采样器按 GPU fence 退役，附件追踪容纳完整 10 个平面。

### Verification
- 状态/生命周期 37 项、真实 Metal Store 27 项及完整图形回归通过；iOS17 IPA 构建、签名与 CRC 通过。
- 用户反馈 build2902 阴影闪烁仍在，撤回上一轮已排除闪烁的定性。此版本尚待 iPhone 同场景验证。


## [1.0.19-ios17-build2026102902] — 2026-10-29

针对 iPhone 14 Pro Max（iOS 17.0 / Apple A16 GPU）实机测试 2901 的录屏（448 帧，鲁高因与碎石荒野）与诊断日志，完成阴影闪烁像素级时空域根因定性、根治动态分辨率 (DRS) 频繁震荡切档、并根除客体主线程 Darwin 内核调度让出惩罚大坑（慢让出 316 次累计 3.13 秒）。所有定位、优化与测试全部在 Mac 本地闭环完成：

### Fixed
- **动态分辨率 (DRS) 频繁振荡与防抖根治（`hle_oe.c`）**：诊断日志显示 DRS 短时间内在 0.75 ↔ 0.70 ↔ 0.65 剧烈振荡 6 次。根源在于 CPU 纹理解码卡顿引发掉帧触发降档后，GPU 极低的负载（9.8 ms）又立即误触发升档。修复方案：将降档 GPU 阈值从 0.75 提至 0.82；升档防抖冷静期从 15 秒翻倍至 30 秒（需连续 45 个干净采样窗）；降档保持期从 3 秒延至 5 秒；堵死掉帧期间因 GPU 空闲误升档的漏洞，强制要求 `clean == 1`（完全零掉帧）方可升档，消除画面分辨率频繁切换带来的走样与重构卡顿。
- **客体主线程 Darwin 调度时间片惩罚（Quantum Demotion）根治（`hle_thread.c`）**：诊断日志显示主线程累计发生 316 次慢让出（>2 ms），耗时高达 3134.2 ms，且单次耗时严格聚集在 10.0～10.5 ms。根源在于主线程频繁调用 `SleepThread(0)` 轮询等待，原先无条件走 `sched_yield()` 触发了 Darwin 内核的时间片惩罚机制。修复方案：实现三级自适应自旋退避算法（Adaptive Spin-Yield）——前 32 次执行 64 次 CPU `yield` 指令（硬件自旋，耗时仅 1 µs，不交出时间片）；33～96 次执行 20 µs 微休眠（`nanosleep`，耗时约 28 µs，消除 10 ms 惩罚）；>96 次才回退到 `sched_yield()`。间隔超 0.5 ms 自动重置突发计数。

### Added
- **主线程自适应让出单测（`t_main_yield.c`）**：在 host 单测套件中验证 32 次自旋让出耗时仅 1 µs、32 次微休眠耗时 956 µs、突发间隔重置机制有效（PASS）。
- **DRS 迟滞与防抖回归单测覆盖（`t_oe.c`）**：验证全掉帧期间即便 GPU 闲置也绝不升档、连续干净窗口满足后平滑升档（69/69 PASS）。

### Analyzed
- **阴影表现像素级时空域量化定性（`RPReplay_Final1793247668.MOV`）**：
  - 静止段（438～448 帧）：镜头亚像素漂移 $< 0.07$ 像素，静态阴影内部时间标准差 $\sigma = 0.332$（$\text{MAE} = 0.42$），阴影半影边缘标准差 $\sigma = 0.962$（$\text{MAE} = 0.82$），阴影像素总数（14～15 万）严格守恒。证实**无任何阴影丢失（Shadow Flickering）与无静态阴影抖动（Shadow Jittering）**。
  - 移动段（1～25 帧，330～360 帧）：半影边缘 $\text{MAE} = 6.84 \sim 7.54$。定性为**阴影边缘走样爬行（Shadow Shimmering）**，属原版无时间抗锯齿 (TAA) 的 PCF 采样在亚像素栅格移动下的固有表现，DRS 稳定后画面走样感大幅缓解。


## [1.0.19-ios17-build2026102901] — 2026-10-29

彻底根治 iPhone 14 Pro Max（iOS 17.0 / Apple A16 GPU）画面周期性实心粉屏闪烁（模 3 节拍）、多线程数据踩踏导致着色器与采样器丢失、以及硬件 GPU 看门狗超时挂起。所有定位、方案与测试全部在 Mac 本地真 Metal GPU 下闭环完成：

### Fixed
- **拦截出错命令缓冲呈现（彻底消除模 3 周期性实心粉屏）**：逐帧像素分解证实录屏中的实心粉屏（`[236, 0, 249]`）严格呈现周期 3 节拍，对应 `CAMetalLayer` 三重缓冲（`maximumDrawableCount = 3`）。在 `dm_present_schedule.h` 中加入状态拦截：当 `scheduled.status == MTLCommandBufferStatusError` 或 `scheduled.error != nil` 时立即返回，坚决不向屏幕呈现已出错或已挂起的交换链缓冲区。
- **彻底默认禁用全局同槽 LWW 合并（根治多线程状态踩踏与 GPU Hang）**：`g_lww[128]` 原为多线程并发录制命令缓冲时无锁访问的全局数组，高并发碰撞导致着色器程序与采样器句柄踩踏，引发计算/渲染程序丢失与采样器号 4095（`0xFFF`）未登记报错，进而触发硬件看门狗挂起（Fence 359/622 GPU Hang）。修复方案：`lww_enabled()` 默认关闭，`rec_k` 均走安全独立的顺序分配，消除跨线程踩踏；并在 `nvnCommandBufferBindProgram` 中按 `stages & 0xFF` 隔离槽键，杜绝计算程序与渲染程序碰撞。
- **受控直接绑定缓存与 TBDR 参数块绑定加固**：`m3_binding_cache_on()` 与 `m3_offset_cache_on()` 联动 `!opt_off()`；在 `m3_rbuf` 中严格限制仅顶点缓冲（`vertex && i >= 16`）走偏移更新 API，参数块（槽 0–15）始终完整重绑缓冲对象与偏移。

### Added
- **GPU Hang 拦截与多线程录制安全回归测试（`t_m3_hang_guard.m`）**：在真实 Metal 环境下验证错误命令缓冲拦截呈现、正常缓冲呈现、4 线程高并发录制 400 轮操作 0 丢失、以及计算/渲染程序阶段隔离（21/21 PASS）。


## [1.0.19-ios17-build2026102806] — 2026-10-28

彻底排查并根治 iPhone 14 Pro Max（iOS 17.0 / Apple A16 GPU）画面剧烈频闪（黑色对角线几何撕裂、半屏/全屏黑帧交替）与严重发热问题。所有定位与验证全部在 Mac 本地真 Metal 环境下完成：

### Fixed
- **彻底根治驱动常量段 `c2` 局部填充漏洞与未初始化内存（黑色三角撕裂主因）**：2802 引入的驱动段局部填充在 `noff > 0` 时跳过 `memset(d, 0, 0xA00)`，且用 `(off - 360) % 8 == 0` 判定 16 字节对齐的偏移，导致槽 0 与所有偶数槽位（如 slot 16 at 488）完全被跳过，着色器读到 Arena 内存池脏数据，引发非法描述符寻址、图元被剔除或返回零、GPU 内存控制器挂起。修复方案：彻底废除危险的局部填充，分配驱动段缓冲区立即 `memset(d, 0, 0xA00)` 并完整填充全部 16 个 SSBO 与 128 个贴图/采样器槽位，由外层 `dc` 块缓存与代号机制安全复用。
- **根治参数块资源追踪容量截断（`ab_m3_res[24]` 溢出导致跨通道复用漏声明）**：全库 6927 个着色器中有 238 个绑定数超过 24（最高达 38 个）。原固定容量 24 导致跨 Pass 复用时超出部分未向新通道的 `MTLRenderCommandEncoder` 重放 `useResource` 声明，在 Apple TBDR 架构下被 Tile 内存调度器丢弃，引发全屏 Quad 缺失一个三角（呈现为精准切断屏幕的 49.63% 黑色直角三角形）。修复方案：将容量扩容至 64（覆盖全库最大 38 个绑定），并增加 `ab_m3_overflow` 溢出标志，超限时安全降级为重新编码。
- **规范 `bloomq_capture` 编码器管理**：改用 `enc_r_begin()` 与 `enc_r_end()` 并自增 `g_pass.serial`，避免绕过 Metal 3 绑定缓存重置。
- **加固 `opt_off()` 兜底开关**：在跨 Pass 复用判据中增加 `!opt_off()` 约束，确保 `dm_opt=0` 时彻底切断参数块跨通道复用。

### Added
- **真 Metal 驱动段与跨通道重放单元测试（`t_c2_full.m`）**：在 M1 GPU 上验证 `c2` 全段清零、关键槽位（0、1、15、16、127、采样器 0、1、127）正确写入，并构造 32 资源（16 UBO + 16 SSBO）参数块验证跨通道无遗漏重放（20/20 PASS）。


## [1.0.19-ios17-build2026102805] — 2026-10-28

针对用户运行 2804 反馈黑多边形撕裂与闪烁更严重，复盘排查确认 2804 的整数格式符号映射反了，彻底修正类型映射：

### Fixed
- **彻底纠正顶点属性格式符号映射（根治黑多边形撕裂）**：2804 中将 `Char4Normalized` 误转为有符号 `Char4`，而第二幕骨骼蒙皮着色器声明为 `uint4`（无符号），导致真机 Metal 再次拒绝并抛出 `Cannot convert attribute from MTLAttributeFormatChar4 to an unsigned integer type`。2805 引入符号感知映射函数 `vfmt_to_int(f, ct)`，按反射签名将 `NVN_CT_UINT` 严格转为 `UChar4/UShort4/UInt4`、`NVN_CT_INT` 转为 `Char4/Short4/Int4`。在 `pso_desc` 组装时直接生效，彻底消除管线编译失败与绘制跳过。
- **根治频繁全屏频闪与双重编译卡顿**：因管线首次即编译成功并加入缓存，彻底消除了每帧反复同步尝试 2 次编译失败的主线程严重掉帧，跳过绘制导致的黑底裸露现象彻底消除。
- 采用真实报错着色器 `3deaf68fd65b5298_b.metallib`（Act 2 阴影蒙皮着色器）实测证明：`Char4` 100% 出现 Metal 拒绝报错，`UChar4` 100% 成功生成 `MTLRenderPipelineState`。


## [1.0.19-ios17-build2026102804] — 2026-10-28

针对用户在 iPhone 14 Pro Max 运行 2803 的真机诊断日志和录屏，紧急修复画面黑三角几何撕裂与额外发热：

### Fixed
- **画面黑三角撕裂修复**：日志中排查出 146 次 `Cannot convert attribute from MTLAttributeFormatChar4Normalized to int4 or uint4`（2601 中为 0 次），导致渲染管线创建失败并跳过绘制，引发网格撕裂并偶发 GPU 错误丢弃命令。在 `pso_build` 统一管线构建入口加入针对性重试：仅当原始描述符被拒时，将整数输入属性从归一化格式转换为同宽度的整数格式（如 `Char4Normalized -> Char4`、`UShort4Normalized -> UShort4`），保持位模式、偏移与步长不变并重试。增加 `t_vattr_int` 真实 Metal 单测（14 项通过）。
- **设备端默认关闭 MTLBinaryArchive 削减发热**：真机日志证实管线归档命中率不足 0.5%（命中 5 次 / 未命中 900–1200 次），却每局落盘 12 MB 二进制归档，徒增 CPU 序列化与文件 I/O 开销。在真机上默认关闭管线归档，可通过 `Documents/dm_archive=1` 开启测试。
- **真机二分总开关**：支持通过在 `Documents` 创建 `dm_opt=0` 一键关闭 2802 的四项热路径（地址解析缓存、驱动常量段缓存、绑定计划、记录侧同槽合并），便于真机进一步定位。

### Added
- `[nvn] 优化计数` 增加 `整数顶点格式重试` 计数器，真机可观测换型重试生效次数。


## [1.0.19-ios17-build2026102803] — 2026-10-28

在 2802 的七项改动上修三处：一处正确性、一处反向性能、一处可观测性。行为改动只有第一条（把一个实验项改成缺省关）。
验证口径与 2802 相同：M1 真 Metal 单元 + gfx / host 全量回归 + iOS 17 严格语法；**仍无真机数据**。

### Fixed
- 同绘制去重的判据从「状态代号」改为「记录代号」（`g_rec_epoch`，`mtl_exec` 每处理一条非绘制记录自增）。原判据漏掉
  `OP_UPDATE_UB`（`nvnCommandBufferUpdateUniformBuffer`，CPU 数据上传进 UBO）、`OP_COPY_B2B`、`OP_DISPATCH`——它们不改状态
  但改绘制读到的数据，会把两次内容不同的绘制判成相同而丢掉第二次。`t_dup_draw` 增加一条走真实回放循环的负向用例
  （屏障记录夹在两次绘制之间 → 不跳），并验证去掉自增后该用例失败。
- 同绘制去重改为**缺省关**：判据覆盖不到客体原地改同一地址的 UBO / 顶点数据。真机开关：Documents 下放内容为 `1` 的
  `dm_dup_draw` 文件（应用开了文件共享）；本机可用 `DM_NVN_DUP_DRAW=1`。
- 归档刷盘不再占提交线程：`nvn_pcache_try_render` / `try_compute` / `add_*` 改 `trylock`，拿不到锁就当未命中 / 不收录
  （计入 `busy`）；`fsync` / `rename` / 目录清理移出锁；刷盘改为「静默 30 秒」且最多重试 10 轮，不再一局里反复序列化整份归档。

### Added
- 缺省开的 `[nvn] 优化计数 至帧 N` 行（每 300 帧）：同绘制去重次数（含开关状态）、参数块新编/复用率、驱动常量段重建、
  地址解析命中、同槽合并条数与字节、归档 hits/misses/added/bypassed/busy/loaded/saved。真机上设不了 `DM_*` 环境变量，
  这是这些改动唯一可见的读数。
- `t_dup_draw` 新增 `default_off` 与 `nonstate_record_prevents_skip` 两项；`nvn_pcache_status` 增加 `busy` 字段。


## [1.0.19-ios17-build2026102802] — 2026-10-28

七项按优先级的性能改动。验证只到"本机真 Metal 单元 / 图形回归 + iOS 17 严格语法"这一层：本轮拿不到完整私有 RomFS
（`data/build_manifest.psv` 全盘缺失），Mac 完整游戏运行与 iPhone 真机数据都没有，帧率结论未验证。

### Added
- **设备本地 Metal 二进制归档** `gfx/nvn/nvn_pipeline_cache.{h,m}`：传统 Metal 3 接口（iOS 17 / A16 可用），不涉及 Metal 4 参数表。
  归档身份 = ABI 标签 + 着色器链 + GPU 名/registryID + 系统版本 + 模块表 SHA-256（不含包版本号，同源更新可复用）；落在
  `Application Support/DmPipelineCache/<身份>/pipelines.metalarc`，排除备份；临时文件 + `fsync` + 原子改名，保留上一份可用文件；
  >256 MB 或空间不足（预留 128 MB）时放弃写盘但不影响游戏；被系统拒绝的旧归档直接重建。
  接线：`pso_get` 按需编译、`pso_pend_worker` 预编、`warm_worker`（渲染 + 计算）、`cps_get`。特化函数（`bf_fn`）在 iOS 18 之前
  不能设备序列化，保守绕过；坏归档由 `FailOnBinaryArchiveMiss` 兜底（查不到就返回 nil，调用方照常编译）。
  进后台异步刷盘、终止时同步刷盘。
- **绑定计划** `NvShader::plan_dyn/plan_sta/plan_tmpl`：首次编码按反射分一次类，恒定值绑定预算进模板，每绘制只补一次
  `useResource` 声明。
- **驱动常量段块缓存** `NvShader::drv_blk[2]`：c0/c2 各 2560 字节原来**每次绘制**都 `arena_alloc` + 整段 memset + 逐槽填充；
  现在按 `(提交序号, 段依赖行代号, 资源代号)` 复用，并按"该段真正依赖哪一行"细分失效（c0 ← 存储缓冲行，c2 ← 贴图/采样器行）。
- **客体地址解析缓存** `NvShader::buf_memo[]`：uniform / 存储缓冲地址 → (缓冲, 池内偏移, GPU 地址)，键含池快照代号；
  代号在解析**之后**读取（首次解析会走 `pool_res` 并可能当场重发布快照，先读会存下过期代号）。
- **同绘制去重**（定向实例化的安全子集）：与紧邻上一次绘制逐字节相同（同管线、同参数块、同几何、同通道、中间无状态记录），
  且混合关闭、模板测试关闭、程序不写图像 / 可写存储缓冲、遮挡计数不在进行、不在通道转储 / RT 范围模式时，直接不发。
  `DM_NVN_DUP_DRAW=0` 可关（真机 A/B 用）。

### Changed
- **跨通道参数块复用改用绑定行代号**：原来每次绘制每阶段逐字节比对 `S` 的 ubo/ssbo/tex/samp/img 五行（约 3 KB），
  现在一次 64 位比较。代号只在 `state_op` 真正改动该阶段绑定行时自增，判据更强（A→B→A 会重编，不再误复用）。
- **发行 PSO 清单合并 build2601 设备实测行**：`pso_manifest.tsv` 追加 956 行（S 203 / R 753 / C 0），原有行逐字节保留、顺序不变；
  对应 2601 日志里帧 12002（265.0 ms）与帧 12003（155.3 ms）两次真实运行时编译。
- **同槽 last-write-wins 合并**（`hle_nvn.c` 录制层）：同一槽的相邻记录在没有屏障记录（屏障 / 绘制 / 拷贝 / 换通道 / 跳转 / 换段）
  的前提下，后写直接覆盖前一条，命令流更短、翻译线程回放更少；回放最终状态不变。
- 版本号 1.0.18 → 1.0.19。
### Fixed
- **打包脚本会打进上一份着色器表**：`scripts/build_retained_game.py` 不跑 `run.sh`，`Gen/dm` 里的 `shader_map.tsv` / `pso_manifest.tsv` /
  `c1_full.tsv` 一直是上一次构建的副本——第一次出 1.0.19 时包内仍是 395 行旧清单（清单合并没进包）。现在构建前从 `ios17/dm/gfx/nvn`
  同步这三份表；那一个包已删除并重出 `2026102802`，包内清单 1351 行且与源文件 SHA-256 一致。

### Validation and limitations
- 真 Metal 新增三组测试：`t_pipeline_cache`（跨进程：阶段 1 编译落盘 `misses=2 added=2 saved=2`，阶段 2 新进程 `loaded=1 hits=3 misses=1`，
  那 1 次 miss 是归档里本来没有的特化管线，返回 nil 且普通编译照常成功）、`t_args_plan`（17/17：段缓存只在依赖行变化时重建、段内容读回核对、地址缓存命中与失效）、
  `t_dup_draw`（9/9：该跳的跳、混合 / 遮挡计数 / 可写缓冲 / 中间状态记录都不跳）。
- 录制层 `t_lww` 9/9：期望值手算自命令内存里的记录序列，覆盖相邻合并、屏障阻断、不同槽、绘制阻断、换段作废。
- 图形回归 `make run` 全绿（含 `t_nvn`、`t_stage_reuse` 全部模式）；宿主回归 `make run` 全绿。
- iOS 17 严格语法：`-target arm64-apple-ios17.0 -mcpu=apple-a16 -DDM_NVN_M3=1 -DDM_LEGACY_IOS17=1 -Werror=unguarded-availability`，
  `nvn_mtl.m` / `nvn_pipeline_cache.m` / `main.m` 全 0 错误。
- **未验证**：Mac 完整游戏运行、iPhone 真机帧率。私有 RomFS 的 `data/build_manifest.psv` 已不在磁盘上，`nnMain` 在 `tact` 阶段
  直接返回（两次失败记录保留在 `artifacts/optimization-20261028/game-baseline*/`，`steady_frames=0`）。
- 每实例数据实例化（真正的粒子 / UI 实例化）没有实现：它需要设备实测出的绘制族（族标识 + 每实例输入来源），本轮无法实测，不臆造。



## [1.0.18-ios17-build2026102601] — 2026-10-26

### Changed
- Audited upstream siblings `seedds/nxnative@d50ecc1f` and `jhaizhou-ops/d2r-mobile@195ae11d` for universal stability, memory, and performance improvements compatible with iOS 17 Metal 3 / A16.
- **ARC autorelease and lock reduction** (`nxnative@5a81e13f`, `d2r-mobile@eb3fe373`):
  - Declared `arena_alloc` out-parameter as `__strong` to eliminate ARC autorelease leakage on every draw call.
  - Cached `len` inside `NvArena` struct to eliminate repeated allocation lookups.
  - Enclosed `mtl_read_texels` in an explicit `@autoreleasepool` block.
  - Replaced `pthread_mutex` with `os_unfair_lock` for `g_rmu` resource registration.
- **PSO key canonicalization** (`nxnative@2ef0a17e`):
  - Introduced `pso_key_norm` to clear blend factors for unblended targets and clear channel mask / blend enable for unformatted targets unless part of a merged pass.
  - Integrated into `pso_key_fill` and `pso_skey_parse`, eliminating up to 35% false-miss shader compilations.
- **Stamp-before-protect dirty page publishing** (`nxnative@5b0c11a4`):
  - Recorded page protection timestamp prior to applying page write protection to eliminate write-race hazards.
  - Added busy-wait retry loop in page fault handler without acquiring coarse global locks.
- **Decoupled texture staging retirement** (`nxnative@7dc250e2`):
  - Added a 128 MB streaming upload batch threshold.
  - Retired temporary texture upload buffers via `MTLCommandBuffer addCompletedHandler` rather than waiting for main render submission fences.
- **HLE system event identity binding** (`nxnative@1a93086e`):
  - Bound a 64-bit monotonically increasing identity to system events to guard against handle reuse races; properly unbind on handle closure.
- **Explicitly excluded incompatible upstream changes**:
  - `nxnative@697df758`: Metal 4 argument table (`MTL4ArgumentTable`) and hybrid command encoders (requires iOS 18 / Metal 4, breaks iOS 17 / A16 compatibility).
  - `d2r-mobile` PR #32: Unconditional draw waiting bypass (causes visible frame tearing and artifacting).
  - `d2r-mobile` PR #37 / PR #247: Unbounded CPU spin waiting (causes deadlocks and high CPU thermal throttling).
  - `d2r-mobile@87e647f5`: Shadow vertex variations.

### Validation and limitations
- Unit regressions all green:
  - `t_oe`: 68/68 passed.
  - `t_system_event`, `t_audio`, `t_audio_spsc`: passed.
  - `t_pso_predict_dedup`: 15/15 modes passed (repeat, no_future, other, merged, harvest, slot_fail, scissor, publication, schedule, running, norm_no_format, norm_invalid_blend, norm_active_blend, norm_active_mask, norm_merged).
  - `t_pso_skey`: passed.
  - `t_readback_lifetime`: 3/3 passed.
  - `t_upload_budget`: 5/5 passed.
  - `t_dirty_race`: passed.
  - `t_astc_array`: 48/48 passed.
  - `t_tex_finalize`: 15/15 passed.
  - `t_nvn`: 82/82 passed.
- Strict iOS 17 syntax check: `arm64-apple-ios17.0` target, Apple A16 architecture, `-Werror=unguarded-availability`, 0 errors.
- Real game 45-second fixed-seed windowed smoke test (`game-integrated/` vs `game-baseline/`):
  - `steady_frames`: 1,029 (baseline 1,078), `natural_performance_eligible=True`, `issues=none`.
  - `nvn_ms`: p50 2.674 -> 2.221 ms (-16.9%), p95 3.613 -> 3.155 ms (-12.7%), max 14.989 -> 9.130 ms (-39.1%).
  - `sub_cpu_ms`: p50 2.639 -> 2.201 ms (-16.6%), p95 3.516 -> 3.058 ms (-13.0%), max 12.259 -> 5.336 ms (-56.5%).
  - `upload_ms`: max 2.903 -> 1.123 ms (-61.3%).
  - `gpu_ms`: max 23.110 -> 17.959 ms (-22.3%).
- Not proven: M1 host run only; no A16 physical device measurement in this round.


## [1.0.18-ios17-build2026102501] — 2026-10-25

Cumulative updates across builds 2026102409, 2026102410, and 2026102501.

### Added
- **GPU-Gated Dynamic 3D Scale (DRS) Controller** (build 2026102410 & 2026102501).
  - Implemented `xbg_recent_gpu_ms` and `nvn_gpu_recent_mean()` in `hle_nvn.c`: replaced the hardcoded `-1.0` stub with real Metal per-frame GPU execution durations.
  - O(1) 60-frame rolling window calculation with 0.5 s expiration and NaN/negative rejection.
  - Controller downscales only when mean GPU time exceeds 75% of the frame budget (12.5 ms for 60 fps). When frames drop due to host CPU load while the GPU has headroom, resolution is locked and will not falsely degrade.
  - Early quality recovery: climbs one level back up every 4 seconds when GPU headroom exists, rather than waiting for 30 seconds of zero-drop windows.
  - Persistent-CPU-stall resilience and 90-second upscale retry cooldown to prevent scale oscillations.
- **Speculative Pipeline Compilation Throttling & Priority Yielding** (build 2026102501).
  - Background speculative PSO worker threads capped at 2 (`PSO_PEND_MAX_WORKERS = 2`).
  - Speculative compile workers immediately yield/pause when the presentation thread initiates a synchronous pipeline state compilation (`pso_pend_pause` / `pso_pend_resume`), limiting speculative contention; later1201/1202 device runs still contain hundreds-of-ms stalls.
- **Cross-Pass Argument Block Reuse** (build 2026102409).
  - Extended argument buffer reuse across render passes within the same command submission (`ab_sub == g_sub_serial && !ab_ui_patched && memcmp`).
  - Automatically replays resource usage declarations for Metal 3 encoders across passes.

### Changed
- **Default Dynamic 3D Scale Floor Raised to 0.60** (build 2026102501).
  - Baseline floor raised from 0.55 back to 0.60 default (`S3_FLOOR_DEF = 0.60f`), eliminating blurriness reported by users.
  - Enabled by the GPU-gated controller, which prevents unnecessary descent into low-resolution states during CPU-bound scenes. 0.55 and 0.65 remain selectable via `DM_3D_SCALE_FLOOR`.

### Validation
- Unit test coverage:
  - `t_oe` test suite expanded to 68/68 passed (verifying GPU gate, early recovery, failed-upscale cooldown, and 0.60 default floor).
  - `t_nvn` test suite expanded to 82/82 passed (verifying 60-frame rolling mean, rollover arithmetic, and 0.5 s expiration).
  - `t_pso_predict_dedup` passed 10/10 modes with real Metal shader compilation and pixel readback.
- Packaged build: `releases/D2R-iOS17-v1.0.18-build2026102501.ipa` (146,077,977 bytes, SHA-256 `ee48e8c57afce22f0c6c0a4029e3ed212fe56345e59a593961fca179c12aa7c3`).


## [1.0.18-ios17-build2026102408] — 2026-10-24

Version bump to 1.0.18; the runtime source is the device-verified build 2026102406 state (the 2407/2408 labels differ only in the embedded version string).

### Added
- **Precise driver-segment constant fill** (build 2026102404). The offline reflection (`nvn_refl`) now parses `drv_reads.vec4_offsets` from the per-shader JSON and the command-encoding hot path fills only the vec4 slots a shader actually reads (constant indices, up to 10) instead of zero-filling the whole 0xA00-byte driver segment and copying 272 table rows per launch. Of the library's 6,927 shaders, 2,795 read the driver segment — all constant-indexed, 1–10 slots each. Shaders whose JSON predates the offsets fall back to whole-table fill. `t_refl` gained assertions for both paths (97/97).
- **Lock-free memory-pool address lookup** (build 2026102405, fixed in 2026102406). `mtl_addr`/`mtl_gpu_addr` previously took the global pool lock and linearly scanned every registered pool on each call (tens of thousands of calls per frame). A seqlock snapshot (`pool_snap_publish` even/odd generation protocol, `pool_snap_find` reader with generation re-check) makes steady-state lookups lock-free.
- Diagnostics switches documented in the README: `dm_sample.txt` (sampler off/interval), `diagnostics_profile.txt` gated on `diagnostics_build.txt` matching the running build, `log_sync_profile.txt`.

### Changed
- **Dynamic 3D-scale floor lowered from 0.60 to 0.55** (build 2026102403), closing the device level sweep: in heavy combat the 0.60 level still left the GPU at 18–20.5 ms against a 16.7 ms budget. The controller only descends to 0.55 when 0.60 keeps dropping frames and climbs back automatically; UI and text scale are untouched. `t_oe` grew a default-floor level-table check (55/55).
- The sideload packaging path (`build_retained_game.py`) now generates the Xcode project from a single-target spec (DmIOS only) with direct-install PNG icons via `tools/ios17_png_icons.py`. The App Store asset-catalog compilation (actool) is not part of the sideload line — on Xcode 26.3 with an iOS 17 disk-image simulator runtime it fails spuriously (`No simulator runtime version … available`), and every previously shipped sideload IPA already used plain PNG icons.

### Fixed
- **Build 2405 purple screen** (device: full-screen purple, unplayable). Root cause: the lock-free fast path returned a pool hit on first lookup, skipping `pool_res()` — which is also responsible for registering the pool buffer into the old-API bind table (`m3_bufs`) and committing it to the residency arena. With registration skipped, old-API vertex/index/compute binds all failed (three one-shot `【红】` lines in boot.txt: 老接口绑定/绘制/计算绑定). The fix requires the pool to have completed the locked slow path once (`res != 0`) before the fast path accepts it, and changes the snapshot to a fixed 1024-entry array: a `realloc` move while a lock-free reader is mid-scan is use-after-free; exceeding the cap invalidates the snapshot and everyone takes the slow path. Device verification of 2406: zero `【红】` lines.

### Validation and limitations
- Regression suites at 2406/2408: host `make run` all-green (oe 55, HID script 37, touch host 29, fs 68/51/14/13/20 classes); graphics t_nvn 75/75, t_stage_reuse real-Metal 10/10, t_refl 97/97 (with `DM_ROOT`), t_pace 35/35, t_pres_drop 40/40, t_present_crop 32/32, t_warm_shader 16/16, t_link_wait clean.
- Device: build 2403 same-route A/B measured present drops 3.54% vs the 8.4–8.8% baseline (worst 10 s window 15.3% vs 63.7%; heavy combat 58.7–60 fps; GPU p95 9.8–14.9 ms). Build 2406 confirmed the purple-screen fix (zero fatal binding lines) with per-frame submit CPU down (≈2.7 ms vs ≈5.2 ms median in that session) and GPU p95 tail improved (10.9–12.0 ms vs 11.9–14.9 ms), **but** the 2406 session ran heavier scenes at the 0.75 level for its first half (process CPU 231% vs 205%), so its headline 8.63% drop rate is not directly comparable to 2403's 3.54%; a same-route A/B remains open. Two anomalies remain unexplained and unattributed: the main-thread yield total-time accounting (33.4 s over 9.9 M yields in 2406 vs 5.6 s over 15.3 M in 2403, while the startup mega-frame is cheaper per yield in 2406) and the scene-confounded drop-rate comparison.
- Build 2405's failed device run is preserved as failure evidence; no package was installed automatically at any point.


## [1.0.17-ios17-build2026102402] — 2026-10-24

### Changed
- Guest main-thread `SleepThread(0)` polling yields normally for 32 consecutive calls, then requests 20 µs sleeps. Other SVCs, positive/negative sleeps and a >200 µs gap reset the sequence; deterministic-clock mode bypasses backoff. `DM_YIELD_BACKOFF=0` restores yielding. Actual host wake latency may exceed 20 µs.
- Predicted Metal pipeline creation uses a dedicated concurrent USER_INTERACTIVE queue. Descriptor, cache, drawing and required-pipeline wait semantics remain intact; device wait-time benefit is unmeasured.
- Diagnostics now include `pso_user.tsv` and atomic cumulative yield/backoff counters, allowing device-learned keys to be harvested for the seed manifest. The seed has not been expanded without device data; unsupported specialization kinds remain skipped.

### Validation and limitations
- New yield boundary regression passed. Real host polling completed with backoff enabled (32 yields, 208 sleeps, 6.280 ms) and disabled (31,556 yields, 6.292 ms); these runs are functional smoke, not an A16 performance comparison.
- Rebuilt prediction tests: all 8 modes passed with GPU pixel readback; warm shader 16/16, NVN 75/75, crop 32/32, pace 35/35, link wait 19/19. Host condition variable 1/1, thread lifetime 3/3, OE 55/55 passed. Actual export formatter body passed a Foundation smoke with platform readings substituted; UIKit share UI was not exercised.
- Published build2402: 145,721,488 bytes; SHA-256 `bb7ec47feb772e1f47efa74f38155d54d39c848e9049dc5f93208ce8e4b1a308`. Codesign/ZIP CRC passed; guest sections byte-identical to retained build2306. Both memory expansion entitlements remain true. The later device log is recorded under the 1.0.18 entry above; no package was installed automatically.
- Build2401 remains immutable and is superseded by2402 after correcting unproven specialization reinterpretation, counter data races and yield boundaries. Four-role evidence: `artifacts/ios17-feasibility/build2026102402-verification.json`; rollback binary: build2306.


## [1.0.17-ios17-build2026102305] — 2026-10-23

### Added
- Guest main-thread PC/backtrace sampling diagnostics enabled for device investigation:
  - Enhanced `crash_sample_self()` in `diag.c`: on iOS devices, checks for `Documents/dm_sample.txt` to override interval or disable (`0`/`off`).
  - Defaults to 10 ms interval on the guest main thread (`SIGUSR2` timer) when unconfigured, capturing program counter and frame pointer backtraces into a lock-free ring buffer directly to `stderr`/`boot.txt`.
  - Enables offline symbol aggregation with `ios17/dm/tools/sampagg.py` to identify hot C++ guest functions during 300–500 ms main-thread CPU freezes.
  - Regenerated `dm_i18n_tab.h` matching the updated `ui_text.tsv` string table.

### Validation and limitations
- Host test suites passed: `t_oe` 55/55 passed; fast graphics `t_pace` 35/35 and `t_link_wait` 19/19 passed.
- Packaged via `D2R_RETAINED_INPUT=releases/D2R-iOS17-v1.0.17-build2026102304.ipa ./scripts/build_game.sh 2026102305`.
- Published `releases/D2R-iOS17-v1.0.17-build2026102305.ipa`: 145,720,389 bytes, SHA-256 `6f89ea2f6f2a41703902d0959088f7e0ebd7ac9bfda672bb7ff60c31cbf881f5`; codesign valid, ZIP CRC verified, minimum OS 17.0, bundle ID `com.ericqin.d2r.ios17`.

## [1.0.17-ios17-build2026102304] — 2026-10-23

### Changed
- Synced the applicable upstream iPhone skill/control UI from `b811b90172f4eb40ec1bc89d903308e0c5ab88d0`: native socket/button/joystick art, silver skill silhouettes, immediate held-state feedback, bounded phone/tablet fan geometry, safe-bottom handling, and release/cancel-safe skill-set switching. Existing iOS17 input timing and display pacing remain in place.
- Removed build 2303's incomplete Mac hover consumer and Spanish monster-resistance formatting as requested. The stepped 5120 → 4864 MiB guest-address reservation fallback remains.
- Added long-frame attribution for guest main-thread yield/block deltas and separated logging producer, background-file, fsync, mirror and client counters. This changes diagnostics only; it does not tune scheduling or claim to fix the observed CPU-heavy freezes.

### Build 2303 device finding
- The current boot contains 14 unobscured in-game rows ≥100 ms outside lifecycle/loading categories. Each spends at least 79.538% of wall time in main-thread CPU. Representative frames: 2960 = 485.6 ms wall / 461.1 ms main CPU; 4995 = 412.2 / 386.3 ms; 5773 = 519.6 / 516.8 ms. Their queue wait and pipeline/library creation are zero; GPU span is 10.1–12.6 ms. Frame 1105's 26,036.7 ms spans explicit background/foreground events and is not an active gameplay freeze. Evidence: `artifacts/stutter-2303-20261023/`.

### Validation and limitations
- Verified `verify_findings.py`: 1,639 field assertions, current boot only. Touch UI: `t_touch_controls` 48/48 cases and 4,463/4,463 checks; `t_joy_travel` 48 checks; `t_skill_aim` 85/85; layout-options and native-art capture checks passed. Thread regressions `t_condvar`, `t_condvar_old`, `t_thread_leak` passed. Graphics regressions `t_nvn` 75/75, `t_pres_drop` 40/40, `t_link_wait` 19/19 passed. Mac touch rollback compatibility `t_touch_mac` 29/29 passed.
- Published `releases/D2R-iOS17-v1.0.17-build2026102304.ipa`: 145,719,881 bytes, SHA-256 `e12cd6b0565dfcb5f1b8c4bd2210a2634df50e0b3b56174c5630f4a54a8fb96c`; codesign valid, ZIP CRC pass, minimum iOS 17.0, 7,212 metallibs, retained guest sections byte-identical to build 2303.
- Device performance remains unverified. The exact CPU-heavy function is unresolved; the new counters separate guest synchronization/yielding from residual CPU work in the next device log. The new native skill/control skin and default portal-arc swap position are packaged, but the optional alternate swap-position row is absent because the available private resource directory lacks the original `data/build_manifest.psv`; the stale generated RomFS overlay was not rewritten or falsely described as complete.


## [1.0.17-ios17-build2026102303] — 2026-10-23

### Added & Changed
- Upstream v2.0 portability and stability sync:
  - In `dm/host/hle_svc.c`, ported stepped address space reservation retry from upstream v2.0: starts at 5120 MiB and steps down by 128 MiB (floor 4864 MiB, guaranteeing 1 GB alias+stack + 3728 MB heap) on devices where virtual memory allocation limits return `ENOMEM`, preventing launch aborts on free/non-extended developer provisioning profiles.
  - In `dm/host/touch_mac.c` and `dm/host/dm_cursor.c`, ported cursor hover tracking (`dm_ui_mouse_hover_now`) and hover queue handling without snapping to adjacent cells.
  - In `dm/host/diag.c`, ported Spanish monster resistance label formatting (`lbes` abbreviations and space formatting) in `monres_on_setinfo` when item annotations are enabled.
  - Preserved fork-specific performance optimizations: `dm_uiscreen_panel()` 3D scale protection during in-game panel inspection, nonblocking funopen long-frame logging, and ProMotion 120Hz display link mode 2 pacing.

### Validation and limitations
- Host unit test suite: all 13 targets pass (`t_thread_leak`, `t_loader_weak`, `t_rift_clock`, `t_rift_next`, `t_map_diag`, `t_warp_diag`, `t_interaction_diag`, `t_textbox`, `mode_scan`, `native_write_scan`, `widget_cache_scan`, etc.).
- Real Metal graphics test suite: `t_rt_store_overwrite` (23/23), `t_defer_chain` (59/59), `t_fuse_check` (10/10), `t_pace` (35/35), `t_link_wait` (19/19), `t_rt_clear_fold` (44/44), `t_astc_array` (48/48) all pass.
- Build packaging via `scripts/build_game.sh 2026102303` with retained build 2302 input: codesign valid (adhoc), ZIP CRC verified, minOS 17.0, embedded guest sections byte-identical with `R44_GATE.json`. Published to `releases/D2R-iOS17-v1.0.17-build2026102303.ipa` (SHA-256: `027e1595560847643cda3361f4a905e003569adc8130a99a979686023c83f26c`, size: 145,710,218 bytes).


## [1.0.17-ios17-build2026102302] — 2026-10-23

### Fixed
- In `dm/gfx/nvn/nvn_mtl.m`, fixed deferral safety under RenderTarget overwrite (`SDX_OVERWRITE`):
  - In `defer_pre()`, added check for `SDX_OVERWRITE` alongside `SDX_CLEAR`: if an attachment is overwritten by `ClearTexture` before $Q$, pass $P$ is not deferred past that overwrite, preventing incorrect render ordering.
  - In `sdx_walk` (`OP_CLEAR_TEX`), initialized `rtseq` to `SDX_NONE` rather than 0, preventing unintended fallthrough to `g_sdx_op[0]` dereferencing in lookahead pre-screening.
  - In `sdx_clear_tex_full()`, guarded newly created textures during submit indexing prior to Metal texture allocation: uncompressed 2D textures qualify for `SDX_OVERWRITE` statically via `!fmt_compressed`, only querying `mt.usage` if `mt` has already been realized in `serial_get`.

### Validation and limitations
- Verified regression suites on Apple M1: `t_rt_store_overwrite` 23/23 pass (`MTL_DEBUG_LAYER=1`), `t_defer_chain` 59/59 pass, `t_fuse_check` 10/10 pass, `t_reorder_chain` 155/155 pass, `t_rt_clear_fold` 44/44 pass.
- Build packaging via `scripts/build_game.sh 2026102302` with retained build 2301 input: codesign valid (adhoc), ZIP CRC verified, minOS 17.0, embedded guest sections byte-identical with `R44_GATE.json`. Published to `releases/D2R-iOS17-v1.0.17-build2026102302.ipa` (SHA-256: `c5a7e448654ffded3d640439e9f48f1f36ed991752d8fe76744292f1a083580b`, size: 145,704,052 bytes).


## [1.0.17-ios17-build2026102301] — 2026-10-23

### Changed
- In `dm/gfx/nvn/nvn_mtl.m`, added render target Store/Load lifecycle elimination for whole-mip `nvnClearTexture` / `clear_tex_cmd`: when a render target texture is cleared entirely before subsequent reads or samples, the redundant store action and writeback bytes from its prior render pass are folded. If the texture is not sampled by intermediate commands, this eliminates unneeded DRAM roundtrips on TBDR architectures.
- In `dm/gfx/nvn/nvn_mtl.m`, enriched per-pass GPU diagnostics (`passgpu`):
  - Added color attachment 0 texture serial (`c0_ser`), depth/stencil texture serial (`d_ser`), and fragment shader key (`fs_key`) to `pg_meta`, `g_pg_st`, and the per-pass TSV logging.
  - Fixed the in-app top-5 channel mean calculation: the divisor now accurately uses the elapsed frames since frame 300 (`double frames = p->frame > 300 ? (double)(p->frame - 300) : 1.0;`), correcting the per-frame channel cost reporting.
- Updated `tools/passgpu_top.py` and added `dm/gfx/tests/test_passgpu_top.py`: provides CLI and Python inspection of the top-5 heaviest passes broken down by render target identity and fragment shader hash.

### Validation and limitations
- Added new real-Metal regression suite `dm/gfx/tests/t_rt_store_overwrite.m`: 23/23 checks pass with `MTL_DEBUG_LAYER=1` on Apple M1. Tests verify store folding on whole-texture clear, conservative preservation on partial clears, mip clears, format-view clears, depth/stencil clears, copy targets, and sampled textures.
- Added new passgpu lifetime regression suite `dm/gfx/tests/t_pg_lifetime.m`: 8/8 real Metal checks pass, verifying zero memory leaks over command buffer submissions, per-pass timing accuracy, attachment serials, and shader key tracking.
- Validated `test_passgpu_top.py`: 11/11 tests pass.
- Regressions pass on Apple M1: `t_rt_clear_fold` 44/44, `t_nvn` 75/75, `t_pace` 35/35, `t_link_wait` 19/19, `t_pres_drop` 40/40, `t_tex_finalize` 15/15, `t_warm_shader` 16/16, `t_astc_array` 48/48, `t_pso_predict_dedup` (all 8 modes: repeat, no_future, other, merged, harvest, slot_fail, scissor, publication) pass, `t_stage_reuse` (all 7 modes: shared, changed, ubo, new_encoder, dirty, aba, epoch) pass.
- Build packaging via `scripts/build_game.sh 2026102301` with byte-verified retained build 2206 input: codesign valid (adhoc), ZIP CRC verified, minOS 17.0, embedded guest sections (`main`, `sdk`) byte-identical with `R44_GATE.json`. Published to `releases/D2R-iOS17-v1.0.17-build2026102301.ipa` (SHA-256: `20b732fbfe5b61b62e65900a4ec0b984e1b650499c799ae283f3c6487fa5cd43`, size: 145,703,688 bytes).
- Full-screen post-processing optimization investigation: identified passes #21 (1.75 ms, 1074x495), #17 (0.82 ms), #25 (0.45 ms), #19 (0.32 ms), #1 (0.32 ms) as post-processing/tone-mapping/compositing chains. Fusing or eliminating them unconditionally without golden recapture on device alters visual fidelity or breaks tone curve/bloom/UI blend. Retained native rendering path and provided diagnostic identification for future safe profiling.


## [1.0.17-ios17-build2026102206] — 2026-10-22

### Changed
- In `dm/gfx/nvn/nvn_mtl.m`, changed the display link pacing mode default on ProMotion devices (`mtl_display_refresh() >= 100.0`) from mode 1 (60 Hz cadence) to mode 2 (120 Hz display link service with step=2 frame consumption). When a frame finishes slightly past its 16.67 ms window (e.g., 17–19 ms), mode 2 allows presentation at the next 120 Hz tick (~25.0 ms) instead of quantizing to the 60 Hz tick (~33.36 ms), reducing late-frame presentation penalty. Non-ProMotion screens (< 100 Hz) retain mode 1 as default, with automatic fallback protection preventing 60 Hz screens from dropping to 30 fps if mode 2 is selected. Explicit `DM_PRESENT_LINK` overrides remain honored.
- In `dm/ios/Sources/dm_power_profile.h` and `dm/ios/Sources/main.m`, added profile `perf60` (alias `900p`). When selected via `render_profile.txt` or `DM_POWER_PROFILE=perf60`, the output resolution is capped to 900p height while strictly preserving the device screen aspect ratio (e.g. 1952x900 on 19.5:9 screens), targeting 60 FPS. Default remains native resolution (`DM_POWER_PROFILE=native`), preserving UI and text crispness as requested.

### Validation and limitations
- Host and graphics regressions on Apple M1: `t_pace` 35/35 pass, `t_link_wait` 19/19 pass (including mode 1 60fps, mode 2 120Hz step=2, timeout safety margins), `t_oe` 49/49 pass.
- Build packaging via `scripts/build_game.sh 2026102206` with byte-verified retained build 2205 input: codesign valid (adhoc), ZIP CRC verified, minOS 17.0, embedded guest sections (`main`, `sdk`) byte-identical with `R44_GATE.json`. Published to `releases/D2R-iOS17-v1.0.17-build2026102206.ipa` (SHA-256: `80cbc69e385bb6cd55d899a891ef500ba8a10148ca36721a42b9c3b599110c61`, size: 145,703,239 bytes).
- Tradeoff boundary: The game engine creates both its UI layer and Final Result composite render target at the output resolution (`renderer+0xee88/0xee8c`). Consequently, lowering output resolution to 900p will scale UI and text by ~1.43x on iPhone 14 Pro Max screen (2796x1290), resulting in softer UI text. To honor the requirement of keeping UI sharp, native output resolution remains the default, while `perf60` is selectable via `render_profile.txt`.


## [1.0.17-ios17-build2026102205] — 2026-10-22

### Changed
- In `dm/gfx/nvn/nvn_mtl.m`, a pending whole-attachment clear followed immediately by an exact same-target `SetRenderTargets` is no longer encoded as its own clear-only render pass. The clear is carried into the next draw pass as `MTLLoadActionClear`, removing one full-attachment store plus the following pass's load. Nothing is reordered: at the second `SetRenderTargets` the clear is still unencoded, and any non-state operation, another target set, frame-freeze/AB measurement, hoist/fuse/defer state, or a first draw that samples an attachment takes the original `rp_flush` path.
- In the same file, a clear-only pass on a packed `Depth32Float_Stencil8` target now attaches only the plane it clears: a depth-only clear omits the stencil attachment and a stencil-only clear omits the depth attachment, so the untouched plane is neither loaded nor stored. Non-packed formats and `DM_NVN_TBDR=0` keep the previous both-plane path.

### Validation and limitations
- New real-Metal regression `t_rt_clear_fold` (production `mtl_exec` replay, `MTL_DEBUG_LAYER=1`, Apple M1): 44/44 with the optimization and 44/44 with `DM_NVN_TBDR=0`; the preserved pre-change source fails 6/44. It asserts pass counts, Load/Store byte ledgers and read-back pixels for exact same-target fold, different target/view rejection, a copy ordering hazard, submit-only clears with no draw, sampling an unrelated texture vs sampling the cleared attachment, and both packed D32S8 single-plane clears.
- Graphics regressions on Apple M1: `t_nvn` 75/75, `t_rt_range` 19/19, `t_rt_range_shape` 19/19, `t_rt_srgb_view` 14/14, `t_rt_depth_ro` 4/4, `t_zskip` 38/38, `t_xv` 21/21, `t_defer_chain` 59/59, `t_fuse_check` 10/10, `t_mip_extent` 303/303, `t_present_crop` 32/32, `t_reorder_chain` 155/155, `t_astc_array` 48/48, `t_pace` 35/35, `t_pres_drop` 40/40, `t_link_wait` 19/19, `t_tex_finalize` 15/15, `t_warm_shader` 16/16. `t_refl` (9/54) and `t_rt_range_ro` (exit 134) still need absent private reflection fixtures; this patch does not change them.
- Build packaging via `scripts/build_game.sh 2026102205` with byte-verified retained build 2202 input: codesign valid (adhoc), ZIP CRC verified, minOS 17.0, 7,212 metallibs, embedded guest sections (`main`, `sdk`) byte-identical with `R44_GATE.json`. Published to `releases/D2R-iOS17-v1.0.17-build2026102205.ipa` (SHA-256: `125f22b747c5584a8fc6c4f6435e0c385d154cde4bb423a3cad318b610168fdb`, size: 145,702,947 bytes).
- Release housekeeping: build 2026102204 was an identical-code predecessor (only its build string and ad-hoc signature differ; all Mach-O segments except `__LINKEDIT` are byte-identical to 2205), so its IPA, sidecar, metadata directory and staging copy were removed after re-hashing each to `d1befbf3…74973`. Nothing under `releases/resources/`, `source/`, `work/data/`, the toolchain or the current candidate was touched. Separately, `releases/D2R-iOS17-v1.0.17-build2026102203.ip` was renamed to `.ipa` with unchanged bytes (`13c2ea62…72c2`); all six retained release sidecars now match their files by size and SHA-256.
- No device installation or A16 acceptance. The M1 result does not establish an A16 bandwidth or frame-time gain, and how often D2R actually re-sets identical targets right after a whole-attachment clear is not measured. Evidence: `artifacts/perf-clear-20261022/RESULT.json`. Copy-only rollback verified: `sh artifacts/ios17-feasibility/ROLLBACK.sh --perf-clear20261022-copy <NEW_DIR_OUTSIDE_PROJECT>`.


## [1.0.17-ios17-build2026102203] — 2026-10-22

### Changed
- Audited `jhaizhou-ops/d2r-mobile` through `53e7c5bb9c` and `seedds/nxnative` through `26a72dd562`, including current performance-related commits, Issues, and open/closed PR diffs rather than titles alone.
- In `dm/gfx/nvn/nvn_mtl.m`, exact repeated texture-ID registrations are now no-ops: the existing host texture view and `g_reg_gen` remain valid instead of being released, rebuilt, and invalidating argument caches. A changed texture/view descriptor still takes the original invalidation path. This is the backend-independent subset of upstream `nxnative` commit `9b7cb76104e0`.

### Validation and limitations
- Real Apple M1 Metal validation: `t_tex_finalize` 15/15 (exact repeat preserves view/generation; changed descriptor retires it; finalized in-flight GPU read remains correct) and `t_warm_shader` 16/16. Graphics regressions: `t_nvn` 75/75, `t_pace` 35/35, `t_pres_drop` 40/40, `t_link_wait` 19/19.
- Built via `D2R_RETAINED_INPUT=releases/D2R-iOS17-v1.0.17-build2026102202.ipa scripts/build_game.sh 2026102203`: codesign and ZIP CRC passed, minOS 17.0, retained guest sections verified. Published `releases/D2R-iOS17-v1.0.17-build2026102203.ipa` (SHA-256 `13c2ea6254b27f792d03e2eef2a3d86256e4fcad6393b574baa6e128c61a72c2`, 145,701,529 bytes).
- Not integrated: Metal-4-only vertex argument-table cache (the iOS17 candidate compiles the old `DM_NVN_M3=1` path); unbounded parallel PSO prewarm or draw skipping; a 30 µs guest-wait spin measured only on M4 Pro; generic frame-step probes that do not match this fork's D2R policy. These lack applicable A16 evidence or change rendering/synchronization semantics.
- No device installation or A16 gameplay/performance acceptance. Copy-only rollback verified: `sh artifacts/ios17-feasibility/ROLLBACK.sh --upstream2203-copy <NEW_DIR_OUTSIDE_PROJECT>`. Evidence: `artifacts/upstream-audit-20261022/RESULT.json`.


## [1.0.17-ios17-build2026102202] — 2026-10-22

### Fixed
- In `dm/gfx/nvn/nvn_mtl.m`, expanded `g_red_once` from 64 to 128 elements with an explicit unsigned bounds check `(unsigned)(k) < 128` to prevent buffer overrun when high message codes are triggered.
- In `dm/host/hle_fs.c`, added retry handling with `dm_guest_write_prepare` for `EFAULT` errors in `h_fs_ReadFile`. When background texture streaming finishes and re-protects pages (`nvn_dirty.c`), `pread` into guest memory previously returned `EFAULT` because the kernel does not trigger user-space page faults on read-only mappings, resulting in dropped texture reads. The loop now unprotects the remaining slice and retries up to 8 times.
- In `dm/gfx/nvn/nvn_pace.h` and `dm/gfx/nvn/nvn_mtl.m`, implemented `nvn_link_pick` FIFO present queueing in the `CAMetalDisplayLink` callback (`metalDisplayLink:needsUpdate:`). When two frames finish within the same refresh interval (a common jitter pattern where 60 fps frame times fluctuate between 16 ms and 17.5 ms), the previous implementation discarded the earlier frame immediately and left the prior frame on screen for ~33 ms, producing perceptible micro-stutter. The new FIFO pacer serves the older frame first and retains at most one frame in queue, while dropping older frames only when queue backlog reaches 3 or more (`ticket - first >= 2`).

### Validation and limitations
- Added `t_fs_efault` unit test in `dm/host/tests`: 14/14 checks passed on candidate (verifying single EFAULT recovery, EFAULT bounded failure after 9 attempts without infinite loops, and partial read remainder unprotection), while the baseline failed 12/14 checks.
- Added `nvn_link_pick` test cases in `dm/gfx/tests/t_pace.c`: 35/35 tests passed (including empty queue, 1-frame dispatch, 2-frame ordered FIFO preservation, 3-frame and 4-frame backlog drop accounting).
- Unit test regressions: `t_pace` 35/35 passed, `t_pres_drop` 40/40 passed, `t_link_wait` 19/19 passed, `t_nvn` 75/75 passed, `t_dirty_race` 4/4 passed, `t_dirty_slots` 4/4 passed, `t_builtin` 15/15 passed.
- Build packaging via `scripts/build_game.sh 2026102202` with byte-verified retained build 2116 input: codesign valid, ZIP CRC verified, minOS 17.0, 7,212 metallibs, and embedded guest-sections (`main`, `sdk`) byte-identical with `R44_GATE.json`. Published to `releases/D2R-iOS17-v1.0.17-build2026102202.ipa` (SHA-256: `e3d0789f9cfdd3e5cc8aeb08cca76f8fad1bc5c098b76a84ea4f573245fc120b`, size: 145,701,300 bytes).
- Rollback copy verified outside project: `sh artifacts/ios17-feasibility/ROLLBACK.sh --perf2202-copy <DEST>` (restored exact baseline files with 0 candidate mutations).


## [1.0.17-ios17-build2026102116] — 2026-10-21

### Changed
- Coalesce background logger fsync durability in `main.m` and `dm_log_ring.h`. Instead of issuing a synchronous `fsync` after every drained chunk (which executed 5,092 fsyncs up to 18.37 ms each in build 2115), file writes stay prompt while durability flushes are batched to 64 KiB accumulated writes, 1-second cadence, or explicit flush requests from shutdown/export.
- Replace the background logging worker's 2 ms polling `nanosleep` loop with `pthread_cond_timedwait` on `g_log_ring.wake` (50 ms timeout). Producers signal the condition variable when transitioning the ring buffer from empty to non-empty, and `dm_log_flush` signals immediately when an explicit flush is requested.

### Validation and limitations
- Bounded real Darwin funopen/pthread/file/fsync regression (`probe_logger.py`): 8/8 scenarios passed (idle, periodic, explicit, partial, raw, threshold, sync_error, write_error). Periodic fsyncs reduced from 120 to 3; idle nanosleeps reduced from 1,110 to 0 while maintaining byte stream integrity, error codes, and bounded flush latencies.
- Stalled sink smoke test: 19/19 runs passed. Producer max write stall remained 0.001–0.006 ms under a 1,200 ms simulated sink stall (baseline blocked 1,202.622–1,205.974 ms).
- Production motion probes: 5/5 suites passed (store, hid, export, nvn, camera) across 430,689 store checks, 192 HID checks, 32,768 export rows with bit-exact float/int identity, 388 NVN checks, and 131,134 camera checks.
- Build packaging via `scripts/build_game.sh 2026102116` with byte-verified retained build 2115 input: codesign valid, ZIP CRC verified, minOS 17.0, 7,212 metallibs, and embedded guest-sections (`main`, `sdk`) byte-identical with `R44_GATE.json`. Published to `releases/D2R-iOS17-v1.0.17-build2026102116.ipa` (SHA-256: `566835ea8ce0f660147447ca4478e1e1c349ea32c8894a3a3cdd4b84efad30dc`, size: 145,701,369 bytes).
- Diagnostic analysis of build 2115 device run (20261021_120320): confirmed 0 in-game PSO/shader compiles and 100% thermal state 0 (no thermal throttling). Smooth 60 mode thresholded long frames showed 65.5% of wall clock spent in display-link pacer wait (`节拍等`, mean 21.6 ms, p50 28.3 ms), with queue return wait mean 0.003 ms and GPU duration mean 16.5 ms, confirming that presentation pacing rather than GPU/swapchain exhaustion dictated the frame interval. Rollback copy: `sh artifacts/ios17-feasibility/ROLLBACK.sh --perf2116-copy <DEST>`.


## [1.0.17-ios17-build2026102115] — 2026-10-21

### Changed
- Send iOS runtime LOG/plog output through a preallocated 2 MiB queue and background file/fsync worker. Producers use trylock and count rejected bytes; overflow can fragment stdio lines. Export includes queue, loss, file-error and durable-flush receipts. Raw fd2 remains a nonblocking compatibility pipe. Startup failures stop before game launch.
- Default iOS long-frame and ten-second performance summaries use buffered boot.txt output instead of a second synchronous perf.txt sink. Explicit DM_PERF_FILE retains the opt-in file diagnostic. Graceful shutdown and export use bounded flushes outside frame callbacks.
- Export a bounded 32,768-event motion timeline: consumed stick vectors, player position/error and yaw hooks, frame CPU/waits/scale, GPU spans, queue tickets, actual presentation callback timestamps, and draw-time current/previous camera matrix samples. Overwrite/contention counts expose missing evidence; pending GPU-written camera buffers are omitted.

### Validation and limitations
- Actual LOG → funopen → production writer/worker against a 1,200 ms stalled FIFO: six baseline runs blocked 1,202.622–1,205.974 ms per worst call; corresponding buffered calls took 0.001–0.005 ms. Nineteen runs covered exact under-capacity bytes, partial writes/EINTR, bounded overflow, default perf sink cutover, and flush timeout/error/success.
- Apple M1 real Metal: NVN 75/75 and crop 32/32. Production motion probes: storage 443,041 checks; HID 192; NVN 391; camera 131,134, including default rendering, matrix offsets, pending writes and short buffers. Production Foundation export formatter round-tripped 32,768 rows with exact numerical/64-bit identity checks. Existing HID receipt/script paths passed.
- Built via scripts/build_game.sh 2026102115 with byte-verified retained build2114 inputs. Signing, ZIP CRC, iOS17 minimum, 7,212 metallibs and embedded guest-section identity passed. IPA SHA256 9e449a0ffbc7f6be9cb49c980763e4ac0ca7ac8b01c4274f5240073c9d70888e.
- No device installation or A16 gameplay/performance acceptance. Client/yaw guest hooks and real iOS display/share-sheet execution remain unmeasured. The logger hazard is reproduced locally; its causation of build2114 movement stutter is unproven. Receipts and preserved failures: artifacts/motion-2114-20261021/RESULT.json. Copy-only rollback: fixed ROLLBACK.sh --motion2115-copy NEW_EXTERNAL_DIR.


## [1.0.17-ios17-build2026102114] — 2026-10-21

### Fixed
- Recheck the render pipeline cache after `pso_predict_rest`. Resolving a future program can call `shader_get` and claim a completed warm pipeline for the current draw after `pso_get` has already checked its cache. The getter now returns that object before synchronous compilation. Existing cache hits add no work; genuinely missing pipelines still compile.
- Extend `t_pso_predict_dedup` with deterministic publication during future-program resolution. The build2113 baseline duplicates one render pipeline and fails the identity/count checks; the candidate reuses the warmed object, leaves ongoing warm-up running, and produces all 64 expected pixels.

### Validation and limitations
- Apple M1 real Metal with API Validation: prediction 63/63 across eight modes; warm shader/compute 16/16. Isolated baseline adds one compile; isolated candidate adds zero. The corrected permanent regression fails 2/9 checks on the baseline and passes 9/9 on the candidate. An initial fixture omitted a future fragment stage; its failed count receipt is retained separately.
- Original 224751 current boot independently checked: three compile-associated records at frames17977/21885/22332; the19720–19754 burst has zero new PSOs/libraries. Window19800 has75.06ms present-interval p95 and9 callback timeouts. Frame19754 is163.6ms total,25.8/20.1ms main/translation CPU and99.7ms summed GPU spans. These measurements do not establish that the reproduced cache gap caused that device run.
- Exact package and rollback receipts: `artifacts/night-perf-20261021/cycles/cycle-018/RESULT.json`. No A16 gameplay/performance acceptance; known missing-fixture failures remain preserved.
- Built via `scripts/build_game.sh 2026102114` using retained build2113; signing, ZIP CRC, minimum iOS17.0, 7,212 metallibs and embedded guest-section byte identity passed. IPA145697485bytes, SHA256 `ef6d256e79a6cba09329fa253e5ac418f112a2a793e0c8c427477b9e422914c1`. Scoped rollback through `cycle018:EMPTY_DIR` reproduces the duplicate compile without modifying the candidate.


## [1.0.17-ios17-build2026102113] — 2026-10-21

### Fixed
- Preserve `R.sc` and `R.has_sc` across `pso_predict_rest`: speculative command scanning previously applied a future scissor to the current draw. Real Metal baseline changed 8×8 to 1×1 and produced 63 incorrect pixels; the candidate preserves all 64 green pixels.
- Extract compute pipeline lookup into `cps_get`; on cache miss claim already-published warm results before synchronous compilation. Hot hits return immediately; cold compilation and error handling remain active. Baseline duplicated one compute pipeline; candidate reuses the warmed object with zero new compiles and 64 exact GPU outputs.

### Validation and limitations
- Metal API Validation: warm 16/16, prediction 54/54 across seven modes, stage reuse 72/72 across seven modes, NVN 75/75. Baseline scissor regression fails 2/8 checks; candidate passes 8/8. Original baseline combined probe failed 5/12; isolated modified passed 12/12.
- Built with `scripts/build_game.sh 2026102113`, retained input build2112; signing and ZIP CRC passed. IPA 145697515 bytes; SHA256 `4bbe3ede26f4f06b01de733d9898e824859a06638a46a76bf23c5e7465256eea`.
- Scoped rollback: `sh artifacts/ios17-feasibility/ROLLBACK.sh --night-perf20261021-copy cycle017:EMPTY_DIR`. No A16 performance or whole-game acceptance; known missing-fixture failures remain recorded.


## [1.0.17-ios17-build2026102112] — 2026-10-21

### Fixed
- Fixed warm shader publication claim gap in `shader_get` (`nvn_mtl.m`): on cache miss, `shader_get` now checks `g_warm_ready` (acquire load) and invokes `warm_claim()` before falling back to expensive synchronous `shader_load()`. Eliminates duplicate `newLibraryWithData`, reflection parsing, and redundant pipeline compiles when a requested shader was already published by the background worker during submission execution.
- Hot cache hits remain free of atomic loads or locks; execution never blocks on still-running warm items (`g_warm_running`).

### Added
- Added real-Metal unit test `t_warm_shader.m` in `ios17/dm/gfx/tests/` covering 5 operational modes: `published`, `render`, `cached`, `cold`, and `unrelated` with NSProxy interception of `newLibraryWithData`, verifying zero duplicate library compilations and exact 64-texel render output (10/10 assertions pass).

### Audited
- Audited compression, copy, and render-pass traffic in `ios17/dm/gfx/`: confirmed `pkg_upload_` GPU deswizzle and BC decode paths, `copy_t2t_astc` block alignment boundaries (`nvn_astc_copy_axis`), and `sd_finish` store lookahead decisions operate under strict correctness constraints. No blanket `DONT_CARE` or visual degradation permitted.

### Validation and limitations
- Targeted and regression suites passed: `t_warm_shader` (10/10), `t_pso_predict_dedup` (7/7), `t_astc_array` (36/36), `t_tex_finalize` (11/11), `t_link_wait` (19/19), `t_stage_reuse` (10/10), `t_nvn` (75/75), `verify_findings.py` (24/24) with 0 failures.
- Built via `scripts/build_game.sh 2026102112` with retained input `releases/D2R-iOS17-v1.0.17-build2026102111.ipa`.
- Published IPA: `releases/D2R-iOS17-v1.0.17-build2026102112.ipa`, 145,697,428 bytes, SHA-256: `41046698e27e6ad9294ffdaf8da6eb88b51c14b848817e85362a759d1662ba45`.
- Rollback: `sh artifacts/ios17-feasibility/ROLLBACK.sh --parent2108 <empty dir>` retains pre-2108 baseline.


## [1.0.17-ios17-build2026102111] — 2026-10-21

### Changed
- Diagnostic correction in `hle_nvn.c`: preserved raw average frequency `平均主频 %.2f GHz（周期 / CPU 时间）` and raw topology evidence while removing misleading core-placement inferences ("主要在能效核" / "在性能核档") and A16-specific ceiling calculations.
- Topology probe queries `sysctlbyname("hw.nperflevels")`: on success logs `[nvn] 拓扑探测：hw.nperflevels=%d`; if query fails or returns non-positive, logs `[nvn] 拓扑探测：hw.nperflevels=unknown` rather than mapping failures to single-type topology.
- Removed obsolete helper `nvn_core_tier.h` and implementation-mirroring unit test `t_core_tier.c` / `t_core_tier.single`.
- Added production diagnostic path smoke invocation in `t_nvn.c` exercising startup topology probe and translation detail logging with zero assertions.

### Validation and limitations
- Full graphics suite regression passed: `t_nvn` (75/75), `t_dirty_slots` (4/4), `t_builtin` (15/15), `t_pace` (27/27), `t_pres_drop` (40/40), `t_cover` (14/14), `t_fuse_check` (10/10), `t_present_crop` (32/32), `t_zskip` (38/38), `t_xv` (21/21), `t_ub` (47/47), `t_rt_depth_ro` (4/4), `t_rt_range_shape` (19/19), `t_rt_srgb_view` (14/14), `t_tex_finalize` (11/11), `t_astc_array` (36/36), `t_vis_retire` (8193 passes), `t_pg_lifetime` (5/5), `t_stage_reuse` (7 modes), `t_pso_predict_dedup` (6 modes), `test_tbdr_budget.py` (5/5), `test_passgpu_top.py` (5/5) with 0 failures.
- Built via `scripts/build_game.sh 2026102111` with retained input `releases/D2R-iOS17-v1.0.17-build2026102110.ipa`.
- Published IPA: `releases/D2R-iOS17-v1.0.17-build2026102111.ipa`, 145,697,242 bytes, SHA-256: `2fb0c8706a6266dfde1da50a0822750c7d24191dbf6a350cd386603a71f7c7e8`.
- Observability and diagnostic calibration only. No changes to game logic, rendering behavior, or thread scheduling.


## [1.0.17-ios17-build2026102110] — 2026-10-21

### Added
- Extracted dynamic core-tier detection to `nvn_core_tier.h`, querying `sysctlbyname("hw.nperflevels")` instead of hard-coding chip-specific frequency bounds. On single-cluster systems (levels < 2), the efficiency-core ceiling defaults to 0 so no clock frequency is misclassified as an efficiency core. On multi-cluster systems (levels >= 2, such as A16 and other Apple Silicon), the divider is 2.02 GHz.
- Added startup diagnostic log: `[nvn] 核档探测：hw.nperflevels=%d，能效核上限 %.2f GHz（0 = 单核型，不判能效核）` recorded on the first 300-frame detail line.
- Added standalone unit test suite `t_core_tier` in `ios17/dm/gfx/tests/`, testing both standard multi-cluster probe (7/7 assertions passed) and compile-time injected single-cluster mode (`t_core_tier.single`, 4/4 assertions passed). Negative controls confirmed that breaking the single-cluster branch triggers an explicit assertion failure.

### Validation and limitations
- Full graphics suite regression passed: `t_nvn` (75/75), `t_dirty_slots` (4/4), `t_builtin` (15/15), `t_pace` (27/27), `t_pres_drop` (40/40), `t_core_tier` (7/7), `t_core_tier.single` (4/4), `t_zskip` (38/38), `t_xv` (21/21), `t_ub` (47/47), `t_rt_depth_ro` (4/4), `t_rt_range_shape` (19/19), `t_rt_srgb_view` (14/14), `t_tex_finalize` (11/11), `t_astc_array` (36/36), `t_vis_retire` (8193 passes), `t_pg_lifetime` (5/5), `t_present_crop` (32/32), `t_cover` (14/14), `t_fuse_check` (10/10) with 0 failures.
- Built via `scripts/build_game.sh 2026102110` with retained input `releases/D2R-iOS17-v1.0.17-build2026102109.ipa`.
- Published IPA: `releases/D2R-iOS17-v1.0.17-build2026102110.ipa`, 145,697,516 bytes, SHA-256: `478a894e334d01aff13ccd58d2a87f0dfcdc926860a7b71b6e4faa2773bb4872`. Byte check confirms all 3 strings present in executable binary.
- Rollback: `sh artifacts/ios17-feasibility/ROLLBACK.sh --parent2108 <empty dir>` retains pre-2108 baseline.


## [1.0.17-ios17-build2026102109] — 2026-10-21

### Added
- The `翻译细项` line now appends a core-tier verdict after the average clock: below 2.02 GHz it reports that the time was mainly spent on efficiency cores, otherwise that it was in the performance-core band. On A16 the efficiency cores top out near 2.02 GHz and the performance cores span 2.02–3.46 GHz, so the two bands do not overlap. This is inferred from the average clock, not read from a core id — the log has no core or cluster field, and both the log text and the code comment say so.

### Why
- The remaining stutter is a throughput loss per instruction, not extra work. Across four build2006 runs, bad windows (frame p95 > 41 ms) draw 30–35% more per frame but execute 2.5–4.6% *fewer* instructions per draw, while translation CPU rises 107–133% and main-thread CPU 68–82%.
- Cycles per instruction separates the runs: 0.25 throughout for 224751, versus 0.34–0.46 continuously from frame 5400 to 12000 in 001049. At matched clocks below 2.0 GHz the bad run's CPI is 44–46% higher; at 2.0 GHz and above the gap is 2–4%. Time below 2.0 GHz is 68% for 001049 versus 19% for the run the user described as smooth, measured independently on both the translation thread and the game main thread.
- Preemption, thread-policy demotion, GPU contention and the 3D scale changes were each checked and do not explain it: wall/CPU ratio stays 1.000–1.001, all four runs report priority 97 with the real-time policy in effect, r(CPI, GPU p50) is −0.09, and CPI stays normal through the scale drops at frames 962/1073/1521.

### Validation and limitations
- `t_pres_drop` 40/40, `t_nvn` 75/75, `t_pace` 27/27, `t_present_crop` 32/32; `hle_nvn.c` passes `clang -fsyntax-only` with 0 errors.
- The core-tier rule replayed on the four runs' measured clocks gives 36% / 70% / 23% / 38% efficiency-core share for 224751 / 001049 / 185146 / 181428, the same order as the felt experience.
- `scripts/build_game.sh 2026102109` with retained build2108 input produced a signed, ZIP-verified 145,697,343-byte IPA. SHA-256: `03861b870809d2764e2a20944b784dc3de06997bab018dc9b55098b2f68958bf`. Both new strings are present in the binary by byte search.
- Rollback: `sh artifacts/ios17-feasibility/ROLLBACK.sh --parent2108 <empty dir>` restores the build2107 source state — neither new string and no `late_band` in the restored files.
- Observability only. No scheduling, rendering, pacing or degradation behaviour changed, and no FPS or power improvement is claimed. The efficiency-core reading is inference, not a measured core id, and its device output is unverified until one build2026102109 run exists.


## [1.0.17-ios17-build2026102108] — 2026-10-21

### Added
- `nvn_pres_summary_t` gained `late_band` and `over_lim`: present intervals inside the drop threshold's blind band (1.2–1.5× the target period — clearly late, but not late enough to count as a dropped frame) and at or beyond the threshold, counted separately. The `上屏 至帧` line now prints the blind-band frame count and its millisecond range.

### Why
- At 30 fps both `scale3d_ctl_step()` and the `[perf]` drop counter use `iv > 1.5 × period` = 50.0 ms, so the whole 33.4–50.0 ms band is invisible to both. Across four build2006 device runs this made the metric disagree with felt smoothness: the run with the best drop rate (4.04%) was not the smoothest, and the worst run still showed a single-digit drop rate. Counting the blind band separates them (16 versus 4 frames in the two window shapes), whereas the drop count is 0 for both.

### Validation and limitations
- `t_pres_drop`: 40 checks, 0 failures. Negative control: with the counter implementation stripped, the same test fails 5 checks (35 pass / 5 fail), so the new cases are not vacuously green.
- Real window shapes replayed through the production summary function: 001049 (16 frames at 45.87 ms + 284 at 33.36 ms) → drop 0, blind band 16; 224751 (4 late frames) → drop 0, blind band 4.
- Adjacent graphics checks: `t_nvn` 75, `t_dirty_slots` 4, `t_builtin` 15, `t_pace` 27, `t_zskip` 38, `t_xv` 21, `t_ub` 47, `t_rt_depth_ro` 4, `t_rt_range_shape` 19, `t_rt_srgb_view` 14, `t_tex_finalize` 11, `t_astc_array` 36, `t_vis_retire` 8193 passes / 14 checks, `t_pg_lifetime` 5, `t_present_crop` 32, `t_cover` 14, `t_fuse_check` 10, `test_tbdr_budget.py` and `test_passgpu_top.py` OK — all 0 failures.
- Pre-existing environment failures, not regressions: `t_refl` needs shader-cache samples under `~/dm-work/build/cache` that are absent here; `t_pg_lifetime` needs `TMPDIR` set (5/5 with `TMPDIR=/tmp`); `t_link_wait` passes standalone.
- `scripts/build_game.sh 2026102108` with retained build2107 input produced a signed, ZIP-verified 145,697,293-byte IPA. SHA-256: `2a914d87f2c895a977299f195ae329a476691747615724c56fc226d8b3c1f16b`. The new log string is present in the binary by byte search (`strings(1)` does not detect CJK).
- Rollback: `sh artifacts/ios17-feasibility/ROLLBACK.sh parent2108:<empty dir>` restores the three pre-2108 files without touching the candidate; the restored set compiles and passes 30/30.
- Observability only. No rendering, pacing, wait or degradation behaviour changed, and no FPS, power or bandwidth improvement is claimed. build2026102108 has not been run on a device, so the new field's device output is unverified.


## [1.0.17-ios17-build2026102107] — 2026-10-21

### Fixed
- `pg_commit()`'s per-submission completion handler allocated the per-pass timestamp array (`calloc(used, 8)`) and never freed it, leaking `used * 8` bytes per submission whenever `DM_NVN_PASSGPU` was enabled. Added `free(t)` after the existing `free(ps)`. Measurement path only: no rendering, GPU work or pacing change.
- `dm/gfx/tools/passgpu_top.py` opened `passgpu.tsv`, but the device measurement layer exports the pass table as `passes.tsv` (`dm_measurement.h` role `passes`). The helper now resolves `passes.tsv` first and still accepts the legacy name, so a real device export is analyzable.
- Added `t_pg_lifetime`: real Metal submissions through the production `rp_begin_ex` / `rp_end` / `mtl_sub_commit` path with accounting `calloc`/`free`, asserting that outstanding allocations do not grow per submission, that every submission frees its array, and that pixels stay exact.

### Validation and limitations
- Fixed backend: 3/3 runs exit 0, outstanding 1 -> 1 across 8 submissions, 9 frees, 10 table rows, every pass exactly 128 on readback. Pre-fix backend snapshot (`free(t)` removed): 3/3 runs exit 1, outstanding 1..2 -> 10, 0 frees. Baseline failure is preserved.
- `passgpu_top.py` on the real 32-row `ios-profile-export`: exit 0 (32 passes, 0.96 ms summed increments); the pre-fix receipt failed with `FileNotFoundError`.
- Adjacent real Metal checks passed: `t_vis_retire` 8193 passes 14/14, `t_tex_finalize` 11 checks, `t_astc_array` 36 checks.
- `scripts/build_game.sh 2026102107` with retained build2106 input produced a signed, ZIP-verified 145,697,165-byte IPA. SHA-256: `d3609ae91980723fc2176e9884e13464047c92790ae9f2396b07811b2ae36910`. Resources remain external.
- Cycle 7 also audited copy/compression and render-pass traffic: the ASTC array preservation path never executed in the three A16 runs (0 allocations, 0 RGBA fallbacks logged), dirty-page misses are 0, and attachment stores are already DontCare only under the proven lookahead. No duplicate conversion or blanket DontCare change was adopted.
- These are measurement-path fixes. No A16 FPS, power, temperature or bandwidth improvement is claimed, and build2026102107 has not been run on a device.


## [1.0.17-ios17-build2026102106] — 2026-10-21

### Fixed
- `mtl_sub_begin()` cleared `g_vis` before checking whether the previous submission left a visibility-query overflow buffer. Preserve that reference until the existing deferred-retirement check, so its resource registration and legacy GPU-address entry are removed after the fence. Ring buffers continue to be reused.
- Added `t_vis_retire`: actual production draws and occlusion reports across 8192, 8193 and 16385 passes, exact sample totals and 64 green pixels, retention before the retirement fence, and removal from resource/address registries afterward.

### Validation and limitations
- Baseline and rollback each fail the two overflow-retirement assertions at 8193 passes. Corrected real Metal runs pass 10/14/14 checks at the three boundaries under API validation; O1 Makefile regression passes 14 checks.
- The initial O1 regression raced completion-handler cleanup after `mtl_wait` signaled. Its failed receipt is preserved; the final test additionally waits for the native command buffer's completion handlers before inspecting retirement. No production fence semantics changed.
- Adjacent real Metal checks passed: texture finalization, pass reorder and deferred chains, ASTC arrays, shared/new-encoder argument reuse, and failed speculative PSO slot reclamation. Missing-fixture full suites were not rerun.
- `scripts/build_game.sh 2026102106` with retained build2105 input produced a signed, ZIP-verified 145,697,201-byte IPA. SHA-256: `be7651d0dbc652ad5d8a51b6e8e289826fe3ed882e6555f2bc2031d00babab99`. Embedded guest sections remain byte-identical; resources remain external.
- This is a reproduced retirement mechanism defect, not proof that gameplay exceeded 8192 query passes per submission or that the reported stutter was caused by it. On iOS17 the tracking set is weak: missing retirement leaves an unsafe address-registry entry, and does not by itself prove retained Metal memory. No A16 FPS, power or bandwidth improvement measured.


## [1.0.17-ios17-build2026102105] — 2026-10-21

### Changed
- Reviewed upstream activity and community PRs/issues (#59, #39, #90, #35, #41, #85, #86, #71, #104), focusing on memory footprint, cache preservation, and runtime stutter mitigation.
- Implemented ASTC array format preservation in `dm/gfx/nvn/nvn_mtl.m` and `dm/gfx/nvn/nvn_astc_copy.h` for iOS 17 / A16 (where BC compressed formats are not supported in hardware). Instead of unconditionally decompressing ASTC-backed 2D arrays to full RGBA8 (which inflates VRAM footprint by ~3x and burdens mobile memory bandwidth during texture-to-texture blits), the ASTC format is preserved during initial creation and blits when 4x4 alignment and mip bounds are satisfied.
- Added transparent, GPU-safe dynamic RGBA8 expansion fallback (`astc_array_expand`): if an incompatible render attachment, format view, non-aligned copy, or clear is requested, existing slices and mip levels are preserved and copied before falling back cleanly to the RGBA8 representation.
- Added comprehensive unit test `dm/gfx/tests/t_astc_array.m` covering:
  1. Axis alignment, negative offset, integer overflow, and mip extent checks.
  2. ASTC 4x4 2D array texture creation and multi-mip, multi-slice copy without expansion.
  3. In-flight pixel sampling via real Metal compute shader.
  4. Dynamic RGBA8 expansion trigger and slice 1 preservation.
  5. Pixel-exact 256 texel RGB readback match between ASTC and expanded RGBA.
  6. Environment variable `DM_ASTC_ARRAYS=0` toggle fallback validation.

### Validation and limitations
- `t_astc_array` passes all 36 checks with 0 failures under real Metal and Metal API validation layer.
- Correction (2026-10-21, cycle 019): the `36 checks` figure above did not validate slice or mip preservation. Every mip and slice in that fixture held the same colour, so a slice swap or a truncated mip level could not change any assertion. The void-extent block header was also invalid (`block[1]=0x01` clears bits 10..63; the canonical ARM `astcenc` encoding is `FC FD FF FF FF FF FF FF`), so both compared paths decoded black. The test now gives each `(slice, mip)` its own colour from two independent ASTC sources and checks all 10 combinations after expansion: 48 checks, 0 failures under Metal API validation, and it fails on deliberate mip-truncation (1 failure) and slice-reversal (2 failures) mutations. Receipts: `artifacts/night-perf-20261021/cycles/cycle-019/RESULT.json`.
- Full gfx regression test suite passes cleanly: `t_tex_finalize` (11/11), `t_pfv` (0 failures), `t_rt_srgb_view` (14/14), `t_mip_extent` (303/303), `t_link_wait`, `t_stage_reuse` (7/7 modes), `t_pso_predict_dedup` (6/6 modes), `test_tbdr_budget.py` (5/5), and all unit tests (`t_dirty_slots`, `t_builtin`, `t_pace`, `t_pres_drop`, `t_hmap`, `t_cover`, `t_zskip`, `t_xv`, `t_ub`).
- Built, signed and published `releases/D2R-iOS17-v1.0.17-build2026102105.ipa` (SHA-256: `339ecb6e37ef06169d630c0c081f5bce802a69f33d379b389c888c441f067b5c`, size: 145,697,189 bytes) via `scripts/build_game.sh` with retained input.
- Local offscreen and static checks are not iOS device proof; real-device performance verification remains pending user testing. No automatic installation, save modification, or phone settings altered.


## [1.0.17-ios17-build2026102104] — 2026-10-21

### Changed
- Fixed pending-slot exhaustion and lifetime defect in `pso_pend_harvest()` in `dm/gfx/nvn/nvn_mtl.m`: failed background speculative compiles (`ps == nil`) were previously skipped without resetting `g_pp[i].used` and `g_pp[i].done`, permanently leaking pending slots (out of 384) and blocking future background compilation for those keys. All completed slots (`used && done`) are now unconditionally reset (`ps = nil; used = 0; done = 0`), with valid pipelines published and learned.
- Fixed slot state invariant in `pso_pend_take()`: reset `g_pp[at].done = 0` upon slot retrieval, maintaining the clean slot state invariant (`used = 0, done = 0, ps = nil`).
- Call `pso_pend_harvest()` in `mtl_sub_begin()`: regularly drain completed background compilations and reclaim finished slots at the start of every frame submission, preventing slots from lingering until a cache miss occurs.
- Filter already-pending keys in `pso_predict_rest()`: added `|| pso_pend_find(&k) >= 0` check when scanning remaining draw calls, preventing keys already compiling or pending in `g_pp` from consuming `qa`/`qb` queue slots (capped at 160) and prematurely terminating the submission look-ahead scan.
- Added regression mode `slot_fail` to `dm/gfx/tests/t_pso_predict_dedup.m`, verifying that background speculative compile failure is handled cleanly and failed slots are properly reclaimed (baseline exited with error/failed slot check; modified passes all 8 checks).

### Validation and limitations
- Unit test `t_pso_predict_dedup` passes in all 6 modes (`repeat`, `no_future`, `other`, `merged`, `harvest`, `slot_fail`) with real Metal compilation and exact pixel readback.
- Unit test `t_stage_reuse` passes in all 7 modes (`shared`, `changed`, `ubo`, `new_encoder`, `dirty`, `aba`, `epoch`); `t_tex_finalize` passes 11/11 checks with Metal debug layer; `t_pso_skey` roundtrip verification passes.
- Adjacent regressions pass: `t_link_wait`, `t_pfv`, `t_rt_srgb_view`, `test_tbdr_budget.py`, `t_dirty_slots`, `t_builtin`, `t_pace`, `t_pres_drop`, `t_hmap`, `t_cover`.
- Built, signed and published `releases/D2R-iOS17-v1.0.17-build2026102104.ipa` (SHA-256: `98912f952d4941ef0c7a82459ccd83db993ae71c91c49207ad5933611714ad97`, size: 145,695,931 bytes) via `scripts/build_game.sh` with retained input; embedded main/sdk binary hashes verified byte-identical.
- Local tests and static checks are not iOS device proof; real-device performance verification remains pending user testing. No automatic installation, save modification, or phone settings altered.


## [1.0.17-ios17-build2026102103] — 2026-10-21

### Changed
- Fixed pipeline learning omission in `pso_pend_harvest()` in `dm/gfx/nvn/nvn_mtl.m`: when background speculative compilation completes, the pipeline key was harvested into the primary `g_pso` cache table but skipped recording into the learning manifest (`nvn_pso_learning.h` via `psol_offer`). Harvested pipelines were thus reused within the current session but omitted from subsequent warm launches.
- Added regression mode `harvest` to `dm/gfx/tests/t_pso_predict_dedup.m`, verifying negative control failure (learned manifest missing key, 2/10 checks failed) on baseline code, and full pass (0 failures, manifest key learned, 2 pipelines compiled, 64-pixel green/blue readback exact) on the corrected path.

### Validation and limitations
- Unit test `t_pso_predict_dedup` passes in all 5 modes (`harvest`, `repeat`, `no_future`, `other`, `merged`) with real Metal compilation and exact pixel readback.
- Unit test `t_stage_reuse` passes in all 7 modes (`shared`, `changed`, `ubo`, `new_encoder`, `dirty`, `aba`, `epoch`); `t_tex_finalize` passes 11/11 checks with Metal debug layer; `t_pso_skey` roundtrip verification passes.
- Static checks pass: `native_write_scan` (74 files clean), `scan_literals` (471 Chinese literals whitelisted), `dm_i18n` (373 entries valid), `mode_scan` (24 pump functions categorized), and `widget_cache_scan` (77 files clean).
- Built, signed and published `releases/D2R-iOS17-v1.0.17-build2026102103.ipa` (SHA-256: `98e09b5273f8efc02cdfb8ea4c3bfd212469ae2cbd6bb25d37d0e7a61380cf31`, size: 145,695,690 bytes) via `scripts/build_game.sh` with retained input; embedded main/sdk binary hashes verified byte-identical.
- Local tests and static checks are not iOS device proof; real-device performance verification remains pending user testing. No automatic installation, save modification, or phone settings altered.


## [1.0.17-ios17-build2026102102] — 2026-10-21

### Changed
- Implement `pso_pend_harvest()` in `dm/gfx/nvn/nvn_mtl.m`: harvest completed background speculative Metal pipeline compiles from the pending array into the primary pipeline cache `g_pso` upon any cache miss.
- Prevent speculative compilation pending array starvation and leak: pipelines speculatively compiled for rest-of-frame draws that are not immediately taken by a direct key match are safely retained in `g_pso` and their pending slots freed for subsequent speculative submissions.

### Validation and limitations
- Unit test `t_pso_predict_dedup` passes in all 4 modes (`repeat`, `no_future`, `other`, `merged`) with real Metal compilation and exact pixel readback; speculative kick and cache hit counts strictly verified.
- Unit test `t_stage_reuse` passes in all 7 modes (`shared`, `changed`, `ubo`, `new_encoder`, `dirty`, `aba`, `epoch`); `t_tex_finalize` passes 11/11 checks with Metal debug layer.
- Unit test `t_oe` passes 49/49 checks; all static scanners (`native_write_scan`, `widget_cache_scan`, `mode_scan`, `scan_literals`, `dm_i18n`) pass.
- Built, signed and published `releases/D2R-iOS17-v1.0.17-build2026102102.ipa` (SHA-256: `7ba0c51afa4a742ecfb9904d1a3788ea84e001023bc29ed34d50e5a71224cfee`) via `scripts/build_game.sh` with retained input; embedded main/sdk binary hashes verified byte-identical.
- Local tests and static checks are not iOS device proof; real-device performance verification remains pending user testing.


## [1.0.17-ios17-build2026102101] — 2026-10-21

### Changed
- Pre-warm Metal render pipeline manifest (`pso_manifest.tsv`) with 3 missing runtime PSO combinations encountered during Catacombs / Andariel combat (`d5eaef5580e95b5c_b` + `95423174e654085d_b` with and without depth attachment, and `69cfdc6545a66915_b` + `9a650561e5c40791_b`), eliminating 200–650ms cold-compile freezes on first encounter.
- Lower dynamic 3D resolution scaling floor from 0.60f to 0.55f (`S3_FLOOR_DEF` in `hle_oe.c`), unlocking level 4 (0.55x internal 3D render scale) to shed ~16% GPU fragment and memory bandwidth load during heavy combat without compromising 2D UI or text clarity.

### Validation and limitations
- Unit test `t_oe` passes all 49 checks (including scale3d controller step, debounce, guard against panels, and quality mode override).
- Static checks pass: literal whitelist (471 entries), i18n scan, native write scan, widget cache scan, mode scan.
- Built and packaged `releases/D2R-iOS17-v1.0.17-build2026102101.ipa` via `scripts/build_game.sh` with retained input; embedded main/sdk binary hashes verified byte-identical.
- Local tests and static checks are not iOS device proof; real-device performance verification remains pending user testing.


## [1.0.17-ios17-build2026102006] — 2026-10-20

### Changed
- Retire descriptor cache aliases on texture destruction (`mtl_tex_release`), releasing matching `g_treg` Metal views via `defer_obj_unref` + `CFRelease` and incrementing `g_reg_gen` to invalidate argument buffer caches (addressing memory growth across areas and panels from PR #86 / Issue #90).
- Attribute residual stalls in longframe logs: include display-link pacing wait (`acq_wait_ms`) and swapchain availability wait (`pq_wait_ms`) in `lf_rec`, closing the unattributed gap between total frame time and CPU/GPU time.
- Synchronize upstream touch improvements: main attack button shares the 10-point drag dead zone to avoid accidental re-aiming on minor finger wobble (Issue #92); native general actions (IDs 357, 358, 360-364, 370) remain valid and not mistakenly marked empty in `skill_live` (Issue #81).
- Add `t_tex_finalize` regression test with real Metal readback to the graphics test suite, verifying alias release and argument buffer invalidation.

### Validation and limitations
- `t_tex_finalize` regression test passes 11/11 checks (negative control baseline failed 2 checks). 75/75 NVN unit tests, 7/7 stage reuse modes, 4/4 PSO dedup modes, 27/27 pacer checks, 30/30 presentation summary checks, 32/32 crop checks, and 29/29 touch host checks pass.
- Full graphics suite retains known environment-fixture skips (`t_refl` missing fixture, `t_rt_range_ro` exit134 missing fixture); full host suite retains `t_romfs_validate` missing RomFS.
- Local tests and static checks are not iOS device proof; stutter resolution on actual devices remains unconfirmed until verified by runtime diagnostics from the user.
- No automatic installation, save modification, or phone settings altered. All published builds remain intact.


## [1.0.17-ios17-build2026102005] — 2026-10-20

### Changed
- Keep eco30 drawable callbacks at 60 Hz and render every two callbacks. Preserve callback phase after a delayed wake and use a two-frame timeout budget.
- Recheck the callback predicate when a timed wait expires; a callback that arrived at the deadline must not trigger the timeout fallback.
- Add an opt-in retained IPA build route through `scripts/build_game.sh`: verify the input IPA hash and recovered main/sdk hashes against the retained r44 receipt, then rebuild current host sources. Historical NSO rewrite checks are not represented as newly executed checks.

### Validation and limitations
- Production waiter regression fails before the deadline-race fix and passes afterward. Pacing and presentation-summary checks pass; iOS17 compilation, actual pthread callback smoke, full app build, ZIP CRC and ad-hoc signature checks pass.
- Build2004 log contains 910 timeouts across 24,600 measured pacing calls, including lifecycle intervals. Pipeline creation/wait spikes remain; this release does not claim that all stutter is fixed or that phone performance improved.
- No device installation, settings changes or save modifications. Existing game resources and previously published IPAs remain in place.


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
