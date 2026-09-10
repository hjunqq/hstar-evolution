# 当前进度

更新日期：2026-09-08。此文件只登记已经发生的事；阶段验收以证据包为准。

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
| M2-01 状态字段映射表 | IN_REVIEW | `docs/m2/state-field-map.toml` 269 字段 / 4 检查点（restart_ready 未覆盖）；`yl_state_map.py check` PASS，**40/40** 非 skip reader 被引用（R27 关闭后新增四个 reader，2026-09-09 更新；原记 39/39）；锚点 `Fem.f90:1909/3603/3657`（M1-02 包装后行号下移；工具按 anchor 内容哈希定位，哈希未变）；S03 目标钉在 E / 约束值 / 重力；新风险 R23、R24 |
| M2-02 状态序列化与比较器 | DONE | 三检查点导出 190 字段（生成式 dump + 25 adapter）；`yl_state.py normalize` 出 §5 九文件与指纹；`yl_state_diff.py` 结构优先定位到对象/字段；dump 开关 × 三 profile × 两例结果逐值不变、`1.flavia.res` 逐字节相同；S01 三次指纹相同；S02 九类反例 + 四类护栏命中；探针 47/47；新风险 R25、R26 |
| M2-03 两例状态证据 | DONE | S01 两例各 3 次指纹相同、3 对两两 PASS；S03 四条扰动探针 4/4 命中（材料 E、约束值、重力，R24 编码为测试）；状态基线冻结到 `reference/state/`（40 文件/例，附 `frozen.json` provenance）；`yl_state_probe.py --selftest` 47/47 |
| M3-01 ProblemState 类型 | DONE | `src/problem/` 最小类型（24 个类型 / 100 字段，98 项对应 M2 映射表，2 项 M5-only）；`opt_*` 包装区分 unset/zero/empty；独立 `problem-types` 构建目标不入求解器链接链（build-id 不变）；`yl_problem_check.py` 双向核对 + 槽位名黑名单；映射表 6 项缺陷修正 + `legacy_only`(47) |
| M3-02 输入流水线 | DONE | normalize/validate/capability gate/finalize 四阶段，仅 `prepare_problem` 公开、阶段间失败即止、阶段内累积；错误累积器为纯内存（不触 `diag_*`，保证同进程重试）；manifest 记派生/默认/核对三类；反例矩阵 485/485 覆盖每条已实现规则的每个条件，能力表 15 行由套件遍历断言（计数与源码哈希冻结于 `docs/m3/evidence/M3-02-selftest.json`）；5 条无反例规则明确不实现 |
| M3-03 build_runtime / commit | DONE | `src/runtime/` 七个模块。`build_runtime` 产出 46 个 `model_ready` 行 + 值状态账本（DEFINED/RESERVED/ABSENT 35/9/2）+ 派生 manifest，无部分提交由结构保证（局部 candidate，末尾两个 `move_alloc`），12 个注入点由 T01 遍历；`commit_legacy_globals` 为迁移期唯一旧全局写入口，VERIFY+STAGE/WRITE 两段、`commit_release` 幂等、记录数组全局的外来分配一律拒绝（交付时六个；M4-01 步 3 加入 `props` 后为七个）；规则表 60 行（5 check/46 derive/6 inv/3 net），`condition` 列与账本状态 1:1 且受检，两张兜底网走账本而非点名行（未接线的 map 行 = 构建失败）；反向双射由 `yl_state_map.py runtime-rules` 消费自检导出行断言；自检 108/108 + 隔离桥接通过（结论标注 PARTIAL；该计数随 M4-01 折叠增长至 1292，**不再登记具体数字**，以当次运行为准）；求解器 build-id 不变。**与冻结基线的逐值比对未执行**——需 deck→ProblemState 适配器（M4-01），见 `docs/m3/M3-03-runtime.md` §8 |
| M4-01 静力 Legacy Adapter | **DONE，待签收** | 九个 `src/adapter/` 模块把两个 golden deck 解析为 `problem_state_t`；L2-b 方言拒绝并入 M3-02 能力表（58 行，每行一个反例，317/317 ×2）；L2-c 折叠把 ProblemState 那一半并入 `commit_legacy_globals` 的同一次 staging，出处账本 `NOT_MIGRATED` **118 → 0**（162 是 `model_ready` 已发出行的**总数**，不是该桶的起点）；**M4-01 自身判据（影子差分）**：`MATCH=324 MISMATCH=0 NOT_COMPARABLE=158 UNVERIFIED=56`——**仅覆盖 `model_ready`**，另两个检查点新路径不跑求解故到不了；L3-b 冻结基线对拍 `MATCH=64 MISMATCH=0`（红线，折叠十七步未动）；步 6 泄漏可检出性：**21 个内层释放站点中 6 处**（每记录数组一处）由 ASan/LeakSanitizer 阳性对照证明可报出——**工具是 ASan 不是 valgrind**（本机无法安装），且**第一次阳性对照什么都没报**（Intel OpenMP 运行时静默关闭 LeakSanitizer）。**未闭合**：R29（无门禁能验证适配器覆盖了哪些读取站点）、R30（`PROV_VIA_RUNTIME` 的来源是散文、无对账）。报告 `docs/m4/M4-01-report.md`；验收矩阵编制中 |
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
