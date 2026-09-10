# M2 验收判据 → 证据映射表

- 候选接受 ID：`M2-static2d-001`（任务底稿 `docs/m2/M2-01-checkpoints.md`、`M2-02-state-serializer.md`、`M2-03-state-evidence.md`）
- 编制日期：2026-09-09；编制人：Claude subagent（accept-m2m3），只读复核 + 在钉住的 `git worktree` 上重跑门禁
- 复核基线：`c0e6087`（`git worktree add /tmp/claude-1000/wt-accept-m2m3 c0e6087`）。共享工作树当时正被 dev-fold2 修改 `src/runtime/**`、`src/problem/**`，本文件的全部数字取自钉住的树，不取自共享树
- 本文件本身不是签收；签字页留空，由负责人填写
- 依 ADR-0005，M2 与 M3 一并签收；本文件只覆盖 M2，M3 见 `docs/m3/M3-acceptance-matrix.md`

## 一句话结论

**23 项判据中 17 项有可独立重现的证据，本次全部重跑并逐条核对；6 项仍属断言。**
其中三项是本次复核新发现、而不是文档自曝的：
**（1）`docs/m2/M2-01-checkpoints.md` §1 守卫表把 `stab_matde` 记为 0 并据此断言
`stab_initialize` 每步都调用——两例 deck 实为 99999，该分支从不执行，映射表已于 M4-01
期间订正（`0646de3`、`a8d4646`）而 M2-01 底稿没有；**这是孤例**，同表另外 18 个可核对的
守卫值本次全部交叉证实无误；
（2）M2-03 记录的两个 S01 指纹（`547e53a8fc6c` / `7c2edf39a342`）在 HEAD 上不再复现
（现为 `95f9ed237500` / `42f345980448`），且冻结基线的 40 个文件与新鲜运行**逐字节全不相同**；
（3）造成（2）的是每个 json 里的 `map_sha256` провenance 头——把它剔除后，三个检查点的
全部字段值与冻结基线**逐值完全相同**。**

**（2）（3）必须按下面这个形状读，不能读成「证据失效」：判据的措辞失效 ≠ 证据失效。**
M2-03 若把判据写成「新运行逐字节复现冻结快照」，**该措辞今日已不成立**（一个溯源键所致，
字段值全同）；但**没有任何门禁依赖过该措辞**。核对 `cases/golden/*/reference/state` 的全部
消费者（`grep -rln` 命中八个文件，其中 `tools/build.sh`、`src/adapter/yl_adapter_harvest.f90`、
`src/runtime/yl_runtime_bridge_test.f90`、`src/runtime/yl_runtime_selftest.f90` 只是注释提及，
后者还明确写着「never reads frozen.json」），真正读它的四处**全部比较字段值，没有一处比较
字节**：`yl_state_probe.py run`（比较器）、`yl_adapter_fidelity.f90`（L3-a，95/98）、
`yl_adapter_bridge_test.f90`（L3-b，`MATCH=64 MISMATCH=0`）、`yl_map_selfcheck.py`（映射表
散文 vs 基线标量）。**这几处依赖冻结基线的证据全部完好，且都是对这份基线测出来的**——
尤其 L3-b 的 `MATCH=64 MISMATCH=0` 不受本条影响。

`yl_state_probe.py verify`（`PASS files=40`）同样**不是**缺陷：它的实现是 `hash_tree(dest)`
对 `frozen.json` 的 `files` 逐条比对（`tools/yl_state_probe.py:626-646`），即**防篡改检查**
——回答「这棵冻结树还是当初那棵吗」。它从不读取新鲜运行，也从未声称过「新运行能否复现」。
两者是不同属性。

**残留风险**：若 dump 的**实质**发生漂移，L3-b 会红（它比值），因此这一面是被覆盖的；
但「新运行 vs 冻结基线」的**字节比对不存在、也从未存在**——谁需要这个属性，就得新建它。

另有一条与 M2 无关但阻断 M2 证据重放的事实：`legacy/yl/libiomp5md.dll` 被 `.gitignore`
的 `*.dll` 排除、未入库，却列在 `legacy/source-manifest.json` 里，因此**任何干净克隆或
新建 worktree 上 `tools/build.sh` 都会以 `source-manifest.json does not verify` 拒绝构建**。
本次是手工把该文件拷进 worktree 才跑通的。

## 验收判据 → 证据映射表

判据引自 `docs/07-acceptance-and-release.md` M2 行「多检查点状态及字段映射、确定性、
比较器反例、扰动检出」，并入 `docs/02-migration-plan.md` §M2 的三条出口条件与
`docs/05-execution-backlog.md` 中 M2-01/02/03 的验收列逐条展开。

