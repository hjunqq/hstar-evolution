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

## PD-2 · `mmats` 被当成材料数，而它是记录数

| | |
|---|---|
| 日期 | 2026-09-17 |
| 位置 | `legacy/yl/Material.f90` 239 / 274 / 276 / 286 / 287 / 289（六行，**行数不变**） |
| 阻塞的算例 | `cases/cases/rcbeam`、`rcbeam_crack`、`tunnel`、`tunnel_sl` —— 四个**真实且可运行**的 2-D L2 算例 |
| 归属 | **迁移引入**（M1-03 守卫），不是 legacy 缺陷 |

**与 PD-1 的区别，必须说清楚**：PD-1 是 legacy 自己的缺陷，我们修它是为了拿到参考；
PD-2 是**我们自己的守卫写错了**，它拒绝了 legacy 一直能跑的算例。两者都属「可验收性恢复」，
但性质相反，不能混为一类。

### 怎么发现的

四个算例在未改动的 5414e73 快照上 `rc=0` 且产出正常结果（5.7 MB / 5.7 MB / 2.5 MB / 43.7 MB），
在本仓库的构建上却停在：

```
code=RANGE reader="MAT.material_set.nmats" site="Material.f90:272"
field="nmats" value="3" allowed="2..2"
```

### 原因

`mmats` 数的是 `.mat` 里的**记录**，不是材料。一个材料可以带多条属性记录——
`MECHANICAL`、`HEAT`、`GEOMETRY`（Material.f90:294 / 994 / 1013）——而**每一个 2-D 杆/梁算例
都会给一个已经有 `MECHANICAL` 记录的材料再挂一条 `GEOMETRY ROD_or_BEAM` 截面记录**：

```
             MECHANICAL               SOLID    1
             MECHANICAL               SOLID    2
               GEOMETRY         ROD_or_BEAM    2     <- 第三条记录，imat 仍是 2
```

两条 M1-03 守卫都是在「每个材料恰好一条记录」的算例上标定的：
`mmats == nmats`，以及按 `imat` 判重。前者直接拒绝，后者即使放宽前者也会误报。

**一个被证伪的推断**：最初判断这是 `props(nmats+1)` 越界写——把 `.mat` 里的
`material_serial N` 标题行误读成了 `imat`。用 `-check bounds,pointers` 的快照构建跑
`rcbeam`，`rc=0` 无越界，推断被推翻；真正的 `imat` 来自下一行的第三个字段，始终在 1..nmats 内。

### 修法

- `mmats` 的范围由 `nmats..nmats` 改为 `nmats..3*nmats`（三个属性类，每类至多一条）；
- 判重的键由 `imat` 改为 `(imat, 属性类)`——同一材料上出现**两条同类**记录仍然是重复。

两条都保持 fail-closed，`imat` 超出 `1..nmats` 仍然是越界。
按仓库既有纪律用 `;` 连接语句，**文件行数不变**，因此 io 站点普查和所有读取站点行号原地不动
（`scan --check` 实测 `CENSUS CURRENT`），六个算例的 gdb 证据无需重采。

### 惰性与恢复证据

- **惰性**：七个 golden 算例逐位不变（`MODERN PASS`，`max|d| = 0`），两条 N4 断言照常成立。
  机械确认：`yl_seen` / `yl_pcls` 在全树只出现在这五行上，`diag_range` / `diag_dup` 的参数
  全是 `intent(in)`，不可能写回任何数值路径。
- **恢复**：四个算例现在都 `rc=0`。`rcbeam` / `rcbeam_crack` / `tunnel` 的
  `1.flavia.res` 与快照二进制**逐字节相同**。`tunnel_sl` 在 1 626 300 个值里有 1 586 个不同，
  `max|d| = 1e-8`（应力量级 1e-5~1e-3，200 个块的强非线性分期开挖）——属于已登记的
  **构建独立性**未决债务那一条轴，与本次改动无关（见上一条机械确认）。

---

## PD-3 · CONCRETE 卸载分支写出未初始化的 `damage`

| | |
|---|---|
| 日期 | 2026-09-18 |
| 位置 | `legacy/yl/Residu.f90:3656-3659`（不赋值）→ `:3696`（照写） |
| 归属 | **legacy 原有缺陷**；本仓库构建与 5414e73 快照对 `hstar_jobs/0406_210921_443f933d` 的 `1.flavia.res` 逐字节相同 |
| 现状 | **不修**，登记为边界 |

卸载分支 `if(estar<=estar0.or.(iload0==0.and.estar<estarm))` 只赋 `iload`、`ftv`、`y0`，
从不赋 `damage`；`:3696` 随后把这个未初始化的局部变量写进 `gpvar(nstre+2)`，
也就是 `gid_Y` 的 `Yield` 输出槽。`-O2` 下它是残留栈值（常常正好是该材料的 `E`），
`-O0` 下是 0。

**影响面**：所有开了 `gid_Y` 的 CONCRETE 算例，其 `Yield` 块里凡是落在卸载分支的点
都是垃圾值。判别方法很简单且不依赖于知道正确值：`damage` 只能取 `0` 或 `1-sqrt(cc)`，
**永远不可能 > 1**，所以任何 ≥1 的 `Yield` 值都是这个缺陷。

**为什么不修**：修它会改变输出（把垃圾变成某个确定值），而「某个确定值」是什么
需要判断 legacy 作者的意图——卸载时 `damage` 应当保持 `damage0` 还是别的。
那是本构语义判断，不是局部修复，超出「非常局部且有独立依据」的门槛。
按裁定只记边界。

