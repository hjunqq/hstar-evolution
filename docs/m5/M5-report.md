# M5：统一 authoring schema 的第一次闭环

- 日期：2026-09-13
- 前置：M4 阶段签收（2026-09-12），ADR-0008（材料域为第二域；单轨 authoring → ProblemState → solver）
- 门禁：`tools/yl_modern_check.py`（N1/N2/N3），接在 `release` 构建里，紧随 M4-02 的 fallback 门禁

## 1. 五条判据与实测

负责人 2026-09-11 把 M5 的完成判据固定为五条，以**用户可见能力**为准。逐条如实：

| 判据 | 实测 | 证据 |
|---|---|---|
| 1 新格式能完整表达现有两个静力 golden 算例 | 成立 | `cases/golden/static_2d/*/modern/case.toml`（66 / 76 行）；契约 `docs/m5/authoring-contract.md` |
| 2 有明确 schema 校验和可读错误信息 | 成立 | `src/authoring/yl_authoring_keys.f90` + `_report.f90`；反例套件 **33/33**（`bash tools/build.sh authoring`）；错误形如 `case.toml:30: INVALID_INPUT material[1].density: wrong type / got string, expected real` |
| 3 新格式 → ProblemState → solver 路径可独立运行 | 成立 | 门禁 **N1**：工作目录里**只有** `case.toml` 与契约点名的 `.cor`/`.ele`，**没有任何 legacy 控制卡**，两例 `rc=0` 并写出结果 |
| 4 新旧输入最终结果严格一致 | 成立 | 门禁 **N2**：两例 DISPLACEMENT/STRESS 对**冻结 legacy 参考** `max|d| = 0.000e+00`，容差 `atol = rtol = 0`（沿用 ADR-0008 §4 的噪声实测结论） |
| 5 legacy 输入仍可通过回退路径运行 | 成立（M4-02 门禁持续守住） | `tools/yl_fallback_check.py` F1–F4 全过，本轮改动后复跑仍全绿 |

补充的第 5 项工程（用户侧诊断）见 §3。

## 2. 判据 3 为什么需要一条专门的断言

判据 4 单独是**不充分**的：只要工作目录里还留着 legacy deck，一条仍在偷偷读取 `.glb` /
`.man` / `.pre` 的路径同样会给出 `max|d| = 0.000e+00`，而看不出新格式其实没在驱动什么。
所以 N1 不是「跑通了」的记录，而是**投放什么文件**的断言：只投 `case.toml` 与
`mesh.file` 点名的网格对。这条断言是本里程碑唯一能把「新格式驱动求解」与
「新格式恰好没有妨碍求解」区分开的东西。

## 3. 判据 4 达成前，状态差分作为诊断工具指出的四处映射错误

端到端通路先于正确数值成立（`81cb07f`）：跑完、写出结果、数值错得离谱
（位移 9.2e11 对参考 4.6e-3，应力 0）。按负责人裁定，**状态差分此时只作诊断**，不再要求
机械全等——`sections[].name` 这类作者语义标签允许与 legacy 不同。四处缺陷：

1. **边界记录的展开维度错了**。映射层按 (nset, dof) 建 1 条记录，求解器的存储是
   (set, dof, node) 一条——`prescrib%ifixset` / `%ifixvar` / `%nodfix`。lame_cylinder 因此
   只约束了 2 个自由度而不是 18，`neq` 160 而非 144，**结构在重力下是自由的**。
   `boundary_t` 的分量名与这层语义**读起来是反的**（`%name` 是集合序号，`%nset` 是节点号），
   这正是它容易写错的原因；现在调用点写明了。
2. `materials[].name` 是 legacy `.mat` 表头词，即**相名 `SOLID`**，既不是本构模型名，也不是
   作者的引用标签（`Fem.f90:258` 拿它与 `'NSTOKS'` 比）。本构模型归 `materials[].model`。
3. `case.name` 就是 legacy 的 `probn`——**每一个输入输出文件的前缀**——所以取自 `mesh.file`。
   作者写的 `[case].name` 是人读的标签，没有 legacy 对应物；映射过去会改掉求解器自己的输出文件名。
