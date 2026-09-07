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
├── modern/case.toml    新输入
├── expected.json       数值与物理判据
├── state-map.json      新旧字段映射和已知差异
└── README.md           目的、能力和限制
```

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
| A | cooks_membrane | 2D Q4 静力、网格与位移/应力基线 |
| A | lame_cylinder | 弹性解析解和边界条件 |
| B | mini_3d | 3D 基础路径 |
| B | mini_modal | 模态与质量矩阵 |
| B | mini_dynamic | 固定边界动力 |
| C | mini_mc | 弹塑性 |
| C | mini_rebar | 钢筋/粘结 |
| C | mini_thermal | 温度场 |
| D | train11_staged_foundation | 施工阶段 |
| D | train10_dynamic_vie | VIE 与复杂动力 |
| D | train12_seepage_steady | 渗流及物理门 |

A 梯队进入 M0；其余在对应阶段开始前才导入，避免仓库过早积累无法判定的算例。

## 算例准入规则

新算例必须：

1. 有单一明确目的；
2. 输入来源和许可可追溯；
3. 不依赖仓库外未登记的模板；
4. 不提交运行日志和可再生大文件；
5. 有机器可判定的预期结果；
6. 标记其验证等级，不把“能跑完”称为验证通过。

