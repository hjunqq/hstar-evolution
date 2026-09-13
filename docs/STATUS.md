# 当前进度

<!-- 事实源：全项目只有这一份「当前状态」。CLAUDE.md、报告、验收包只链接本文件，
     不复制「当前在做 / 下一步」。.ccg/tasks/*/task.json 是执行器的工作队列，
     不是状态；两者不一致时以本文件为准。 -->

更新日期：2026-09-12。此文件只登记已经发生的事；阶段验收以证据包为准。

## 验收链（2026-09-12 总览时清点）

| 阶段 | 实现 | 验收 | 证据包 |
|---|---|---|---|
| M0 基线 | 完成 | **ACCEPTED** 2026-09-09 | `docs/m0/M0-acceptance-matrix.md`（18 判据，带 R28） |
| M1 Crash Firewall | 完成 | **从未作为阶段签收** | **没有 M1 验收矩阵**；只有逐任务 DONE + R27 关闭报告 |
| M2 状态观测 | 完成 | **ACCEPTED（有条件）** 2026-09-10 | `docs/m2/M2-acceptance-matrix.md`（23 判据） |
| M3 ProblemState | 完成 | **ACCEPTED（有条件）** 2026-09-10 | `docs/m3/M3-acceptance-matrix.md`（27 判据） |
| M4 Legacy Adapter | 完成 | **ACCEPTED** 2026-09-12 | `docs/m4/M4-01-acceptance-matrix.md`（32 判据）+ `M4-02-report.md` |
| M5 现代输入闭环 | 完成 5/5 | **ACCEPTED（窄口径）** 2026-09-13 | `docs/m5/M5-report.md` + `docs/m5/authoring-contract.md` + `tools/yl_modern_check.py`（N1/N2/N3，release 门禁） |

**M1 是验收链上唯一的洞，而且是最早的一段。** M2/M3/M4 的每一条证据都建立在
`docs/m1/reader-inventory.toml` 之上——它是「这条路径上有哪些读取」的唯一登记。
M0/M2/M3/M4 各有一份独立编制的验收矩阵，M1 没有；它走的是「逐任务 DONE + 条件解除」，
而条件解除的判断本身没有被第二方按判据逐条核过。R29（没有门禁能验证适配器覆盖了哪些读取站点）
至今 OPEN，问的正是 M1 完备性的同一个问题。

**负责人裁定（2026-09-12）**：**不补 M1 验收矩阵**。M1 的问题是**形式验收不完整**，
不是主线技术能力缺失；不为「验收形式对称」增加工作，也不为已有后续实战证据的问题重复做证明。
进入第二功能域之前对 M1 做一次**轻量**复核，目标只有一个：
**reader inventory 与 adapter 覆盖面是否机械可验证**——用一道自动 coverage gate 关闭 R29，
而不是复制 M0/M2/M3/M4 那种完整矩阵。**风险登记表不是工作队列**：26 条 OPEN 不意味着 26 条现在都要处理。

**这不是说 M1 的结论错了**——R27 关闭时命中集由 211 升为 216，四处新站点已按流程补包装，
方言套件与影子差分都在其上跑通。缺的是**独立复核这件事本身**。

## 功能域视图（ADR-0007）

**静力是第一个迁移切片，不是项目终点。** 总体目标是以输入体系现代化为主线，
把 legacy YL 迁移成结构清晰、可校验、可扩展、有回归证据保障的现代结构；
静力切片的真正产物是**一套可复制的迁移方法**，后续按功能域展开。

每个域按五件套判定：**旧输入字段 → 语义 → 内部数据结构 → 新 schema → 回归证据**。
下表的「未开始」是**范围事实，不是缺陷**；站点数取自 `docs/m1/reader-inventory.toml`
的 `not_on_path` 表（本路径不经过的读取站点，54 组、806 处，均已按域登记）。

| 功能域 | 旧字段 | 语义 | 内部结构 | 新 schema | 回归证据 | 里程碑 |
|---|---|---|---|---|---|---|
| **静力（2D Q4 线弹性 / 重力 / 单增量 / PROFILE）** | 已登记 157 处 | 已摸清（有具名缺口） | `ProblemState` + `deck_residue_t` + 运行存在面 | **v1 契约可完整表达两例** | **状态等价与数值等价均已证（严格相等）；新格式亦严格复现冻结参考** | M1～M5 完成，M5 已签收（窄口径） |
| 荷载扩展（点/边/梁板荷载、压力面） | `.loa` 32 处 | 未开始 | — | — | — | M5.pressure / M6 |
| 求解器变体（PARDISO 等） | `.sol` 29 + iafile 5 | 未开始 | — | — | — | M5 |
| 输出与观测点 | `.opr` 10 | 未开始 | — | — | — | M5 |
| 材料（非弹性本构、属性曲线、液化） | `.mat` 104 + 4 | 未开始 | — | — | — | M6.4 / M6.5 |
| 几何与插值扩展（3D、局部坐标、移动网格） | `.nrt` 40 + `.ftr` 13 + 10 | 未开始 | — | — | — | M6.2 |
| 接触与界面 | `.ctt` 16 + `.glb` 部分 | 未开始 | — | — | — | M6.6 |
| 施工/加载过程与重启 | `.man`/`.rtt`/`.resb`/`.stf`/`.stn` 239 | 未开始 | — | — | — | M6.7 |
| 动力与模态（含 VIE/MIF 边界） | `.pre` 20 + `.ifs` 13 + `.man` 动力段 | 未开始 | — | — | — | M7 |
| 温度 / 渗流 / 多场 | `.tem` 25 + `.aqu` 10 + `.upf` 4 + `.inw` 1 | 未开始 | — | — | — | M8 |
| 长尾（反分析、可靠度、水平集、网格细化、优化） | 17 组 152 处 | 未开始 | — | — | — | M9 |
| 输出写出（GiD / COSMOS 等） | 13 组 27 处 | 不属输入迁移 | — | — | — | n/a |

**静力域四项限定，逐条如实**：

- **旧字段**：157 处为**测量集合**（R27 关闭后），但**逐站计数仍是下界**；
  `.tem` 只覆盖本路径读到的零计数记录，其余 25 处属 M8。
- **语义**：`ProblemState.*` 98 行 + `deck_residue_t` 27 行有 owner；具名缺口——
  `nextr` 无持久留存（R25）、守卫表 5 个量不在导出面上（`yl_guard_check.py` 每次点名）。
- **新 schema**：v1 契约 `docs/m5/authoring-contract.md` + `src/authoring/`（严格 TOML 子集读取器、
  校验器 33/33 反例、默认表即代码、authoring → ProblemState 唯一映射层）。两个 golden 算例
  **仅凭 `case.toml` + `.cor`/`.ele`** 驱动求解，工作目录内**没有任何 legacy 控制卡**
  （`yl_modern_check.py` N1 就是这条断言）。`schemas/case.schema.json` 仍是旧 bootstrap，
  无人消费，待 M5 收尾时退役或对齐。
- **回归证据**：**两条路径严格相等**——两例 DISPLACEMENT/STRESS `max|d| = 0.000e+00`，
  三个检查点的 190 个发出字段全部一致（`yl_state_diff` 两例各 `PASS compared=190`）。
  容差按 ADR-0008 §4 定为 `atol = rtol = 0`（噪声测不出来，56 对重复运行）。
  适配器已是默认入口，`--adapter=off` 为回退开关且经门禁测试。
  新格式路径同样 `max|d| = 0.000e+00`（两例 DISPLACEMENT/STRESS，严格）。**限定**：两个 deck。

| 项目 | 状态 | 说明 |
|---|---|---|
| 独立仓库与目录 | 完成 | HSTAR Evolution，已建立 origin/main 跟踪 |
| 历史源码和两个种子算例导入 | 完成 | 不等于认证的生产基线 |
| 总体架构和 M0～M9 路线 | 已编写 | modern 直接初始化；事务提交；显式能力范围 |
| 任务/测试/验收手册 | 已编写 | 待执行，不能计为测试通过 |
| M0 开工前文档修正 | 完成 | ADR-0003（CAE 对象模型 + SI）；02/05/06/08 出口条件按环境实证修正；两例标为回归例 |
| M0-01 来源清单与哈希 | ACCEPTED（M0 签收 2026-09-09） | 源码/算例逐文件 SHA-256、gidpost 桩入库、脏树 15 组 hunk 分类（3 个 VERIFY 项已由 M0-04c 判定为 DEFER，见 docs/m0/orig-worktree-diff.md） |
| M0-02 Linux 构建 | ACCEPTED（M0 签收 2026-09-09） | `env -i` 下 release/debug 可构建，依赖固定并入 manifest；release 冒烟两例与历史输出逐字节相同；检查型 profile 暴露 R17/R18 |
| M0-05a 模型说明与容差登记 | ACCEPTED（M0 签收 2026-09-09） | 两例 MODEL.md / observables.toml / tolerances.toml；两例均为重力回归例 |
| M0-03 隔离运行器 | ACCEPTED（M0 签收 2026-09-09） | 七种状态各有反例；两例 COMPLETED |
| M0-04 参考结果 | ACCEPTED（M0 签收 2026-09-09） | 两例各 3 次逐值相等（B02）；候选脏树二进制两例与 reference 相同（04c）；reference 已冻结到 `cases/golden/*/reference/` |
| M0-05b M0 报告 | **ACCEPTED（负责人 Huijun 签收 2026-09-09）** | `docs/m0/M0-report.md`。**签收只满足判据 18 的一半**：负责人接受成立，「独立于实现人的复核人读过 1～17 条证据」在单人项目里结构性缺席，仍未满足。判据 6（七种隔离状态各有反例）与判据 13（跨路径容差）**签收后仍属断言而非独立证据**；三项一并登记 **R28**。接受范围不因签收而扩大，仍限 `M0-report.md` 的六条「不能声称」 |
| M1-01 reader 清单 | **DONE（条件已解除 2026-09-09）** | 静态全集 1022 处；两例 gdb 实证命中 211 位点（read 152）；`docs/m1/reader-inventory.toml` 经 `check` 通过。**2026-09-08 有条件接受**：`Load.f90:231` 未包装读取已修复并验证（153 readers，153/153 已包装，`wrap_reads` 0 edits，两例 `max|d|=0.000e+00`）。**条件**：遗留 **R27** —— gdb 证据是**下界不是测量值**（`gdb-script` 假设一行一地址），命中集的完备性未被证明；关闭里程碑 **M1-04**，在 M4 影子差分前必须完成 |
| M1-02 checked I/O | **DONE（条件已解除 2026-09-09）** | `src/diagnostics/yl_diag*`；152 个 reader 与 14 个 open 已包装；两例结果逐字节不变；探针 29/29；`--check-legacy` 可用；新盲区 R19/R21。**2026-09-08 有条件接受**：`Load.f90:231` 未包装读取已修复并验证（153 readers，153/153 已包装，`wrap_reads` 0 edits，两例 `max|d|=0.000e+00`）。**条件**：遗留 **R27** —— gdb 证据是**下界不是测量值**（`gdb-script` 假设一行一地址），命中集的完备性未被证明；关闭里程碑 **M1-04**，在 M4 影子差分前必须完成 |
| M1-03 语义守卫 | DONE | 数量/引用/分配守卫（RANGE/REF/DUPLICATE/UNSUPPORTED，`--max-entities`）；R17/R18 关闭；路径上 38 处裸 `stop`（39 条替换，`Temper.f90:455` 一处两条）纳入退出协议；release/debug/strict × 两例精确相同；探针 47/47；注册表 `check` PASS；新契约 R22 |
| M2-01 状态字段映射表 | **ACCEPTED（有条件接受，负责人 Huijun 签收 2026-09-10）** | `docs/m2/state-field-map.toml` 269 字段 / 4 检查点（restart_ready 未覆盖）；`yl_state_map.py check` PASS，**40/40** 非 skip reader 被引用（R27 关闭后新增四个 reader，2026-09-09 更新；原记 39/39）；锚点 `Fem.f90:1909/3603/3657`（M1-02 包装后行号下移；工具按 anchor 内容哈希定位，哈希未变）；S03 目标钉在 E / 约束值 / 重力；新风险 R23、R24。**签收（2026-09-10）**：依 ADR-0005 三份矩阵一并审阅，M2 三条件、M3 一条件签字前全部完成（判据 4 锚点顺序改由测量建立、判据 5 守卫表机械对账 + `stab_matde` 订正、判据 16/17 口径修订为字段值级可复现见 ADR-0006、判据 9 层次边界写明）；带着签的债务：M2 判据 10/22、M3 判据 5/11/25 覆盖残余。**签收不确立 `docs/07` SECTION 02 的任何能力** |
| M2-02 状态序列化与比较器 | **ACCEPTED（有条件接受，负责人 Huijun 签收 2026-09-10）** | 三检查点导出 190 字段（生成式 dump + 25 adapter）；`yl_state.py normalize` 出 §5 九文件与指纹；`yl_state_diff.py` 结构优先定位到对象/字段；dump 开关 × 三 profile × 两例结果逐值不变、`1.flavia.res` 逐字节相同；S01 三次指纹相同；S02 九类反例 + 四类护栏命中；探针 47/47；新风险 R25、R26。**签收（2026-09-10）**：依 ADR-0005 三份矩阵一并审阅，M2 三条件、M3 一条件签字前全部完成（判据 4 锚点顺序改由测量建立、判据 5 守卫表机械对账 + `stab_matde` 订正、判据 16/17 口径修订为字段值级可复现见 ADR-0006、判据 9 层次边界写明）；带着签的债务：M2 判据 10/22、M3 判据 5/11/25 覆盖残余。**签收不确立 `docs/07` SECTION 02 的任何能力** |
| M2-03 两例状态证据 | **ACCEPTED（有条件接受，负责人 Huijun 签收 2026-09-10）** | S01 两例各 3 次指纹相同、3 对两两 PASS；S03 四条扰动探针 4/4 命中（材料 E、约束值、重力，R24 编码为测试）；状态基线冻结到 `reference/state/`（40 文件/例，附 `frozen.json` provenance）；`yl_state_probe.py --selftest` 47/47。**签收（2026-09-10）**：依 ADR-0005 三份矩阵一并审阅，M2 三条件、M3 一条件签字前全部完成（判据 4 锚点顺序改由测量建立、判据 5 守卫表机械对账 + `stab_matde` 订正、判据 16/17 口径修订为字段值级可复现见 ADR-0006、判据 9 层次边界写明）；带着签的债务：M2 判据 10/22、M3 判据 5/11/25 覆盖残余。**签收不确立 `docs/07` SECTION 02 的任何能力** |
| M3-01 ProblemState 类型 | **ACCEPTED（有条件接受，负责人 Huijun 签收 2026-09-10）** | `src/problem/` 最小类型（24 个类型 / 100 字段，98 项对应 M2 映射表，2 项 M5-only）；`opt_*` 包装区分 unset/zero/empty；独立 `problem-types` 构建目标不入求解器链接链（build-id 不变）；`yl_problem_check.py` 双向核对 + 槽位名黑名单；映射表 6 项缺陷修正 + `legacy_only`(47)。**签收（2026-09-10）**：依 ADR-0005 三份矩阵一并审阅，M2 三条件、M3 一条件签字前全部完成（判据 4 锚点顺序改由测量建立、判据 5 守卫表机械对账 + `stab_matde` 订正、判据 16/17 口径修订为字段值级可复现见 ADR-0006、判据 9 层次边界写明）；带着签的债务：M2 判据 10/22、M3 判据 5/11/25 覆盖残余。**签收不确立 `docs/07` SECTION 02 的任何能力** |
| M3-02 输入流水线 | **ACCEPTED（有条件接受，负责人 Huijun 签收 2026-09-10）** | normalize/validate/capability gate/finalize 四阶段，仅 `prepare_problem` 公开、阶段间失败即止、阶段内累积；错误累积器为纯内存（不触 `diag_*`，保证同进程重试）；manifest 记派生/默认/核对三类；反例矩阵 485/485 覆盖每条已实现规则的每个条件，能力表 15 行由套件遍历断言（计数与源码哈希冻结于 `docs/m3/evidence/M3-02-selftest.json`）；5 条无反例规则明确不实现。**签收（2026-09-10）**：依 ADR-0005 三份矩阵一并审阅，M2 三条件、M3 一条件签字前全部完成（判据 4 锚点顺序改由测量建立、判据 5 守卫表机械对账 + `stab_matde` 订正、判据 16/17 口径修订为字段值级可复现见 ADR-0006、判据 9 层次边界写明）；带着签的债务：M2 判据 10/22、M3 判据 5/11/25 覆盖残余。**签收不确立 `docs/07` SECTION 02 的任何能力** |
| M3-03 build_runtime / commit | **ACCEPTED（有条件接受，负责人 Huijun 签收 2026-09-10）** | `src/runtime/` 七个模块。`build_runtime` 产出 46 个 `model_ready` 行 + 值状态账本（DEFINED/RESERVED/ABSENT 35/9/2）+ 派生 manifest，无部分提交由结构保证（局部 candidate，末尾两个 `move_alloc`），12 个注入点由 T01 遍历；`commit_legacy_globals` 为迁移期唯一旧全局写入口，VERIFY+STAGE/WRITE 两段、`commit_release` 幂等、记录数组全局的外来分配一律拒绝（交付时六个；M4-01 步 3 加入 `props` 后为七个）；规则表 60 行（5 check/46 derive/6 inv/3 net），`condition` 列与账本状态 1:1 且受检，两张兜底网走账本而非点名行（未接线的 map 行 = 构建失败）；反向双射由 `yl_state_map.py runtime-rules` 消费自检导出行断言；自检 108/108 + 隔离桥接通过（结论标注 PARTIAL；该计数随 M4-01 折叠增长至 1292，**不再登记具体数字**，以当次运行为准）；求解器 build-id 不变。**与冻结基线的逐值比对未执行**——需 deck→ProblemState 适配器（M4-01），见 `docs/m3/M3-03-runtime.md` §8。**签收（2026-09-10）**：依 ADR-0005 三份矩阵一并审阅，M2 三条件、M3 一条件签字前全部完成（判据 4 锚点顺序改由测量建立、判据 5 守卫表机械对账 + `stab_matde` 订正、判据 16/17 口径修订为字段值级可复现见 ADR-0006、判据 9 层次边界写明）；带着签的债务：M2 判据 10/22、M3 判据 5/11/25 覆盖残余。**签收不确立 `docs/07` SECTION 02 的任何能力** |
| M4-01 静力 Legacy Adapter | **ACCEPTED（M4 阶段签收，负责人 Huijun，2026-09-12）** | `src/adapter/` 的**十个解析器**（`parse_inp/cor/ele/glb/loa/man/mat/pre/sol/tem`，分布在 13 个模块中）把两个 golden deck 解析为 `problem_state_t`；L2-b 方言拒绝并入 M3-02 能力表（每行一个反例，且断言「只有该行触发」；计数随能力表增长，以 `bash tools/build.sh adapter` 为准，验收复核日实测 337/337 ×2）；L2-c 折叠把 ProblemState 那一半并入 `commit_legacy_globals` 的同一次 staging，出处账本 `NOT_MIGRATED` **118 → 0**（162 是 `model_ready` 已发出行的**总数**，不是该桶的起点）；**M4-01 自身判据（影子差分）**：`MATCH=324 MISMATCH=0 NOT_COMPARABLE=158 UNVERIFIED=56`——**仅覆盖 `model_ready`**，另两个检查点新路径不跑求解故到不了；L3-b 冻结基线对拍 `MATCH=64 MISMATCH=0`（红线，折叠十七步未动）；步 6 泄漏可检出性：**21 个内层释放站点中 6 处**（每记录数组一处）由 ASan/LeakSanitizer 阳性对照证明可报出——**工具是 ASan 不是 valgrind**（本机无法安装），且**第一次阳性对照什么都没报**（Intel OpenMP 运行时静默关闭 LeakSanitizer）。**未闭合**：R29（无门禁能验证适配器覆盖了哪些读取站点）、R30（`PROV_VIA_RUNTIME` 的来源是散文、无对账）。报告 `docs/m4/M4-01-report.md`（实现者撰写）；验收矩阵 `docs/m4/M4-01-acceptance-matrix.md`（独立于实现者编制，32 项判据 → **24 独立证据支撑 / 0 不满足 / 4 未建立 / 4 仅有断言**）。**待签收；签 M4-01 不等于签阶段 M4**——阶段四条出口条件里三条属 M4-02 |
| M4-02 独立进程差分与默认入口 | **ACCEPTED（M4 阶段签收，负责人 Huijun，2026-09-12）** | 适配器真正驱动求解：两例 `--adapter=on` 与冻结参考**严格相等**（`max|d| = 0.000e+00`），三个检查点 190 个发出字段全部一致；跨路径容差按 ADR-0008 §4 定为 `atol = rtol = 0`（噪声测不出来），R28 判据 13 关闭；适配器成为默认入口（`yl_adapter_mode` 默认 on，release 链接 `yl_adapter_entry`），`--adapter=off` 回退开关由 `tools/yl_fallback_check.py` 四条断言守住（含「被拒绝的 deck 必须停下、不得自动回落」，该断言当场查出对外判决被压成 INIT 的缺陷）；运行存在面按 ADR-0009 机械清点建立。**legacy 侧改动 19 行且不改变任何文件行数**。**结束**了 M4-01 判据 12（求解器不链接 adapter 目标文件）——出口条件的直接后果。报告 `docs/m4/M4-02-report.md` |
| M5 统一 authoring schema 首次闭环 | **ACCEPTED（窄口径，负责人 Huijun 签收 2026-09-13）** | v1 契约 `docs/m5/authoring-contract.md`；`src/authoring/` 五个模块（严格 TOML 子集读取器、校验器、默认表即代码、authoring → ProblemState 唯一映射层、错误渲染）；反例套件 **33/33**；门禁 `tools/yl_modern_check.py` 接入 release —— **N1** 工作目录只投 `case.toml` + 契约点名的 `.cor`/`.ele`，**没有任何 legacy 控制卡**（这条断言是「新格式在驱动求解」与「新格式恰好没妨碍求解」的唯一区分）；**N2** 两例对冻结 legacy 参考 `max|d| = 0.000e+00`（`atol = rtol = 0`）；**N3** 四个失败形态各自停机、不写结果、每条发现只渲染一次。达成前用状态差分**作诊断**查出四处映射错误（边界记录按 (set, dof, node) 而非 (nset, dof) 展开——lame_cylinder 只约束了 2 个自由度而非 18；`materials[].name` 是相名不是本构模型名；`case.name` 即 `probn` 取自 `mesh.file`；`record_reaction` 默认 1）。`output.stress_averaging` **移出默认表**改为必填——它决定上报应力是什么，按契约准入规则不得替作者选。**签收仅确立**：两例完整新输入闭环、authoring → validation → ProblemState → solver 路径成立、新旧路径数值严格等价、用户侧主要失败路径能明确拒绝并给出可定位诊断。**不确立**白名单之外任何能力；**不把门禁通过表述为独立第三方验证**（与 M0 判据 18 同一结构性缺口，R28）。**限定**：两个 deck / Q4 / elastic_isotropic / static / profile / gravity。带着签的债务：`schemas/case.schema.json` 仍是无人消费的旧 bootstrap |
| M1～M5 实现及验收 | TODO | 尚无 checked I/O、状态比较器、现代初始化或可运行 TOML |
| M6～M9 | BACKLOG | 按真实需求逐能力启动 |

当前没有 production 现代输入能力。构建、求解回归与物理验收尚未在本工程重新执行。
本轮核实了环境（ifx 2025.3、MKL 2026.1、无 gfortran）、原仓库脏树差异、两例 deck 内容与输出路径，
并据此修正文档；没有更改求解器或算例输入。

M3 阶段**延后出口**（ADR-0004）：三个任务各自 DONE，出口条件「bridge 状态等价」需要 M4 的适配器。**该债已于 2026-09-09 由 M4-01 的 L3-b 结清**（`MATCH=64 MISMATCH=0`，见 `docs/m4/L3b-bridge-report.md` 与 ADR-0004 文末「结算」）；按 **ADR-0005**，M2 与 M3 在 M4-01 结束后一并签收，三份验收矩阵已备/编制中。

下一步：**M4-01 的实现已于 2026-09-09 完成**（见上表 M4-01 行与 `docs/m4/M4-01-report.md`），
当前处在 Layer 4：验收矩阵编制、文档与复核。此后按 **ADR-0005** 将 M2、M3 与 M4-01 一并签收。

**签收前已知的三处缺口，均不因签收而消失**：

- **判据 18 的一半结构性缺席**——单人项目无独立于实现人的复核人。M0 已按此签收并如实记录（R28），
  M2/M3/M4-01 的矩阵签字页同样留空。**不得因为前面这样签过就淡化。**
- **R28 判据 13**：跨路径容差是量纲估算（`status="provisional"`），**必须先于 M4-02 的跨路径数值比对定案**，
  而定案需要同一二进制在不同线程数/环境下的重复噪声分布——**那批数据尚不存在**。
- **R29 / R30 未闭合**：前者是「没有门禁能验证适配器覆盖了哪些读取站点」，
  后者是「出处账本的 runtime 来源是散文、无机械对账」。二者都使某类断言不成立，已各自登记关闭条件。
