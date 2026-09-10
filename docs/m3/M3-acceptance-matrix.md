# M3 验收判据 → 证据映射表

- 候选接受 ID：`M3-static2d-001`（任务底稿 `docs/m3/M3-01-problemstate.md`、`M3-02-pipeline.md`、`M3-03-runtime.md`）
- 编制日期：2026-09-09；编制人：Claude subagent（accept-m2m3），只读复核 + 在钉住的 `git worktree` 上重跑门禁
- 复核基线：`c0e6087`（`git worktree add /tmp/claude-1000/wt-accept-m2m3 c0e6087`）。共享工作树当时正被 dev-fold2 修改 `src/runtime/**`、`src/problem/**`，本文件的全部数字取自钉住的树
- 本文件本身不是签收；签字页留空，由负责人填写
- 依 ADR-0004 / ADR-0005：M3 的第四条出口条件「bridge 状态等价」由 M4-01 履行，M2 与 M3 一并签收。M2 见 `docs/m2/M2-acceptance-matrix.md`

## 一句话结论

**27 项判据中 22 项有可独立重现的证据，本次全部重跑；5 项仍属断言**（判据 5、9、11、25、27）。

> **更正（2026-09-09，编制人自查）**：本行原写「20 项有证据；7 项仍属断言」，与下表的判决列
> **对不上**——下表 27 行里标 `仅有断言` 的是 5 行，其余 22 行标 `独立证据支撑`。7 这个数字
> 来自本文末尾「升级路径」表的行数，那张表额外收了判据 26 的两条残余与 build-id 附录，
> 二者都不是判决为断言的准则。**摘要与它所概括的表不一致，正是本项目反复编目的那个缺陷形状**，
> 在此更正而非悄悄改数。以判决列为准。
M3 的实现质量在本次复核中站得住：四套门禁（`problem-types` 50/50 + 485/485、`runtime`
108/108 + 双射、`runtime-bridge` 1131/1131、`adapter` 桥接 64/0/28/0 + 方言 317/317×2）
全部在钉住的树上复现，规则覆盖不是「套件绿了」而是**由可遍历的表逐行断言**（能力表 15/15、
规则表 60 行、七扇提交门各有反例）。ADR-0004 移交给 M4-01 的那条出口证据由
`docs/m4/L3b-bridge-report.md` 结清，且**带 lead 的独立复核与一次真实阴性对照**（逐字节改基线
一个值 → `MISMATCH` + `STOP RULE TRIGGERED`），这在本项目里是证据强度最高的一档。

需要在签收时看清、而读 `docs/STATUS.md` 会被顺过去的有四件：
1. **`docs/05-execution-backlog.md` 给 M3-01/M3-02 写的两条验收要求，在整个仓库里找不到任何
   对应的文档段落或断言**——「初始输入与积分历史变量分离」和「未知字段拒绝」。二者都能论证
   为「结构上成立」，但**没有人写下过这个论证**，也没有门禁指名它们（判据 5、9）。
2. **「每条已实现规则的每个条件都有反例」只对能力门是常设控制，对 validate 家族不是。**
   M3-02 §7 自己说得很清楚：validate 的条件只作为代码里的 raise 点存在，补的是「一次已完成
   的审计，不是常设控制」，并预言「它会和能力门当初一样退化」（判据 11）。
3. **`ProblemState` 并不能独自表示两个基准 deck。** M4-01 交付后新增了
   `src/problem/yl_problem_deck_residue.f90`：**27 行** deck 值抵达 legacy 全局却没有任何
   `ProblemState.*` owner；`model_ready` 的 162 个 provenance 条目里 `FROM_PROBLEM` 只有 **49**、
   `NOT_MIGRATED` 有 **66**（判据 23）。这不必然是缺陷（映射表自己把这些行判给 `derived`/
   `not_migrated`），但 `docs/02` 的出口条件字面是「`ProblemState` 可以**完整**表示两个首批基准」。
4. **STATUS 与底稿里的桥接计数都不复现。** `docs/STATUS.md` 第 26 行写 `581/581`、
   `M3-03-runtime.md` §6 写 `513/513`，HEAD 上实测 **1131/1131**；提交守卫的「六个记录数组全局」
   在 HEAD 上已是**七个**（M4-01 加入 `props`）。数字变大是 M4-01 扩充所致、不是坏事，但
   **M3-03 自己的数字今天已无法在 HEAD 上复现**，要核对必须 `git show` 回到 M3-03 的提交。

## 验收判据 → 证据映射表

判据引自 `docs/07-acceptance-and-release.md` M3 行「类型/所有权、校验/派生来源、事务失败及恢复、
~~bridge 状态等价~~」，并入 `docs/02-migration-plan.md` §M3 的四条出口条件与
`docs/05-execution-backlog.md` 中 M3-01/02/03 的验收列逐条展开。

### A. 类型与所有权（M3-01）

