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
| `[[material]]` | 表数组 | 材料 |
| `[[section]]` | 表数组 | 截面：把单元集、单元类型、公式与材料绑在一起 |
| `[[amplitude]]` | 表数组 | 时间曲线 |
| `[[step]]` | 表数组 | 分析步；本版**只允许一个**，但形态从一开始就是数组 |
| `[solver]` | 表 | 线性求解器选择 |
| `[output]` | 表 | 输出格式与场 |

**为什么 `[[step]]` 从一开始就是表数组**：多步是后续功能域必然要有的东西，
把它现在写成单数表、以后再改成数组，是一次不兼容变更;
而「一个域引入的新概念若与已有域同形，必须复用既有结构」正是 ADR-0007 第 4 条。
同理 `[[material]]` / `[[section]]` / `[[nset]]` / `[[elset]]` / `[[amplitude]]` 一律表数组。

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
| `steps[0].controls.nonlinear_type` | 5 | 线性静力下 `algort` 只在首次迭代置 `kresl=1`，取值不进入结果 |
| `steps[0].controls.steps` / `step_increment` | 1 / 1 | 单增量静力的定义本身 |
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
controls.max_iterations,controls.tolerance_*}`、边界的 `{nset,dof,value}`、
重力的 `{magnitude,direction,amplitude}`、`solver.linear`、`output.{format,field}`。

## 6. 白名单（超出即 `UNSUPPORTED_CAPABILITY`）

- `mesh.dimension = 2`；`mesh.format = "hstar-legacy-cor-ele"`
- `section.element = "Q4"`；`section.formulation = "plane_strain"`
- `material.model = "elastic_isotropic"`
- `step.procedure = "static"`；`step.controls.increments = 1`
- 边界只有给定位移（`value`），`dof ∈ {1,2}`
- 荷载只有 `gravity`
- `amplitude.type = "linear"`
- `solver.linear = "profile"`
- `output.format = "gid"`；`output.field ⊆ {"u","s"}`；`output.stress_averaging ∈ {"none","smoothed","direct"}`
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
