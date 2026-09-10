# M4-01 验收判据 → 证据映射表

- 候选接受 ID：`M4-static2d-001`
- 编制日期：2026-09-10；编制人：Claude subagent（accept-m2m3）。**未参与本任务任何编码**——
  实现由 dev-fold2 完成，`docs/m4/M4-01-report.md` 由实现者撰写，因此本矩阵把该报告
  **当作待核对的声明，而不是证据**
- 复核基线：`f9a8430`，`git worktree add /tmp/claude-1000/wt-m401 f9a8430`。所有数字**本次重跑**，
  不引用报告或 STATUS
- 本文件不是签收；签字页留空，由负责人填写
- 配套：`docs/m2/M2-acceptance-matrix.md`、`docs/m3/M3-acceptance-matrix.md`（依 ADR-0005 三份一并签收）

## 判决词表

本矩阵用四种判决，它们不可互换：

| 判决 | 含义 |
|---|---|
| **独立证据支撑** | 有可独立重跑的产物或门禁，本次已重跑并核对 |
| **仅有断言** | 只有文字叙述或声明，没有独立可重放的证据 |
| **未建立** | 该判据所要求的东西**根本没有做**——不是证据弱，是没有 |
| **不满足** | 本次复核实测为**红** |

「产物存在」「套件打印 PASS」「任务标着 DONE」**都不算**判据达成。

## 一句话结论

**32 项判据中 23 项有独立证据、1 项不满足、4 项未建立、4 项仅有断言。**
（判决列可被机械清点：每行恰好一个判决。）

实现面本身很扎实：影子差分 `MATCH=324 MISMATCH=0`、红线 `MATCH=64 MISMATCH=0`、
出处账本 `NOT_MIGRATED` 桶为空、staging 投毒、释放盲区首次有仪器——**本次全部逐条重跑，
与报告逐字相同**，且报告主动划定的每一条边界经独立核对**都成立、无一被夸大**。这在本项目里
是少见的：M3 那一轮「所有数字都不复现」，这一轮**所有数字都复现**。

但有四件事必须在签收前看清：

1. **`tools/yl_problem_check.py --selftest` 在 HEAD 上是红的：54/56。**
   判据 A-reg（「M0–M3 既有套件全部不变」）**不满足**。二分定位：`ed7e4eb^`（`9511832`）为
   `56/56 PASS`，`ed7e4eb` 为 `54/56 FAIL`。**`ed7e4eb` 正是为了关闭 M3 矩阵判据 5 而新增的
   规则 15**——规则本身是对的（本次阴性对照确认会响），但它把自检夹具里**缺省的
   `determinism` 键**判成了非确定性，于是两个「好样例必须 PASS」的用例变红。
   **而 `tools/build.sh` 从不调用 `yl_problem_check.py`（`grep -c` → 0）**，所以没有任何
   构建目标会发现它。一条为了消除断言而加的规则，弄红了守着同一个工具的套件，且无人会知道。
2. **四条 M4 阶段出口条件里，只有一条在 M4-01 范围内被建立。**「两条路径的关键结果在容差内一致」
   「适配器成为白名单切片默认入口」「回退开关经测试但不自动触发」——**三条都未建立**，
   按 `docs/05-execution-backlog.md` 它们属 **M4-02**。签 M4-01 不等于签 M4 阶段。
3. **`docs/STATUS.md` 第 27 行写「出处账本 `NOT_MIGRATED` 162 → 0」，这个数字是错的。**
   162 是 `model_ready` 的**发出行总数**，不是 `NOT_MIGRATED` 桶。折叠起点该桶是 **118**
   （`docs/m4/L2c-fold-design.md:73` 「118 行（24+5+89）」、`:696`、`:714`、`:720` 一致），
   报告 headline 的「118 → 0」是对的。**实现报告正确、STATUS 错误**——与 M3 那一轮方向相反。
4. **适配器实际读 10 种 deck，`requirements.md` 写的是 9 种。**`.tem` 在需求里列在
   「不读但必须能拒绝」一栏，实现却在步 4b 新增了 `parse_tem`。这是**有正当理由的范围扩大**
   （折叠需要那些 `not_migrated` 行），但需求文档没有跟着改。

## A. 任务自身的验收判据（`.ccg/tasks/m4-01-legacy-adapter/requirements.md`）

