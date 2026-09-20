# 合并验收矩阵 · M7 Phase 4 / M8 / M10 / M11 / M9

编制日期：2026-09-20。范围：**证据归位 + 口径冻结**。

这份文件**不重新展开**五个域的研究，**不复制** M0–M5 那种逐条判据的重型验收工程。
它只做一件事：把五个「完成但未签收」的域各自**真正确立了什么**写死，
让「窄口径 ACCEPTED」这个词在每个域上有唯一解释。

每个域回答七问，一问一行，不合并、不省略：

1. 声称建立了什么能力
2. 明确**不**声称什么
3. 真实证据在哪（golden / 反例 / 门禁）
4. 最终结果是否严格等价
5. 目标能力**是否真实被触发**，而不只是输入链路通过
6. 证据是否依赖其他域**后来**补出的结果
7. 已知边界与 OPEN DEBT

**授权**：负责人（Huijun）于 2026-09-20 批准按本文件口径对五个域做**窄口径签收**，
并明确：R28（单人项目无独立复核人）继续作为已知结构性限制**记录在案、不阻塞签收**，
**不为此引入新的 reviewer 机制**。「独立性」一栏因此如实填写实际存在的独立要素，
不虚构不存在的第三方复核。

---

## 0. 本次签收所依据的新鲜证据（2026-09-20 实跑，非引用历史记录）

三道门禁在本 session 从当前工作树重新构建并运行（源码曾新于 2026-09-18 的二进制，故先重建）：

```
=== BUILD OK (release)          2026-09-20T02:47:29Z -> 02:50:12Z
MODERN PASS   九个 golden 算例全部 N1/N2 通过，N3 十九条反例全部按预期停机
FALLBACK PASS （作用域见 R34）
=== BUILD OK (adapter/release)  2026-09-20T02:52:01Z -> 02:54:13Z
  dialect 套件 394/394；coverage 自检 9/9
  on-path reader 181/187，covered by adapter marker 155，registered as not adapted 26
=== BUILD OK (runtime/release)  2026-09-20T02:54:14Z -> 02:54:23Z
  runtime self-test 100/100；yl_problem_check 58/58
  state-field-map 325 字段 / 190 emitted / readers 63/63
  reader inventory 187 readers，evidence 覆盖九个算例
  STEP-SCOPE PASS: per_analysis 29, per_block 5, per_block_refused 8
```

N2 逐例（`atol = rtol = 0`，全部 `mismatches=0`）：

| 算例 | 块 | 值 | max\|d\| | 属域 |
|---|---|---|---|---|
| `static_2d.cooks_membrane` | 2 | 1 734 | 0.000e+00 | M5（既有） |
| `static_2d.lame_cylinder` | 2 | 486 | 0.000e+00 | M5（既有） |
| `plasticity.mini_mc` | 3 | 210 | 0.000e+00 | M6.4（既有） |
| `plasticity.slope_srm` | 600 | 541 200 | 0.000e+00 | M6.5（既有） |
| `loads_2d.wall_reservoir` | 4 | 552 | 0.000e+00 | M7 P1–3（既有） |
| **`loads_2d.beam_point_load`** | 2 | 756 | 0.000e+00 | **M7 P4** |
| **`nonlinear_elastic.new_duncan_chang`** | 30 | 2 100 | 0.000e+00 | **M8** |
| **`solver_2d.benchmark_100x100`** | 2 | 61 206 | 0.000e+00 | **M10** |
| **`damage_2d.concrete_gravdam`** | 30 | 3 220 | 0.000e+00 | **M11** |
| **`elements_2d.rcbeam`** | 120 | 214 110 | 0.000e+00 | **M9** |

N4（能力是否真被触发）逐例：

```
plasticity.slope_srm                PLASTICSTRAIN non-zero: 18924
nonlinear_elastic.new_duncan_chang  DISPLACEMENT  non-zero: 440
solver_2d.benchmark_100x100         DISPLACEMENT  non-zero: 20200
elements_2d.rcbeam                  DISPLACEMENT  non-zero: 47490
elements_2d.rcbeam                  Yield non-zero values in [0.0, 1.0]: 5371
damage_2d.concrete_gravdam          （无 Yield 断言——见 M11 第 5 问）
```

