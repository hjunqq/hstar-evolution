# M2-03：两例状态证据与单字段扰动

- 日期：2026-09-07
- 范围：static_2d 两例（cooks_membrane、lame_cylinder）的 S01 重复证据、S03 单字段扰动检出、状态基线冻结
- 依赖：M2-02（`4448d9c`）的导出、规范化与比较器

## 1. 结论

`docs/02` 的 M2 三条出口条件全部有可复跑证据：

| 出口条件 | 证据 | 结果 |
|---|---|---|
| 相同输入三次运行得到相同摘要 | `evidence/repeat-state-<case>.json` | 两例各 3 次，指纹相同，3 对两两比较 PASS |
| 人为改一个材料/约束/荷载，diff 指出准确位置 | `evidence/S03-report.json` + `evidence/S03-diffs/` | 4/4 命中，各恰好 1 条主 MISMATCH |
| 摘要生成不改变求解结果 | 本文 §4 与 M2-02 §5 | dump 开/关 `1.flavia.res` 逐字节相同，`yl_compare` max\|d\|=0 |

## 2. 工具

`tools/yl_state_probe.py`（复用 `yl_probe.py` 的物化 / derive / 写保护，不修改它）：

| 子命令 | 作用 |
|---|---|
| `freeze --case --from` | 从一次 COMPLETED 的 dump-on 运行**复制**状态树到 `cases/golden/static_2d/<case>/reference/state`，并写 `reference/frozen.json`（逐文件 sha256 + provenance）。目标已存在即拒绝，无 `--force`；**绝不把 `yl_state.normalize` 的输出指向 reference**（`yl_state.py:702` 会 `rmtree` 输出目录）。写入前按树内在特征交叉校验归属：从 `derived.counts.npoin/nelem` 与两个 mesh id 向量长度读出节点/单元数，必须与目标算例 `observables.toml` 登记的数目一致，两个数都没登记则拒绝冻结；读数记入 `frozen.json` 的 `case_identity` |
| `verify --case` | 按 `frozen.json` 逐文件核对摘要；每次 `run` 前自动执行 |
| `repeat --case --binary` | 同一二进制 N 次 dump-on 运行，断言全部 COMPLETED、指纹相同、两两比较 PASS，产出 S01 报告 |
| `run [--ids]` | 物化 → 单点 `set_field` → 运行 → 与冻结基线比较 → 按 `[expect_state]` 断言 |
| `--selftest` | 47 项自检，含**空扰动必须判失败**、白名单越界在加载期失败、原 token 不符即失败、冻结目标已存在即拒绝、路径逃逸拒绝 |

断言只读比较器的 JSON 报告，不解析文本；文本全量存档到 `evidence/S03-diffs/<id>.txt`。

## 3. S03 探针矩阵

四条探针，每条只改一个输入 token，比较器均 exit 1、`struct=0 mismatch=1 compared=190 skipped=79`：

| 探针 | 编辑 | 命中字段 | path |
|---|---|---|---|
| `S03_E_cooks` | `1.mat:20` token5 `2.500E+10`→`2.600E+10` | `materials.E` | `materials[1].E` |
| `S03_E_lame` | 同上（lame_cylinder） | `materials.E` | `materials[1].E` |
| `S03_BC_cooks` | `1.pre:5` token1 `17*0.`→`1.0e-3,16*0.` | `steps0.boundary.value` | `steps[0].boundary[set=1,rec=1,node=1].value` |
| `S03_G_cooks` | `1.loa:14` token1 `9.81000E+00`→`9.80000E+00` | `steps0.load.gravity.magnitude` | `steps0.load.gravity.magnitude` |

要点：
- `.pre` 的值记录是 Fortran 重复计数 ` 17*0.`；只改第一个值必须写成单个 token `1.0e-3,16*0.`（逗号是 list-directed 分隔符），改成 `17*1.0e-3` 会同时改 17 个值。34 个边界值中恰好 1 个变化（`count=1/34`）。
- 只有 `S03_BC_cooks` 会打印 `count=` 续行；单叶子字段（nmats=1 的 `materials.E`、标量 `gravity.magnitude`）不打印，断言方按叶子数记 1。
- **R24 被编码为测试**：`S03_BC_cooks` 的 `forbid_fields` 要求 `runtime.dof.fixed` 与 `runtime.dof.fixed_at_increment` 不出现且保持全零——`modf_var_prescribed` 在 `Fem.f90:3667` 才运行，晚于所有检查点，所以约束此时只体现在 prescribed 值上。报告的 `zero_in_reference` 字段把这一点写成显式证据。
- `forbid_fields` 的全零要求是**按基线判定**的：基线中该字段全零则扰动后必须仍全零；基线中本就非零（如 `materials.density`、`gravity.direction`）则只要求不出现在任何 finding 中。
- `forbid_fields` 不允许写"空转"条目：加载期拒绝 compare 规则为 `ignore`、`emit = "none"` 或不在冻结基线中的字段——禁用一个从不导出的字段等于什么都没断言。报告里 `exported` 为假时 `all_zero` 记为 null 而非 true。

## 4. 冻结基线

`cases/golden/static_2d/<case>/reference/state/`（每例 40 个文件：3 检查点 × 13 + `fingerprint.json`），cooks 592 KB、lame 280 KB。
`reference/frozen.json` 记录逐文件 sha256 与 provenance：source commit、binary sha256、build-manifest、map sha256、normalizer 版本、来源 run id 与输入哈希。
既有的 `results.json`、`run-manifest-*.json`、`repeat-report.json`、`build-manifest.json` 未被改动。

指纹（release 二进制 `445090142419dcb0…`）：cooks `547e53a8fc6c…`、lame `7c2edf39a342…`。按 R26，指纹判据只在同一二进制内成立；跨构建的等价性由比较器判定。

## 5. 验证记录（2026-09-07）

| 项 | 判据 | 结果 |
|---|---|---|
| S01 | 两例 × 3 次，指纹相同、3 对两两 PASS、字段 162/11/17 | PASS |
| S03 | 4 条探针命中预期字段与 path，恰好 1 条主 MISMATCH，无越界字段 | 4/4 PASS |
| 非干扰 | dump 开/关 `1.flavia.res` 逐字节相同；`yl_compare` max\|d\|=0 | PASS |
| 冻结 | `verify` 两例 files=40 PASS；重复 freeze 被拒绝 | PASS |
| 自检 | `yl_state_probe.py --selftest` | 47/47 |
| 回归 | 探针 47/47、`--check-legacy` 6/6 | PASS |

## 6. 证据文件的路径处理

`docs/m2/evidence/**` 中的绝对路径在归档前被替换：会话临时目录写成 `<scratch>`，仓库根写成相对路径。
目的是让证据可跨机器比对，代价是无法据此复跑原始命令；复跑方式见 §2 的子命令与 `cases/probes/state/README.md`。

`cases/golden/static_2d/*/reference/frozen.json` **保留**绝对路径（binary、build manifest、case dir、来源 run），
因为它是 provenance 记录而非可移植证据：它要回答"这棵树是谁、在哪、用什么二进制生成的"。
跨机器复核时只应依赖其中的 sha256 与 commit，不应依赖路径。

## 7. 范围与盲区

- 79 个 `ignore` 字段未被证明；`restart_ready` 未覆盖。
- R25：`nextr` 无持久留存，快照无法证明外推行为等价。
- R26：指纹跨 profile 不可比。
- 扰动只覆盖材料 E、一个约束值、重力大小三类；其余字段的可检出性由 S02 的结构护栏与 S03 的机制推广，未逐字段验证。
