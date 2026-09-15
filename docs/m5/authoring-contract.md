# M5 authoring 契约 v1（`case.toml`）

- 日期：2026-09-11
- 依据：ADR-0003（CAE 对象模型 + SI）、ADR-0007（新输入体系尽量统一，避免各功能域孤立格式）
- 取代：`schemas/case.schema.json` 的 bootstrap 版本（自述「M5 之前不蕴含任何求解能力」）

## 0. 这份契约要做到的事

**让静力算例第一次可以完全用新格式表达、校验、转换并驱动求解。**
判据是用户可见的能力，不是内部状态：

1. 新格式能完整表达现有两个静力 golden 算例；
2. 有明确的 schema 校验与**可读**错误信息；
3. `case.toml → ProblemState → solver` 可独立运行（不打开任何旧 deck 控制文件）；
4. 新旧输入最终结果**严格一致**；
5. legacy 输入仍可通过回退路径运行。

## 1. 分层：authoring ≠ ProblemState

```
case.toml  --读--> authoring AST --映射--> ProblemState --build_runtime--> runtime --commit--> solver
```

**authoring 层按人写的方式组织，ProblemState 按求解器需要的方式组织。** 两者不是同一张表：
`ProblemState` 有 98 个已登记字段，而本契约要求作者写的只有其中的**物理选择**。
其余由**声明式默认**补齐——每一条默认都登记在 §5，并进入 manifest，可溯源。

**材料域补充（2026-09-14）**：本契约第一次出现**按模型条件必填**的字段。
legacy 读一条公共 SOLID 记录后再按本构模型分支，所以「必填」不再是键的属性，
而是（键, 模型）这一对的属性。规则 `model_requires` 两个方向都检查：
塑性模型缺参数是 `MISSING_FIELD`，弹性材料上写塑性参数是 `INVALID_INPUT`——
**不是静默忽略**，否则作者会以为那个摩擦角生效了。

另有两行**移出默认表**，都是按下面那条准入规则移的：
`steps[0].controls.nonlinear_type`（何时重装切线刚度）原写着「取值不进入结果」——
这在线性弹性单次迭代下成立，**材料非线性时立刻不成立**；
一个「是否无害取决于材料」的默认不是默认。现由作者写 `step.controls.stiffness_update`。
（另一行是 `output.stress_averaging`，见下。）

**默认的准入规则（这条比默认表本身重要）**：

> **一个字段只有在「它不是物理选择」时才可以有默认值。**

`materials[].E` 是物理选择，必须写；`steps[0].output.frequency.*` 是输出细节，可以默认。
`steps[0].output.stress_averaging` 曾被放进默认表，后来按这条规则移出：它决定上报的节点应力
**是什么**（Output.f90:5102），换一个取值就换一组数字，所以必须作者写。
判断标准是可操作的:**换一个默认值会不会改变计算结果或其物理含义**——会，就必须作者写。
`docs/00-project-charter.md` 的「30～50 行，不以隐藏物理选择为代价」就是这条规则。

## 2. 顶层结构

| 表 | 形态 | 说明 |
|---|---|---|
| `version` | 整数 | 恒为 1；契约不兼容变更时递增 |
| `[case]` | 表 | `name`、`units`（**必须**是 `"SI"`）、可选 `description` |
| `[mesh]` | 表 | 网格来源与维度 |
| `[[nset]]` / `[[elset]]` | 表数组 | 命名的节点集 / 单元集，边界与截面通过**名字**引用 |
| `[[surface]]` | 表数组 | 命名的**边集合**，面荷载通过**名字**引用（§8.1）|
| `[[material]]` | 表数组 | 材料 |
| `[[section]]` | 表数组 | 截面：把单元集、单元类型、公式与材料绑在一起 |
| `[[amplitude]]` | 表数组 | 时间曲线（§8.2）|
| `[[step]]` | 表数组 | 分析步；本版**只允许一个**，但形态从一开始就是数组 |
| `[solver]` | 表 | 线性求解器选择 |
| `[output]` | 表 | 输出格式与场 |

