# 目标架构

## 1. 两类状态

### ProblemState

描述用户想计算什么，初始化完成后只读。结构采用通用 CAE 软件共有的“模型层 / 历史层 /
求解层”对象模型（见 ADR-0003），不自创分类：

```text
ProblemState
├── case          名称、描述、单位制（固定 SI）
├── mesh          节点、单元、来源文件、命名集合 nset / elset / surface
├── materials     按名字定义的本构模型与有量纲参数
├── sections      elset → 单元类型 + 公式（平面应变/应力、厚度、积分）+ 材料
├── amplitudes    按名字定义的时间/荷载曲线
├── interactions  接触对、Goodman、粘结、吸收边界（后续阶段）
├── steps[]       有序分析步：procedure、controls、boundary、load、activation、output
└── solver        线性求解器、线程数、全局容差
```

规则：

- 所有对象只通过名字互相引用；`npoin/nelem/ngroup/nmats/mdofn` 等数量全部派生；
- 场与自由度由 section 的 formulation 派生，用户不填 MDOFN；
- YL 的“组”拆为 elset、section、material 三个对象，提交时再合并；
- 模型层与时间无关；随阶段变化的条件一律放在 step 内。

### RuntimeState

描述求解器如何执行：自由度编号、稀疏矩阵结构、工作数组、历史变量、迭代状态和输出句柄。
`RuntimeState` 只能由已经 finalize 的 `ProblemState` 构建。

## 2. 输入流水线

```text
parse
  ↓
Authoring AST             保留文件、行列、缺失/显式值
  ↓
normalize                 名称、引用、坐标系和单位
  ↓
ProblemState draft
  ↓
semantic validation       跨对象、跨阶段、物理组合
  ↓
capability gate           当前构建是否支持该组合
  ↓
finalize                  派生数量，冻结默认值和清单
  ↓
RuntimeState build        分配、DOF、拓扑和矩阵结构
  ↓
dry-assemble / solve
```

Legacy Adapter 从旧文件构建同一个 `ProblemState draft`。Modern Reader 从 TOML 构建它。
两条路径从 normalize 之后共用全部代码。

## 3. 事务式提交

YL 现状会在读取过程中不断改变 `global_var`，一旦中途失败便形成不完整状态。迁移期采用：

```fortran
call load_problem(source, draft, errors)
if (errors%any()) return
call validate_problem(draft, errors)
if (errors%any()) return
call finalize_problem(draft, problem, manifest, errors)
if (errors%any()) return
call build_runtime(problem, runtime, errors)
if (errors%any()) return
call commit_legacy_globals(runtime)
```

`commit_legacy_globals` 是迁移期唯一允许写入旧全局输入变量的入口。计算模块完成显式参数化后，
该 bridge 逐步缩小直至删除。

提交阶段不得再解析输入或执行可能失败的分配。先准备完整所有权和所需数组，再转移所有权；
指针别名、生命周期与失败后的再次加载必须单测。输入模式由命令行显式指定。

## 4. 三种运行模式

- `legacy-reference`：原 reader + 原计算路径，只用于保存基准和紧急回退。
- `legacy-adapter`：旧 deck → ProblemState → RuntimeState → 计算核心。
- `modern`：TOML → ProblemState → RuntimeState → 计算核心。

禁止解析失败后自动从 `modern` 回退到 `legacy-reference`。这会掩盖错误并导致同一输入在不同
机器上走不同路径。

## 5. 状态等价优先于文件等价

每个算例在第一次组装前生成确定性摘要：

```text
control.json
mesh.sha256
dof.sha256
groups.json
materials.json
constraints.sha256
loads.sha256
steps.json
numerics.json
```

第一次组装只是检查点之一。YL 会在分析阶段内继续读取 `.man` 等输入；迁移必须登记
`model_ready`、`phase_ready(phase_id)`、`increment_ready(phase_id, step_id)`，
以及使用重启时的 `restart_ready`。对消费路径涉及的每个检查点比较已生效参数。
两个实现使用独立进程，不在同一 `global_var` 上先后运行两套 reader。
哈希用于识别完全相同的数据，带容差的浮点比较必须读取结构化值，不能只比较哈希。

迁移判据首先是旧路径与新路径进入计算核心时的状态是否等价，其次才是最终结果。文本完全
相同既非必要条件，也不足以证明物理语义相同。

## 6. 现代输入原则

- 使用通用 CAE 词汇（mesh、nset、elset、material、section、amplitude、step、boundary、
  load、output、solver），不暴露 Fortran 槽位名称；
- 单位制固定为 SI（m、N、Pa、kg、s、K），`case.units = "SI"` 必须显式声明，不做换算；
- 分析类型和边界类型使用 tagged union（`procedure = "static"`、`type = "gravity"`）；
- 数量由对象派生，不让用户重复填写；
- 默认值来自有版本的 profile，并写入清单；
- 未知字段报错；
- 非法组合报错；
- 未验证组合由 capability gate 拒绝；
- 命名集合先由网格文件提供；几何拓扑选择留待后续能力。