| # | 判据 | 支撑证据（路径 + 具体字段/数字） | 复核命令 | 结论 |
|---|---|---|---|---|
| 1 | 多检查点：四个检查点已登记，id/顺序/词表受检，`covered=false` 才允许零字段 | `docs/m2/state-field-map.toml` `[[checkpoint]]`：`model_ready`(1)、`phase_ready(1)`(2)、`increment_ready(1,1)`(3)、`restart_ready`(4，`covered=false`)；规则 2 要求 `covered=true` 必须有 site/anchor/after/first_consumer/snapshot_files 且至少一个字段 | `python3 tools/yl_state_map.py check` → `PASS: 269 fields (190 emitted: 162/11/17), 4 checkpoints (3 covered), readers covered 40/40, skip-class 114`（已跑）；反例存在：`--selftest` 的 `zero-field covered checkpoint` 用例得到 `checkpoint restart_ready: covered=true but has no fields`（已跑，97/97） | 独立证据支撑 |
| 2 | 锚点身份由语句内容哈希锚定，行号漂移不使其失效 | 规则 3：`anchor` 12 位哈希必须等于 `anchor_hash(full_statement(site 行))`，漂移即报 "source changed?"。M1-02 包装 reader 使 `Fem.f90` 行号下移，`site` 已随之更新为 1909/3603/3657，哈希未变 | 同上 `check` PASS（本次在 M1-04/R27 又一次改动 `legacy/yl` **之后**仍 PASS，说明重定位流程被执行过） | 独立证据支撑 |
| 3 | 锚点与首个消费者之间没有对该消费者的调用（例程内） | 规则 15：从锚点所在例程起点到锚点行之间不得出现 `call <first_consumer>`；`docs/m2/M2-01-checkpoints.md` §10 写明作用域限于锚点所在例程 | 同上 `check` PASS；`tools/yl_state_map.py` 头部规则 15 原文（已读） | 独立证据支撑（仅例程内，见判据 4） |
| 4 | 锚点位于「最后一个已执行 reader 之后、第一个消费者之前」——**跨例程**的那一半 | `M2-01-checkpoints.md` §2 的调用序表（`Fem.f90:117/191/1682/1873/1896/1899/1909/1939` 等）是人工逐条核对的叙述；§10 明确「跨例程的先后关系由 §2 的调用序表人工保证」 | 无机器判据。`check` 只在锚点所在例程内扫描 | **仅有断言** — 「`model_ready` 之前没有别的模型级 reader 了」这句话，工具不校验；要升级需把 §2 的调用序做成可机器校验的形式（例如用 M1 注册表的 `executed_by` + 站点行号推出锚点前后的 reader 集合，并断言锚点前的集合等于 §2 表） |
| 5 | 锚点有效性所依赖的守卫值表（`M2-01-checkpoints.md` §1，17 行）在两例 deck 上成立 | §1 逐行给出守卫、值、来源与所决定的分支 | 本次用 M2-02 自己的 dump 交叉核对（等价地可读冻结基线，值相同）。**19 个守卫量可从快照直接读出，其中 18 个与 §1 一致**：`model_ready` 的 `block_stab/bparameter/ebody/nbackf/ninit/nlayer/nlinks/ntrans/state_change/adina/relis/restart` 全为 0、`uinitial=[0]`、`nblks=runblks=1`；`phase_ready(1)` 的 `increments=1`；`increment_ready(1,1)` 的 `step_increment=1`、`qstatic=0`。**唯一不一致的是 `stab_matde`：实测 99999，§1 记为 0。** 其余守卫（`type_nl`、`type_problem`/`type_solver`、`ngaps`、`nrcsteel`、`cwater`、`tfixvar`/`nextr`）不在导出面上，本次未经快照证实 | **仅有断言，且其中一行已被证伪** — §1 写「`stab_matde` = 0 → `:3658 iblks>=stab_matde` 为**真**：每步调 `stab_initialize`（清 `result_zero`、`gpvar0/gpvar`）」。映射表已在 M4-01 集成时订正（`state-field-map.toml:1886`；对应提交 `0646de3`、`a8d4646`）：99999 是禁用哨兵，`stab_initialize` **从不运行**，「旧注归给它的副作用另有原因」；**M2-01 底稿未跟着改**。**限定：这是孤例，不是系统性问题**——可核对的另外 18 个守卫值全部无误。不影响三个锚点的位置（`:3658` 在全部锚点之后），但它是锚点论证所引用的事实之一，且「`result_zero`/`gpvar0`/`gpvar` 在 `model_ready` 处为零**是谁做的**」目前没有答案 |
| 6 | 每个字段登记来源、消费者、shape、单位、所有权、比较规则 | 269 个 `[[field]]`，规则 6（source 必须是注册表里已执行、非 reached_only 的 reader，或可解析的 `derived:<rule>`）、9（consumers 非空且能 grep 到子程序）、10（shape 符号已声明、dtype/unit/owner/determinism 在词表内）、11（owner 匹配 ADR-0003 正则）、12（compare 规则合法） | `check` PASS（269 字段）；`--selftest` 97/97 里每条规则各有一个坏样例（如 `field mesh.nodes.xyz: dtype 'float' not in vocabulary`、`owner 'ProblemState.nodes' not in vocabulary`、`abs_tol requires basis`）（已跑） | 独立证据支撑 |
| 7 | 反向覆盖：每个已执行、非 skip 类的 reader 至少被一个字段引用 | 规则 7 | `check` → `readers covered 40/40, skip-class 114`（已跑）。**注意 `docs/STATUS.md` 第 21 行仍写「39/39 非 skip reader」「skip-class 110」**——R27 关闭时新增了 4 个 reader（`Load.f90:231`、`Output.f90:4301/4326/4351`、`Temper.f90:243`），分母已变，STATUS 的数字是陈旧的 | 独立证据支撑（范围受限：40/40 的**分母**来自 M1 命中集；R27 关闭后站点**集合**已升格为测量值，逐站**计数**仍是下界，见 `docs/08-risk-register.md` R27） |
| 8 | `legacy_symbol` 指向真实存在的 legacy 声明（不是自造的名字） | 规则 8：`<module>.<var>[%comp...]`，模块要找得到、变量要在 `module`…`contains` 之间（或例程内）声明，`%comp` 链逐级走真实类型定义 | `check` PASS；`--selftest` 有 `legacy var not declared: field mesh.nodes.xyz: 'stiff_u' not declared in module global_var` 反例（已跑） | 独立证据支撑 |
| 9 | 确定性：指针、未初始化填充、非确定顺序不得进入摘要 | 规则 18a：`compare.rule ≠ ignore` 的行不得有 `determinism = uninitialized|pointer`；18b/c：`emit="none"` 只允许在 `ignore` 行、`ignore` 行必须 `emit="none"`；规则 12 要求非确定字段用 ignore 或 hash（`order_dependent` 给了 `sorted_by` 才可 exact） | `check` PASS；269 登记中 79 行 `ignore`、190 行导出（已跑，与 M2-02 §5 记载一致） | 独立证据支撑（机制层） |
| 10 | 确定性**标签**本身分类正确（哪些分量确实未初始化 / 是未关联指针） | `M2-01-checkpoints.md` §6 的清单：`delitfi/deltafi`（`Fem.f90:246` 只分配）、`rvector`（`Solver.f90:7237`）、`element%field(1)%tload/eload/rload`、`prescrib%ifixvar0`（`Prescrib.f90:274` 拷贝一个从未赋值的局部量）等，以及未关联指针清单 | 无机器判据：工具只检查「标了 uninitialized 就必须 ignore」，不检查「标 uninitialized 的确实未初始化」，也不检查「没标的确实已初始化」 | **仅有断言** — 这是 R23 的核心，处置写的是「逐分量登记 determinism」，而登记的正确性来自人工阅读 legacy。要升级为独立证据，最直接的路径是在 `strict` profile（`-init=snan,arrays -fpe0`）下导出并断言：所有被标 `uninitialized` 的分量确实触发信号 NaN，所有未标的确实不触发 |
| 11 | 序列化器是映射表的生成物，不可手工漂移 | `src/state/yl_state_dump.f90` 头部「生成文件，请勿手改」；`tools/yl_state_map.py gen-fortran` 产出；`--selftest` 含 `gen-fortran deterministic + no timestamp`、`<= 132 cols, ASCII, one guard statement per parent` | `python3 tools/yl_state_map.py --selftest` → 97/97（已跑，含上述两条） | 独立证据支撑 |
| 12 | 比较器反例：缺字段、截断、NaN、错 ID、错 shape、错检查点、错 dtype、陈旧摘要——九类全部拒绝并定位到对象与字段 | `tools/yl_state_diff.py` 内建九类（`deleted_field`/`wrong_shape`/`nonfinite`/`duplicate_id`/`wrong_dtype`/`wrong_checkpoint`/`stale_digest`/…），每类断言退出码与首行报文；`docs/m2/evidence/S02-negatives.json` 归档了同样九类在**真实快照**上的首行 | `python3 tools/yl_state_diff.py --selftest` → `PASS selftest s02=9 guards=4 checks=16`（已跑）。注意常设自检跑在合成 fixture（`build_fixture()`）上；「在真实快照上命中」是 2026-09-07 的一次性归档，不是每次可重放的门禁 | 独立证据支撑（常设：fixture 层；真实快照层为一次性归档） |
| 13 | 比较器护栏：ragged 长度变化、跨集合重组（扁平序列不变）、reference 侧缺检查点、两侧都缺字段 | Round 1 审查发现的 fail-open，已修；四类固化为自检 | 同上 `--selftest` → `guards=4`（已跑） | 独立证据支撑 |
| 14 | 摘要生成不改变求解结果（`docs/02` 出口条件三） | M2-02 §5 记 dump 开/关 × 三 profile × 两例 6/6 | 本次重跑：`yl_run.py --case-id static_2d.cooks_membrane`（无 dump）与同一命令加 `--dump-state`，两次 `work/1.flavia.res` **`cmp` 逐字节相同**；且 dump-on 的结果对 M0 冻结参考 `python3 tools/yl_compare.py cases/golden/static_2d/cooks_membrane/reference/results.json <run>/results.json` → `PASS DISPLACEMENT: n=578 max|d|=0.000e+00; STRESS: n=1156 max|d|=0.000e+00`（已跑） | 独立证据支撑 |
| 15 | 相同输入三次运行得到相同摘要（`docs/02` 出口条件一） | M2-03 §5 S01 两例各 3 次 | 本次重跑：`yl_state_probe.py repeat --case static_2d.cooks_membrane` → `PASS runs=3 fingerprint=95f9ed237500 pairs=3`；`--case static_2d.lame_cylinder` → `PASS runs=3 fingerprint=42f345980448 pairs=3`（已跑，3 对两两比较均 `PASS exit=0 compared=190`） | 独立证据支撑 |
| 16 | M2-03 记录的具体指纹值可复现 | `M2-03-state-evidence.md` §4：cooks `547e53a8fc6c…`、lame `7c2edf39a342…`（release 二进制 `445090142419dcb0…`） | 本次实测为 `95f9ed237500` / `42f345980448`（release 二进制重建后 sha256 `24d770c9a7db7ffe…`）。**记录值不复现** | **仅有断言（且已失效）** — 根因见判据 17：指纹随 `state-field-map.toml` 的 sha256 变化，而映射表自 M2-03 之后被 M3/M4 多次修改。R26 只登记了「跨 profile 不可比」，**没有登记「跨映射表版本不可比」**，而后者才是本次踩到的那一个 |
| 17 | 冻结基线（`cases/golden/*/reference/state/`，每例 40 文件）在当前源码树上仍然成立 | `reference/frozen.json` 逐文件 sha256 + provenance；`yl_state_probe.py verify` 每次 `run` 前自动执行 | 本次：`verify --case static_2d.cooks_membrane` / `static_2d.lame_cylinder` 均 `PASS files=40`。另把冻结树与一次新鲜运行逐文件比较：40 个文件**逐字节全不相同**；再逐 json 比较，剔除 `map_sha256` 一个键之后**三个检查点的全部字段值完全相同**（差异只在 `map_sha256`、由它派生的四个 `.sha256` 摘要、以及 `fingerprint.json` 的 `map`/`fingerprint`/`checkpoints`） | 独立证据支撑（**值层**：基线仍然逐值可复现，本次实测确认，判据 18 的 S03 四条探针 `mis=1` 是它的二次证明）。**字节层的那句措辞今日不成立**——但它**从未被任何门禁依赖**：读这份基线的四处（`yl_state_probe.py run`、L3-a、L3-b、`yl_map_selfcheck.py`）**全部比较值**。`verify` 是**防篡改**检查（`hash_tree(dest)` 对 `frozen.json`，`tools/yl_state_probe.py:626-646`），它没有、也从未声称有「新运行能否复现」这个属性 |
| 18 | 人为改一个材料 / 约束 / 荷载，diff 指出准确位置，且恰好一条主 MISMATCH（`docs/02` 出口条件二） | `cases/probes/state/` 四条探针；`docs/m2/evidence/S03-report.json`、`S03-diffs/` | 本次重跑（release 二进制、当前树）：`yl_state_probe.py run` → 4/4 PASS，逐条 `exit=1 mis=1`：`S03_E_cooks`→`materials.E`、`S03_E_lame`→`materials.E`、`S03_BC_cooks`→`steps0.boundary.value`、`S03_G_cooks`→`steps0.load.gravity.magnitude`（已跑）。**这同时二次证明了判据 17 的值层结论**：若基线值有任何漂移，`mis` 不会恰好等于 1 | 独立证据支撑 |
| 19 | S03 的反例不是空转：目标钉在检查点处**可观测**的量上（R24） | `M2-01-checkpoints.md` §7：`fixed` 与 `tcurves%dfact` 在 `increment_ready(1,1)` 仍为零（`Fem.f90:3666-3667` 才赋值），所以扰动目标钉在 `props%…%e` / `prescrib%vdofix,nodfix` / `gravy,factg,tcurvegravity`；`M2-03` §3 把它编码成 `S03_BC_cooks` 的 `forbid_fields`，并禁止「空转条目」（加载期拒绝 `ignore`/`emit=none`/不在基线中的字段） | 上述 S03 重跑 4/4 PASS 即包含 `forbid_fields` 断言（`yl_state_probe.py --selftest` 47/47 另含「空扰动必须判失败」「白名单越界在加载期失败」，已跑） | 独立证据支撑 |
| 20 | 跨 profile 的状态等价由比较器（而非指纹）判定 | M2-02 §3 与 R26 | 本次重跑：新建 `debug` 构建，同一算例 dump-on 后 `python3 tools/yl_state_diff.py <release>/state <debug>/state` → `PASS compared=190 skipped=79`；两者指纹分别为 `95f9ed237500` 与 `48a53c3da92e`，**不同**（R26 的现象本次复现） | 独立证据支撑 |
| 21 | `restart_ready` 零字段是**范围边界**而非缺口（ADR-0005 的核心论断） | 映射表 `restart_ready`：`covered=false`，`reason = "restart=0 on both golden cases; resta_read_write(1) (Fem.f90:283) and the .rtt/.stf units are not on the static_2d path…"`；`check` 规则 2 只允许 `covered=false` 的检查点零字段（判据 1 已给反例）。ADR-0005 另称「能力表有 `F1/restart` 方言规则会拒绝任何 restart≠0 的 deck」——**核实成立**：规则在 `src/adapter/yl_adapter_fem90.f90:199` `reject_nonzero(errors, restart, 'F1', 'restart', loc)`；反例在 `src/adapter/yl_adapter_dialect_test.f90:82` `run_case('F1','restart','inp',2,'1  0  0  0  0  0','W')`，且 `run_case` 同时断言「该行触发」「**只有**该行触发」「对外判决统一」 | `bash tools/build.sh adapter` → 方言套件在**两个** golden deck 上各 `317/317 PASS`，含 `-- counter-examples, one per CAP_STAGE_ADAPT row` 与 `-- coverage`（已跑） | 独立证据支撑（**范围受限，且有时间性**：这条门禁属 **M4-01**，在 M2 与 M3 交付时并不存在；M2 自身对 restart 只有映射表里的一行散文理由，M3-02 §4 更明确写着「gate 的 restart 项……构造不出反例」故**不实现**。ADR-0005 的论断在**今天**成立，但它不是 M2 阶段自带的证据） |
| 22 | 扰动可检出性推广到其余字段 | M2-03 §7 自述：「扰动只覆盖材料 E、一个约束值、重力大小三类；其余字段的可检出性由 S02 的结构护栏与 S03 的机制推广，未逐字段验证」 | 无 | **仅有断言** — 这是文档自曝。190 个导出字段中，有单变量扰动实证的是 3 个字段（4 条探针）。升级路径：对 `[[perturbation]]` 扩表，或至少对每个 `compare.rule = exact` 的**字段族**各取一条探针 |
| 23 | 复核与负责人签收 | 无。`docs/STATUS.md` 第 21 行 M2-01 仍为 **IN_REVIEW**；`docs/in-review-audit-2026-09-08.md` §四第 4 条列出的三项前置整改，本次核对：①「统一任务文档头部状态与 STATUS」——**未做**，`docs/tasks/M2-01.md:3` 仍写「状态：DONE（待提交）」；②「锚点改为只引用 anchor 哈希」——**未做**，STATUS 与底稿仍引行号（但已更新为 1909/3603/3657，与映射表一致）；③「selftest 计数以复核当下重跑为准」——**未做**，`docs/tasks/M2-01.md:26` 仍记 `48/48`，实测 `97/97` | `grep -n "状态" docs/tasks/M2-01.md`；`python3 tools/yl_state_map.py --selftest`（均已跑） | **仅有断言**——严格说是「尚无」：与 M0 判据 18 同一形态，单人项目里没有独立于实现人的复核人。另外，M2-01 之所以是 IN_REVIEW，审计给出的原因是「无独立复核人 + 三处文档漂移」；**三处漂移到今天仍有两处未消**，第三处（行号）已订正 |

