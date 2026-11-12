"""逐通道表分析器回归：小型导出 + 闭式期望，不需要游戏或 GPU；临时文件只放 run/gfx。
Per-pass table analyzer regression: small exports with closed-form expectations, no game or GPU needed; temp files go only under run/gfx.
覆盖设备测量档的真实文件名与帧号起点，以及「目录 / 文件」两种入参：
Covers the device profile's real file name and frame origin, and both directory / file arguments:
- 目录里只找 passes.tsv，缺了才用旧名 passgpu.tsv；当前工作目录里的同名文件不得顶替 | inside a directory only passes.tsv is looked for, the legacy passgpu.tsv only when it is absent; a same-named file in the working directory must not replace it
- 也可以直接给表文件路径 | a table file path is accepted directly
- 设备导出从第 0 帧记起，默认帧下限 300 会筛空，必须给出说明并以非 0 退出 | the device export starts at frame 0, so the default floor 300 empties it: that must be reported and exit non-zero
- 分母是选中的总帧数，不是各序号自己的出现次数：只出现一两帧的稀有序号按 0 计入其余帧，不得把整帧合计抬高
  | the denominator is the total number of selected frames, not each index's own occurrence count: a rare index present in one or two frames counts as zero elsewhere and must not inflate the frame total
- 同一帧内序号在不同帧落到不同通道（元数据混合）时不得把最后一行的身份当成该序号的元数据
  | when one in-frame index lands on different passes in different frames (mixed metadata) the last row's identity must not be presented as that index's metadata
- 表尾追加的 c0_ser / d_ser / fs_key 列按列名读取，逐帧变化时报 ? 而不是借用某一帧的值；旧表头照旧可读
  | the appended c0_ser / d_ser / fs_key columns are read by name, reported as varying instead of borrowing one frame's value, and the legacy header still reads
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

DM_ROOT = os.environ.get('DM_ROOT') or os.path.expanduser('~/dm-work')
TOOL = Path(os.environ.get('PASSGPU_TOP_TOOL', Path(__file__).resolve().parents[1] / 'tools/passgpu_top.py'))
# 设备真实表头（nvn_mtl.m 的 DM_NVN_PASSGPU 写法）| the device's real header (as written by DM_NVN_PASSGPU in nvn_mtl.m)
COLS = ['frame', 'idx', 'kind', 'gpu_ms', 'inc_ms', 'w', 'h', 'fmt0', 'dfmt', 'load', 'draws', 't0_ns', 't1_ns', 'pass']
# 旧表头：名字不同、列数相同（本工具按位置回退）| legacy header: different names, same positions (the tool falls back to positions)
LEGACY_COLS = ['frame', 'idx', 'kind', 'ms', 'inc', 'w', 'h', 'cf', 'df', 'load', 'draws', 'a', 'b', 'pass']


def row(frame, idx, inc, w=8, h=8, kind='R', load='L', draws=1, c0=None, d=None, fs=None):
    cells = [str(frame), str(idx), kind, '%.4f' % inc, '%.4f' % inc, str(w), str(h), '70', '0', load, str(draws), '1', '2', str(idx)]
    if c0 is not None: cells += [str(c0), str(d), fs or '-']
    return '\t'.join(cells) + '\n'


class PassTableAnalyzer(unittest.TestCase):
    def setUp(self):
        root = Path(DM_ROOT) / 'run/gfx'
        root.mkdir(parents=True, exist_ok=True)
        self._tmp = tempfile.TemporaryDirectory(prefix='passgpu_top_', dir=root)
        self.dir = Path(self._tmp.name)
        self.cwd = self.dir / 'cwd'
        self.cwd.mkdir()

    def tearDown(self):
        self._tmp.cleanup()

    def export(self, relpath, rows, cols=COLS):
        p = self.dir / relpath
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text('\t'.join(cols) + '\n' + ''.join(rows))
        return p

    def run_tool(self, arg, *extra):
        return subprocess.run([sys.executable, str(TOOL), str(arg), *extra], capture_output=True, text=True, cwd=str(self.cwd))

    def test_directory_prefers_passes_tsv_and_ignores_working_directory(self):
        # 设备档写法：帧号从 0 起，所以帧下限用 -1 | device layout: frames start at 0, hence the -1 floor
        self.export('session/passes.tsv', [row(0, 1, 0.25), row(1, 1, 0.75)])
        # 旧名放在同一目录里也必须让位给 passes.tsv | the legacy name in the same directory must yield to passes.tsv
        self.export('session/passgpu.tsv', [row(0, 9, 99.0)])
        # 当前工作目录里的同名文件不得参与选择 | a same-named file in the working directory must not take part in the choice
        (self.cwd / 'passes.tsv').write_text('\t'.join(COLS) + '\n' + row(0, 9, 99.0))
        p = self.run_tool(self.dir / 'session', '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('session/passes.tsv', p.stdout)
        self.assertIn('#1：0.500 ms', p.stdout)   # (0.25 + 0.75) / 2 frames
        self.assertNotIn('#9', p.stdout)
        self.assertIn('通道数 / 帧：1.00', p.stdout)
        self.assertIn('合计 0.50 ms', p.stdout)

    def test_table_file_path_is_accepted_directly(self):
        p0 = self.export('session/passes.tsv', [row(500, 2, 1.5)])
        p = self.run_tool(p0, '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('#2：1.500 ms', p.stdout)

    def test_legacy_name_alone_still_works(self):
        self.export('legacy/passgpu.tsv', [row(0, 4, 2.0)])
        p = self.run_tool(self.dir / 'legacy', '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('passgpu.tsv', p.stdout)
        self.assertIn('#4：2.000 ms', p.stdout)

    def test_legacy_header_names_still_read(self):
        # 旧表头把 inc_ms 叫 inc、fmt0 叫 cf、dfmt 叫 df：按位置回退，结果与真表头一致
        # the legacy header calls inc_ms 'inc', fmt0 'cf', dfmt 'df': positional fallback gives the same numbers
        self.export('old/passes.tsv', [row(0, 3, 0.4), row(1, 3, 0.6)], cols=LEGACY_COLS)
        p = self.run_tool(self.dir / 'old', '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('#3：0.500 ms', p.stdout)
        self.assertIn('8x8 fmt70 d0 L 1 绘制 R', p.stdout)

    def test_empty_frame_selection_is_reported_not_crashed(self):
        # 默认下限 300 会把从第 0 帧记起的设备导出整份筛空 | the default floor 300 empties an export that starts at frame 0
        self.export('session/passes.tsv', [row(0, 1, 0.5), row(5, 1, 0.5)])
        p = self.run_tool(self.dir / 'session')
        self.assertEqual(p.returncode, 1)
        self.assertIn('没有帧号 > 300 的行', p.stdout + p.stderr)
        self.assertNotIn('Traceback', p.stderr)

    def test_missing_table_names_both_accepted_files(self):
        (self.dir / 'empty').mkdir()
        p = self.run_tool(self.dir / 'empty', '-1', '5')
        self.assertEqual(p.returncode, 1)
        self.assertIn('passes.tsv', p.stdout + p.stderr)
        self.assertIn('passgpu.tsv', p.stdout + p.stderr)
        self.assertNotIn('Traceback', p.stderr)

    def test_rare_index_is_amortised_over_all_frames(self):
        # 10 帧；序号 1 每帧 0.5 ms，序号 7 只在第 0 帧出现 9 ms。
        # 每帧合计 = (10*0.5 + 9) / 10 = 1.4 ms；序号 7 的贡献 = 0.9 ms（64.3%），不是 9 ms。
        # 10 frames; index 1 costs 0.5 ms every frame, index 7 appears once (frame 0) at 9 ms.
        # Per-frame total = (10*0.5 + 9) / 10 = 1.4 ms; index 7 contributes 0.9 ms (64.3%), not 9 ms.
        rows = [row(f, 1, 0.5) for f in range(10)] + [row(0, 7, 9.0)]
        self.export('sparse/passes.tsv', rows)
        p = self.run_tool(self.dir / 'sparse', '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('#7：0.900 ms 64.3%', p.stdout)
        self.assertIn('#1：0.500 ms 35.7%', p.stdout)
        self.assertIn('出现 1 行 / 10 帧', p.stdout)
        self.assertIn('合计 1.40 ms（10 帧）', p.stdout)
        # 旧算法会把 9.0 + 0.5 = 9.5 ms 报成整帧合计 | the old arithmetic would report 9.0 + 0.5 = 9.5 ms as the frame total
        self.assertNotIn('合计 9.50', p.stdout)

    def test_index_absent_in_some_frames_counts_zero(self):
        # 序号 3 只在后 5 帧出现，每帧 1.0 ms → 每帧均值 0.5 ms，占比 50%（另有 5 帧的 0.5 ms 序号 1）
        # index 3 appears only in the last 5 frames at 1.0 ms -> 0.5 ms per frame, 50% share (index 1 costs 0.5 ms in all 10)
        rows = [row(f, 1, 0.5) for f in range(10)] + [row(f, 3, 1.0) for f in range(5, 10)]
        self.export('partial/passes.tsv', rows)
        p = self.run_tool(self.dir / 'partial', '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('#3：0.500 ms 50.0%', p.stdout)
        self.assertIn('出现 5 行 / 10 帧', p.stdout)
        self.assertIn('合计 1.00 ms（10 帧）', p.stdout)

    def test_mixed_metadata_is_not_pinned_to_last_row(self):
        # 同一个序号 2 在三帧里落在完全不同的通道上：旧工具会把第 3 行（256x256 fmt115 d260）当成 #2 的身份
        # the same index 2 lands on different passes in three frames: the old tool would present row 3 (256x256 fmt115 d260) as #2's identity
        rows = [row(0, 2, 0.2, w=64, h=32, load='C'),
                row(1, 2, 0.2, w=64, h=32, load='C'),
                row(2, 2, 0.2, w=256, h=256, load='L')]
        self.export('mixed/passes.tsv', rows)
        p = self.run_tool(self.dir / 'mixed', '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('#2：0.200 ms 100.0%', p.stdout)
        self.assertIn('混合 2 种元数据', p.stdout)
        # 主签名（2/3 行）只能作为「主」出现，不能单独充当身份 | the dominant signature (2 of 3 rows) may only appear labelled as dominant
        self.assertIn('主 64x32', p.stdout)
        self.assertNotIn('｜ 256x256', p.stdout)
        self.assertNotIn('｜ 64x32', p.stdout)

    def test_appended_serial_columns_uniform_and_varying(self):
        # 追加列（设备当前表头）：c0_ser / d_ser / fs_key 逐帧一致就报值，变化就报 ?，不借用最后一行的值
        # appended columns (the device's current header): uniform c0_ser / d_ser / fs_key are printed, varying ones print ? instead of borrowing the last row
        cols = COLS + ['c0_ser', 'd_ser', 'fs_key']
        rows = [row(0, 1, 0.5, c0=11, d=12, fs='fsA'),
                row(1, 1, 0.5, c0=11, d=12, fs='fsA'),
                row(0, 5, 0.5, c0=21, d=0, fs='fsB'),
                row(1, 5, 0.5, c0=22, d=0, fs='fsC')]
        self.export('ser/passes.tsv', rows, cols=cols)
        p = self.run_tool(self.dir / 'ser', '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('#1：0.500 ms', p.stdout)
        self.assertIn('［fsA c0:11 d:12］', p.stdout)
        self.assertIn('［? c0:? d:0］', p.stdout)   # fs 与 c0 变化、d 恒为 0 | fs and c0 vary, d stays 0
        self.assertNotIn('fsC', p.stdout)
        self.assertNotIn('c0:22', p.stdout)

    def test_frame_count_and_pass_count_are_true_means(self):
        # 4 帧，通道数 2/3/1/2 → 每帧 2.00 个通道；合计 = (0.1*2 + 0.2*3 + 0.3 + 0.1*2) / 4 = 0.325 ms
        # 4 frames with 2/3/1/2 passes -> 2.00 passes per frame; total = (0.1*2 + 0.2*3 + 0.3 + 0.1*2) / 4 = 0.325 ms
        rows = [row(0, 0, 0.1), row(0, 1, 0.1),
                row(1, 0, 0.2), row(1, 1, 0.2), row(1, 2, 0.2),
                row(2, 0, 0.3),
                row(3, 0, 0.1), row(3, 1, 0.1)]
        self.export('counts/passes.tsv', rows)
        p = self.run_tool(self.dir / 'counts', '-1', '5')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('通道数 / 帧：2.00', p.stdout)
        self.assertIn('合计 0.33 ms（4 帧）', p.stdout)


if __name__ == '__main__':
    unittest.main()
