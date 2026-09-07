# 算例组织与演进策略

## 目录分层

```text
cases/
├── golden/       不随实现修改的参考算例
├── migration/    当前迁移阶段的新旧输入对
└── probes/       一个能力或一种故障的最小算例
```

### golden

用于回答“旧 YL 在固定环境下原来做了什么”。输入冻结；结果不直接保存大量二进制，而保存：

- 来源仓库和提交；
- 输入文件 SHA-256；
- solver binary/build manifest；
- state fingerprint；
- 关键数值指标与容差；
- 收敛历史摘要；
- 物理判据结果。

### migration

每个迁移包包含：

```text
case-name/
├── legacy/             已冻结旧输入
├── modern/case.toml    新输入（CAE 对象模型，SI 单位，见 ADR-0003）
├── expected.json       数值与物理判据
├── state-map.json      旧文件字段 → ProblemState 对象的映射和已知差异
└── README.md           目的、能力和限制
```

`state-map.json` 按下表的方向记录；首批静力切片的映射如下：

| ProblemState 对象 | YL 旧输入来源 |
|---|---|
| mesh.nodes / mesh.elements | `.cor` 坐标；`.ele` 连接表及组号 |
| mesh.sets（elset） | `.ele` 末列组号；`.glb` NGROUP 记录的 NAME |
| mesh.sets（nset） | `.pre` NFIXSETS 的节点列表（导入时生成命名集合） |
| materials | `.mat` 的 ELASTIC_ISOTROPIC 等记录 |
| sections | `.glb` 组记录的 NAME、MATNO、TYPE_STIFF、elcod_local、CLASS、FIELDID |
| amplitudes | `.loa` 开头的 tcurves |
| steps[].boundary | `.pre` 约束集的自由度码与给定值 |
| steps[].load | `.loa` 的点荷载、边荷载、体力（按 BLKS 分块） |
| steps[].controls | `.man` 的 nincs 与每增量的 miter、toler、nstep |
| steps[].output | `.opr` 输出标志；`.glb` 的 gid_* / res_* |
| solver | `.sol`；`.glb` 的 TYPE_SOLVER（PROFILE / PARDISO） |

YL 的"组"同时承担 elset、section 和材料引用，映射时必须拆开；`.glb` 中的
`npoin/nelem/ngroup/nmats/mdofn` 在 ProblemState 中为派生量，不作为输入字段。

迁移完成后可保留于 migration 作为审计材料，或提炼为 golden + probe；不得覆盖原 golden。

### probes

探针保持最小，每个只回答一个问题，例如：

- 缺一条材料引用是否在 check 阶段拒绝；
- 一致质量和集中质量是否产生预期模态关系；
- VIE 激励变化是否降低指定边界的反射能量；
- restart 前后状态是否连续。

探针必须声明预期关系：`must_preserve`、`must_change`、`must_reduce` 或明确解析值。

## 首批算例梯队

| 梯队 | 算例 | 用途 |
|---|---|---|
| A | cooks_membrane | 2D Q4 静力回归例：Cook 形网格 + 重力体力（非经典剪切荷载基准） |
| A | lame_cylinder | 2D Q4 静力回归例：环形网格 + 重力体力（非 Lamé 内压模型） |
| A′ | patch_2d、lame_probe | M5 新建：常应变 patch test 与符合解析假设的 Lamé 探针 |
| B | mini_3d | 3D 基础路径 |
| B | mini_modal | 模态与质量矩阵 |
| B | mini_dynamic | 固定边界动力 |
| C | mini_mc | 弹塑性 |
| C | mini_rebar | 钢筋/粘结 |
| C | mini_thermal | 温度场 |
| D | train11_staged_foundation | 施工阶段 |
| D | train10_dynamic_vie | VIE 与复杂动力 |
| D | train12_seepage_steady | 渗流及物理门 |

已核实两个 A 梯队算例的 `.loa`、`.mat`、`.man`、`.opr`、`.sol` 字节相同，荷载仅有重力体力，
材料 E=2.5e10 Pa、ν=0.2、ρ=2400 kg/m³。它们只能作状态与数值回归例；解析解判据由 A′ 探针承担。

A 梯队进入 M0；其余在对应阶段开始前才导入，避免仓库过早积累无法判定的算例。

## 算例准入规则

新算例必须：

1. 有单一明确目的；
2. 输入来源和许可可追溯；
3. 不依赖仓库外未登记的模板；
4. 不提交运行日志和可再生大文件；
5. 有机器可判定的预期结果；
6. 标记其验证等级，不把“能跑完”称为验证通过。

