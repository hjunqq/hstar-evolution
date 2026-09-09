> **状态：须修改后实施（2026-09-09）。本文若干数字已被证伪，修订前不得据以实施。**
>
> 独立对抗性复核见 `docs/m4/L2c-fold-review.md`。主干结论（方案 A、折叠不能分批、
> 账本轴取「出处」、最大风险在释放路径）经复核未被推翻，保留；以下各点**以复核报告为准**：
>
> - **§2 的 59/59/2 是错的**，正确值 24 / 5 / 89 / 2。根因是把「容器有守卫」误当「分量有守卫」。
>   其中 5 行的失败模式本身不稳定（`n = <未定义标量>; if (n>0)`，n 恰为 0 时不中止而发长度 0 记录），
>   §2 的二分法在它们身上不成立。
> - **§6 步 2 的通过判据不成立**：步 2 之后 dump 仍中止，只是从 `coord` 移到 `lnods_f`。
> - **调用点是 8 不是 9**；§3 推荐②/§6 步 1 的「2 个」与 §3 表自相矛盾。
> - **§1.6 的取值来源曾被 map 缺陷阻塞**，该缺陷已于 `a8d4646` 修复。
> - **那 14 行不是 legacy 默认值，是 deck 供的输入字段**（`source` 全部指向
>   `INP.FEM90.run_control` / `GLB.global_data.*`）。首选做法是让适配器真的去读它们，
>   而非钉常量；`DEFAULTED` 标签若无封闭的 `NOT_MIGRATED` 桶，只是把假绿换成假豁免。
> - **实施前须先补盲区守卫**：`group%unode%{np_unode,patch_nod}` 与
>   `runtime.cursor.{lineload,linet}` 目前无任何断言覆盖（详见复核报告 (b)）。

# M4 L2-c：把 ProblemState 那一半折叠进 `commit_legacy_globals` 的单次 staging —— 设计提案

> 本文是**设计提案，不是实施记录**。截至写作时 `src/runtime/**` 未被本任务改动一行；
> 本文唯一新增的文件就是它自己。所有行数与行 id 均由 `docs/m2/state-field-map.toml`
> 程序化枚举得到（命令见 §8），不是估算。

## headline

| 项 | 数 |
|---|---|
| `model_ready` 全部行 | 239 |
| 其中 `emit ≠ none`（影子差分的判据面） | 162 |
| 今天已有仓库侧写入者 | **42** |
| 今天没有写入者 | **120** |
| 其中：不写就让 `yl_state_dump` **中止**（有 `state_fail` 守卫） | **59** |
| 其中：不写就以 **Fortran 未定义初值**被当作状态发出 | **59** |
| 其中：适配器自行合成、不需要任何全局 | **2** |

**结论先说三句：**

1. **推荐 A：把 `commit_legacy_globals` 的签名改成同时接收 `problem_state_t` 与 `runtime_state_t`。**
   B（让 `build_runtime` 把 ProblemState 的值搬进 `runtime_state_t`）会撞碎 map ↔ `RuntimeState`
   的双射闸门，那正是不变量 4 禁止的"第二处所有权语义"。理由见 §3。
2. **折叠必须是全覆盖的，没有"先折一半"这个选项。** 59 行不写会让 dump 中止（`coord` 只是其中
   第一个），另外 59 行不写会把**未定义内存**当成状态发出去 —— 后者比错值更糟，因为它不可复现。
   所以不变量 3 的账本轴不是"写没写"（写是被 dump 的总体性强制的），而是**"这个值是从哪来的"**。见 §4。
3. **单个最大风险不是 46 行回归，是释放路径。** 折叠会给 `commit_release` 新增 8 个可分配全局
   和至少 8 类新的指针目标（`props%mechanical%solid` 那条链最重）。W4 守卫的名单必须在**同一个提交里**
   同步扩张，否则模块头里 `trans` 那个"描述覆盖得比它说的少"的缺陷会以更大的规模重演。见 §5。

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
- **14 行** `emit ≠ none`，**在影子差分的判据面里**：
  `control.run.{restart,relis,adina}`、
  `control.glb.{nlayer,block_stab,nbackf,ebody,ninit,uinitial,state_change,bparameter,stab_matde,nlinks,ntrans}`。
  其中 **`control.glb.uinitial` 是 `allocatable`**（`Global.f90:186-187`，`allocate(...uinitial(nblks)...)`
  在 `:965`），dump 在 `yl_state_dump.f90:491` 对它有 `state_fail` 守卫 ——
  **不分配 `uinitial`，新路径就产不出 `model_ready` 快照，和 `coord` 完全同一类阻塞。**
  另外 13 行是标量：12 个在两个 golden deck 上都是 0（与 Fortran 未初始化内存**碰巧**相等就会被
  记成 MATCH），`control.glb.stab_matde` 在两个 deck 上都是 **99999**（map 的 note：一个禁用哨兵），
  它一定会差。