| # | 判据 | 支撑证据（路径 + 具体字段/数字） | 复核命令 | 结论 |
|---|---|---|---|---|
| 1 | 顶层结构按 ADR-0003 的 CAE 对象模型（case、mesh、materials、sections、amplitudes、interactions、steps、solver） | `docs/m3/M3-01-problemstate.md` 的八个分节，字段数 2/10/13/17/4/1/47/6；`src/problem/yl_problem_types.f90` | `python3 tools/yl_problem_check.py check` → `PASS: 98 exported ProblemState fields, 100 type fields (92 optional, 2 M5-only), 24 types, deny list 252/260 legacy slot names, 7 derive-rule constants`（已跑） | 独立证据支撑 |
| 2 | 98 项已导出字段与类型双向核对通过（映射表 `owner` 路径 → Fortran 字段名，机械推导） | 同上；`tools/yl_problem_check.py` 头部：字段名从 `owner` 路径推导而非从 `id`（`id` 仍带 `gid_u`/`icreep`/`type_nalgo` 等 Fortran 拼写） | 同上 `check` PASS；`--selftest` → `SELFTEST PASS: 56/56`（每条规则 1–13 各有一个必须 FAIL 的变异，含「用例名所称规则号必须等于匹配报文的规则号」这条常设断言）（已跑） | 独立证据支撑 |
| 3 | 类型中无 Fortran 槽位名 | 规则 10：deny 列表**机械地**从映射表的 `legacy_symbol` 末段与 `derived.counts.*` 收割，再减去干净 owner 路径自己用到的词 | `check` → `deny list 252/260 legacy slot names`（已跑） | 独立证据支撑 |
| 4 | 缺失 / 零 / 空三态分离（`opt_*` 包装 + 集合分配状态） | `yl_problem_optional`；`yl_problem_builder` 的私有枚举 `COLL_UNSET/EMPTY/FILLED`，`COLL_EMPTY` 全文件仅 11 处赋值；I04 断言三态互不混淆；M3-02 §9 另拆出**发布侧**一条（作者显式声明的空集合必须以显式空的形态穿过 finalize） | `bash tools/build.sh problem-types` → `PASS: 50/50`（类型级）+ `PASS: 485/485`（流水线），日志含 `ok I04 …`、`ok P-emp …`（已跑） | 独立证据支撑 |
| 5 | 初始输入与积分历史变量分离（`docs/05` M3-01 验收列） | **找不到任何证据**：`docs/m3/*.md`、`docs/tasks/M3-01.md`、`src/problem/**`、`tools/yl_problem_check.py` 中都没有「历史」/`history`/`gpvar`/`stres0` 的段落或断言 | `grep -rn "历史\|history" docs/m3/*.md docs/tasks/M3-0*.md` → 无命中；`grep -n "gpvar\|stres0" docs/m2/state-field-map.toml` → 仅出现在两条 `ignore`/说明性 note 里，无 `ProblemState.*` owner（均已跑） | **仅有断言（本次复核后已部分升级）** — 分离在结构上成立（`ProblemState` 的字段全部由映射表的 `ProblemState.*` owner 机械推导，而 `element%estif/alfa/stres0/gmatx`、`gpvar0/gpvar` 在映射表里没有 ProblemState owner），但编制本矩阵时**没有任何文档写下过这个论证，也没有门禁指名它**——它靠判据 2 的双射顺带成立，映射表加一行就可能不成立。**2026-09-09 由负责人补上 `yl_problem_check.py` 规则 15（`ed7e4eb`）**：任何 `ProblemState.*` owner 的行其 `determinism` 必须是 `deterministic`，规则从映射表**派生**而非维护一张会腐烂的历史槽位清单。本次对它做了阴性对照——把 `case.name` 的 determinism 改为 `pointer`，得到**恰好一条** FAIL 且点名规则 15 与该字段，其余规则保持沉默（预期先写、结果相符）。**残余仍属断言**：规则是**必要条件而非该性质本身**（其 docstring 亦如此声明并回指本判据）——一个在其检查点上恰好确定性的历史槽位仍能通过 |
| 6 | YL「组」拆为 elset / section / material | 类型表：`mesh%elsets(i)%elements(:)`、`sections(i)%*`（17 项）、`materials(i)%*`（13 项）各自独立；映射表 `mesh.sets.elset` / `sections.*` / `materials.*` 三组 owner 前缀不同 | `python3 tools/yl_problem_check.py render` 的输出与 `docs/m3/M3-01-problemstate.md` **逐字节相同**（已跑，`diff` 无差异），即该文档是生成物、不能手工漂移 | 独立证据支撑 |

### B. 校验、派生来源与事务（M3-02）

