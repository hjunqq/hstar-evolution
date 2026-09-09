> **状态：v3（2026-09-09）。v2 的四项必改已完成，v3 处理 lead 对第 0 项守卫的对照发现。**
>
> 独立对抗性复核：`docs/m4/L2c-fold-review.md`。主干四条（方案 A、折叠不能分批、
> 账本轴取「出处」、最大风险在释放路径）经复核未被推翻，保留。v1 被证伪的部分逐条处置：
>
> | 复核/lead 指出 | v2 的处置 |
> |---|---|
> | §2 的 59/59/2 错，应为 **24 / 5 / 89 / 2**；其中 5 行失败模式本身不稳定 | §2 整段重写，5 行单列并给出 `need_count` 的实测形状 |
> | §6 步 2 的通过判据不成立（dump 仍中止，从 `coord` 移到 `lnods_f`） | §6 重排：新增步 **3b** 把两个确定中止的 B 类行提前，检查点 ★ 挪到 3b 之后 |
> | 调用点是 **8** 不是 9，且文内自相矛盾 | §3 表与推荐②统一；并注明 `a5a6e15` 之后真实调用点已是 **11**，实施时以当次 `grep` 减去那条注释为准 |
> | 那 14 行是 deck 供的输入字段，不是 legacy 默认值 | §1.6.1 更正；§1.6.2 给出**更强**的答案：13 行的值由**适配器拒绝规则唯一蕴含**（`COMMIT_FROM_GATE`），照常参加比对，**不需要豁免桶** |
> | `DEFAULTED` 只是把假绿换成假豁免 | 取消 `DEFAULTED`；`NOT_MIGRATED` 只剩 ≤8 行，且 §4.4 要求该桶**封闭**（多一行少一行即失败） |
> | 实施前须先补盲区守卫 | **已完成**：提交 `a5a6e15`，4 条断言 + 5 个反例，581/581 → **720/720** |
> | §5.1 的「构造」并不能锁死三处 | §5.1 重写：承认只覆盖可分配全局那一半，指针目标那一半**没有仓库内机制**；§5.4 把 ASan/valgrind 定为**出口条件**；§5.1.3 新增一条能机检「忘在 release 里」的释放后总体性断言 |
>
> **v3 相对 v2 的改动：**
>
> | lead 指出 | v3 的处置 |
> |---|---|
> | `np_unode` 守卫抓不到「漏写」 | §4.5.1 如实写明三个守卫**能证明什么、不能证明什么**（复现了 lead 的对照，并把范围扩到 `strict` / `sanitize`：**三个剖面全部漏检**）；`yl_runtime_bridge_test.f90` 的注释同步更正，不再声称覆盖漏写 |
> | 通用解法：staging 分配后立即投毒 | **§5.5 新增**，作为机制与 §5.1.3、§5.4 并列；含哨兵取值、三条约束（尤其"哨兵绝不能被 legacy 看见"与 RESERVED 行的例外必须由账本说了算） |
> | 四个温度计数按"legacy 读不读"定，不按"deck 上是 0"定 | **§1.7.1 查实**：`.tem` 在 `Global.f90:661` 无条件打开，`boundt` 在 `Fem.f90:1899` 无条件调用，四个计数在 `Temper.f90:126/154/246/310` 被 `read` 赋值。**legacy 确实读**，所以写 0 是伪造读取结果 → 必须写 `.tem` 解析器；解析器一旦存在，这四行自动成为 `FROM_GATE`，**载体问题随之消失** |
> | `npoinb`/`nsmat`/`delgroup` 同理 | **§1.7.2**：legacy 读了并留在全局。`delgroup` 可以干净走闸门；`npoinb`/`nsmat` 确实需要一个不破坏双射的承载方式 —— 按你的话，报你决定 |
> | `nsmat` map 缺陷（`0646de3`）、`build.sh adapter` 目标（`21a5c98`） | 已采纳；§1.8 改记为**已修**，§6 的两个构建目标都跑 |
>
> **v3 新增、需要 lead 决定的一件事**：`sanitize` 剖面**今天跑不起来**
> —— 干净工作树上 rc=6，死在 libiomp 内部的 MSan 误报，进不了仓库代码。
> `KMP_AFFINITY=disabled` 即可绕过（实测 `PASS: 720/720`）。
> `tools/build.sh` 现在是你的，请决定是否把它加进 `sanitize` 剖面的运行环境 ——
> 在此之前 §5.4 的出口条件无从满足。

# M4 L2-c：把 ProblemState 那一半折叠进 `commit_legacy_globals` 的单次 staging —— 设计提案

> 本文是**设计提案**。除提交 `a5a6e15`（§4.5 的盲区守卫，lead 明确授权的唯一一处源码改动）外，
> `src/runtime/yl_runtime_commit.f90` 与 `src/adapter/**` 一行未动。
> 所有行数与行 id 均由 `docs/m2/state-field-map.toml` 与 `src/state/**` 的实际守卫
> 程序化枚举或逐行读出（命令见 §8），不是估算。

## headline

> **v2（2026-09-09）**：按 `docs/m4/L2c-fold-review.md` 的对抗性复核与 lead 的裁定修订。
> 改了什么：§2 的后果切分（59/59/2 → **24/5/89/2**）、调用点数（9 → **8**）、
> §1.6 关于 14 个 `not_migrated` 行的整段理由（"补默认值"是错的）、§4.3 的桶封闭、
> §5.1 的释放路径（"构造"只覆盖一半）、§6 的检查点位置。
> 主干四条未变：方案 A、必须一次全覆盖、账本轴是"出处"、最大风险在释放路径。
> §1 的行清单经复核逐行复现，未改。

| 项 | 数 |
|---|---|
| `model_ready` 全部行 | 239 |
| 其中 `emit ≠ none`（影子差分的判据面） | 162 |
| 今天已有仓库侧写入者 | **42** |
| 今天没有写入者 | **120** |
| 其中：不写就让 `yl_state_dump` **确定中止** | **24** |
| 其中：不写就**中止或静默发一条空记录**（失败模式本身不稳定） | **5** |
| 其中：不写就把 **Fortran 未定义初值**当作状态发出 | **89** |
| 其中：适配器自行合成、不需要任何全局 | **2** |
| 另有：`emit = none` 的 `RuntimeState` 行（快照永远看不见） | **14** |

**结论先说四句：**

1. **推荐 A：把 `commit_legacy_globals` 的签名改成同时接收 `problem_state_t` 与 `runtime_state_t`。**
   B（让 `build_runtime` 把 ProblemState 的值搬进 `runtime_state_t`）会撞碎 map ↔ `RuntimeState`
   的双射闸门。**同一道闸门也否掉了"把这些值读进 ProblemState"这个看起来更干净的办法** ——
   见 §3.1，这是 v2 新增的关键发现。
2. **折叠必须一次全覆盖。** 118 行（24+5+89）不写就是中止、不稳定或未定义内存，
   没有"先折一半"这个选项。
3. **不变量 3 的账本轴是"出处"，不是"写没写"** —— 写是被 dump 的总体性强制的。
   但账本按**发出行**建表，结构上覆盖不到那 14 个 `emit = none` 的行；这个缺口在 §4.5 显式记账，
   并已经由提交 `a5a6e15` 补上了其中最危险的 4 行的守卫。
4. **单个最大风险仍是释放路径，且 v2 承认它没有仓库内机制。** §5.1 原来提的"把名单改成构造"
   只覆盖可分配全局那一半；指针目标那一半（泄漏真正住的地方）表达不了。
   因此 ASan/valgrind **是出口条件，不是建议**。

---

## 1. 行清单：84 个 ProblemState 行 + 32 个 derived 行，按落点的旧全局分组

按"折叠时要做什么"分成五类。**分类依据是旧全局本身的形态**（已被写 / 是已重建记录数组的分量 /
新的可分配全局 / 新的标量全局 / 不落全局），因为这决定了 staging 代码的形状和释放路径的负担。

| 类 | 含义 | ProblemState | derived | 合计 |
|---|---|---|---|---|
| **A** | 旧全局**今天已经**被 commit 写了值（作为 extent 或作为 RuntimeState 行的载体），这些行不需要新代码 | 1 | 9 | **10** |
| **B** | 是 commit **已经重建**的记录数组的分量 —— 只能折叠，不可能由第二个写者补写 | 31 | 6 | **37** |
| **C1** | 新的**可分配**全局；不分配 → `yl_state_dump` 按契约中止 | 20 | 1 | **21** |
| **C2** | 新的**标量**全局；不写 → 发出未定义初值 | 30 | 16 | **46** |
| **D** | 适配器自行合成、不读任何全局 | 2 | 0 | **2** |
| | | **84** | **32** | **116** |

### 1.1 A 类（10 行）——已经有值，只欠账本

| 旧全局 | 行 id | commit 里的写入点 |
|---|---|---|
| `global_var.ndimn` | `mesh.dimension` | `s_ndimn = size(runtime%element(1)%field_coordinates,1)` |
| `global_var.npoin` | `derived.counts.npoin` | extent |
| `global_var.nelem` | `derived.counts.nelem` | extent |
| `global_var.ngroup` | `derived.counts.ngroup` | extent |
| `global_var.mdofn` | `derived.counts.mdofn` | extent |
| `global_var.cdofn` | `derived.dof.cdofn` | extent |
| `prescribed.ndofix` | `derived.counts.ndofix` | extent |
| `applied_load.ntcurve` | `derived.counts.ntcurve` | extent |
| `global_var.lmdofn` | `derived.dof.active_flags` | `move_alloc(s_lmdofn, lmdofn)`；dump 侧 `merge(1,0,lmdofn/=0)` 反构 |
| `global_var.lcdofn` | `derived.dof.lcdofn` | `move_alloc(s_lcdofn, lcdofn)`；dump 侧只取 `lcdofn(1:cdofn)` |