**这 14 行是本设计里我不能替 lead 决定的一处。** 两条路：

- **(i)（推荐）** 折叠照写，取值来自 map 每行自己的 `reason`/`note` 记录的 legacy 默认值，
  并在 §4 的账本里标成 `DEFAULTED` —— 账本因此可以把它们从 MATCH 统计里剔除，
  "写了"与"迁移了"不会被同一个数字表示。
- **(ii)** 改 map，把这 14 行降为 `ignore` / `emit = "none"`。这是 map 所有者的决定，不是我的；
  而且它会缩小判据面，需要 lead 权衡。

---

## 2. 一个先于 A/B/C 的观察：折叠的总体性是被 dump 强制的，不是可选的

把 120 个无写入者的行按"不写会发生什么"重新切一刀（逐行 grep `yl_state_dump.f90` /
`yl_state_adapters.f90` 的 `state_fail` 守卫得到，不是推断）：

| 不写的后果 | 行数 | 组成 |
|---|---|---|
| `yl_state_dump` 中止（有分配/关联守卫） | **59** | B 类 37 + C1 类 21 + `control.glb.uinitial` 1 |
| 未定义初值被当作状态发出 | **59** | C2 类 46 + 13 个 `not_migrated` 标量 |
| 无事发生 | **2** | D 类 |

**这否掉了"先折叠一部分、剩下的以后再说"这个路线。** 前 59 行少写任何一行，L3-c 的判据面就还是
产不出来（只是中止点从 `coord` 换成别的）；后 59 行少写任何一行，快照里就有一段**不可复现**的字节 ——
它可能碰巧等于 legacy 的值（记成 MATCH，一条假证据），也可能不等（记成 MISMATCH，一条假缺陷），
而两次运行还可能给出不同答案。**错值至少是确定的；未定义值连"错"都不稳定。**

所以：**折叠必须一次覆盖全部 162 个 `emit ≠ none` 的 `model_ready` 行。**
这也直接决定了不变量 3 的答案形状（§4）。

---

## 3. 岔路：A / B / C

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
| 其他 | 签名变更 → **9 个调用点，3 个文件**（`src/adapter/yl_adapter_shadow.f90` 1 处、`src/adapter/yl_adapter_bridge_test.f90` 2 处、`src/runtime/yl_runtime_bridge_test.f90` **6 处**）。三个文件里 `problem_state_t` 都已经在手（`yl_runtime_bridge_test.f90:116` 自己调 `prepare_problem`），但 §2/§3/§5/§6 那四个测试子程序今天只收 `rt`，需要把 `problem` 一起穿进去 —— 机械但不是零。模块依赖方向不变：`yl_runtime_commit` 已经 `use yl_problem_optional / yl_problem_errors`，加 `yl_problem_types` 不引入新的层级。 |

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
② A 的签名变更成本是 2 个调用点，一次性；
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

三件东西，职责不重叠：

1. **生成的行清单**（单一来源仍是 map）。
   `src/state/yl_state_dump.f90` 已经是 `tools/yl_state_map.py gen-fortran` 的产物 ——
   同一条命令再生成一张 `model_ready` 且 `emit ≠ none` 的**有序行 id 表**
   （建议 `src/state/yl_state_rows.f90`，与 dump 同源同 sha256 标注）。
   **没有任何一处手抄行清单**，map 增删一行，表跟着变。
2. **commit 声明每行的出处**（手写，就在 `yl_runtime_commit`）。取值域：

   | 状态 | 含义 |
   |---|---|
   | `COMMIT_FROM_PROBLEM` | 值取自 `problem_state_t` 的对应 owner 分量 |
   | `COMMIT_FROM_RUNTIME` | 值取自 `runtime_state_t`（今天的 46 行 + A 类的 extent） |
   | `COMMIT_DEFAULTED` | 值是 map 自己的 `reason`/`note` 记录的 legacy 默认值，**不是**被迁移的值（`not_migrated` 的 14 行、`derived:legacy_default` 的若干行） |
   | `COMMIT_SYNTHETIC` | dump 侧自行合成，commit 无事可做（D 类 2 行） |

3. **总体性闸门**，放在 commit 的 VERIFY 段，与 `INV-COMMIT-TOTAL` 同形：
   生成表里的每一个行 id 都必须在声明表里有条目，否则 commit **拒绝提交**。
   map 新增一行而 commit 没跟上 → 在 VERIFY 段失败，而不是"静默地少写一个全局"。
   这与今天 `verify_registered` 走规则表而不走本地清单，是同一条理由。

