# M4-01 适配器共享契约

- 日期：2026-09-08
- 适用：`src/adapter/` 下的全部解析器模块与收割预言机
- 目的：五个解析器并行开发时的**唯一对接面**。任何偏离都必须先改这份文件。

## 1. 模块与文件

| 模块 | 文件 | 负责的 deck |
|---|---|---|
| `yl_adapter_harvest` | `src/adapter/yl_adapter_harvest.f90` | 预言机（不解析，调 legacy reader 后收割全局） |
| `yl_adapter_mesh` | `src/adapter/yl_adapter_mesh.f90` | `.cor`、`.ele` |
| `yl_adapter_model` | `src/adapter/yl_adapter_model.f90` | `.glb` |
| `yl_adapter_material` | `src/adapter/yl_adapter_material.f90` | `.mat`、`.sol` |
| `yl_adapter_load` | `src/adapter/yl_adapter_load.f90` | `.loa`、`.pre` |
| `yl_adapter_fem90` | `src/adapter/yl_adapter_fem90.f90` | `inp`、`.man`（FEM90 残余，无预言机保护） |

一个模块一个文件，**文件所有权互斥**。

## 2. 解析器的唯一公开形状

每个解析器模块**只导出解析子程序**。**碰 `steps[0]` 的**（`.glb` / `.loa` / `.pre` / `.man`）：

```fortran
subroutine parse_<kind>(unit, b, parts, errors)
  integer, intent(in) :: unit                    ! 已打开的 deck 单元，由驱动持有
  type(problem_builder_t), intent(inout) :: b    ! 共享 draft builder
  type(step_parts_t), intent(inout) :: parts     ! 共享 steps[0] 草稿聚合体
  type(problem_errors_t), intent(inout) :: errors
```

**不碰 `steps[0]` 的**（`.cor` / `.ele` / `.mat`）沿用不带 `parts` 的形式。
`.sol` 用 `sparts`（见 §2.2）。

除 `parse_glb` 外，**每个解析器都额外收一个 `type(deck_context_t), intent(in) :: ctx`**：

```fortran
subroutine parse_cor(unit, ctx, b, errors)
subroutine parse_loa(unit, ctx, b, parts, errors)
subroutine parse_sol(unit, ctx, b, sparts, errors)
```

`parse_glb` 反过来**填** ctx，且它同时供给两个写聚合体的叶子：

```fortran
subroutine parse_glb(unit, ctx, b, parts, sparts, errors)
  type(deck_context_t),  intent(inout) :: ctx      ! 它是唯一写者
  type(step_parts_t),    intent(inout) :: parts    ! procedure_/load_mode/output/activation/...
  type(solver_parts_t),  intent(inout) :: sparts   ! solver%linear、solver%symmetric
```

（此处早先的示例漏了 `sparts`，与同节叶子表矛盾；由 L1-c 指出。**叶子表是权威，示例是摘要**——
与 `output` 归属那次更正同一条规则。）

### 2.2 跨文件上下文与第二个写聚合体（2026-09-08 修订，由 L1-b/d 与 L1-e 发现）

共享模块是 `src/adapter/yl_adapter_parts.f90`（模块 `yl_adapter_parts`，原 `yl_adapter_step_parts`
更名扩充），含三个类型：

| 类型 | 方向 | 用途 |
|---|---|---|
| `deck_context_t` | **读** | `.glb` 建立、后续解析器**定尺寸或选分支**所必需的事实 |
| `step_parts_t` | 写 | `steps[0]` 的碎片，来自四个文件 |
| `solver_parts_t` | 写 | `solver` 的碎片，来自两个文件 |

