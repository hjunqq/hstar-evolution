# 故障注入探针（M1-02 / M1-03）

每个子目录是一条探针：`<probe_id>/probe.toml` 描述"从哪个 golden 算例派生、破坏哪个输入文件、
期望二进制给出什么诊断"。运行器是 `tools/yl_probe.py`；探针**不复制 deck**，
运行时才从 `cases/golden/<family>/<name>/` 物化到 `runs/probes/<id>/case/`。

```
python3 tools/yl_probe.py list
python3 tools/yl_probe.py run                       # 全矩阵 → runs/probes/report.json
python3 tools/yl_probe.py run --ids F20 F01         # 按 id 或唯一前缀
python3 tools/yl_probe.py run --materialize-only    # 只派生不运行（自测）
```

## probe.toml

```toml
schema = 1
id = "F20_cor_eof"                      # 必须与目录名一致
base_case = "static_2d.cooks_membrane"  # cases/golden/static_2d/cooks_membrane
description = "..."

[[derive]]                 # 依次作用于 case/legacy/，文本按 latin-1 字节处理，保留原换行（CRLF/LF）
op = "truncate_lines"      # delete_file | empty_file | truncate_lines(keep) | truncate_bytes(keep)
file = "1.cor"             #   | replace_line(line, text) | replace_token(line, old, new, count=1, occurrence=1)
keep = 200

[expect]
status = "INPUT_ERROR"     # run-manifest.json 的 status
exit_code = 2              # 进程退出码
code = "EOF"               # 首条 HSTAR_DIAG 的 code：FILE_MISSING | EOF | PARSE
stage = "startup"          # startup | phase_lazy(1) | increment_lazy(1,1) | solver_lazy
file_suffix = ".cor"       # DIAG 的 file 以此结尾：读错误给扩展名（".cor"），缺文件给实际文件名（"1.cor"）
reader = "COR.global_data.node_coordinates"   # 可省略；给出时必须与 docs/m1/reader-inventory.toml 的 id 完全一致
index = 201                # 可省略；循环读取的记录序号
no_core = true             # outputs 中不得出现 core*
max_wall_seconds = 10      # 传给 yl_run.py --timeout；防 call exit 在运行时挂起
```

`reader` / `index` 省略的探针只核对 status、exit_code、code、stage、file_suffix、no_core。派生按 LF 分行（CRLF 保留，裸 CR 不分行），物化后行数与原文件一致。

## 语义探针矩阵（M1-03，N01–N18，2026-09-07 全部 PASS）

所有探针 base_case 为 `static_2d.cooks_membrane`（npoin=289、nelem=256、nmats=1、ngroup=1、mdofn=2、ntcurve=1），期望 `no_core=true`；
exit 2 / `INPUT_ERROR` 除非注明 exit 3 / `UNSUPPORTED`。派生原语：`set_field(file,line,field,value)` 替换第 field 个空白分隔 token，
`insert_line(file,after,text)`，`duplicate_line(file,line,count)`。断言除 M1-02 的 status/code/stage/file/reader/index 外，还有
`value`（首条报文 `value=` 精确）、`field`（首条 `field=` 子串）、`diag_count`（报文条数）、`indices`（全部报文 index 顺序）；
`binary_args` 顶层键传给二进制（N02 用 `--max-entities=100000`）。

