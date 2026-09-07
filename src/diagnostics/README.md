# diagnostics

结构化错误、退出码、state dump、fingerprint、状态 diff、收敛摘要和崩溃前诊断。

错误类别至少包括：`INVALID_INPUT`、`UNSUPPORTED_CAPABILITY`、`INITIALIZATION_ERROR`、
`SOLVE_FAILURE`、`INTERNAL_ERROR`。

## M1-02：`yl_diag` 与 `yl_diag_registry`

| 文件 | 来源 | 作用 |
|---|---|---|
| `yl_diag_registry.f90` | **生成文件，请勿手改**：`python3 tools/yl_io_inventory.py gen-fortran` | 由 `docs/m1/reader-inventory.toml` 的 `[[reader]]`（按出现顺序，idx 从 1 起）生成：`YL_NREADERS`、`YL_READER_ID/SITE/FILE/UNIT/STAGE/FIELD/SEQ` 常量表，以及每个 reader 的 `RD_<sanitized id>` 整数常量（源码只通过它引用 reader）。`reached_only` 条目 stage 为 `reached_only`、seq 为 0；fields 超过 256 字符截断。 |
| `yl_diag.f90` | 手写，不依赖任何 legacy 模块 | 退出码常量 `EXIT_OK/INPUT/UNSUPPORTED/INIT/SOLVE/INTERNAL`（0/2/3/4/5/6）；模块变量 `yl_ios`、`yl_msg` 供包装后的 `read/open(...,iostat=yl_ios,iomsg=yl_msg)` 使用；`diag_check_open`、`diag_check_read`（首错即退）；`diag_raise` + `diag_fail`（累积后按最大退出码退出，供 M1-03/M3 语义检查）；`diag_internal`；`--check-legacy` 模式（`diag_set_mode_from_argv`、`diag_check_mode`、`diag_summary_and_exit`）。 |

编译序：`tools/build.sh` 先编译这两个文件（registry → diag），再编译 legacy 模块；两者的哈希记录在
`build-manifest.json` 的 `sources.files` 中（按仓库相对路径）。

报文契约（stderr 单行，`tools/yl_run.py` 用 shlex 解析）：

```
HSTAR_DIAG schema=1 code=<CODE> exit=<n> severity=fatal stage=<stage> file=<file> unit=<unit> reader=<id> site=<site> seq=<seq> index=<index> iostat=<ios> field="<field>" message="<iomsg>"
```

`field`/`message` 内的 `"` 与 `\` 以反斜杠转义，换行替换为空格。退出统一为 `flush` 后 `call exit(code)`。

check 模式（首个命令行参数为 `--check-legacy`）向 stdout 写：

```
HSTAR_CHECK schema=1 mode=check-legacy status=OK errors=0 readers_executed=<n> readers_registered=<N>
HSTAR_CHECK_READER id=<id> n=<count>      # 每个计数非零的 reader 一行
```

一致性校验：`python3 tools/yl_io_inventory.py check --evidence docs/m1/evidence/*/hits.json` 会解析 `legacy/yl` 中
所有 `diag_check_read(...)` 调用的第三个实参，要求它是注册表生成的 `RD_*` 常量，并报告"已包装 / 注册"数量。
