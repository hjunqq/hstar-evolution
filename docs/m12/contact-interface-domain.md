# M12 · 接触与界面域 · 阶段 0：语义还原

日期 2026-09-20。本阶段**不设计 schema、不扩 ProblemState、不碰本构**，
只回答一个问题并给出可验证依据：

> **Goodman 节理中的 `gap` / `natural_thickness` 到底由什么输入或几何关系定义，
> legacy 正常路径原本应如何建立它们。**

（`docs/STATUS.md` 的功能域视图把本域标为 `M6.6`，那一列是开工前的规划编号；
实际里程碑已按 M9/M10/M11 顺序推进，故本域取 **M12**，两者指同一件事。）

---

## 0. 里程碑合同

| | |
|---|---|
| 目的 | 还原接触/界面的输入语义与状态建立路径，使 PD-4 可被有证据地回答 |
| 范围 | `.mat` 的 `CONTACT` 材料记录、`contact_state` 初始化与演化、Goodman 节理的几何派生 |
| 非范围 | authoring schema、ProblemState、本构、3-D、动力/渗流接触 |
| 验收判据 | ① 四类语义（输入 / 材料 / 几何派生 / 动态演化）逐项有源码位置与真实 deck 佐证；② 找出或证伪「可运行且能触发接触状态变化的最小算例」；③ PD-4 归属有机械证据，**不靠推断** |
| 预算 | 本 session，定位轮次 ≤5 |

---

## 1. 先更正上一轮的一处测量错误

PD-4 记了一句「全树 1 361 个 `.glb` 里把组 SPTYPE 声明为 `CONTACT` 的有 **0** 个」。
**那句话量错了字段。** legacy 判断接触用的 `name` 不是组头的 SPTYPE：

| 位置 | `name` 从哪来 |
|---|---|
| `Global.f90:1280` | `name = group(igroup)%sptype` —— **只在 `read_element` 里用**，是单元表读取的局部量 |
| `Fem.f90:11741` / `Fem.f90:12763` | `name = props(matno)%name` —— **材料记录的第二个字段**，`Material.f90:283` 的 `read(munit,*) property, name, imat` |

也就是说，接触是由 **`.mat` 的材料头**声明的：

```
     material_serial         3
          MECHANICAL             CONTACT    3      <- property=MECHANICAL, name=CONTACT, imat=3
```

重新按正确字段做全树普查：

| 测量 | 结果 |
|---|---|
| 扫描 `.mat` 文件 | **1 340** |
| 材料记录 `name` 字段分布 | `SOLID 2088` / `ROD_OR_BEAM 46` / `WATER 51` / **`CONTACT 11`** |
| 含 `name=CONTACT` 的 `.mat` | **11 份** |

**语料里确实有接触 deck。** PD-4 的那句话作废，归属随之改写，见 §5。

---

## 2. 输入语义：`CONTACT` 材料记录追加什么

`Material.f90:419-448`，只在 `name=='CONTACT'` 时读：

```fortran
if (name=='CONTACT') read(munit,*) igap0, gap0, ftcontact, icft
if (igap0==2) then
    read(munit,*) gap_define%gap_kind, ngapx
    if (gap_kind==1) then          ! 仅 ndimn==2，否则 M1-03 按名拒绝
        read(munit,*) radius, centerx(1:ndimn)
        read(munit,*) gapalfax(1:ngapx)
        read(munit,*) gapx(1:ngapx)
    endif
endif
```

| 键 | 类型 | 含义 | 归类 |
|---|---|---|---|
| `igap0` | int | **初始间隙来源的选择子**，见 §3 | 接触输入 |
| `gap0` | real | 常数初始间隙，**仅 `igap0==1` 消费** | 接触输入 |
| `ftcontact` | real | 接触面抗拉强度，状态机的 `ft0` | 接触输入 |
| `icft` | real | 是否启用 `ftcontact`（`icft==0` 时 `ft0` 取 0.01） | 接触输入 |
| `gap_kind` / `ngapx` / `radius` / `centerx` / `gapalfax` / `gapx` | | **圆弧几何**描述，仅 `igap0==2 .and. gap_kind==1` | 接触输入（几何参数） |

