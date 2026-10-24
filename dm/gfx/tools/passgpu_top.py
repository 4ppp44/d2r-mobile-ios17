# 逐通道 GPU：按帧内序号汇总时间线增量 inc_ms，再**除以选中的总帧数**（某帧没出现的序号记 0）；与同帧 @gpu_ms 对照
# （列见 nvn_mtl.m DM_NVN_PASSGPU 注释）。表尾可带 c0_ser / d_ser / fs_key 三列，旧表头（不带这三列）照旧可读。
# Per-pass GPU: aggregate the timeline increment inc_ms by in-frame index, then divide by the **total number of selected
# frames** (an index absent from a frame counts as zero); compare against @gpu_ms on the same frames (for the columns see
# the DM_NVN_PASSGPU comment in nvn_mtl.m). The trailing c0_ser / d_ser / fs_key columns are optional; the legacy header
# without them still reads fine.
#
# 为什么不能按「每个序号各自的出现次数」取均值：帧内序号每帧动态分配，稀有序号（只出现一两帧）会把自己的单次耗时
# 当成每帧成本，把整帧合计抬高数倍——真实设备导出实测 8.78 ms 被报成 27.85 ms，前列几乎全是只出现 1~4 帧的序号。
# 合计 = 所有行 inc 之和 / 帧数，所以每个序号的贡献必须用同一个分母，占比才有意义。
# Why not average each index over its own occurrence count: the in-frame index is assigned dynamically every frame, so a
# rare index (present in one or two frames) would present its single-pass duration as a per-frame cost and inflate the
# frame total several-fold - a real device export measuring 8.78 ms was reported as 27.85 ms, with nearly all top entries
# being indices present in only 1-4 frames. The total is the sum of all inc values over the frame count, so every index
# must use that same denominator for its contribution and share to mean anything.
#
# 元数据混用：同一个帧内序号在不同帧可能落在完全不同的通道上（种类 / 尺寸 / 格式 / 读入都变）。按
# (种类, 宽, 高, 颜色格式, 深度格式, 读入) 分组，多于一种就只报「混合 N 种（主 …）」，不把某一种当成该序号的身份；
# c0_ser / d_ser / fs_key 逐帧变化时报 ?，不借用某一帧的值冒充。
# Mixed metadata: the same in-frame index can land on entirely different passes in different frames (kind / size /
# formats / load action all change). Rows are grouped by (kind, w, h, color format, depth format, load); with more than
# one group only "mixed N kinds (dominant ...)" is reported, never one group as the index's identity; varying
# c0_ser / d_ser / fs_key are shown as ? instead of borrowing one frame's value.
#
# 输入：设备测量层把通道表导出为 <目录>/passes.tsv（dm_measurement.h 的 passes 角色），旧名 <目录>/passgpu.tsv 仅在缺前者时用；
# 也可直接给文件路径。只在给定目录里找，不在当前工作目录找——否则同名杂散文件会顶掉要分析的导出。
# Input: the device measurement layer exports the pass table as <dir>/passes.tsv (the passes role in dm_measurement.h); the legacy
# <dir>/passgpu.tsv is used only when the former is absent. A file path is accepted directly. Lookup is confined to the given
# directory, never the current working directory, so a stray same-named file cannot silently replace the export under analysis.
import sys, os, collections, itertools, statistics as S

if len(sys.argv) < 2:
    sys.exit('用法：passgpu_top.py <目录|文件> [帧下限] [前列数]\nusage: passgpu_top.py <dir|file> [min_frame] [top_n]')
A = sys.argv[1]
F0 = int(sys.argv[2]) if len(sys.argv) > 2 else 300
NTOP = int(sys.argv[3]) if len(sys.argv) > 3 else 10
if os.path.isfile(A):
    PATH, X = A, os.path.dirname(A) or '.'
else:
    X = A
    PATH = next((p for p in (os.path.join(X, 'passes.tsv'), os.path.join(X, 'passgpu.tsv')) if os.path.isfile(p)), None)
    if not PATH: sys.exit('没有通道表：%s 下找不到 passes.tsv（旧名 passgpu.tsv 也接受），也不是文件路径' % X)

# 列按表头名字定位（新 / 旧表头通用）；表头缺失时退回位置约定。注释行与空行跳过。
# Columns are located by header name (new / legacy alike); without a header the positional convention is used. Comment
# and blank lines are skipped.
REQ = {'frame': 0, 'idx': 1, 'kind': 2, 'inc_ms': 4, 'w': 5, 'h': 6, 'fmt0': 7, 'dfmt': 8, 'load': 9, 'draws': 10}
OPT = ('c0_ser', 'd_ser', 'fs_key')

def lines(path):
    with open(path, errors='replace') as fh:
        for l in fh:
            l = l.rstrip('\n').rstrip('\r')
            if l.strip() and not l.lstrip().startswith('#'):
                yield l.split('\t')

it = lines(PATH)
first = next(it, None)
if first is None: sys.exit('%s：没有数据行' % PATH)
header = [p.strip() for p in first] if first[0].strip().lower() == 'frame' else None
data = it if header is not None else itertools.chain([first], it)   # 无表头时首行就是数据 | without a header the first line is data
if header is not None:
    # 名字优先，缺名字的列退回位置约定（旧表头把 inc_ms 写成 inc / ms 也照样读）
    # Name first, positional convention for columns the header omits (legacy headers name inc_ms 'inc' or 'ms' and still read)
    C = {k: (header.index(k) if k in header else REQ[k]) for k in REQ}
    CO = {k: (header.index(k) if k in header else None) for k in OPT}
