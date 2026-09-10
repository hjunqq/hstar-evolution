# M4-02：适配器成为默认入口，两条路径数值等价

- 日期：2026-09-11
- 前置：M4-01（矩阵 `docs/m4/M4-01-acceptance-matrix.md`），M2/M3 已有条件签收
- 相关裁定：ADR-0008 §4（先测噪声后定容差）、ADR-0009（观测面 / 运行存在面）

## 1. 出口条件与实测

`docs/02-migration-plan.md` M4 行四条出口条件：

| 出口条件 | 实测 |
|---|---|
| 首批基准状态逐字段等价 | `yl_state_diff` 两例各 `PASS compared=190 skipped=79`——**三个检查点的全部发出字段**，不只是 `model_ready` |
| 两条路径的关键结果在容差内一致 | **严格相等**：两例 DISPLACEMENT/STRESS 均 `max|d| = 0.000e+00`。容差按 ADR-0008 §4 定为 `atol = rtol = 0`，因为噪声测不出来（56 对重复运行，`docs/m4/evidence/noise/noise.json`） |
| 新 Legacy Adapter 成为白名单切片默认入口 | `yl_adapter_mode` 默认 `.true.`；`release` 起链接 `yl_adapter_entry.f90` |
| 回退开关经过测试，但不会自动触发 | `tools/yl_fallback_check.py` 四条断言全过，见 §3 |

## 2. 数值等价是怎么达成的

M4-01 结束时适配器只能产出 `model_ready` 快照。M4-02 让它真正驱动求解，接入点落在
`global_data` 的**文件打开之后、第一条读取之前**（`Global.f90:757`，一条原本就空的行）：
legacy 的全部单元照常连接（求解器的结果从这些单元写出），而其后的读取一条都不执行。

legacy 侧改动 **19 行，且不改变任何文件的行数**——每一处都是就地前缀，接入点用的是空行。
三个检查点锚点、七个 reader 注册表站点、`M2-01-checkpoints.md` 的全部行号引用一个都没动。

### 2.1 覆盖式接入被 M3 的所有权闸门否决

第一版设计想在 `model_ready` 处**覆盖** legacy reader 建好的全局量。
`commit_legacy_globals` 直接拒绝：`move_alloc` 到别人分配的目标上会静默丢弃那块内存。
**这不是缺陷，是闸门按设计工作**，而覆盖式接入恰是它要防的那件事。
详见 `docs/m4/M4-02-finding-observation-vs-existence.md`。

### 2.2 运行存在面

映射表回答「我们比较什么」，求解器要的是「什么必须存在」。ADR-0009 拆开两者：
`docs/m4/runtime-state-manifest.toml` 由 `tools/yl_runtime_scan.py` **机械清点**接入点之后
`global_data` 建立的状态（133 处分配 + 73 个 `.glb` 标量），每条都有处置，
门禁 E0–E5 双向对账，**冻结基线不动**。

## 3. 回退开关：`tools/yl_fallback_check.py`

四条断言，**第四条才是这个工具的价值**：

- **F1** 默认路径（不带开关）在每个 golden 算例上严格复现冻结参考；
- **F2** `--adapter=off` 也复现——**回退必须是能跑的路径，不是写在文档里的路径**；
- **F3** 两条路径**互相**一致。F1 和 F2 可以同时成立而两条路径仍在参考不包含的东西上不同；
- **F4** **开关自己不做任何决定**。适配器拒绝的 deck 必须**停下**并点名它拒绝的方言，
  **不得**悄悄回落到 legacy reader。自动回落意味着一个适配器建不了模的 deck 照样出数，
  而输出里没有任何东西说明这些数是哪条路径算的。

实测：`rc=3`、`verdict=yes`、`results_written=no`。

### 3.1 F4 当场查出的一个缺陷

第一次跑 F4 得到的是 `rc=4`（INIT）。`yl_adapter_override` 把**所有** finding 都压成 INIT，
于是「方言不被支持」（exit 3）与「初始化失败」（exit 4）在对外判决上被抹平了——
而 M4-01 判据 5 断言的正是「对外判决统一」。已修：finding 自己的 `exit_code()` 现在原样
传出，UNSUPPORTED → 3、INPUT → 2、其余 → 4。

**这条缺陷是被「问一个真实的问题」问出来的**：一个被拒绝的 deck 到底报什么？

## 4. 本阶段结束的一条 M4-01 性质

M4-01 判据 12「求解器不链接任何 adapter 目标文件」**到此为止**，
这是 M4-02 出口条件的直接后果，不是回归：那条判据的全部意义在于**当时适配器还不是入口**。
`release` 现在链接 `yl_adapter_entry.f90`；`runtime-bridge` / `adapter` 两个测试目标仍链接
**拒绝式 stub**（它们不设开关，而一个「on 时静默等于 off」的 stub 比没有开关更坏）。

## 5. 明确不能据此声称

- **不能声称适配器能读白名单以外的 deck。** 它会拒绝，并要求操作者显式 `--adapter=off`。
- **不能声称现代输入路径可用。** authoring schema 仍是 bootstrap，无求解路径消费；
  这是 M5，静力域五件套的第 4 段。
- **不能声称等价对第三个 deck 成立。** 两例，两个 deck。
- **不能声称运行存在面已完备。** 它是**扫描**——扫的是 `global_data` 一个例程里的分配与
  `.glb` 标量读取。别处建立的状态、或以赋值而非分配建立的状态，在它视野之外；
  这正是裁定把它与「用真实求解推进验证」配对的原因。