## 明确不能据此声称的事

按 `docs/07-acceptance-and-release.md` M2 行「不能据此声称：所有物理能力已理解」，具体化：

- **不能声称 79 个 `ignore` 字段的值是对的。** 它们从未被比较过（M2-03 §7 自述）。`ignore`
  的理由分三类（未初始化、未关联指针、本路径未定义），理由本身是人工判定（判据 10）。
- **不能声称 `restart` 路径已被观测。** `restart_ready` 零字段；`.rtt/.stf` 单元、
  `resta_read_write` 从未执行过一次。今天由 `F1/restart` 拒绝的 deck，其状态**没有**基线。
- **不能声称快照能证明外推行为等价（R25）。** `.pre` 集合头的 `nextr` 是 `prescrib_set` 的
  局部量、无任何持久留存，两例 `nextr=0`，该分支不执行。
- **不能声称指纹是跨构建或跨版本的等价判据（R26 + 判据 16/17）。** 指纹既随构建 profile 变
  （R26 已登记），也随 `state-field-map.toml` 的 sha256 变（**未登记**）。跨构建/跨版本的等价
  只能由 `yl_state_diff.py` 判定。
- **不能声称存在「新运行逐字节复现冻结基线」这个属性。** 它不存在，也从未存在：四个消费者
  全部比较字段值。反过来也**不能**因此声称依赖冻结基线的证据有问题——L3-a 的 95/98、
  L3-b 的 `MATCH=64 MISMATCH=0` 都是对这份基线测出来的，且比的是值，不受影响。