| # | 判据 | 支撑证据 | 复核命令（本次已跑） | 结论 |
|---|---|---|---|---|
| 1 | **A-parse**：两个 golden deck 经适配器构建出 `ProblemState`，走真实 builder + `prepare_problem`，无 finding | `src/adapter/` 十个解析器 + `yl_adapter_driver.adapt_legacy_deck`；影子差分的新侧子进程若有 finding 会中止并把行记为 UNVERIFIED | `python3 tools/yl_shadow_diff.py` 两例新侧均产出完整 `model_ready` 快照、`UNVERIFIED` 仅来自另两个检查点（见判据 3d） | 独立证据支撑 |
| 2 | **A-bridge**（M3 遗留，ADR-0004）：适配器 → `build_runtime` → `commit` 后与冻结基线比对；32 个可比行逐值一致，14 个 ignore 行按性质断言 | `docs/m4/L3b-bridge-report.md`，含 lead 独立复核（§9）与逐字节阴性对照（`STOP RULE TRIGGERED`） | `bash tools/build.sh adapter` → `TOTALS MATCH=64 MISMATCH=0 NOT_COMPARABLE=28 UNVERIFIED=0`；方言套件两例各 `337/337` | 独立证据支撑（范围：`model_ready`、两例、`static-q4-si/1`） |
| 3a | **A-shadow**：两条路径在**独立子进程、独立目录**各跑一次（硬约束，「进程隔离是判据的一部分」） | `tools/yl_shadow_diff.py` 模块头：旧侧由 `yl_run.py` 在 `runs/<case>/<utc>_<hash8>_<label>/work` 起独立进程组；新侧由本工具在自己 stage 的目录里跑；该文件**不含比较器、不含容差、不含 ignore 清单**，判决全部委托给既有 `yl_state.py` + `yl_state_diff.py` | 同上，本次用 `--runs-root` / `--new-root` 指向两个独立目录复跑，结果不变 | 独立证据支撑 |
| 3b | **A-shadow**：**三个**检查点的 state fingerprint 相同 | 实得 `MATCH=324 MISMATCH=0 NOT_COMPARABLE=158 UNVERIFIED=56`（两例各 `162/0/79/28`） | 同上。**独立核实 `UNVERIFIED=56` 的成因**：工具自己打印 `normalize(new): presence narrowed to model_ready; increment_ready(1,1), phase_ready(1) carry no state.txt and are UNVERIFIED below`；28 = 11 + 17，正是 M2 登记的另两个检查点的导出字段数 | 独立证据支撑（**仅限 `model_ready`**） |
| 3d | **A-shadow**：`phase_ready(1)` 与 `increment_ready(1,1)` 两个检查点的等价 | 无。新路径不驱动求解，两个检查点上新侧不产出 `state.txt` | 同上：`UNVERIFIED=56` = 两例 × 28 行（11 + 17），工具自己打印 `presence narrowed to model_ready` | **未建立** — 既不是通过也不是失败，是**没测**。**不得写成「折叠已被验证正确」** |
| 3c | 影子差分的**比较器确实在比**（阴性对照） | `--negative-control FIELD_ID` 会腐蚀新侧一个叶子值 | 预测先写：「恰好 1 条 MISMATCH 点名 `materials.E`，退出码非零」。实得：`materials.E leaf "42174876E8000000" -> "...01"`，`MISMATCH … rule=exact expected=2.5e+10 actual=2.5000000000000004e+10`，`exit=1`。**预测的「MATCH 由 324 降到 323」未命中**——harness 在首个失败算例即停，总计只显示该例。机制正确，我的预测形状错了，如实记 | 独立证据支撑 |
| 4 | **A-numeric**：两条路径的关键结果在 `tolerances.toml` 容差内一致 | 无。报告 §8 主动声明「求解结果等价」未建立 | 影子差分不驱动求解；新路径产出的是快照，不是 `1.flavia.res` | **未建立** |
| 5 | **A-reject**：未支持方言返回 `UNSUPPORTED_LEGACY_DIALECT`，每种拒绝各有反例 | `src/problem/yl_problem_profile.f90:154` `DIALECT_VERDICT = 'UNSUPPORTED_LEGACY_DIALECT'`（单一拼写常量，`docs/02-migration-plan.md:103` 的原文）；`yl_adapter_dialect_test.f90` 的 `run_case` 对每行断言三件事：该行触发、**只有该行触发**、对外判决统一 | `bash tools/build.sh adapter` → 方言套件在**两个** golden deck 上各 `337/337`，含 `-- counter-examples, one per CAP_STAGE_ADAPT row` 与 `-- coverage` | 独立证据支撑（覆盖单位是「表行」而非 rule_id，沿用 M3-02 §6 的教训） |
| 6 | **A-fallback**：回退开关经过测试，但不会自动触发 | 无。求解器的命令行只有 `--check-legacy` 与 `--dump-state`（`grep` `src/diagnostics/yl_diag.f90`）；`src/adapter/**` 中 `fallback`/`回退` 零命中 | 同上 | **未建立** — 无开关，因而也无「经过测试」。按 backlog 属 M4-02 |
| 7 | **A-drift**：求解器 GNU build-id 与本任务开工前一致 | 直接比对 build-id 在本窗口内**不成立**：`git diff --name-only e5b99bb^ HEAD -- legacy/ src/state/ src/diagnostics/` 命中 `Output.f90`、`Temper.f90`、`yl_diag_registry.f90`、`source-manifest.json`、`libiomp5md.dll`。**但归因是干净的**：`git log e5b99bb^..HEAD` 对这些路径只有两个提交——`4f5c407`（M1-04 关闭 R27）与 `c429def`（负责人修干净检出），**没有一个 M4-01 提交碰过求解器输入** | 上述两条 git 命令（已跑）；`bash tools/build.sh release` 得 `sha256=62925fcd658a6f45…` | 独立证据支撑（**按其实质而非字面**：判据要问的是「M4-01 有没有动求解器」，答案是没有，且这个问题由 git 机械回答，比比对一个 build-id 字符串更强。字面读法因并发的 M1-04 而不可能成立） |
| 8 | **A-reg**：M0–M3 既有套件全部不变 | 本次逐条重跑，见下 | `yl_state_map.py check` PASS（269 字段 / 40-40 / skip 114）；`yl_state_map.py --selftest` 97/97；`yl_problem_check.py check` PASS；`yl_state.py --selftest` 42/42；`yl_state_diff.py --selftest` s02=9 guards=4；`yl_state_probe.py --selftest` 47/47；`yl_manifest.py check` 39 files PASS；`build.sh runtime-bridge` 1292/1292。**但 `yl_problem_check.py --selftest` → `SELFTEST FAIL: 54/56`** | **不满足** — 见下方「§F 本次复核实测为红的一项」 |