**为什么 `[[step]]` 从一开始就是表数组**：多步是后续功能域必然要有的东西，
把它现在写成单数表、以后再改成数组，是一次不兼容变更;
而「一个域引入的新概念若与已有域同形，必须复用既有结构」正是 ADR-0007 第 4 条。
同理 `[[material]]` / `[[section]]` / `[[nset]]` / `[[elset]]` / `[[amplitude]]` 一律表数组。

## 2.1 分析步与 legacy 的三层时间（冻结映射）

legacy 有三层嵌套时间：**block(`iblks`) → increment(`iincs`) → step(`istep`)**。
`.loa` 的尾部（边荷载 / 体力 / 每组曲线号）**按 block 重复一遍**，`.man` 的增量控制卡
按 increment 重复。名字是历史造成的陷阱：legacy 的 `nstep` **不是**「有几个分析步」，
而是一个 block 内部再走多少小步。

契约因此把 authoring 的 `[[step]]` 对齐到 legacy 的 **block**，把 block 内部的细分
命名为 `substeps`（2026-09-15 由 `controls.steps` 改名，原名会被读成「分析步数」）。
**冻结映射公式，任何实现都不得偏离：**

```
legacy nblks = count(step)          legacy nstep = step.controls.substeps
```

这条改名是纯命名改动：`docs/m2/state-field-map.toml` 的行 id 仍是
`steps0.controls.steps`（它是**线格式**，写进了冻结基线），只有 owner 路径与作者可写的
键名改成 `substeps`；四个 golden 算例改名前后逐位一致，即为该性质的证据。

## 3. 引用一律用名字

截面引用 `elset` 与 `material` 的**名字**，边界引用 `nset` 的名字，荷载引用 `amplitude` 的名字。
**新输入里不出现整数 id**。id 是 `ProblemState` 的事，由映射层分配并记录在 manifest 里。

这条不是风格问题：legacy 的每一个缺陷类别里都有「整数槽位在不同开关下含义不同」，
而名字引用让「引用了一个不存在的集合」成为一个可以被检查、可以被报出的错误。

## 4. 错误模型

一切拒绝都落在三个既有判决上（`docs/02-migration-plan.md`）：

| 判决 | 何时 | 退出码 |
|---|---|---|
| `INVALID_INPUT` | TOML 语法错、类型错、缺必填、未知键、引用不存在的名字、单位不是 SI | 2 |
| `UNSUPPORTED_CAPABILITY` | 语法与引用都对，但组合不在白名单内（例如 `element = "Q8"`） | 3 |
| `READY` | 通过 | 0 |

**每一条错误都必须带**：`case.toml` 的**行号**、出错的**键路径**、读到的值、以及
（能给出时）允许的取值。这是判据 2 里「可读」的操作化定义——
**不写行号的错误信息，在一个 50 行的输入上就已经不可读了。**

**未知键一律拒绝**（`additionalProperties: false`）。这条要求 2026-09-10 从 M3-02 的验收列
移到这里：`problem_state_t` 是强类型派生类型，未知字段在那一层写不出来因而不可失败，
而在文本输入这一层它是真实的、可失败的（见 `docs/m3/M3-02-pipeline.md` §4.1）。

**还有三条，都是实测出来的，不是设计出来的**（2026-09-12，`tools/yl_modern_check.py` N3）：

1. **文件读不出来也必须是这个错误模型**。原设计把「可读性」也交给 entry 判决，
   但 entry 活在 `global_data` 里，而 `probn` 在此之前就要用来命名所有文件——
   于是一个不存在或语法错的 `--input` 会掉进 **legacy reader**，对着一个从没提供过
   legacy deck 的人打印 `Input the problem name?`，然后 Fortran traceback。
   现在**可读性、且只有可读性**由 prelude 判决，退出码仍是 2。
2. **一条错误只渲染一次**。曾经 validator 的调用方与拒绝路径各打印一遍，操作者看到两份。
3. **错误里的文件名是操作者敲的那个**，不是硬编码的 `case.toml`。
   映射层原先把 `case.toml` 写死在 source location 里。

