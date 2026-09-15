# M6 材料域：语义面、白名单边界，与下一个能力

- 日期：2026-09-13
- 前置：M5 窄口径签收（`docs/m5/M5-report.md`）、R29 关闭
- 方法：沿用静力切片已验证的链条 —— **旧字段 → 语义 → 内部数据结构 → 新 schema → 回归证据**
- 纪律：**不新增治理层**。以**真实能力**为推进单位，不以「读取点研究完毕」为进度。

## 0. 这一章不做什么

不把 `.mat` 全部逆向工程一遍。下面的 §2 是**分类**，不是逐字段研究：
它只需要精确到「哪些能力在白名单内、哪些是 legacy-only、边界画在哪条分支上」，
因为这正是决定下一个能力怎么切的信息。未进入白名单的模型**不提前设计 schema**。

## 1. 基线：`ELASTIC_ISOTROPIC` 在材料域中的完整语义

### 1.1 `.mat` 上的读取站点（12 条，M1 普查）

| seq | id | 位置 | 语义 |
|---|---|---|---|
| 1 | `MAT.material_set.title#1` | `Material.f90:243` | 标题行，丢弃 |
| 2 | `MAT.material_set.curve_count` | `:245` | 材料属性曲线条数 `nscurve`，两例均 0 |
| 3 | `MAT.material_set.comment_line_count` | `:261` | 注释行数 `nline` |
| 4 | `MAT.material_set.comment_line#1` | `:264` | 注释行 ×`nline` |
| 5 | `MAT.material_set.title#2` | `:270` | 标题行，丢弃 |
| 6 | `MAT.material_set.nmats` | `:272` | 材料数 `mmats` |
| 7 | `MAT.material_set.title#3` | `:281` | 标题行，丢弃 |
| 8 | `MAT.material_set.material_header` | `:283` | `property, name, imat` |
| 9 | `MAT.material_set.material_nphase` | `:298` | 相数 `nphase` |
| 10 | `MAT.material_set.material_phase` | `:302` | 相名 ×`nphase` |
| 11 | `MAT.material_set.elastic_isotropic` | `:310` | **公共 SOLID 记录**（见下） |
| 12 | `MAT.material_set.elastic_extra` | `:313` | `iE, iNu, density_w` |

### 1.2 一处必须纠正的命名

**seq 11 的 id 叫 `elastic_isotropic`，但它不是某个本构模型的记录，而是每个 SOLID 相
都要读的公共记录**（`Material.f90:310`，在 `case('SOLID')` 之内、`material_select` 之前）：

```
material, density, ratio, thickness, e, nu, alfa, icreep, kind_wt, jliqu
```

`material` 只是这条记录的**第一个字段**，本构模型的**专属**参数在其后的
`material_select`（`Material.f90:457`）里按模型各读各的。这个命名差异不影响静力切片
（`ELASTIC_ISOTROPIC` 的分支恰好什么都不读），但材料域第一件事就会撞上它：
**任何「新增一个材料模型」的工作量估算，如果以为 seq 11 是模型专属记录，就会低估。**

`E`/`nu`/`density` 是物理选择且是作者写的；`ratio`/`alfa`/`icreep`/`kind_wt`/`jliqu`
在当前白名单下是常量（契约 §5），`thickness` 的 ProblemState 归属是 `sections[].thickness`
而不是 `materials[]`——`.mat` 是它**唯一**的读取点。

### 1.3 内部映射（既有，未改动）

`materials[].{id,name,kind,phase,model,E,nu,density,thermal_expansion,solid_ratio,
creep_model,liquefaction,wetting_kind}` + `sections[].thickness`。
`materials[].name` 是 `.mat` 表头词即**相名**（`SOLID`），不是本构模型名，
也不是作者的引用标签——这条在 M5 被订正过（`docs/m5/M5-report.md` §3）。

## 2. `.mat` 能力分类：白名单 vs legacy-only