## B. 硬约束（requirements.md「硬约束」节）

| # | 判据 | 支撑证据 | 复核命令 | 结论 |
|---|---|---|---|---|
| 9 | **不得新增第二个 legacy 全局 writer**：ProblemState 那一半必须折叠进**同一次 staging** | `yl_runtime_commit.f90` 保持 VERIFY → STAGE → WRITE 三段，WRITE 段只有 `move_alloc` 与标量赋值；报告 §0.1 给出理由——**总体性是被 `yl_state_dump` 强制的**：快照在检查点读全局，它不知道第二个 writer 还没跑完 | `grep` 确认全模块仍只有一个 `commit_legacy_globals` 公共入口；`build.sh runtime` 目标**仍不编译** `yl_runtime_commit.f90`（机械保证 `runtime` 二进制无法写 legacy 全局） | 独立证据支撑 |
| 10 | 不改 `legacy/yl` | `git log e5b99bb^..HEAD -- legacy/yl/` 只有 `4f5c407`（M1-04）与 `c429def`（负责人），无 M4-01 提交 | 同判据 7 | 独立证据支撑 |
| 11 | 不改 M2 映射表中参与快照的键 | 判据面 162 行的 id 集合未变：`yl_state_map.py check` 仍报 `190 emitted: 162/11/17`，与 M2-02 交付时逐字相同 | `python3 tools/yl_state_map.py check` | 独立证据支撑 |
| 12 | 新模块不进求解器链接链 | `grep -o "yl_adapter[a-z_]*\.o" build/release/build.log` → **空** | 同上（已跑） | 独立证据支撑 |

## C. 折叠（L2-c）自身的判据