> **与 L3-c 的一处记账差异，请 lead 复核。** `docs/m4/L3c-shadow-report.md` §5.2 把这一类记为 **8**
> 行并列出了 8 个 id；本文记为 **10**，多出的两行是 `derived.dof.active_flags` 与 `derived.dof.lcdofn`。
> 理由：这两行的 dump 取值分别读 `lmdofn` 与 `lcdofn(1:cdofn)`，而这两个全局都由
> `yl_runtime_commit.f90` 的 `move_alloc(s_lmdofn, lmdofn)` / `move_alloc(s_lcdofn, lcdofn)` 写入。
> L3-c 当时观察不到这一点是因为 dump 在第 14 行就中止了，`normalize` 把 `active_flags` 报成
> `reconstruct` 失败而非 `missing`。**这不改变 L3-c 的任何结论**（120 vs 122 都远大于零），
> 只影响本文的分母；两个数都写在这里，lead 可自行判定取哪个。

### 1.2 B 类（37 行）——必须折叠，因为记录数组是被**重建**的

这是模块头那句"a second writer would reintroduce exactly the partial-commit state"的具体内容：
下面每一行的宿主记录都在 `commit_legacy_globals` 的 staging 里被整体新建、然后 `move_alloc` 进全局。
任何"第二次 commit 补写这些分量"的方案都会在下一次 commit 时被整体覆盖掉。

| 旧全局 | 行数 | 行 id |
|---|---|---|
| `global_var.group` | 21 | `derived.counts.nrfields`, `derived.counts.nstre`, `mesh.sets.elset`, `sections.class`, `sections.dof_count`, `sections.dof_list`, `sections.elcod_local`, `sections.element`, `sections.element_kind`, `sections.elset_size`, `sections.fields`, `sections.formulation`, `sections.ilayer`, `sections.liquj`, `sections.material`, `sections.name`, `sections.special`, `sections.type_ecoint`, `sections.type_nalgo`, `sections.type_stiff`, `sections.uplift_ic` |
| `prescribed.prescrib` | 7 | `mesh.sets.nset`, `steps0.boundary.amplitude`, `steps0.boundary.dof`, `steps0.boundary.nodes`, `steps0.boundary.record_reaction`, `steps0.boundary.set`, `steps0.boundary.value` |
| `global_var.element` | 5 | `mesh.elements.group`, `mesh.elements.kind`, `mesh.elements.material`, `mesh.elements.nodes`, `sections.material_header` |
| `applied_load.tcurves` | 4 | `amplitudes.points.count`, `amplitudes.points.time`, `amplitudes.points.value`, `amplitudes.type` |

`global_var.listp_group` 与 `global_var.trans` 没有 ProblemState/derived 行，折叠不碰它们。

**B 类里新增的指针目标**（`commit_release` 必须同步增长，见 §5）：
`group%list`、`group%dof(:)`、`group%dof(if)%listdof_f`、`element%field(1)%lnods_f`、
`tcurves%ttime_curve`、`tcurves%dfact_curve`。
其余分量是记录内的标量（`group%kname/%name/%class/%index/%matno/%nelgroup/…`、
`prescrib%nodfix/%ifixvar/%vdofix/…`、`tcurves%ntime/%type_curve`），只赋值、不新增所有权。

### 1.3 C1 类（21 行）——不分配就中止

| 旧全局 | 行数 | 行 id |
|---|---|---|
| `materials.props` | 15 | `derived.counts.nphase`, `materials.E`, `materials.density`, `materials.icreep`, `materials.id`, `materials.jliqu`, `materials.kind`, `materials.kind_wt`, `materials.model`, `materials.name`, `materials.nu`, `materials.phase`, `materials.ratio`, `materials.thermal_expansion`, `sections.thickness` |
| `global_var.coord` | 1 | `mesh.nodes.xyz` |
| `global_var.appear_process` | 1 | `steps0.activation.active` |
| `global_var.matno_process` | 1 | `steps0.activation.material` |
| `global_var.average_appear` | 1 | `steps0.output.stress_averaging` |
| `applied_load.factg` | 1 | `steps0.load.gravity.direction` |
| `applied_load.tcurvegravity` | 1 | `steps0.load.gravity.amplitude` |

`materials.props` 是这一类里最重的一个：`props(:)` 是 `allocatable`，但 `props(i)%mechanical`
与 `props(i)%mechanical%solid` 是**指针**（`Material.f90:200-205`），dump 对两级都有
`state_fail` 守卫。折叠要为每个材料建两级指针目标，`commit_release` 要按相反次序释放两级。

### 1.4 C2 类（46 行）——不写就发出未定义内存

`applied_load.{delgroup,edge_load_group,gravy,nbeamload,nedge,nplateload,nplgroup}`（7）、
`global_var.{NGRAV,nblks,nmats,nonsym,npoinb,nsmat,outplot,probn,runblks,type_ABC,type_load,type_nl,type_problem,type_solver}`（14）、
`global_var.gid_*` 20 个 GiD 输出开关（20）、
`prescribed.nfixsets`（1）、`temperature.{npipe,ntedge,ntelgroup,ntemp_surface}`（4）。

L3-c §5.3 手工比出的 5 行差异（`probn`/`runblks`/`npoinb`/`nmats`/`outplot`）全部落在这一类，
不是巧合：这一类没有分配守卫，所以 dump 会把它读到的任何字节当成状态发出去。

### 1.5 D 类（2 行）——不需要写入者

`mesh.nodes.id`、`mesh.elements.id`：两行的 `legacy_symbol` 都是 `global_var.i0`，而 `i0` 是
`global_var` 里一个被读取循环复用的**标量临时量**（`Global.f90:48`），legacy 读进去、校验、丢弃。
map 的 note 明说 dump 侧发的是 `1..npoin` / `1..nelem` 的下标序列。**折叠对这两行无事可做**，
它们会自动 MATCH。这是本文唯一两行"抗拒分类"的行，处理方式是照 map 的 note 直说，而不是硬塞进某一类。

### 1.6 不变量 5：77 个 `not_migrated` 行 —— 63 个出局，**14 个不出局**

明确写下来，而不是默认略过：`not_migrated` 的 77 行**不是**都在范围外。

- **63 行** `compare.rule = ignore` 且 `emit = "none"`：dump 根本不发，折叠不碰，出局。
  （程序化核对：`model_ready` 的 77 个 `ignore` 行 = 14 个 `RuntimeState.*` + 63 个 `not_migrated`。）
- **14 行** `emit ≠ none`，**在影子差分的判据面里**，必须写。其中 `control.glb.uinitial`
  是 `allocatable`（`Global.f90:186-187`，`allocate` 在 `:965`，`read` 在 `:1093`），
  dump 在 `yl_state_dump.f90:491` 有守卫 —— 不分配就没有快照，和 `coord` 同级阻塞。

#### 1.6.1 更正：这 14 行不是"legacy 默认值"，是**牌面供给的输入字段**

v1 把这 14 行的取值来源写成"map 每行自己的 `reason`/`note` 记录的 legacy 默认值"。**这是错的**，
复核者查了 `source` 列，我复查确认：14 行全部指向 deck 读入记录
（`INP.FEM90.run_control`、`GLB.global_data.{problem_type,init_and_blocks,sizes_and_switches,uinitial,transform_and_mif}`）。
map 的 `reason`/`note` 记的是**消费点**和**两个 golden deck 上的观察值**，不是赋值点。
所以"补一个默认值"这个说法从根上不成立：deck **供了**这些值，是新路径没有把它们带过来。

#### 1.6.2 但真正的答案比"钉值"好：**13 行的值是适配器闸门自己蕴含的**

lead 要我优先评估 (i-a)"让适配器真的去读它们"。**逐行查完了：适配器今天已经全部读了。**
而且它做的比"读"更强——它**拒绝**任何不合规的值。逐行（引用 HEAD 的 `src/adapter/**`，
不是 dev-l2b 的工作树）：

| 行 | 读取点 | 闸门 | 蕴含的值 |
|---|---|---|---|
| `control.run.restart` | `yl_adapter_fem90.f90:190` | `reject_nonzero(... 'F1','restart')` | 0 |
| `control.run.relis` | 同上 | `reject_nonzero` | 0 |
| `control.run.adina` | 同上 | `reject_nonzero` | 0 |
| `control.glb.ninit` | `yl_adapter_model.f90:377` | `reject_pinned('ninit-nonzero')` | 0 |
| `control.glb.nlinks` | 同上 | `reject_pinned` | 0 |
| `control.glb.block_stab` | 同上 | `reject_pinned` | 0 |
| `control.glb.nbackf` | 同上 | `reject_pinned` | 0 |
| `control.glb.ebody` | 同上 | `reject_pinned` | 0 |
| `control.glb.nlayer` | `yl_adapter_model.f90:441` | `reject_dialect('nlayer-nonzero')` | 0 |
| `control.glb.state_change` | 同上 | `reject_pinned` | 0 |
| `control.glb.bparameter` | 同上 | `reject_pinned` | 0 |
| `control.glb.ntrans` | `yl_adapter_model.f90:762` | `reject_pinned('ntrans-nonzero')` | 0 |
| `control.glb.uinitial` | `yl_adapter_model.f90:825` | `reject_pinned` on `any(uinitial(1:nblks) /= 0)` | 全 0 |
| **`control.glb.stab_matde`** | `yl_adapter_model.f90:301` 读，`:396` 判 | `stab_matde <= nblks` 才拒 —— **一个区间，不是一个值** | **不确定** |

**这把"钉常量"换成了一个完全不同的东西。** 对前 13 行，commit 写 0 不是硬编码观察值，
而是**写下闸门唯一放行的那个值**：任何携带非 0 的 deck 在 `adapt_legacy_deck` 阶段就被拒了，
`problem_state_t` 根本不会诞生。所以