三层 `select`，边界画在第三层上。

### 2.1 第一层 `property_select`（`Material.f90:294`）

| 取值 | 有分支 | 处置 |
|---|---|---|
| `MECHANICAL` | 有 | **白名单** |
| `HEAT` | 有（`:993`） | legacy-only（热学域，M8.1） |
| 其他 | 无 | legacy 自己 `diag_unsupported`，allowed 串写作 `MECHANICAL \| HEAT \| GEOMETRY` |

### 2.2 第二层 `phase_select`（`Material.f90:305`）

| 取值 | 处置 |
|---|---|
| `SOLID` | **白名单** |
| `FLUID` | legacy-only（`:944`，渗流/流固耦合，M8.3 / M7.6） |

### 2.3 第三层 `material_select`（`Material.f90:457`）：15 个本构模型

| 模型 | 行 | 专属记录 | 处置 |
|---|---|---|---|
| `ELASTIC_ISOTROPIC` | 465 | **无** | **白名单**（静力基线） |
| `ELASTIC_FRICTIONLESS` | 466 | **无** | 候选：零成本，但无真实算例，**不做** |
| `CLASSICALEP` | 618 | 2–4 条，依 `criteria` | **本次新增能力**（见 §3） |
| `PLANE_LOWFT` | 458 | 1 | legacy-only |
| `ELASTIC_SPRING` | 467 | 1 | legacy-only |
| `ELASTIC_EP` | 475 | ≥1 | legacy-only |
| `STEEL_EP` / `STEEL_SP` | 485 / 495 | ≥1 | legacy-only（配筋域 M6.8） |
| `DUNCANCHANG` | 501 | 多条 | legacy-only（下一批候选） |
| `GOODMAN` | 544 | 多条 | legacy-only（接触/节理面） |
| `CAMCLAY` | 655 | 1 | legacy-only |
| `CONCRETE` | 664 | 多条 | legacy-only（损伤域） |
| `ClayPZ` / `SandPZ` / `SoilPZ` | 738 / 766 / 858 | 多条 | legacy-only |

### 2.4 与本构模型**正交**的四个子能力族

它们挂在公共 SOLID 记录的开关上，**任何**模型都可能带上，所以它们是独立的能力单位，
不属于任何一个模型：

| 开关 | 触发 | 追加记录 | 处置 |
|---|---|---|---|
| `icreep` 1..4 | 徐变 | 1–2 条，依取值 | legacy-only（`train_temp_creep`） |
| `kind_wt > 0` | 湿化变形 | 1 | legacy-only |
| `jliqu /= 0` | 抗液化循环参数 | 2+`nalfa` 条 | legacy-only |
| `name == 'CONTACT'` / `igap0 == 2` | 接触缝 | 1–2 条 | legacy-only（接触域） |

当前契约把这四个开关都钉成 0，**并且适配器逐条拒绝非零值**——即 legacy-only 不是
「没想到」，而是「写下来并且会拒绝」。

## 3. 下一个能力：`CLASSICALEP` + `MC` 准则

### 3.1 为什么是它

它是这个求解器的主场（土石坝、边坡）里最常用的弹塑性模型，且**结构上最能检验方法是否可复制**：
它同时带来「模型专属记录」「准则再分支」两层新形状，而不引入新的单元、新的过程或新的求解器。

### 3.2 记录形状（`Material.f90:618-654`）

```
criteria, sigma0, hardening                     ! 总是
frict_angle, dilan_angle                        ! criteria(1:2) 为 'MC' 或 'DP'
csigma0                                         ! 总是
cfrict, cdilan                                  ! criteria(1:2) 为 'MC' 或 'DP'
ft, cft, sigmat, csigmat                        ! criteria 为 'MCC'/'DPC'/'MCJOINT'
```

