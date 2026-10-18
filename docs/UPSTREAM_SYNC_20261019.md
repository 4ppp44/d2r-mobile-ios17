# Upstream review and bounded iOS17 backport — 2026-10-19

## Identity and scope
- Retained playable baseline: 1.0.17 / build2026101705. Its IPA and ASTC resources are unchanged.
- Latest observed upstream release: [v1.0.18](https://github.com/jhaizhou-ops/d2r-mobile/releases/tag/v1.0.18), release commit120fe55c02; main9393b00ea9aca52d9254214da93738f26582562f.
- This is a selective backport, **not a complete v1.0.18 merge or a new playable release**. Keep1705 timing/input/rendering compatibility.

## Imported
1. Merged46cb318b17 minimap/layout lifetime fixes: recompute `mv_offset` insertion index after pruning; avoid `ui_lift_pump` writes during unsettled widget/mode transactions. Import the production-source regression, including full96-entry boundary coverage.
2. Merged9393b00ea9 / issue77: Playback with MixWithOthers, retaining existing interruption/resume logic. This is audio coexistence, not a GPU/FPS improvement; phone audio behavior remains unverified.
3. Independently reviewed [open PR85](https://github.com/jhaizhou-ops/d2r-mobile/pull/85), head85ccbf9f78ac44453491eb8aaa47e183a4b3fc18: reject zero/nonfinite/unsupported-negative timing samples and do not replace missing actual-present intervals with CPU intervals in a windowed trace. Four synthetic tests, three fail on the old analyzer. This changes report correctness, not runtime speed. Upstream PR is not represented as merged.

## Existing in1705, not newly claimed
- Earlier source improvements in loader weak imports, checked stride/block copy, pipeline prewarm, translator separation, M3 load/store handling and runtime first-use resources are not new fixes in this backport.
- Preserve per-encoder iOS17 M3 resource declarations, bloom/system-UI snapshot guards, Scheduled direct present, eco30 period/ticket handling, NSTimer input polling and build-bound opt-in diagnostics. No1706 timeout experiment or MRU2 trial.

## Reviewed but not copied wholesale
- v1.0.18 controls appearance/layout and related controller mappings: larger UI behavior change, not an A16 performance result; requires its own compatibility review before adoption.
- 6edec84405: skill-slot rim art; no graphics throughput claim.
- 3af961d3c0 / issue76: guest code-signature reservation for alternate installation; packaging follow-up, not current TrollStore runtime bottleneck. Keep public guest minOS17.
- 120fe55c02: 4GB-device documentation; does not imply A16/6GB thermal parity.
-46cb318 host virtual-address reservation fallback and x18 rewrite prefilter: startup/build-tool changes, not measured A16 gameplay gains; deferred rather than silently altering guest address-space/rewrite contracts.
- Metal4 magenta diagnostics are not enabled in the iOS17 M3 backend; no extra per-present GPU readback is introduced.
- [Draft PR86](https://github.com/jhaizhou-ops/d2r-mobile/pull/86): tvOS A15/4GB pressure budgets and shared texture-finalization lifetime changes; report retains scene-transition memory termination and failed reflection checks. Do not transfer those budgets to A16/6GB or assume a performance win. Descriptor alias cleanup is a separate future hypothesis, not a verified fix.
- [Issue39](https://github.com/jhaizhou-ops/d2r-mobile/issues/39): iOS17 remains outside upstream support; residency lifetime/declaration equivalence and the Scheduled-present distinction still matter.
- [Issue59](https://github.com/jhaizhou-ops/d2r-mobile/issues/59): use same-scene rendered intervals and warmed pipelines; do not replace proper attachment/resource lifetime checks with blanket DontCare flags. No new measured A16 result is provided by that discussion.
- Issues78/75: newer SDK packaging and inventory semantics respectively, not evidence of the observed A16 frame-pacing bottleneck.

## Executed validation
- Identical minimap production-source regression: BASELINE330 checks /121 failures /exit1; MODIFIED330 /0 /exit0; ROLLBACK330 /121 /exit1.
- Identical synthetic analyzer tests: BASELINE4 tests /3 failures /exit1; MODIFIED4 /0 /exit0; ROLLBACK4 /3 /exit1. Restored source hashes equal originals before reapplying the patch.
- Strict iOS17 deployment compilation: six runtime units, including frontend and M3 backend, all exit0; checked unguarded availability errors. Existing local generated headers were used privately and are not published.
- Actual Mac Foundation timer/profile contract:12 checks pass. Native NVN75, crop32, pace23; depth-RO4 is explicitly mock. Mac real-Metal deswizzle15, RT-range19 and mip303 pass, plus checked copy pitch. Host touch29, interaction18 and weak-loader checks pass.
- These are host/source/native checks, not A16 gameplay, same-scene FPS, whole-device energy or full-game graphics certification. No measured performance/power gain, new IPA, device action, quality reduction or resource replacement is claimed.