4. **旁挂文件**：commit 成功后把声明表写成 `<dump dir>/model_ready/provenance.txt`
   （或由 shadow 程序在 `yl_state_dump` 之后调用一个 `commit_provenance_dump(unit)` 写出）。
   `tools/yl_shadow_diff.py` 读它，把 `COMMIT_DEFAULTED` / `COMMIT_SYNTHETIC` 的行记为
   **第五个桶 `NOT_MIGRATED`**，既不算 MATCH 也不算 MISMATCH。

### 4.4 这样做换来什么

- L3-c §5.3 的"未写入的全局被当成状态发出"从**结构上**消失：任何进入 MATCH 统计的行，
  都有一个 `COMMIT_FROM_{PROBLEM,RUNTIME}` 的出处声明。
- 更重要的是挡住**反方向**的假证据：13 个 `not_migrated` 标量的 Fortran 零初值与 deck 值
  碰巧都是 0，今天会白送 13 × 2 = 26 个 MATCH。**白送的 MATCH 比 MISMATCH 更危险**，
  因为没人会去查一条绿线。
- 语义没有第二个来源：行清单来自 map，容差/ignore 来自 map 每行的 `compare.rule`（夹具照旧不碰），
  commit 只声明出处 —— 这是**只有 commit 知道**的事实，别处无从推导。

---

## 5. 会出什么问题，怎么被发现

### 5.1 最大风险：释放路径与 W4 守卫的名单（不是 46 行回归）

模块头已经把这类缺陷的形状写死了：*"a list that must be maintained is honest about needing
maintenance; a description that quietly covers less than it says is not"* —— 第一版 W4 守卫
描述了"记录数组"这一类却只枚举了六个里的五个，`trans` 那道门是敞开的。

折叠会把这份名单的规模乘上去：

- **`commit_release` 新增的所有权**：8 个可分配全局（`coord`、`props`、`appear_process`、
  `matno_process`、`average_appear`、`tcurvegravity`、`factg`、`uinitial`）
  + 至少 8 类新指针目标（`group%list`、`group%dof(:)`、`group%dof%listdof_f`、
  `element%field(1)%lnods_f`、`tcurves%ttime_curve`、`tcurves%dfact_curve`、
  `props%mechanical`、`props%mechanical%solid`）。
- **W4 守卫的名单**必须同步从"六个记录数组"扩成"本模块 `move_alloc` 的全部可分配全局"。
  漏掉一个，就是一个"新路径在 legacy reader 填过的进程里跑，静默泄漏"的入口 —— 和 `trans` 一模一样。

**建议把这条从"名单"改成"构造"**：把待发布的全局收进一张显式的清单（一个
`allocated()` 探针数组 + 名字），守卫、`move_alloc` 段、`commit_release` 三处都走这一张表，
新增一个全局时三处一起变或一处都不变。这一条是我对实现形态唯一的强建议。

**怎么被发现**：进程内看不见自己的泄漏（模块头自己说的）。所以
- `yl_runtime_bridge_test` 的 **T02 重复提交属性**（commit → commit → release → commit）
  是仓库里唯一能把"释放路径漏了一个新指针目标"暴露成 use-after-free / double-free 的检查；
- 真正的确认需要**外部工具**（valgrind / `-fsanitize=address`，`legacy/yl/sanitizer_guide.md`
  已有条目）。今天这一项记的是 NOT PERFORMED；折叠让它的价值上一个数量级，**建议在本任务里
  把它从"待办"提升为出口条件**，而不是继续记为未做。

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
- `tools/yl_shadow_diff.py --old-vs-old` 380/380 与阴性对照 —— 证明夹具没被折叠带偏。

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

## 6. 实施顺序（含 lead 复核检查点）

| 步 | 内容 | 触碰的全局 | 通过判据 |
|---|---|---|---|
| **0** | 账本骨架：`yl_state_map.py` 生成行清单 + commit 侧出处声明表 + VERIFY 段总体性闸门 + `provenance.txt` 旁挂；**全部 120 行先声明为未迁移**，一个全局都不新写 | 无 | `bridge_test` / `selftest` 与今天逐位相同；`build.sh` 双射检查绿 |
| **1** | 签名改 A：`commit_legacy_globals(problem, runtime, errors)`，2 个调用点跟改，**不新增任何写入** | 无 | 同上；差分行为与步 0 相同 |
| **2** | **C1 类 21 行 + `uinitial`**：8 个可分配全局的 staging / `move_alloc` / `commit_release` / W4 名单，四处一起改 | 8 个新全局 | **这一步第一次让新路径产出完整的 162 行 `model_ready` 快照** |
| **★** | **CHECKPOINT —— lead 复核后才继续** | | 见下 |
| **3** | **B 类 37 行**：折进已有的 `element` / `group` / `prescrib` / `tcurves` 循环。**一个记录数组一个提交**，每个之后跑 `bridge_test` | 无新全局，新指针目标 6 类 | 每个记录数组之后 L3-b 的 64 行仍 MATCH=64 / MISMATCH=0 |
| **4** | **C2 类 46 行 + 13 个 `not_migrated` 标量**：一段纯标量 staging | 59 个标量全局 | 影子差分：162 行判据面上 MISMATCH=0，`NOT_MIGRATED` 桶 = 14 |
| **5** | 外部内存工具（valgrind / ASan）在两个 golden 算例上跑重复提交序列 | — | 无泄漏、无 use-after-free；结果入报告 |

