# 工具规划

M0～M5 需要的命令：

```text
yl-case hash          计算并检查算例输入哈希
yl-case clean         只清理 manifest 声明的可再生产物
yl-check legacy       旧输入预检查
yl-check modern       现代输入预检查
yl-state dump         导出第一次组装前状态
yl-state diff         对比两个状态摘要
yl-run                运行并生成 build/run manifest
yl-import-case        从登记来源导入算例，不导入运行垃圾
```

已实现：

| 计划命令 | 实现 | 说明 |
|---|---|---|
| `yl-case hash` | `tools/yl_manifest.py generate / check` | 逐文件 SHA-256 清单；`check` 对缺失、篡改、未登记文件均非零退出 |
| `yl-run` | `tools/yl_run.py` | 隔离目录、单线程、进程组超时、前后 golden 重哈希；解析 `HSTAR_DIAG`/`HSTAR_CHECK` 报文；状态 INPUT_HASH_MISMATCH / TIMEOUT / CRASHED / INPUT_ERROR / UNSUPPORTED / INIT_ERROR / SOLVE_ERROR / INTERNAL_ERROR / FAILED / GOLDEN_MODIFIED / CHECKED / MISSING_OUTPUT / COMPLETED；`--expect-status` 命中期望时退出 0 |
| （结果解析） | `tools/yl_parse_flavia.py` | 解析 `1.flavia.res`，检查节点数、有限性、重复 ID、列数一致 |
| `yl-state diff`（数值部分） | `tools/yl_compare.py` | 先结构后数值的逐分量比较；默认精确相等；可加载 `tolerances.toml` 指定节 |
| 构建 | `tools/env.sh`、`tools/build.sh` | 见 `docs/build-linux.md`；`trace` profile 供 gdb 计数 |
| （reader 清单） | `tools/yl_io_inventory.py`、`tools/yl_io_trace.sh` | 静态 I/O 普查、gdb 断点实证、注册表校验与渲染（M1-01）；`gen-fortran` 生成 `src/diagnostics/yl_diag_registry.f90` |
| （checked I/O 改写） | `tools/yl_wrap_reads.py` | 按注册表锚点给 read/open 加 iostat 与 `diag_check_*` 调用；幂等；`--dry-run`、`--line-map`（M1-02） |
| `yl-check legacy`（雏形） | `build/release/hstar --check-legacy` | 只跑启动 reader 后退出 0 并输出 `HSTAR_CHECK*` 摘要 |
| （故障探针） | `tools/yl_probe.py` | 从 golden 派生 `cases/probes/failure/*/probe.toml`，运行并断言结构化错误；M1-03 原语 `set_field`/`insert_line`/`duplicate_line`，断言 `value`/`field`/`diag_count`/`indices`，`binary_args`（如 `--max-entities=N`） |

工具实现必须 fail-closed：无法判断时返回未验证，不得返回通过。

