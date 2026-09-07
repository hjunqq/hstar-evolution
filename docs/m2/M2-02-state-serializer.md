# M2-02：状态序列化与比较器

- 日期：2026-09-07
- 范围：static_2d 路径三个 covered 检查点的状态导出、规范化、指纹与比较器；`restart_ready` 不导出
- 配套：`docs/m2/state-field-map.toml`（权威契约）、`docs/m2/M2-01-checkpoints.md`（锚点）、`docs/m2/evidence/`

## 1. 组成

| 件 | 位置 | 说明 |
|---|---|---|
| 写出器 | `src/state/yl_state_io.f90` | 手写；`state_writer_t` + `state_open/state_close/begin_field/end_field/put_i32/put_f64/put_str/state_fail`；自带 iostat/iomsg，不复用 `yl_ios/yl_msg`；`access='stream', form='formatted'`，行尾 LF |
| adapter | `src/state/yl_state_adapters.f90` | 手写；25 个 `emit_<name>(w)`，处理 ragged、重建与概念字段 |
| 导出模块 | `src/state/yl_state_dump.f90` | **生成文件，请勿手改**：`python3 tools/yl_state_map.py gen-fortran` |
| 开关 | `src/diagnostics/yl_diag.f90` | `--dump-state=DIR`；与 `--check-legacy` 互斥（任一顺序 PARSE exit 2） |
| 插桩 | `legacy/yl/Fem.f90` | 第 10 行 `use yl_state_serializer`；三处 `if (yl_dump_enabled) call yl_state_dump(...)`（:1908 / :3602 / :3656） |
| 规范化 | `tools/yl_state.py` | `normalize` → 九文件 + `fingerprint.json`；`fingerprint` 复核 |
| 比较器 | `tools/yl_state_diff.py` | 结构优先、按规则比值；`--selftest`、`--snapshot` |
| 运行器 | `tools/yl_run.py` | `--dump-state`，manifest 新增 `state` 块（schema 同步） |

## 2. 线格式（Fortran → Python）

```
HSTAR_STATE schema=1 checkpoint=<raw id> fields=N
field=<id> key=[..] shape=[..] dtype=i32|f64|str values=[..]
HSTAR_STATE_END fields=N
```

- 目录名用 sanitize 后的 id（`phase_ready_1`），**报文头用原始 id**（`phase_ready(1)`）。
- `key=[]` 是稠密标记，等同于无 key；ragged 一行一外键，key 可为多元组（外维在前）。
- `f64` 为 IEEE-754 位模式的 16 位大写十六进制（大端整数形式，`transfer` + `Z16.16`）；`i32` 十进制；`str` 为 `x`+字节十六进制（空为 `x`），不解码 GBK。
- dense 值按 Fortran 序（首维最内）。`fields=N` 计逻辑字段数，不计记录数。

## 3. 规范化与指纹

九个文件按 `docs/01 §5`：`control.json`、`mesh.sha256`、`dof.sha256`、`groups.json`、`materials.json`、`constraints.sha256`、`loads.sha256`、`steps.json`、`numerics.json`；四个 `.sha256` 旁边有同名 `.json`，摘要覆盖其确切字节。
`ntotv` 索引数组经 `nodfn` 重键为 `(node, dof)` 并断言到 `1..ntotv` 的双射；两条 `reconstruct` 配方在导出值旁校验。

**指纹只在同一二进制内可比。** `runtime.gauss.gpcod/cartd/djacb` 是读入时计算的派生浮点，release（-O2）与 debug/strict（-O0）末位不同，映射表已按 `abs_tol` 登记；`yl_state_diff` 跨 profile 判 PASS，而 `fingerprint.json` 是逐位摘要，因而跨 profile 不同。这与 `docs/01 §5`"哈希用于识别完全相同的数据，带容差的浮点比较必须读取结构化值"一致：**跨构建的等价性由比较器判定，不由指纹判定**（登记为 R26）。

## 4. 比较器

结构优先，再按 `compare.rule` 比值。结构问题会抑制该字段的值比较。