| # | 判据 | 支撑证据 | 复核命令 | 结论 |
|---|---|---|---|---|
| 13 | 出处账本对每一行都有条目，`NOT_MIGRATED` 桶为空 | 折叠起点该桶为 **118** 行（`L2c-fold-design.md:73/696/714/720` 四处一致，`24+5+89`） | `bash tools/build.sh runtime-bridge` → `162 model_ready provenance entries cover the map's 162 emitted rows (bijection, both directions); DERIVED=8, FROM_DECK=27, FROM_PROBLEM=81, FROM_RUNTIME=44, SYNTHETIC=2`——`NOT_MIGRATED` 桶**整个不存在**，五桶和 = 162 | 独立证据支撑（**桶为空这一事实**）。**注**：`docs/STATUS.md:27` 的「162 → 0」是错的，见下 |
| 14 | `NOT_MIGRATED = 0` 这件事**意味着什么** | 报告 §3 自述：**这是账本关于自身的陈述**。步 1 时把 118 个表项从 `NOT_MIGRATED` 翻成 `FROM_RUNTIME` 就能让计数归零且四门全绿——**出口条件曾经可以被一个谎言满足**。折叠后重跑该攻击并补两个方向，三次都被挡（`L2c-fold-design.md`「出口条件的谎言检测」：全翻 → rc=6 / 120 个问题；单行 `FROM_PROBLEM→DERIVED` → 恰好 1；单行 `FROM_DECK→FROM_PROBLEM` → 恰好 1） | 本次未重放三次谎言检测（需改表再重建） | **仅有断言** — 不是因为攻击做得不好，而是**「三个方向都没进去」在逻辑上不等于「不存在能进去的方向」**，而步 1 时第一个方向就进去了。报告自己是这样写的，本矩阵原样保留。该计数的真正作用是**让影子差分第一次可运行**；判据是影子差分，不是这个计数 |
| 15 | Staging 投毒：漏写一行必然失败而非静默 | 每个 staging 缓冲赋值前写 `STAGE_POISON_I`/`STAGE_POISON_R`（`huge()`），指针用 `null_*` 覆盖，两者不重叠。报告 §0.3：**账本只能声明写了，投毒才能让没写显形** | `grep` 确认投毒常量与覆盖点存在；`build.sh runtime-bridge` 1292/1292 通过 | 独立证据支撑（机制层）。**未做**：本次未删一行写入做阳性对照 |
| 16 | `commit-inputs` 覆盖门：staging 读到的每个输入叶子都必须在被读之前检查过 | 现覆盖**两个面**（`problem` 与 `residue`）。报告 §6.4 记录该门**自己犯过它要防的错**：原先只切掉当前被检面的检查子程序，于是 `opt_is_set(residue%x)` 在正则眼里就是一次对 `residue%x` 的读取，**一个守卫的文本替另一个守卫充当了覆盖证据** | `python3 tools/yl_state_map.py commit-inputs` → `PASS: every input leaf the commit staging reads is checked before it is read`；`problem: 86 read / 87 checked`、`residue: 27 read / 27 checked` | 独立证据支撑 |
| 17 | `deck_residue_t` 不是 ProblemState 的后门 | 27 个分量，无 `compare.rule`、不进快照比对面，每个分量须过 `verify_residue_inputs`（26 个 `opt_is_set` + 1 个 `allocated`）与 `verify_residue_against_gates`。模块头**点名了哪些没有交叉校验**：`stab_matde` 的区间、`npoinb`/`nsmat`/`delgroup` 根本没有闸门规则——**这三项靠适配器写对，没有第二道机制** | `build.sh runtime-bridge` → `deck_residue_t carries 27 rows and the computed residue is 27`（残余集合与映射表计算值必须相等，多一个少一个都失败） | 独立证据支撑（27 行的**集合**受机器强制） |

| 17b | `residue` 中**没有闸门交叉校验**的那三项，其值是对的 | `verify_residue_against_gates` 的模块头点名：`stab_matde` 的区间、`npoinb`/`nsmat`/`delgroup` **根本没有闸门规则**——「这三项今天靠的是适配器写对，没有第二道机制」 | 无 | **仅有断言**（模块头自曝，属如实记录而非隐瞒） |

## D. 释放盲区（步 6）