- **不需要 `NOT_MIGRATED` 桶，也不需要静默豁免**：这 13 行照常参加比对。
  它们会 MATCH；哪天闸门被放宽而 commit 没跟上，差分**立刻变红**。
  这正好消掉复核者点出的"静默豁免比静默假绿更难发现"。
- 账本里它们的出处是 **`COMMIT_FROM_GATE`**，值旁边记的是**拒绝规则的 id**
  （`F1/restart`、`A-GLB/nlayer-nonzero` …），不是"两个 deck 上是 0"。这是可机检的来源。

**一处必须写明的限制**：`FROM_GATE` 的正确性依赖"这个 `problem_state_t` 来自旧 deck 适配器"。
这些拒绝规则住在适配器，不在 M3-02 的能力闸门里；将来的现代输入路径不会跑它们。
所以 `FROM_GATE` 只在旧适配器是唯一生产者期间成立，这条依赖要写进账本条目本身，
而不是留在注释里。

#### 1.6.3 剩下的一行：`stab_matde`，以及为什么它不能靠"读进 ProblemState"解决

`stab_matde` 的闸门是 `> nblks`（一个禁用区间），两个 golden deck 都是 99999，
但一个合规的第三份 deck 可以是 5。写常量 99999 在那份 deck 上就是**错的**。

自然的想法是"读进 ProblemState 再由 commit 写出去"——**这条路被堵死了，堵它的是同一道闸门**。
见 §3.1：`not_migrated` 与 `derived` 行没有 `ProblemState.*` owner 路径，
`tools/yl_problem_check.py` 的双射不允许 `problem_state_t` 出现一个没有 map 行的分量
（`@m5-only` 的语义是"ADR-0003 契约有、legacy 没有"，正好反过来）。

**这一行的三条路，请 lead 选（我推荐 (b)）：**

- (a) **闸门收紧成一个精确值**（`stab_matde == 99999`）。commit 写的值因此可证明正确。
  代价是拒绝一部分 legacy 能正常处理的 deck —— 一次**声明式的能力收窄**，
  必须登记进能力表，而不是悄悄发生。
- (b) **封闭的单行 `NOT_MIGRATED` 桶**：桶里恰好这一行，多一行少一行都让差分失败（§4.4）。
  代价是这一行在影子差分里永远不产生证据，但它**只有一行**，而且封闭桶让它不可能悄悄长大。
- (c) 给 map 加一个能承载它的 owner 路径。这是 map 所有者的动作，超出本设计。

推荐 (b)：它不缩小能力，代价被限制在一行，且封闭性使这个代价可见。
(a) 更"干净"，但用拒绝真实 deck 换取一行快照的可比性，代价方向不对。

### 1.7 同一个问题问 `derived` 行：还有 7 行处境相同

复核和 lead 都只讨论了 14 个 `not_migrated` 行。**但 32 个 `derived` 行里有 28 行的 `source`
也是 deck 读入记录**（只有 4 行是 `derived:` 规则）。逐行查完，它们分三种，前两种没问题：

- **可从 ProblemState 重算（17 行）** —— `npoin`/`nelem`/`ngroup`/`nmats`/`nblks`/`ntcurve`/
  `mdofn`/`nfixsets`/`nrfields`/`elset_size`/`dof_count`/`dof_list`/`nphase`/
  `amplitudes.points.count`/`cdofn`/`lcdofn`/`ndofix`。
  map 的 `[shape_symbols]` 段本身就是这么定义它们的（`nmats = "count(materials)"`、
  `nblks = "count(steps)"`）。**这些是真正的 derived，不需要任何决定。**
- **闸门蕴含（7 行）** —— `runblks`（`yl_adapter_fem90.f90:232` 拒非 1）、
  `nplgroup`/`nedge`/`edge_load_group`/`nbeamload`/`nplateload`（`yl_adapter_load.f90` 各自
  `reject_dialect` 拒非 0）、`nstre`（`derived:legacy_default`）。与 §1.6.2 同一处理。
- **既不能重算、也没有闸门（7 行）** —— **和 `stab_matde` 同一处境**：

| 行 | 旧全局 | 适配器怎么处理它 | 两个 golden deck 上的值 |
|---|---|---|---|
| `derived.counts.npoinb` | `global_var.npoinb` | 读了就丢（`yl_adapter_model.f90:301`，模块头："read here but never authored"），**不校验** | 289 / 81（恰好 = `npoin`） |
| `derived.counts.nsmat` | `global_var.nsmat` | 读了就丢（`:491`），**不校验** | **1 / 1** |
| `derived.counts.delgroup` | `applied_load.delgroup` | 与 `edge_load_group` 同一条 read（`yl_adapter_load.f90:498`），**只校验前者** | 0 / 0 |
| `derived.counts.ntemp_surface` | `temperature.ntemp_surface` | **产品路径完全不读 `.tem`** | 0 / 0 |
| `derived.counts.ntedge` | `temperature.ntedge` | 同上 | 0 / 0 |
| `derived.counts.ntelgroup` | `temperature.ntelgroup` | 同上 | 0 / 0 |
| `derived.counts.npipe` | `temperature.npipe` | 同上 | 0 / 0 |

（`src/adapter/yl_adapter_harvest.f90:303` 确实 `call boundt`，但它的模块头写明
"THIS IS AN ORACLE, NOT A PRODUCT PATH"，`adapt_legacy_deck` 不经过它
（`git show HEAD:src/adapter/yl_adapter_driver.f90 | grep -c harvest` → 0）。
所以产品路径上这四个温度计数**没有读取者**。）

**所以需要 lead 决定的不是 1 行，是 8 行**：`stab_matde` + 上表 7 行。

#### 1.7.1 legacy 在 static_2d 上**确实读 `.tem`** —— 所以写 0 是伪造读取结果

lead 给的判据不是"0 对不对"，而是"legacy 在这条路径上写不写它们、从哪写"。**查实了，逐条：**

| 事实 | 位置 |
|---|---|
| `.tem` 在 `global_data` 里**无条件**打开 | `legacy/yl/Global.f90:661`（`open(tunit, file=probn(1:len1)//'.tem', status='old')`），紧接着 `diag_check_open` |
| `boundt` 被**无条件**调用（块循环内，无 guard） | `legacy/yl/Fem.f90:1899` `call boundt !! temperature` |
| `ntemp_surface` 在 `if(iblks==1)` 下从 `tunit` 读入（本路径 `iblks==1`） | `legacy/yl/Temper.f90:126` |
| `ntedge` / `ntelgroup` / `npipe` 同样从 `tunit` 读入 | `Temper.f90:154` / `:246` / `:310` |
| M1 的 reader 清单登记了这些站点 | `docs/m1/reader-inventory.toml`：`TEM.boundt.{temp_surface_count,temp_edge_count,temp_elgroup_count,pipe_count}` |
| golden deck 里 `1.tem` 真实存在且有记录 | `cases/golden/static_2d/*/legacy/1.tem`（四个计数都是 0，但**是读出来的 0**） |

**结论（按 lead 的规则第二条）：legacy 在这条路径上确实读了 `.tem`，
所以折叠往这四个全局写 0 就是伪造读取结果，不得这么做。**
它们不是"停在零初始化"——它们是被 `read` 语句赋的值。

**正确做法**：写一个 `.tem` 解析器。它很小 —— M1 清单里就是 5 条 title + 4 个计数，
形状与 `yl_adapter_load.f90` 已经在做的 `nplgroup`/`nedge`/`nbeamload`/`nplateload`
完全一样：读记录、非 0 即 `reject_dialect`。lead 已确认 M4-01 的解析器扩展不再被阻塞
（L3-a 已验收）。

**解析器一旦存在，载体问题自动消失**：这四行随即与 `nedge` 同类，成为
`COMMIT_FROM_GATE`（值由拒绝规则唯一蕴含），**不需要 ProblemState 承载它们**，
也就不触碰 §3.1 的双射闸门。
"伪造"与"闸门蕴含"的分界线，正好是**新路径有没有真的读过那条记录**。

#### 1.7.2 `npoinb` / `nsmat` / `delgroup`：读了却丢弃，legacy 把它们留在全局里

同一条规则应用到这三行，答案与温度计数不同：

- legacy **读了并留在全局**：`npoinb` / `nsmat` 由 `Global.f90:694` / `:815` 的 `read` 赋值给
  `global_var` 的模块变量；`delgroup` 由 `Load.f90:754` 赋值给 `applied_load` 的模块变量。
- 新路径的适配器**也读了**（§1.7 表），只是读完丢弃、不校验。

所以按 lead 的规则，它们"既然被读了，就应当被带出来"。可带出的方式有两种，
而**载体问题在这里是真的**（它们是 `derived` 行，无 `ProblemState.*` owner，§3.1）：

| 行 | legacy 是否消费它 | 建议 |
|---|---|---|
| `derived.counts.npoinb` | **从不消费**：全仓库只有 `Global.f90:694` 读、`:696` 打印、`:699` 范围检查，无其他引用 | 需要载体或闸门。加 `reject` 会拒绝 legacy 能正常处理的 deck，而这个值 legacy 自己都不用 —— 我倾向**需要一个不破坏双射的承载方式**，这正是 lead 说的架构决定 |
| `derived.counts.nsmat` | **消费**：`Fem.f90:15499` 的刚度重组节奏（见 `0646de3` 的更正） | 同上，且更强：它影响控制流，钉死等于替 deck 做决定 |
| `derived.counts.delgroup` | 只在 `edge_load_group /= 0` 的块内有意义，而该分支已被拒 | 三者中唯一可以干净地走闸门：在 `edge_load_group == 0` 时要求 `delgroup == 0`，代价接近零 |

