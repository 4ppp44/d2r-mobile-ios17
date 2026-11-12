# 单测：make 编译并运行（秒级）
# 源文件按通配纳入，口径与宿主 Makefile 的 GFX 一致（hle_nvn.c 由 t_nvn.c 直接 #include，故剔除）；新增源文件无需改这里
# Unit tests: make compiles and runs them (seconds)
# Source files are included by wildcard, same convention as GFX in the host Makefile (hle_nvn.c is #included directly by t_nvn.c, so it is excluded); adding new source files needs no change here
CFLAGS=-O1 -g -Wall -Wno-unused-function -I../nvn/include
GFX=$(filter-out ../nvn/hle_nvn.c,$(sort $(wildcard ../nvn/*.c ../nvn/*.m ../nvn/*.S ../tex/*.c ../tex/*.m))) ../../host/tests/motion_fixture.c
GFX_H=$(wildcard ../nvn/*.h ../nvn/*.inc ../nvn/include/*.h ../tex/*.h)
FW=-framework Metal -framework Foundation -framework QuartzCore -framework ImageIO -framework CoreGraphics -framework UniformTypeIdentifiers
# 宿主 crash.c 一并链入：写保护单测走生产同一套缺页钩子
# Host crash.c is linked in as well: the write-protect unit tests go through the same page-fault hook as production
t_nvn: t_nvn.c ../nvn/hle_nvn.c ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_nvn.c ../../host/crash.c $(GFX) $(FW)
t_dirty_slots: t_dirty_slots.c ../nvn/nvn_dirty.c ../../host/crash.c ../nvn/nvn_dirty.h
	clang $(CFLAGS) -o $@ t_dirty_slots.c ../../host/crash.c ../nvn/nvn_dirty.c
t_builtin: t_builtin.m ../nvn/nvn_builtin.h
	clang -O1 -g -Wall -fobjc-arc -o $@ t_builtin.m -framework Metal -framework Foundation
t_deswz_gpu: t_deswz_gpu.m ../tex/nvn_deswizzle.c ../tex/nvn_deswizzle_gpu.m ../tex/nvn_deswizzle.h ../tex/nvn_deswizzle_gpu.h ../nvn/nvn_tex.c ../nvn/nvn_tex.h
	clang $(CFLAGS) -fobjc-arc -o $@ t_deswz_gpu.m ../tex/nvn_deswizzle.c ../tex/nvn_deswizzle_gpu.m ../nvn/nvn_tex.c -framework Metal -framework Foundation
t_refl: t_refl.m ../nvn/nvn_refl.m ../nvn/nvn_refl.h ../nvn/dmsh_chain.h
	clang -O1 -g -Wall -fobjc-arc -o $@ t_refl.m ../nvn/nvn_refl.m -framework Metal -framework Foundation
t_hmap: t_hmap.c ../nvn/nvn_hmap.h
	clang -O1 -Wall -o $@ t_hmap.c
t_cover: t_cover.c ../nvn/nvn_cover.h
	clang -O1 -Wall -o $@ t_cover.c
t_pace: t_pace.c ../nvn/nvn_pace.h
	clang -O1 -Wall -o $@ t_pace.c
t_pres_drop: t_pres_drop.c ../nvn/nvn_pace.h
	clang -O1 -Wall -Werror -o $@ t_pres_drop.c -lm
t_adaptive_pace: t_adaptive_pace.c ../nvn/nvn_adaptive_pace.h ../nvn/nvn_pace.h
	clang -O1 -Wall -o $@ t_adaptive_pace.c
run: t_adaptive_pace


t_fuse_check: t_fuse_check.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_fuse_check.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_rt_srgb_view: t_rt_srgb_view.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_rt_srgb_view.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_present_crop: t_present_crop.m ../nvn/hle_nvn.c ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_present_crop.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m,$(GFX)) $(FW)
t_reorder_chain: t_reorder_chain.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_reorder_chain.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_defer_chain: t_defer_chain.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_defer_chain.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_zskip: t_zskip.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_zskip.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_xv: t_xv.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_xv.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_ub: t_ub.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_ub.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_mip_extent: t_mip_extent.m ../nvn/hle_nvn.c ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_mip_extent.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m,$(GFX)) $(FW)
t_rt_range_shape: t_rt_range_shape.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_rt_range_shape.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_rt_range_ro: t_rt_range_ro.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_rt_range_ro.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_rt_range: t_rt_range.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_rt_range.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_rt_depth_ro: t_rt_depth_ro.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_rt_depth_ro.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_pso_skey: t_pso_skey.m ../nvn/nvn_pso_skey.h ../nvn/nvn_obj.h
	clang $(CFLAGS) -fobjc-arc -o $@ t_pso_skey.m -framework Foundation
t_pfv: t_pfv.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_pfv.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
# 同槽 last-write-wins 合并：直接走命令内存里的记录序列手算期望 | Same-slot last-write-wins merging: walks the record sequence in command memory with hand-calculated expectations
t_lww: t_lww.c ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_lww.c ../../host/crash.c $(GFX) $(FW)
t_m3_hang_guard: t_m3_hang_guard.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_m3_hang_guard.m ../../host/crash.c $(GFX) $(FW)
t_dup_draw: t_dup_draw.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_dup_draw.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_nvn t_dirty_slots t_dirty_race t_builtin t_deswz_gpu t_pace t_pres_drop t_refl t_hmap t_cover t_fuse_check t_present_crop t_reorder_chain t_defer_chain t_zskip t_xv t_ub t_mip_extent t_rt_range_shape t_rt_range_ro t_rt_range t_rt_depth_ro t_pso_skey t_pfv t_rt_srgb_view t_readback_lifetime t_upload_budget t_lww t_m3_hang_guard t_args_plan t_c2_full t_pipeline_cache t_dup_draw
	./t_nvn
	for mode in fast count tsv timing; do ./t_nvn_fast $$mode || exit 1; done
	./t_lww
	./t_m3_hang_guard
	./t_eco_fps
	./t_eco_fps 30
	./t_eco_fps 60
	./t_shadow_store
	MTL_DEBUG_LAYER=1 ./t_shadow_motion
	MTL_DEBUG_LAYER=1 ./t_shadow_motion d32s8
	MTL_DEBUG_LAYER=1 ./t_rt_store_overwrite
	./t_args_plan
	./t_c2_full
	./t_vattr_int
	./t_pipeline_cache
	./t_dup_draw
	./t_dirty_slots
	./t_dirty_race
	./t_builtin
	./t_deswz_gpu
	./t_pace
	./t_pres_drop
	./t_link_wait
	./t_eco_clock
	./t_refl
	./t_hmap
	./t_cover
	./t_fuse_check
	./t_present_crop
	MTL_DEBUG_LAYER=1 ./t_reorder_chain
	MTL_DEBUG_LAYER=1 ./t_defer_chain
	./t_zskip
	./t_xv
	./t_ub
	MTL_DEBUG_LAYER=1 ./t_mip_extent
	MTL_DEBUG_LAYER=1 ./t_mip_extent --stencil-only
	./t_rt_depth_ro
	./t_rt_range_shape
	./t_rt_range_ro
	DM_NVN_UNWRITTEN_DC=0 MTL_DEBUG_LAYER=1 ./t_rt_range
	MTL_DEBUG_LAYER=1 ./t_rt_range   # Read-only depth/stencil contents remain live and must be stored.
	DM_NVN_UNWRITTEN_DC=0 MTL_DEBUG_LAYER=1 ./t_rt_range --disabled
	DM_NVN_UNWRITTEN_DC=0 MTL_DEBUG_LAYER=1 ./t_rt_range --small-depth
	DM_NVN_UNWRITTEN_DC=0 MTL_DEBUG_LAYER=1 ./t_rt_range --sample-attachment --both-flags
	./t_pso_skey
	for mode in shared changed ubo new_encoder dirty aba epoch texsmp xpass; do ./t_stage_reuse $$mode || exit 1; done
	for mode in overlap early_fail priority promote busy repeat no_future other merged harvest slot_fail scissor publication schedule running norm_no_format norm_invalid_blend norm_active_blend norm_active_mask norm_merged; do ./t_pso_predict_dedup $$mode || exit 1; done
	MTL_DEBUG_LAYER=1 ./t_pfv
	MTL_DEBUG_LAYER=1 ./t_rt_srgb_view
	MTL_DEBUG_LAYER=1 ./t_tex_finalize
	MTL_DEBUG_LAYER=1 ./t_astc_array
	MTL_DEBUG_LAYER=1 ./t_vis_retire
	MTL_DEBUG_LAYER=1 ./t_pg_lifetime
	MTL_DEBUG_LAYER=1 ./t_warm_shader
	MTL_DEBUG_LAYER=1 ./t_readback_lifetime
	MTL_DEBUG_LAYER=1 ./t_upload_budget
	python3 test_tbdr_budget.py
	python3 test_passgpu_top.py
.PHONY: run

STAGE_TEST_FLAGS ?= -DT_BIND_STAGES_FIXED
t_bind_stages: t_bind_stages.m ../nvn/nvn_mtl.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) $(STAGE_TEST_FLAGS) -fobjc-arc -o $@ t_bind_stages.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_bind_stages

t_copy_pitch: t_copy_pitch.c ../nvn/nvn_copy_pitch.h
	clang -O1 -Wall -Werror -o $@ t_copy_pitch.c

# Count real Metal PSO compilation through production prediction/getter code.
t_pso_predict_dedup: t_pso_predict_dedup.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_pso_predict_dedup.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_pso_predict_dedup

# Production argument encoding and exact real Metal pixel readback.
t_stage_reuse: t_stage_reuse.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_stage_reuse.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
# 绑定计划 / 驱动段块缓存 / 地址解析缓存：真 Metal 下断言复用与重建的边界 | Binding plan / driver segment cache / address memo: asserts the reuse and rebuild boundaries on real Metal
t_args_plan: t_args_plan.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_args_plan.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
t_c2_full: t_c2_full.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_c2_full.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
# 整数顶点输入 × 归一化客体格式：真 Metal 下断言换格式、建成与负对照 | Integer vertex inputs vs normalized guest formats: asserts the swap, the build and the negative control on real Metal
t_vattr_int: t_vattr_int.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_vattr_int.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_args_plan
run: t_vattr_int
run: t_stage_reuse

t_link_wait: t_link_wait.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_link_wait.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_link_wait

t_tex_finalize: t_tex_finalize.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_tex_finalize.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_tex_finalize

t_astc_array: t_astc_array.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_astc_array.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_astc_array

t_vis_retire: t_vis_retire.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_vis_retire.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_vis_retire

t_pg_lifetime: t_pg_lifetime.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_pg_lifetime.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_pg_lifetime

t_warm_shader: t_warm_shader.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_warm_shader.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_warm_shader

# Pending clear folding and packed D32S8 clear-only plane omission via production replay and real Metal readback.
t_rt_clear_fold: t_rt_clear_fold.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_rt_clear_fold.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_rt_clear_fold

# Store lookahead: a supported whole-subresource ClearTexture can discard the overwritten attachment store.
t_rt_store_overwrite: t_rt_store_overwrite.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_rt_store_overwrite.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_rt_store_overwrite

t_shadow_motion: t_shadow_motion.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_shadow_motion.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_shadow_motion

t_shadow_store: t_shadow_store.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_shadow_store.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_shadow_store

t_shadow_motion_store: t_shadow_motion_store.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_shadow_motion_store.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)



t_dirty_race: t_dirty_race.c ../nvn/nvn_dirty.c ../../host/crash.c ../nvn/nvn_dirty.h
	clang $(CFLAGS) -o $@ t_dirty_race.c ../../host/crash.c

t_readback_lifetime: t_readback_lifetime.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_readback_lifetime.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_readback_lifetime

t_upload_budget: t_upload_budget.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_upload_budget.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_upload_budget

# 管线二进制归档：两阶段跨进程（阶段 1 编译并落盘，阶段 2 直接命中）。只链归档模块本身，不链整个图形后端。
# Pipeline binary archive: two phases across processes (phase 1 compiles and persists, phase 2 hits directly). Links only the
# archive module itself, not the whole graphics backend.
t_pipeline_cache: t_pipeline_cache.m ../nvn/nvn_pipeline_cache.m ../nvn/nvn_pipeline_cache.h ../nvn/dmsh_chain.h
	clang $(CFLAGS) -fobjc-arc -o $@ t_pipeline_cache.m ../nvn/nvn_pipeline_cache.m $(FW)
run: t_pipeline_cache

t_eco_fps: t_eco_fps.m fps_setting_fixture.c ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_eco_fps.m fps_setting_fixture.c ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_eco_fps

t_eco_clock: t_eco_clock.m ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_eco_clock.m ../../host/crash.c $(filter-out ../nvn/nvn_mtl.m ../nvn/nvn_entry.S ../nvn/nvn_thunks.S,$(GFX)) $(FW)
run: t_eco_clock

t_nvn_fast: t_nvn_fast.c ../nvn/hle_nvn.c ../../host/crash.c $(GFX) $(GFX_H)
	clang $(CFLAGS) -fobjc-arc -o $@ t_nvn_fast.c ../../host/crash.c $(GFX) $(FW)
run: t_nvn_fast
