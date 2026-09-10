# M2-01：检查点选址说明（static_2d 路径）

- 日期：2026-09-07
- 范围：`legacy/yl` 上 static_2d 路径（cooks_membrane、lame_cylinder 两例 golden）的四个检查点 `model_ready`、`phase_ready(1)`、`increment_ready(1,1)`、`restart_ready`；本文只做选址与说明，不改 `legacy/yl`，不写序列化代码（M2-02）
- 配套：`docs/m2/state-field-map.toml`（权威机器可读映射）、`tools/yl_state_map.py check`（锚点 hash 与覆盖校验）、`docs/m1/reader-inventory.toml`（reader id 来源）
- 行号：全部经 `sed -n` / `awk` 按物理行号逐条核对（源码含非 UTF-8 字节，不能用普通编辑器行号）；引用形式 `文件:行`，语句原文见各表


> **M2-02 插桩后的行号（2026-09-07）**：`legacy/yl/Fem.f90` 第 10 行加了 `use yl_state_serializer`，三个锚点各加一行 `if (yl_dump_enabled) call yl_state_dump(...)`，因此本文所有 `Fem.f90:N` 已按 +1/+2/+3 更新为插桩后的行号，与 `docs/m2/state-field-map.toml` 的 `[[checkpoint]].site`（1909 / 3603 / 3657）一致。锚点语句文本与 12 位 hash 未变。其他文件（`Solver.f90`、`Global.f90`、`Prescrib.f90` 等）未插桩，行号不变。

## 1. 目的与范围

检查点是 M2-02 序列化器插桩的位置，也是 M2-03 两例状态证据的比较单位。docs/05 的硬规则是：检查点必须位于消费者使用参数之前，但不得为了观测而提前执行原来属于阶段内的计算或分配。因此每个锚点都落在一条已有语句的边界上，位于"最后一个已执行 reader"之后、"第一个消费者"之前，中间不搬动任何语句。

锚点只在下列守卫值下有效，两例 golden deck 全部满足；任一值偏离，控制流就离开本路径，锚点与死代码判定同时失效：

| 守卫 | 值 | 来源（deck / reader） | 决定的分支 |
|---|---|---|---|
| `restart` | 0 | `inp` 第 2 行 / INP.FEM90.run_control（`Fem.f90:99`） | `Fem.f90:277` 走 `lblks=0, lincs=0`（`:278-280`）；`:283 resta_read_write(1)` 不执行 |
| `nblks` / `runblks` | 1 | `.glb` NBLKS 列 / GLB.global_data.init_and_blocks | 块循环 `:1683 do iblks=lblks+1,runblks` 只跑一次 |
| `type_nl` | 5 | `.glb` TYPE_NL 列 / GLB.global_data.problem_type | `algort` `Fem.f90:15454`：仅 iiter=1 置 `kresl=1` |
| `nincs` | 1 | `.man` 第 2 行 / MAN.STATIC_U.nincs（`:3594`） | 增量循环 `:3622` 只跑一次 |
| `nstep`, `inc_step` | 1, 1 | `.man` 第 3 行 / MAN.STATIC_U.increment_control（`:3625`） | 步循环 `:3656` 只跑一次 |
| `cwater`, `Qstatic` | 0, 0 | 同上（第 3 行末两项） | `:3633-3638`、`:3641-3650` 不执行 |
| `ngaps` | 0 | GLB.contact_point_to_point.contact_control（`Global.f90:3469`，empty_section） | `:3601` 不分配 `tofor0`；`:3691-3692` 不执行 |
| `nrcsteel` | 0 | GLB.link_concrete_and_steel.rc_steel_count（`Global.f90:4681`） | 同上 |
| `type_problem`, `type_solver` | `Q`, `PROFILE` | `.glb` TYPE_PROBLEM/TYPE_SOLVER | `:1918` 进入 `static_U`（`:1938`）；`solve` 走 PROFILE 分支 |
| `relis`, `ADINA` | 0, 0 | `inp` / INP.FEM90.run_control | `:1920-1922` 不走 `STATIC_U_reli`/`static_rigid_reli`；`:1900-1902` 不 cycle/stop |
| `block_stab`, `ebody` | 0, 0 | `.glb` / GLB.global_data.init_and_blocks（`Global.f90:762`） | `:1897` 调 `contact_pair_process`；`:1920-1924` 不走 rigid 分支；`Prescrib.f90:161` 不执行 |
| `nbackf` | 0 | 同上 | `:223` 不分配 `result_zero_g/e`；`:1931` 不走 `back_analysis` |
| `ninit`, `uinitial(1)` | 0, 0 | 同上 / GLB.global_data.uinitial（`Global.f90:1093`） | `:1705` 不调 `read_initial`；`:1707` 不清 `result_zero`；`stab_initialize` `:2347` 不 stop |
| `nlayer`, `state_change`, `Bparameter` | 0, 0, 0 | `.glb` / GLB.global_data.problem_type（`Global.f90:789`） | `:1913` 不调 `nonzero_stiff_pcg`；`Prescrib.f90:64` 走 appear 分支；`:1650`、`:3588`、`Stiff.f90:99` 不 rewind / 不取 `xvalue` |
| `nlinks`, `ntrans` | 0, 0 | `.glb` init_and_blocks / transform_and_mif | `totv_to_eq` 无 link 循环；`.pre` 无 frecoord 记录（`Prescrib.f90:243`） |
| `stab_matde` | 99999 | `.glb` / GLB.global_data.sizes_and_switches（`Global.f90:694`） | `:2441`/`:3030`/`:3661`/`:4869` 的 `if(iblks>=stab_matde)call stab_initialize` 为**假**（`iblks<=nblks=1`）：`stab_initialize` **从不执行**。99999 是**禁用哨兵**，不是零 |
| `tfixvar`, `nextr`（每个 .pre 集） | 0, 0 | `.pre` 集头 / PRE.prescrib_set.set_header（`Prescrib.f90:220`） | `iffix=tfixvar+1=1`（`:258`）；`:261` 不读外推记录 |