**这十行是本次签收的全部数值依据。** 五个域各自的能力边界由下面五张表冻结。

---

## 1. M7 Phase 4 · 集中力

| # | |
|---|---|
| **1 声称** | authoring 契约的 `[[step.load]] type="concentrated"`（`nset` / `value` / `amplitude` 三字段）→ ProblemState `concentrated_t` → `commit_point_loads` → legacy `pload` 的**完整链路成立**，且集中力真实驱动位移场。同时确立一条**通用防线**：凡 legacy 只读一次、契约却写在 step 下的字段，必须按名拒绝跨步分歧（`commit_step_invariants`，29 个字段） |
| **2 不声称** | 不声称梁荷载、板荷载（`nbeamload`/`nplateload` 全语料 0 个算例，按 ADR-0008 §3 记为 legacy-only，**裁定待定**，见第 7 问）；不声称第 2 步可以声明不同的集中力（该形态被**按名拒绝**，不是被支持）；不声称第二种 legacy 写法（`corlist`，`Load.f90:305-311`）——仍 suspended；不声称节点号存在性由校验层检查（校验层从不打开网格文件） |
| **3 证据** | golden `cases/golden/loads_2d/beam_point_load`（源 deck `hstar_jobs/0413_164206_1c44582f`，126 节点 / 100 单元）；反例：N3 `steps that disagree about a per-analysis field` rc=3；门禁 `tools/yl_step_scope_check.py`（本次实跑 `per_analysis 29 / per_block 5 / per_block_refused 8`） |
| **4 严格等价** | **是**。2 块 / 756 值 / mismatches=0 / `max|d| = 0.000e+00`（2026-09-20 实测） |
| **5 真实触发** | **是，且是本项目里最干净的一次**。该 deck `gravy=0`、`factg=(0,0)`——体力真为零，位移场**完全**由集中力决定。丢掉集中力的结果不是「错」而是「恒等于零」，自洽的运行藏不住 |
| **6 依赖后补证据** | **否**。本域证据自足，不依赖任何后续域 |
| **7 边界 / OPEN DEBT** | 梁/板荷载的处置是一条**未裁定的范围决策**（自造 deck 取 legacy 作 oracle vs. 记为 legacy-only 等真实 deck），报告 §3 停在这里等裁定，本次签收**不替它裁定**；`factf`（`Load.f90:913` 的第二组方向系数）适配器按 legacy 默认写回，**未经反例确认**；`water` 的负号档与 `code_load/=0` 档属 legacy-only，不是 covered；R32（TOML 子集不接受多行数组）OPEN |

---

## 2. M8 · DUNCANCHANG（非线性弹性）