| 探针 | 派生 | code | reader（index） | field=value |
|---|---|---|---|---|
| N01_glb_npoin_negative | 1.glb 第 2 行 field 1 `289`→`-5` | RANGE | GLB.global_data.sizes_and_switches | npoin=-5 |
| N02_glb_npoin_huge | 同上 →`99999999`，`--max-entities=100000` | RANGE | 同上 | npoin=99999999（allowed 1..100000；随后还有 npoin×ndimn 两条乘积报文） |
| N03_glb_nelem_negative | 第 2 行 field 3 `256`→`-1` | RANGE | 同上 | nelem=-1 |
| N04_glb_ndimn_unsupported | 第 2 行 field 4 `2`→`4` | UNSUPPORTED（exit 3） | 同上 | ndimn=4 |
| N05_glb_matno_out_of_range | 第 59 行（组头）field 10 `1`→`7` | REF | GLB.global_data.group_header（1） | matno=7 |
| N06_glb_index_unsupported | 第 59 行 field 3 `5`→`999` | UNSUPPORTED（exit 3） | 同上（1） | index=999 |
| N07_glb_nelgroup_sum_mismatch | 第 59 行 field 9 `256`→`255` | RANGE | 同上（1，组循环末） | nelgroup=255（allowed 256..256） |
| N08_ele_lnods_out_of_range | 1.ele 第 1 行 field 2 `1`→`300` | REF | ELE.read_element.element_connectivity（1） | lnods=300；diag_count=1，indices=[1] |
| N09_ele_lnods_accumulated | 第 1/3/5 行各改一个节点为 0 / 290 / -1 | REF | 同上（1） | lnods=0；diag_count=3，indices=[1,3,5] |
| N10_cor_duplicate_id | 1.cor 第 2 行 field 1 `2`→`1` | DUPLICATE | COR.global_data.node_coordinates（2） | i0=1 |
| N11_mat_imat_out_of_range | 1.mat 第 17 行 field 3 `1`→`2` | RANGE | MAT.material_set.material_header | imat=2 |
| N12_mat_imat_duplicate | 1.glb nmats→2、1.mat nmats→2 并插入第二个材料块（imat 仍为 1） | DUPLICATE | 同上 | imat=1 |
| N13_pre_itcurve_out_of_range | 1.pre 第 3 行 field 3 `0`→`5` | REF | PRE.prescrib_set.set_header（1） | itcurve=5 |
| N14_pre_nfixnods_too_large | 第 3 行 field 2 `17`→`300` | RANGE | 同上（1） | nfixnods=300 |
| N15_pre_list_fix_out_of_range | 第 4 行 field 1 `1`→`290` | REF | PRE.prescrib_set.set_nodes（1） | list_fix=290 |
| N16_pre_ifixvar8_zero_curve | 第 3 行 field 1 `1`→`8`（itcurve 仍 0） | REF | PRE.prescrib_set.set_header（1） | itcurve=0（R18：水位集合必须有曲线；随后还有 ifixvar 越界 RANGE） |
| N17_loa_tcurvegravity_out_of_range | 1.loa 第 16 行 field 1 `1`→`3` | REF | LOA.external_load_2.gravity_curves | tcurvegravity=3 |
| N18_loa_ntcurve_negative | 第 2 行 field 1 `1`→`-1` | RANGE | LOA.external_load_1.curve_count | ntcurve=-1 |

## 结构探针矩阵（M1-02，29 条，2026-09-07 全部 PASS）

所有探针 base_case 均为 `static_2d.cooks_membrane`，期望 `status=INPUT_ERROR`、`exit_code=2`、`no_core=true`。

