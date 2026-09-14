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

### 5.1 这一能力实际改动的边界

- 白名单新增：`material.model` 增 `CLASSICALEP`；`criterion` 只收 `MC`；
  `stiffness_update` 两个取值（legacy `type_nl` 5/4）；`output.field` 增 `ep`。
- 白名单**移除**：`model.section_count`（原钉死 1）。移除的前提是新增校验 **V26**
  「每个 section 至少拥有一个单元」——那行旁边写着的正是这个前提。
- 契约首次出现**按模型条件必填**：`model_requires` 两个方向都查。
- `elset[].mesh_group` 改为 `elset[].element_count`：前者是**死键**（声明了、从没被读过），
  而单元归属在 legacy 里本来就是**按文件顺序、每组取 nelgroup 个**；
  `.ele` 是否带组号列因算例而异（`lame_cylinder` 带、`mini_mc` 不带），legacy 两种都忽略。