| # | 判据 | 支撑证据 | 复核命令 | 结论 |
|---|---|---|---|---|
| 18 | 仪器**确实会响**（阳性对照） | 报告 §4.3 的六个阳性对照，每记录数组一处 | **本次做了一次独立的第七个阳性对照，刻意挑一个不在报告六处清单里的站点**：删掉 `element(i)%egaus(ig)%djacb` 的释放（assert-guard：目标文本恰好出现一次），`build.sh runtime-bridge --profile asan` → `rc=6`，`SUMMARY: AddressSanitizer: 3120 byte(s) leaked in 26 allocation(s)`，归因到 `yl_runtime_commit.f90:800` 与 `:809` 各 7 条记录。**预测先写且命中**，源码随后还原 | 独立证据支撑 |
| 19 | 「套件全绿」本身是这一步的**发现**，不是噪声 | 上述阳性对照中，`runtime-bridge` 套件仍报 **`PASS: 1292/1292`**——**释放总体性断言一处都看不见** | 同上（已跑） | 独立证据支撑（这条比干净跑的 0 泄漏更有信息量） |
| 20 | 干净树上无泄漏 | — | `build.sh runtime-bridge --profile asan` → `rc=0`，字符串 `LeakSanitizer` 出现 **0 次**，套件 1292/1292 | 独立证据支撑（**其意义完全依赖判据 18**：没有阳性对照，「一片安静」等于什么都没说——这正是报告 §4.2 的教训） |
| 21 | 工具与出口条件的**实质偏离**：ASan/LSan 而非 valgrind，且第一次阳性对照什么都没报 | 设计 §5.4 的出口条件写「外部内存工具」，实施计划写作 valgrind；本机无 valgrind 且 uid 1000 非 root，装不了，改用 `ifx -fsanitize=address` 并新增 `asan` profile。**第一次阳性对照一片安静**：Intel OpenMP 运行时**静默禁用** LeakSanitizer（直接链接→报出；链 MKL 不链 OpenMP→报出；加 `-qopenmp`→静默；只加 `-liomp5`→静默；显式调 `__lsan_do_leak_check()`→仍静默；`ASAN_OPTIONS=detect_leaks=1` 覆盖不了）。ASan 本身全程活着，**只有泄漏检测那一半死了，而且不报错** | `tools/build.sh` 的 `asan` profile 链接参数（顺序版 MKL、不链 OpenMP、`tools/asan/omp_stub.c`）；本次 asan 构建与运行均按此路径 | 独立证据支撑（偏离**已如实记录**，`docs/07` 已收）。**这条本身就是「仪器可以在关着的时候表现得像开着」的实例**，必须随判据一起被读 |
| 22 | 覆盖面：21 个内层释放站点中 **6** 处 | 报告 §4.5 | **本次独立复算分母**：`sed -n '/subroutine commit_release/,/end subroutine commit_release/p' … \| grep -oE 'deallocate \([a-z_]+\(i\)%[a-z_%()]+\)' \| sort \| uniq -c` → **26** 个站点；其中容器级释放 5 个（`element(i)%egaus`、`element(i)%field`、`group(i)%dof`、`group(i)%unode`、`props(i)%mechanical`）；26 − 5 = **21**。分母复现 | 独立证据支撑（**其余 15 处不在结论之内**，不得放宽。我的第七次对照说明 LSan 对未被覆盖的站点同样会响，但那是**仪器的普遍能力**，不等于那 15 处已被验证——它们没有被做过对照） |
| 23 | 仪器的两条构造性盲区 | **LeakSanitizer 只报不可达块**：仍被活的模块变量引用的内存对它不算泄漏，无论持有它多么错误。「全局跨 commit 留着一个陈旧句柄」按构造看不见。另：`commit_legacy_globals` 无线程，故今天不存在被线程持有的泄漏可被漏掉——**若这一点改变，该 profile 就不再充分** | — | **仅有断言**（工具的构造性质，不可由本仓库证明；如实登记即可） |
| 24 | MSan 与 ASan/LSan **互为反面，不是互相替代**，两道门都必须跑 | `sanitize` 查未初始化读取、永远查不出泄漏；`asan` 查泄漏、永远查不出未初始化读取（`tools/build.sh` 头部亦写明 MSan「does NOT detect leaks」） | 两道门本次都跑：`--profile sanitize` → `PASS: 1292/1292`、rc=0；`--profile asan` → rc=0、零泄漏 | 独立证据支撑 |

## E. `docs/05-execution-backlog.md` M4-01 行的三条验收要求

| # | 判据 | 支撑证据 | 结论 |
|---|---|---|---|
| 25 | **完整消费所需路径** | 十个解析器（`parse_inp/cor/ele/glb/loa/man/mat/pre/sol/tem`）。**但 R29 未关闭**：`docs/m1/reader-inventory.toml` 的站点 id 与 `src/adapter/**` 的 `! RD:` 标记之间**没有机械核对** | **仅有断言** — 报告 §5 自己说得最准：「任何形如『适配器覆盖了全部读取站点』的断言，目前既无法证实也无法证伪」。M4-01 关掉的是一个**子集**：落在 `model_ready` 比对面上、有真实比较规则的未覆盖行恰好 4 个，全部源自 `TEM.boundt.*`，由步 4b 覆盖——**这是逐行结论，不是覆盖率结论** |
| 26 | **未知方言拒绝** | 同判据 5 | 独立证据支撑 |
| 27 | **不把动态运行量猜成输入常量** | 两处可核对的实例：①`stab_matde` 的闸门是**关系**而非常量——`src/adapter/yl_adapter_model.f90:401` `if (stab_matde <= nblks)` 拒绝，注释写明「both golden decks carry 99999, a disable sentinel」，`yl_problem_deck_residue.f90` 模块头另记「pinning that constant would silently corrupt the third deck」；②`prescrib` 对齐前提**拒绝而不是猜**：commit 按位置读 `boundary` 与 `ndofix`，两者不等长时发一条点名两个数字的拒绝，而不是取较小者继续 | 独立证据支撑 |

