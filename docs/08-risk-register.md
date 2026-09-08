# 风险登记表

状态均为 OPEN，直到有关闭证据；本次为计划审查，不代表故障已经修复。

| ID | 证据/风险 | 影响 | 处置与关闭证据 |
|---|---|---|---|
| R01 | 历史源码提交与当前算例非同一时间基线，原工作树有修复 | 无法复现或保留已知错误 | M0 对照版本；单独导入必要修复；构建/运行可追溯 |
| R02 | 两例都声明 PROFILE，初稿却限定 PARDISO | 算法变更与输入迁移混在一起 | 已修计划；M0 复现 PROFILE，PARDISO 单独验证后关闭 |
| R03 | `Fem.f90` 多处阶段内 READ/REWIND | 启动摘要相同仍可能执行不同分析 | M1 路径清单、M2 多检查点、M4 延迟读取消除证据 |
| R04 | 同目录含 `1.LOA` 和 `1.loa` | Linux 与不区分大小写平台含义不同 | 已核实：两文件字节相同，`Global.f90:633` 只打开小写 `.loa`；保留原件并在 input manifest 记录，M0-01 记录后关闭，不需要冲突拒绝逻辑 |
| R05 | 原源码非统一 UTF-8 | 扫描丢失 reader、错误修改源码 | 按字节保全哈希；搜索使用二进制文本模式；编码转换独立任务 |
| R06 | legacy 包含 Windows 工程、预编译库及本地依赖 | 干净 Linux 构建失败、发布依赖来源不清 | M0 依赖/再分发范围清单与构建验证；不自动公开二进制 |
| R07 | 全局变量、指针别名、初始化副作用 | 新 bridge 产生悬空状态或污染参考 | 所有权表、独立进程差分、分配失败与再次加载测试 |
| R08 | Cook/Lamé 文件名未证明实际模型 | 错用解析公式，虚假物理通过 | 已证实：两例 `.loa/.mat/.man/.opr/.sol` 字节相同，仅重力体力；两例降为回归例，M5 新建解析 probe |
| R09 | 只比较哈希或最大值，数组截断可通过 | 错误被掩盖 | M2 结构化比较和缺失/截断/NaN/shape 反例 |
| R10 | 项目试图一次改完全部 READ/全局状态 | 首条闭环无限延期 | M1～M5 限定静力切片；长尾清单不阻塞首条独立能力 |
| R11 | bootstrap Schema 尚无材料/约束/荷载等 | 被误当可运行输入标准 | M5 替换为完整规范；此前明确不可用于运行能力声明 |
| R12 | golden 被运行输出或自动更新预期污染 | 基线丢失、自证正确 | 独立运行目录、前后哈希、基线变更独立评审 |