| # | |
|---|---|
| **1 声称** | 统一 `[[material]]` 对象在**第二类非线性材料参数体系**上仍然成立：13 个键（`bulk_modulus_law` 领头）进入同一个材料对象，`cohesion`/`friction_angle` 与 CLASSICALEP **共用拼写**，必填性是 (键, 模型) 这一对的性质（`model_requires` 三组走同一个 `group_requires`）；ProblemState 侧 `duncan_chang_t` 是 `plasticity_t` 的**兄弟块**——M6 写下的「下一个模型加一个兄弟块」第一次被兑现。本构计算**一行都没重写**，走 legacy 的 `tangceDC`→`EBMOD`→`ecmat` |
| **2 不声称** | 不声称 DUNCANCHANG 的另外三条记录（`k1/k2/nd/lamdaMax` 属 `type_problem=='F'`、`G/F/Vtf` 属 `EV`/`CR`、`phi_s/k_s` 属 `kind_wt>0`）——全部**按名拒绝**；不声称 `bulk_modulus_law` 除 `EB` 外任何取值；`phi_s`/`k_s` 由 commit **复现 legacy 自己的派生**（`Material.f90:533-537`），不是作者输入，也不是新数值 |
| **3 证据** | golden `cases/golden/nonlinear_elastic/new_duncan_chang`（30 块 / 2 100 值）；五条 authoring 反例（预期先写、五条全中）；两条 dialect 反例 `A-MAT/duncanchang-bulk-law`、`A-MAT/duncanchang-f-problem`，各自单独触发自己那一行（本次 dialect 套件 394/394） |
| **4 严格等价** | **是**。30 块 / 2 100 值 / mismatches=0 / `max|d| = 0.000e+00`（2026-09-20 实测） |
| **5 真实触发** | **是**。N4 `DISPLACEMENT non-zero: 440`，且该断言本轮才被修好——`must_be_nonzero` 过去拿 observable 的 `components` 去匹配**块名**，唯一用它的算例恰好块名=分量名，所以一直看着是对的；给 `DISPLACEMENT` 加断言时它匹配不到任何块、**什么也没断言而门禁全绿**。现在 observable 显式写 `block`，指向不存在的块直接失败 |
| **6 依赖后补证据** | **否**，但有**前置**依赖：该算例在未修补的 legacy 上 SIGSEGV（PD-1），参考是在打了 PD-1 一行补丁之后才冻结的 |
| **7 边界 / OPEN DEBT** | **独立性上的一处真实减弱**：`new_duncan_chang` 的冻结参考**不是**未改动 5414e73 快照产出的（快照 `rc=174`），oracle 是「本仓库 legacy + PD-1 一行」。PD-1 的惰性另有两条证据（全语料 1810 条 solid 记录 `kind_wt` 分布 `{0: 1810}`，被守卫分支永远走不到；重建后两道门禁全绿、既有算例 `max|d|=0`），但**「与未改动快照逐字节相同」这一条对本算例不存在**，必须如实带着。PD-1 **不计入** DUNCANCHANG 能力 |

---

## 3. M10 · PARDISO（第二个线性求解器）

| # | |
|---|---|
| **1 声称** | authoring 的求解器选择 → ProblemState → legacy PARDISO 路径 → 真实算例 → 严格回归**链路成立**。`mtype` / `ncpu` / `msglvl` 三字段迁移，`mtype` **按名白名单**只放行 `-2`。同时确立一条**通用规则并机械化**：**冻结参考包含执行环境**——`yl_run.pinned_env()` 是全仓库唯一定义，runner 施加、两个 checker 复用 |
| **2 不声称** | 不声称 `isdefault`（能力开关，按名拒绝，不做字段）；不声称 `mtype` 的 `2`/`11`/`13`——选错不会响，只会按错误方式分解，故未被真实算例证明的取值一律拒绝；**不声称任何性能结论**：`ncpu=4` 是照搬 deck，不是调优；不声称 PARDISO 本身可重复 |
| **3 证据** | golden `cases/golden/solver_2d/benchmark_100x100`（10 201 节点 / 10 000 单元，相对 `cooks_membrane` 的差值**只有求解器本身**）；三条 authoring 反例（预期先写、三条全中）；两条能力表反例（`G4 unsupported linear solver` 改指 `SSORPBCG`、`G4 unsupported pardiso matrix type`） |
| **4 严格等价** | **是**。2 块 / 61 206 值 / mismatches=0 / `max|d| = 0.000e+00`（2026-09-20 实测） |
| **5 真实触发** | **是**。N4 `DISPLACEMENT non-zero: 20200`；且该算例是第一个非 PROFILE 求解器算例，链路走的确实是 `MAIN_PARDISO` |
| **6 依赖后补证据** | **否**。反过来，本域**向前**改正了一条既有口径：两个 checker 此前从不钉线程环境，一直在拿「另一个环境跑出的结果」比「这个环境冻结的参考」。它一直看不见，是因为此前每个 golden 都是单线程 PROFILE；第一个 PARDISO 算例进门禁时立刻在 61 206 个值里失败 206 个 |
| **7 边界 / OPEN DEBT** | **必须成对读的一条**：deck 写 `ncpu=4`，桥接忠实写进 `iparm(3)`，而运行器把 MKL 钉在 1 线程——**两件事都成立**：携带 `ncpu` 是因为复现 deck 就得带上它，而参考是在钉住的环境下定义的。实测：不钉线程 3 次运行 3 个哈希，钉住 1 个且等于冻结参考 `f4f124fa38438663`。**PARDISO 不是无条件可重复的**。另：报告 §6 登记的既有缺口 OPEN——PROFILE 一侧 `.sol` 的读被守卫关掉后，`iafile/icond/ipdchk/ising` 无任何供给，而 deck 写的是 `ipdchk=1, ising=1`；静力 golden 仍逐位复现「是运气不是设计」。再另：本算例**没有**与 5414e73 快照的逐字节对照记录，oracle 是本仓库 release 构建 |