**它如何差点骗过门禁**：`tools/yl_io_trace.sh` 对任何跨构建不一致都打印
「that is build independence (open debt), not instrumentation」。
这次的 `max|d| = 3.170e+10` 正是被这句话包装过去的——而 3.17e10 是材料的 E，
不是 1e-13 量级的噪声。**那句话应当带上量级判断**，否则它会把结构性差异说成噪声。

---

## PD-4 · GOODMAN/JANBU 分支读 `CONTACT` 门控的 `gapg` / `natural_thickness`

| | |
|---|---|
| 日期 | 2026-09-20 |
| 位置 | `legacy/yl/Stiff.f90:880`（快照 5414e73 的 `Stiff.f90:877`，**逐字节相同**）；`Residu.f90:1158` 是同一表达式的第二处 |
| 阻塞的算例 | `cases/cases/goodman_evolution`（SIGSEGV，`rc=174`，无输出） |
| 归属 | **legacy 原有缺陷**；未改动的 5414e73 快照同样 `rc=174 res=0` |
| 现状 | **不修**，登记为边界；GOODMAN/JANBU 不作为下一材料能力 |

`dep` 的 `GOODMAN` → `model=='JANBU'` → `type_stiff==1` 分支在调用 `PKPN` 之后直接读：

```fortran
normal_gap = element(ielem)%field(1)%gapg(igaus) &
           - element(ielem)%field(1)%natural_thickness(igaus)
```

而这两个数组**只在 `name=='CONTACT'` 时分配**（`Fem.f90:11999-12008`，`name` 即组头的
`SPTYPE` 字段，`Global.f90:1280`）。同一段分配代码里，`evk` 却是按**材料**
`material=='GOODMAN'` 分配的（`Fem.f90:12018-12020`）。**门控不一致就是这个缺陷**：
一条按材料进入的路径，去读一组按 sptype 分配的数组。

**这不是这个 deck 特殊，是整条路径都走不通**——两项全树测量：

| 测量 | 结果 |
|---|---|
| 全树 `.glb` 文件数 | **1 361** |
| 其中把组 `SPTYPE` 声明为 `CONTACT` 的 | **0** |
| 含 `GOODMAN` 材料记录的 `.mat` | 6 |
| 其中 `GOODMAN` 的 `model` 是 `JANBU` 的 | **6（全部）** |

即：语料里没有任何一个 deck 会让 `gapg` 被分配，而每一个 GOODMAN deck 都会走到读它的
那一行。**GOODMAN/JANBU 路径在 5414e73 基线上无法运行。**

### 为什么不修（与 PD-1 的门槛对照）

做过一次**仅在 scratchpad 的实验**（未进仓库）：把那一行加 `associated` 保护、
`normal_gap` 缺省取 0，并抑制同样读 `gapg` 的调试 `write(7,*)`。结果是

```
goodman_evolution  EXPERIMENT  分析跑完，1.flavia.res = 680 636 字节
                   rc=24 出现在分析之后：'give me the vdimn,coef1 and coef2?'
                   ——一个交互式后处理提问向 stdin 要输入，与求解无关
```

**只有这一处阻断，没有级联**（运行前写下的两个预期是 A「只有这一处」/ B「别处再崩」，
落地的是 A）。但它**仍然不能给出可验收参考**，三条理由：

1. **跳过罚函数是一个行为选择，不是恢复既有行为。** PD-1 能修，是因为全语料
   `kind_wt` 分布为 `{0: 1810}`，被守卫的分支**可证不可达**，那一行只能把「读未初始化
   整数」变成「读确定的 0」。这里被守卫的**正是分支本身**——`normal_gap` 该是什么，
   没有任何 oracle 能判定。
2. **`natural_thickness` 对 Goodman 节理应当取什么值是设计问题**（很可能是组头的
   `elcod_local`，本 deck 为 `2.00E-02`）。定下它就是发明一条输入映射，
   越过「不扩 schema、不重构本构」的边界。
3. **deck 自带的 `1.flavia.res` 不能充当 oracle**：690 960 字节，与实验输出
   680 636 字节不同，且**产出它的二进制未知**（本仓库基线 5414e73 提交于 2026-02-09，
   该结果文件时间戳为 2026-04-09；上游仓库在 5414e73 之后没有任何提交）。
   按 M0 规则，参考必须由可重现的构建产出。

### 它属于哪个域

`CONTACT` sptype、gap、罚函数——**这是接触与界面域的东西**。PD-4 不是一个需要单独
立项的缺陷，而是那个域开工时会正面撞上的第一件事：接触域必须回答「一个 Goodman 节理
组的 gap 与自然厚度从哪来」，回答了它，PD-4 自然关闭。**因此不在材料域里修它。**

---

## 不予修复的登记

同批查清但**不**修的，列在这里，以免以后重复调查：

| 算例 | 第一失效点 | 为什么不修 |
|---|---|---|
| `cases/cases/mini_goodman` | `Elements.f90:3368`，`elcod` 第 2 维越界 | 是**算例**缺陷不是代码缺陷：deck 把接缝组声明成 2 节点 b2，却给了 4 节点的 `1.ele` 表，组尾又按 b2 写，自相矛盾；且目录带 `gen_all.py`，是自造算例。legacy 这条路径对正常的 q4 接缝用法是正确的（全树 119 条带 `elcod_local` 的组定义里 95 条是 q4） |
| `cases/cases/goodmanLU` | `Global.f90:878`，`1.ftr` 读到文件尾（`rc=2`，M1 守卫按设计拦下） | deck 不完整，不是代码问题 |
| `cases/cases/goodman_evolution` | **已定位 2026-09-20**：`Stiff.f90:880`，`gapg` 未关联 —— 见上方 **PD-4** | legacy 原有缺陷，但修它要回答「Goodman 节理的 gap 与自然厚度从哪来」，属**接触与界面域**；材料域内不修 |
