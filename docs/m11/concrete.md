# M11 · CONCRETE：材料域的第三个本构，也是第一个真正触发的损伤路径

## 1. 切片：全语料普查后只有一个候选

CONCRETE 的真实 deck 有 54 份（去重后 6 个算例）。按「2-D 且不含线单元组」筛，
**只剩两份 `.glb`，而且是同一个算例**：

| deck | 为什么不能用 |
|---|---|
| `damage`（3-D，1 单元） | 3-D 未开始 |
| `train06_concrete_damage`（3-D，230 单元） | 3-D，且多块 |
| `rcbeam` / `rcbeam_crack` / `tunnel` / `tunnel_sl`（2-D） | 都带 L2/steel，随 M9 暂停 |
| **`hstar_jobs/0406_210921_443f933d`** | **可用** |

选中的 deck：46 节点 / 32 单元、**两个 Q4 组**、2-D、`NBLKS=1`、`nscurve=0`、
`PARDISO`（M10 已迁移的前置）。与快照二进制**逐字节相同**，
适配器对它的**唯一**发现就是 `materials[2].model: CONCRETE`。

这一次没有落入 M9 的耦合陷阱，而且是靠证据确认的，不是靠构造。

## 2. 能力差值：9 个输入 + 1 个选择子 + 2 个派生

`.mat` 的 CONCRETE 记录是一条九个值的记录：

```
0.013  0.1177  0.7509  0.246  3.480E+07  0.1  100  0.1  6
  A      B        C      D       Fc       Ct   Gf   h  icr
```

**四个系数按它们在 legacy 自己表达式里乘的东西命名**，不按字母
（规则 10 本来也不允许拿 `A`/`B`/`C`/`D` 进类型，而字母本身什么也没说）：

```
eqstr = A*steff**2/Fc + B*steff + C*sigma1 + 3*D*smean      (Residu.f90:3265)
        ^偏应力二次      ^偏应力一次  ^主应力     ^平均应力
```

| legacy | 现代名 | 单位 |
|---|---|---|
| `A` | `dev_stress_quadratic` | 1 |
| `B` | `dev_stress_linear` | 1 |
| `C` | `principal_stress` | 1 |
| `D` | `mean_stress` | 1 |
| `Fc` | `compressive_strength` | Pa |
| `Ct` | `tensile_ratio` | 1（legacy 注释即 `Ct=Ft/Fc`） |
| `Gf` | `fracture_energy` | N/m |
| `h` | `characteristic_length` | m（软化律要除以它，答案依赖于它） |
| `icr` | `crack_model` | id，**白名单只放行 6** |

**`icr` 是选择子，决定后面还读不读**：

* `icr == 2` → 再读一条 `ft0/eft/at/bt/alfat`（Material.f90:700）
* `icr ∈ {3,5,6}` → **不再读**，改为**派生** `bb` 与 `et0`（:684-694）

只放行 6——那是这个真实 deck 的取值。`rcbeam` 用 3，但 rcbeam 属 M9 且已暂停，
放行 3 就是一条没有 deck 支撑的声称。

**`bb` / `et0` 不是输入，是读取器的派生**，因此由桥接**逐字照抄** legacy 的表达式
（含 `bb<0` 的钳位）复现，而不是重新推导一个等价形式——
在逐位一致的判据下，「等价改写」正是 1-ULP 偏差的入口。

其余 `at/bt/alfat/t1..t4/ft0/eft` 与受压侧的 `ac/bc/...` 属 `icr==2` 分支，
legacy 在本路径上同样不写它们，所以桥接也不写、不下毒——下毒反而会与 legacy 路径不同。

## 3. `Yield` 非零——但**不是损伤**。判据 5 不成立

这一节记录一个我先下错、后被证据推翻的结论。

第一次看 `Yield` 时我读到「460 个值里 169 个非零，第 1 子步为零、其后逐步演化」，
就判定损伤已经触发。**这是错的**，而且当时手上就有能证伪它的东西：
`damage` 在 legacy 里只有两种取值——`0.`，或 `1-sqrt(cc)`（Residu.f90:3664/3675）——
**它不可能大于 1**。

逐值分类之后：

| 取值 | 个数 |
|---|---|
| 恰好 0 | 291 |
| 落在 (0,1)，即真实损伤 | **0** |
| 大于 1e9 | **169** |

**一个真实损伤值都没有。**

### 根因：legacy 的一处未初始化读

`Residu.f90:3656` 的**卸载分支**只赋 `iload`、`ftv`、`y0`，**从不赋 `damage`**：

```fortran
if(estar<=estar0.or.(iload0==0.and.estar<estarm))then
    ftv=ftv0-(estar0-estar)*(1-damage0)**2*e
    y0=ftv/ft0
    iload=0                      ! <- damage 没有被赋值
else
    ...
    damage=1-sqrt(cc)
endif
...
element(ielem)%field(1)%gpvar(nstre+2,igaus)=damage    ! :3696 照写不误
```