---

## 4. M11 · CONCRETE（损伤本构）

| # | |
|---|---|
| **1 声称** | 两半，**分别由两个算例支撑，必须分开说**：<br>**(a) 读取 / 映射 / 派发链路**——9 个输入 + 选择子 `crack_model` + 2 个派生（`bb`/`et0` 由桥接**逐字照抄** legacy 表达式含 `bb<0` 钳位，不等价改写），由 `damage_2d.concrete_gravdam` 证明（最小切片，适配器对它的**唯一**发现就是 `materials[2].model: CONCRETE`）。<br>**(b) 损伤演化路径真实成立**——由 `elements_2d.rcbeam` 证明，**这是后补证据，来自 M9**，见第 6 问与 §2 |
| **2 不声称** | **`damage_2d.concrete_gravdam` 这个 deck 不触发损伤**，本次签收不因 (b) 而改写这句话；不声称 `crack_model` 的 `2`（读第二条记录的分支，按名拒绝）与 `5`；不声称 `icr==2` 分支的 `at/bt/alfat/t1..t4/ft0/eft` 与受压侧 `ac/bc/...`——legacy 在本路径上也不写它们，桥接也不写、不下毒；不声称 3-D CONCRETE |
| **3 证据** | golden `cases/golden/damage_2d/concrete_gravdam`（30 块 / 3 220 值，源 deck `hstar_jobs/0406_210921_443f933d`，与快照二进制**逐字节相同** `5f3036c863225b2b`）；三条 authoring 反例（`crack_model=2`→exit 3、删 `compressive_strength`→exit 2、把 `crack_model` 写到弹性材料上→exit 2）；损伤侧证据见 §2 |
| **4 严格等价** | **是**。30 块 / 3 220 值 / mismatches=0 / `max|d| = 0.000e+00`（2026-09-20 实测） |
| **5 真实触发** | **在本域自己的算例上：否。** `concrete_gravdam` 的 `Yield` 460 个值里 291 个恰好 0、落在 (0,1) 的**0 个**、大于 1e9 的 169 个——**一个真实损伤值都没有**。根因是 PD-3：`Residu.f90:3656` 的卸载分支从不赋 `damage`，`:3696` 照写不误，`-O2` 下写进输出槽的是残留栈值（常常正好等于 `E`=3.170e+10）。原判据 5 **不成立**，且比全零更糟——是非零的垃圾值。<br>**在后补证据上：是**，见第 6 问 |
| **6 依赖后补证据** | **是。本域是五个域里唯一一个。** 损伤演化由 M9 的 `elements_2d.rcbeam`（`crack_model=3`）证明：`Yield` **5 371 个落在 (0,1]、区间外 0 个**，同一条断言在 `concrete_gravdam` 上是 **0 个在区间内 / 169 个在区间外**。该后补证据已按 §2 登记并回填 |
| **7 边界 / OPEN DEBT** | **PD-3 仍 OPEN**（legacy 自身缺陷，未修；已证实不是迁移引入——与快照逐字节相同）；`crack_model` 白名单现为 {3, 6}，两个取值各有一个真实算例；**口径冻结**：本域的「窄口径 ACCEPTED」= 链路 (a) + 演化 (b)，**不**等于「`concrete_gravdam` 触发了损伤」 |

---

## 5. M9 · 2-D 线单元域（L2 / STEEL）

