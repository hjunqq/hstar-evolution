# state

M2-02 状态导出（checkpoint state dump）。只读观测，不参与计算。

| 文件 | 来源 | 作用 |
|---|---|---|
| `yl_state_io.f90` | 手写 | `state_writer_t` 与线格式原语：`state_open/state_close`、`begin_field/end_field`、`put_i32/put_f64/put_str`、`state_fail`。自带 `iostat/iomsg`，不复用 `yl_ios/yl_msg`；`access='stream', form='formatted'`，行尾 LF；打开时断言 `ink` 为 32 位、`irk` 为 IEEE binary64 |
| `yl_state_adapters.f90` | 手写 | 25 个 `emit_<name>(w)`：ragged 数组、重建值与概念字段。禁止赋值 legacy 全局量、禁止分配或重关联 legacy 对象、禁止调用 legacy 例程或读输入单元；每层父对象单独 `allocated/associated` 判定；未定义关联状态的指针不得查询 |
| `yl_state_dump.f90` | **生成文件，请勿手改**：`python3 tools/yl_state_map.py gen-fortran` | 由 `docs/m2/state-field-map.toml` 生成：模块 `yl_state_serializer`，`yl_state_dump(checkpoint)` 按检查点分派，逐字段导出 |

编译序（`tools/build.sh`）：`src/diagnostics/*` → legacy 模块（至 `Level.f90`）→ 本目录三文件 → `Fem.f90`。

开关：`--dump-state=DIR`（`yl_diag`），与 `--check-legacy` 互斥。关闭时不打开任何单元、不产生文件。

格式、规范化与比较见 `docs/m2/M2-02-state-serializer.md`。
