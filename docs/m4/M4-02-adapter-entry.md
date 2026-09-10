# M4-02：适配器进入求解器（进行中）

- 日期：2026-09-10
- 前置：M4-01 已交付（矩阵 `docs/m4/M4-01-acceptance-matrix.md`）；M2/M3 已由负责人有条件签收
- 相关：ADR-0008 §4（先测噪声后定容差）、R28（判据 13，容差半边已关闭）

## 0. 本文件先记两件已经确定的事

**(1) 跨路径容差已定案为严格比较，因为噪声测不出来。**
`tools/yl_noise.py` 用同一二进制、同一输入、同一环境，两例各跑 8 次、两两 28 对（共 56 对），
严格比较（`atol = rtol = 0`）下 `max|d|` 处处为 0。阴性对照把一个位移分量改动 `1e-18`
即被报出（3 对中 2 对出现差异，STRESS 保持沉默），所以这次的安静是有意义的安静。
两例 `tolerances.toml` 的 `[cross_path]` 已改为 `atol = rtol = 0`、`status = "measured"`。
**限定**：这把**观测到的**噪声在该二进制/输入/环境/重复次数下界定为 0，
**不是确定性证明**，也不涉及别的线程数或环境。

**(2) 覆盖式接入（override）在结构上是被禁止的——而禁止它的那道闸门是对的。**
见 §1。

## 1. 第一版设计被 M3 的所有权闸门当场否决

**原计划**：在 `model_ready` 锚点之前挂一个钩子，让适配器把 legacy reader 已经建好的全局量
**覆盖**掉，然后求解照常继续。这样只动 legacy 一行，且能立刻回答那个承重问题——
**映射表登记的状态，是否足以复现结果**。

**实测结果**：`commit_legacy_globals` 直接拒绝：

```
commit_legacy_globals: INTERNAL runtime.*: one of element, group, listp_group, prescrib,
tcurves, trans or props is already allocated but commit_owned is false -- committing
would silently leak a foreign allocation via move_alloc; refusing to run in a process
whose legacy globals were populated by something other than this module
```

**这不是缺陷，是 M3-01 的所有权闸门按设计工作。** `move_alloc` 到一个已被别人分配的目标上
会静默丢弃那块内存；闸门要求 commit 只写自己拥有的全局量。**覆盖式接入恰好就是它要防的那件事。**

**结论：适配器必须是 reader 的替代者，不是它的覆盖者。** 这正是 `docs/02-migration-plan.md`
M4 行的原话——「旧 deck **不再由原 reader 直接驱动全局变量**」。第一版设计想绕开这句话
省点力气，闸门把它挡了回来。**记在这里，是因为「一道闸门挡住了实现者想抄的近路」
比「闸门跑绿了」更能说明它值不值得存在。**

## 2. 采用的设计

**接入点前移到 reader 之前**（`Fem.f90:106`，`diag_set_mode_from_argv()` 与第一个 `.inp`
读取之间），此时全局量尚未分配，所有权闸门自然满足；随后**逐点关掉 legacy reader**。

```
--adapter=on:
  Fem.f90:106  call yl_adapter_override()   ! deck -> ProblemState -> runtime -> commit
  Fem.f90:117  global_data                  ! 关
  Fem.f90:185  runblks 读取                  ! 关
  Fem.f90:191  material_set                 ! 关
  Fem.f90:193  modf_element_lib             ! 关
  Fem.f90:195/197/198/209-212  空段 reader   ! 关
  Fem.f90:215  output_read                  ! 关
  Fem.f90:219  result_zero 分配              ! 关（commit 自己分配）
  Fem.f90:1682 external_load_1              ! 关
  Fem.f90:1873 prescrib_set                 ! 关
  Fem.f90:1896 external_load_2              ! 关
  Fem.f90:1899 boundt                       ! 关
  ……随后求解照常运行在适配器状态上
```

### 2.1 legacy 侧改动的形状：19 行，行数不变

所有改动都是**就地前缀**（`if (.not. yl_adapter_mode) ` 加在原语句前），接入点用的是
一条**原本就空的行**。因此：

- **文件行数完全不变**，`Fem.f90:N` 形式的引用**一个都没动**——三个检查点锚点
  （1909/3603/3657）、七个 reader 注册表站点、`M2-01-checkpoints.md` 的全部行号引用；
- `git diff` 在 `Fem.f90` 上恰好显示 **19 行改动**，无其他噪声；
- 重新锚定那套级联流程（`docs/m1` 的 reader 注册表 + `diag_check_open` 字面量 + 扫描 + 校验）
  **完全不需要跑**。

**为什么值得为此把可读性让一点**：重新锚定是有文档的机械流程，但它在 M1-03 里造成过一次
弯路。一个 `;` 或一个前缀读起来丑，但**它不可能错得无声无息**。

### 2.2 stub / 实体两分的链接缝

`yl_adapter_override` 是**无参外部子程序**，所以 `Fem.f90` 不需要新增 `use` 行
（这也是改动能压到 19 行的原因）。恰好链接一个实现：

| 目标 | 链接 | 行为 |
|---|---|---|
| `release`（及其余全部目标） | `src/adapter/yl_adapter_entry_stub.f90` | **拒绝**，`UNSUPPORTED` / exit 3 |
| `solver-adapter` | `src/adapter/yl_adapter_entry.f90` | 适配 + 提交 |

**stub 拒绝而不是静默返回**，理由写在它自己的文件头：一个「on」在某些构建里悄悄等于「off」的
回退开关，比没有开关更坏——操作者要了新路径，什么都没被告知，拿到的是旧路径。
M4 出口条件「回退开关经过测试，但不会自动触发」要的正是**开关自己不做任何决定**。

`release` 仍然可机械核对不依赖任何适配器目标文件：

```
grep -o "yl_adapter_[a-z_]*\.o" build/release/build.log   # 只应有 yl_adapter_entry_stub.o
```

### 2.3 开关的解析

`--adapter=on|off`，默认 **off**：legacy 路径在跨路径比对通过之前仍是默认入口。
拼写严格——`--adapter=bogus` 是 `PARSE` / exit 2，重复给出也是 exit 2，
**打错的开关永远不会被读成 off**。

## 3. 当前状态（进行中）

- `commit_legacy_globals` 在 `--adapter=on` 下**成功**（所有权闸门通过，全局量由适配器建立）。
- 随后求解在 `Fem.f90` 早段崩溃（release 构建无行号，正在用 debug profile 取回溯）。
  **这正是本设计要回答的那个问题的答案形式**：映射表没登记、而求解器又需要的状态，
  会以崩溃或数值差异的形式逐个显形。每一个都要单独判定是「映射表漏了」还是
  「这一段本来就该由 legacy 派生代码做、不属输入状态」。

**尚未建立的**（不得提前声称）：
- 两条路径的数值等价；
- 三个检查点的状态等价（今天只有 `model_ready`，且那是 M4-01 的影子差分，不是本路径）；
- 适配器成为白名单默认入口；
- 坏输入门在适配器路径上的行为。