真实取值（`cases/cases/disc_contact_3d`，圆柱接触，唯一的 CONTACT+GOODMAN 模型）：

```
          MECHANICAL             CONTACT    3
GOODMAN   0.000E+00  0.100E+01  0.100E+01  0.100E+12  0.300E+00  1.000E-05  0 0 0
  0  0  0    0.100E+04
       99      0.000E+00      -.001    1      <- igap0=99  gap0=0.0  ftcontact=-0.001  icft=1
JANBU  ...
```

**组头侧不声明接触**：该 deck 三个组的 SPTYPE 全是 `PE`，接缝组（GROUP3，140 个单元，
matno=3）靠的是 **`elcod_local = 0.001`** —— 把线状接缝沿法向偏移展成零厚度四节点单元
（`Elements.f90:3368` 的 `normal_local_inc`）。这与 `mini_goodman` 调查里量到的
「全树 119 条 `elcod_local /= 0` 的组定义中 95 条是 q4」是同一条正常用法。

---

## 3. `gap` 的三条来源，由 `igap0` 选择

`Fem.f90:12818-12885`，条件是**本组本块首次出现的第一个迭代**
（`appear_process(igroup,iblks)==1 .and. appear_process(igroup,iblks-1)==0
.and. iincs==1 .and. istep==inc_step .and. iiter==1 .and. ic==0`）：

| `igap0` | `gap` 从哪来 | 归类 | 是否设 `natural_thickness` |
|---|---|---|---|
| `1` | `gapg = gapg0 = gapn = gapn0 = gap0`（材料给的常数） | **输入** | **否** |
| `2` + `gap_kind==1` | 按节点 x 坐标相对 `centerx`/`radius` 求方位角 `alfax`，在 `(gapalfax, gapx)` 折线上**线性插值**得 `gapnod`，再用形函数插到高斯点 | **几何派生（由输入的圆弧描述）** | **否** |
| `99` | `nordis(inode) = rot · coord(:, node)`（节点坐标在法向上的投影），2-D 下 `gapnod(1)=nordis(4)-nordis(1)`、`gapnod(2)=nordis(3)-nordis(2)` —— **零厚度四节点接缝单元上下对应节点的法向间距** | **纯网格几何派生** | **是** |

GOODMAN 与非 GOODMAN 在插值上差一处，是本域必须记住的细节：

```fortran
if (material=='GOODMAN') then
    shape = elkn(jndex)%ggaus(order_int)%shape(:,:)   ! jndex=1 (2-D)，即线单元的形函数
    gapgaus = transpose(shape) .x. gapnod(1:nnode_half)   ! 只取一半节点
else
    shape = elkn(index)%ggaus(order_int)%shape(:,:)
    gapgaus = transpose(shape) .x. gapnod
endif
```

`nnode_half = nnode/2`：Goodman 单元是四节点，但上下两条边一一对应，间隙只有 `nnode/2` 个独立值。

### `natural_thickness` 的唯一赋值点

```fortran
! Fem.f90:12882-12884，在 igap0==99 分支内部
if (istep.eq.1 .and. iincs==1) then
    element(ielem)%field(1)%natural_thickness = element(ielem)%field(1)%gapg
endif
```

**结论（本阶段的核心交付）**：

> `natural_thickness` = **第一步第一增量时的初始几何法向间隙**，
> 即零厚度接缝单元上下对应节点在法向上的原始距离；
> 它**只由 `igap0==99` 这条纯几何路径建立**，不是任何输入字段，也不是 `elcod_local`。

`elcod_local` 与 `natural_thickness` 的关系是**间接**的：`elcod_local` 决定了
`normal_local_inc` 把两个节点沿法向偏移多远，于是决定了 `coord`，`coord` 再经
`rot ·` 投影相减得到 `gapnod`。**两者数值上未必相等**（`rot` 是单元法向，偏移是按
`elcod_local` 沿该法向做的，但 `gapnod` 取的是投影差），所以
**不能把 `natural_thickness` 直接映射成 `elcod_local`** —— 上一轮 PD-4 里写的
「很可能是 `elcod_local`」是猜测，本阶段按证据**否掉它**。

---

## 4. 四类语义的分离（用户要求的分类）

