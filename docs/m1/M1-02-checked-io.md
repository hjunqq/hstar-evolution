# M1-02：结构化 Error、checked I/O 与退出协议

- 范围：`docs/m1/reader-inventory.toml` 中 152 个 `[[reader]]`（149 个执行 + 3 个 reached_only）与 14 个输入文件的 `open`
- 源码：`legacy/yl` 由快照 `5414e73` 加本任务改写；未修改的快照身份由 `cases/golden/*/reference/build-manifest.json` 中逐文件哈希保存
- 工具：`tools/yl_wrap_reads.py`（改写，幂等：只有完整结构——iostat/iomsg + 紧随的 `diag_check_read/open` 调用且全部实参逐一相符（RD_ 常量与 index 表达式；open 的 file 表达式、unit、当前行号 site）——才视为已包装，半包装或实参不符的位点中止且不写文件）、`tools/yl_io_inventory.py gen-fortran`（注册表 → Fortran 常量表；`check` 逐条比对生成表的 RD_ 常量、ID、site 与注册表）、`tools/yl_probe.py`（故障注入；写保护：runs-root 与 `cases/` 不得重叠、派生目标限定在 case/legacy/ 内）
- 证据：两例 release 结果与 reference 逐字节相同；`yl_io_trace.sh` 位点集合不变；探针矩阵 29/29

## 设计

```text
legacy 源码                          src/diagnostics
read(u,*,iostat=yl_ios,iomsg=yl_msg) …      yl_diag_registry.f90  ← gen-fortran ← reader-inventory.toml
call diag_check_read(yl_ios,yl_msg,RD_<id>,index)   yl_diag.f90: diag_check_open / diag_check_read / diag_raise / diag_fail
open(u,file=…,status='old',iostat=yl_ios,iomsg=yl_msg)
call diag_check_open(yl_ios,yl_msg,<file>,'<unit>','<site>')
```

- 代码只引用由注册表生成的整数常量 `RD_<id>`；`yl_io_inventory.py check` 校验每个调用的常量都存在，并报告已包装数（152/152）。
- `yl_ios/yl_msg` 是 `yl_diag` 的模块变量；所有 reader 都在串行代码中执行。
- 单行 `if (cond) read(...)` 保留内联形式，其后追加 `if (cond) call diag_check_read(...)`；四处条件均为不受 read 影响的纯比较（`rmesh/=0`、`nlayer==2`、`type_abc=='MIF'`、`type_abc/='MIF'`）。
- 输入 `open` 加 `status='old'`：缺文件不再静默创建空文件。空占位文件（`.aqu .ftr .ifs .nrt .tem`）在 golden 中存在，行为不变。

## 报文契约（stderr，单行）

```text
HSTAR_DIAG schema=1 code=EOF exit=2 severity=fatal stage="startup" file=".cor" unit="cunit" reader="COR.global_data.node_coordinates" site="Global.f90:1161" seq=1 index=201 iostat=-1 field="i0:int:mesh.nodes[].id,coord[1:ndimn]:real:mesh.nodes[].xyz" message="end-of-file during read, unit 2, file …"
```

| 键 | 含义 |
|---|---|
| code | FILE_MISSING / EOF / PARSE / INTERNAL（M1-03 起：RANGE / REF / DUPLICATE / UNSUPPORTED） |
| exit | 进程退出码：0 成功；2 输入错误；3 能力不支持；4 初始化失败；5 求解失败；6 内部错误 |
| stage | startup / phase_lazy(1) / increment_lazy(1,1) / solver_lazy / reached_only / internal |
| file / unit / reader / site / seq / field | 取自注册表；`file` 对读错误是扩展名（`.cor`），对缺文件是实际文件名（`1.cor`） |
| index | 传入的循环索引（节点号、单元号、约束集号、增量号），0 表示无 |
| iostat / message | 编译器运行时原值；`message` 不参与断言 |