**为什么需要 `deck_context_t`**：`.loa` 的重力记录按 `ndimn`/`ngroup` 定长；`.pre` 的集合头有
8 字段 `FIX` 与 9 字段 `MIF` 两种，由 `type_abc` 决定，另有 `nbackdt`、`ntrans` 两个分支；
`.cor`/`.ele` 需要 `ndimn` 与单元类型才知道记录形状。这些全部由 `.glb` 读出。
没有这条通道，后续解析器只能**猜**，而失败是静默的——`ndimn` 猜错会让其后每一次读都错位，
把 MIF deck 当 FIX 解析**不会产生任何 I/O 错误**，只是读错字段。所以它们必须作为**数据**传递，
而不是作为假设写死。（L1-b/d 的 `NDIMN=2` / `NNODE_Q4=4` 硬编码正是这个洞。）

**`solver_parts_t` 与 `step_parts_t` 同因**：`builder_set_solver` 也是一次性 setter，而
`.glb` 供给 `linear` 与 `symmetric`，`.sol` 供给 `profile%*` 四项。同样的纪律：
解析器只填自己的叶子，驱动做那一次调用。

### 2.1 为什么多一个 `parts`（2026-09-08 修订，由 L1-e 发现）

`steps[0]` 由**四个 deck 共同供给**——按映射表计数：`.glb` 28 项、`.man` 10 项、`.pre` 6 项、
`.loa` 3 项。更麻烦的是两个聚合体本身就跨文件劈开：

| 聚合体 | 来自 `.glb` | 来自别处 |
|---|---|---|
| `load_t` | `gravity.enabled` | `gravity.magnitude/direction/amplitude`（`.loa`） |
| `controls_t` | `nonlinear_type` | 其余八项（`.man`） |

而 `builder_step_set_load` / `builder_step_set_controls` 是**单次 setter**，第二次调用被拒为
`builder.duplicate_singleton`。那是**对的**——它正是用来防止一个写者静默覆盖另一个。

所以"把共享 `step_builder_t` 传下去"解决不了问题：无论谁发起，第二次 setter 调用都会被拒。

**修订后的机制**：解析器**完全不调用 step builder 例程**，只往共享的 `step_parts_t` 里填
自己拥有的叶子；**由 L2-a 驱动在最后一次性完成全部 `builder_step_*` 调用**。
builder 的单次语义完好无损，且仍在履职——它现在守的是驱动那一趟。

**叶子所有权表在 `src/adapter/yl_adapter_parts.f90` 的模块头**，一个叶子一个写者。
写了不属于自己的叶子即为缺陷，**哪怕值恰好是对的**——第二个写者会静默胜出，而两位作者都不会发觉。

**约束：**

- **不打开、不关闭、不 rewind 任何单元。** 单元生命周期归 L2-a 驱动。
  理由：legacy 的读取协议是位置敏感的，游标状态必须由一个地方统筹。
- **不触碰任何 legacy 全局。** `use global_var` 在解析器里是禁止的——那正是 M4 要消灭的耦合。
  预言机是唯一例外，且它在模块头必须写明自己不是产品路径。
- **只通过 `yl_problem_builder` 写 draft。** 不得手工分配 `problem_state_t` 的分量。
- **失败即返回**，不吞掉错误、不继续读。位置敏感协议下继续读只会产生错位的垃圾。

## 3. 每一次读都必须可追溯到 reader 清单

解析器复刻的每一个 `read`，都要在紧邻的注释里写出它对应的 reader id：

```fortran
! RD: GLB.global_data.npoin  (Global.f90:812)
read (unit, *, iostat=ios) npoin
```

id 取自 `docs/m1/reader-inventory.toml` 的 `id` 字段，行号取自其 `site`。

**这不是文档洁癖**：预言机的逐字段对拍在失败时只能告诉你"哪个字段偏了"，
而这条注释是从字段回到"是哪一次读取写错了"的唯一线索。125 个站点里没有它就得靠猜。

## 4. 错误如何上报

沿用 M3-02/M3-03 的绑定纪律——finding 携带**行的身份**，位置进 message：