**报给 lead 的结论**：`delgroup` 走闸门；`npoinb` 与 `nsmat` 需要一个承载方式 ——
按你的话，这是架构决定，我不自行选。`stab_matde` 与它们同类（§1.6.3），
三者一起决定比分开决定省事。

### 1.8 一处 map 事实错误：`derived.counts.nsmat`（**已由 `0646de3` 修复**）

`derived.counts.nsmat` 的 map note 写着 **"0 on both cases"**。
**冻结的 M2-03 基线和 deck 本身都说是 1。**

```
cases/golden/static_2d/{cooks_membrane,lame_cylinder}/reference/state/model_ready/control.json
    derived.counts.nsmat = 1
legacy deck 1.glb 第 10-11 行:  NMASS NSMAT NHMAT ... ->  1  1  1  1  0  0  1  0  1  0  0
```

这与 lead 已在 `a8d4646` 修好的 `restart` / `stab_matde` 错位是同一类：
**map 的 note 不能当作取值来源**。这正是本节把取值来源从"note"改成"闸门规则"的第二个理由。

**已由 `0646de3` 修复**（lead）。值得记下的是后果的量级：note 说 0 而实际是 1，
把控制流结论整个倒转 —— `Fem.f90:15499` 的 `IF (NSMAT.EQ.0 .OR. ...)` 在 0 时析取恒真、
每次都重组刚度，而实际的 1 只在 `inc_step` 首迭代重组。
**一个 note 里的错值，改变的是"legacy 在这条路径上到底做了什么"的答案。**

---

## 2. 折叠的总体性是被 dump 强制的（v2 修正切分）

把 120 个无写入者的行按"不写会发生什么"重新切一刀。**v1 的 59/59/2 是错的**，
根因是把"容器有守卫"当成了"分量有守卫"：`element`/`group`/`prescrib`/`tcurves`
今天就被 commit `move_alloc` 进全局了，容器级守卫因此不触发，dump 读到的是
**记录内未被赋值的标量分量**（legacy 的这些记录类型没有任何默认初值）。

| 不写的后果 | 行数 | 组成 |
|---|---|---|
| `yl_state_dump` **确定中止** | **24** | C1 21 + `control.glb.uinitial` 1 + B 类 2 |
| **中止 _或_ 静默发一条长度 0 的记录**（不确定） | **5** | B 类 5 |
| 未定义初值被当作状态发出 | **89** | C2 46 + 13 个 `not_migrated` 标量 + B 类 30 |
| 无事发生 | **2** | D 类 |
| | **120** | |

**确定中止的 2 个 B 类行**（其余 B 类行的宿主容器已分配，不中止）：

| 行 | 守卫 | 为什么必中止 |
|---|---|---|
| `mesh.elements.nodes` | `yl_state_dump.f90:135` | 无条件 `associated(element(1)%field(1)%lnods_f)`；commit 的 `null_element_field` 把它 nullify 了 |
| `sections.material_header` | `yl_state_adapters.f90:271` | `ne = group(g)%nelgroup` 之后是**无条件**的 `if (ne < 1) state_fail`；`ne >= 1` 则下一句 `associated(group(g)%list)` 失败。两条路都中止 |

**那 5 个"失败模式本身不稳定"的行**，是本次修正里最值得单独记住的一点：

| 行 | 位置 | 决定成败的未定义标量 |
|---|---|---|
| `mesh.sets.elset` | `yl_state_adapters.f90:381` | `group(g)%nelgroup` |
| `sections.dof_count` | `:301` | `group(g)%nrfields` |
| `sections.dof_list` | `:335` | `group(g)%nrfields`，再 `group(g)%dof(f)%nfdof` |
| `amplitudes.points.time` | `:466` | `tcurves(c)%ntime` |
| `amplitudes.points.value` | `:499` | `tcurves(c)%ntime` |

五处是同一个形状（实测自 `need_count`，`yl_state_adapters.f90:83-88`：**只在 n < 0 时中止**）：

```fortran
n = <未定义的标量分量>
call need_count(w, id, '...', n)      ! n < 0  -> 中止
if (n > 0_ink) then                   ! n > 0  -> associated() 检查失败 -> 中止
  ...
end if
call begin_field(w, id, ..., [int(n, int64)], ...)   ! n == 0 -> 发一条长度 0 的记录，不中止
```

`n` 恰为 0 时**不中止**，发出一条结构完好、长度为 0 的记录，直接进差分。
v1 的论证是"未定义值比错值更糟，因为不可复现"；这 5 行把不可复现性又推高一级 ——
**连失败模式本身都不可复现**，同一份二进制两次运行可以一次中止一次不中止。
**v1 的二分法（"要么中止、要么发未定义值"）在它们身上不成立。**

定性结论不变，反而更强：落在"未定义或不稳定"桶里的从 59 涨到 **94**。
**折叠必须一次覆盖全部 162 个 `emit ≠ none` 的 `model_ready` 行。**

---

## 3. 岔路：A / B / C

### 3.1（v2 新增）先排除一个看起来更干净的办法：把这些值读进 ProblemState

lead 的 (i-a) 问的是"适配器已经在解析这些记录了，为什么不读进来、由 commit 从 problem_state 写出去"。
读——已经读了（§1.6.2）。**但"进 ProblemState"这一步被一道现成的闸门堵死，而且是堵死选项 B 的同一道。**

`tools/yl_problem_check.py` 在 `problem_state_t` 的叶子分量与 map 的 98 个
`owner` 以 `ProblemState.` 开头的行之间强制**双向双射**。一个分量要么带 `@map:<id>` 指向一个
真实的 `ProblemState.*` 行，要么带 `@m5-only:<reason>`——而 `@m5-only` 的语义正好相反
（"ADR-0003 契约要求、而任何 legacy 记录都不携带的字段"）。`@required:` 不是逃生口，
它的语义是"一个**已映射**字段为何可以是裸内建类型"。

`not_migrated` 与 `derived` 行**没有 `ProblemState.*` owner 路径**。所以给
`problem_state_t` 加一个 `restart` / `stab_matde` / `nsmat` 分量，会造出一个没有 map 行的分量，
`yl_problem_check` 直接 FAIL。要绕过它，就得重新定义 map 里 owner 列的含义 ——
**与选项 B 要做的事一模一样，也是不变量 4 禁止的同一件事。**

这就是为什么 §1.6.2 的答案落在"闸门蕴含的值"而不是"读进 ProblemState 再写出去"：
前者不需要 ProblemState 多一个字段，也不需要动任何闸门的判据。

### 选项 A —— `commit_legacy_globals(problem, runtime, errors)`

commit 同时接收 `problem_state_t` 与 `runtime_state_t`，在**同一个 staging 段**里把两半一起建出来，
写阶段仍然只有 `move_alloc` 和标量赋值。

| 不变量 | 代价 |
|---|---|
| 1 单写者/单次 staging | **满足**。仍然是一个 subroutine、一段 staging、一段 write。新增的局部 staging 变量与既有的同形。 |
| 2 事务性 | **满足**，且是结构性的：新增的失败点全部在 staging 局部量上。 |
| 3 账本 | 需要新增 commit 侧账本（§4），但这在**任何**方案下都要做，不是 A 的成本。 |
| 4 无重复语义 | **满足**。每行的值取自它 map `owner` 指定的那个对象；commit 只做转换（kind、字符串、1-based 下标），不做判定。 |
| 5 not_migrated | 与方案无关。 |
| 其他 | 签名变更 → **8 个调用点，3 个文件**（`yl_adapter_shadow.f90:114` 1 处、`yl_adapter_bridge_test.f90:204` 1 处、`yl_runtime_bridge_test.f90` 的 `{131,550,617,647,675,721}` 6 处；v1 写的 9 把 `yl_adapter_bridge_test.f90:18` 的一行注释算成了调用点）。**提交 `a5a6e15` 之后 `yl_runtime_bridge_test.f90` 又多了 3 处（新 section 7），真实调用点已是 11 个**；实施时以 `grep -rn 'call commit_legacy_globals' src/` 的当次结果减去 `yl_adapter_bridge_test.f90:18` 那一条注释为准，不要照抄这里的数。三个文件里 `problem_state_t` 都已经在手（`yl_runtime_bridge_test.f90:116` 自己调 `prepare_problem`），但 §2/§3/§5/§6 那四个测试子程序今天只收 `rt`，需要把 `problem` 一起穿进去 —— 机械但不是零。模块依赖方向不变：`yl_runtime_commit` 已经 `use yl_problem_optional / yl_problem_errors`，加 `yl_problem_types` 不引入新的层级。 |

**A 的唯一真风险**：commit 会拿到一个"可能没被 gate 过"的 `problem`，容易长成第二个校验器。
约束写死在实现规则里：**commit 只许转换，不许判定**。任何 `opt_*` 未设值一律 `PE_INTERNAL`
（和今天 `opt_or` 的 fallback 依据同一条理由：到了 commit 还缺值，那是管道坏了，不是模型坏了）。

### 选项 B —— 让 `build_runtime` 把 ProblemState 的值带进 `runtime_state_t`

**否决。** 它会同时撞碎三道现有闸门，而这三道闸门的存在理由就是不变量 4：

1. `tools/yl_state_map.py:1863-1873`（R3）：`derive` 规则若声明一个**不是** `model_ready`
   `RuntimeState.*` 的 map 行，直接 FAIL。带过去的行 owner 是 `ProblemState.*`。
2. 同文件 R5（`:1885-1891`）+ `verify_registered`（`yl_runtime_commit.f90`）要求
   `runtime_status_count(runtime) == build_rule_produced_count()`，即账本 = 规则表产出集 = 那 46 行。
   加行就要动规则表；动规则表就要动 R3 的判据。
3. `yl_runtime_types` 的头部契约：每个分量带一个指向 `RuntimeState.*` 行的 `@map` 标记，
   自检断言这是一个双射。