所有文本值（stage/file/unit/reader/site/field/message）一律双引号，内部 `"` 与 `\` 反斜杠转义，换行替换为空格；`file` 字段容量 256 字符（缺文件报实际路径名）。
Python 端用 `shlex.split` 严格解析：解析失败、`schema≠1`、缺 `code`、`exit`/`seq`/`index`/`iostat`/`schema` 任一非整数的行记入 `diagnostics_malformed` 并判 FAILED。
退出统一为 `flush` 后 `call exit(code)`。旧程序约 90 处裸 `stop` 未替换（R20）。

## `--check-legacy`

- 触发：第一个命令行参数为 `--check-legacy`。
- 收口点：`process_analysis` 入口第一条语句，在 `.sol`（PROFILE 内）与 `.man`（STATIC_U 内）延迟读取之前。
- 覆盖：14 个输入文件存在性、143 个 startup reader（含 `.man/.sol` 的存在性但不含其内容）。
- 输出（stdout）：`HSTAR_CHECK schema=1 mode=check-legacy status=OK errors=0 readers_executed=N readers_registered=152` 与每个执行过的 reader 一行 `HSTAR_CHECK_READER id=… n=…`；退出 0。
- 运行器：`yl_run.py --binary-args "--check-legacy" --expect-status CHECKED`。摘要校验：恰一行 `HSTAR_CHECK` 且 `schema=1`、`mode=check-legacy`、`errors`/`readers_executed` 为整数、`readers_executed` 等于 `HSTAR_CHECK_READER` 行数、每行 READER 有 `id` 与整数 `n`；不满足记入 `check_malformed`。CHECKED 要求 `check_malformed` 为空且 `status=OK`、`errors=0`；摘要存在但不满足（含 `status≠OK`）而 rc=0 → FAILED，原因写入 `protocol_violation`。
- 副作用：启动期仍会创建约 30 个空输出文件（.chk .opw …），在隔离目录中可接受。

## 运行器状态

`INPUT_HASH_MISMATCH, TIMEOUT, CRASHED, INPUT_ERROR, UNSUPPORTED, INIT_ERROR, SOLVE_ERROR, INTERNAL_ERROR, FAILED, GOLDEN_MODIFIED, CHECKED, MISSING_OUTPUT, COMPLETED`（先命中者胜）。
`INPUT_ERROR / UNSUPPORTED / INIT_ERROR / SOLVE_ERROR / INTERNAL_ERROR` 分别要求 rc=2/3/4/5/6 且有一条报文 `exit` 等于 rc；报文格式不合法、`exit` 不在 2..6、rc 与 `exit` 不一致、check 摘要不合法或非 OK/errors=0 均判 `FAILED`（协议违规，原因见 manifest `protocol_violation`）。
`GOLDEN_MODIFIED` 先于 `CHECKED`/`COMPLETED` 判定：改动了 golden 输入的运行（含 check 模式）不会被接受。`--expect-status` 让退出码只在命中期望时为 0。

## 探针矩阵（`cases/probes/failure/`，29 条，全部 PASS）

| 组 | 探针 | 预期 |
|---|---|---|
| 缺文件 | F01–F14（14 个输入文件各一） | FILE_MISSING，stage=startup，报文含 unit/site |
| 文件截断/清空 | F20 .cor、F22 .ele、F23 .glb、F28/F29 .man、F30/F31 .sol、F32 .mat、F34 .ifs | EOF，reader 与 index 精确（F23 → `GLB.global_data.title#9`；F28 → increment_lazy） |
| 类型错 | F24 .glb npoin、F25 .ele、F26 .pre、F27 .man miter、F33 .loa | PARSE，reader 精确 |
| 字段缺失 | F21 .cor 第 57 行删 y | EOF@index 289（见盲区） |

探针从 golden 派生物化到 `runs/probes/<id>/case/`，不复制 deck；`yl_probe.py` 校验 status、code、stage、file 后缀、reader、index、无 core。

## 已知盲区（登记为风险）

- R19 记录字段不足：list-directed READ 静默跨到下一记录，`iostat=0`。
- R21 整数项接受实数形式：`5.5` 读入整数得 5，`iostat=0`；只有非数字 token 才报 PARSE。
- 多余项被丢弃：`.man` 首记录 `nincs` 之后的 3 个值即依赖此行为。
以上三者由 M4 的记录级 Legacy Adapter 处理；M1-02 只保证缺文件、EOF、语法错误可控退出。

## 验证记录（2026-09-07，Round 1 修复后重跑）

- `tools/build.sh release/trace` 0 warning；两例 COMPLETED，`yl_compare` max|d|=0，`1.flavia.res` SHA 与 `reference/run-manifest-1.json` 相同。
- `scan`：read 886 / open 80 / rewind 54 / close 2 不变；`yl_io_trace.sh` 两例位点 211、命中 767/367 与 M1-01 证据逐点一致（行号后移）。
- `check`：PASS，wrapped 152/152；生成的 `yl_diag_registry.f90` 与注册表逐条一致（陈旧表会被 `check` 拒绝）；注册表只更新 site/anchor/statement/hits。
- 探针 29/29 PASS；F20 报文 `site="Global.f90:1161"` 与注册表一致。
- `--check-legacy`：两例 CHECKED；F24 物化目录 → INPUT_ERROR；假二进制在 check 模式下篡改 golden 副本 → GOLDEN_MODIFIED；未闭合引号 / `schema=9` / `exit=0` / rc≠exit 的报文 → FAILED；`exit=3` 且 rc=3 → UNSUPPORTED。