- `code`：`PE_INVALID_INPUT`（deck 内容坏）/ `PE_UNSUPPORTED`（白名单外方言）/ `PE_INTERNAL`（解析器自身故障）
- `rule_id`：`A<n>/<condition>` 复合键，例如 `A3/node-count-mismatch`
- `object_path` / `field`：该规则报告的对象
- `stage`：`PE_STAGE_ADAPT`（L2-b 负责新增此常量）
- 具体的行号、读到的值、期望值 → `message` / `actual` / `expected` / `index`

**不得**把出事位置写进 `object_path`。M3-03 Round 1 有两处这么干，导致 finding 无法被识别为
是哪条规则在响，覆盖走查报 0/5 而每个反例其实都在正确触发。

## 5. 白名单与拒绝

白名单沿用 M3-02 能力表 `static-q4/1`，**不扩大**：2D、Q4、位移场、线弹性各向同性、
单阶段静力、固定/给定位移、重力。

解析器遇到白名单外的方言：`PE_UNSUPPORTED` + 规则 id，**不猜、不填默认值、不跳过**。
`UNSUPPORTED_LEGACY_DIALECT` 的对外表达由 L2-b 统一，解析器只负责如实报。

## 6. 预言机的特殊约束

`yl_adapter_harvest` 是**唯一**允许 `use global_var` 的适配器模块。它必须：

- 在模块头写明：**这是预言机，不是产品路径**；它保留"reader 写全局"的行为，
  因此它自身不满足 M4 的目标，只用于校验解析器；
- 收割映射按 `docs/m2/state-field-map.toml` 的 `legacy_symbol` 列，**不手抄**；
- 不修改任何全局，只读。**唯一例外见 §6.1。**

### 6.1 `local_p4` 的例外（2026-09-08，R-order-2 发现）

`prescrib_set` 在 `Prescrib.f90:442` 读 `local_p4(ipoin)`，而 `local_p4` 由
`modf_element_lib`（`Fem.f90:11689-12242`）计算——**它也是 `PROGRAM FEM90` 的内部子程序**
（`contains` 在 552 行），与已知那 9 个站点是同一道结构性壁垒。所以不是"复现 FEM90 的中间状态"
就够了：其中一步本身被墙在外面，而它的输出喂给一个可达的 reader。这是计划未预料到的**第二类依赖**。

**允许的例外**：预言机可以 `allocate(local_p4(npoin))` 并**置零**，此外不得再动它。

理由与边界：

- 置零**就是 `modf_element_lib` 自己的初始状态**（`Fem.f90:11718`：`local_p4=0`），
  不是编造的值。被跳过的只有那段"有条件地把某些项提升为 1"的逻辑。
- `local_p4` 在 `Prescrib.f90` 全文只用于 `:442` 的 `if(local_p4(ipoin)/=1)cycle`，
  所以置零的效果是**整段追加约束的循环不执行**，作用面清晰。
- 由此产生一条**明确的假设**：*p4 局部约束机制在白名单路径上不产生任何约束记录。*
- 该假设**无法先验验证**（提升逻辑被墙在外面），但**可以后验证伪**：预言机得到的 `ndofix`
  必须等于冻结基线的。两个 golden 算例的基线均为 `ndofix = 34`，恰是 `.pre` 的 17 节点 × 2 自由度
  （`cases/golden/*/reference/state/model_ready/constraints.json`），即 p4 在这两例上确实颗粒无收。
  一旦某个 deck 上 p4 真的产生记录，预言机的 `ndofix` 会**偏低**，L3-b 的基线比对必然报红。

**不选的方案**：在预言机里重实现 `modf_element_lib` 的 `local_p4` 计算（约 500 行 legacy 分析逻辑）
——那正是本节第一条禁止的"手抄"，为 6 个站点复制 500 行且引入真实漂移风险，不划算。

## 7. 禁止（全体）

不改 `legacy/yl`；不改 M2 映射表中参与快照的键；不进求解器链接链；
不新增第二个 legacy 全局 writer；不在解析器里 `use global_var`。