## E2. `docs/02-migration-plan.md` M4 行的第三条阶段出口条件

| # | 判据 | 支撑证据 | 复核命令 | 结论 |
|---|---|---|---|---|
| 28 | **新 Legacy Adapter 成为白名单切片的默认入口** | 无。求解器**不链接任何** adapter 目标文件；适配路径只存在于独立可执行文件 `yl_adapter_shadow` 中 | `grep -o "yl_adapter[a-z_]*\.o" build/release/build.log` → 空（已跑） | **未建立** — 按 `docs/05-execution-backlog.md`，「等价后切换白名单算例」属 **M4-02** |

（编号连续至 28，含 3a/3b/3c/3d 与 17b，**全表共 32 项判据**。每行只带一个判决，
使判决列可被机械清点——本矩阵初稿有两行各带两个判决，清点时发现并已拆开。）

## F. 本次复核实测为红的一项

**`python3 tools/yl_problem_check.py --selftest` → `SELFTEST FAIL: 54/56 expectations`。**

二分定位：

```
ed7e4eb^ (9511832):  SELFTEST PASS: 56/56 expectations
ed7e4eb:             SELFTEST FAIL: 54/56 expectations
```

红的两条都是**「好样例必须 PASS」**类用例（`good sample` 与
`a support module beside the scoped files … is not parsed`）。报文形如：

```
map: case.name is owned by ProblemState.case.name but its determinism is None;
a ProblemState field must be deterministic … (rule 15)
```

根因：自检的合成夹具 map **不写 `determinism` 键**，规则 15 把缺省值 `None` 当作
「非 deterministic」而拒绝。**规则 15 本身是对的**——本次对真实映射表做过阴性对照：
把 `case.name` 的 `determinism` 改成 `pointer`，得到**恰好一条** FAIL、点名规则 15 与该字段，
其余规则保持沉默（预期先写、结果相符）。坏的是夹具与规则的接触面，不是规则的判断。

**为什么没人发现**：`grep -c "yl_problem_check" tools/build.sh` → **0**。
没有任何构建目标运行这个自检；它只在有人手工敲的时候才跑。

**这条与本任务的关系**：`ed7e4eb` 是为了关闭 **M3 验收矩阵判据 5**（初始输入与积分历史变量
分离）而加的。**一条为了消除断言而加的规则，弄红了守着同一个工具的自检套件**，而这个套件
没有门禁承载，于是红了也不会有人知道。处置属负责人；本矩阵只如实记录 A-reg 不满足。

## 明确不能据此声称的事

按 `docs/07-acceptance-and-release.md` M4 行「不能据此声称：未覆盖旧方言可读」，具体化：

- **不能声称「折叠已被验证正确」。** 已验证的是 `model_ready` **一个面**。
  `UNVERIFIED=56` 是 `phase_ready(1)` 与 `increment_ready(1,1)`——新路径不驱动求解，
  到不了那两个检查点，**既不是通过也不是失败，是没测**。
- **不能声称求解结果等价。** 影子差分不产生位移/应力，判据 4 未建立。
- **不能声称适配器已是白名单切片的默认入口。** 求解器**没有链接任何** adapter 目标文件；
  适配路径今天只活在 `yl_adapter_shadow` 这个独立可执行文件里。
- **不能声称回退开关可用。** 没有开关（判据 6）。
- **不能声称适配器覆盖了全部读取站点**，也不能声称反面——R29 未关闭，该断言不可证实也不可证伪。
- **不能声称出处账本的 runtime 来源可信。** R30 未关闭：`PROV_VIA_RUNTIME` 里「值来自哪个
  runtime 量」是散文、无机械对账。把实现从「拷贝 `active_to_component`」改成「计算 `1..nfdof`」
  而不改标签，集合等式照样通过、字节照样相同、**没有门禁会响**。
