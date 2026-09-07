# ADR-0003：Authoring 模型采用通用 CAE 对象模型，单位固定为 SI

- 状态：接受
- 日期：2026-09-07
- 取代：`01-target-architecture.md` 初稿第 1 节的 ProblemState 分类（model / formulations /
  regions / interfaces / phases / actions / numerics / outputs）

## 背景

初稿为 ProblemState 自创了一套分类。它既不是工程师熟悉的 CAE 词汇，也没有与 YL 旧对象
一一对应，导致旧 Fortran 槽位、新发明的中间层和用户 TOML 三套词汇并存。核对两个种子算例
的旧 deck 后确认：YL 的 `.glb` 组记录、`.pre` 约束集、`.loa` 时间曲线与荷载块、`.man`
增量控制、`.opr` 输出标志，本质上已经是通用 CAE 的模型/历史对象模型，只是被压平进了
位置敏感文本。

Abaqus、CalculiX、Nastran、LS-DYNA、Elmer、MOOSE 等软件语法各异，但共享同一对象模型：
模型层（网格、命名集合、材料、截面、幅值曲线、相互作用）、历史层（有序 step，每步含分析
类型、控制、边界、荷载、输出请求）、求解层。所有对象只通过名字引用，数量全部派生。

## 决策

1. ProblemState 的顶层结构固定为：

```text
ProblemState
├── case          名称、描述、单位制
├── mesh          节点、单元、来源文件、命名集合（nset / elset / surface）
├── materials     按名字定义的本构与有量纲参数
├── sections      elset → 单元类型 + 公式（平面应变/应力、厚度、积分）+ 材料
├── amplitudes    按名字定义的时间/荷载曲线
├── interactions  接触对、Goodman、粘结、吸收边界（后续阶段）
├── steps[]       有序分析步：procedure、controls、boundary、load、activation、output
└── solver        线性求解器、线程、全局容差
```

不再使用 formulations / regions / actions / phases / interfaces 这些自创名称。
对应关系：formulations → sections；regions → mesh.sets；actions → step.boundary/load；
phases → steps；interfaces → interactions；numerics → step.controls 与 solver。

2. YL 的"组"在 ProblemState 中拆为 elset、section、material 三个对象；
   `commit_legacy_globals` 负责重新合并为旧 `.glb` 组记录所需的字段。

3. 现代输入使用上述 CAE 词汇，不暴露 Fortran 槽位名。`npoin/nelem/ngroup/nmats/mdofn`
   等数量一律派生；场与自由度由 section 的 formulation 派生。

4. 单位制固定为 SI：长度 m、力 N、应力 Pa、质量 kg、密度 kg/m³、时间 s、温度 K。
   `case.units` 必须显式写 `"SI"`；未写或写其他值为 `INVALID_INPUT`。不做单位换算，
   不接受 kPa/MPa/cm/gf 等变体；单位 profile 版本（`SI-v1`）写入 build manifest。

5. M5 阶段命名集合由网格文件提供，不做几何拓扑选择；拓扑选择留待后续能力。

## 后果

- M0 不受影响：基线、构建、运行器和参考结果与输入模型无关。
- M3 的 ProblemState 类型和 M5 的 TOML v1 规范按本 ADR 设计；`schemas/case.schema.json`
  的 bootstrap 结构同步改为上述顶层键。
- `cases/migration/*/state-map.json` 记录旧文件字段到 CAE 对象的映射；`03-case-strategy.md`
  给出首批映射表。
- 用户输入可以直接按 Abaqus/CalculiX 的心智模型书写；普通二维静力算例约 30～50 行。
- 单位错误只能由数值范围检查和物理判据兜底，因此 M5 的 validate 必须包含材料参数
  合理范围警告，但不得据此自动修正。
