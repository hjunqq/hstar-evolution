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

每个解析器模块**只导出解析子程序**，形如：

```fortran
subroutine parse_<kind>(unit, b, errors)
  integer, intent(in) :: unit                    ! 已打开的 deck 单元，由驱动持有
  type(problem_builder_t), intent(inout) :: b    ! 共享 draft builder
  type(problem_errors_t), intent(inout) :: errors
```

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
- 不修改任何全局，只读。

## 7. 禁止（全体）

不改 `legacy/yl`；不改 M2 映射表中参与快照的键；不进求解器链接链；
不新增第二个 legacy 全局 writer；不在解析器里 `use global_var`。
