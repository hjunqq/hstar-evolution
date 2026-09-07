# M1-03：语义守卫、负向探针、R17/R18 修复与裸 `stop` 替换

- 范围：static_2d 路径上已执行 reader 的消费点（`docs/m1/reader-inventory.toml`）；PGO 函数计数得到的 109 个执行例程内的 38 处裸 `stop`（Temper.f90:455 一行含两处，实替换 39 处）
- 源码：`legacy/yl` 10 个文件（Global、Elements、Load、Prescrib、Material、Fem、Temper、Residu、Stiff、Output）；`src/diagnostics/yl_diag.f90` 新 API；不改算法、数据结构、输出格式
- 证据：release/debug/strict × 两例 6 次 COMPLETED 且 `yl_compare` 与 reference 精确相同；6 次 `--check-legacy` CHECKED；探针 47/47（F 29 + N 18）；`yl_io_inventory.py check` PASS（152/152 wrapped，两例 gdb 证据重采且 `1.flavia.res` 与 reference 逐字节相同）

## 设计

- **守卫模式**：读后局部守卫 + 消费前失败屏障。守卫只测自己的条件，值合法时不记录，调用方可以无条件调用。
  - 决定分配或循环上界的量（npoin、nelem、mdofn、nfixnods、nincs …）：`diag_range` 后立即 `diag_flush_stage`（有条目即 `diag_fail`）。
  - 记录内引用/重复（`.cor` id、`.ele` 连接、`.pre` list_fix、tcurvegravity）：逐条 `diag_ref/diag_dup` 累积，读完该文件（或该集合）再 `diag_flush_stage`。每 reader 最多保留 20 条，超出计数并在最后一条 message 末尾追加 ` (+K more)`。
- **坏引用不能"钳位后继续消费"**：`read_element` 发现任一 `lnods ∉ 1..npoin` 时置模块变量 `ele_scan_only=.true.` 并直接 `return`（不再索引 `coord(:,lnods)`）；`global_data` 的单元循环对随后的每个单元只读不消费（`cycle`），组尾的拓扑处理整体跳过，组循环结束后 `diag_flush_stage`。这样一次运行能报出 `.ele` 里全部坏记录（探针 N09：index 1、3、5 三条）。
- **数量上限**：`diag_product` 用 int64 逐项除法预检（`acc > cap/b`），cap 由 `--max-entities=N` 覆盖（默认 `huge(0_ink)`）；探针 N02 用 `--max-entities=100000` 夹具，不真分配。`global_data` 首个 `allocate` 加 `stat=/errmsg=`，失败 → `diag_abort('INIT', 4)`。
- **新 code**：RANGE / REF / DUPLICATE（exit 2）、UNSUPPORTED（exit 3）；报文新增键 `value="…"`、`allowed="…"`（紧跟 `field=`，其余键不变）。裸 `stop` 替换点无 reader 上下文，用 `diag_abort(code, exit, site, message)` 单条报文即退，`stage="runtime"`，`site` 为 `文件:例程`（不随行号漂移）。
- **命令行**：`diag_set_mode_from_argv` 扫描全部参数，`--check-legacy` 与 `--max-entities=N` 任意顺序；未知参数或非法 N → `code=PARSE stage="argv"` exit 2。

## 守卫表（按 reader）