要让 B 成立，就得重新定义 map 里 "`RuntimeState`" 这个 owner 的含义，让它容纳
"owner 写着 `ProblemState.*`、但也住在 runtime 里的一份拷贝"。**那正是一行的所有权在两处被决定。**
附带成本：`build_shape_t%coord` 已经在 build 里私有存在了一份，B 会让它变成第二份公开拷贝；
`manifest` 还得为它没做过的"派生"记账。

### 选项 C —— A + 文件拆分

若折叠后 `yl_runtime_commit.f90`（现 751 行）膨胀过头，把 ProblemState 那一半的 staging 抽成
`yl_runtime_commit_stage`，由 commit 在它自己的 staging 段里调用，**以 `intent(out)` 的
allocatable 局部量返回**。硬约束：辅助模块**不 `use` 任何 legacy 模块**（编译期即可保证它写不了全局），
公开入口与 write 段留在 `yl_runtime_commit`。

**这只是 A 的实现细节，不是第三条路线。** 建议：先按 A 写，超过 ~1500 行再拆，拆的时候
以"辅助模块的 `use` 列表里没有 `global_var` / `materials` / `prescribed` / `applied_load` / `meshfine`"
作为可 grep 的闸门。

### 推荐

**A**（必要时以 C 的方式拆文件）。理由排序：
① B 违反不变量 4 且要改三道闸门的判据，代价不对称；
② A 的签名变更成本是 3 个文件里的十来个调用点（`a5a6e15` 前 8，今天 11），一次性，且每个调用点的 `problem_state_t` 都已在作用域内；
③ A 让每行的值来自 map 指定的 owner 对象，这本身就是"单一来源"在代码里的样子。

---

## 4. 不变量 3：账本怎么扩展才能回答"这条路径写了这一行吗"

### 4.1 先纠正问题的形状

§2 已经证明：**在 162 个发出行上，"写没写"不是一个自由变量** —— 不写就是中止或未定义内存。
所以账本要回答的不是**是否**写了，而是 **值是怎么来的**。这是不变量 3 的实际内容：
L3-c §5.3 那 5 行的病根不是"没写"，是"发出去的东西没有出处，却被当作有出处的值参与比对"。

### 4.2 现有账本不能直接扩

`runtime%field_status` 的行集被 §3 里那三道闸门钉死在 46 个 `RuntimeState.*` 行上。
往里加 ProblemState 行 = 走 B 的老路。**不扩它。**

### 4.3 提案：commit 侧的**出处账本**，行清单由 map 生成

四件东西，职责不重叠：

1. **生成的行清单**（单一来源仍是 map）。
   `src/state/yl_state_dump.f90` 已经是 `tools/yl_state_map.py gen-fortran` 的产物 ——
   同一条命令再生成一张 `model_ready` 且 `emit ≠ none` 的**有序行 id 表**
   （建议 `src/state/yl_state_rows.f90`）。**没有任何一处手抄行清单。**
   溯源行必须由 `tools/build.sh` 校验 —— 提交 `a8d4646` 已经给 `yl_state_dump.f90`
   加了这道 fail-closed 门禁，新表沿用它，不要另起一套。

2. **commit 声明每行的出处**（手写，就在 `yl_runtime_commit`）。取值域（v2 修订）：

   | 状态 | 含义 | 行数（预期） |
   |---|---|---|
   | `COMMIT_FROM_PROBLEM` | 值取自 `problem_state_t` 的对应 owner 分量 | 84 − 已由 runtime 覆盖的部分 |
   | `COMMIT_FROM_RUNTIME` | 值取自 `runtime_state_t`（今天的 32 个发出行 + A 类 extent） | 42 |
   | `COMMIT_DERIVED` | 从 ProblemState 的集合基数算出（`count(materials)` 一类，见 §1.7） | 17 + 4 |
   | `COMMIT_FROM_GATE` | 值由**适配器的拒绝规则**唯一蕴含；条目里记规则 id（`F1/restart`），不记"两个 deck 上是 0" | 20（13 + §1.7 的 7） |
   | `COMMIT_SYNTHETIC` | dump 侧自行合成，commit 无事可做（D 类） | 2 |
   | `COMMIT_NOT_MIGRATED` | **没有来源**：既不能重算、也没有闸门（§1.6.3 + §1.7 的 8 行） | ≤ 8 |

   `COMMIT_FROM_GATE` 是 v2 相对 v1 最重要的改动：v1 的 `DEFAULTED` 把 20 行推进豁免桶，
   而它们其实是**可比对、且应当比对**的 —— 闸门放宽而 commit 没跟上时，
   差分要立刻变红，这正是复核者担心的"静默豁免"的反面。
   每个 `FROM_GATE` 条目必须携带它依赖的拒绝规则 id，以及 §1.6.2 末尾那条限制
   （只在旧 deck 适配器是唯一生产者期间成立）。

3. **总体性闸门**，放在 commit 的 VERIFY 段，与 `INV-COMMIT-TOTAL` 同形：
   生成表里的每一个行 id 都必须在声明表里有条目，否则 commit **拒绝提交**。
   map 新增一行而 commit 没跟上 → 在 VERIFY 段失败，而不是静默少写一个全局。

4. **旁挂文件**：commit 成功后写出 `<dump dir>/model_ready/provenance.txt`，
   `tools/yl_shadow_diff.py` 读它。

### 4.4 `NOT_MIGRATED` 桶必须**封闭**（lead 必改项 ④）

只说"记为第五个桶、既不算 MATCH 也不算 MISMATCH"是不够的。复核者说得对：
一个不被任何 STOP RULE 看的桶，是比静默假绿更暗的地方 —— 假绿至少还在 MATCH 计数里。

**封闭的定义（可机检，写进 `yl_shadow_diff.py` 的停止规则）：**

- 差分实际归入 `NOT_MIGRATED` 的行 id 集合，必须**逐字等于**账本里声明为
  `COMMIT_NOT_MIGRATED` 的集合；
- 且该集合必须**逐字等于**一份入库的、评审过的期望清单（本设计的 §1.6.3 + §1.7 的 8 行）；
- **多一行或少一行都让差分以非 0 退出**，与一条 MISMATCH 同级。

于是"桶变大"这件事在 CI 里是一次响亮的失败，而不是一个没人看的数字。
这与 §4.3 第 3 点的总体性闸门是同一条理由：**豁免必须被枚举，不能被计算。**

### 4.5 账本覆盖不到的那一部分：14 个 `emit = "none"` 的 `RuntimeState` 行

出处账本按**发出行**建表，所以它结构上**看不见**这 14 行。这个缺口必须显式记账
（lead 要求），而不是靠人记得。这 14 行由 commit 写入、永不进快照，
唯一的防线是 `yl_runtime_bridge_test` 对**提交后全局值**的断言：

| map 行 | 旧全局 | 断言者（提交 `a5a6e15` 之后） |
|---|---|---|
| `runtime.gauss.djacb_mass` | `element%egaus(2)%djacb` | `check_landed`（既有） |
| `runtime.gauss.gpcod_mass` | `element%egaus(2)%gpcod` | `check_landed`（既有） |
| `runtime.element.elcod_f` | `element%field%elcod_f` | `check_landed`（既有） |
| `runtime.element.tload` / `eload` / `rload` | `element%field%*` | `check_landed`（既有，只断言分配与长度） |
| `runtime.vectors.delitfi` / `deltafi` | `global_var.*` | `check_landed`（既有，只断言分配与长度） |
| `runtime.cursor.line_load_block` / `line_temp_block` | `global_var.*` | `check_landed`（既有，只断言长度） |
| `runtime.topology.unode_np_unode` | `group%unode%np_unode` | **`a5a6e15` 新增** + 反例 |
| `runtime.topology.unode_patch_nod` | `group%unode%patch_nod` | **`a5a6e15` 新增**（连同 `patch_sta`/`patch_load`）+ 反例 |
| `runtime.cursor.lineload` | `global_var.lineload` | **`a5a6e15` 新增** + 反例 |
| `runtime.cursor.linet` | `global_var.linet` | **`a5a6e15` 新增** + 反例 |

前 10 行本来就被覆盖；**后 4 行在 `a5a6e15` 之前没有任何断言**，而它们恰好是折叠步 3
要重写的那段 `s_group`/`unode` staging 循环碰得到的。丢掉 `null_unode` 就会在真实全局里
留下一个**未初始化指针**（`associated()` 是未定义行为，正是 `null_group` 自己注释点名的危险），
而 `yl_runtime_bridge_test`、`yl_runtime_selftest`、影子差分、L3-b 的 64 行**全部保持绿色**。
这与模块头记录的 `trans` 缺陷同类：**一道守卫覆盖的对象不是它声称覆盖的对象。**

`a5a6e15` 补上了这 4 行的断言，并为每一条配了一个能让它变红的反例
（毒化真实全局 → 断言谓词返回 `.false.` → 复原）。

#### 4.5.1 这四个守卫**能证明什么、不能证明什么**（v3 更正）

lead 独立做了一次我没做的对照：**不是改错值，而是把 commit 里的写入整行删掉**
（`yl_runtime_commit.f90:307`）。结果我已复现：

| 对照 | 结果 |
|---|---|
| `s_group(ig)%unode(i)%np_unode = 7_ink`（**写错值**） | **BAD**，守卫响 |
| 整行删除（**漏写**） | **全绿 720/720**，连"restored to 0 by a recommit"也过 |
| 去掉 `lineload` 的发布（`:353`） | **BAD** ×2，守卫响 |

**根因不是漏加检查，是这两类行的存储形态不同：**

- `lineload` / `linet` 是**持久的标量全局**。毒化留在原地，漏写就恢复不了 →
  "投毒→重提交→值必须回来"是一条真性质。**这两个守卫覆盖漏写。**