| # | |
|---|---|
| **1 声称** | 现有现代输入词汇（`[[section]]` / `[[material]]` / `mesh`）**能容纳第二个单元族，不需要新层**。`rcbeam` 实际需要的**六个域**同时打开：单元族（Q4 + L2(1) + STEEL(25)）、截面面积走 `section.area`、CONCRETE `crack_model=3`、材料曲线、`.nrt` 节点插值表（`parse_nrt` + `mesh.interpolation[]`）、`[bond]` 粘结律。并去掉了适配器 / `build_runtime` / commit **三层各自复制的**「一个网格一种单元」假设——legacy 从来没有这个假设（`Elements.f90:1081-1087` 在组循环里按各组 `nnode` 读 `.ele`） |
| **2 不声称** | 合同非范围，逐条不变：3-D beam、梁/板荷载、转动自由度、局部坐标输出、`Iy/Iz/J`、其他 L2 算例。`read_geometry` 读到非零 `J`/`Iy`/`Iz` **直接拒绝而不是丢弃**；索引 20（`b2`，真正的梁单元，3 自由度含转动）**不在本域内**；材料应力-应变曲线**不表达**——读了就丢，因为本路径逐一查过没有任何消费者 |
| **3 证据** | golden `cases/golden/elements_2d/rcbeam`（793 节点 / 721 单元，Q4×600 + L2(1)×60 + STEEL(25)×61，与快照 `rc=0` 且**逐字节相同**）；合同六条判据见 `docs/m9/l2-element-domain.md` §0/§4；反例：截面面积两个方向（非线单元写 `area` / 线单元不写 `area`） |
| **4 严格等价** | **是**。120 块 / 214 110 值 / mismatches=0 / `max|d| = 0.000e+00`（2026-09-20 实测）。工作目录只有 `case.toml` + `1.cor`/`1.ele`/`1.nrt` |
| **5 真实触发** | **是，两条独立断言**。N4 `DISPLACEMENT non-zero: 47490`；N4 `Yield non-zero values in [0.0, 1.0]: 5371`。后者的预测（291/0/169 的对照形态）在**运行前写下**，实测完全一致 |
| **6 依赖后补证据** | **否**（本域不依赖后来的域），但有两条**前置**：M10 的 PARDISO 与 M11 的 CONCRETE 链路，两个阻塞都在本域开工前解除；以及 PD-2（`mmats` 被当成材料数——**我们自己的守卫写错了**，拒绝了 legacy 一直能跑的算例），修复后四个算例恢复可运行。PD-2 **不计入**本域能力。<br>**反向**：本域**向 M11 出借**了损伤演化证据，见 §2 |
| **7 边界 / OPEN DEBT** | 判据 2 收口前的分歧值得永久记住，已写进纪律：`.nrt` 曾被登记为「随网格原样带走」的直通文件，理由是 `Global.f90:1489-1531` 那段**没有** `yl_input_enabled` 守卫——但整个 `global_data` 在适配器路径上就不执行，**「没有守卫」不蕴含「会被读到」**，这是从代码形状推断执行。定位靠的是 `1.chk` 的方程数（`1459 = 1586 - 122 - 5` vs `1581 = 1586 - 0 - 5`，122 = 61 节点 × 2 自由度）。<br>其余 OPEN：`tunnel_sl` 在 1 626 300 个值里 1 586 个不同、`max|d|=1e-8`——**构建独立性欠债**，非本域引入；`test_beam2d`（`.pre` 约束 `ifixvar=4` 而 `MDOFN=2`，deck 自身错误）与 `pile_beam`（`.glb` 更老方言，快照 legacy 自己也读不了）**无可运行参考**，不是能力缺口 |

---

## 2. 后补证据登记（跨域，不再悬空）

本项目此前发生过一次「后来的证据顺手补了前面的判据」而没有登记的情形。
**规则**：跨域借用的证据必须在**两侧**都写明，并标注为**后补证据**，不得只写在出借方。