对应的门禁断言写在 `tools/yl_modern_check.py` N3 的四个形态里；
三条都是**先观察到失败输出、再写断言**，不是先写断言再假设它有效。

## 5. 默认表

每一条默认都写明**为什么它不是物理选择**。任何一条被质疑，做法是把它移出这张表、
变成必填项——**不是**改掉它的值。

| ProblemState 字段 | 默认 | 为什么不是物理选择 |
|---|---|---|
| `steps[0].controls.step_increment` | 1 | 步循环的步长；白名单内唯一取值 |
| ~~`steps[0].controls.substeps` / `time_increment`~~ | **已移出本表**（M6.5） | 它们决定分析停在折减曲线的哪一点——是实验本身，不是记账 |
| `steps[0].controls.time_increment` | 1.0 | 静力无时间尺度；只用于曲线求值的横坐标 |
| `steps[0].controls.restart_frequency` | 1 | 重启不在白名单内 |
| `steps[0].load_mode` | `"LOAD"` | 白名单只有一种加载模式 |
| `steps[0].output.field.*`（20 个开关） | 由 `[output].field` 展开 | 作者选“要哪些场”，开关是它的编码 |
| `steps[0].output.frequency.*` | 1 / 1 | 单增量下只有一个输出时刻 |
| `steps[0].activation[].*` | 全激活 | 施工阶段不在白名单内（M6.7） |
| `sections[].class` / `formulation` / `special` | 由 `element` + `formulation` 决定 | 是同一物理选择的编码 |
| `sections[].algorithm` / `stiffness_kind` / `stress_recovery` | 0 / 1 / 1 | 数值细节，白名单内唯一取值 |
| `sections[].layer` / `liquefaction` / `uplift` / `local_axes` | 0 / 0 / 0 / 0 | 相应能力不在白名单内 |
| `sections[].thickness` | 1.0 | 平面应变按单位厚度——**这一条是边界情况**：若将来支持平面应力，厚度就是物理选择，必须移出本表 |
| `materials[].kind` / `phase` / `name` | `"MECHANICAL"` / `"SOLID"` / `"SOLID"` | 白名单只有单相固体；`name` 是 legacy `.mat` 表头词，即相名，不是作者的引用标签 |
| `materials[].creep_model` / `wetting_kind` / `liquefaction` / `solid_ratio` / `thermal_expansion` | 0 / 0 / 0 / 1.0 / 1e-5 | 相应本构不在白名单内；取值不被消费 |
| `solver.symmetric` / `solver.profile.*` | 0 / (0,0,1,1) | PROFILE 的固定开关 |
| `mesh.*` 的一切计数 | 由网格文件派生 | 计数不是输入 |
| `interactions.absorbing.type` | 空 | 吸收边界不在白名单内（M7） |

**不在默认表里、必须由作者写的**：`case.name`、`units`、网格来源、节点/单元集、
`materials[].{name,model,density,E,nu}`、`sections[].{elset,element,formulation,material}`、
`amplitudes[].{name,type,points}`、`steps[].{procedure,controls.increments,
controls.substeps,controls.time_increment,controls.max_iterations,controls.tolerance_*}`、边界的 `{nset,dof,value}`、
`steps[].load_mode`、荷载对象的 `{type,amplitude}` 与其按类型条件必填的字段（gravity：`{magnitude,direction,apply_to}`；pressure：`{surface,distribution.*}`，见 §8.3）、`[[surface]]` 的 `{name,kind,edges}`、`solver.linear`、`output.{format,field}`。

## 6. 白名单（超出即 `UNSUPPORTED_CAPABILITY`）

- `mesh.dimension = 2`；`mesh.format = "hstar-legacy-cor-ele"`
- `section.element = "Q4"`；`section.formulation = "plane_strain"`
- `material.model ∈ {"elastic_isotropic", "classicalep"}`；
  `classicalep` 需要 `criterion = "mohr_coulomb"` 及 `cohesion` / `hardening` /
  `friction_angle` / `dilation_angle`（**角度单位是度**，legacy 直接 `tand()`），
  且这些字段**只允许**出现在塑性材料上——两个方向都有反例