| # | 判据 | 支撑证据 | 复核命令 | 结论 |
|---|---|---|---|---|
| 7 | 四阶段流水线，仅 `prepare_problem` 公开，阶段间失败即止 | `src/problem/yl_problem_pipeline.f90`；阶段私有、屏障顺序无法绕过 | `build.sh problem-types` 日志 `-- 5. stage barrier`：`ok P-stage validate did not run` / `the capability gate did not run` / `finalize did not run` / `the later-stage defects are not reported` / `finalize produced no manifest entry`（已跑） | 独立证据支撑 |
| 8 | 阶段之内累积全部独立缺陷 | 同上 | 日志 `-- 6. accumulation within a stage`：`ok P-acc at least three findings accumulated` + V1/V2/V4 各自被报出（已跑） | 独立证据支撑 |
| 9 | 未知字段拒绝（`docs/05` M3-02 验收列） | **找不到**：`grep -rn "未知字段\|unknown field" docs/m3/M3-02-pipeline.md docs/tasks/M3-02.md src/problem/yl_problem_pipeline.f90` → 无命中 | 同上（已跑） | **仅有断言** — 可以论证为结构上不可表达：`problem_state_t` 是强类型 Fortran 派生类型，「未知字段」在这一层写不出来；deck 文本里的未知字段属 M4 的方言门（`yl_adapter_dialect_test` 317/317 覆盖 `CAP_STAGE_ADAPT` 每一行）与 M5 的 authoring 契约。**但这个论证同样没有人写下来**，验收列的这条要求在 M3 的三份底稿里没有落点 |
| 10 | 不支持的组合被能力门拒绝，且**每一行**都有反例 | `yl_problem_profile` 的能力表 `static-q4/1`，15 行对应 6 个 rule_id（G1 占 4 行、G2 占 3、G3/G4 各 2、G5 占 1、G6 占 4）；M3-02 §6：审计曾发现 **6 行从未被任何反例触达**，都因为同 id 的另一行让它「看起来被覆盖」；处置是**常设断言**——自检运行期遍历能力表，按 `object_path`+`field` 把真实 finding 匹配回表行，任一行未触发即整套失败并点名该行；lead 实证插入第 16 行不写反例得到 `covered: 15/16`、`NEVER TRIGGERED`、`FAIL` | `build.sh problem-types` 日志：`capability rows covered: 15/15` + `ok P-cov every declared capability row has a counter-example`（已跑） | 独立证据支撑（本项目里覆盖度量做得最扎实的一处：单位是「行」不是 rule_id，且守卫本身有过一次可证伪的实证） |
| 11 | validate 家族「每条已实现规则的每个条件都有反例」 | M3-02 §7 自述：8 条规则的多数分支从未被触达（V1 有 11 个条件只覆盖 1 个，V22 有 10 个覆盖 1 个，V21 有 8 个覆盖 1 个），补齐后自检 286→456；并明确写「**validate 的条件守不住**，因为它们只作为代码里的 raise 点存在……这边补的是一次**已完成的审计，不是常设控制**。它会和能力门当初一样退化」 | 无机器判据（能力表可遍历，validate 规则表不可遍历） | **仅有断言** — 文档自曝。升级路径由 M3-02 §7 自己给出并对 M3-03 下了硬性要求：「新增校验规则必须声明在可遍历的表里」。M3-03 **照做了**（判据 19 的 60 行规则表 + B-cov），但 **M3-02 自己的 validate 家族至今没有回改** |
| 12 | 派生值与默认值在 manifest 中可溯源（流水线侧） | `yl_problem_manifest` 三类条目：`derived`（规则/来源/结果）、`default`（profile 与版本）、`check`（声明值 vs 派生值 vs 判定，让通过的核对也留痕）；M3-02 §4 明确「条目数随 draft 规模变化，不是常数」——两个约束集合的 good draft 是 16 条而非 15，并记下「记数时必须写明针对哪个 draft」 | `build.sh problem-types` 日志：`ok P-ok manifest has derived mesh.elements.elset` / `mesh.elsets[1].elements` / `mesh.nsets[1].nodes` / `sections[1].material_header` / `sections[1].material` / `default sections[1].stress_components` / `the 8 declared-count checks`（已跑） | 独立证据支撑（**范围受限**：断言是「这个 fixture 上这些条目在」，不是「任何 draft 的每个派生都必有条目」；后者在流水线侧没有可遍历表可依） |
| 13 | 派生值在 manifest 中可溯源（runtime 侧） | `yl_runtime_rules` 的规则表含一条 net：`NET-MAP-BIJECTION/manifest-derive-rows-match-map` | `bash tools/build.sh runtime` 日志：`ok B-ok[1] manifest holds exactly the produced-row count`、`RULE\|build-runtime/1\|NET-MAP-BIJECTION/manifest-derive-rows-match-map\|net…`（已跑） | 独立证据支撑（比判据 12 强一档：这里是机器守的双射，不是逐 fixture 断言） |
| 14 | 失败不留半成品且可同进程重试（T01，流水线） | 错误累积器 `yl_problem_errors` 是**纯内存**，不调用任何 `diag_*`（那些例程持有全局 pending 状态并会终止进程）；每阶段先建候选、成功才 `move_alloc` | `build.sh problem-types` 日志 `-- 4. T01 transaction`：`the draft is unchanged after the failed run` / `no problem state was published` / `no manifest entry was produced` / `a legal draft succeeds immediately afterwards` / `the retry produced a manifest`（已跑） | 独立证据支撑 |

### C. build_runtime / commit 与所有权（M3-03）