| 编号 | 出借域 | 借入域 | 借的是什么 | 为什么本域自己给不出 | 回填位置 |
|---|---|---|---|---|---|
| **BACKFILL-1** | M9 `elements_2d.rcbeam`（`crack_model=3`，`Yield` 5 371 个 ∈ (0,1]、区间外 0 个） | **M11** 判据 5「`Yield` 必须真实非零」 | CONCRETE **损伤演化路径**被真实触发的证据 | 语料普查结论：**凡是真的进损伤分支的 CONCRETE deck，都需要 L2 或 3-D**（`tunnel_sl` 47 765 / `rcbeam` 5 371 / `tunnel` 2 703 个真实损伤值，全部带 L2；`damage` 80 个，3-D）。M11 选的最小切片正因为躲开了这两处耦合，代价就是它从不进损伤分支 | `docs/m11/concrete.md` §3 + 后记；`docs/m9/l2-element-domain.md` §5；本文件 M11 第 6 问 |

**BACKFILL-1 不改变 M11 自己那个算例的结论**：`damage_2d.concrete_gravdam` 的 `Yield`
非零值全部是 PD-3 写进输出槽的未初始化局部量，这句话在签收后依然成立。

这一课已经**机械化**，不只是记在文档里：N4 的 `must_be_nonzero` 现在可带 `in_range=[lo,hi]`。
理由正是 `concrete_gravdam`——一个只数非零的断言**通过了**，靠的是垃圾值；
而 `damage` 在 legacy 里只能取 `0` 或 `1-sqrt(cc)`，不可能大于 1。
**一条什么都不检查的断言比没有更糟，因为它会被当成证据读。**

---

## 3. 签收时点的 OPEN DEBT 合并表

按 §4 纪律：冻结任何验收包之前先列全部 OPEN DEBT，逐条标注**影响哪些结论**。
受影响的结论不得写成「已验收」。

| 编号 | 一句话 | 影响哪些结论 | 是否阻塞本次签收 |
|---|---|---|---|
| **R28** | 单人项目无独立于实现人的复核人；M0 判据 18 只满足一半 | **全部五个域**的「独立性」栏。见 §4 | 否（负责人明示不阻塞、不新增 reviewer 机制） |
| **R30** | `PROV_VIA_RUNTIME` 的来源是散文、无机械对账 | 任何以**出处账本**判断「这个值从哪来」的推理；本次五个域均**不以**出处账本为论据 | 否 |
| **R32** | authoring 的 TOML 子集不接受多行数组 | M7 域的**可读性**判据（不是正确性）；真实坝面（30 条边 ≈ 330 字符一行）进来之前必须处理 | 否 |
| **R34**（新） | `yl_fallback_check.py` 只遍历 `state-field-map.toml` 的两个静力算例、且把算例路径硬编码为 `cases/golden/static_2d/`，却打印「**on every golden case**」 | 「回退开关在每个 golden 算例上都被验证过」——**这句话不成立**，实测只覆盖 `cooks_membrane` 与 `lame_cylinder` | 否，但**口径必须改写**：本次五个域的 FALLBACK 证据**不适用** |
| **PD-3** | CONCRETE 卸载分支写出未初始化的 `damage`（legacy 自身缺陷，未修） | M11 第 5 问；`concrete_gravdam` 的 `Yield` 输出槽**不可作为任何结论的输入** | 否（已如实记账，且不是迁移引入） |
| **M10 §6** | PROFILE 侧 `.sol` 读被守卫关掉后 `iafile/icond/ipdchk/ising` 无供给，而 deck 写 `ipdchk=1, ising=1` | 「静力 golden 逐位复现」——复现成立，但**原因是这些量在本切片上不被消费，是运气不是设计** | 否 |
| **构建独立性** | `tunnel_sl` 1 586/1 626 300 值不同、`max|d|=1e-8`；`beam_point_load` gdb 对照 6/756 值、`max|d|=1.3e-10` | 任何「跨构建逐位相等」的断言。**本次九个 golden 的 N2 不受影响**——它们是同一构建对同一冻结参考 | 否 |
| **M7 待裁定** | 梁/板荷载：自造 deck 取 legacy 作 oracle，还是记为 legacy-only 等真实 deck | M7 域的**完备性**（不是已签收部分的正确性） | 否；是一条**待裁定的范围决策**，本次签收不替它裁定 |