- `unode%np_unode` 是**每次提交都重新分配**的派生类型数组分量。commit 用 `move_alloc`
  换上全新的 `s_group`，**重分配本身抹掉了投毒**；`unode_elements`（`Global.f90:263-271`）
  没有默认初值，未定义内存恰好读作 0，于是在**毫无写入**的情况下恢复检查照样通过。
  **这个守卫只覆盖"写错值"，不覆盖"漏写"。**
- `patch_nod` / `patch_sta` / `patch_load` 同理，而且更糟：漏掉 `null_unode` 之后
  `associated()` 本身就是未定义行为，**守卫连安全求值都做不到**，它的 `.false.` 与 `.true.`
  都不构成证据。

所以这三个守卫的准确表述是：**它们把"写错了"从静默变成红线，不能把"根本没写"从静默变成红线。**
后者需要 §5.5 的机制，而那属于折叠本身，不属于测试。这一段是本设计对
"`a5a6e15` 已经把盲区补上了"这个说法的自我更正 —— 它补上了一半。

测试从 581/581 变为 720/720，0 失败。

## 5. 会出什么问题，怎么被发现

### 5.1 最大风险：释放路径 —— 而且 v2 承认它**没有仓库内机制**

模块头已经把这类缺陷的形状写死了：*"a list that must be maintained is honest about needing
maintenance; a description that quietly covers less than it says is not"* —— 第一版 W4 守卫
描述了"记录数组"这一类却只枚举了六个里的五个，`trans` 那道门是敞开的。

折叠会把这份名单的规模乘上去，分成**两半**，而这两半的可机检程度完全不同：

**上半：8 个可分配全局**（`coord`、`props`、`appear_process`、`matno_process`、
`average_appear`、`tcurvegravity`、`factg`、`uinitial`）。
它们出现在三处：W4 守卫的名单、`move_alloc` 段、`commit_release`。

**下半：至少 8 类新的指针目标**（`group%list`、`group%dof(:)`、`group%dof%listdof_f`、
`element%field(1)%lnods_f`、`tcurves%ttime_curve`、`tcurves%dfact_curve`、
`props%mechanical`、`props%mechanical%solid`）。**泄漏住在这一半。**

#### 5.1.1 v1 的"把名单改成构造"只覆盖上半，而且连上半也没有真正锁死

v1 建议"把待发布的全局收进一张显式清单，守卫/`move_alloc`/`commit_release` 三处都走这张表"。
复核者的反驳成立，我接受：

1. **探针表本身仍然是手抄的。** Fortran 没有反射，`move_alloc(s_X, X)` 必须字面写出名字对，
   无法由表生成。加第九个可分配全局时，表和 `move_alloc` 段仍然要人同时改。
   **"三处一起变或一处都不变"这句话不成立**；实际效果是把三份名单压成两份。
2. **`commit_release` 根本不是一张扁平名单**，它是一次嵌套的指针目标遍历
   （`yl_runtime_commit.f90:397-448`）。一张全局**名字**表表达不了
   `element%field%{ldofs_f,elcod_f,tload,eload,rload}` 这种结构，
   而下半的泄漏正是住在这里。`props(i)%mechanical%solid` 这条两级链会把这块面积再放大。
3. **现成的守卫也不覆盖 `commit_release`。** §5.2b 的 `check_guard_names_match`
   只把 **W4 拒绝消息**与测试自己的 `NAMES` 绑在一起。一个全局加进了 W4 名单和
   `move_alloc` 段、**忘在 `commit_release` 里**，W4 解析照过，
   T02 重复提交在进程内也看不出来（模块头："a process cannot observe its own leaks"），
   **全部测试通过**。
4. **检查点 ★ 的"逐个 grep"是人工复核，不是机制** —— 和当年放走 `trans` 的是同一种东西。

#### 5.1.2 因此，诚实的写法

- **上半**：仍然做那张表（把三处压成两处是真改进），但设计**不再声称**它让漂移不可能，
  只声称它把漂移面减半。`check_guard_names_match` 的解析必须随名单一起扩。
- **下半**：**明说仓库内没有机制**。唯一的检查是外部工具。
- 因此 **ASan / valgrind 不是建议，是这条路线成立的必要条件**：
  它是下半唯一的检查手段。见 §5.4。

#### 5.1.3 一个能覆盖下半一部分的低成本补充（新增建议）

`commit_release` 之后，全局应当处于"全部未分配 / 全部未关联"的状态。
可以给 `yl_runtime_bridge_test` 加一条**释放后的总体性断言**：
遍历它知道的每一个全局与每一层指针分量，断言 release 之后无一 `allocated` / `associated`。
它抓不到泄漏（泄漏是进程看不见的），但它**能抓到"忘在 `commit_release` 里"这一类漏项**
—— 因为一个没被释放的分量在 release 之后仍然 `associated`。
这不能替代 ASan，但它把上面第 3 点的那个具体缺口从"全部测试通过"变成"一条红线"。

### 5.2 折叠会不会打破 L3-b 现在全绿的 46 行？会，有三条具体路径

1. **同一条 staging 循环里的相互干扰。** B 类的 37 行与 46 行里的 24 行住在同一批记录里
   （`element` / `group` / `prescrib` / `tcurves`）。两个具体雷：
   - `group%unode(i)%np_unode` 今天被显式置 0 且 `patch_nod` 保持 null，`verify_registered`
     会拒绝一个分配了 `patch_nodes` 的 runtime；折叠 `group` 的 21 个分量时很容易顺手动到它。
   - `element%matno` 与 `group%matno`：map 明说 `.glb` 组头里的 `matno` 在 `Fem.f90:1717`
     被**就地覆盖**，`sections.material_header` 是通过 `element%matno` 反构出来的。
     若折叠把组头原值写进 `element%matno`，`sections.material` 与 `sections.material_header`
     会一起错，而两者在 golden deck 上恰好相等 —— 错了也可能看不出来。
2. **extent 的第二个推导源。** 今天 `npoin/nelem/ngroup/ndimn/mdofn/cdofn/ntotv` 全部从
   `runtime` 推出。折叠拿到 `problem` 之后，从 `count(problem%mesh%nodes)` 再推一次是最自然的写法，
   **也正是不变量 4 禁止的事**。规则：**extent 仍然只从 runtime 推**；ProblemState 那一半
   只允许**断言一致**，不允许覆盖。两者不一致时 commit **失败**（`INV-COMMIT-TOTAL`），
   不许挑一个。
3. **kind 转换。** 新增的字符串分量（`group%kname/%name/%class/%fieldid/%special/%sptype`、
   `probn` `character(200)`、`outplot` `character(20)`、`type_*` `character(50)`）是今天
   commit 完全没有的一类交叉。定长字符赋值会静默截断或补空格，而比对是 `trim()` 后的 exact。

**捕获这三类的测试**（都已存在，不需要新建判据）：
- `yl_runtime_bridge_test`（L3-b 的那 64 行逐值比对 + T02 属性）—— 这是 46 行的所有者，
  **每折叠完一个记录数组就跑一次**，不要攒到最后；
- `yl_runtime_selftest`（108/108，含 B-cov 双射与 12 个分配站点的 `fail_at` 走查）；
- `tools/build.sh` 里的反向双射交叉检查（规则表 ↔ map）；
- `tools/yl_shadow_diff.py --old-vs-old` 380/380 与阴性对照 —— 证明夹具没被折叠带偏；
- **提交 `a5a6e15` 新增的 4 条盲区断言 + 5 个反例**（§4.5）—— 专门守 `s_group`/`unode`
  这段重写，是步 3 唯一能看见 `patch_nod` 变成未初始化指针的东西。

### 5.2b 折叠会让两个现有测试**按设计**变红 —— 这是特性，不是回归

这两处必须和折叠在同一个提交里改，改法要写进提交信息，否则复核时无法区分"按计划失效"和"折坏了"：

- **`yl_runtime_bridge_test.f90` §5 `group_sentinels`（:657-682）** 用哨兵值断言
  `nmats`、`nblks`、`restart`、`ttime` **未被 commit 触碰**，注释写明理由是
  "they belong to the ProblemState half ... out of scope until M4-01"。
  折叠的 C2 类正好写 `nmats`、`nblks`、`restart` 三个。**这一节要从"未被触碰"翻转成
  "被写成 ProblemState/默认值声明的那个值"**，剩下的 `ttime` 继续做哨兵。
- **`yl_runtime_bridge_test.f90` §6 `group_foreign_allocation_guard`（:703-）** 不止走六道门，
  它还**解析 W4 拒绝消息里的 "one of ... or ..." 子句**，断言它恰好、按序命名这六个。
  W4 名单一旦按 §5.1 扩张，这个解析必然失败 —— 这正是它存在的意义
  （"Add a seventh global to the guard without adding it to NAMES ... and that parse --
  not a maintainer's memory -- is what fails"）。**它是 §5.1 那份名单的现成守卫，
  扩张名单时连它一起改，不要绕过它。**

### 5.3 次级风险

- **`props` 的两级指针**：`props(i)%mechanical%solid` 要新建两级目标。若 `commit_release`
  只释放 `props(:)` 而不先释放两级目标，就是一次每提交一次泄漏一次的确定性泄漏。
- **`appear_process` 的下标下界**：`appear_process(1:ngroup, 0:nblks)`，列 0 是初始态且**参与比对**
  （map note，`Fem.f90:1719-1720` 会消费它）。用 1-based 的 `allocate` 会静默错位一列。
- **`uinitial`**：见 §1.6，需要 lead 的一个决定。

---

### 5.4 出口条件（不是建议）：外部内存工具 —— 以及它今天跑不起来

§5.1.2 已经说明：释放路径的下半（嵌套指针目标）在仓库内**没有**检查手段，
而 `props(i)%mechanical%solid` 这条两级链把这块面积放大了一个量级。

**本设计把外部内存工具定为 M4-01 折叠的出口条件**：