| 组 | 探针 | 派生（作用于 case/legacy/） | code / stage | reader（index） |
|---|---|---|---|---|
| 缺文件 | F01–F14 | `delete_file`：inp、1.glb、1.cor、1.ele、1.pre、1.mat、1.loa、1.man、1.sol、1.opr、1.tem、1.ifs、1.nrt、1.ftr | FILE_MISSING / startup，`file_suffix` 为实际文件名（`inp`、`1.glb`…） | 不断言（缺文件由 `diag_check_open` 报告，报文 `reader=""`，`unit`/`site` 为 open 位点） |
| 截断 EOF | F20 | `truncate_lines` 1.cor keep=200（共 289） | EOF / startup | `COR.global_data.node_coordinates`（201） |
| | F22 | `truncate_lines` 1.ele keep=100（共 256） | EOF / startup | `ELE.read_element.element_connectivity`（101） |
| | F23 | `truncate_lines` 1.glb keep=12 | EOF / startup | `GLB.global_data.title#9` |
| | F28 | `truncate_lines` 1.man keep=2（title + nincs） | EOF / increment_lazy(1,1) | `MAN.STATIC_U.increment_control` |
| | F30 | `truncate_lines` 1.sol keep=1 | EOF / solver_lazy | `SOL.PROFILE.profile_control` |
| | F32 | `truncate_lines` 1.mat keep=19（删末两行） | EOF / startup | `MAT.material_set.elastic_isotropic` |
| 清空 EOF | F29 | `empty_file` 1.man | EOF / phase_lazy(1) | `MAN.STATIC_U.title#1` |
| | F31 | `empty_file` 1.sol | EOF / solver_lazy | `SOL.PROFILE.title#1` |
| | F34 | `empty_file` 1.ifs | EOF / startup | `IFS.stiff_interface_fluid_solid.title#1`（seq 1；`stiff_ifs2006.title#1` 是 seq 7） |
| 类型错 PARSE | F24 | `replace_token` 1.glb 第 2 行 `289`→`abc`（npoin） | PARSE / startup | `GLB.global_data.sizes_and_switches` |
| | F25 | `replace_token` 1.ele 第 1 行第 2 个 `1`→`x`（`occurrence=2`，首个连接节点号） | PARSE / startup | `ELE.read_element.element_connectivity`（1） |
| | F26 | `replace_token` 1.pre 第 3 行 `17`→`17x`（nfixnods） | PARSE / startup | `PRE.prescrib_set.set_header` |
| | F27 | `replace_token` 1.man 第 3 行 `5`→`5x`（miter；`5.5` 会被 ifx 截成 5 而不报错，R21） | PARSE / increment_lazy(1,1) | `MAN.STATIC_U.increment_control` |
| | F33 | `replace_token` 1.loa 第 2 行 `1`→`one`（ntcurve） | PARSE / startup | `LOA.external_load_1.curve_count` |
| 行短跨行 | F21 | `replace_line` 1.cor 第 57 行 → `57  15.0`（删 y 分量） | EOF / startup | `COR.global_data.node_coordinates`（289）：list-directed READ 静默跨到下一记录（R19），整数项接受实数形式（R21），逐条错位直到最后一个节点 EOF |

延迟读取覆盖：F27/F28 `increment_lazy(1,1)`、F29 `phase_lazy(1)`、F30/F31 `solver_lazy`；其余为 `startup`。

## 各字段的核定状态

- **F01–F14**：不断言 `reader`。缺文件由 `diag_check_open` 报告，报文 `reader` 为空、`file` 为实际文件名、`unit`/`site` 为 open 位点（如 `cunit` / `Global.f90:632`）。
- **F23**：`reader` 已按首次运行的 DIAG 核定为 `GLB.global_data.title#9`（`.glb` 第 13 行）。
- **F21**：`index=289` 已断言（EOF 落在最后一个节点记录）；描述中记录了跨行机制。
- **F34**：使用 `.ifs` 的 seq 1 读取点 `IFS.stiff_interface_fluid_solid.title#1`。

`reader` 取值必须从 `docs/m1/reader-inventory.toml` 抄写；`yl_io_inventory.py check` 保证注册表、生成的 Fortran 常量表与源码引用一致。

## 写保护

`yl_probe.py` 在任何删除/写入之前检查：`--runs-root` 不得位于 `cases/` 之下或包含它；物化目录必须解析到 `--runs-root` 之内；
每个 derive 的 `file` 必须是裸文件名（无目录分隔、非 `..`），目标解析后必须在 `case/legacy/` 内。违规时不写任何文件并以退出码 2 报错。

## 判定

`yl_probe.py run` 对每条探针：物化 → `yl_manifest.py generate` 重建 `input-manifest.json`（meta 记录 probe 与 derived_from）
→ `yl_run.py --case-dir … --expect-status <status> --label <id>` → 读取该次 `run-manifest.json` 断言。
任一探针 FAIL 则退出 1；报告 `runs/probes/report.json` 逐条记录 pass/fail 与原因。
