# M9 · 2-D L2 单元域：第二个单元族

目标不是做梁荷载，而是回答一个结构问题：**现有现代输入体系能否从 Q4 自然扩展到第二种单元族。**
推进顺序沿用既有方法：真实 deck → 能力差值 → 最小 schema 扩展 → ProblemState →
复用 legacy 单元计算 → solver → 严格回归。

## 0. 里程碑合同

| | |
|---|---|
| 目的 | 证明 `[[section]]` / `[[material]]` / `mesh` 的现有词汇能容纳第二个单元族，不需要新层 |
| 范围 | 2-D、`rcbeam` 这一个真实 deck 所需的单元族与截面语义 |
| 非范围 | 3-D beam、梁/板荷载、转动自由度、局部坐标输出、`Iy/Iz/J`、其他 L2 算例 |
| 验收判据 | 见 §4，初始全部 `passes: false` |

## 1. 候选算例：先证伪，再选择

用户点名的两个算例**都不可用**，这是量出来的，不是推断：

| deck | 快照 5414e73 | 本仓库构建 | 结论 |
|---|---|---|---|
| `test_beam2d` | **rc=174 SIGSEGV** | rc=2，`ifixvar=4 out of range 1..2` | **算例缺陷**：`MDOFN=2`、L2 组只声明 2 个自由度（`1 2`），`.pre` 却约束 `ifixvar=4`（转动）。守卫的界是 `1..mdofn`（Prescrib.f90:159），不是写死的 2，所以守卫是对的，deck 是错的 |
| `pile_beam` | **rc=64 input conversion error** | rc=2 PARSE，指名到字段 | `.glb` 是更老的方言，**快照 legacy 自己也读不了**。无可运行参考 |

语料普查（1308 个 `.glb`）后，2-D 且带线单元组的真实算例是：

| deck | 规模 | 组 | 快照 | 本仓库（PD-2 修复后） |
|---|---|---|---|---|
| `rcbeam` | 793 节点 / 721 单元 | Q4×600 + L2(1)×60 + L2(25)×61 | rc=0, 5.7 MB | rc=0，**与快照逐字节相同** |
| `rcbeam_crack` | 同上 | 同上 | rc=0, 5.7 MB | rc=0，**逐字节相同** |
| `tunnel` | 680 / 600 | 7 组，含一个 `elcod_local` 接缝组 | rc=0, 2.5 MB | rc=0，**逐字节相同** |
| `tunnel_sl` | 3614 / 3402 | 21 组 | rc=0, 43.7 MB | rc=0，1 586/1 626 300 个值不同，`max|d|=1e-8` —— 构建独立性债务 |
| `rc_lining` | 268 / 292 | 6 组 | rc=59（向 stdin 要输入） | deck 不完整 |

**选 `rcbeam`**：最小的、与快照逐字节相同的、真实的 2-D L2 算例。

## 2. 三个线单元族不是一回事

| elkn 索引 | 名字 | CLASS | 自由度 | 刚度路径 |
|---|---|---|---|---|
| 1 | `l2` | `CO` | 2（`1 2`，与 Q4 相同） | **与 Q4 同一条**普通高斯积分路径（Stiff.f90:121 的 `index/=20/21/25`） |
| 20 | `b2` | `BM` | 3（`1 2 4`，含转动） | 独立分支，读 `Iy/Iz/J`（Stiff.f90:206-213） |
| 25 | `steel` | `CO` | 2 | 第三条分支，粘结/弹簧列式（Stiff.f90:572+） |

**索引 1 在刚度层面与 Q4 的唯一差别**是 `thick` 的来源：
`if (nnode==2.and.index/=25) thick = props(matno)%geometry%aera`（Stiff.f90:118）——
杆件的「厚度」就是截面面积。`Iy/Iz/J` 只在**梁**分支里读，转动自由度同理，
所以本轮两者都不需要，也不为将来预留。

## 3. 能力差值（机械测得）

适配器跑未修改的 `rcbeam`，第一条拒绝就是本域的核心：

```
UNSUPPORTED sections[][2].element_kind: only the capability table's element.kind_code (Q4)
is whitelisted; this parser only knows how to shape a Q4 connectivity record
```

逐项：

| 差值 | 归属 | 现有词汇够不够 |
|---|---|---|
| `section.element_kind` 需容纳 1 与 25 | G1 能力行 | **够**：`section_t` 已有 `element` / `element_kind` / `class` |
| `.ele` 每组 `nnode` 不同（4 / 2 / 2） | 适配器 mesh 解析器 | **不够**：`deck_context_t%nnode` 是**一个标量**，写死了「全网格一种单元」。legacy 本来就是在组循环里按该组 `nnode` 读 `.ele`，`ctx%group_kind(:)` 也已经是逐组的——只有这个标量把它压平了。`element_t%nodes` 本身是 allocatable，混合拓扑**已经可表达** |
| 截面面积 `aera` | `.mat` 的 `GEOMETRY ROD_or_BEAM` 记录 | **够**：与 `thickness` 完全同构——legacy 存在**材料**上，ADR-0003 归到**截面**，桥接层已经在做 material→section 的解析。按同一条路走，不引入新概念 |
| 索引 25 的 `prot` / `icpspring` / `element%rotation` / `element%area` | Material.f90:1091+ 由网格**派生** | **不是输入**：从索引 1 和 20 的单元与 `coord`、`aera` 推出来，不新增任何 deck 字段 |