- **不能声称三个锚点覆盖了「YL 第一次组装前消费的全部状态」。** 覆盖的分母是 M1 的命中集；
  R27 关闭后站点集合是测量值，但**逐站计数仍是下界**（`docs/08-risk-register.md` R27）。
- **不能声称字段映射对 `nblks>1` 成立。** `M2-01-checkpoints.md` §8 写明：`nblks>1` 时
  `.pre/.loa/.tem` 每块执行一次，`model_ready` 应变成每块一个。两例 `nblks=1`。
- **不能声称两例的物理正确。** 沿用 M0：两例是重力回归例（R08），不是物理验证。
- **不能声称本阶段已完成负责人签收**（判据 23）。

## 仍属断言而非独立证据的项

| 判据 | 当前状态 | 升级为独立证据所需 |
|---|---|---|
| 判据 4：锚点跨例程的「最后 reader 之后」 | `M2-01-checkpoints.md` §2 的人工调用序表；`check` 只在锚点所在例程内扫描 | 用 M1 注册表的站点行号 + `executed_by` 机械推出「锚点之前已执行的 reader 集合」，断言它等于 §2 表所列，并在 `check` 里固化 |
| 判据 5：§1 守卫值表 | 19 个可从快照读出的守卫量中 18 个交叉证实无误；**`stab_matde` 一行是错的**（记 0，实为 99999），且据此推出的「`stab_initialize` 每步运行、负责清 `result_zero`/`gpvar`」也是错的。**孤例，非系统性** | ①订正 `M2-01-checkpoints.md` §1 该行与 §5/§6 中依赖它的推论（本 subagent 不拥有该文件，已上报）；②回答映射表 `:1886` 留下的空缺——`result_zero` 与 `gpvar0/gpvar` 在 `model_ready` 处为零，**是谁做的**；③把守卫表变成机器判据：每个守卫在映射表里都已是 `compare="exact"` 的字段，可让 `check` 断言 §1 的「本路径值」等于冻结基线中该字段的值 |
| 判据 10：确定性标签的分类正确性 | 人工阅读 legacy 得到的清单（§6），工具只校验「标了就必须 ignore」 | 在 `strict`（`-init=snan,arrays -fpe0`）下导出，断言被标 `uninitialized` 的分量确实是信号 NaN、未标的确实不是 |
| 判据 16：M2-03 记录的指纹值 | 不复现（`547e53a8fc6c`→`95f9ed237500`、`7c2edf39a342`→`42f345980448`） | 二选一：①把 `map_sha256` 移出被摘要的字节（即指纹只覆盖字段值），使指纹成为**内容**判据而非**内容+版本**判据；②接受现状，但把「指纹随映射表版本变化」补进 R26，并在 M2-03 记录指纹时同时记录当时的 map sha256，使读者知道它何时该被重算 |
| 判据 17：冻结基线的**字节级**可复现性 | 40/40 文件与新鲜运行逐字节不同，值逐条相同。**这不是一处回归**：字节级同一性从未被任何门禁强制过，`verify` 是防篡改检查而非复现检查，三处实质消费者比的都是值且全部完好 | 只有在**确实需要**这个属性时才新建：给 `yl_state_probe.py` 增一条 `reverify`——跑一次新鲜 dump-on 运行，用**比较器**（不是 sha256）对冻结基线判定，PASS 才算基线仍然成立。当前这个保证由 S03 四条探针顺带提供（各恰好 1 条 MISMATCH，其余 189 个比较项全 PASS），可以接受，但它是顺带的、不是指名的 |
| 判据 22：扰动可检出性的推广 | 3 个字段 / 4 条探针 | 扩 `[[perturbation]]` 表，或对每个 exact 字段族各取一条探针 |
| 判据 23：复核与负责人签收 | 无独立复核人；M2-01 的三条整改两条未做 | 与 M0 判据 18 相同的结构性缺口；三条整改属可立即消除的文档债 |

