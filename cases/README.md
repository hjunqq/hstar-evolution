# 算例库

- `golden/`：冻结的旧程序行为参考；
- `migration/`：同一工程的新旧输入对及状态映射；
- `probes/`：一个能力或一个错误的最小可判定实验。

当前只导入 A 梯队的 `cooks_membrane` 和 `lame_cylinder`。其 legacy 目录只保留求解所需输入，
不保存 `.chk/.rtt/.flavia.*` 等可再生结果。

算例来源和计划见 `manifest.toml`；完整策略见 `docs/03-case-strategy.md`。


## probes/failure

`probes/failure/<id>/probe.toml` 是 M1-02 的故障注入探针：从 golden 算例派生一个坏输入（删文件、截断、清空、改字段），
并写明期望的退出状态与 `HSTAR_DIAG` 诊断。探针目录只存 `probe.toml`，坏输入在运行时由 `tools/yl_probe.py`
物化到 `runs/probes/<id>/case/`。矩阵与格式见 `probes/failure/README.md`。
