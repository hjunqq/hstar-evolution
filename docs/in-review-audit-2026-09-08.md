# IN_REVIEW 九项独立审计底稿

- 日期：2026-09-08
- 执行：Claude subagent（`audit-in-review`），全只读检查（`check` / `--selftest` / `cmp` / `grep`），
  未重建求解器、未重跑算例
- **这不是签收**。`docs/07-acceptance-and-release.md` 明确「自动全绿不等于负责人签收」。
  本文件是复核底稿，供负责人据以签字或退回；三项最关键发现已由 lead 独立复验（见文末）。

## 一、总表

| 项目 | 结论 | 一句话理由 |
|---|---|---|
| M0-01 来源清单与哈希 | SIGNABLE WITH NOTES | 三个清单 `check` 全 PASS，gidpost 桩 126 符号核实无误；但 STATUS 仍写「3 项待 M0-04c 验证」，而 M0-04c 已在同批次判定全部改判 DEFER——文字未回填 |
| M0-02 Linux 构建 | SIGNABLE | `reference/build-manifest.json` 二进制哈希、12 个运行时依赖、R17/R18 记录与文档逐字一致 |
| M0-05a 模型说明与容差登记 | SIGNABLE WITH NOTES | 节点/单元数、TOML 语法均通过；跨路径容差自标 `provisional`，且因 B02 精确重复而无观测噪声依据——文档已自曝 |
| M0-03 隔离运行器 | SIGNABLE | 七种状态的反例与两例 COMPLETED 均可在 schema/`runs/` 找到对应记录 |
| M0-04 参考结果 | SIGNABLE | B02 三次 `flavia_res_sha256` 相同；候选二进制哈希与逐值比较 `max_abs_diff=0` 均核实 |
| M0-05b M0 报告 | NOT SIGNABLE（结构性） | 报告自身写明「复核结论：待填写（不得代填）」；证据链核实完整，唯一缺口是没有第二个人 |
| M1-01 reader 清单 | SIGNABLE | 1022 静态站点、两例各 211 命中、152 reader（149 执行+3 reached_only）均由产出直接复核 |
| M1-02 checked I/O | SIGNABLE | 152/152 包装、29 条探针矩阵、R19/R21 登记、三轮审查记录均有据可查 |
| M2-01 状态字段映射表 | SIGNABLE WITH NOTES | `check` 数字一致，但 selftest 计数与锚点行号已漂移；任务文档自称 DONE 与 STATUS 的 IN_REVIEW 矛盾 |

## 二、逐项细节

### M0-01
`yl_manifest.py check` 对三个清单（legacy/39 文件、两例各 16 文件）全部 PASS。
`gidpost.F90` 133 处 `BIND(C…)` 中 126 处带 `NAME=`，与 `legacy/stubs/gidpost_stub.c` 的 126 个
`GiD_*` 定义精确对应。`1.LOA`/`1.loa` 两个大小写文件哈希在两个 input-manifest 中完全相同。

**发现**：`docs/m0/orig-worktree-diff.md`（M0-01 自己的产出）已在同批提交 `f7abe9d` 记录
「下表 3 个 VERIFY 项全部改判 DEFER」，即悬项已关闭；STATUS 仍写「3 项待 M0-04c 验证」。
文字未同步，非证据缺失。

### M0-02
`lame_cylinder/reference/build-manifest.json` 的 `binary.sha256 = 6df6ea8d18c9fa5d…` 与任务文档
一致；`runtime_dependencies` 长度 12，`unresolved_runtime_deps` 为空。R17/R18 在风险表中为
「CLOSED（M1-03）」，与 M0-02 暴露 / M1-03 关闭的时间线吻合。
（`build/` 目录下的活动构建哈希不同，但该目录被 gitignore、非证据来源。）

### M0-05a
两例 `.cor`/`.ele` 非空行计数 289/256 与 81/64，与 MODEL.md 一致；两个 TOML 均可解析。
`tolerances.toml` 的 `[cross_path]` 自称 `status = "provisional"`，而 B02 三次重复是逐字节相同
（无观测噪声），故 `atol=2.2e-12` / `rtol=1e-9` 目前只是量纲估算。文档已自曝，复核人签字时应知晓。

### M0-03
`schemas/run-manifest.schema.json` 的 `status.enum` 现 13 值，M0-03 只需的 7 个
（TIMEOUT/CRASHED/FAILED/MISSING_OUTPUT/GOLDEN_MODIFIED/INPUT_HASH_MISMATCH/COMPLETED）
均能对应；其余 6 个为 M1-03 之后新增，不在范围内。两例 `run-manifest-1.json` 状态为 COMPLETED。

### M0-04
`repeat-report.json` 两例 `runs[].status` 均 COMPLETED，三次 `flavia_res_sha256` 完全相同。
候选证据 `status=COMPLETED`、二进制哈希 `dea1a66d0b57daf4…`、`compare-*.json` 的 `passed=true`
且全部 block `max_abs_diff=0.0`。