| # | 判据 | 支撑证据 | 复核命令 | 结论 |
|---|---|---|---|---|
| 15 | 分配失败无部分提交：12 个注入点由 T01 遍历，先前的好 runtime 逐位存活 | `build_runtime(..., fail_at)` 是测试钩子；全程建在局部 candidate 上，末尾两个 `move_alloc` 之前每个子构建都有 errors 计数闸门 | `bash tools/build.sh runtime` → `PASS: 108/108`，日志 `-- 4. T01 (no partial commit under allocation failure)`，逐点 `ok T01 site dof/topology/boundary/activation/increment/amplitudes… the manifest gained no entry`（已跑） | 独立证据支撑 |
| 16 | 合法加载 → 失败加载 → 合法加载通过；重复加载逐位相同；`runtime_free`/`commit_release` 幂等 | T02 | 同上，日志 `-- 5. T02 (repeat load: equality, idempotent free, correct reload)`（已跑） | 独立证据支撑 |
| 17 | `commit_legacy_globals` 是迁移期**唯一**写旧全局的入口 | 机械保证而非注释保证：`tools/build.sh` 的 `runtime` 目标**不编译** `yl_runtime_commit.f90`（该模块 USE legacy 模块，只属 `runtime-bridge`），因此 `runtime` 二进制里任何自检都**不可能**写 legacy 全局 | `tools/build.sh` 头部注释原文；`build/rt/build.log` 的链接行确认 `yl_runtime_commit.o` 不在其中（已读） | 独立证据支撑 |
| 18 | 记录数组全局的外来分配一律拒绝（W4 守卫），且**每扇门**各有反例 | Round 2 审查发现守卫清单漏了 `trans`，且「桥接的 513 条断言里没有一条碰过这个守卫」；处置是清单驱动遍历。HEAD 上清单已是**七**个（`element`/`group`/`listp_group`/`prescrib`/`tcurves`/`trans`/`props`，`props` 随 M4-01 step 3 加入并在同一提交登记），`yl_runtime_bridge_test.f90:1297` 的 `NAMES(7)` 逐个 `allocate_foreign` → 断言拒绝、`commit_owned` 保持 false、自己的外来分配未被动过 | `bash tools/build.sh runtime-bridge` → `PASS: 1131/1131`，日志 `-- 6. the W4 foreign-allocation guard, one door at a time`（已跑） | 独立证据支撑 |
| 19 | 规则表的 46 个 derive 行与 M2 映射表 model_ready 的 46 个 `RuntimeState.*` 行双向双射 | `yl_runtime_rules` 60 行 = 5 check + 46 derive + 6 invariant + 3 net；Fortran 侧断言正向与单射，Python 侧断言反向 | `build.sh runtime` → `PASS: build-runtime/1 60 rules, 46 produce the 46 model_ready RuntimeState map rows (bijection, both directions)`（已跑）。lead 在 `docs/m4/L3b-bridge-report.md` §9.1 独立核过分母：映射表里 `model_ready` 且 `id` 以 `runtime.` 开头的是 53 行、`ignore` 21 个，差的 7 行在映射表里全是 `owner=not_migrated`/`emit=none`，**46/14 成立且不是循环论证** | 独立证据支撑 |
| 20 | `runtime_state_t` 无别名分量（所有权即分配状态） | `src/runtime/yl_runtime_types.f90` 整个文件不出现指针关键字 | `grep -nic "pointer" src/runtime/yl_runtime_types.f90` → `0`（已跑） | 独立证据支撑（**范围受限**：这是一条 grep，只作用于一个文件；它不是构建期门禁，未被 `build.sh` 执行） |
| 21 | 数值保真：Gauss 几何按 legacy 语句逐句复刻（求积字面量在默认实精度求值后加宽；`jacob` 用显式循环不用 `MATMUL`；形函数保持 `(1-t-s+st)*0.25` 而非因式分解） | `M3-03-runtime.md` §5；契约里写作 `real(1./3.**0.5, real64)` | 逐句复刻本身是**论证**；实证在 `docs/m4/L3b-bridge-report.md` §4：三个 `abs_tol` 行（`atol=1e-14, rtol=1e-12`，容差取自映射表本身）在两个真实 golden 算例上的实测最大偏差已列表，全部 MATCH。本次 `bash tools/build.sh adapter` 重跑得到同样的 `MATCH=64 MISMATCH=0`（已跑） | 独立证据支撑（经 M4-01 的 L3-b 实证；M3-03 阶段内它只是论证） |

### D. 出口条件与阶段级判据