> 在两个 golden 算例上，跑 commit → commit → release → commit → release 序列，
> **无泄漏、无 use-after-free**，结果与命令入报告。这一条不通过，折叠不算完成。

**但它今天跑不起来，原因已查明并可一行修复。** 在**干净工作树**上实测：

```
tools/build.sh runtime-bridge sanitize   ->  rc=6
SUMMARY: MemorySanitizer: use-of-uninitialized-value
         ... in __kmp_affinity_insert_numa_nodes(kmp_topology_t*)
```

这是 Intel OpenMP 运行时（libiomp）内部的 MSan 误报，发生在进入仓库任何一行代码**之前**，
与被测代码无关。加一个环境变量即可绕过：

```
KMP_AFFINITY=disabled build/<out>/yl_runtime_bridge_test   ->  PASS: 720/720
```

**请 lead 决定**（`tools/build.sh` 现在是你的）：把 `KMP_AFFINITY=disabled`
（`OMP_NUM_THREADS=1` 已经在别处这么做了）加进 `sanitize` 剖面的运行环境。
在此之前 `sanitize` 剖面对这个二进制是不可用的，出口条件也就无从满足。

另注：`sanitize` 用的是 `-check uninit`（MemorySanitizer），不是 AddressSanitizer；
泄漏检测需要另外的 `-fsanitize=address`（含 LeakSanitizer）或 valgrind。
两者不能互相替代：MSan 查未初始化读，LSan/valgrind 查泄漏，而 §5.1 的下半要的是后者。

### 5.5（v3 新增，lead 处方）Staging 投毒：让"漏写"变成红线

#### 5.5.1 为什么必须有它：三个剖面全部漏检，实测

lead 指出 `a5a6e15` 的 `np_unode` 守卫抓不到**漏写**，我复现并把范围扩到了整个工具链。
对照方式是把 `yl_runtime_commit.f90:307` 的写入整行删掉，然后逐剖面跑
（每次跑完还原，`git status` 干净）：

| 剖面 | 编译选项要点 | 漏写被抓到吗 |
|---|---|---|
| `release` | `-O2` | **否** —— `PASS: 720/720`，0 BAD |
| `strict` | `-init=snan,arrays -fpe0 -check bounds,pointers` | **否** —— `PASS: 720/720`。`-init=snan` 只作用于实型 |
| `sanitize` | `-check bounds,pointers,uninit`（MemorySanitizer） | **否** —— `KMP_AFFINITY=disabled` 绕过 libiomp 误报后 `PASS: 720/720`，**0 条 MSan 报告** |

**仓库里没有任何一个现成机制能看见"折叠漏写了一行"。** 这不是推理，是三次实测的排除法。
对照组（`lineload` 的发布被删）在 `release` 下就是 **BAD**，说明夹具本身没有失灵 ——
区别在存储形态，见 §4.5.1。

#### 5.5.2 处方

**staging 缓冲在分配之后立刻投毒，真实赋值再覆盖它。**

```fortran
allocate (s_group(s_ngroup))
call poison_group(s_group)          ! 每个整型分量 = STAGE_POISON_I, 每个实型 = NaN
...                                 ! 真实赋值覆盖
```

- 赋值在 → 发布出去的是真值 → 绿；
- 赋值被漏掉 → 发布出去的是哨兵 → 影子差分、`bridge_test` 的逐值断言**立刻红**。

这把"未定义内存恰好读作 0"变成"已定义的哨兵"，于是**每一个**新增行的漏写都可检测，
不必逐行手写守卫去追。折叠要新增 **89 行**"未定义值"（§2），它们全部共享这个性质，
所以这条是**机制**，不是逐行守卫的替代品可以省掉的优化。

**哨兵取值**：整型用 `huge(0_ink)`，实型用 signalling NaN（与 `strict` 剖面的
`-init=snan` 同一个约定），字符用一个不可能出现的填充。选 `huge` 而不是 0 或 −1，
理由与 ADR-0002 的绝对值哨兵禁令一致：它必须是一个**任何合法路径都产生不了**的值，
而 0 和 −1 都可能是合法的。

**三条约束，缺一不可：**

1. **哨兵绝不能被 legacy 看见。** 它只存在于 staging 局部量里；
   到 write 段之前必须已被真实赋值全部覆盖。**覆盖不全本身就是缺陷**，
   这正是这个机制要暴露的东西。
2. **RESERVED 行是例外，而且必须显式列出。** `element%field%tload/eload/rload`、
   `delitfi`/`deltafi` 按账本就是"已分配、内容未定义、不许读"。它们**应当**带着哨兵发布
   —— 那比带着 0 发布更诚实（0 会被误读成一个值）——
   但每一个这样的行都要在出处账本里是 `RESERVED`，且不在任何比对里。
   **哪一行带哨兵出门，必须是账本说了算，不是遗漏说了算。**
3. **投毒函数与 `null_*` 系列必须同源。** 现在的 `null_element` / `null_element_field` /
   `null_gauss` / `null_group` / `null_unode` / `null_prescrib` / `null_tcurve`
   已经逐类型枚举了指针分量并在注释里记了数目；投毒函数要枚举**非指针**分量，
   写在同一个位置、同一套注释纪律下。一个 legacy 类型新增分量时，
   两边一起暴露缺口，而不是只暴露一边。

#### 5.5.3 它与 §5.1.3 的分工

两条机制盖的是**不同**的洞，都要：

| 机制 | 盖住什么 | 盖不住什么 |
|---|---|---|
| staging 投毒（§5.5） | **漏写**一个 staging 分量 | 释放路径漏项、泄漏 |
| 释放后总体性断言（§5.1.3） | **忘在 `commit_release` 里**（release 之后仍 `associated`/`allocated`） | 真正的泄漏（进程看不见） |
| 外部工具（§5.4） | 泄漏、use-after-free | 语义错误 |

---

## 6. 实施顺序（v2 修订：检查点挪到能真跑一次差分的地方）

v1 的步 2 判据"第一次产出完整的 162 行快照"是**假的**（lead 必改项 ②）：步 2 只写 24 个
确定中止里的 22 个，剩下 2 个（`mesh.elements.nodes`、`sections.material_header`）属 B 类，
所以步 2 之后 dump **仍然中止**，只是中止点从 `coord`（`yl_state_dump.f90:119`）
移到 `element%field(1)%lnods_f`（`:135`）。检查点 ★ 的差分那一条在步 2 无法执行。

复核给了两条改法。**选把那 2 行提前**，理由是设计自己的意图就是"检查点要能真跑一次差分"；
代价（步 2 要碰 `element` / `group` 记录）用步骤 **2b** 单独隔开，不与 C1 混在一个提交里。

| 步 | 内容 | 触碰的全局 | 通过判据 |
|---|---|---|---|
| **0** | **已完成（`a5a6e15`）**：补上 4 行 `emit = none` 盲区的提交后全局断言 + 每条一个反例（§4.5） | 无 | 581/581 → **720/720**，0 失败 |
| **0b** | **staging 投毒机制**（§5.5）：`poison_*` 系列 + 三条约束，先只作用于**今天已有**的 staging（不新增任何行）。这一步的验收就是它自己的对照：删掉 `s_group(ig)%unode(i)%np_unode = 0_ink`，`bridge_test` 必须**变红** —— 今天在三个剖面下都是绿的 | 无 | 对照红、正常绿；`720/720` 不降 |
| **1** | 账本骨架：从 map 生成行清单 + commit 侧出处声明表 + VERIFY 段总体性闸门 + `provenance.txt` 旁挂 + `NOT_MIGRATED` 桶的**封闭**检查（§4.4）；**一个全局都不新写**，全部 120 行先声明为 `COMMIT_NOT_MIGRATED` | 无 | `bridge_test` / `selftest` 逐条与今天相同；`build.sh` 双射与溯源门禁绿 |
| **2** | 签名改 A，全部调用点跟改（今天 11 个；以 `grep -rn 'call commit_legacy_globals' src/` 当次结果减去 `yl_adapter_bridge_test.f90:18` 的注释为准），**不新增任何写入** | 无 | 同上；差分行为与步 1 相同 |
| **3** | **C1 类 21 行 + `uinitial`**：8 个可分配全局的 staging / `move_alloc` / `commit_release` / W4 名单 / `check_guard_names_match` 的解析，**五处一起改** | 8 个新全局 | `bridge_test`、`selftest` 全绿；释放后总体性断言（§5.1.3）通过 |
| **3b** | **把 2 个确定中止的 B 类行提前**：`element%field(1)%lnods_f`（`mesh.elements.nodes`）与 `group%list` + `group%nelgroup`（`sections.material_header`） | 无新全局，新指针目标 2 类 | **这一步才第一次让新路径产出完整的 162 行 `model_ready` 快照** |
| **★** | **CHECKPOINT —— lead 复核后才继续** | | 见下 |
| **4** | **B 类其余 35 行**：折进 `element` / `group` / `prescrib` / `tcurves` 循环。**一个记录数组一个提交**，每个之后跑 `bridge_test` | 无新全局，新指针目标 4 类 | 每个记录数组之后 L3-b 的 64 行仍 MATCH=64 / MISMATCH=0；§4.5 的 4 条盲区断言仍绿 |
| **4b** | **`.tem` 解析器**（§1.7.1）：5 条 title + 4 个计数，形状照抄 `yl_adapter_load.f90` 的 `nedge`/`nplgroup`。属 `src/adapter/**`，需与 dev-l2b 协调所有权 | 无 | 两个 golden deck 上 `adapt_legacy_deck` 仍成功；四个温度计数随即成为 `FROM_GATE` |
| **5** | **C2 类 46 行 + 13 个 `not_migrated` 标量 + §1.7 的 7 个闸门蕴含行**：一段纯标量 staging。`group_sentinels` 在这一步按设计翻转（§5.2b） | 59 个标量全局 | 影子差分：162 行判据面 MISMATCH=0；`NOT_MIGRATED` 桶**恰好**是 §1.6.3 + §1.7 决定的那 ≤8 行，多一行少一行即失败 |
| **6** | **出口条件**：ASan / valgrind 跑 commit→commit→release→commit→release（§5.4） | — | 无泄漏、无 use-after-free；命令与结果入报告 |