---

## 4. 独立性（如实填写，不制造不存在的复核）

**本项目不存在独立于实现人的复核人。** 这是 R28 登记的结构性缺口，本次签收**不声称**补上了它，
**也不为此引入新的 reviewer 机制**（负责人 2026-09-20 明示）。

那么这五个域的证据里，**真正独立于现代实现**的要素是什么？逐条点名，不多说一个字：

| 独立要素 | 强度 | 覆盖哪些域 |
|---|---|---|
| **冻结参考是 legacy 自己产出的**——oracle 不是现代实现的另一次运行，而是另一套代码 | **强**。这是「正确」而不是「自洽」：现代路径算错会与 legacy 分叉 | 五个域全部 |
| **与未改动 5414e73 快照逐字节相同** | **强**（本仓库构建 = 原始 legacy） | `rcbeam`(M9)、`concrete_gravdam`(M11)。**`new_duncan_chang`(M8) 没有**（快照上 SIGSEGV）；**`benchmark_100x100`(M10) 无记录**；`beam_point_load`(M7 P4) 无记录 |
| **反例先写预期再跑**（M8 五条 / M10 三条 / M11 三条全部按预期落地） | **中强**。它防的是「反例失效并伪装成结论」 | M8 / M10 / M11 |
| **阳性对照**（`must_be_nonzero` 的 `in_range`、`cases/` 守卫的注入写、PARDISO 不钉线程的 3 哈希） | **中强**。证明断言**能**报错 | M8 / M10 / M11 / M9 |
| **合同判据先写、初始全 `passes: false`** | 中。M9 是五个域里唯一有完整书面合同的（§0 + §4 六条） | M9 |
| 求解器收敛、同一实现跑两遍一致、内部自检零发现 | **弱，单独不支持 ACCEPTED**，此处**不作为**签收依据 | — |

**结论**：五个域的签收建立在「legacy 作为独立 oracle + 严格相等 + 先写预期的反例 + 阳性对照」之上，
**不**建立在第二方复核之上。这一句不因签收而淡化。

---

## 5. 签收页

**负责人（Huijun）于 2026-09-20 签收，口径如下，逐域不同：**

| 域 | 窄口径签收的内容 | 一并带着的债 |
|---|---|---|
| **M7 Phase 4** | 集中力链路成立且真实驱动位移场（体力为零，不可能自洽蒙混）；`commit_step_invariants` 29 字段防线成立 | 梁/板荷载待裁定；`factf` 未经反例；R32 |
| **M8** | 统一 `[[material]]` 容纳第二类非线性参数体系；`duncan_chang_t` 兄弟块成立；本构计算全部复用 legacy | **oracle 不是未改动快照**（PD-1 补丁后才有参考） |
| **M10** | 求解器选择链路成立；`mtype` 白名单只放行 `-2`；**冻结参考包含执行环境**成为机械化的通用规则 | `ncpu=4` 与钉住 1 线程必须成对读；`iafile/icond/ipdchk/ising` 无供给；无快照对照记录 |
| **M11** | (a) CONCRETE 读取/映射/派发链路成立（`concrete_gravdam`）；(b) 损伤演化路径成立（`rcbeam`，**后补证据 BACKFILL-1**） | PD-3 OPEN；`concrete_gravdam` **不触发损伤**这句话不变；白名单仅 {3,6} |
| **M9** | 现代输入词汇容纳第二个单元族无需新层；六个域同时打开；三层「一个网格一种单元」假设被去掉 | `tunnel_sl` 构建独立性；材料曲线读了就丢；非范围六项不变 |

**五个域一律为「窄口径 ACCEPTED」，不是无限定的能力签收。**
每个域「不声称」的那一行与本文件 §3 的 OPEN DEBT 表**与签收同等有效**；
引用本次签收时必须连同该域的第 2 问与第 7 问一起引用，单独引用第 1 问是**过度声称**。

**独立复核人一栏：空。** 理由见 §4，登记于 R28，不因本次签收而改变。