| 类别 | 内容 | 源码位置 |
|---|---|---|
| **(a) 接触/界面输入语义** | `igap0`, `gap0`, `ftcontact`, `icft`；`igap0==2` 追加 `gap_kind`, `ngapx`, `radius`, `centerx`, `gapalfax`, `gapx`。组侧的 `elcod_local`（把接缝展成零厚度单元） | `Material.f90:419-448`；`Global.f90:1216-1221`（`elcod_local` 在组头） |
| **(b) GOODMAN 材料参数** | `model`(JANBU/FCM/WATERTIGHT/EQUBOLT), `point1`, `point2`, `uniax_cohes`, `frict_angle`；JANBU 追加 `K1, n, Kzz, Rf, phi, Kzx, pa, gamaw, cohes, Ft`（`ndimn==3` 再加 `Kzy`） | `Material.f90:544-565` |
| **(c) 网格/几何派生状态** | `rotation`, `aera_local`, `evk`（按**材料** `GOODMAN` 分配）；`gapn0`, `gapg0`（按 `igap0` 建立）；**`natural_thickness`（仅 `igap0==99`）** | `Fem.f90:12018-12020`；`Fem.f90:12822-12884` |
| **(d) 求解中动态演化的状态** | `gapn = gapn0 + gapnod(位移)`；`gapg = gapg0 + gapgaus(位移)`；`state ∈ {contact, open}`, `state0`, `state1`, `icftcontact ∈ {0,1}`, `icok` | `Fem.f90:12886-12986` |

状态机（`Fem.f90:12949-12974`），**两条判据形态不同，必须分开记**：

```
contact → open :  smean > ft0            （应力判据；同时令 evk(:,igaus) = 0.02）
open → contact :  gap_change < eps  .and.  current_gap < natural_gap   （几何判据）
   其中 gap_change = gapg - gapg0 , natural_gap = natural_thickness , eps = 1.e-5
```

PD-4 那段罚函数（`Stiff.f90:880-888`）属于 **(d)**，消费的是 (c) 的 `natural_thickness`：

```
normal_gap = gapg - natural_thickness
if (normal_gap < 0) evk(ndimn) = evk(ndimn) * 100
where (evk > 1.0d9) evk = 1.0d9
```

**`gap` 分配面**：`gapg0/gapg/gapn0/gapn/state0/state/state1/icftcontact/natural_thickness`
九个数组一次分配，条件只有 `name=='CONTACT'`（`Fem.f90:11999-12008`）。
而 `evk` 在同一段里按 `material=='GOODMAN'` 分配（`Fem.f90:12018`）。
**这两个门控不同，正是 PD-4 的机制。**

---

## 5. PD-4 归属改写（有机械证据）

上一轮判为「legacy 原有缺陷」。按 §1 的正确测量，归属是**两半**，必须分开说：

**一半是 deck 声明缺陷。** 三个 GOODMAN deck 把节理材料声明为 `MECHANICAL SOLID n`：

| deck | 材料头 | 后果 |
|---|---|---|
| `goodman_evolution` | `MECHANICAL SOLID 4/5/6/7` | 不满足 `name=='CONTACT'` → 九个接触数组从不分配 → `contact_state` 整个跳过 → `Stiff.f90:880` 读未关联的 `gapg` → SIGSEGV |
| `goodmanLU` | 同上 | 同上（且 `.ftr` 先行读到文件尾） |
| `mini_goodman` | 同上 | 同上（且更早崩在 `elcod` 越界） |
| **`disc_contact_3d` / `_archive/…/圆柱接触/disc_contact`** | **`MECHANICAL CONTACT 3`** + `igap0=99 gap0=0.0 ftcontact=-0.001 icft=1` | **正确写法的唯一实证** |

**另一半仍是 legacy 缺陷，但性质与上一轮写的不同。** 不是「计算逻辑错」，
而是**缺 fail-closed 守卫**：进入罚函数那一段只要求 `material=='GOODMAN'`（材料级），
却去读只在 `name=='CONTACT'`（声明级）下分配的数组。一个写错声明的 deck 得到的是
SIGSEGV，而不是一条点名的诊断。**这属于 M1 防线的范畴**，不属于本域的能力。