准则取值（来自 `Stiff.f90` 的分派）：`TC` `VM` `MC` `MCC` `DP` `DPC` `MCJOINT`。
**本次只把 `MC` 放进白名单**，其余准则由能力门逐条拒绝——它们的记录形状不同，
且没有真实算例支撑。

### 3.3 真实 deck 与能力差值（实测）

deck = `cases/golden/plasticity/mini_mc`（即 `cases/manifest.toml` 早已规划的 M6.4 算例），
30 节点 / 20 个 Q4 / 2 材料 / 2 单元组，重力单增量。

差值是**测**出来的，不是读代码估的。但**第一次测量不完整，这里如实记下来**：

- 第一次把 deck 交给适配器，只报两条拒绝——`nonlinear_type=4` 与 `materials[2].model`。
  当时据此写下「`nmats=2`、`ngroup=2` 一律已经支持」。
- **这个结论是错的。** 流水线**阶段间失败即止**：`.glb` 的 `type_nl` 拒绝发生在
  `.mat` 之前，`.mat` 的拒绝又发生在 M3-02 能力表之前。把前面的逐条放开之后，
  能力表又报出**第三、第四条**：`materials[].model` 的能力行（与适配器方言表是两张不同的表）
  和 **`sections.size` 必须为 1**。

所以真实差值是**四条**，不是两条：

1. `steps[0].controls.nonlinear_type`：deck 为 4（full Newton），白名单只有 5；
2. 适配器方言表 `A-MAT/model`：`CLASSICALEP` 不在白名单内；
3. 能力表 `G3 material.model`：同一件事的另一张表；
4. 能力表 `sections.size`：只允许 1 个单元组，deck 有 2 个。

**教训与 M5 的「反例失效」同形**：一个 fail-fast 管线上的「只报了两条」不等于「只有两条」。
要得到真实差值，必须逐条放开再测，直到通过为止；只测一次就下结论，会**系统性低估**。

第 4 条**不是**放开一个数字就行：`sections.size` 那一行旁边写着一段警告——finalize 会为每个
section 派生一个单元集，两个 section 若元素全属第一个，第二个就会成为「显式的空集合」，
ADR-0002 禁止；而且**没有校验规则守它**（因为这行读 1 时该情况不可达）。
所以抬高它**必须先补那条校验规则并配反例**，否则用户写的第一个双 section 模型
会收到一个 internal fault。

### 3.4 这个 deck 的**限定**，实测，不是推断

`mini_mc` 的 `1.flavia.res` 有三个块：`DISPLACEMENT`、`STRESS`、**`PLASTICSTRAIN`**。
第三块是弹性材料不会写出的块，正是塑性能力本身的观察量。

**实测：`PLASTICSTRAIN` 全部为 0（30 个值，非零 0 个）。这个 deck 不屈服。**

所以本次能力达成后可以说的是：**`.mat` 的读取、映射、按模型分派、多材料多单元组
这条链路成立，并在真实 deck 上与冻结参考严格相等**；
**不能**说的是：塑性回映（return mapping）被验证过——它根本没有被触发。
这条限定必须写进完成判据，否则「数值等价」在塑性完全没发生的情况下也成立，
和 M5 那次「反例失效却看起来通过」是同一种错误。

**会屈服的 deck 已经找到并命名**：`train05b_slope_srm`（CLASSICALEP + MC + PROFILE，
451 节点 / 400 单元，塑性应变非零值 11803 个）。它的额外能力差值是
`TYPE_LOAD=MAT_DE`（强度折减）与 `MAT_curve=2`（材料曲线），
**属于下一个能力，不并入本次**。

## 4. 完成判据

沿用 M5 的形态，不新增验收层：

1. `plasticity.mini_mc` 能由新格式**完整表达**；
2. 校验器对新增白名单行**各有一个反例**，且**只有该行触发**；
3. 该算例**仅凭 `case.toml` + 网格**驱动求解，工作目录内无 legacy 控制卡；
4. 与**冻结 legacy 参考严格相等**（`atol = rtol = 0`），**三个块都比**，
   `PLASTICSTRAIN` 含在内；
