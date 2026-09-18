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
2. 现代输入独立驱动 `rcbeam`（工作目录只有 `case.toml` + `.cor`/`.ele`/`.nrt`），与冻结参考
   `atol = rtol = 0` — **`passes: true`**：120 块 / 214 110 值 / mismatches = 0 /
   `max|d| = 0.000e+00`。收口前的最后一处分歧见 §5
3. 既有八个 golden 算例逐位不变 — **`passes: true`**（每一轮 `max|d| = 0.000e+00`，
   本域所有机制类改动的惰性由此证明）
4. 混合拓扑由**每组** `nnode` 驱动 — **`passes: true`**：适配器、`build_runtime`、
   commit 三层都已改为逐单元，`rcbeam` 的 4 / 2 / 2 在一个网格里跑通
5. 截面面积走 `[[section]]`，且两个方向都有反例（非线单元写 `area`／线单元不写 `area`） — **`passes: true`**
6. 不新增 `Iy`/`Iz`/`J`/转动自由度/局部坐标的任何 schema 字段 — **`passes: true`**
   （`read_geometry` 读到非零 `J`/`Iy`/`Iz` 直接拒绝，而不是丢弃）

## 5. 收口状态：**closed**，六条判据全部成立（2026-09-18）

2026-09-17 的 suspended 已解除：`CONCRETE`（M11）与 `PARDISO`（M10）两个前置都已迁移。

`rcbeam` 现在由现代输入独立驱动（工作目录只有 `case.toml` + `1.cor`/`1.ele`/`1.nrt`），
与冻结参考 **`atol = rtol = 0` 下 120 块 / 214 110 值 / mismatches = 0 / max|d| = 0.000e+00**。
`Yield` 有 **5371 个落在 (0,1] 的真实损伤值、区间外 0 个**——
这同时补上了 M11 欠下的判据 5：同一条断言在 `damage_2d.concrete_gravdam` 上是
**0 个在区间内、169 个在区间外**（最大 3.17e10，恰是该材料的 `E`，即 PD-3）。
预测在运行前写下（291 / 0 / 169），实测完全一致。

### 收口前最后一处分歧，以及它揭穿的一个错误推断

判据 2 一度不成立，形态是：`--adapter=off` 对冻结参考逐位一致，
而**适配器路径与现代路径彼此一致、双双偏离** 133 477 个值。
两条现代侧路径互相吻合，说明 deck 是忠实的，问题在链上。

不需要状态快照就定位到了——`1.chk` 的方程数把它写在脸上，两个减法逐项对上：

```
ntotv = 1586 = 793 节点 x 2 自由度        （两条路径相同）
  legacy 读取器   Neq = 1459 = 1586 - 122 - 5
  适配器/现代     Neq = 1581 = 1586 -   0 - 5
  122 = 61 个被插值节点 x 2 自由度   <- .nrt 表
    5 = 给定位移自由度               <- 两条路径相同
```

`.nrt` 的插值约束**根本没有被施加**。原因是我自己在本轮早些时候下的一个判断：
把 `.nrt` 登记为「随网格原样带走、legacy 在两条路径上都读」的直通文件，
理由是 Global.f90:1489-1531 那一段没有 `yl_input_enabled` 守卫。
守卫确实没有——但整个 `global_data` 在适配器路径上就不执行，
所以「**没有守卫**」根本不蕴含「**会被读到**」。
这是从代码形状推断执行，而本项目的纪律恰恰是以执行为证据。

修法不是绕过，是按迁移的正常路径走完：
`parse_nrt`（`src/adapter/yl_adapter_mesh.f90`）复现全部七条读取，
表进 `ProblemState.mesh.interpolation[]`，
`build_runtime` 经 `nodfn`/`lmdofn` 把一条节点记录展开成 mdofn 条变量记录，
commit 发布 `trans%nintf/listf/rintf`。
`docs/m1/adapter-coverage.toml` 的 `.nrt` 段因此**整段清空**——
按那份文件自己的规矩，行是靠「把 parser 写出来」删掉的。

`mesh.format` 当天加过的第二个取值 `"hstar-legacy-cor-ele-nrt"` 也随之撤回：
它存在的前提就是那个被证伪的判断；`parse_nrt` 写出来之后它已无物可分。

## 6. 本轮打开了什么（每一条都有真实 deck 支撑）

单元族本身只是切片的一部分。`rcbeam` 实际需要的是**六个域**，逐条登记：

| 能力 | legacy | 现代表达 | 证据 |
|---|---|---|---|
| L2（kind 1）/ STEEL（kind 25） | `group%index` | `section.element ∈ {Q4,L2,STEEL}` | 三族同在一个 `.ele` |
| 截面面积 | `props%geometry%aera` | `section.area`（仅 L2） | `GEOMETRY ROD_or_BEAM` 记录 |
| CONCRETE `icr=3` | `Concrete%icr` | `crack_model ∈ {3,6}` | 两个值各一个真实算例 |
| 材料应力-应变曲线 | `scurves` | **不表达**：读了就丢 | 本路径无任何消费者，逐一查过 |
| `.nrt` 节点插值表 | `trans` | `mesh.interpolation[]` + `parse_nrt` | 61 节点 x 4 权重；缺了就少 122 个约束 |
| 粘结律 | `ikindks/coefMpa/doubsig/ktan1` | `[bond]` 四个键 | 缺了就是 Material.f90:1330 的裸 `stop` |

顺带做实了三个**一直存在、一直没被证伪**的假设：

- `deck_context_t%nnode`、`build_shape_t%nnode`/`nevab`、commit 的 `nnode`/`nevab`
  全部由标量改为**逐单元**。legacy 从来没有「一个网格一种单元」的假设
  （它在组循环里按各组 `nnode` 读 `.ele`，Elements.f90:1081-1087），是迁移侧三层各自复制了一份。
- `step[].load[].apply_to` 自 M5 起就是一个「校验了但没人消费」的键：校验器会拒绝悬空的名字，
  然后扇出仍旧把曲线发给每一个 section。`rcbeam` 的 `tcurvegravity = [1,0,0]` 是第一个需要它的 deck。
- `output.stress_averaging` 在 legacy 里是**逐组**的（`average_appear`），
  此前每个 deck 都逐组同值，所以差别不可见；`rcbeam` 是 `[1,0,0]`。

以及两条纯属遗漏的存在性：`pstrain` 与 `ipp4`（Global.f90:712-714 同一段语句）。
Q4-only 路径上没有任何东西读它们，所以「没分配」一直是不可见的——
直到 `rcbeam` 走进 `strain_for_steel_`（Fem.f90:17793）并在那里 SIGSEGV。

## 7. N4 的加强：只数非零是不够的

`must_be_nonzero` 现在可以带 `in_range = [lo, hi]`。理由是 M11 的教训：
`damage_2d.concrete_gravdam` 的 `Yield` 有 169 个非零值，断言**通过了**——
而那些值全部大于 1e9，是 PD-3 把一个未初始化局部量写进了输出槽。
`damage` 只能取 `0` 或 `1-sqrt(cc)`，不可能大于 1。
一个只数非零的断言无法区分这两件事；一条声明的取值区间可以。

## 8. 前置

`PD-2`（`mmats` 守卫）已于 2026-09-17 修复，四个算例因此恢复可运行。
见 [`../m8/pre-migration-defects.md`](../m8/pre-migration-defects.md)。它**不计入**本域能力。