### M0-05b
证据包表格逐项核对（source/input/build/run manifest、reference、MODEL 文档、脏树对照、
检查型构建证据、任务记录）全部指向前五项已核实的真实文件。
报告在签收节写明「复核结论 / 负责人接受记录：**待填写（不得代填）**」——需要一个人来填的空白。

### M1-01
```
python3 tools/yl_io_inventory.py check --inventory docs/m1/reader-inventory.toml \
  --sites docs/m1/io-sites.json \
  --evidence docs/m1/evidence/*/hits.json \
  --registry src/diagnostics/yl_diag_registry.f90
→ PASS: 152 readers, 59 cursor ops, 54 not_on_path groups；wrapped readers: 152/152
```
`io-sites.json` 的 `site_count=1022`（read 886 / open 80 / rewind 54 / close 2）。
两例 `hits.json` 的 `distinct_sites` 均为 211 且集合内容一致。152 条 reader 中恰 3 条
`reached_only=true`，其余 149 条命中数非零。**九项里证据链最完整的一项。**

### M1-02
R19/R21 登记且触发条件与探针对应。`M1-02-checked-io.md` 内嵌 29 条探针矩阵
（缺文件 14 + 截断/清空 8 + 类型错 5 + 盲区 2）逐条列出预期分类。
归档任务的 `review.md` 三轮审查逐条列出 Critical/Warning 及修复确认，与任务文档记载对应。

### M2-01
```
python3 tools/yl_state_map.py check
→ PASS: 269 fields (190 emitted: 162/11/17), 4 checkpoints (3 covered), readers covered 39/39, skip-class 110
```
与 STATUS 逐字一致。R23/R24 登记且描述相符。

- **漂移 1**：`--selftest` 现返回 `97/97`，任务文档记 `48/48`。根因是 `state-field-map.toml` 在 M2-01
  之后被 M2-02（`4448d9c`）及几何派生规则提交（`4b70161`）继续修改，用例随之增长。
- **漂移 2**：三个 checkpoint 的 `site` 现为 `Fem.f90:1909/3603/3657`，文档写 `1908/3601/3654`
  （M1-02 包装 reader 时 `Fem.f90` 行号下移）。**anchor 哈希完全未变**，工具靠内容哈希定位，
  身份没丢——漂的是给人看的行号提示。
- **自评矛盾**：`docs/tasks/M2-01.md` 头部写「状态：DONE（待提交）」，STATUS 同项为 IN_REVIEW。
  按 `docs/07`，「自审 + 双路 Claude subagent 审查」不构成独立复核，STATUS 判 IN_REVIEW 是对的。

## 三、链条与根因

1. **结构性根因（覆盖全部九项）**：卡住的直接原因是同一件事——**独立复核人始终缺席**，
   不是九个独立的证据问题。最下游也是唯一汇总点是 **M0-05b**，它汇总 M0-01～M0-05a 五项；
   其自身证据链已核实完整，签收它不需要新证据，只需要一个人读完签字。
2. **证据链依赖**：M1-01 → M1-02，M1-01/M1-03 → M2-01。每一环独立可复现，链条上没有
   「下游其实空转」的风险；真正传递下去的只有「没有复核人」这一个结构性缺口。
3. **文档漂移集中在 M2-01**：因为 `state-field-map.toml` 是被后续任务持续复用/修改的活文档。
   复核人应当用 `git show <M2-01 提交>:docs/m2/state-field-map.toml` 还原到当时版本核对，
   而不是对着 HEAD 核对文档里的旧数字。

## 四、复核人行动清单（最短路径优先）

1. 读 `docs/m0/M0-report.md` 并签字——五项 M0 子任务证据均可复现，无需返工；
   签收它会连带解除 M0-01～M0-05a 的「无复核人」状态。
2. ~~回填 M0-01 措辞~~（已由 lead 订正，见文末）。
3. 签收 M1-01 与 M1-02——技术底稿最完整，抽查本报告列出的命令即可复现全部数字。
4. M2-01 签收前先解决：统一任务文档头部状态与 STATUS；锚点改为只引用 anchor 哈希
   （避免代码再变又脱节）；selftest 计数以复核当下重跑结果为准。
5. M0-05a 的跨路径容差不阻塞签收，但签字时应记录「这两个数字目前没有噪声实证支撑」。

## 五、lead 的独立复验

三项最关键发现由 lead 亲自复验，均属实：

| 发现 | 复验结果 |
|---|---|
| M2-01 锚点行号漂移 | 映射表现为 `Fem.f90:1909/3603/3657`，STATUS 写 `1908/3601/3654`；anchor 哈希未变，`check` 仍 PASS ✓ |
| M2-01 selftest 计数漂移 | 实际 `97/97`，文档 `48/48` ✓ |
| M0-01 悬项其实已关闭 | `orig-worktree-diff.md:15`「下表 3 个 VERIFY 项全部改判 DEFER」，STATUS 仍写待验证 ✓ |

已据此订正 STATUS 的陈旧文字（纯事实订正，不改变任何项的 IN_REVIEW 状态）。