### 新发现，登记为 PD-5

`natural_thickness` 在 `name=='CONTACT'` 下**无条件分配**（`Fem.f90:12008`），
却**只在 `igap0==99` 分支赋值**（`:12882-12884`）。因此一个
`igap0==1` 或 `igap0==2` 的 GOODMAN 接触 deck 会：

- 分配成功（所以**不会**是 408「未关联指针」），
- 然后在 `Stiff.f90:880`、`Residu.f90:1158`、`Fem.f90:12936` 读到**未初始化的已分配内存**。

这与 PD-3（CONCRETE 卸载分支写出未初始化 `damage`）是**同一形态**：
不崩，安静地产出垃圾。目前语料里唯一的 CONTACT+GOODMAN 模型用的是 `igap0=99`，
所以这条路径还没有真实 deck 踩到——**但它是一个已经装好的陷阱**。
登记于 `docs/m8/pre-migration-defects.md` 的 **PD-5**，本阶段不修。

---

## 6. 可运行算例：**没有**，并且量清了缺什么

11 份声明 `CONTACT` 的 `.mat` 对应的 deck，逐个用本仓库 release 实跑：

| deck | 接触材料 | `TYPE_PROBLEM` | 实测 | 缺什么前置 |
|---|---|---|---|---|
| **`cases/cases/disc_contact_3d`**（名字带 3d，实为 **2-D**：3 922 节点 / 3 740 单元 / `ndimn=2`） | **CONTACT + GOODMAN，`igap0=99`** | **`Q`** + PARDISO + `NBLKS=1` + 全 Q4 | **rc=59**，读 `.mat` 的 JANBU 记录时 list-directed 语法错 | ① **deck 缺陷**：`JANBU` 那行只有 3 个记号（`model` + 2），正确形状是 5 个（`model, point1, point2, uniax_cohes, frict_angle`），于是 `uniax_cohes`/`frict_angle` 被从下一行取走，参数行随即短 2 个；② `nscurve /= 0`（材料属性曲线，M10 普查已记） |
| `_archive/…/圆柱接触/disc_contact` | 同上（同一模型的另一份副本，`JANBU` 行同样只有 3 个记号） | — | rc=2，`.glb` `init_and_blocks` 输入转换错 | `.glb` 是更老方言（与 `pile_beam` 同类） |
| `cases/cases/fix`、`hstar_jobs/0415_…`、`hstar_jobs/0630_…` | CONTACT + ELASTIC_ISOTROPIC | **`F`**（渗流/固结） | rc=2，`.glb` `matno_process` 解析失败 | 两道：非 `Q` 问题类型 + 更老方言 |
| `cases/cases/freq` | CONTACT + ELASTIC_ISOTROPIC | **`E`**（模态） | **rc=0**，2.3 MB 结果 | **不是接触证据**：`E` 不走 `static_u`，`contact_state` 从未被调用（运行目录**没有 `fort.7`**，而 `contact_state` 入口第一句就是 `write(7,*)`） |
| `hstar_jobs/0330_212302_…/test_2d` | 同上 | **`F`** | **rc=0**，1.1 MB 结果 | 同上，无 `fort.7` |
| 其余 3 份（`_archive/process/fix`、`_archive/process/freq`、`0330_233554_…/1_backup.mat`、`0330_232945_…`） | CONTACT + ELASTIC_ISOTROPIC，其中两份 `ndimn=3` | — | 与上面同源或 3-D | 同上 |

**两条结论，都是量出来的**：

1. **唯一形状合格的接触算例是圆柱接触**（2-D / `Q` / PARDISO / Q4 / 单块 / `elcod_local≠0` /
   `igap0=99`）—— 它几乎正好落在当前白名单里，**只差两样**：一个 `.mat` 记录缺 2 个值，
   一条材料属性曲线。而语料里它只有两份副本，**两份的 `JANBU` 行都短 2 个记号**。
2. **能跑出结果的那两个 CONTACT deck 都不触发接触**：一个是模态、一个是渗流，
   `contact_state` 根本没被调用。用 `fort.7` 是否生成作判据，比读结果文件更直接。