## M2 提出的风险的当前状态

`docs/08-risk-register.md` 开篇规则：「状态均为 OPEN，直到有关闭证据」。按此逐条核对：

| 风险 | 登记于 | 是否有关闭证据 | 结论 |
|---|---|---|---|
| R23（派生类型含未初始化分量与未关联指针） | M2-01 | 无「已关闭」标记；处置（逐分量登记 + 白名单序列化 + `associated()`）**已实施**，机制由规则 18a/b/c 守住 | **OPEN**（处置已落地，但分类正确性本身仍是判据 10 的断言） |
| R24（`fixed`/`dfact` 在 `increment_ready` 仍为零） | M2-01 | 无「已关闭」标记；处置**已实施且被编码为测试**（`S03_BC_cooks` 的 `forbid_fields` + `zero_in_reference`） | **OPEN**（实质已处置；这是四条里最接近可关闭的一条） |
| R25（`nextr` 无持久留存，快照无法证明外推等价） | M2-02 | 无关闭证据。两例 `nextr=0`，分支不执行 | **OPEN**（真实盲区，关闭需先补 reader capture） |
| R26（指纹跨 profile 不可比） | M2-02 | 无关闭证据；现象本次复现 | **OPEN**，且**描述过窄**：本次发现指纹同样随 `state-field-map.toml` 版本变化，风险条目未涵盖 |

