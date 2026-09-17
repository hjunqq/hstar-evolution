# 迁移前置缺陷修复登记

本文件登记的是**为了让一个真实算例可被验收而必须先修的 legacy 缺陷**。

它与「现代化能力」是两件事，必须分开计数：

- 这里的每一条都**不算**任何现代输入能力；它们不扩 authoring schema、不进 ProblemState、
  不改变现代路径能表达什么。修完之后，能力清单和修之前一模一样。
- 它们唯一的作用是把一个算例从「跑不起来、没有参考」变成「可运行、可冻结」，
  从而使后续的能力迁移有一个可比的基准。

准入门槛（三条都要满足才动 legacy）：

1. 缺陷**不是**迁移/包装/构建引入的——必须先在未改动的 legacy 快照上复现；
2. 修改**非常局部**，且有**独立依据**（最好是 legacy 自己在同类站点的写法），
   不是我们对本构或算法的重新判断；
3. 对既有全部 golden 算例**可证惰性**——不是"应该没影响"，是量出来的。

---

## PD-1 · `kind_wt` 未初始化 → 解引用未关联的 `isatu`

| | |
|---|---|
| 日期 | 2026-09-17 |
| 提交 | `51515e3` |
| 位置 | `legacy/yl/Stiff.f90:818`（`dep`，DUNCANCHANG / `type_stiff==1` 分支） |
| 阻塞的算例 | `cases/cases/new_duncan_chang`（SIGSEGV，`rc=174`，输出截断在 5818 字节） |
| 归属 | **legacy 原有缺陷**；未改动的 5414e73 快照同样 `rc=174` |
| 改动 | 一行：`kind_wt=props(matno)%mechanical%solid%kind_wt`，插在 `isat=0` 之前 |
| 依据 | 形式逐字取自 legacy 自己的兄弟站点 `Stiff.f90:1136`（SandPZ），后者在同一个 `type_problem=='Q'` 守卫内无条件赋值 |
| 惰性证据 | ① 全树 1283 个 `.mat` 的 1810 条 solid 记录 `kind_wt` 分布为 `{0: 1810}`，`isatu` 在整个语料里从未分配，被守卫的分支永远走不到；② 重建 release 后 MODERN 与 FALLBACK 两道门禁全绿，六个既有 golden 算例在现代输入与 legacy 两条路径上 `max|d| = 0` |
| 解锁 | `nonlinear_elastic.new_duncan_chang` 于同日冻结参考（3 次运行 `1.flavia.res` 逐字节相同，30 块 / 2100 值） |

详细调查过程见 [`sigsegv-investigation.md`](sigsegv-investigation.md)。

**明确记账**：PD-1 不是 DUNCANCHANG 的现代化能力。DUNCANCHANG 能力的进度从
「参考已冻结、现代输入尚不支持」起算。

---

## 不予修复的登记

同批查清但**不**修的，列在这里，以免以后重复调查：

| 算例 | 第一失效点 | 为什么不修 |
|---|---|---|
| `cases/cases/mini_goodman` | `Elements.f90:3368`，`elcod` 第 2 维越界 | 是**算例**缺陷不是代码缺陷：deck 把接缝组声明成 2 节点 b2，却给了 4 节点的 `1.ele` 表，组尾又按 b2 写，自相矛盾；且目录带 `gen_all.py`，是自造算例。legacy 这条路径对正常的 q4 接缝用法是正确的（全树 119 条带 `elcod_local` 的组定义里 95 条是 q4） |
| `cases/cases/goodmanLU` | `Global.f90:878`，`1.ftr` 读到文件尾（`rc=2`，M1 守卫按设计拦下） | deck 不完整，不是代码问题 |
| `cases/cases/goodman_evolution` | 未定位（`rc=174`） | GOODMAN 暂记为「无可验收真实算例」，不消耗主线资源；有完整可运行 deck 时再恢复 |
