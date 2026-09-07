# 状态扰动探针（M2-03 / S03）

每个子目录是一条探针：`<probe_id>/probe.toml` 描述"从哪个 golden 算例派生、改哪一个输入 token、
状态比较器必须报出哪一条 MISMATCH"。运行器是 `tools/yl_state_probe.py`；探针**不复制 deck**，
运行时才从 `cases/golden/static_2d/<name>/` 物化到 `runs/probes-state/<id>/case/`，沿用
`yl_probe.py` 的写保护判据（`--runs-root` 不得位于 `cases/` 之下；derive 的 `file` 必须是裸文件名）。

与 `cases/probes/failure/` 的区别：那边的判据是二进制的 `HSTAR_DIAG` 报文（输入必须被拒绝），
这边的判据是**运行成功之后**的状态快照差分——扰动必须在 `model_ready` 检查点上被恰好一个字段看见。

```
python3 tools/yl_state_probe.py list
python3 tools/yl_state_probe.py verify --case static_2d.cooks_membrane   # 核对冻结基线摘要（case id 含 static_2d. 前缀）
python3 tools/yl_state_probe.py run \
    --binary build/release/hstar \
    --diffs-dir docs/m2/evidence/S03-diffs \
    -o docs/m2/evidence/S03-report.json          # 全矩阵；不带 -o 时默认写 <runs-root>/state-probe-report.json
python3 tools/yl_state_probe.py run --ids S03_E_cooks
python3 tools/yl_state_probe.py --selftest                     # 护栏自检（空扰动必须判失败）
```

每条探针的执行链：物化 golden → 应用唯一 `set_field`（先核对 `original_token`，改后核对恰好该
token 变化）→ 重生成 `input-manifest.json` → `yl_run.py --dump-state`（须 COMPLETED、rc=0、
`state.normalize.ok`）→ `yl_state_diff.py <case>/reference/state <run>/state -o report` →
按 `[expect_state]` 断言 JSON 报告（不解析文本；文本全量存档到 `docs/m2/evidence/S03-diffs/<id>.txt`）。

## 探针矩阵

| 探针 | 算例 | 派生（`set_field`） | 目标字段 / path | 证明什么 |
|---|---|---|---|---|
| `S03_E_cooks` | cooks_membrane | `1.mat` 第 20 行 field 5 `2.500E+10`→`2.600E+10` | `materials.E` / `materials[1].E` | 单个材料标量的改动被状态快照捕获；E 只被 `STIFF_U` 消费，`model_ready` 上无派生字段，故必须恰好一条主 MISMATCH |
| `S03_E_lame` | lame_cylinder | 同上（该例 `1.mat` token 布局相同） | `materials.E` / `materials[1].E` | 同一扰动在第二个算例（npoin 81 / nelem 64、边界集顺序不同）上同样被检出——检出能力属于序列化器而非某一个 deck |
| `S03_BC_cooks` | cooks_membrane | `1.pre` 第 5 行 field 1 `17*0.`→`1.0e-3,16*0.` | `steps0.boundary.value` / `steps[0].boundary[set=1,rec=1,node=1].value` | 34 个边界值中恰好 1 个变动，命中集合 1 的第一个节点；同时把 **R24** 变成测试：`runtime.dof.fixed` / `runtime.dof.fixed_at_increment` 必须未出现（`modf_var_prescribed` 在 `Fem.f90:3667` 才运行，晚于 `model_ready` 锚点） |
| `S03_G_cooks` | cooks_membrane | `1.loa` 第 14 行 field 1 `9.81000E+00`→`9.80000E+00` | `steps0.load.gravity.magnitude` | 荷载块对求解器尚未消费的标量敏感；`gcom=factg*gravy*tdensity*thick`（`Load.f90:1268`）在锚点之后才形成，方向因子与幅值曲线必须保持不变 |

## 出口条件映射