四条**没有一条**被标记关闭。但**「都没有关闭标记」不等于「都被遗忘」**——这两件事必须分开读：
每一条都有与代码相符的、活的缓解文本，R24 甚至已被编码成测试；缺的是关闭证据行，而按登记表
自己的规则（「状态均为 OPEN，直到有关闭证据」），OPEN 就是 OPEN。R23/R24 的处置已落地；
R25/R26 是真实盲区。**一个由本阶段提出、至今 OPEN 的风险，与本阶段的签收相关**——签收 M2 时
应逐条决定是「随签收关闭并写明关闭证据」还是「明确带着它签」。

R23 的残余值得单独说，因为它是本项目反复出现的那个形状：
**门禁强制的是「标为 uninitialised ⇒ 必须 ignore」，从不强制「标得对不对」。**
分类本身是人读 legacy 的结果，属断言。换个说法——
**门禁核对的是声明之间的一致性，不是声明与现实的一致性。**

## 复核过程中的旁证与阻碍（不属判据，但影响可复现性）

1. **干净树上跑不了任何依赖 legacy 源码的门禁（复核当时；已由负责人修复）。**
   `legacy/yl/libiomp5md.dll` 未入库（`.gitignore:8` 的 `*.dll`）但列在
   `legacy/source-manifest.json` 的 39 个文件里，`tools/build.sh` 在构建前 fail-closed
   校验该 manifest，于是新建 worktree 上 `release` / `runtime-bridge` / `adapter` 三个目标
   全部以 `build.sh: legacy/source-manifest.json does not verify; refusing to build` 拒绝。
   本次复核是手工拷贝该文件后才继续的。**已于 `c429def` 修复**——取「让两个断言都为真」
   而非削弱其一：文件入库 + `.gitignore:15` 加 `!legacy/yl/*.dll` 例外，并有修复前 FAIL /
   修复后 PASS 的两个对照。**连带后果**：M0 签收里「构建与运行可重现（干净检出）」一行
   当时未经检验，已由负责人在 `0a92e81` 改为如实措辞——该条自 `c429def` 起成立。
2. 本次重跑用的 release 二进制 sha256 为 `24d770c9a7db7ffe…`，与冻结 provenance 记录的
   `445090142419dcb0…` 不同（其间 R27 关闭改动了 `legacy/yl` 四处包装）。**结果不受影响**：
   dump 值逐条相同、两例数值 `max|d|=0.000e+00`。

## 负责人签收裁定（2026-09-10）

结论：**有条件接受**。条件为三项签字前补正，**已全部完成**；另两项残余覆盖问题**登记为债务、
不阻塞本阶段签收**。逐项如下——上表任何一格的原文都未被改写，本节只追加裁定与新证据。

### 条件一（判据 4）：跨例程锚点顺序改由测量建立

