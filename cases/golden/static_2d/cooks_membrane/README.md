# cooks_membrane

首批二维 Q4 静力回归基准。`legacy/` 来自现有 cases 仓库，只保存输入文件。

已核实的模型（2026-09-07，只读 deck，尚未运行）：

- Cook 形四边形网格（289 节点、256 个 Q4）；
- 荷载仅有重力体力（`.loa` 无点荷载、无边荷载），材料 ELASTIC_ISOTROPIC，
  E=2.5e10 Pa、ν=0.2、ρ=2400 kg/m³；
- 单增量静力（`.man` nincs=1），PROFILE 求解器，2 个约束集各 17 节点；
- 输出标志 gid_u=gid_s=1，不输出反力。

因此本算例**不是**同名经典解析基准，只作状态等价与数值回归例（风险 R08）；解析判据由
M5 新建的探针承担。`1.LOA` 与 `1.loa` 字节相同，Linux 下程序只打开小写文件。

M0 待补：输入哈希、固定构建信息、`1.flavia.res` 参考结果与容差（MODEL.md、
observables.toml、tolerances.toml）。
M5 待补：`modern/case.toml`，且 modern 路径不得打开 legacy deck。