5. 两个静力算例**不受影响**（既有门禁全绿）。

**不以「`.mat` 读取点研究完毕」作为进度指标。**

## 5. 结果（2026-09-14）

五条判据全部达成：

| 判据 | 实测 |
|---|---|
| 1 新格式完整表达 | `cases/golden/plasticity/mini_mc/modern/case.toml` |
| 2 新白名单行各有反例 | authoring 套件 41 + 11（塑性 deck 专用一组）；方言套件 372/372 ×2；流水线 490/490（含 V26） |
| 3 仅凭 `case.toml` + 网格驱动 | 门禁 **N1**，工作目录内无任何 legacy 控制卡 |
| 4 与冻结参考严格相等 | 门禁 **N2**：`DISPLACEMENT` / `STRESS` / **`PLASTICSTRAIN`** 三块均 `max|d| = 0.000e+00` |
| 5 两个静力算例不受影响 | 同一次 N1/N2 通过，fallback 门禁亦全绿 |

**结论边界，照旧不放宽**：`PLASTICSTRAIN` 三十个值仍全为 0——**这个 deck 不屈服**。
本次确立的是 **CLASSICALEP/MC 的输入、映射、按模型分派与求解链路成立**，
**不是**塑性回映已被验证。下一能力用 `train05b_slope_srm`（真正屈服）来验证那一半。

### 5.0 签收（负责人 Huijun，2026-09-14，窄口径）

**本次确立**：

- CLASSICALEP/MC 已进入统一 authoring schema；
- 条件必填、映射、按模型分派和求解链路成立；
- `mini_mc` 可仅由现代输入驱动；
- DISPLACEMENT / STRESS / PLASTICSTRAIN 与冻结 legacy 参考严格一致。

**明确不确立**：

- 塑性回映已经得到验证；
- 非零塑性应变路径已经覆盖；
- 其他材料模型因此自动获得支持。

与 M5 同一口径：门禁由实现方编写并运行，**不表述为独立第三方验证**（R28 的同一结构性缺口）。

### 5.1 这一能力实际改动的边界

- 白名单新增：`material.model` 增 `CLASSICALEP`；`criterion` 只收 `MC`；
  `stiffness_update` 两个取值（legacy `type_nl` 5/4）；`output.field` 增 `ep`。
- 白名单**移除**：`model.section_count`（原钉死 1）。移除的前提是新增校验 **V26**
  「每个 section 至少拥有一个单元」——那行旁边写着的正是这个前提。
- 契约首次出现**按模型条件必填**：`model_requires` 两个方向都查。
- `elset[].mesh_group` 改为 `elset[].element_count`：前者是**死键**（声明了、从没被读过），
  而单元归属在 legacy 里本来就是**按文件顺序、每组取 nelgroup 个**；
  `.ele` 是否带组号列因算例而异（`lame_cylinder` 带、`mini_mc` 不带），legacy 两种都忽略。

## 6. 下一个能力：`train05b_slope_srm`（强度折减，真正屈服）

deck：451 节点 / 400 个 Q4 / 1 材料 1 组，`CLASSICALEP` + `MC`，`PROFILE`，
`TYPE_LOAD = MAT_DE`（强度折减），100 个 step × 最多 40 次迭代。
legacy 跑出 **600 个结果块**（6 种 × 100 step）、**541 200 个数值、非有限值 0 个**。
`PLASTICSTRAIN` 非零值 11 803 个——**这才是塑性真正发生的算例**。

### 6.1 能力差值：逐轮放开测出来的，不是读代码估的

fail-fast 管线一次只报一层，所以按 M6.4 学到的做法**逐轮放开、重测**，直到通过：