4. `boundary.record_reaction` 默认改为 1（上报支反力），与两份冻结参考一致，
   而不是默默丢掉 legacy 路径会报的支反力。

## 4. 一条默认被移出默认表

`output.stress_averaging`（legacy `average_appear`）原在契约 §5 的默认表里，理由写的是
「输出后处理，不改变解」。**这条理由是错的**：它决定上报的节点应力**是什么**
（`Output.f90:5102`）。按契约自己的准入规则——「一个字段只有在它不是物理选择时才可以有
默认值」——它必须由作者写。现为必填，白名单 `none|smoothed|direct`，并与其他白名单行一样带反例。

**实测而非推断**：本切片上 `smoothed` 与 `direct` **不可区分**——`Output.f90:5128-5129` 的
1/2 分支只在 `nnode == 8 .and. ndimn == 3` 下成立，2-D Q4 走同一条 else。
第一次反例（`direct` → `smoothed`）**通过了**，这意味着**反例失效**，不是门禁合格；
改成 `none` 才真正证伪（应力偏 1.5e5，位移不变）。两个名字都保留，因为它们是 legacy 自己的
两种方案，会在 3-D 8 节点单元进入白名单那天分叉；**不得从「它们今天相等」反推任何结论**。

## 5. 用户侧失败路径

探真实失败路径查出三个缺陷，**全部对既有门禁隐身——因为既有门禁只喂好 deck**：

1. `--input` 文件不存在或不是契约的 TOML 子集时，**掉进 legacy reader**：对着一个从未提供
   legacy deck 的操作者打印 `Input the problem name?`，然后 Fortran traceback，`rc=30`。
   根因是原设计把可读性判决也交给 entry，而 entry 活在 `global_data` 里，`probn` 在此之前
   就要用于命名所有文件——**entry 根本轮不到**。现在**可读性、且只有可读性**由 prelude 判决；
   内容判决仍全部属于 entry，一个坏文件仍只得到一份消息。
2. 每条错误**渲染两遍**（validator 调用方一遍、拒绝路径一遍）。
3. 错误里的文件名是硬编码的 `case.toml`，不是操作者敲的那个。

另有一处静默替换：`yl_modern_step_controls` / `yl_modern_tolerances` 重读同一文件失败时
**静默回落到默认值**。今天不可达，但 `increments` / `max_iterations` / 容差是**作者写的值**，
悄悄换掉会改答案且屏幕上没有痕迹。改为拒绝。

门禁 N3 因此从一个形态长到四个（未列值 / 文件不存在 / 不是 TOML 子集 / 一次三条发现各只渲染一次）。
**这四组断言每一条都是先观察到错误输出、再写断言**，不是先写断言再假定它有效。

## 6. 签收

**负责人 Huijun 签收，2026-09-13。窄口径，逐条如下。**

M5 **仅确立**：

- 两个 golden 静力算例已经形成完整的新输入闭环；
- authoring → validation → ProblemState → solver 路径成立；
- 新旧路径最终数值结果严格等价；
- 用户侧主要失败路径能够明确拒绝并给出可定位诊断。

**不确立**：白名单之外的任何能力。
**不把门禁通过表述为独立第三方验证**——N1/N2/N3、fallback、authoring 套件都由实现方编写并运行，
与 M0 判据 18 同一个结构性缺口（单人项目，R28），签收不改变这一点。

**限定**：两个 deck、一种单元（Q4）、一种材料模型（elastic_isotropic）、一种过程（static）、
一种求解器（profile）、一种荷载（gravity）。

**带着签的债务**：`schemas/case.schema.json` 仍是旧 bootstrap，无人消费，待退役或对齐。

## 7. 下一步

按负责人裁定：先做**轻量 M1 复核**，唯一目标是关闭 **R29**——建立自动的
reader / adapter coverage gate。**不借此重新展开 M1 全套验收工程。**
R29 关闭后进入**材料域**，沿用本阶段已验证的迁移方法
（旧字段 → 语义 → 内部数据结构 → 新 schema → 回归证据）。