### 1.1 `stab_matde` 一行的订正（2026-09-10）

本表初稿把 `stab_matde` 记作 **0**，并由此推出「`iblks>=stab_matde` 为真 → 每步调
`stab_initialize` → 它清零 `result_zero` 与 `element%field(1)%gpvar0/gpvar`」。**值错了，
结论跟着反了**：两个 golden deck 的 `.glb` 记录 2 第 15 项都是 **99999**，冻结基线
`control.glb.stab_matde` 也是 99999，因此该分支在本路径上**恒假**，`stab_initialize`
**一次都没跑**。映射表已于 2026-09-08 订正（`state-field-map.toml` 该行 note，提交
`0646de3`/`a8d4646`），本表直到此刻才跟上——**这正是「同一事实记在两处、只订正了一处」的
复发形态**，已计入 `docs/04-quality-gates.md` 的缺陷表。

被这条错误结论顶替掉的两个真实成因，本次一并查明并记在这里，以免「谁把它们清零的」
继续悬空（M2 验收矩阵判据 5 把它列为未答问题）：

- **`result_zero` 在 `model_ready` 处为零**：由 startup 的分配即清零造成——`Fem.f90:219`
  与 `:243-244`（见 §2 调用序表同一行）。与 `stab_initialize` 无关。
- **`element%field(1)%gpvar0` / `gpvar` 为零**：由 `modf_element_lib`（`Fem.f90:193` 调用，
  仍在 startup）在分配点旁边显式清零——`Fem.f90:11859-11860` 分配、`:11881-11882` 赋 0。
  与 `stab_initialize` 无关。

**订正不改变任何锚点位置**：这四个 `iblks>=stab_matde` 判断全部在三个锚点之后或在与锚点
无关的分支里。改变的是「本路径上还有哪些代码在跑」这一事实本身。

**支持条件也随之改写**：可支持的前提是 `stab_matde > nblks`（禁用），**不是**
`stab_matde == 0`。`src/adapter/yl_adapter_model.f90:401` 的闸门按**关系**而非常量写，
原因即此。

### 1.2 本表由门禁核对，不再靠人读

`tools/yl_guard_check.py` 把上表逐行解析出来，经映射表的 `legacy_symbol` 解析到冻结基线的
快照字段，在两例上逐值比对。它有三种判决，第三种是关键：