```
STRUCT stage=<cp> [file=] [field=] problem=<kind> [path=] [expected=] [actual=]
MISMATCH stage=<cp> field=<id> path=<object.path[i].attr> rule=<rule> expected= actual= unit= source=<reader id> legacy=<symbol>
SKIPPED  stage=<cp> field=<id> rule=ignore reason=<..>
```

续行缩进两格：容差的 `diff=/atol=/rtol=/worst_path=`、精确数组的 `count=n/total`、`--expand-hash` 的 `first_diff=`、以及 `secondary_of=<primary id>`。
退出码 0 通过 / 1 仅值不符 / 2 有结构问题 / 3 用法错误。

ragged 字段（`shape: null`）按**逐层长度树**比较：任一外键下的列表长度不同即 `problem=length` 并给出该键的路径；因此"某集合少一个节点"与"节点在集合间迁移但扁平序列不变"都会被拒绝。字段集合由映射表的非 ignore 期望集与两棵树的并集共同驱动，两侧都缺的字段也会报 `missing`；covered 检查点在 reference 侧缺失同样是结构问题（`detail=reference`）。

## 5. 验证记录（2026-09-07）

| 项 | 判据 | 结果 |
|---|---|---|
| 构建 | release/debug/strict，0 warning | PASS |
| dump 关 × 三 profile × 两例 | `yl_compare` max\|d\|=0 | 6/6 PASS |
| dump 开 × 三 profile × 两例 | COMPLETED；max\|d\|=0；`1.flavia.res` 与 dump 关逐字节相同 | 6/6 PASS |
| S01 重复运行 | release × 两例各 3 次，指纹相同 | PASS（cooks `547e53a8fc6c`、lame `7c2edf39a342`） |
| 跨 profile 状态等价 | `yl_state_diff` release vs debug | PASS compared=190 skipped=79 |
| S02 反例 | 九类在真实快照上全部命中，定位到对象与字段 | 9/9，见 `evidence/S02-negatives.json` |
| 比较器护栏 | ragged 长度变化、跨集合重组（扁平序列不变）、reference 侧缺检查点、两侧都缺字段 | 4/4 命中（Round 1 审查发现的 fail-open，已修） |
| 探针 | F01–F34 + N01–N18 | 47/47 PASS |
| `--check-legacy` | 三 profile × 两例 | 6/6 CHECKED |
| 互斥 | 两种参数顺序 | 均 PARSE exit 2 |
| 注册表 | M1 `check`、wrap `--dry-run`、M2 `check` | PASS / 0 edits / PASS |
| 证据重采 | `yl_io_trace.sh` 两例 | 211 位点、767/367 命中不变；结果与 reference 相同 |
| 工具自测 | `yl_state_map`/`yl_state`/`yl_state_diff` | 88/88、42/42、9 类 12 检查 |

字段规模：269 登记，190 导出（model_ready 162 / phase_ready(1) 11 / increment_ready(1,1) 17），79 `ignore`。

## 6. 已知盲区

- **R25**：`nextr` 是 `prescrib_set` 局部量且无任何持久留存（`tfixvar` 经 `iffix=tfixvar+1` 留存，`nextr` 走 `Prescrib.f90:261-268` 另一分支），快照无法证明外推行为等价；两例 `nextr=0`。
- **R26**：指纹跨 profile 不可比（见 §3）。
- `runtime.topology.unode_np_unode/patch_nod` 只在 `stabpw==1` 且 P/W 场分支初始化，本路径未定义，已 `ignore`；未定义关联状态的指针连 `associated()` 都不调用。
- `materials.kind/phase`、`derived.counts.nphase` 是本路径的重建值，不能证明任意 deck 的表头计数。

## 7. 维护

任何 `legacy/yl` 插桩或行号变动后：重定位 M1 `site` 与 M2 `[[checkpoint]].site` → `yl_io_inventory.py scan` → `yl_io_trace.sh` 两例 → `yl_io_inventory.py gen-fortran` → `yl_io_inventory.py check` → `yl_wrap_reads.py --dry-run`（须 0 edits）→ `yl_state_map.py check` → `yl_state_map.py gen-fortran` → 最后重生成 `legacy/source-manifest.json`。