于是 `:3696` 把一个**未初始化的局部变量**写进输出槽。
`-O2` 下它是残留栈值（常常正好等于 `E` = 3.170E+10），`-O0` 下是 0。

这也解释了 tracer 那句 `max|d| = 3.170e+10 -- that is build independence`：
**那不是构建独立性**。tracer 对任何不一致都套这句话，而 3.17e10 是本构的 E，
不是 1e-13 量级的噪声。差点被我按噪声记下去。

这是 **legacy 自身缺陷**，不是迁移引入：本仓库构建与 5414e73 快照对该 deck
`1.flavia.res` **逐字节相同**（`5f3036c863225b2b`）。

### 对本轮的后果

> **已回填（2026-09-20）**：判据 5 由 **后补证据 BACKFILL-1** 满足——证据在 M9 的 `elements_2d.rcbeam` 上，不在本算例上。登记见 [`../acceptance/M7P4-M11-consolidated-matrix.md`](../acceptance/M7P4-M11-consolidated-matrix.md) §2，签收口径见同文件 §4（M11）。**下面这一段的结论不变**：本算例确实不触发损伤。

判据 5「`Yield` 必须真实非零」**不成立**，且情形比全零更糟——是非零的垃圾值。
按判据 6，本轮只能声称**读取、映射与派发链路成立**，
**不能签收 CONCRETE 能力**。与 `mini_mc` 的 `PLASTICSTRAIN` 全零是同一类记账。

没有为了让损伤发生去改荷载、材料参数或构造算例。

### 语料里哪些 deck 真的有损伤

同样按「(0,1) 内的值」逐个量：

| deck | 真实损伤值 | 可用性 |
|---|---|---|
| `tunnel_sl` | 47 765 | 2-D，但带 L2 —— M9 |
| `rcbeam` / `rcbeam_crack` | 5 371 | 同上 |
| `tunnel` | 2 703 | 同上 |
| `damage` | 80 | 3-D，未开始 |
| `train06_concrete_damage` | 0 | 同样不进损伤分支 |
| **本算例** | **0** | 判据 5 不达 |

**凡是真的进损伤分支的 deck，都需要 L2 或 3-D。**
本算例躲开了这两处耦合，代价正是它从不进损伤分支——
对建立链路足够，对签收能力不够。

负责人裁定（2026-09-18）：**恢复 M9，以 `rcbeam` 作 CONCRETE + L2 的联合切片**。
rcbeam 的两个阻塞（PARDISO、CONCRETE 链路）都已解除，且它有 5 371 个真实损伤值。

## 4. 回归证据

```
MODERN PASS（九例）
  N2 damage_2d.concrete_gravdam   blocks=30 values=3220  max|d|=0.000e+00
  N4 damage_2d.concrete_gravdam   Yield non-zero values: 169
  其余八例 max|d| = 0.000e+00，一个都没动
FALLBACK PASS
```

三条新反例，运行前先写预期：`crack_model = 2` → exit 3；删掉
`compressive_strength` → exit 2；把 `crack_model` 写到同一 deck 的弹性材料上 → exit 2。

## 5. 执行环境现在是参考的一部分（M10 规则的落地）

按裁定，「冻结参考包含执行环境」已成为通用规则，并且是**机械**的而不是约定：

* `yl_run.pinned_env()` 是唯一定义，runner 施加、两个 checker 复用；
* 参考里记录的环境**取自实际施加的那一份**，不再手写列举——
  原先手写的那份已经漂移（漏了 `MKL_DYNAMIC`）；
* `PINNED_KEYS` 与 `pinned_env()` 之间有断言，防止再次分叉。

本算例的参考因此记录为
`{"OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "MKL_DYNAMIC": "FALSE"}`。

## 后记（2026-09-18）：判据 5 在 `rcbeam` 上补上了

本文件结论不变——**`damage_2d.concrete_gravdam` 这个 deck 确实不触发损伤**，
它的 `Yield` 非零值全部是 PD-3 写进输出槽的未初始化局部量。

但 CONCRETE 的损伤路径本身**已经有可验收证据**了，只是在另一个算例上：
M9 的 `elements_2d.rcbeam`（`crack_model = 3`）在同一条断言下是
**5 371 个落在 (0,1]、区间外 0 个**，并且现代输入与冻结参考逐位一致
（120 块 / 214 110 值 / `max|d| = 0.000e+00`）。见
[`../m9/l2-element-domain.md`](../m9/l2-element-domain.md) §5。

也就是说本域的两半现在分别由两个真实算例支撑：
读取/映射/派发链路由 `concrete_gravdam` 证明（最小切片、唯一差值就是 `model: CONCRETE`），
损伤演化由 `rcbeam` 证明（真实非线性响应被触发）。
签收口径由负责人决定；本文件只负责把两边各自确立了什么写清楚。

N4 的 `in_range` 就是这一课的机械化：`must_be_nonzero` 单独通过过一次，靠的是垃圾值。