- **不能声称已排除泄漏。** 覆盖的是 21 个内层释放站点里的 6 处；LeakSanitizer **只报不可达块**，
  被活模块变量持有的陈旧句柄按构造看不见。
- **不能声称白名单之外的 deck 或 `static-q4-si/1` 之外的契约可用。**
- **不能声称 M4 阶段可以签收。** 本矩阵覆盖的是 **M4-01 这个任务**；M4 的四条阶段出口条件里
  三条属 M4-02（判据 4、6 与「默认入口」）。
- **不能声称本阶段已完成负责人签收。**

## 仍属断言、未建立或不满足的项

| 判据 | 当前状态 | 升级所需 |
|---|---|---|
| 判据 4：两条路径关键结果在容差内一致 | **未建立** | 新路径需驱动求解并产出 `1.flavia.res`，再用 `tools/yl_compare.py` 按 `tolerances.toml` 判定。**注意 R28 判据 13**：跨路径容差目前是量纲估算（`status="provisional"`），**必须先于此定案**，否则会以估算数当判据 |
| 判据 6：回退开关 | **未建立** | M4-02：加显式命令行开关，测试它可用、且不在 modern 解析失败时自动触发（`docs/07`「回退使用上一已接受构建……用户显式选择」） |
| 判据 8（A-reg） | **不满足**：`yl_problem_check.py --selftest` 54/56 | ①让规则 15 对「夹具未声明 `determinism`」与「声明为非确定性」区别对待（或给夹具补键）；②**把这个自检接进 `tools/build.sh`**——否则下一次同样不会被发现 |
| 判据 14：`NOT_MIGRATED=0` 的含义 | **仅有断言**：三个方向的谎言检测都被挡住，但那不等于不存在能通过的谎言 | 结构上难以升级（这是账本自指的固有限制）。可行的替代是继续加大投毒与集合等式的独立性——**但判据本来就是影子差分，不是这个计数**，因此不建议为它投入 |
| 判据 22 的其余 15 处释放站点 | **未覆盖**（不是未通过） | 逐站点阳性对照，或一条能遍历释放站点表的机器断言（当前释放路径是代码里的语句，不是可遍历的表——与 M3-02 validate 家族同一形状） |
| 判据 23：LSan 的两条构造盲区 | **仅有断言**（工具性质） | 陈旧句柄类缺陷需要另一类仪器（如 commit 前后对全局指针做身份快照并比对），不在本任务范围 |
| 判据 25：完整消费所需路径 | **仅有断言**，R29 未关闭 | R29 的关闭条件：在 `reader-inventory.toml` 的站点 id 与 `src/adapter/**` 的 `! RD:` 标记之间建立机械核对 |
| 判据 27 之外的 residue 三项（`stab_matde` 区间、`npoinb`/`nsmat`/`delgroup`） | **仅有断言**：无闸门规则交叉校验，靠适配器写对 | 为这三项补闸门规则，或在模块头保留点名（现状即如此，是可接受的如实记录） |
| 复核与负责人签收 | **仅有断言** | 与 M0 判据 18、M2 判据 23、M3 判据 27 相同的结构性缺口：单人项目无独立于实现人的复核人。**不得因为前三个阶段都这样签过就淡化** |

## 本次复核对实现报告的核对结论

`docs/m4/M4-01-report.md` 由实现者撰写，本矩阵把它当作待核对的声明。逐项核对结果：

| 报告的声明 | 本次实测 | 判定 |
|---|---|---|
| 影子差分 `MATCH=324 MISMATCH=0 NOT_COMPARABLE=158 UNVERIFIED=56`，仅 `model_ready` | 逐字相同，两例各 `162/0/79/28`；`UNVERIFIED` 成因由工具自己打印，独立证实 | **属实** |
| 红线 `MATCH=64 MISMATCH=0` | `TOTALS MATCH=64 MISMATCH=0 NOT_COMPARABLE=28 UNVERIFIED=0` | **属实** |
| `NOT_MIGRATED` **118 → 0** | 桶为空已证实；起点 118 与 `L2c-fold-design.md` 四处一致 | **属实**（而 STATUS 的「162 → 0」错误） |
| 释放盲区 21 中 6 | 分母 26 − 5 = 21 独立复算命中；6 处对照未逐一重做，另做第七处独立对照成功 | **属实** |
| `commit-inputs` 两个面均覆盖 | `problem: 86/87`、`residue: 27/27` PASS | **属实** |
| 干净树 asan 零泄漏、MSan 全绿 | rc=0、`LeakSanitizer` 零次；sanitize 1292/1292 | **属实** |
| 报告 §8 列的六条「未建立」 | 逐条核对，**无一被夸大**，且判据 6 与「默认入口」是报告没列而本矩阵补上的 | **属实且偏保守** |
| 方言套件 `317/317` | 实测 **`337/337`**（两例） | 计数已增长；属正常漂移，报告 §7 已声明「凡会增长的计数指向命令而非登记数字」，但 headline 与 §7 之外仍留了具体数 |
| 需求写 9 种 deck | 实际 10 个解析器（含 `parse_tem`） | **范围已扩大**，理由正当，`requirements.md` 未同步 |

