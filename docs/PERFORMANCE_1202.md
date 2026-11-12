# 1202 runtime review / 1202 真机复核

Reviewed 2026-11-13. Build `2026111202`, iPhone15,3 / iOS17.0, approximately six minutes. Only the current boot was counted; previous-session logs and historic pipeline records were excluded. This document contains aggregate results, not device logs, identifiers, saves or game data.

## Result / 结论

**Runtime validation is incomplete: visible cold-pipeline stutter remains. / 尚未通过全部卡顿验收，运行期冷管线仍是主要问题。**

| Frame / 帧 | Region / 区域 | Whole frame / 整帧 | Submit + present / 提交 | Pipeline preparation / 管线准备 | New compile / 新编 | GPU |
|---|---:|---:|---:|---:|---:|---:|
| 4222 | 43 | 608.8ms | 615.1ms | 582.7ms | 3 / 504.4ms | 12.7ms |
| 3627 | 43 | 286.1ms | 305.0ms | 296.4ms | 1 / 296.4ms | 10.4ms |
| 6258 | 43 | 147.0ms | 161.0ms | 152.8ms | 1 / 101.9ms | 9.2ms |
| 6422 | 43 | 119.2ms | 137.5ms | 111.6ms | 3 / 111.5ms | 8.2ms |

These are asynchronous frame counters, not a strictly additive decomposition. An early worker's compile wall overlaps prediction scanning; do not add it again to pipeline/frame wall. GPU duration is not the hundreds of milliseconds of host-side preparation.

59 long-frame diagnostic records include GPU-only flags and loading-covered frames. Seven whole frames exceed100ms; five have a non-menu region, including one covered loading frame. This is not59 severe gameplay freezes. Main-thread CPU peaks at87.9ms in region40/frame225, with a loading overlay; the earlier region42/703ms issue was not covered and remains open.

The35 FPS samples range58.1–60.0, with3D scale0.75 throughout. Mostly60fps does not exclude the609ms spike. No CRASH/red-marker line was found in the current boot. A short session does not certify long-session stability, memory lifetime or temperatures.

## What1202 changed, and what this test shows

The source starts the demanded PSO while the submit thread decodes future state, but only with idle speculative workers and no pending warm publication. Primary attachment candidates outrank alternatives; exact-key ownership, fallback and rendering remain intact.

Prediction-wait counters were0 in the observed long frames. This alone is not proof of a causal improvement: scenes, PSO sets and existing caches differ from1201. Four early-build records show compile / remaining join of0/0,101.9/101.8,31.4/31.4 and29.5/29.5ms. For these cases, prediction scanning hid little of the actual compile. The next useful work is earlier knowledge of missing exact PSOs and handling first-use compilation before visible rendering; task rearrangement alone is insufficient.

Startup prewarm completed401 shaders,1874 render PSOs and12 compute PSOs in1107ms; it did not cover every runtime combination. A persistent list learns newly encountered PSOs for later launches, so repeated visits can be warmer without proving an algorithmic fix.

## Other unresolved paths

- The earlier region40/~219ms non-compile submit spike was not reproduced here. It is not declared fixed.
- A separate instrumented1201 capture found buffer-blit API waiting on an AGX internal program-variant lock despite zero game-PSO compiles. It occurred in region62 near a screenshot request; neither the screenshot confound nor its relationship to the original219ms event was resolved.
- A120-second A16 capture recorded28,610 buffer copies with no lost records and a maximum0.052ms API duration. Thirty size/mod256-offset combinations completed correctly on independent Shared buffers in two passes. This was a warm-process feasibility test, not a cold-start A/B or proof that these groups equal driver variant keys.
- Buffer-copy prewarm is **not shipped**. Its cold-start benefit remains unverified. No cache deletion or game-data changes were used to manufacture a cold result.

## Measurement boundaries

The header reports about six minutes, while per-frame seconds begin around2230 and startupT1 already includes a large process-origin offset. Treat frame order and durations as primary; do not describe this as37minutes of play. Production log writes peaked at0.112ms, with no>5ms pipe block;2300 bytes were dropped through contention. Missing log records are not zero measurements. Thermal state0 is not skin temperature, and the reported GPU occupancy0 is not evidence of idle GPU or whole-device watts.

## Validation levels

1202's20 targeted real Mac Metal modes /184 checks, full local GFX suite, iOS17 arm64 retained-input build, signature and ZIP integrity checks passed before delivery. They do not prove A16 performance. This public source export additionally runs the public GFX target; it does not include the private retained IPA, regenerated guest images, original device logs or a fresh clean full-game rebuild.