| # | 判据 | 支撑证据 | 复核命令 | 结论 |
|---|---|---|---|---|
| 22 | **bridge 后的 state fingerprint 与原路径一致**（`docs/02` 出口条件四，经 ADR-0004 移交 M4-01） | `docs/m4/L3b-bridge-report.md`：`适配器 → build_runtime(static-q4-si/1) → commit_legacy_globals → 回读真实 legacy 全局 → 对 cases/golden/<case>/reference/state/model_ready/*.json`，46 行 × 2 例 = 92 行判定，**MATCH=64 / MISMATCH=0 / NOT_COMPARABLE=28 / UNVERIFIED=0**，停止规则未触发。§9 lead 独立复核：自建编译链重跑逐字相同；**阴性对照**——把 `cooks_membrane` 基线 `mesh.json` 里 `runtime.element.ice0` 的首元素**逐字节**改 `0→1`，程序立即报 `MISMATCH … baseline=1 runtime=0` + `STOP RULE TRIGGERED` 并 `error stop`；并记下无效对照的教训（用 `json.dump` 重写基线会退化为 UNVERIFIED，必须逐字节改） | `bash tools/build.sh adapter` → 桥接 `TOTALS MATCH=64 MISMATCH=0 NOT_COMPARABLE=28 UNVERIFIED=0`；方言套件在两个 deck 上各 `317/317`（已跑，与报告逐字相同） | 独立证据支撑（**范围受限，报告 §0.1 自己划定**：只比 `model_ready` **一个**检查点、只两个 golden deck、只 `static-q4-si/1` 一个契约；不驱动求解器、不是影子差分、不是数值结果等价性证明；14 个 `ignore` 行的值不在判定范围内） |
| 23 | **`ProblemState` 可以完整表示两个首批基准**（`docs/02` 出口条件一） | `docs/m4/L3a-fidelity-report.md`：仓库侧手写 parser 的 draft 与「驱动真实 legacy reader 再从全局收割」的 oracle draft，按映射表全部 98 个 `ProblemState.*` 行逐字段对拍，**终审判定 MATCH=95 / MISMATCH=0 / NOT_COMPARABLE=3**（`sections.material_header`、`sections.material` 为下一阶段派生列；`mesh.sets.nset` 集合行数不一致），且报告把工具原始输出 95/2/1 与终审 95/0/3 **两组数字都列在最前**。**但另一侧的事实**：`src/problem/yl_problem_deck_residue.f90` 承载 **27 行** deck 值——它们抵达 legacy 全局却没有任何 `ProblemState.*` owner，模块头明确「必须**不**成为 `problem_state_t` 的一部分」；`model_ready` 的 162 个 provenance 条目按来源分布，其中 `FROM_PROBLEM` 与 `NOT_MIGRATED` 是**随 M4-01 折叠进度变动的量，不是定值**：2026-09-09 12:04（`f4d6432`）实测 `DERIVED=5, FROM_PROBLEM=51, FROM_RUNTIME=44, NOT_MIGRATED=60, SYNTHETIC=2`；约一小时前（`c0e6087`）同一命令给出 `3 / 49 / 42 / 66 / 2`。折叠仍在进行，`NOT_MIGRATED` 归零是 **M4-01 的出口条件**。相对不动的是 `deck_residue_t` 的 **27 行**（两次测量相同） | `bash tools/build.sh runtime-bridge` 末尾的 `commit-provenance` 交叉校验：`162 model_ready provenance entries cover the map's 162 emitted rows (bijection, both directions); DERIVED=5, FROM_PROBLEM=51, FROM_RUNTIME=44, NOT_MIGRATED=60, SYNTHETIC=2` + `deck_residue_t carries 27 rows and the computed residue is 27`（`f4d6432` 上已跑）。**引用这两个数字时必须带提交号**——它们每天都在动 | 独立证据支撑（**范围受限，且与出口条件的字面不完全重合**）——「完整表示」成立的是：映射表判给 `ProblemState.*` 的 98 行中 95 行在两例上与 legacy 一致。**不成立的是字面读法**：deck 里还有 27 行值必须走 `deck_residue_t` 这条旁路才能到达 legacy 全局，且 `NOT_MIGRATED` 尚未归零（该数字归零是 **M4-01** 的出口条件，不是 M3 的）。签收 M3 时要判的是**前一句**是否满足出口条件，而不是等后一句变成 0 |
| 24 | **无半初始化提交**（`docs/02` 出口条件二） | 两处均为结构性保证：`build_runtime` 全程建在局部 candidate、末尾两个 `move_alloc` 之前每个子构建有闸门（判据 15）；`commit_legacy_globals` 分 VERIFY+STAGE 与 WRITE 两段，WRITE 段只有 `move_alloc` 与标量赋值，**无分配、无转换、无失败路径** | `build.sh runtime` 108/108（T01/T02）+ `build.sh runtime-bridge` 1131/1131（含「被拒绝的提交什么也没碰」「重复提交与 release/recommit 循环逐位稳定」「提交契约之外的全局未被扰动」）（已跑） | 独立证据支撑 |
| 25 | 泄漏与用后释放 | `M3-03-runtime.md` §8 自述**未做**：「进程无法观测自己的泄漏。需要 ASan/valgrind 目标与 shell 层比对，本任务未做」；`tools/build.sh` 的 `sanitize` profile 头部同样写明「it is MemorySanitizer（未初始化内存使用），**does NOT detect leaks**。Leak evidence needs `-fsanitize=address` or valgrind and is still **NOT PERFORMED**」 | `sanitize` profile 下 `runtime-bridge` 曾报 720/720（未初始化内存维度），**与泄漏无关**（本次未重跑 sanitize） | **仅有断言（实为未建立）** — 这是 M3-03 报告自曝、且必须原样出现在验收矩阵里的那一条。`commit_release` 的幂等与「只释放本模块分配过的存储」有断言，但「没有泄漏」没有 |
| 26 | 桥接结论的强度：M3-03 的桥接证据**按构造是 PARTIAL** | 桥接二进制自己打印的 `CONCLUSION`（本次原样复现）：「…It does NOT run any solver consumer, does NOT compare against the frozen M2 baseline (no deck-to-ProblemState reader exists yet — M4-01), and **CANNOT** show the absence of a leak or a use-after-free from inside this process」 | `bash tools/build.sh runtime-bridge` 输出（已跑） | 独立证据支撑（限制本身是被证据打印出来的，不是事后补的措辞）。**注意**：其中「不与 M2 冻结基线比对」这一条已由判据 22 在 M4-01 里补上，另两条仍然成立 |
| 27 | 复核与负责人签收 | 无。M3-01/02/03 三项 STATUS 均为 DONE；ADR-0004 明确阶段签收推迟；与 M0 判据 18、M2 判据 23 同一形态——单人项目里没有独立于实现人的复核人。**局部例外**：判据 22 的那份报告有 lead 的独立复核（`L3b-bridge-report.md` §9），是本项目里唯一一次「不同的人用自己的编译链重跑 + 做阴性对照」 | `grep -n "M3-0" docs/STATUS.md`（已跑） | **仅有断言** |

## 明确不能据此声称的事

按 `docs/07-acceptance-and-release.md` M3 行「不能据此声称：modern 已实现」，具体化：

- **不能声称 modern 输入路径可用。** M3 不含 parse/reader；`case%units` 与
  `amplitudes%name` 两个字段是 `M5-only`，legacy 路径上恒 unset。
- **不能声称求解器等价。** M3 的 commit **不接线进求解器**；影子进程差分是 L3-c 的职责，
  L3-b 报告 §0.1 明确「不是数值结果等价性证明」。
- **不能声称没有泄漏或用后释放**（判据 25）。
- **不能声称 14 个 `ignore` 行的值是对的。** 值状态账本区分 `DEFINED`(35)/`RESERVED`(9)/
  `ABSENT`(2)；分配状态能把 `ABSENT` 与另两者分开，**分不开 `RESERVED` 与 `DEFINED`**——
  「这些字节没有意义」不是数组的结构性质，它逐行记在 `runtime%field_status` 里、由
  `run_nets` 断言账本状态等于规则表 `condition` 列，但账本内容本身是**声明**。
- **不能声称 `phase_ready` / `increment_ready` 的 RuntimeState 已建立。** 不在 M3-03 范围内。
- **不能声称能力门放宽后现有不变量仍然成立。** M3-02/03 把不变量分成「因构造不可达」与
  「因能力上限不可达（**有失效日期**）」两类：`INV-EMPTY-DERIVED`（section 数 > 1 时失效）、
  `INV-NTOTV-POSITIVE`（注 `review 2026-12-31: fields widen`）属后者。
- **不能声称 Fortran 侧有自动化质量/安全门禁。** CCG 的 `verify-quality`/`verify-security`
  对 `src/runtime` **扫描 0 文件**（不识别 `.f90`），约 5000 行的质量保证实际来自编译器
  `-warn all -stand f18` 零告警、自检、双射校验与人工审查。已登记为 M3-03a，**未开工**。
- **不能声称本轮审查经过外部模型交叉验证。** codex 在裸连通性探针上即以
  `codex_models_manager` 超时失败，改用两个干净上下文的 Claude reviewer 替代（M3-03 §8 自述）。