**原状态：仅有断言。** §2 的调用序表是人工逐条核对的叙述；`yl_io_inventory.py check`
**只在锚点所在例程内扫描**，跨例程的那一半（「别的例程里没有模型级 reader 在锚点之后跑」）
没有任何机器判据。

**现状态：独立证据支撑。** 新增 `tools/yl_anchor_order.py`。它不去读源码推断调用序——
它**让进程回答**：对**全部 886 个 `read` 站点普查**（不只是已登记的 157 个）加三个锚点行
下断点，跑 trace 二进制，按 gdb 命中日志的**先后**分桶。三条断言：

- **A1**：每个已登记 reader 实际所在的桶必须等于它 `phase` 键声称的桶。这把手工维护的
  `phase` 从声明变成**派生事实**。
- **A2**（矩阵点名要的那条）：**`model_ready` 之前被抵达的每一个读语句，要么执行了，
  要么是已登记的 `reached_only` 站点并写明抑制它的那个内联条件。** 一个未登记、未执行的
  读若出现在锚点之前，就意味着快照声称「模型已装载完」而某个字段从未被读。
- **A3**：不得有注册表不知道的站点被抵达——否则 A2 校验的是一个它管不住的集合。
  （**普查全部读站点而非只普查已登记站点，正是为了让 A3 有可能失败**；只对已登记站点
  下断点的话，A3 永远为真且毫无信息。）

**实测**（`bash tools/build.sh trace`，两例）：
`ANCHOR-ORDER PASS: 157 registered readers, 2 case(s)`；每例 889 个站点 → 5044 个断点地址；
`model_ready` 之前唯一的未执行读恰好是那 3 个 `reached_only` 站点
（`Global.f90:722` `rmesh/=0` 假、`Global.f90:810` `nlayer==2` 假、`Prescrib.f90:218`
`type_abc=='MIF'` 假），每个都带 `condition_value`。证据：
`docs/m2/evidence/anchor-order/<case>/anchor-order.json` 与 `hits-ordered.log.gz`。

**三个阴性对照，预测先写、逐条命中**：

| 对照 | 预测 | 实测 |
|---|---|---|
| 把 `GLB.global_data.title#1` 的 phase 改标为 `increment_lazy(1,1)` | 恰好 1 条 A1，点名该 reader，其余沉默 | 恰好 1 条 A1，点名该 reader 与两个桶 |
| 把 `model_ready` 锚点移到 `Fem.f90:97` | 大批 startup reader 落错桶（约 147），且**不应**产生 A2/A3 | **147 条，全部 A1**，无 A2、无 A3 |
| 抹掉一个 `reached_only` 登记（读仍不执行） | 恰好 1 条 A2 点名该站点 | 恰好 1 条 A2，文字为「reached before model_ready but the registry records no execution and no reached_only condition」 |

**门禁位置**：`tools/build.sh` 的 `trace` profile 构建成功后自动运行（trace 二进制是唯一
能回答这个问题的构建，检查就放在它刚被产出的地方）。失败 `exit 6`。

**限度，写在这里以免被过读**：结论的分母是**这次运行抵达的站点**。注册表的 `not_on_path`
（54 组）本次运行根本不经过，本工具看不见它们——所以它能说的是「**运行抵达的一切都有着落**」，
**不是**「别处不存在 reader」。守卫为假的条件读是**关于这两个 deck 的**陈述，不是关于方言的。

### 条件二（判据 5）：`stab_matde` 订正 + 守卫表机械对账

**订正**：`M2-01-checkpoints.md` §1 的 `stab_matde` 行由 `0` 改为 **99999**，并新增 §1.1
说明这条错值**把结论也带反了**——`iblks>=stab_matde` 在本路径上**恒假**，`stab_initialize`
**一次都没跑**，99999 是禁用哨兵。映射表 2026-09-08 已订正，本表拖到今天才跟上，
**「同一事实记在两处、只订正了一处」已计入 `docs/04-quality-gates.md` 的复发缺陷表**。

**顺带答了矩阵留下的空缺**（「`result_zero`/`gpvar0`/`gpvar` 在 `model_ready` 处为零
**是谁做的**」，原文写「目前没有答案」）：

- `result_zero`：startup 分配即清零，`Fem.f90:219` 与 `:243-244`（§2 调用序表同一行）。
- `element%field(1)%gpvar0` / `gpvar`：`modf_element_lib`（`Fem.f90:193` 调用，仍在 startup）
  在分配点旁显式清零——`Fem.f90:11859-11860` 分配、`:11881-11882` 赋 0。

两者都与 `stab_initialize` 无关。**订正不移动任何锚点**：四个 `iblks>=stab_matde` 判断全在
三个锚点之后或在无关分支里；变的是「本路径上还有哪些代码在跑」这一事实本身。

**机械对账**：新增 `tools/yl_guard_check.py`。它把 §1 的表逐行解析出来，**经映射表自己的
`legacy_symbol` 键**解析到冻结基线的快照字段（而不是一张会腐烂的手写别名表），在两例上逐值比对。

实测 `GUARD-CHECK PASS: 23 confirmed, 0 mismatched, 5 not on the export face`
（28 个守卫值 × 2 例）。**订正之前**同一工具给出
`MISMATCH stab_matde ... declared 0, frozen 99999`（两例各一条）、退出码 1——
**它独立地、机械地抓到了矩阵人工发现的那一条**。阴性对照：任意腐蚀一个守卫的声明值 →
恰好 2 条 MISMATCH（两例）点名该守卫，其余 22 个不受影响。