else:
    C = dict(REQ)
    CO = {k: None for k in OPT}

sums = collections.defaultdict(float)              # 序号 -> 选中帧内 inc 之和 | index -> sum of inc over selected frames
counts = collections.defaultdict(int)              # 序号 -> 出现行数（正常每帧一行）| index -> rows seen (normally one per frame)
sigs = collections.defaultdict(collections.Counter)  # 序号 -> 元数据签名计数 | index -> metadata signature counts
sigrow = {}                                        # (序号, 签名) -> 代表行 | (index, signature) -> representative row
ser = collections.defaultdict(dict)                # 序号 -> {c0, d, fs}，值变化则记 '?' | index -> serials, '?' when they vary
per = collections.defaultdict(float)               # 帧 -> 该帧 inc 之和 | frame -> sum of inc in that frame
rows_sel = 0

def cell(r, k, default='?'):
    j = C[k]
    return r[j] if j is not None and j < len(r) else default

def ser_note(store, key, val):
    if key not in store: store[key] = val
    elif store[key] != val: store[key] = '?'

for r in data:
    if len(r) < 5: continue
    try:
        f = int(r[C['frame']]); i = int(r[C['idx']]); v = float(r[C['inc_ms']])
    except (ValueError, IndexError, TypeError):
        continue
    if f <= F0: continue
    sums[i] += v
    counts[i] += 1
    per[f] += v
    rows_sel += 1
    sig = (cell(r, 'kind'), cell(r, 'w'), cell(r, 'h'), cell(r, 'fmt0'), cell(r, 'dfmt'), cell(r, 'load'))
    sigs[i][sig] += 1
    sigrow.setdefault((i, sig), r)
    for key, name in zip(('c0', 'd', 'fs'), OPT):
        j = CO[name]
        if j is not None and j < len(r): ser_note(ser[i], key, r[j])

# 设备 gpu 测量档从第 0 帧记起，默认下限 300 会把整份导出筛空；此时必须说明，而不是在空统计上抛异常
# The device gpu profile records from frame 0, so the default floor of 300 can empty the whole export; say so instead of
# raising on empty statistics
if not per: sys.exit('%s：没有帧号 > %d 的行（设备导出从第 0 帧记起，帧下限用 -1）' % (PATH, F0))

NF = len(per)
g = {}
try:
    for l in open(os.path.join(X, 'frames.tsv'), errors='replace'):
        p = l.rstrip('\n').rstrip('\r').split('\t')
        if len(p) == 3 and p[0].isdigit() and p[1] == '@gpu_ms':
            g[int(p[0])] = float(p[2])
except FileNotFoundError:
    pass
c = [f for f in per if f in g]
pv = sorted(per.values())
p95 = pv[min(len(pv) - 1, int(len(pv) * .95))]
extra = '；同帧 @gpu_ms p50 %.2f ms' % S.median(g[f] for f in c) if c else ''
print('文件 %s；帧数 %d；每帧增量之和 p50 %.2f / p95 %.2f ms；平均每帧 %.2f ms%s' %
      (PATH, NF, S.median(pv), p95, sum(per.values()) / NF, extra))

tot = sum(sums.values()) / NF     # 每帧合计（缺失序号记 0）| per-frame total, absent indices counted as zero
print('前列（帧内序号：每帧均值 ms，占比 ｜ 尺寸 颜色格式 深度格式 读入 绘制数 种类）')
for k in sorted(sums, key=lambda k: -sums[k])[:NTOP]:
    m = sums[k] / NF
    share = 100 * m / tot if tot else 0
    variants = sigs[k]
    if len(variants) == 1:
        sig = next(iter(variants))
        r = sigrow[(k, sig)]
        body = '%sx%s fmt%s d%s %s %s 绘制 %s' % (sig[1], sig[2], sig[3], sig[4], sig[5], cell(r, 'draws'), sig[0])
        if CO['c0_ser'] is not None:
            body += ' ［%s c0:%s d:%s］' % (ser[k].get('fs', '?'), ser[k].get('c0', '?'), ser[k].get('d', '?'))
    else:
        sig, n = variants.most_common(1)[0]
        r = sigrow[(k, sig)]
        body = '混合 %d 种元数据（主 %sx%s fmt%s d%s %s %s 绘制 %s，%d/%d 行）' % (
            len(variants), sig[1], sig[2], sig[3], sig[4], sig[5], cell(r, 'draws'), sig[0], n, counts[k])
        if CO['c0_ser'] is not None:
            body += ' ［%s c0:%s d:%s］' % (ser[k].get('fs', '?'), ser[k].get('c0', '?'), ser[k].get('d', '?'))
    if counts[k] != NF: body += ' ［出现 %d 行 / %d 帧］' % (counts[k], NF)
    print('  #%d：%.3f ms %4.1f%% ｜ %s' % (k, m, share, body))
print('通道数 / 帧：%.2f（不同帧内序号 %d）；合计 %.2f ms（%d 帧）' % (rows_sel / NF, len(sums), tot, NF))