### 检查点 ★ 上 lead 要复核的五件事

1. `bridge_test` 与 `selftest` 逐条与折叠前一致（**46 行没有被 C1 类的改动带偏**）；
2. `commit_release` 与 W4 守卫的名单**确实**覆盖了新增的 8 个可分配全局 —— 逐个 grep，不看描述；
3. 影子差分首次跑出完整快照，且**没有一行是 MISMATCH**：此时 B/C2 类还没写，
   它们必须全部落在 `NOT_MIGRATED` 桶，任何一条 MISMATCH 都说明出处账本漏了行；
4. §5.2b 里**只有 §6 的 W4 消息解析**应当在这一步被改（因为步 2 扩了名单），
   且它的新名单与 `commit_release` 逐字一致；**`group_sentinels` 此时必须原样还绿** ——
   `nmats`/`nblks`/`restart` 属 C2 类，要到步 4 才写，它在步 2 变红就说明写超了范围；
5. extent 仍然只有一个推导源（`grep -n 'problem%mesh%nodes' src/runtime/yl_runtime_commit.f90`
   应当只在断言里出现）。

---

## 7. 本文没有建立什么

- **没有实施。** `src/runtime/**` 未改动一行；本文不构成"折叠已设计完毕可以照抄"的承诺，
  §5.2 的三类干扰只有在真写的时候才能逐个确认。
- **没有验证 ProblemState 侧的值是否正确。** 本文只论"值怎么从 owner 对象到达旧全局"，
  不论适配器读得对不对 —— 那是 L2-a/L2-b 和 R27 的事。
- **没有触碰 `phase_ready` / `increment_ready`。** 那 28 行不在 `model_ready`，与本折叠无关。
- **没有替 map 所有者决定任何事。** §1.6 的 14 个 `not_migrated` 行给了两条路和一个推荐，
  选哪条是 lead 与 map 所有者的决定。
- **没有推翻 R27。** 判据面仍然只覆盖 map 登记过的状态；折叠做到 100%，也不能说
  "reader 站点已全覆盖"。

## 8. 复现本文的每一个数

```bash
cd /home/huijun/HSTAR_Next/hstar-evolution

# 239 / 84 / 77 / 46 / 32
python3 -c "
import tomllib,collections
d=tomllib.load(open('docs/m2/state-field-map.toml','rb'))
f=[x for x in d['field'] if x['checkpoint']=='model_ready']
print(len(f), collections.Counter(x['owner'].split('.')[0] for x in f))"

# 162 个 emit != none；77 个 ignore = 14 RuntimeState + 63 not_migrated
python3 -c "
import tomllib,collections
d=tomllib.load(open('docs/m2/state-field-map.toml','rb'))
f=[x for x in d['field'] if x['checkpoint']=='model_ready']
e=[x for x in f if x.get('emit')!='none']
print('emitted',len(e))
print(collections.Counter(x['owner'].split('.')[0] for x in f if x.get('emit')=='none'))"

# §1 的五类分组（按 legacy_symbol 的基名）
#   A: 基名已在 commit 的写入清单里；B: 基名属六个被重建的记录数组；
#   C1: 基名是 allocatable 的新全局；C2: 其余标量；D: global_var.i0
# §2 的 59/59/2：逐行 grep src/state/yl_state_{dump,adapters}.f90 的 state_fail 守卫

# 三道闸门的位置
grep -n "not a model_ready RuntimeState row" tools/yl_state_map.py     # R3
grep -n "has no producing rule" tools/yl_state_map.py                  # R5
grep -n "runtime_status_count(runtime) /= build_rule_produced_count"   \
     src/runtime/yl_runtime_commit.f90                                 # verify_registered

# uinitial 是 allocatable，且 dump 对它有守卫
sed -n '186,187p' legacy/yl/Global.f90
grep -n "uinitial is not allocated" src/state/yl_state_dump.f90
```