- `CONFIRMED`——在导出面上且与冻结基线一致（现 **22** 个守卫值）；
- `MISMATCH`——在导出面上且**不一致**，退出码 1（`stab_matde` 那一行在订正前正是这样被机械
  抓到的，与矩阵的人工发现独立吻合）；
- `NOT_ON_FACE`——**不在任何检查点的导出面上，本工具无法确认**（现 5 个：`cwater`、`ngaps`、
  `nrcsteel`、`tfixvar`、`nextr`）。这一类**每次都逐名打印**。一个确认不了的守卫必须持续可见：
  在这里保持沉默读起来与「已确认」完全一样，而本表那一行错值正是这样活下来的。

规则：**决定路径的守卫值一律 `compare="exact"`**（不用 `ignore`），owner 仍为 `not_migrated` 并保留 `reason`；映射表中这些行的 note 以 "pinned guard" 开头。守卫值一旦偏离，比较立刻失败并指出原因，而不是静默地比较另一条路径上的状态。

## 2. 检查点选址表

`process_analysis`（`Fem.f90`）上与选址有关的调用序（全部核实）：

| 阶段 | 位点 | 语句 / 发生的事 |
|---|---|---|
| startup | `Fem.f90:117` | `call global_data`：`.glb/.cor/.ele/.nrt/.ftr` reader；`set_elem_dofs`（`Global.f90:1483`）建 `nodfn/ntotv/element%ldofs`；`trans` 分配并清零（`Global.f90:1488-1489`） |
| startup | `Fem.f90:191` | `call material_set`（`.mat`） |
| startup | `Fem.f90:219`, `:243-244` | `result_zero`、`tofor/stfor/toforl/toform` 分配并清零 |
| startup | `Fem.f90:246` | `allocate(delitfi(ntotv),deltafi(ntotv))`，**未初始化** |
| startup | `Fem.f90:260` | `ice0=0` |
| block 1 | `Fem.f90:1682` | `call external_load_1`（`.loa` 曲线 → `tcurves`） |
| block 1 | `Fem.f90:1716-1717` | `appear(igroup)=appear_process(igroup,iblks)`；`group(igroup)%matno=matno_process(igroup,iblks)` |
| block 1 | `Fem.f90:1873` | `call prescrib_set`（`.pre` → `iffix/fixed/prescrib`） |
| block 1 | `Fem.f90:1896` | `call external_load_2`（`.loa` 重力块 → `gravy/factg/factf/tcurvegravity`） |
| block 1 | `Fem.f90:1899` | `call boundt`（`.tem`，计数全 0） |
| block 1 | `Fem.f90:1903-1904` | `line_load_block(iblks)=lineload`、`line_temp_block(iblks)=linet`（游标簿记） |
| block 1 | `Fem.f90:1909-1909` | `operation='SET'`；`call solve` → PROFILE SET（`Solver.f90:6820`）：读 `.sol`（`:6829-6832`），`totv_to_eq`（`:6834`，`Solver.f90:9027`），`iseq`（`:6838-7227`），`Stiff_length=Iseq(neq)`（`:7229`），`global_stiff1` 分配清零（`:7235-7236`），`rvector` 分配（`:7237`，未初始化） |
| block 1 | `Fem.f90:1918` | `call modf_time_order`（`order_time_mdofn=0` 时无操作） |
| block 1 | `Fem.f90:1939` | `call static_U` |

选址结果：