**一个被语料否决的偏好**：本想只做索引 1 这一个族，但全语料没有任何 2-D deck 只用索引 1
而不用索引 25——两者总是成对出现（钢筋混凝土算例的配筋 + 粘结）。既然不自造算例，
本轮的族集合就由真实 deck 决定：Q4 + L2(1) + L2(25)。输入侧的差值仍然只有上表那几行。

## 4. 验收判据（初始全部未通过）

1. `rcbeam` 冻结参考：3 次运行 `1.flavia.res` 逐字节相同 — **`passes: true`**（120 块 / 214 110 值）
2. 现代输入独立驱动 `rcbeam`（工作目录只有 `case.toml` + `.cor`/`.ele`），与冻结参考
   `atol = rtol = 0` — `passes: false`，**被 CONCRETE + PARDISO 阻塞**，见 §5
3. 既有七个 golden 算例逐位不变 — **`passes: true`**（保留下来的机制类改动惰性由此证明）
4. 混合拓扑由**每组** `nnode` 驱动，且有反例：组声明的单元族与 `.ele` 记录长度不符时按名拒绝 — `passes: false`
5. 截面面积走 `[[section]]`，且两个方向都有反例（非线单元写 `area`／线单元不写 `area`） — `passes: false`
6. 不新增 `Iy`/`Iz`/`J`/转动自由度/局部坐标的任何 schema 字段 — `passes: false`

## 5. 收口状态：**suspended**（2026-09-17）

判据 2 走不通，原因是量出来的，不是估计：**四个候选 deck 全部同时需要
`CONCRETE` 与 `PARDISO`**。

| deck | TYPE_SOLVER | Q4 组材料 |
|---|---|---|
| `rcbeam` | **PARDISO** | **CONCRETE**（icr=3） |
| `rcbeam_crack` | PARDISO | CONCRETE |
| `tunnel` | PARDISO | CONCRETE |
| `tunnel_sl` | PARDISO | CONCRETE |

（`.mat` 里出现的 `CAMCLAY` 是第 12/15 行的**注释**，不是材料记录——这次先查了。）

`CONCRETE` 已于 2026-09-17 由负责人裁定暂缓，`PARDISO` 属未开始的求解器变体域，
而且正是该裁定引述的 CONCRETE 前置条件本身。因此本域停在判据 2，
状态 **suspended，前置条件 = CONCRETE + PARDISO**。

rcbeam 的 gdb 取证还显示它触及**四个**未迁移域，远不止一个单元族：

| 未注册站点 | 属于 |
|---|---|
| `Solver.f90:7772-7794` | PARDISO 求解器输入 |
| `Material.f90:250/256/257`、`:666` | 材料属性曲线 与 CONCRETE 记录 |
| `Global.f90:1499-1529` | `.nrt` 插值组（几何域 M6.2） |
| `Global.f90:1042/1043`、`Output.f90:1303` | `bcs` 输出文件 |

这条证据本身说明 rcbeam **不是任何东西的最小切片**，佐证了暂停的判断。
它的取证保存在 `suspended/evidence/rcbeam/`，**不进** `docs/m1/evidence/` 的门禁通配，
因为那 16 个站点未注册会让 reader inventory 红掉，而注册它们就是开启上述四个域。

### 保留了什么

机制类改动保留，且都由七个既有 golden 逐位不变证明惰性：

- `deck_context_t` 的 `nnode` 标量 → `group_nnode(:)`，经 `nodes_of_kind` 派生；
  现代路径 `fill_context` 同样改为逐 section 走 `.ele`。这是适配器最后一处
  「一个网格一种单元」的假设，**legacy 从来没有这个假设**。
- `nodes_of_kind` 认识 kind 1 / 25 的节点数——那是 legacy 的编译期事实，不是能力声明。
- `element_kind_of` / `nodes_per_element` 认识 `L2` / `STEEL` 的名字，同理。
- 能力行 `element.kind_code` 改为**集合语义**（`gate_int_set` + `text_in_set`），
  但**取值仍只有 `5`**。

### 撤回了什么，以及为什么

能力**声明**类改动全部撤回，因为没有任何被接纳的算例能证明它们：

- `sections[].cross_section_area`（类型 / map 行 / `.mat` GEOMETRY 分支 / commit / authoring 键与规则）
- `MAT.material_set.geometry_section` reader 行
- `section[].element` 白名单里的 `L2` / `STEEL`
- `output.field` 里的 `bcs`
- map 单位表里的 `m2`

撤回的直接原因是一条门禁规则，而它是对的：
`yl_state_map.py` 要求**任何 map 字段的来源 reader 必须被某个被接纳的算例执行**
（`reader ... has empty executed_by`）。这正是「没有真实 deck 就不能声称一个字段」的机制表达。
与其绕开它，不如承认这一层现在没有证据。

完整改动保存在 [`suspended/section-area-and-element-whitelist.patch`](suspended/section-area-and-element-whitelist.patch)，
恢复时按上表逐条放回即可；白名单加一个取值是一行改动。

## 5b. 前置

`PD-2`（`mmats` 守卫）已于 2026-09-17 修复，四个算例因此恢复可运行。
见 [`../m8/pre-migration-defects.md`](../m8/pre-migration-defects.md)。它**不计入**本域能力。