按裁定「不自造能力证明」：**不补那两个缺失的值**——它们是 `uniax_cohes` 与
`frict_angle`，是真实物理参数，凭空填写就是发明输入。

---

## 7. 本阶段结论与下一步

| 问题 | 答案 |
|---|---|
| `gap` 由什么定义 | 由 `.mat` 的 `igap0` 选择三条来源之一：常数 `gap0`(1) / 圆弧几何插值(2) / **纯网格法向间距(99)** |
| `natural_thickness` 由什么定义 | **第一步第一增量的初始几何间隙 `gapg`**，**只有 `igap0==99` 会建立它**；不是输入，也**不是** `elcod_local`（该猜测已被否掉） |
| legacy 正常路径应如何建立 | 材料头写 `MECHANICAL CONTACT n`，追加 `igap0/gap0/ftcontact/icft`；组头 `elcod_local≠0` 把接缝展成零厚度四节点单元；`static_u` 每块首迭代调 `contact_state(0)` 建立初始间隙，之后 `contact_state(1)` 按位移演化 |
| PD-4 归属 | **两半**：deck 把节理材料声明成 `SOLID` 而非 `CONTACT`（deck 缺陷）＋ legacy 在材料级分支里读声明级数组、缺 fail-closed 守卫（M1 防线范畴） |
| 本域能否取得真实参考 | **暂不能**。唯一形状合格的算例的 `.mat` 缺两个真实物理参数，按裁定不补 |

**PD-4 仍不关闭**：按裁定，它要等本域「给出有证据支撑的 `gap`/`natural_thickness` 来源
**并恢复真实路径**」之后才关。来源已经给出（本文 §3），**真实路径尚未恢复**，因为没有可运行算例。

**建议的下一步（需裁定）**：本域在「等一个完整的接触 deck」与
「先做 legacy 侧的 fail-closed 守卫」之间二选一。后者是 M1 防线的自然延伸、
不需要新算例、且能把 PD-4 的 SIGSEGV 变成一条点名诊断——但它**不产生接触能力**，
也不关闭 PD-4。

---

# 阶段 1（2026-09-20）：legacy 侧 fail-closed 防线

**本阶段不计作接触能力迁移，不关闭 PD-4。** 只做一件事：把两条会**静默出错**的路径
变成**点名拒绝**。不新增 authoring schema、不扩 ProblemState、不改 GOODMAN/JANBU 数值实现、
不补圆柱接触 deck 缺失的参数、不自造可运行接触算例。

## 8.1 改了什么：三条语句，三个文件行数不变

按既有纪律（M4-02 / M5 / M7 / M9 / M10 同形）用 `;` 接到**已有行**尾，
所以 io 站点普查、检查点锚点与全部 reader 行号原地不动——`runtime` 门禁的
`io-sites.json is a current scan` 当轮实测通过。

| 文件:行 | 接在哪条语句后 | 守卫 |
|---|---|---|
| `Stiff.f90:878` | `call PKPN(matno,evk,sgtot,first)` | **PD-4** + PD-5（纵深） |
| `Residu.f90:1156` | 同上（`residu_f` 的同一表达式） | **PD-4** + PD-5（纵深） |
| `Fem.f90:12768` | `igap0 = props(matno)%mechanical%solid%igap0` | **PD-5** |

**PD-4 守卫**（`Stiff.f90:dep` / `Residu.f90:residu_f`）：

```fortran
if(props(matno)%name/='CONTACT') call diag_abort('UNSUPPORTED',EXIT_UNSUPPORTED,'Stiff.f90:dep', &
    'PD-4: material N is GOODMAN/JANBU but its .mat header declares name="SOLID", not CONTACT; &
     gapg/natural_thickness are allocated only for a CONTACT material (Fem.f90:11999) ...')
```

它守的正是 §5 认定的那半个 legacy 缺陷：**进入分支看的是本构名（材料级），
读的却是按声明名（`name=='CONTACT'`）分配的数组**。守卫把这个不一致变成一条点名诊断。

**PD-5 守卫**（`Fem.f90:contact_state`）：`igap0/=99` 一律拒绝，**不限本构模型**——
因为消费点 `Fem.f90:12936`（`open→contact` 判据）对所有接触材料都执行，不是 GOODMAN 专有。