**第三种判决是这条补正的重点**：`NOT_ON_FACE` —— 不在任何检查点导出面上、**本工具确认不了**的
守卫，**每次逐名打印**（现 5 个：`cwater`、`ngaps`、`nrcsteel`、`tfixvar`、`nextr`）。
在这里保持沉默读起来与「已确认」一模一样，**而那一行错值正是这样活下来的**。

**门禁位置**：与 `yl_map_selfcheck.py --positive-control` 并列，在 `runtime-bridge`
与通用构建两处；失败 `exit 4`。

### 条件三（判据 16 / 17）：验收口径修订为字段值级可复现

**裁定见 `docs/decisions/0006-state-baseline-is-value-level.md`（ADR-0006）。** 要点：

- **判据 17 的正式表述**改为「新鲜 dump-on 运行经 normalize 后**每一个字段值**与冻结基线一致，
  由**比较器**判定」。**不要求、也不追求**携带 `map_sha256` 的快照字节级同一。它由此从
  「独立证据支撑（值层）」升为**无保留的独立证据支撑**——口径与被测属性现在是同一件事。
- **判据 16 撤销**，不再计入判据总数。「M2-03 当时那两个指纹值今天仍复现」是**把版本号当成
  内容判据**。指纹保留其真实用途：同一二进制、同一映射表版本内的重复运行判据（S01）。
- **provenance hash 的可追溯性保留，且是这次修订的对价**：`map_sha256` 继续写进每个快照，
  含义随之写死——指纹不同回答的是「是不是同一张映射表、同一个二进制产生的」，
  **不是**「内容是否等价」；后者只由比较器回答。
- **被拒绝的方案**（记在 ADR 里）：把 `map_sha256` 移出摘要字节。那样判据 16 能复现，
  但会**丢掉溯源**——而正是那个键让本次能迅速定位根因。**用可追溯性换一个判据的字面成立，
  不划算。**
- **值级可复现由谁强制**：不新建门禁。每条 S03 探针都要求扰动运行相对冻结基线
  **恰好出现预测的那一个字段差异、其余全部 PASS**——「其余全部 PASS」就是值级可复现。
  **如实记录其限度：这个保证是顺带的，不是指名的**；指名形式（`probe reverify`）的路径已写好，
  本次不做，理由是收益重复而非无必要。

### 登记为债务、不阻塞签收的两项

| 判据 | 残余 | 关闭路径 | 里程碑 |
|---|---|---|---|
| **判据 10**：确定性标签的**分类**正确性 | 门禁强制的是「标了 uninitialized 就必须 ignore」，从不强制「标得对不对」。分类来自人读 legacy（R23 的核心） | 在 `strict`（`-init=snan,arrays -fpe0`）下导出，断言被标 `uninitialized` 的分量确实是信号 NaN、未标的确实不是 | 不晚于任何要以 determinism 标签作论据的验收 |
| **判据 22**：扰动可检出性的推广 | 190 个导出字段中，有单变量扰动实证的是 **3 个字段 / 4 条探针**；其余靠 S02 结构护栏与机制推广 | 扩 `[[perturbation]]` 表，或对每个 `compare.rule = exact` 的**字段族**各取一条探针 | M5 之前 |

**这两项是「覆盖面不足」，不是「结论可疑」**——两者必须分开读。已有的探针每一条都真实有效；
缺的是把同一形态的保证铺到其余字段族上。

### 判据 23（复核与负责人签收）

**视为已完成。** 负责人非本项目任何代码的实现人（编码由 Claude 与 subagent 完成），
因此负责人逐条阅读证据**就是**该判据要的那个复核，而不是它的替代品。
上表判据 23 记的「无独立于实现人的复核人」在**本次签收中不成立**——**但在
`docs/tasks/M2-01.md` 的两条文档漂移上仍然成立**（状态头与 selftest 计数），
那两条已随本次一并消除（见提交）。

### 签收口径（沿用 M0）

本次签收**明确不确立** `docs/07-acceptance-and-release.md` SECTION 02 所列的任何能力。
上文「不能据此声称」一节的九条**全部继续有效**，逐条不因签收而放宽。
本签收也**不把「结构成立」或「人工判断」扩大表述为「已被独立验证」**：
判据 10、22 仍是断言，本节以债务形式如实登记；判据 4、5 的升级是**新增了测量**，
不是把旧断言重新措辞。

## 签字页

- 复核人：**Huijun（负责人）**
- 日期：**2026-09-10**
- 结论：**有条件接受**
- 条件：
  1. 判据 4——用 M1 注册表机械证明跨例程锚点之前不存在未执行 reader。**已完成**
     （`tools/yl_anchor_order.py`，两例 PASS，三个阴性对照命中，接入 `build.sh trace`）。
  2. 判据 5——订正 `stab_matde=99999` 及由错值推出的结论，并把守卫表与冻结基线机械核对。
     **已完成**（`M2-01-checkpoints.md` §1/§1.1/§1.2 + `tools/yl_guard_check.py`，
     23 confirmed / 0 mismatched / 5 not on face，接入 `build.sh`）。
  3. 判据 16/17——不追求带 `map_sha256` 的字节级同一；口径修订为字段值级可复现，
     保留 provenance hash 的可追溯性。**已完成**（ADR-0006）。
- 带着签的残余（不阻塞）：判据 10、判据 22 登记为债务，见上表。
- 依 ADR-0005，与 `docs/m3/M3-acceptance-matrix.md` 一并签收。