| 轮 | 报出 | 性质 |
|---|---|---|
| 1 | `control.glb.mat_curve = 2` | **真能力**：材料属性曲线 |
| 2 | `sections[1].element = "B8"`；`steps[1].load.gravity.enabled = 999` | 见 §6.2、§6.3 |
| 3 | `build_runtime B6` 重复 (node, dof) | **已修**，见 §6.4 |
| 4 | *（无）* rc=0 | — |

**第 4 轮是关键**：`TYPE_LOAD = MAT_DE`、`nstep = 100`、`miter = 40`、`ditime = 0.01`、
以及 `.glb` 里那一排 `999` 计数，**全部早已被接受**，不需要任何改动。
把放开后的 probe deck 交给两条路径对拍，**600 个块的每一个有限值 `max|d| = 0.000e+00`**
（probe 改过物理，两条路径同样发散，非有限值两边一致出现——这只说明适配器忠实，
不说明 probe 的结果有意义）。

所以真实差值只有**三项**，其中两项不是「新能力」而是**旧判据错了**。

### 6.2 `sections[].element` 的白名单管错了字段

deck 的组头第一个词是 `B8`，而 `INDEX = 5`（= Q4），`.ele` 每单元 4 个节点——
**这是个标签写错的 deck**，legacy 毫不在意：`group%name` 在 `Global.f90:1272` 赋给一个局部量，
**七行之后就被 `group%sptype` 覆盖**（两处都被 legacy 作者自己标了 `!why`），
真正的分派靠 `index`。能力表里已经有 `element.kind_code`（`index == 5`）这条**正确**的判据；
`element.name` 这条约束的是一个**被覆盖前从未使用的标签**。

### 6.3 `NGRAV` 是频率，不是开关

映射表把 `global_var.NGRAV` 记作 `steps0.load.gravity.enabled`，note 写「1 on both cases」。
`Fem.f90:15582` 里 NGRAV 决定的是**每隔几个 step 重算一次重力**：
`NGRAV == 0` 或首个 step 的首次迭代 → `KGRAV = 1`，否则每 NGRAV 个 step 一次。
**静力切片分不出频率和开关，因为它只有一个 step。** 这与 §1.2 的 `elastic_isotropic`
命名、M5 的 `materials[].name` 是同一类：**单点观测下两种语义恰好同值。**

### 6.4 B6 已按实测收窄（本轮唯一已落地的改动）

`build_runtime` 原先拒绝任何重复的 (node, component)。理由写的是「legacy 会用后一条的
mask 覆盖前一条并把两条都留在 `prescrib` 里，作者在输出里看不见」——**这在两条记录取值
不同时成立**。取值相同时没有任何东西被藏起来，而真实 deck 正是在**两条受约束边相交的角点**
上这么写的（本 deck 在两个重叠节点集上都写 `ux = 0`）。已收窄为「重复且**取值不同**才拒绝」，
并补上**另一半断言**——「完全相同的重复必须被接受」：一条只会 fire 的规则，
不能说明它 admit 什么；没有这条，收窄与删除无法区分。
原反例恰好是「完全相同的重复」，收窄后它**变绿却什么都不再断言**，已改为取值不同。

### 6.5 `mat_curve` 能力已接入，但**等价性尚未达成**

`mat_curve` 不是开关，是**索引**：`type_load == 'MAT_DE'` 时，
`Stiff.f90:5779` 取 `tcurves(mat_curve)%dfact` 去缩放 `sigma0` 与 `tand(frict)/tand(dilan)`——
**那条曲线就是强度折减的进度表**。本 deck 的 `.loa` 有两条曲线：
第 1 条 (0,1)→(1,1) 驱动重力，第 2 条 (0,1)→(1,**0.5**) 就是折减曲线。

已落地：`ProblemState.steps[0].load.strength_reduction`（off-face 映射行）、
适配器承载、commit 写回 `mat_curve`、**V27**（非零值必须指向已声明的 amplitude——
legacy 用它直接索引 `tcurves(:)` 且**从不检查**）。原「pinned guard」方言行已删除:
它拒绝一切非零值，而真正需要的是**范围检查**。