- `step.procedure = "static"`；`step.controls.increments = 1`
- `step.controls.stiffness_update ∈ {"first_iteration", "every_iteration"}`（legacy `type_nl` 5 / 4）
- 边界只有给定位移（`value`），`dof ∈ {1,2}`
- `step.load[].type ∈ {"gravity", "pressure"}`（§8.3）；
  `pressure` 需要 `surface` / `amplitude` / `distribution`，且
  `distribution.type = "linear_in_coordinate"`、`distribution.axis = "y"`
- `surface.kind = "edge2"`（每行恰好 `[n1, n2, element]`）
- `amplitude.type ∈ {"linear", "waterlevel"}`
- `solver.linear = "profile"`
- `output.format = "gid"`；`output.field ⊆ {"u","s","ep"}`；`output.stress_averaging ∈ {"none","smoothed","direct"}`
  （`"smoothed"` 与 `"direct"` 在本切片上不可区分：Output.f90:5128-5129 的分支只在
  `nnode==8 .and. ndimn==3` 下成立，2-D Q4 走同一条 else 分支。实测而非推断——改成
  `"smoothed"` 仍严格复现冻结参考，改成 `"none"` 应力偏离 1.5e5、位移不变。）
- `[[step]]` 恰好一个

白名单之外的每一条都要有**反例**，与 M4 方言门同一形态：一行一个反例，
断言该行触发、且**只有该行触发**。

## 7. 网格仍来自文件，这是有意的

`[mesh].file` 指向旧的 `.cor`/`.ele` 对。**网格不是 authoring 的内容**——
289 个节点坐标写进 `case.toml` 只会让它不可读，而 30～50 行的目标正是为了可读。
换一种网格格式（gmsh）是 `format` 的事，不改变契约其余部分。

**这一条的限度要说清**：因此 M5 的「不打开任何旧 deck」指的是**控制文件**
（`.glb/.mat/.pre/.loa/.man/.sol/.opr`），不包括网格文件本身。

## 8. `.loa` 家族：幅值、面与荷载

`.loa` 是第一个按**输入家族**（而不是按材料或求解器）推进的切片。它的 legacy 形态是
一条读取流水线：曲线表 → 集中力 → 边定义 → **（按 block 重复）** 边荷载 → 体力 →
每组重力曲线号 → 梁荷载 → 板荷载。这一节把其中**首批四个家族**（B 幅值 / D 边定义 /
E 面荷载 / F 重力）提炼成声明式对象；C（集中力）挂起，G（梁）/ H（板）与未见曲线类型
按 ADR-0008 §3 保持 legacy-only。

契约的立场：**作者写对象，不写读取顺序。** 下面每一条「legacy 对应」都是适配器的职责，
不是作者要知道的事。

### 8.1 `[[surface]]`：面就是一张显式的边表

```toml
[[surface]]
name  = "upstream_face"
kind  = "edge2"              # 2-D 的两节点直边
edges = [                    # [n1, n2, element]
  [ 1,  7,  1],
  [ 7, 13,  6],
]
```

**三列全部显式，一个都不推导。** `element` 是该边所依附的单元，legacy 自己也把它写在
文件里（`edges(t)%aelem`，`Load.f90:383`）；由节点对反查单元是**拓扑推导**，而这个仓库
刚刚因为在 Bridge/Runtime 里做数值与拓扑镜像付出过两次代价（R31、`jacob` 的 1-ULP 分叉）。
适配器在这一家族里只做查表与搬运，零浮点、零推导。

| legacy | 由什么决定 |
|---|---|
| `nedge` | `Σ len(surface.edges)` |
| 分块头 `sedge nnode index vdimn` | `len(edges)`、`2`、`1`、`0`（白名单内取值） |
| 每行 `i0 lnode(1:nnode) aelem` | `edges[i]` 的三列 |