| M2-03 出口条件 | 由哪些探针覆盖 |
|---|---|
| S03「状态快照能定位单点扰动到具体字段与具体索引」 | 四条全部：`comparator_exit=1`、恰好一条 `secondary_of == null` 的 MISMATCH、`stage`/`field`/`path`/`rule`/`expected`/`actual` 逐字匹配 |
| S03「扰动不得溢出到无关字段」 | `allow_secondary = []`（加载期按映射表 `derived_from` 闭包校验）+ 各探针的 `forbid_fields` |
| R24「`model_ready` 上约束尚未落到 dof」 | `S03_BC_cooks` 的 `forbid_fields = ["runtime.dof.fixed", "runtime.dof.fixed_at_increment"]` |
| 跨算例可移植性 | `S03_E_cooks` + `S03_E_lame` 同一扰动、同一期望 |
| 护栏（"没检出"必须判失败） | `yl_state_probe.py --selftest` 的空扰动用例，不在本矩阵内 |

## probe.toml

```toml
schema = 1
id = "S03_E_cooks"                      # 必须与目录名一致
base_case = "static_2d.cooks_membrane"  # cases/golden/static_2d/cooks_membrane
description = "..."

[[derive]]                  # 恰好一条；文本按 latin-1 字节处理，保留原换行（CRLF/LF）
op = "set_field"            # 替换第 field 个空白分隔 token
file = "1.mat"
line = 20                   # 1-based 物理行
field = 5                   # 1-based token 序号
value = "2.600E+10"
original_token = "2.500E+10"   # 改动前的 token；不符即拒绝运行（防规格过期）

[expect_state]
comparator_exit = 1         # 值不符；结构性扰动才用 2
mismatch_count  = 1         # secondary_of == null 的 MISMATCH 条数
stage = "model_ready"       # 检查点
field = "materials.E"       # 映射表字段 id
path  = "materials[1].E"    # 报文 path 逐字匹配
rule  = "exact"
expected = "2.5e+10(42174876E8000000)"   # short_float(值)(IEEE-754 大端十六进制)
actual   = "2.6e+10(421836E210000000)"
changed_values = 1          # 该字段内变动的叶子个数（报文 count=1/34 的分子）
allow_secondary = []        # 允许出现的 secondary 字段白名单
forbid_fields = ["materials.density", "materials.nu"]   # 必须未出现
```

`expected` / `actual` 的写法由 `tools/yl_state_diff.py` 的 `show()` 决定：最短可回环的科学计数
十进制 + 括号内 IEEE-754 大端十六进制（`0.0` → `0e+00(0000000000000000)`）。
单叶子字段（`materials.E` 在 nmats=1 时、标量 `steps0.load.gravity.magnitude`）不会打印
`count=` 续行——`changed_values` 仍按叶子数记 1。

## 数值来源

四条探针的 `expected` / `actual` / `path` **全部为实测值**，逐字抄自比较器输出，无预测项。
`S03_E_cooks` / `S03_E_lame` / `S03_G_cooks` 由 2026-09-07 的 M2-03 Layer 2 运行测得
（release 二进制 sha256 前缀 `4450901424`，基线为冻结候选的 M2-03 r1 运行）；
`S03_BC_cooks` 由更早的一次 release 运行测得（基线为 M2-02 的 r1 快照）。
四条的比较器汇总行均为 `FAIL struct=0 mismatch=1 compared=190 skipped=79`，退出码 1。

其中只有 `S03_BC_cooks` 会打印 `count=` 续行（`count=1/34`）：另外三条命中的是单叶子字段
（nmats=1 时的 `materials.E`、标量 `steps0.load.gravity.magnitude`），而 `yl_state_diff` 以
`total > 1` 为门限才输出该续行。断言方按叶子数记 `changed_values = 1`，不要去解析 `count=`。

`[expect_state]` 不含 `unit` / `source` / `legacy`：`Finding.as_json()` 只导出
`kind/stage/file/field/problem/path/rule/expected/actual/secondary_of/text`，这三项仅存在于
`text` 里，断言它们就得回去做文本子串匹配，与"断言读 JSON 报告"的契约冲突；且它们本就由
映射表的 `unit` / `source` / `legacy_symbol` 固定，已有独立校验，在探针里重复一遍只会多一处漂移点。