**适配器现在接受这个 deck 并跑完(rc=0)，但与 legacy 路径不等价**，如实记录：

```
FAIL  blocks=600 values=541200 mismatches=104135 max|d|=6.544e+07
  first mismatch: DISPLACEMENT step=0.75 node=4 comp=1
                  reference=-0.22071836 actual=-0.22071835
```

**前 74 个 step 逐位相同**，从第 75 步开始出现最后一位有效数字的差异并迅速放大
（这是个跑到破坏的算例，塑性路径对扰动极敏感）。

### 6.6 已经**排除**的原因（每条都是测出来的）

| 假设 | 测法 | 结论 |
|---|---|---|
| 非确定性（线程等） | 两条路径各跑两遍 | **排除**：各自逐字节相同 |
| model_ready 状态不同 | `yl_state_diff`，3 个检查点 | **排除**：`mismatch=0 compared=160`，唯一差异是 section 键（deck 把组名写成 `'  1'`，适配器给 `1`）——标签 |
| 幅值曲线搬运有误 | 直接看两边 dump 的 `amplitudes.*` | **排除**：含第 2 条折减曲线在内逐位相同 |
| 读到未初始化的局部存储 | 新增 `initzero` profile（`-init=zero,arrays`）两条路径同跑 | **排除**：差异仍在（且提前到 step 0.48） |

**顺带测到一件必须记下的事**：`strict`（`-init=snan -fpe0`）**在这个 deck 上不能用作差分工具**——
**legacy 路径自己**就在 `fwds_euler`（`Residu.f90:2879`）触发 floating divide by zero。
塑性积分器在正常运行中就依赖 IEEE 非停止算术，release build 把结果吸收掉了。
这也是新增 `initzero` profile 的原因：不陷入陷阱、但让未初始化局部变量确定化。

**尚未排除**：commit 未复现的、不在观测面上的某个值，且只在塑性充分发展后才被读到。
下一步的工具是**更晚的检查点**或对已提交状态做二分，而不是继续猜。

**结论边界**：本能力**未达成**。`mat_curve` 链路成立且被 V27 守住，
但 `train05b_slope_srm` 的严格等价**没有**达成，非零 `PLASTICSTRAIN` 的判据也**不能**据此宣称。

## 7. 第一处分叉:定位结论(2026-09-14)

本轮唯一目标是**定位第一个产生差异的量及其来源**。已定位。

### 7.1 分叉点

**`element(i)%egaus(1)%cartd`** —— 高斯点上的**笛卡尔形函数导数**,首次出现差异的单元是 **101**。
数值差 **1–2 ULP**:

```
legacy   CARTD 101 1 1 = BFC0068A44F7521C  -1.25199588465549350E-01
adapter  CARTD 101 1 1 = BFC0068A44F7521A  -1.25199588465549294E-01
```

不是错位、不是缺字段、不是量纲——**是同一个数的最后一两位**。
`tload` 的差异(97/400 个单元)是它的下游后果,位移与高斯点状态再往下。

**关键澄清**:打印输出前 74 步逐位相同,曾让人以为分叉发生在第 75 步。
**不是**——用位级探针逐步比对后,**第 1 步就已经不同**;
8 位有效数字的输出把它藏了 74 步。任何以打印结果为准的二分都会从错误的地方开始。

### 7.2 逐条排除(全部为实测)