| reader | 字段 | 规则 | code | 时机 |
|---|---|---|---|---|
| GLB.global_data.sizes_and_switches | npoin / nelem / nmats / ngroup | ≥1 且 ≤ max_entities | RANGE | 立即（首个 allocate 前） |
| | npoinb / ntlink | ≥0 | RANGE | 立即 |
| | ndimn | ∈ {2,3} | UNSUPPORTED | 立即 |
| | npoin×ndimn、npoin×ndimn×ndimn | ≤ max_entities | RANGE | 立即 |
| GLB.global_data.mdofn | mdofn | ≥1 | RANGE | 立即 |
| GLB.global_data.group_nfdof / group_listdof | nfdof、listdof | ∈ 1..mdofn | RANGE | 立即 |
| COR.global_data.node_coordinates | i0 | 必须等于行序 ipoin；i0∈1..ipoin−1 判 DUPLICATE，否则 RANGE（allowed `ipoin..ipoin`） | DUPLICATE / RANGE | 累积，`.cor` 读完 |
| GLB.global_data.group_header | index | ∈ 1..ekind(26) | UNSUPPORTED | 立即 |
| | nrfields | ≥1 | RANGE | 立即 |
| | matno | ∈ 1..nmats | REF | 立即（该组内消费） |
| | nelgroup | ∈ 0..(nelem−Σ已读)；组循环结束后 Σnelgroup = nelem（index=ngroup，value=Σ） | RANGE | 立即 / 组循环末 |
| | nelgroup×nnode | ≤ max_entities | RANGE | 立即 |
| ELE.read_element.element_connectivity | lnods(1:nnode) | ∈ 1..npoin | REF | 累积（scan-only），组循环末 |
| | i0 | 必须等于行序 ielem（同 `.cor`） | DUPLICATE / RANGE | 累积，组循环末 |
| MAT.material_set.nmats | nmats | = `.glb` nmats | RANGE | 立即 |
| MAT.material_set.material_header | imat | ∈ 1..nmats；未曾出现 | RANGE / DUPLICATE | 立即 |
| | property / phase / material | 已知名称（原 `case default` 三处 stop） | UNSUPPORTED | 立即 |
| LOA.external_load_1.curve_count | ntcurve | ≥0 | RANGE | 立即 |
| LOA.external_load_1.curve_header | ntime / nstoch_curve | ≥0（HARMONIC 等类型不用点表，ntime=0 合法，故未按计划取 ≥2） | RANGE | 立即 |
| LOA.external_load_2.gravity_curves | tcurvegravity(igroup) | ∈ 0..ntcurve | REF | 累积，读完该行 |
| PRE.prescrib_set.set_header | ifixvar∈{8,10} 且 itcurve=0 | 水位/温度集合必须有曲线（R18） | REF | 立即（先于其余守卫，使其成为首条报文） |
| | nfixnods | ∈ 1..npoin | RANGE | 立即 |
| | ifixvar | ∈ 1..mdofn | RANGE | 立即 |
| | itcurve | ∈ 0..ntcurve（`use applied_load, only: ntcurve`） | REF | 立即 |
| PRE.prescrib_set.set_nodes | list_fix(1:nfixnods) | ∈ 1..npoin | REF | 累积，读完该集合 |
| MAN.STATIC_U.nincs | nincs | ≥1 | RANGE | 立即 |
| MAN.STATIC_U.increment_control | miter / nstep / inc_step | ≥1 | RANGE | 立即 |

未做（登记）：`material_serial` 与 imat 一致性——`material_serial N` 那一行由 title reader 以单个字符串读入，序号并未被解析，不改读语句就拿不到；留待 M4 Adapter。

## 契约变更（对历史 deck 的新要求）

| 变更 | 旧行为 | 新行为 |
|---|---|---|
| `.cor` 节点 id | 读入后忽略，坐标按行序存 | id 必须等于行序，否则 DUPLICATE/RANGE |
| `.ele` 单元 id | 同上 | id 必须等于行序 |
| `.glb` 组 nelgroup | 不校验，多余单元静默不读 / 不足时越界 | Σnelgroup = nelem |
| `.pre` itcurve=0 | 读 `tcurves(0)`（越界，R18） | 因子 1、`type_curve='NONE'`；ifixvar=8/10 时必须给曲线 |
| 命令行 | 只看第一个参数 | 全部参数解析，未知参数报错 |
| `.mat` mmats | 分配 props(nmats)，只读 mmats 条，多余槽位允许（mmats<nmats） | mmats 必须等于 `.glb` nmats，否则 RANGE（比安全所需更严；matno REF 已覆盖引用。若遇备用材料槽的历史 deck，可放宽为 1..nmats + "已定义"检查） |
| `.pre` itcurve=0 且 val_fix≠0 | 未定义（乘以 `tcurves(0)` 越界值） | 因子恒为 1（`fixed = 1.0*vdofix`），两例 val_fix=0 不受影响 |
| `.man` nstep | nstep=0 走空步循环（无操作） | nstep、miter ≥1，nstep=0 的 no-op deck 现被拒绝 |
| 空字符串命令行参数 `""` | 忽略 | PARSE exit 2 |

两例 golden 均满足新契约（id 即行序）。乱序 id 的 deck 若存在，需在 M4 Adapter 里另行支持。

## R17 / R18

- R17：`kinddefine` 每个积分点先 `t=0; u=0` 再按 `lnidmn` 覆盖（`Elements.f90` 约 197 行）。strict profile（`-init=snan,arrays -fpe0`）两例完整运行且结果精确相同——关闭。
- R18：`modf_var_prescribed`（`Fem.f90` 约 12305 行）与 `time_dependent`（约 9265 行）在 `itcurve==0` 时不再索引 `tcurves(0)`：`dfact=1.0`、`type_curve='NONE'`。两例 `.pre` 的 itcurve=0 集合 `val_fix=0`，`0×垃圾 = 0×1`，结果不变；debug profile（`-check bounds`）两例完整运行——关闭。

## 裸 `stop` 审计（38 处 + Temper 同行 1 处）