**步 5 的前置**：§1.8 的 `nsmat` map note 错误已由 `0646de3` 修好；
仍待 lead 裁定的是 §1.6.3 的 `stab_matde` 与 §1.7.2 的 `npoinb` / `nsmat`
（`delgroup` 与四个温度计数已有明确做法：走闸门 / 写 `.tem` 解析器）。
裁定之前 `NOT_MIGRATED` 桶的期望清单无从入库，步 5 不能收尾。

**每一步的固定动作**（`21a5c98` 之后）：`tools/build.sh runtime-bridge`
与 `tools/build.sh adapter` **两个都跑**；并行构建时必须加 `--out` 指到自己的目录
——共用 `build/runtime-bridge/release/obj` 会把 `Global.mod` 写坏，
并伪装成 legacy `Material.f90` 编译失败。

### 检查点 ★ 上 lead 要复核的六件事

1. `bridge_test` 与 `selftest` 逐条与折叠前一致（**46 行没有被步 3/3b 带偏**），
   且 §4.5 的 4 条盲区断言与 5 个反例仍在且仍绿；
2. `commit_release`、W4 守卫名单、`move_alloc` 段**三处**都覆盖了新增的 8 个可分配全局；
   §5.1.3 的"释放后总体性断言"已经落地并通过 —— **这是能机检"忘在 release 里"的唯一一条**，
   §5.1 已经说明纯 grep 复核不是机制；
3. 影子差分**首次跑出完整的 162 行快照**，且**没有一行 MISMATCH**：
   此时 B 类其余 35 行与 C2 类还没写，它们必须全部落在 `NOT_MIGRATED` 桶里，
   任何一条 MISMATCH 都说明出处账本漏了行；
4. `NOT_MIGRATED` 桶的封闭检查确实在跑（故意加一行 / 删一行，差分必须失败）；
5. `group_sentinels` **原样还绿** —— `nmats`/`nblks`/`restart` 要到步 5 才写，
   它在这一步变红就说明写超了范围；`check_guard_names_match` 则**应当**已随名单扩张而改；
6. extent 仍然只有一个推导源（`grep -n 'problem%mesh%nodes' src/runtime/yl_runtime_commit.f90`
   应当只在断言里出现）。

---

## 7. 本文没有建立什么

- **只实施了一件事，就是提交 `a5a6e15`**（§4.5 的 4 条盲区断言 + 反例）。
  `src/runtime/yl_runtime_commit.f90`、`yl_runtime_build.f90`、`yl_runtime_types.f90`
  与 `src/adapter/**` 一行未动。本文不构成"折叠已设计完毕可以照抄"的承诺：
  §5.2 的三类干扰只有在真写的时候才能逐个确认。
- **没有验证 ProblemState 侧的值是否正确。** 本文只论"值怎么从 owner 对象到达旧全局"，
  不论适配器读得对不对 —— 那是 L2-a/L2-b 和 R27 的事。
- **§1.6.2 / §1.7 的闸门表读的是 HEAD 的 `src/adapter/**`（`git show`），不是工作树**
  —— dev-l2b 持有 `src/adapter/**` 且处于不可编译状态。若 L2-b 改动了任何一条
  `reject_*`，`FROM_GATE` 的蕴含关系必须重新逐行核对，本表不自动成立。
- **没有触碰 `phase_ready` / `increment_ready`。** 那 28 行不在 `model_ready`，与本折叠无关。
- **没有替 map 所有者决定任何事。** §1.6.3 / §1.7 的 8 行给了三条路和推荐，
  §1.8 的 `nsmat` note 错误由 map 所有者修。
- **没有证明折叠之后影子差分会全绿。** 本文只证明了它今天为什么产不出快照，
  以及要产出快照必须写哪些行。
- **没有推翻 R27。** 判据面仍然只覆盖 map 登记过的状态；折叠做到 100%，也不能说
  "reader 站点已全覆盖"。

## 8. 复现本文的每一个数

```bash
cd /home/huijun/HSTAR_Next/hstar-evolution

# 239 / 84 / 77 / 46 / 32，以及 162 个 emit != none
python3 -c "
import tomllib,collections
d=tomllib.load(open('docs/m2/state-field-map.toml','rb'))
f=[x for x in d['field'] if x['checkpoint']=='model_ready']
print(len(f), collections.Counter(x['owner'].split('.')[0] for x in f))
print('emitted', sum(1 for x in f if x.get('emit')!='none'))"

# §2 的 24 / 5 / 89 / 2：逐行读守卫，不要只看容器
sed -n '83,88p'   src/state/yl_state_adapters.f90   # need_count: 只在 n < 0 时中止
sed -n '264,282p' src/state/yl_state_adapters.f90   # sections.material_header: 无条件 ne<1 -> 确定中止
sed -n '376,392p' src/state/yl_state_adapters.f90   # mesh.sets.elset: need_count + if(ne>0) -> 不确定
sed -n '133,145p' src/state/yl_state_dump.f90       # mesh.elements.nodes: 无条件 associated -> 确定中止

# §1.6.2 的闸门表（读 HEAD，不读工作树）
git show HEAD:src/adapter/yl_adapter_fem90.f90 | sed -n '188,205p;222,236p'
git show HEAD:src/adapter/yl_adapter_model.f90 | sed -n '300,302p;376,400p;441,462p;761,770p;824,834p'
git show HEAD:src/adapter/yl_adapter_load.f90  | sed -n '420,455p;495,515p'

# §1.7 温度计数在产品路径上没有读取者（harvest 是 oracle，不是产品路径）
git show HEAD:src/adapter/yl_adapter_harvest.f90 | sed -n '1,15p;303p'
git show HEAD:src/adapter/yl_adapter_driver.f90  | grep -c harvest   # 0

# §1.8 nsmat：map note 说 0，冻结基线和 deck 都说 1
python3 -c "
import json
for c in ('cooks_membrane','lame_cylinder'):
    d=json.load(open(f'cases/golden/static_2d/{c}/reference/state/model_ready/control.json'))['fields']
    print(c, d['derived.counts.nsmat']['values'])"
sed -n '10,11p' cases/golden/static_2d/cooks_membrane/legacy/1.glb

# §3.1 ProblemState 不能承载 not_migrated / derived 行
grep -n 'expected @m5-only:<reason> | @optional | @required' tools/yl_problem_check.py

# 三道否决选项 B 的闸门
grep -n "not a model_ready RuntimeState row" tools/yl_state_map.py     # R3
grep -n "has no producing" tools/yl_state_map.py                       # R5（消息跨行，别 grep 整句）
grep -n "runtime_status_count(runtime) /= build_rule_produced_count"   \
     src/runtime/yl_runtime_commit.f90                                 # verify_registered

# §4.5 / 步 0：盲区断言与反例
grep -n "unode_np_unode_all_zero\|unode_patch_pointers_all_null\|group_blind_spot" \
     src/runtime/yl_runtime_bridge_test.f90
tools/build.sh runtime-bridge   # PASS: 720/720（此前 581/581）

# §4.5.1 / §5.5.1 三剖面漏检的对照（每次跑完还原 yl_runtime_commit.f90）
#   删掉 src/runtime/yl_runtime_commit.f90:307 的 `s_group(ig)%unode(i)%np_unode = 0_ink`
tools/build.sh runtime-bridge          --out build/probe-rel   # PASS 720/720（漏检）
tools/build.sh runtime-bridge strict   --out build/probe-str   # PASS 720/720（漏检）
tools/build.sh runtime-bridge sanitize --out build/probe-msan  # 编译后手动跑：
KMP_AFFINITY=disabled build/probe-msan/yl_runtime_bridge_test  # PASS 720/720，0 条 MSan 报告
#   对照组：删掉 :353 的 lineload 发布 -> release 下即 BAD ×2

# §5.4 sanitize 剖面在干净树上就跑不起来，且一个环境变量即可绕过
tools/build.sh runtime-bridge sanitize --out build/base-msan   # rc=6, __kmp_affinity_insert_numa_nodes
KMP_AFFINITY=disabled build/base-msan/yl_runtime_bridge_test   # PASS: 720/720

# §1.7.1 legacy 在 static_2d 上确实读 .tem
sed -n '661,662p' legacy/yl/Global.f90     # open(tunit, ... '.tem', status='old')
sed -n '1899p'    legacy/yl/Fem.f90        # call boundt   -- 无 guard
sed -n '126p;154p;246p;310p' legacy/yl/Temper.f90   # 四个计数的 read 语句
grep -n 'TEM.boundt.\(temp_surface_count\|temp_edge_count\|temp_elgroup_count\|pipe_count\)' \
     docs/m1/reader-inventory.toml
cat cases/golden/static_2d/cooks_membrane/legacy/1.tem

# §1.7.2 npoinb 在 legacy 里从不被消费（只有读/打印/范围检查三处）
grep -an 'npoinb' legacy/yl/*.f90 | grep -v 'integer'

# 实施时的调用点数，以当次结果为准。今天 grep 命中 12 条：
#   yl_adapter_bridge_test.f90  2 条，其中 :18 是注释 -> 真实调用 1
#   yl_adapter_shadow.f90       1
#   yl_runtime_bridge_test.f90  9（`a5a6e15` 之前是 6）
# 即今天真实调用点 11 个；§3 表里的 8 是 `a5a6e15` 之前的数（9 命中 − 1 注释）。
grep -rn 'call commit_legacy_globals' src/
```