**声明顺序即 legacy 边号顺序**，一个 `[[surface]]` 因此恰好是一段连续的边号区间。
这正是 legacy 的边荷载卡用 `begin_edge..end_edge` 引用边的方式——**区间是适配器的内部
产物，作者永远只写名字**（§3）。

### 8.2 `[[amplitude]]`：一种对象，两种线格式

```toml
[[amplitude]]
name   = "constant"
type   = "linear"            # 或 "waterlevel"
points = [[0.0, 1.0], [1.0, 1.0]]     # [t, f]，t 严格递增
```

作者看到的永远是 `(t, f)` 点列。**legacy 的两种类型线格式不同**，这一点由适配器吸收：

| `type` | legacy `type_curve` | 线格式（`Load.f90:214-232`） |
|---|---|---|
| `linear` | 默认分支（deck 里写 `LINEAR`） | **两条记录**：先 `ntime` 个时间，再 `ntime` 个系数（列优先） |
| `waterlevel` | `WATERLEVEL` | **`ntime` 行**，每行一对 `(t, f)`（行优先） |

两种类型在 deck 里长得几乎一样，含义却转置——这正是「读取顺序不该进入作者视野」的
最短论据。

### 8.3 `[[step.load]]`：一步之内的荷载对象列表

荷载从「一个 `[step.load]` 表」改成**对象数组**，因为同一步里可以有多个同类荷载
（不同单元组不同重力历程、不同面不同水位）。

```toml
[[step.load]]
type      = "gravity"
magnitude = 9.81
direction = [0.0, -1.0]      # 模长必须非零
amplitude = "constant"
apply_to  = "all"            # 或某个 elset 名字

[[step.load]]
type      = "pressure"
surface   = "upstream_face"
amplitude = "reservoir"
[step.load.distribution]
type  = "linear_in_coordinate"
axis  = "y"                  # legacy abs(water)；2-D 白名单只有 "y"
at    = [23.0, 0.0]          # [y0, y1]，y0 ≠ y1
value = [0.0, 23.0]          # [p0, p1]，与 at 等长且一一对应
scale = 9810.0               # legacy fact，例如水的重度
```

**重力与单元组解耦**：legacy 把每个单元组的重力曲线号平铺在
`tcurvegravity(1:ngroup)`（`Load.f90:922`）。作者不写这个数组，而是写若干个
`type = "gravity"` 对象，各自 `apply_to` 一个 elset、各自挂自己的 `amplitude`；
适配器负责回填。`apply_to = "all"` 是「全体同一历程」的简写。

**面压力的分布**：legacy 逐节点算
`press = -(p0 + dcor/(y0-y1)*(p1-p0)) * scale`，其中 `dcor = y0 - coord(axis, node)`
截断在 0，且坐标落在 `[y1, y0]` 之外时压力归零（`Load.f90:816-830`）。契约因此要求：

- `at` 与 `value` 必须**等长**，2-D 下恰好 2 个点（两点确定线性插值）；
- **`at[0] ≠ at[1]`**——legacy 直接除以 `y0-y1`，相等即除零。这是一条反例，
  不是一句提醒。

### 8.4 过程型 vs 对象型：暴露出来的唯一真冲突

`.loa` 的尾部（边荷载 / 体力 / 每组曲线号）**在文件里按 block 重复一遍**。也就是说
legacy 的「荷载」本质上是一个**按块推进的状态机**，而不是一组对象。

契约的答复是 §2.1 的那条映射：**一个 block = 一个 `[[step]]`**，于是「第 2 块的边荷载」
变成「第 2 个 step 的 `[[step.load]]`」，状态机被展平成显式的分析步序列。
这是 ADR-0007 第 4 条的直接应用，也是这个家族里唯一需要架构判断的地方——
其余（曲线、边、重力）都只是把整数槽位换成名字。

**代价要写清楚**：legacy 允许两块之间「只改一点点」而文件里仍重复整段；
现代输入里每个 step 都要把自己那一份荷载写全。这是有意的——
**隐式继承上一块的状态，正是 legacy 输入最难审阅的性质。**