| 量 | 结果 |
|---|---|
| 两条路径各自可复现 | **是**,各跑两遍逐字节相同 |
| 观测面 190 字段 × 3 检查点 | **完全相同**(`mismatch=0`) |
| `coord`(节点坐标) | **逐位相同** |
| `posgp`(高斯点母坐标,904 个值) | **逐位相同** |
| `deriv`(母单元形函数导数,8623 个值) | **逐位相同** |
| `elcod_f`(单元坐标) | **逐位相同**(400/400) |
| `djacb`(雅可比行列式) | **逐位相同**(400/400) |
| 材料参数(E/ν/ρ/厚度/σ₀/φ/ψ/硬化) | **逐位相同** |
| `dfact`(强度折减因子) | **逐位相同** |
| 未初始化局部存储 | **排除**:`initzero` profile 下差异依旧 |
| FMA 收缩 | **排除**:`-fma-` 下差异**逐位不变** |

`jacob`(`Elements.f90:3245-3318`)与 `evaluate_rule`(`yl_runtime_build.f90`)
**逐行同形**:同样的循环顺序、同样的公式、同样的求逆写法。
输入全等、源码同形,结果仍差 1 ULP。

### 7.3 根因

**编译器层面的浮点变换**,而非迁移字段遗漏或错误。
决定性证据:`-fp-model=precise`(禁止重结合与倒数替换)下——

```
cartd IDENTICAL
PASS  blocks=600 values=541200 mismatches=0 max|d|=0.000e+00
```

**两条路径在 600 个块、541 200 个数值上完全相同。**
`-fma-` 单独无效而 `-fp-model=precise` 有效,说明不是乘加收缩,
而是重结合/倒数替换这一类变换在两个例程上被施加得不同
(一个累加到标量局部量、一个累加到数组元素,`-O2` 下优化决策不同)。

### 7.4 需要负责人裁定的事

按第 5 条的三个条件,现在**全部成立**:输入与语义状态完全相同;
第一处分叉来自编译执行路径而非迁移缺陷;两条路径各自确定可复现。

**本轮不自行修改判据。** 可选项与代价留待裁定,不在此预设。

### 7.5 临时设施与保留边界

- `tools/probe/yl_step_probe.f90`:位级逐步探针,**不进入任何构建目标**,是本次结论的复现器。
- `build.sh` 新增 profile:`initzero`(排除未初始化存储)、`nofma`(排除收缩)、
  `fpprecise`(**本结论的证据**)。三者都不是默认路径。
- `HSTAR_EXTRA_LEGACY`:允许把一个额外源文件加进 legacy 编译列表,
  使探针无需弄脏被跟踪的 legacy 树。默认为空。
- **没有**把塑性积分器纳入观测面,**没有**新增常设门禁。

## 8. 裁定执行:`evaluate_rule` 复用 legacy `jacob`(2026-09-14)

按裁定采用方案一。改动是最小复用:`evaluate_rule` 不再自己算雅可比、求逆和笛卡尔导数,
改为 `call jacob(...)`,并把 `cartd` 抄进 `shape_gradient`。
**没有重构 `jacob`**;B3(雅可比非正)判据**留在本层**——legacy 只告警继续,拒绝是本 build 的决定。

### 8.1 确认(默认编译选项,未启用 `-fp-model=precise`)

```
PASS  blocks=600 values=541200 mismatches=0 max|d|=0.000e+00
```

600 块、541 200 个数值,**严格 `max|d| = 0`**。判据未修改。

### 8.2 一处必须单独报告的边界代价

`tools/build.sh` 里 `runtime` 目标原本的注释写着两条理由:

> 「Keeping it out here is what makes this target buildable **without the legacy tree**,
> and it is also the mechanical guarantee that **no self-test in this binary can write a
> legacy global**。」

**第二条完好**:`jacob` 是纯计算,不读不写任何全局。
**第一条被打破**:该目标此前**不含任何 legacy 源文件**,现在需要
`variable_types`、`arrayutil`、`elements` 及其依赖的诊断模块——共 5 个文件。

也就是说:**「不写 legacy 状态」的安全性质保住了,「不依赖 legacy 树」的构建独立性没保住。**
这是本次复用的真实代价,不是顺带清理。是否长期接受由负责人裁定;
注释已写在该目标旁,使后来者看到的是代价而不是一份更长的文件清单。