| 检查点 | 插在……之后 | 插在……之前 | 之前最后一个 reader | 之后第一个消费者 |
|---|---|---|---|---|
| `model_ready` | `Fem.f90:1907` `write(chkunit,*)'time(solve): ', char_time` | `Fem.f90:1909` `operation='SET'` | TEM.boundt.pipe_count（经 `:1899 call boundt`） | PROFILE SET：`Solver.f90:6829` `Read (solveunit,*,…) text`；随后 `:6834 call totv_to_eq` 消费 `iffix`、`trans%nintf`、`nodfn`、`nlinks` |
| `phase_ready(1)` | `Fem.f90:3598` `call diag_flush_stage()`（nincs 守卫 flush） | `Fem.f90:3603` `if(ngaps/=0.or.nrcsteel/=0)allocate(tofor0(ntotv))` | MAN.STATIC_U.nincs（`:3594`） | `Fem.f90:3624` `do iincs=lincs+1,nincs`（`:3601-3617` 在本路径为死代码，见 §4） |
| `increment_ready(1,1)` | `Fem.f90:3654` `print *,'cwater,Qstatic=',cwater,Qstatic` | `Fem.f90:3657` `ttime0=ttime` | MAN.STATIC_U.tolerances（`:3631`） | `:3654-3655`（`ttime0/trstep0`）、`:3663-3664`（`xtime/ttime`）、`:3666 dfact_time_curve`、`:3667 modf_var_prescribed`（→ `fixed`）、`:3672 gravity`（→ `element%field(1)%rload`）、`:3678 force_external`（→ `tofor`）、`:3711 algort`（→ `kresl`）、`:3733 stiff_u`、`:3749 estif_assemble` |
| `restart_ready` | — | — | 无 | 无：`covered=false`，`restart=0`，`Fem.f90:283 call resta_read_write(1)` 位于 `:277 if (restart==0)` 的 else 分支，本路径不执行 |

检查点之间被消费的量（决定哪些字段必须在前一个检查点登记）：

- `model_ready` → `phase_ready(1)`：`.sol` 控制字（`iafile,icond,ipdchk,ising`，`Solver.f90:6831`，本身只在 `phase_ready(1)` 可观测）；`iffix`、`trans%nintf`、`nodfn`、`nlinks`（→ `totveq`、`neq`）；`appear`、`group%list`、`element%ldofs`、`totveq`（→ `iseq`、`Stiff_length`）；`nonsym`、`nlayer`；`.man` 标题与 `nincs`（`:3592-3594`）。
- `phase_ready(1)` → `increment_ready(1,1)`：只有两条 `.man` 增量记录：`miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic`（`:3625`）与 `toler_force,toler_var(1:mdofn)`（`:3631`）。

## 3. 与需求措辞的偏离

requirements.md 写的是"model_ready = 首次 `global_stif_profile`/`stiff_u` 之前"。字面读法不能成立：

- 首个 `call stiff_u` 在 `Fem.f90:3736`，处于 `do iiter=1,miter`（`:3702`）迭代循环内；它在 `.man` 的阶段头 reader（`:3592-3594`）与增量 reader（`:3625-3631`）**之后**。字面放置会让 `model_ready` 排到 `phase_ready(1)` 与 `increment_ready(1,1)` 之后，检查点顺序倒置。
- `global_stif_profile` 从不被 `process_analysis` 直接调用；它由 `estif_assemble` 内部到达（`Stiff.f90:3425`、`:3783`），而 `call estif_assemble` 在 `Fem.f90:3752`，同样位于迭代循环内。
- 在 `stiff_u` 之前、`.man` reader 之后的任何位置都已经执行过 PROFILE SET（`:1909`），即方程编号、profile 指针与刚度数组已经建立。此时观测到的是"求解器结构建立之后的模型"，不再是模型装载完成时的状态。

采用的读法是"**求解器结构建立之前**"：`model_ready` 放在 `:1908 operation='SET'` 之前。这是最后一个模型级 reader（`boundt`，`:1899`）之后、第一个消费模型级状态的例程（PROFILE SET 的 `totv_to_eq`）之前的唯一语句边界；`:1903-1907` 只是游标簿记与计时打印。需求文本应回写为此表述。

## 4. 死代码区间

两个区间夹在锚点与其第一个消费者之间，本路径下不执行，因此不影响锚点位置。这里只陈述事实，不搬动、不预计算任何语句（docs/05 规则）。