- **不能声称本阶段已完成负责人签收**（判据 27）。

## 仍属断言而非独立证据的项

| 判据 | 当前状态 | 升级为独立证据所需 |
|---|---|---|
| 判据 5：初始输入与积分历史变量分离 | **必要条件已由规则 15 机器强制**（`ed7e4eb`，本次阴性对照确认会响）；残余是「恰好确定性的历史槽位仍能通过」，且 M3-01 底稿仍未写下这条论证 | 在 M3-01 底稿写明该论证与规则 15 的作用边界；若要覆盖残余，需要一个独立于 determinism 的判据（例如按 legacy 槽位的**首次赋值位点**是否晚于检查点来分类），但这条是否值得做由负责人判断——当前残余的可达性很低 |
| 判据 9：未知字段拒绝 | 同上，无落点。结构上由 Fortran 强类型 + M4 方言门覆盖 | 在 M3-02 底稿里写明「这条验收要求在本层由类型系统承担，deck 文本侧由 M4 的 `CAP_STAGE_ADAPT` 表承担」，并指向 `yl_adapter_dialect_test` 的逐行反例；或明确把它移出 M3 的验收列 |
| 判据 11：validate 家族每条件反例 | 一次已完成的审计，非常设控制；M3-02 §7 自己预言会退化 | 按 M3-02 §7 对 M3-03 下的那条硬性要求，回过头把 validate 规则也声明进可遍历的表，使「每条规则的每个条件都有反例」成为套件断言（M3-03 已经这样做了，M3-02 没有回改） |
| 判据 25：泄漏 / 用后释放 | 未做 | 建 ASan 或 valgrind 目标 + shell 层比对（进程内无法观测自身泄漏），并把它做成 `tools/build.sh` 的一个目标——「没有构建目标的套件不是门禁，无论手工跑起来多绿」（`build.sh` 头部对 `adapter` 目标的原话） |
| 判据 26 的残余两条 | 桥接不跑任何求解器消费者、进程内看不到泄漏/UAF | 前者属 L3-c 影子差分；后者同上 |
| 判据 27：复核与负责人签收 | 无独立复核人（判据 22 的那一份除外） | 与 M0 判据 18 相同的结构性缺口 |
| **附**：M3-03 的求解器 `build-id` 不变（`b10f13ba5694…`） | M3-03 §6 的证据在**当时**成立；HEAD 上 `legacy/yl` 已被 R27 关闭改动，重建的 release 二进制 sha256 为 `24d770c9a7db7ffe…`，**该判据无法在 HEAD 复现** | 这是历史性证据，只能在 M3-03 的提交上复核（`git show`）。不需要升级，但引用时必须说清它绑定的是哪个提交 |

## M3 提出的风险的当前状态

M3 的三个任务**没有向 `docs/08-risk-register.md` 新增任何风险条目**（M2 新增了 R23–R26，
M1 新增了 R19/R21/R22/R27）。M3 把自己的限制写在任务底稿的「明确未证明 / 依赖登记」小节里，
而不是登记表里。签收时这一点值得注意：**底稿里的限制不会像风险条目那样被后续阶段例行读到**，
下列四条依赖登记目前只存在于 `M3-02-pipeline.md` §8 与 `M3-03-runtime.md` §9：

**下表是这些限制的完整清单——每一条都只活在草稿里，`docs/08-risk-register.md` 中没有对应条目，
因而对「只读登记表」的后续阶段实际不可见：**

| 只存在于草稿中的限制 | 出处 | 后续阶段可能踩到的形态 |
|---|---|---|
| 泄漏 / 用后释放**未做**（进程无法观测自身泄漏，需 ASan/valgrind + shell 层比对） | `M3-03-runtime.md` §8 | M4/M5 读到「commit 有幂等与所有权断言」，据此以为内存安全已被覆盖 |
| 14 个 `ignore` 行的值正确性不覆盖；`RESERVED` 与 `DEFINED` **不能**由分配状态区分 | `M3-03-runtime.md` §3、§8 | 把 `NOT_COMPARABLE=28` 读成「已核对且相等」 |
| `NET-SNAN` 的强度分档：`release` 下是**弱检查**（未初始化内存碰巧是 NaN 才被抓）；`strict` 下进程**中止而非返回 finding**，调用方不应指望在 `errors` 里看到它 | `M3-03-runtime.md` §8 | 在 release 下跑一遍没红，就认为未初始化内存已被排除 |
| validate 家族的条件覆盖是**一次审计，不是常设控制**，作者预言「会和能力门当初一样退化」 | `M3-02-pipeline.md` §7 | 新增 validate 规则时不补反例，而套件仍然全绿 |
| `INV-EMPTY-DERIVED` 属「因能力上限不可达」，**有失效日期**：section 数一旦 > 1 就必须补规则 | `M3-02-pipeline.md` §8 | 放宽能力门时只改能力表，不回头补规则 |
| `INV-NTOTV-POSITIVE` 同类，注 `review 2026-12-31: fields widen` | `M3-03-runtime.md` §4 | 同上 |
| 本轮审查**未经外部模型交叉验证**（codex 以 `codex_models_manager` 超时失败，改用两个 Claude reviewer） | `M3-03-runtime.md` §8 | 把「双路审查」读成「跨实现交叉验证」 |
| Fortran 侧**无**自动化质量/安全门禁（CCG 对 `src/runtime` 扫描 0 文件） | `M3-03-runtime.md` §8、backlog M3-03a | 以为约 5000 行 Fortran 有 SAST 覆盖 |

四条**依赖登记**（同样只在草稿里）：

