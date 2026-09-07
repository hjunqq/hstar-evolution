# 故障注入探针（M1-02）

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

## 矩阵（29 条，2026-09-07 全部 PASS）

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