**改动恰好是这三处追加**：把追加的字节去掉后复原的三个文件与上一提交**逐字节相同**
（Stiff 追加 752 B / Residu 764 B / Fem 353 B）。`legacy/source-manifest.json` 已重新生成，
39 个文件里散列变化的恰好是 `yl/Stiff.f90`、`yl/Residu.f90`、`yl/Fem.f90`。

## 8.2 正反例：三个对照，外加一个「对照的对照」

门禁 `tools/yl_contact_guard_check.py`，已接入 `tools/build.sh release`。

| 控制 | 是什么 | 实测（2026-09-20T08:05Z） |
|---|---|---|
| **C3 正例** | 未改动的 golden deck `plasticity/mini_mc` 必须照常跑完 | `rc=0`，5 818 B 结果 — **PASS** |
| **C1 反例（PD-4）** | **真实 deck** `cases/cases/goodman_evolution`（节理材料声明成 `SOLID`） | `rc=3`，`site="Stiff.f90:dep"`，点名 `material 5 ... declares name="SOLID", not CONTACT`，**不写结果** — **PASS**（守卫前是 `rc=174` SIGSEGV、无输出、无诊断） |
| **C2 反例（PD-5）** | 由 C3 那份 golden deck **运行时派生**：一个材料头改成 `MECHANICAL CONTACT`，插入一条 `igap0=1` 记录 | `rc=3`，`site="Fem.f90:contact_state"`，点名 `natural_thickness is assigned only under igap0=99` — **PASS** |

**更宽的正例**是九个 golden 算例在本轮改动后仍逐位复现冻结参考
（`N2` 全部 `mismatches=0 / max|d| = 0.000e+00`，`FALLBACK PASS`），门禁不重复它。

C2 的派生**不发明任何物理**：插入的 `gap0 / ftcontact / icft` 三个数在运行被拒之前
根本没被消费——拒绝发生在读到 `igap0` 的那一刻。派生结果只存在于临时目录，
**不写进 `cases/`**。

### 对照的对照

按「阴性对照会失效并伪装成结论」这条纪律，还要证明 **C2 的 `rc=3` 来自守卫**，
而不是派生本身把 deck 弄坏了。把**同一份派生 deck** 交给**无守卫的 5414e73 快照二进制**：

```
ctl  同一份派生 deck × 快照 hstar_orig   rc=0   1.flavia.res = 1 798 B   无 severe
```

**它无声地跑通了**，一边读着未赋值的 `natural_thickness` 一边写出结果——
这正是 PD-5 描述的陷阱在真实二进制上的一次演示。所以 C2 的拒绝确实由守卫产生。

### C1 的作用域，如实说明

`goodman_evolution` 属于**本仓库之外**的策展算例库，因此 C1 在 deck 不存在时
**打印 SKIP 并点名路径**，不静默、也不计为通过。C2 与 C3 是自足的。

### 一处必须说清的不覆盖

`mini_goodman` 在本轮之后**仍然 `rc=174`**。它崩在更早的 `Elements.f90:3368`
（`elcod` 第二维越界，算例自身缺陷，已登记为不予修复），**与这两条守卫无关**。
守卫不声称覆盖它。

## 8.3 本阶段对两条债务的效果

| | 状态 |
|---|---|
| **PD-5** | **关闭（陷阱已封闭）**。`igap0/=99` 的接触 deck 不再读未赋值内存，而是带诊断停机。**注意口径**：关闭的是「安静出错」这件事，**不是**「非 99 路径的自然厚度语义已确定」——那仍然未知，只是现在会被拒绝而不是被猜。 |
| **PD-4** | **保持 OPEN**。SIGSEGV 变成了点名拒绝，**但真实接触路径仍未恢复**：语料里唯一形状合格的圆柱接触算例的 `.mat` 仍缺 `uniax_cohes` / `frict_angle`。按裁定，PD-4 要等真实完整 deck 并恢复可验收运行才关。 |

## 8.4 本域到此停止

按裁定，接触与界面域在本阶段之后**停止扩能力**，等待真实完整接触 deck
或明确的参数来源。本阶段**没有**产生任何接触能力，也**没有**产生可冻结的接触参考。