| R13 | 原仓库脏树《修改报告.md》与实际 diff 不符；Stiff.f90 含密度循环前 `factw` 未初始化修复 | 按报告归类补丁会漏掉影响重力路径的修复 | 已完成 M0-04c：candidate 两例与 reference 逐值相同，脏树对静力切片无影响；`factw` 初始化并入 M1-03 防御性修复。对其他能力切片开工时须重新对照 |
| R14 | 旧程序多处 `stop '文本'` 退出码为 0；`.chk` 与 stdout 含时间戳 | 仅凭退出码或字节比较误判成功 | M0-03 组合判据；比较只用解析后的 `1.flavia.res` |
| R15 | 种子算例关闭反力输出，且静力单增量流程是否调用 GiD 写出未经运行确认 | 首跑可能无可解析结果；反力平衡判据不可用 | 已确认 `1.flavia.res` 在 nincs=1 静力流程写出（M0-02/04a）；反力平衡仍需 M5 新建探针 |
| R17 | `Elements.f90:197` `kinddefine` 对一维单元类型不赋值 `t/u` 即调用 `shfunc`（`Elements.f90:2588`），使用未初始化实数 | 任何 `-init=snan`/`-fpe0` 运行在启动即中止；结果不受影响（相关项未用于线单元） | **CLOSED（M1-03，2026-09-07）**：每个积分点先 `t=u=0`；strict profile 两例 COMPLETED 且与 reference 精确相同（`docs/m1/M1-03-semantic-guards.md`） |
| R18 | `Fem.f90:12288` `modf_var_prescribed` 在约束集 `itcurve=0` 时读 `tcurves(0)%dfact/type_curve`，越界 | `-check bounds` 中止；release 下读到相邻内存，两例结果未受影响但不可保证 | **CLOSED（M1-03，2026-09-07）**：`itcurve==0` ⇒ `dfact=1`、`type_curve='NONE'`（`modf_var_prescribed` 与 `time_dependent`）；`.pre` 读取处校验 itcurve∈0..ntcurve 且 ifixvar=8/10 必须有曲线；debug profile 两例 COMPLETED 且精确相同 |
| R19 | list-directed READ 遇记录字段不足时静默跨到下一记录，`iostat=0`（ifx 实验与探针 F21 证实） | 少一个值的 deck 会整体错位而不报错 | M4 记录级 Legacy Adapter；M1-02 只保证 EOF/语法错可控 |
| R20 | 旧程序约 90 处裸 `stop`/`stop '文本'` 退出码为 0，未纳入退出协议 | 求解失败或内部错误仍可能以 rc=0 结束 | M1-03 已替换 static_2d 路径上的 38 处、39 条语句（审计表见 `docs/m1/M1-03-semantic-guards.md`：正常结束→exit 0，输入错→2，能力不支持→3，内部表→6）；路径上另有 3 处行内 `if(...) stop`（`Fem.f90:1902`、`Fem.f90:9336`、`Load.f90:1073`，复核发现，两例不触发）与路径外约 50 处保持 OPEN，运行器以组合判据兜底 |
| R22 | M1-03 起 `.cor`/`.ele` 的 id 必须等于行序、`.glb` Σnelgroup 必须等于 nelem、未知命令行参数报错（旧代码忽略 id、多余单元静默不读、只看首个参数） | 乱序 id 或多余单元的历史 deck 会被拒绝（RANGE/DUPLICATE），而旧程序能跑 | 契约变更登记于 `docs/m1/M1-03-semantic-guards.md`；两例 golden 满足；乱序 id 若有真实需求由 M4 Adapter 支持 |
| R21 | ifx list-directed 整数项接受实数形式并截断（`5.5`→5，`iostat=0`） | 输入错误被静默吞掉 | M4 记录级解析按字段类型严格判定；探针 F27 改用非数字 token |
| R23 | 派生类型含未初始化分量与未关联指针（`prescrib%ifixvar0` Prescrib.f90:274、`deltafi/delitfi` Fem.f90:246、`rvector` Solver.f90:7237、`element%field%rload/tload/eload`）；整体 dump 会把随机字节写进摘要 | 重复运行摘要不稳定，S01 假失败 | M2-01 在 `docs/m2/state-field-map.toml` 逐分量登记 determinism，未初始化/指针一律 `ignore`；M2-02 序列化器只按白名单分量输出，指针先 `associated()` |
| R24 | `fixed` 与 `tcurves%dfact` 在 `increment_ready(1,1)` 仍为 0（Fem.f90:3666-3667 才赋值） | 对 `fixed` 做 S03 约束扰动检不出差异 | M2-01 `[[perturbation]]` 把 S03 目标钉在 `props%…%e`、`prescrib%vdofix/nodfix`、`gravy/factg/tcurvegravity`；M2-03 按此执行 |
| R25 | `.pre` 集合头的 `nextr` 是 `prescrib_set` 局部量且无任何持久留存（`tfixvar` 经 `iffix=tfixvar+1` 留存，`nextr` 走 `Prescrib.f90:261-268` 另一分支分配 `listep/value_ext`） | 状态快照无法证明外推（extrapolation）行为等价 | M2-01 登记为 `ignore` 并在 `docs/m2/M2-02-state-serializer.md` §6 写明；两例 `nextr=0`，该分支不执行；若将来支持 `nextr/=0` 必须先补 reader capture |
| R26 | `runtime.gauss.gpcod/cartd/djacb` 是读入时计算的派生浮点，release(-O2) 与 debug/strict(-O0) 末位不同，导致 `fingerprint.json` 跨 profile 不同 | 误把指纹当跨构建等价判据会产生假失败 | 映射表按 `abs_tol` 登记这三个字段；跨构建等价由 `tools/yl_state_diff.py` 判定（实测 PASS compared=190），指纹只在同一二进制内做 S01 重复判据；见 `docs/m2/M2-02-state-serializer.md` §3 |
| R27 | **M1 的 gdb 证据是下界，不是测量值。** `tools/yl_io_inventory.py` 的 `gdb-script` 对每个站点只发一条 `break FILE:LINE`，**假设一行编译成一个地址**。ifx 会把一条数组段读取编译成**两段不相连的地址范围**、都标同一行号（实测 `Load.f90:231`：`0x5a9b16` 与 `0x5a9e38`），gdb 只绑定第一段，而执行进入第二段 —— 断点永不触发。失效随后**静默传播五步**：站点执行了 → 断点没打中 → 不在 `hits.json` → 未被加进 reader 清单 → 未被 `diag_check_read` 包装。`check` 发现不了，因为它校验清单与证据的一致性，**而两者都在同一个工具假设的下游** | **「两例各命中 211 位点」是下界，不是测量值，且目前无法知道低了多少。** 受影响的是任何以命中集为完备性依据的判断：M1-01 的 `not_on_path` 分类、M1-02 的「路径上读取全部包装」、以及将来任何「这条路径上再无未包装读取」式的论证。**不受影响、仍然可信的证据**：命中集内的 211 条是真命中（假阳性不是本缺陷的失效模式）；`check` 对清单与注册表的一致性校验；`wrap_reads --dry-run` 的 0 edits；两例数值逐值相同（`max|d|=0`）；M0/M2/M3 的全部证据（不依赖该工具） | **处置**：M1-01/M1-02 按本缺陷**有条件接受**（`Load.f90:231` 已修复验证，功能面无未决项）。**关闭条件**：`gdb-script` 改为对一行的**全部**地址下断点并合并计数，重跑两例 trace，用新命中集与现有 211 条对差；差为 0 则下界升格为测量值，差不为 0 则每条新站点按 M1-02 流程补包装。**关闭里程碑：M1-04**（若不单独立项，则并入 M4-02 之前必须完成——M4 的影子差分会以 M1 的完备性为前提）。见 `docs/m1/M1-finding-2026-09-08-unwrapped-loa-read.md` |
| R16 | 初稿 ProblemState 自创分类，与 CAE 惯例和 YL 对象都不对应 | 三套词汇并存，输入更混乱 | ADR-0003 采用 CAE 对象模型；docs/01、03 与 schema 已改，M3/M5 按其实施 |

每次新增风险补充责任人、发现提交、最小复现、预定处置阶段和关闭证据路径。
计划修正只解决文档问题，不能替代代码或运行验证。