| 区间 | 语句 | 守卫 | 本路径值 | 结论 |
|---|---|---|---|---|
| `Fem.f90:3603` | `if(ngaps/=0.or.nrcsteel/=0)allocate(tofor0(ntotv))` | `ngaps`、`nrcsteel` | 0、0 | 不分配 |
| `Fem.f90:3605-3617` | `do iincs=1,lincs` 内重读已完成增量的 `.man` 记录（含 `cwater`/`Qstatic` 子块） | `lincs` | 0（`Fem.f90:280`，因 `restart=0`） | 循环体零次 |
| `Fem.f90:3635-3638` | `if(cwater/=0.and.delgroup>0)` 分配并读 `coef_water` | `cwater` | 0（`.man` 第 3 行第 8 项） | 不执行 |
| `Fem.f90:3643-3650` | `if(Qstatic/=0)` 分配 `qstatic_force` 并读 5 条记录 | `Qstatic` | 0（`.man` 第 3 行第 9 项） | 不执行 |

`:3619 xtime=0.0` 与 `:3652` 的 `print` 是区间内仅有的两条实际执行语句，均不消费映射表登记的字段。

## 5. 读后被改写的量

下列量在 reader 读入后、检查点到达前已被覆盖。映射表登记的是**变换后**的内存值（`source="derived:…"`），modern 侧比较时必须做同样的变换，否则必然不匹配。

| 量 | deck 中的值 | 变换 | 位点 | 检查点处的值 |
|---|---|---|---|---|
| `lmdofn(1:mdofn)` | 0/1 开关（`.glb` MDOFN 块第 2 行） | 非零项改写为压缩序号 `cdofn`，同时填 `lcdofn(cdofn)=idofn` | `Global.f90:1119-1125`（赋值语句在 `:1123`） | 两例：`(1,2)` |
| `group(igroup)%matno` | `.glb` 组头的 matno | 每块由 `matno_process(igroup,iblks)` 覆盖 | `Fem.f90:1717` | `matno_process(:,1)` |
| `nodfn(idofn,ipoin)` | 无（按组 `listdof_f` 置 1） | 1 → 全局 totv 号 | `Global.f90:2096`（清零）、`:2147-2156`（编号）、`:2161-2199`（`element%ldofs`） | 1..ntotv 的编号 |
| `appear(igroup)` | `.glb` 组头 | 每块由 `appear_process(igroup,iblks)` 覆盖，退出组置 −1 | `Fem.f90:1716-1720` | `appear_process(:,1)` |
| `iffix(itotv)` | 无 | 初值 5（未激活），激活组自由度置 0，约束自由度置 `tfixvar+1` | `Prescrib.f90:62`、`:72`、`:258` | 0 / 1 / 5 |
| `appear_process(igroup,0)` | 无 | 第 0 列（初始状态）清零 | `Global.f90:964`（分配 `0:nblks`）、`:968` | 0；`Fem.f90:1719-1720` 以 `iblks-1=0` 消费，故形状登记为 `["ngroup","nblks1"]` |

其中两项在检查点处**原值已不可观测**，映射表用 `reconstruct` 字段给出 M2-02 的重建配方，序列化器输出重建值：

| 字段 | 原值 | 重建配方 | 依据 |
|---|---|---|---|
| `derived.dof.active_flags` | `.glb` 的 0/1 开关 | `merge(1, 0, lmdofn(idofn) /= 0)` | `Global.f90:1119-1125` 只改写非零项，零/非零性保留 |
| `sections.material_header` | 组头 matno | `element(group(igroup)%list(1))%matno` | `Elements.f90:1083` 是 `element%matno` 的唯一赋值点，之后不再改写；`group%matno` 在 `Fem.f90:1717` 被覆盖 |

依赖方向据此改为无环：reader `GLB.global_data.group_header` → `mesh.elements.material`（`element%matno`）→ `sections.material_header`（重建）→ `sections.material`（`matno_process` 覆盖后的内存值）。

## 6. 未初始化与指针清单（ignore 规则）

以下对象在某个检查点到达时尚无确定值。序列化器必须**按分量白名单**输出，永远不整体 dump 派生类型；未初始化分量、未关联指针一律 `compare="ignore"` 并写明理由。