**结论：这份实现报告经得起核对。** 它的数字全部复现，它主动划定的边界经独立核实全部成立，
它自陈的缺陷（§6 六条）不是谦辞而是可复用的判断。本矩阵与它的差别只在两处：
**A-reg 今日为红**（报告写作时未跑该自检），以及**三条 M4 阶段出口条件属 M4-02**
（报告未涉及，因为那不是它的范围）。

## 负责人追记（2026-09-10，基线 `9f6c421`）

本矩阵的复核基线是 `f9a8430`。它交付之后，负责人处置了它列出的四件事中的两件，
**在此追记以免签收人拿着一份与 HEAD 不符的判决表**。追记不改上表任何一格的原文——
上表记录的是 `f9a8430` 上的实测，那个实测是对的。

| 矩阵列出的问题 | HEAD (`9f6c421`) 上的状态 |
|---|---|
| **判据 8 A-reg 不满足**：`yl_problem_check.py --selftest` 54/56 | **已修，且修的是两处而不是一处。** ①规则 15 收窄为 `and "determinism" in r`——缺失的 `determinism` 是「未声明」，不是「非确定性」；收窄后**重跑阴性对照确认它仍会响**（恰好 1 个问题点名规则 15），否则就是把规则调松到通过。②**把该自检接进 `problem-types` 目标**——矩阵指出的真正缺陷不是那两个红用例，而是 `grep -c "yl_problem_check" tools/build.sh` → 0：一个守着映射表的工具，有一套守着该工具的自检，却没有任何门禁跑它。新门禁做了阴性对照：退回未收窄的版本 → `SELFTEST FAIL: 54/56` → 构建 `exit 6`。**这道门禁若在昨天就存在，规则 15 落地时会当场被拦。** 现 HEAD 实测 `SELFTEST PASS: 56/56` |
| **`docs/STATUS.md:27` 的「162 → 0」是错的** | **已修为「118 → 0」**（`9f6c421`）。矩阵的判定成立：162 是 `model_ready` 的发出行总数，不是该桶。**实现报告正确、负责人的 STATUS 错误**——与 M3 那一轮方向相反，一并记入 `docs/04` 的复发缺陷表 |
| **四条 M4 阶段出口条件里三条属 M4-02** | **不修，因为它不是缺陷，是范围事实。** 判据 4（容差内一致）、6（回退开关）、28（默认入口）三条留在表中记作「未建立」是正确的做法。**签收 M4-01 不等于签收阶段 M4**；这一点写进签字页，请签收人明确知悉 |
| **需求写 9 种 deck、实际 10 个解析器** | **已同步**：`.ccg/tasks/m4-01-legacy-adapter/requirements.md` 「范围」节改为 10 种，并**在原地追记为什么扩大**（`TEM.boundt.*` 的 4 行在折叠后落进 `model_ready` 比对面），而不是把 9 悄悄改成 10 |

签收人据此看到的最终计数：**32 项判据 → 24 项独立证据支撑、0 项不满足、4 项未建立、4 项仅有断言。**
（原表的 23/1/4/4 中那个「不满足」已转绿；其余三类未动。）

## 签字页

**签收范围（请与签收人确认）**：本页签收的是 **M4-01 任务**，不是 **M4 阶段**。
判据 4、6、28 三条阶段出口条件在本任务内**未建立**，按 `docs/05-execution-backlog.md` 属 M4-02。

**依 ADR-0005，本页与 `docs/m2/M2-acceptance-matrix.md`、`docs/m3/M3-acceptance-matrix.md` 三份一并签收。**


- 复核人：
- 日期：
- 结论（接受 / 有条件接受 / 退回）：
- 条件或退回理由：
