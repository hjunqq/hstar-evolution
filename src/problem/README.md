# problem

工程语义与输入真值层。包含 `ProblemState`、材料/单元/阶段等类型、语义规则、capability gate、
finalize 和 build manifest。

本层不得依赖旧文件格式和求解工作数组。



## M3-01：最小类型与可选性

| 文件 | 作用 |
|---|---|
| `yl_problem_optional.f90` | `opt_int` / `opt_real` / `opt_text` / `opt_logical`：私有分量 + `has` 标志（默认 `.false.`），配 `opt_set/opt_get/opt_is_set/opt_clear/opt_value_or/opt_equal`。**unset、显式零、空集合是三件不同的事**：显式零 `opt_set(x, 0.0_real64)` 报告已设置；集合用 `allocatable` 的未分配表示 unset、零长表示 empty。分量私有，因此未经 `opt_get` 读取值是编译期错误 |
| `yl_problem_types.f90` | `problem_state_t` 及 24 个成员类型，按 ADR-0003：`case / mesh / materials / sections / amplitudes / interactions / steps / solver`。100 个字段中 98 个对应 `docs/m2/state-field-map.toml` 的已导出行，2 个为 M5-only（`case%units`、`amplitudes%name`），均带 `@m5-only` 标注 |
| `yl_problem_selftest.f90` | 类型级自检程序（50 项），验证三态语义在 release 与 strict（`-init=snan,arrays -fpe0`）下都成立 |

构建：`tools/build.sh problem-types [--profile release|strict]`。**独立目标**，不进求解器链接链；
求解器不漂移的判据是 GNU build-id 相等（整文件 SHA-256 不可用：同源码重建也会差几个字节的随机临时标记）。

逐字段表见 `docs/m3/M3-01-problemstate.md`（生成文件），核对用 `python3 tools/yl_problem_check.py check`。
本阶段只定义类型，不含 parse / normalize / validate / finalize / commit（M3-02、M3-03）。