1. 支持的 section 数一旦超过 1，必须为「两个 section、元素全指向第一个」补规则
   （`INV-EMPTY-DERIVED` 今天不可达**只是因为**能力门恰好只允许一个 section——「这是意外，不是设计」）。
2. M4-01 折叠 commit 时必须把 ProblemState 那一半**折叠进同一次 staging**，不得新增第二个 writer。
3. restart 一旦被接纳，`runtime.cursor.lineload` 需要真实来源，其 manifest `check` 条目须停止空判。
4. 能力门放宽 section 数或场数时，D 类契约条目须逐条重新决定。

（M2 提出的 R23–R26 **四条至今全部 OPEN**，逐条核对见 `docs/m2/M2-acceptance-matrix.md`
「M2 提出的风险的当前状态」。M3 与其中的 R23 相关：`ignore` 分类的正确性同样是人工判定。）

## 复核过程中的旁证与阻碍（不属判据）

1. **底稿与 STATUS 里的桥接计数在 HEAD 上都不复现。** `M3-03-runtime.md` §6 记 `513/513`、
   `docs/STATUS.md` 第 26 行记 `581/581`（`L3b-bridge-report.md` §9.2 也记 581/581），HEAD 实测
   **`1131/1131`**；「六个记录数组全局」在 HEAD 上是**七个**。数字随 M4-01 扩充增长属正常，
   但**M3-03 自己的数字今天只能在它自己的提交上核对**。
2. **`docs/m3/evidence/M3-02-selftest.json` 冻结的 9 个源文件 sha256，有 3 个在 HEAD 已漂移**
   （`yl_problem_errors.f90`、`yl_problem_manifest.f90`、`yl_problem_profile.f90`）。
   计数（485/485、15/15、50/50）仍然复现，属巧合而非保证。**没有任何工具消费这个 json**
   （`grep -rn "M3-02-selftest.json" --include=*.py --include=*.sh --include=*.f90 .` 无命中），
   它是归档记录而不是门禁——引用它时必须说明这一点。
3. **`docs/tasks/` 下没有 M3-03 的任务文档**（只到 `M3-02.md`）。
4. **干净树上跑不了任何依赖 legacy 源码的门禁**：`legacy/yl/libiomp5md.dll` 被 `.gitignore`
   的 `*.dll` 排除、未入库，却列在 `legacy/source-manifest.json` 的 39 个文件里，于是新建
   worktree 上 `runtime-bridge` 与 `adapter` 都以
   `build.sh: legacy/source-manifest.json does not verify; refusing to build` 拒绝。
   本次是手工拷贝该文件后才继续的。已上报，本 subagent 不拥有 `legacy/**` 与 `.gitignore`。

## 负责人签收裁定（2026-09-10）

结论：**有条件接受**。条件为一项签字前补正（判据 9 的层次边界），**已完成**；
另三项残余覆盖问题**登记为债务、不阻塞签收**，其中判据 25 同步到现有 ASan 门禁事实。
上表任何一格的原文都未被改写，本节只追加裁定。

### 条件（判据 9）：写明层次边界——「未知字段拒绝」不属 M3 本层

**裁定：`docs/05` M3-02 验收列的「未知字段拒绝」这条要求，在 M3 这一层由类型系统承担，
其可失败的那一半属于 M4 的方言门。理由不是「做不到」，是「在这一层写不出来」。**

- **`problem_state_t` 是强类型 Fortran 派生类型。** 「未知字段」在这一层**不可表达**——
  没有一个入口能构造出一个带未知分量的 `problem_state_t`，因此也没有一条运行时检查
  可以拒绝它。**一条永远无法失败的检查不是控制，是装饰**（这与本项目对空阴性对照的
  判法一致：不能失败的断言不计为判据）。
- **deck 文本里的未知字段是真实的、可失败的**，它由 **M4 的方言门**承担：
  `CAP_STAGE_ADAPT` 能力表逐行反例，`yl_adapter_dialect_test` 对每行断言三件事
  ——该行触发、**只有该行触发**、对外判决统一为 `UNSUPPORTED_LEGACY_DIALECT`。
  两个 golden deck 上各 `337/337`。**这才是这条验收要求的落点。**
- **M5 的 authoring schema 承担第三种情形**：现代输入里的未知键，由
  `additionalProperties: false` 在 schema 层拒绝（`schemas/case.schema.json` 现已如此声明，
  但该文件是 bootstrap、尚无求解路径消费，**因此这一半今天仍未建立**，属 M5）。

**因此判据 9 的判决由「仅有断言」改为「不属本层——已写明落点」。** 它**不转为**
「独立证据支撑」：M3 层没有可失败的检查，就不该有一条判据声称它通过了。
论证已写入 `docs/m3/M3-02-pipeline.md` §8.1（原缺陷正是「这个论证没有人写下来」）。

**同时修正验收列本身**：`docs/05-execution-backlog.md` 的 M3-02 行不应再列这条要求，
它应出现在 M4 与 M5 的验收列。改动随本次提交。

### 判据 25（泄漏 / 用后释放）：同步到现有 ASan 门禁事实

上表记「**仅有断言（实为未建立）**」——那是 M3-03 交付时的实况，**保留原文不改**。
**现状已变**：M4-01 步 6 建了这道门禁，事实如下，**连同它的覆盖边界一起记**：

- **门禁存在**：`tools/build.sh` 新增 `asan` profile；`bash tools/build.sh runtime-bridge
  --profile asan` 在干净树上 **rc=0**、字符串 `LeakSanitizer` 出现 **0 次**、套件 1292/1292。
- **仪器确实会响**（否则「一片安静」什么都不说明）：**6 个阳性对照**，每个记录数组一处；
  M4-01 验收复核另做了**独立的第七处**（`element%egaus%djacb`，不在报告六处清单内）→
  `rc=6`、`3120 byte(s) leaked in 26 allocation(s)`，归因到两行。