| 对象 | 分配 / 定义位点 | 首次赋值 | 处理 |
|---|---|---|---|
| `delitfi`, `deltafi` | `Fem.f90:246` 仅分配 | `deltafi=0.0` `:3693`；`delitfi=0.0` `:3716` | 三个检查点均 ignore |
| `rvector(neq)` | `Solver.f90:7237` 仅分配 | 求解时 | `phase_ready(1)` 起 ignore |
| `element(ielem)%field(1)%tload/eload/rload` | `Global.f90:1321-1323` 仅分配 | `rload=0.0` 在 `Load.f90:1237`（`gravity` 内，`:3672` 之后） | 三个检查点均 ignore |
| `prescrib(k)%ifixvar0` | `Prescrib.f90:274` 拷贝局部变量 `ifixvar0`（`:45` 声明，例程内从未赋值） | 无 | ignore |
| `prescrib(k)%rdofix, bfrecoord, gamaw, mfixset` | 本路径无赋值 | 无 | ignore |
| `group%btime, educ, ditime_1, ivcoh, ivfri, ngvar, kinit_g, cgroup, point_direct` | 本路径无 reader | 无 | ignore |
| `toler_var(1:mdofn)` | 模块变量 | `Fem.f90:3633` | `model_ready`、`phase_ready(1)` 不登记；`increment_ready(1,1)` exact |
| `lcdofn(cdofn+1:mdofn)` | `Global.f90:954` 分配 `mdofn` | 仅 `1:cdofn` 在 `:1124` 赋值 | 形状登记 `["mdofn"]`，exact 只比 `1:cdofn`（序列化器截断；两例 cdofn=mdofn，截断为空） |
| `element%egaus(2)%cartd` | 不分配：`Elements.f90:1232` 只对非 `mass` 规则分配 | 无 | 不登记；`egaus(2)%gpcod/djacb`（16 点 mass 规则）登记为 ignore 行 `runtime.gauss.*_mass`，因 q4 `order_intrules=(/1,1/)`（`:377`）使本路径所有消费者都取 `egaus(1)` |

Gauss 字段 `runtime.gauss.djacb/gpcod/cartd` 只登记 `egaus(1)`（ikg=1，4 点刚度规则）；`djacb` 的存储值是 `djacb*weigp`（`Elements.f90:1363`），不是裸行列式。
| 未关联指针：`props%mechanical%fluid/heat/geometry`、`props%…%solid%scycl`、`tcurves%a0sin…`（LINEAR 曲线）、`element%estif/alfa/stres0/gmatx`、`trans%listf/rintf`、`prescrib%listep/value_ext` | 类型定义 | 本路径不关联 | 序列化前 `associated()` / `allocated()` 判定；对未关联指针取值视为 fault |

字符分量（`probn` char(200)、`type_problem` char(50)、`group%name`、`props%name`）按 `trim()` 后比较或哈希，避免填充字节干扰。

## 7. S03 陷阱：`fixed` 与 `dfact` 在 `increment_ready(1,1)` 仍为零

- `fixed` 在 `prescrib_set` 中清零（`Prescrib.f90:63`），真正赋值 `fixed(ldofix)=dfact*prescrib(idofix)%vdofix` 在 `modf_var_prescribed`（`Fem.f90:12353`），由 `:3667` 调用。
- `tcurves(i)%dfact` 在 `external_load_1` 中置 0（`Load.f90:166`），由 `:3666 dfact_time_curve(ttime)` 才求值。

两者都在 `increment_ready(1,1)` 锚点（`:3652/:3654`）之后。若 S03 的"约束扰动"直接改 `fixed` 或"荷载扰动"直接看 `dfact`，三个检查点都观测不到差异。映射表 `[[perturbation]]` 因此钉住以下目标，全部 `compare="exact"`：

| 扰动 | 字段 | legacy 符号 | 消费位点 |
|---|---|---|---|
| 材料 | `materials.E` | `props(imat)%mechanical%solid%e` | `Stiff.f90:102`（`stiff_u`） |
| 约束 | `steps0.boundary.value` / `.nodes` | `prescrib(k)%vdofix` / `%nodfix` | `Fem.f90:12353` |

P-BC 的 `index` 写成按集名的形式 `[set=1]`（与 `index_by = steps[0].boundary[].name` 一致），而不是位置下标 `[1]`：prescrib 记录按"集 × 节点"顺序生成（`Prescrib.f90:216,253`），lame_cylinder 上记录顺序与 deck 中集的顺序不一致，位置下标在两例上不指向同一条记录。
| 荷载 | `steps0.load.gravity.magnitude` | `applied_load.gravy`、`factg`、`tcurvegravity` | `Load.f90:1268`、`:1200`；`Fem.f90:13422` |