### 8.3 顺带修掉的一个工具脆弱点

`runtime` 目标开始编译 legacy 源之后,构建日志里混进了 latin-1/GBK 注释字节,
而 `yl_state_map.py runtime-rules --export` 以 UTF-8 读取该日志,直接 `UnicodeDecodeError`。
它要解析的 `RULE|` 行是纯 ASCII,日志别处的一个字节不该成为关于规则表的结论——改为
`errors="replace"`。

### 8.4 边界维持

临时浮点探针与 `initzero` / `nofma` / `fpprecise` 三个 profile **仍为非默认**,
未升级为常设治理设施;未新增常设门禁;塑性积分器未纳入观测面。

## 9. `mat_curve = 2` 能力收口:`train05b_slope_srm`(2026-09-15)

### 9.1 判据

| 判据 | 实测 |
|---|---|
| 现代输入独立驱动 | 门禁 **N1**:工作目录只有 `case.toml` + `1.cor`/`1.ele`,**无任何 legacy 控制卡**,`rc=0` |
| 材料曲线链路成立 | `mat_curve` → `steps[0].load.strength_reduction`(按名字引用 amplitude)→ commit → `Stiff.f90:5779` |
| **真实非零 `PLASTICSTRAIN`** | 门禁 **N4**:**18 924 / 45 100 个非零值**(冻结参考中同样) |
| 与冻结 legacy 参考严格等价 | 门禁 **N2**:`blocks=600 values=541200 mismatches=0 max|d|=0.000e+00` |

**这才是塑性真正发生的算例。** `mini_mc` 的 `PLASTICSTRAIN` 恒为 0,只能确立读取/映射/分派;
本算例 42% 的塑性应变值非零,通过的等价比较因此**也覆盖塑性回映**。

### 9.2 这一能力实际打开的白名单

全部由这份真实 deck 逼出来,没有一条是预先设计的:

| 行 | 取值 | 原因 |
|---|---|---|
| `step.load.mode` | `load` / `strength_reduction` | legacy `type_load`,后者即 `MAT_DE` |
| `step.load.strength_reduction.amplitude` | 按名字引用 | 折减进度表;**条件必填**(有模式必须有曲线,无模式不许有曲线),两个方向各有反例 |
| `step.controls.steps` / `time_increment` | 100 / 0.01 | **移出默认表**:它们决定分析停在折减曲线的哪一点 |
| `material[].thermal_expansion` | 5.0e-6 | **移出默认表**:真实 deck 之间不同(静力两例是 1.0e-5) |
| `output.field` | 增 `ms` / `f` / `y` | 主应力、节点合力(`tofor`)、屈服指示 |
| `output.stress_averaging` | 增 `smoothed_legacy` / `direct_legacy` | legacy 的 -1/-2:同样两种方案,但只作用于通过 `Output.f90:5104` 资格判定的单元组。本 deck 用 -2 |

### 9.3 三处工程性事实

- **参考基线 13.5 MB**,gzip 后 3.0 MB。冻结件必须**完整**(逐块摘要不是验收要求,但审计要靠它),
  所以压缩而不是裁剪;`yl_compare` 两种拼写都读。
- **比较器的结构性失败也要有界**:"block names differ" 原样打印两份 600 元素列表。
  改为只报两边的块数与**第一处不同的位置**。
- **TOML 子集要求数组写在一行**。41 个节点号一行放得下;真要几百个节点的集合时再教读取器多行数组——**不是现在**。

### 9.4 结论边界

本次确立:`CLASSICALEP/MC` + 强度折减在真实 deck 上由现代输入独立驱动,
且在**塑性确实发生**的条件下与冻结 legacy 参考严格等价。
**未**确立:其他准则(TC/VM/DP/MCC/DPC/MCJOINT)、其他本构模型、
以及 §2.4 那四个与模型正交的子能力族——它们仍是 legacy-only。