- **覆盖边界，不得放宽**：分母是 `commit_release` 的 **21 个内层释放站点**
  （26 个站点 − 5 个容器级），**已被对照证明可检出的是其中 6 处**。
  其余 15 处**没有做过对照**——第七次对照说明 LSan 对未覆盖站点同样会响，
  但那是**仪器的普遍能力**，不等于那 15 处已被验证。
- **工具的构造性盲区**：LeakSanitizer **只报不可达块**——仍被活的模块变量引用的内存
  对它不算泄漏，无论持有它多么错误；「全局跨 commit 留着一个陈旧句柄」**按构造看不见**。
  另：`commit_legacy_globals` 今天无线程，故不存在被线程持有的泄漏被漏掉；
  **这一点一旦改变，该 profile 就不再充分**。
- **工具与出口条件的实质偏离已如实登记**：设计写的是 valgrind，本机装不了（无 valgrind、
  uid 非 root），改用 `ifx -fsanitize=address`。**第一次阳性对照一片安静**——
  Intel OpenMP 运行时**静默禁用** LeakSanitizer，`ASAN_OPTIONS=detect_leaks=1` 覆盖不了；
  现由 `tools/asan/omp_stub.c` + 顺序版 MKL 绕开。**「仪器可以在关着的时候表现得像开着」
  这条必须随判据一起被读**，已收入 `docs/07-acceptance-and-release.md`。
- **MSan 与 ASan/LSan 互为反面、不是互相替代**：`sanitize` 查未初始化读取、永不查泄漏；
  `asan` 查泄漏、永不查未初始化读取。**两道门都要跑**，本次都跑且都绿。

**判决**：由「未建立」改为**「已建立，覆盖 21 处中的 6 处，边界如上」**。
**不改为无保留通过**——21 中的 15 处仍未被对照覆盖，这是债务，见下表。

### 登记为债务、不阻塞签收的三项

| 判据 | 残余 | 关闭路径 | 里程碑 |
|---|---|---|---|
| **判据 5**：初始输入与积分历史变量分离 | 必要条件已由规则 15 机器强制（阴性对照确认会响），但规则是**必要条件而非该性质本身**——一个在其检查点上恰好确定性的历史槽位仍能通过；M3-01 底稿仍未写下这条论证 | ①在 M3-01 底稿写明论证与规则 15 的作用边界；②若要覆盖残余，需要独立于 determinism 的判据（例如按 legacy 槽位**首次赋值位点**是否晚于检查点分类） | ①随材料域开工前；②残余可达性低，按需 |
| **判据 11**：validate 家族每条件反例 | 一次**已完成的审计**，不是常设控制；M3-02 §7 自己预言「会和能力门当初一样退化」。M3-03 已按该要求把规则声明进可遍历的表，**M3-02 自己没有回改** | 把 validate 规则也声明进可遍历的表，使「每条规则的每个条件都有反例」成为套件断言 | 材料域扩 validate 规则之前**必须**完成——否则新域的规则一落地就处在同一形态 |
| **判据 25** 的覆盖残余 | 21 个内层释放站点中 **15 处**未做阳性对照 | 逐站点删除释放 + assert-guard 对照，或一次性对每个记录数组的每个内层指针各做一处 | 不晚于 commit 结构再次变动时 |

**这三项是「覆盖面不足」，不是「结论可疑」**——已有的每一条对照都真实有效；
缺的是把同形保证铺到其余站点/规则上。

### 判据 27（复核与负责人签收）

**视为已完成**，与 M2 判据 23 同理：负责人非本项目任何代码的实现人，
其逐条阅读证据**就是**该判据要的那个复核。上表「无独立于实现人的复核人」
在本次签收中不成立。

### 「只活在草稿里的限制」这一节的处置

上表列出 8 条限制 + 4 条依赖登记，**只存在于任务底稿、不在 `docs/08-risk-register.md`**，
因而对「只读登记表」的后续阶段实际不可见。**裁定：本次签收不逐条搬进登记表**——
搬进去会让登记表变成底稿的副本，而**同一事实记在两处、只订正一处**正是本项目的复发缺陷
（`stab_matde` 即是）。**改为**：本矩阵本身即是它们的可见入口，
`docs/STATUS.md` 的 M3 行指向本矩阵；其中**两条已在别处获得机械落点**——
判据 25（ASan 门禁）与判据 5（规则 15 + `problem-types` 自检门），不再只是散文。

### 签收口径（沿用 M0）

本次签收**明确不确立** `docs/07-acceptance-and-release.md` SECTION 02 所列的任何能力。
上文「明确不能据此声称的事」十条**全部继续有效**，逐条不因签收而放宽——
**尤其是「不能声称 modern 输入路径可用」**：authoring schema 仍是 bootstrap，
静力域的五件套第 4 段尚未闭合（ADR-0008 第 2 条）。
本签收**不把「结构成立」或「人工判断」扩大表述为「已被独立验证」**：
判据 5、11 的残余与判据 25 的 15 处未覆盖站点，均以债务形式如实登记。

## 签字页

- 复核人：**Huijun（负责人）**
- 日期：**2026-09-10**
- 结论：**有条件接受**
- 条件：判据 9——在矩阵中写明层次边界：`problem_state_t` 强类型层无法表示未知字段，
  该要求不属 M3 本层；deck 文本未知字段由 M4 方言门承担。**已完成**
  （本节「条件」段 + `docs/m3/M3-02-pipeline.md` §8.1 + `docs/05-execution-backlog.md` 验收列修正）。
- 带着签的残余（不阻塞）：判据 5、判据 11、判据 25 的覆盖残余登记为债务，见上表。
- 依 ADR-0005，与 `docs/m2/M2-acceptance-matrix.md` 一并签收。