`fixed`、`dfact` 本身仍登记为 RuntimeState、exact 全零，用于证明"检查点处尚未装载"这一事实本身是确定的（风险表 R24）。

## 8. M1 注册表说明：`.pre/.loa/.tem` 的 phase 标签

`docs/m1/reader-inventory.toml` 把 PRE.prescrib_set.*、LOA.external_load_1.*、LOA.external_load_2.*、TEM.boundt.* 标为 `phase = "startup"`，但它们实际在块循环 1 内执行：`prescrib_set` `Fem.f90:1873`、`external_load_2` `:1896`、`boundt` `:1899`（`external_load_1` 在 `:1682`，紧邻 `:1683` 循环入口之前）。`nblks=1` 时块循环只跑一次，标签与执行顺序无冲突，`model_ready` 锚点不受影响。`nblks>1` 时这些 reader 每块执行一次，`model_ready` 应随 `iblks` 变为每块一个。本任务不改 M1 注册表（`yl_io_inventory.py check` 保持 PASS 的前提），仅在此登记。

## 9. Q1–Q3 结论

- **Q1（dof 编号与 profile 是否进入 model_ready）**：拆开处理。`nodfn`、`ntotv`、`element%ldofs` 在 startup 建立（`Global.f90:1483`）且在 `model_ready` 之前已被 `prescrib_set` 消费（`Prescrib.f90:71-72`、`:255`），因此在 `model_ready` 登记为 `owner="RuntimeState"`、`compare="hash"`；所有以 `ntotv` 为下标的数组（`iffix`、`fixed`、`result_zero`）经 `nodfn` 重键为 `(node_id, dof_id) → value` 序列化，使 ProblemState 比较不依赖编号。`totveq`、`neq`、`iseq`、`Stiff_length` 在 `:1909` 之前不存在，只在 `phase_ready(1)` 登记（数组 hash，标量 exact）；不为观测它们而提前执行 PROFILE SET。
- **Q2（73 条 `title_skip` 记录是否隐含状态）**：无值状态。标题记录读入共享 scratch `global_var.text`（`Global.f90:44`）后从不消费；唯一隐含状态是记录**顺序**，已由 M1 注册表的 `seq`/`cursor_op` 固定。`.ele` 尾列组号从不读取（`Elements.f90:1087` 只读 `i0,lnods`），elset 成员关系按组序派生。不为 `title_skip` 登记结构字段。
- **Q3（restart_ready）**：登记为 `covered=false`、零字段，理由 `restart=0`；`Fem.f90:283 resta_read_write(1)` 与 `.rtt/.stf` 单元不在路径上。`check` 只允许 `covered=false` 的检查点零字段。

## 10. 后续（M2-02）

- 锚点用与 M1 相同的 `site + 12 位 hash` 登记在 `state-field-map.toml` 的 `[[checkpoint]]`；任何对 `legacy/yl` 的插桩编辑（哪怕只加一行 `call`）都会使 `Fem.f90` 行号漂移，必须先重定位三个 covered 锚点，再重跑 `tools/yl_state_map.py check` 到 PASS，随后才能重建。
- 插桩语句必须放在本文 §2 表中"插在……之后 / 之前"的两条语句之间，不得移动 `:3601-3617`、`:3633-3650` 的死代码，也不得为了在 `model_ready` 观测 `neq/iseq` 而提前调用 `solve`。
- 序列化器按 §6 白名单输出分量；§5 的变换值直接输出内存值，不反推 deck 值。
- `check` 规则 15（锚点前不得出现 `call <first_consumer>`）只扫描锚点所在例程：`model_ready` 在 `process_analysis` 内（从例程起点到 `:1908`），`phase_ready(1)` 与 `increment_ready(1,1)` 在 `STATIC_U` 内（从 `:3560` 附近的例程起点到各自锚点）。因此 `phase_ready(1)` 的 `first_consumer=STATIC_U` 不会被 `:1938 call static_U` 误判；跨例程的先后关系由 §2 的调用序表人工保证。