| 位点（原行号） | 语义 | 替换 | exit |
|---|---|---|---|
| Fem 299 | restart=2 写完输出后结束 | `diag_exit(EXIT_OK)` | 0 |
| Fem 360 / 367 | Bparameter=3/4 反分析完成 | `diag_exit(EXIT_OK)` | 0 |
| Global 4530 / 4657 | Σnel_pipe、Σnel_steel ≠ 组 nelgroup | `diag_abort('RANGE')` | 2 |
| Load 210 | 弧长控制节点自由度无方程 | `diag_abort('REF')` | 2 |
| Load 1288 | 高斯点不在任何 qstatic_force 系数区间 | `diag_abort('RANGE')` | 2 |
| Prescrib 289 | MIF 匹配节点数 ≠1 | `diag_abort('REF')` | 2 |
| Temper 455（两处） | 管段触及 >2 个节点 / 找不到所在单元 | `diag_abort('REF')` | 2 |
| Residu 777、855 / Stiff 584、655 | 钢筋弹簧单元两端都不是自由节点 | `diag_abort('REF')` | 2 |
| Residu 796 / Stiff 604 | icpnorm 两端同时为 0 或同时非 0 | `diag_abort('REF')` | 2 |
| Output 4138 | res_* 与 gidres_* 标志不匹配 | `diag_abort('RANGE')` | 2 |
| Material 423 | igap0=2、gap_kind=1 但 ndimn≠2 | `diag_abort('UNSUPPORTED')` | 3 |
| Material 930 / 978 / 1013 | 未知 material / phase / property 名 | `diag_unsupported`（含违规 token）+ flush | 3 |
| Fem 3943 | restart_ctt 取值未知（同文本另有 4 处不在路径，未动） | `diag_abort('UNSUPPORTED')` | 3 |
| Fem 12717 | type_curve 未知 | `diag_abort('UNSUPPORTED')` | 3 |
| Residu 942 / 962 / 967 / 986 / 991 | icreep>2 或 icreep=2 分支未实现 | `diag_abort('UNSUPPORTED')` | 3 |
| Elements getgauss ×6、shfunc ×4 | kinddefine 固定表触发的高斯规则/形函数缺失 | `diag_abort('INTERNAL')` | 6 |
| Output 988 | ndimn 已在 `.glb` 守卫，此处不可达 | `diag_abort('INTERNAL')` | 6 |

每处保留原 `print/write` 文本。`Residu.f90`（模块 `internal_force`）补 `use yl_diag`。路径外的裸 `stop` 未动（R20 保持 OPEN，范围收窄为"路径外"）。

审计用 `^\s*stop` 扫描，漏掉了三处行内 `if(...) stop` 形式（复核发现，本任务未动，留给 R20）：`Fem.f90:1902`（`process_analysis`，ADINA==1 且末块时结束，两例不触发）、`Fem.f90:9336`（`write_stiff_u`，static_u 条件调用）、`Load.f90:1073`（`step_water_pressure`，water=0）。三处在 golden deck 上均不触发。另：`.ele` 坏记录"只扫描"模式依赖 `read_element` 每记录恰一次 read 且组循环到组尾之间无其他 gunit 读——当前成立，若 `read_element` 增加第二个 read 需同步调整。

## 探针矩阵（`cases/probes/failure/`，N01–N18，全部 PASS）

见 `cases/probes/failure/README.md`。新原语 `set_field`、`duplicate_line`、`insert_line`；新断言 `diag_count`、`indices`、`value`、`field`；`binary_args` 传 `--max-entities`。

## 检查型构建出口

| profile | cooks_membrane | lame_cylinder |
|---|---|---|
| release | COMPLETED，max\|d\|=0（DISPLACEMENT 578、STRESS 1156） | COMPLETED，max\|d\|=0（162 / 324） |
| debug（`-check bounds,pointers`） | COMPLETED，max\|d\|=0 | COMPLETED，max\|d\|=0 |
| strict（debug + `-init=snan,arrays -fpe0`） | COMPLETED，max\|d\|=0 | COMPLETED，max\|d\|=0 |
| `--check-legacy`（三 profile） | CHECKED | CHECKED |

strict 未再暴露新的未初始化点；M0-02 记录的 `Elements.f90:2588`（R17）与 `Fem.f90:12288`（R18）两个中止点均已消失。

## 注册表维护

守卫插入使 166 个位点行号漂移。处理：用 git HEAD 与工作树的逐行 difflib 映射重写 `reader-inventory.toml` 的 `site`（anchor 是语句哈希，不变）；`diag_check_open` 的 site 字面量按"open 在上一行"规则重写 13 处；`scan` 重建 `io-sites.json`；trace profile 两例 `yl_io_trace.sh` 重采证据（211 位点，767/367 命中，与 M1-01 相同；输出与 reference 逐字节相同）；`gen-fortran` 重生成注册表；`check` PASS；`yl_wrap_reads.py --dry-run` 0 edits（幂等性保持）。

## 验证记录（2026-09-07）

- 构建：release/debug/strict/trace 均 0 warning（`tools/build.sh`，manifest 门通过，`legacy/source-manifest.json` 重生成 `modified_by=M1-03`）。
- 运行：`runs/static_2d.*/…_m103-{release,debug,strict}`（6 次 COMPLETED）及 `…_m103-*-check`（6 次 CHECKED）。
- 探针：`runs/probes-m103/report.json`，47/47 PASS。
- 注册表：`python3 tools/yl_io_inventory.py check --evidence docs/m1/evidence/*/hits.json` → PASS。
