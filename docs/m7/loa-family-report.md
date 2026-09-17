# `.loa` 家族现代输入契约与覆盖率报告

状态：**Phase 2 完成（契约 + 校验器 + 反例）**。Phase 3（ProblemState 映射与逐位回归）未开始。
契约正文见 `docs/m5/authoring-contract.md` §2.1 与 §8；本文件只做**覆盖率与口径**的记账。

## 1. 本轮确立了什么，没确立什么

**确立**：

- `.loa` 的 52 处读取站点已逐条归类，每一条要么进入首批语义对象，要么被显式挂起，
  要么被声明为 legacy-only（§3 的矩阵，没有「未分类」这一栏）。
- 四类语义对象进入统一 authoring 契约：幅值 `[[amplitude]]`（linear / waterlevel）、
  面 `[[surface]]`（显式边表）、荷载对象数组 `[[step.load]]`（gravity / pressure）、
  以及把 legacy 的「按 block 重复的荷载段」展平成 `[[step]]` 序列的映射公式。
- 校验器对上述对象的**结构性非法输入**在解析/校验阶段直接拦截，共 12 条反例逐条通过
  （§4），其中 10 条跑在 `cases/authoring/wall_reservoir` 上。
- 四个 golden 算例在 `[step.load]` 表 → `[[step.load]]` 对象数组的重构前后**逐位一致**。

**不确立**：

- 面压力**没有**被搬到 ProblemState，也没有任何算例用现代输入跑出过水压结果。
  `yl_authoring_map` 的 `executable_shape` 明确拒绝它，退出码 3。
- 多分析步**没有**被执行过。契约能描述 `count(step) > 1`，这个 build 拒绝它。
- `wall_reservoir` 是**校验器夹具**，不是 golden 算例：它没有网格，也没有冻结参考。
- 「引用了不存在的节点号」**没有**被检查。校验层不打开网格文件，见 §4 的说明。

## 2. legacy 侧的形态，一句话

`.loa` 是一条读取流水线，不是一组对象：

```
曲线表 → 集中力 → 边定义 →  [ 边荷载 → 体力 → 每组重力曲线号 → 梁荷载 → 板荷载 ] × nblks
```

方括号里的整段**按 block 重复**。这是这个家族里唯一需要架构判断的地方，答复是
`docs/m5/authoring-contract.md` §2.1 冻结的那条公式：

```
legacy nblks = count(step)          legacy nstep = step.controls.substeps
```

## 3. 52 处读取站点的覆盖映射矩阵

行号是 `legacy/yl/Load.f90`。`covered` = 首批语义对象已表达；`suspended` = 家族已识别、
本轮不做；`legacy-only` = 按 ADR-0008 §3 永远由 legacy 读取，现代输入不表达。

| 家族 | 行号 | 读取的内容 | 现代表达 | 状态 |
|---|---|---|---|---|
| B 幅值 | 136, 143, 145 | 标题行、`ntcurve` | `[[amplitude]]` 的条数 | covered |
| B 幅值 | 156 | `ntime type_curve nstoch_curve nline` | `type` + `points` 的长度 | covered（`nstoch_curve` / `nline` 不表达，见下） |
| B 幅值 | 220, 231 | LINEAR：时间记录、系数记录（**列优先**） | `points = [[t, f], ...]` | covered |
| B 幅值 | 192 | WATERLEVEL：`ntime` 行 `(t, f)`（**行优先**） | 同上，线格式差异由适配器吸收 | covered |
| B 幅值 | 171 | `order_stoch_parameter`（随机曲线） | — | legacy-only |
| B 幅值 | 178 | HARMONIC | — | legacy-only |
| B 幅值 | 183, 187, 188 | FOURIERSERIES | — | legacy-only |
| B 幅值 | 196, 224 | SEISMIC | — | legacy-only |
| B 幅值 | 200 | EXTRAPOLATION | — | legacy-only |
| B 幅值 | 206, 211 | ARCLENGTH（含 `nalgo==2` 的控制自由度） | — | legacy-only |
| C 集中力 | 240, 242, 250, 260, 264, 288, 291 | `nplgroup kpload`、每组 `pxyz` 与节点表 | — | **suspended** |
| C 集中力 | 305, 306, 310, 311 | 第二种写法（`corlist`） | — | **suspended** |
| D 边定义 | 364, 366, 374, 375, 383 | `nedge`、分块头 `sedge nnode index vdimn`、每行 `i0 lnode(:) aelem` | `[[surface]] edges = [[n1, n2, element], ...]` | covered（2-D `nnode=2` 一档） |
| E 面荷载 | 750, 752, 755 | 标题、`edge_load_group delgroup` | `[[step.load]] type="pressure"` 的条数 | covered |
| E 面荷载 | 767 | `begin_edge end_edge itcurve water code_load` | `surface` + `amplitude` + `distribution.axis` | covered（`water=2`、`code_load=0` 一档） |
| E 面荷载 | 772 | `cor0 cor1 p0 p1 fact` | `distribution.{at,value,scale}` | covered |
| E 面荷载 | 782 | `code_load/=0` 的第二段分布（背水面） | — | legacy-only |
| E 面荷载 | 879 | 逐节点显式压力 | — | legacy-only |
| F 重力 | 911, 913 | 标题、`gravy factg(:) factf(:)` | `type="gravity"` 的 `magnitude` / `direction` | covered（`factf` 见下） |
| F 重力 | 920, 922 | `tcurvegravity(1:ngroup)` | 若干 gravity 对象的 `apply_to` + `amplitude` | covered |
| G 梁荷载 | 932, 934, 947 | `nbeamload`、每条 `aelem itcurve gloc(:) cc` | — | legacy-only |
| H 板荷载 | 1013, 1015, 1026, 1027, 1029 | `nplateload`、每组 `igroup itcurve water` 与分布 | — | legacy-only |

**合计 52 = covered 21 + suspended 11 + legacy-only 20。**

三处「covered 但不完整」必须写清楚，否则这张表会被读成比事实更强的东西：

1. **156 的 `nstoch_curve` / `nline`**：前者是随机曲线的参数个数，后者是这条曲线在文件里
   占几行——一个属于未进入白名单的能力，一个是**行计数**，即读取过程的记账。两者都不
   进入 authoring；`nline` 尤其不该进入，它正是「读取顺序」本身。
2. **913 的 `factf`**：`factg` 是重力方向，`factf` 是另一组方向系数（浮力/渗流侧），
   本轮只表达 `factg`。适配器按 legacy 的默认写回 `factf`，这条**未经反例确认**。
3. **767 的 `water`**：legacy 的 `abs(water)` 选坐标轴、符号选深度增加的方向。真实 deck 里
   只见到 `water = 2`（沿 y、向下加深）与 `water = 3`（3-D）。白名单只收 `axis = "y"`，
   负号一档没有实现，也没有反例——**它是 legacy-only，不是 covered**。

## 4. 反例清单（Phase 2 的交付物）

`src/authoring/yl_authoring_test.f90`，`--loa` 模式跑在 `cases/authoring/wall_reservoir`，
其余两条跑在 `lame_cylinder`。每条断言四件事：判决、退出码、错误里点名了键、点名了行。

| # | 反例 | 判决 | 退出码 | 跑在 |
|---|---|---|---|---|
| 1 | 荷载引用未定义的 `[[surface]]` | `DANGLING_REF` | 2 | wall_reservoir |
| 2 | 荷载引用未定义的 `[[amplitude]]` | `DANGLING_REF` | 2 | wall_reservoir |
| 3 | 线性水压 `at = [y0, y0]`（legacy 除以 `y0-y1`） | `INVALID_INPUT` | 2 | wall_reservoir |
| 4 | `at` 与 `value` 长度不等 | `INVALID_INPUT` | 2 | wall_reservoir |
| 5 | 幅值时间点非严格递增 | `INVALID_INPUT` | 2 | wall_reservoir |
| 6 | 边表某行不是 `[n1, n2, element]` | `INVALID_INPUT` | 2 | wall_reservoir |
| 7 | 边表里的编号 ≤ 0 | `INVALID_INPUT` | 2 | wall_reservoir |
| 8 | `surface.kind` 不在白名单 | `UNSUPPORTED` | 3 | wall_reservoir |
| 9 | `pressure` 缺 `distribution.scale` | `MISSING_FIELD` | 2 | wall_reservoir |
| 10 | `pressure` 上写了 `magnitude`（属于 gravity） | `INVALID_INPUT` | 2 | wall_reservoir |
| 11 | `direction` 模长为 0 | `INVALID_INPUT` | 2 | lame_cylinder |
| 12 | `apply_to` 指向未定义的 `[[elset]]` | `DANGLING_REF` | 2 | lame_cylinder |

**「引用不存在的节点」不在这张表里，这是有意的。** 校验层从不打开网格文件；
声称检查了节点存在性，是比不检查更危险的半真话。文件本身能知道的是**形状与符号**
（第 6、7 条），节点号与单元号是否真的存在属于映射层——那里 `.cor`/`.ele` 在手，
和已有的单元数不符检查（`tools/yl_modern_check.py` N3）在同一层。

另有两条拒绝在**映射层**而非校验层，因为它们是关于这个二进制而不是关于输入语言的陈述
（`yl_authoring_map.executable_shape`）：`count(step) /= 1` 与「携带了 pressure 荷载」，
两者都是 `UNSUPPORTED` / 退出码 3。它们的反例属于 Phase 3。

## 5. 本轮暴露的问题

1. **`arr_name` 与 `idx` 长度不一致**（`yl_authoring_toml.f90`）。`.loa` 夹具是第一个用到
   九个 `[[table]]` 名字的文件；只把 `arr_name` 从 8 改到 16，写 `idx(9)` 越界，
   在 `-O2` 下不是诊断而是**挂死**，在 `debug` 剖面下一行报出。两个数组现在由同一个
   `TOML_MAX_ARRAYS` 定长。教训照旧：**并行数组必须由同一个常量定长。**
2. **一条反例在重构后变成空对照**。`[step.load.strength_reduction]` 改名后，
   「写了折减曲线却没有对应 mode」这条反例仍然绿，但它触发的已经是「未知键」，
   不再是那条条件必填规则。按既有纪律，反例改名后要重新确认**它触发的是哪条规则**，
   而不只是确认它还红/还绿。
3. **多行数组仍不被 TOML 子集接受**。一个 30 条边的坝面必须写在一行上（约 330 字符）。
   夹具只有 4 条边，所以本轮不受影响；真实坝面进来之前要处理。登记为 OPEN DEBT。
4. **`adapter` 目标的 `cases/` 守卫在测量错误的东西**。它想证明的是「本目标没有写进
   golden 输入」，实现却是「`git status cases/` 必须为空」——于是任何**在同一个提交里
   合法修改算例**的工作都会被它拒绝，而它对这件事本没有意见。已改为**比较目标运行
   前后的差**——然后在给这道改动写阳性对照时，发现**第一版修正是瞎的**：在一个 deck
   已经是 ` M` 的树上（也就是促成本次修改的那种树），追加一行之后 `git status` 的列表
   逐字不变。最终改为对 `cases/` 下全部文件取内容哈希，并补上阳性对照。
   两件事都值得记：一道会拒绝自己无权评判之事的门禁会先失去可信度、再被绕过；
   而**一道没有阳性对照的修正，和没修一样**——这一版正是被对照当场否掉的。

---

# Phase 3：面荷载 + 多分析步 → ProblemState → solver

状态：**收口**。五个 golden 算例全部由现代输入独立驱动，逐位复现冻结参考：
cooks 1734 值、lame 486、mini_mc 210、slope_srm 600 块 541 200 值、
**wall_reservoir 4 块 552 值**，`max|d| = 0`。

## 1. 算例是量出来的，不是挑出来的

`hstar_jobs` 语料里**每一个**两块 2-D deck 都带施工分期（`APPEAR_PROCESS = 1 0 / 1 1`）——
分期正是这些 deck 之所以有两块的原因。所以分期不是这个算例额外拖进来的负担，
它是多分析步能力的一部分。在这些 deck 里取最小的一个：

`0416_125158_determ_test` → `cases/golden/loads_2d/wall_reservoir`：46 节点、32 单元、
两个单元组（Foundation 20 / Dam 12）、一种材料、4 条边、2 块。第 1 块只有基础在自重下，
第 2 块坝体就位并加上水面 y = 50 的静水压（`water = 2`，`fact = 9810`）。
冻结参考 3 次运行逐字节相同：**4 块 552 值**。

## 2. 复用 legacy，而不是重写它

`Load.f90` 与 `Prescrib.f90` 的四段计算被**提取**为模块级子程序，两条路径调用同一份代码：

| 提取出来的 | 原来在哪 | 谁调用 |
|---|---|---|
| `edge_dofs(tedge)` | `external_load_1` 读取循环内 | legacy 读取路径 + `commit_surface_edges` |
| `edge_geometry()` | `external_load_1` 读完边表之后 | 同上 |
| `edge_load_group_apply(...)` | `external_load_2` 的每组循环 | legacy 读取路径 + `commit_block_state` |
| `prescribe_free_active()` | `prescrib_set` 开头的 iffix 推导 | legacy 读取路径 + `commit_block_state` |
| `edge_cosc` | `external_load_1` 的 `contains` 块 | `edge_geometry`（改名是因为 Stiff.f90 自己有一个 `cosc`）|

**没有写一行同义的数值代码。** 提取是否保行为，由三个算例的 gdb 追踪当场证明：
`cooks_membrane` / `lame_cylinder` / `wall_reservoir` 在提取之后逐位复现各自的冻结参考。

## 3. 多分析步的接缝在 legacy 自己的位置上

legacy 在**每一块**的开头重读 `.pre` 与 `.loa` 尾部（`Fem.f90:1873 / 1896`）。现代侧因此也
必须有一个每块的接缝：`Fem.f90:1721` 加了一行（与 `end do` 同行，文件行数不变）
`if (yl_adapter_mode .and. iblks > 1) call yl_adapter_block_override(iblks)`，
位置在 `appear` 按本块更新**之后**、任何东西消费荷载**之前**。
第 1 块走的仍是改动前那条路径。`yl_adapter_session` 保存已提交的
ProblemState / RuntimeState 供后续块使用。

## 4. 进入 ProblemState 的新对象

`surface_edges[]`（`nodes` / `element` / `element_class` / `projection_axis`）与
`steps[].load.pressure[]`（`first_edge` / `last_edge` / `amplitude` / `distribution_axis` /
`at` / `value` / `scale`），各带 `@off-face` 标记与 map 行。**没有一条直接写 legacy 全局**：
commit 仍是唯一的写入口。`code_load` 故意**不**进 ProblemState——legacy 把它读进一个例程
局部量就丢了，没有全局可供 map 行指认，编造一个会是凭空发明状态。

## 5. 契约新增与移出默认表的两项

`step.active_elsets`（这一步里有哪些单元集）与 `step.reset_state`（这一步是否从零开始）
双双**移出默认表变成必填**——见 `docs/m5/authoring-contract.md` §9。两者都不是表达性字段：
它们就是分期分析要回答的问题。

## 6. 那个 bug，以及它为什么值得写下来

第一次跑通时，第 1 步逐位一致而第 2 步差 260/552 值。**定位过程全部是实测，没有猜**：

1. 两条路径逐项对照，以下**全部逐位相同**：边表、边高斯几何、四条边组装出的 `edload`
   连同 `dfact`、`gpwater` 的五个分布量、`tcurvegravity`、每块的 `appear`、`nelgroup`、
   `ice0`、`uinitial = (0, 1)`、约束自由度。**水压算得一模一样**，所以问题不在面荷载。
2. 分叉的形态很窄：坝体那 16 个节点在第 2 步恰好为 0，且第 2 步的 `retot = |tofor|²`
   与第 1 步**完全相等** —— 第 2 块没有获得任何新荷载。
3. 顺着 `tofor ← element%tload ← ldofs_f` 往回看，唯一没被实测过的一环是自由度冻结。

**根因**：`yl_runtime_build` 里 `dof%fixed_mask` 的推导写着 `problem%steps(1)%activation`
——「一切冻结，然后为**活动**单元集的单元解冻」。它对单步分析恒真；分期分析里，
第 2 块才出现的那一组自由度**永远冻着**，于是位移恒为 0。legacy 没有这个问题，
因为它每块都在 `prescrib_set` 里按当前 `appear` 重新推一遍。

**修法沿用同一条纪律**：不在现代侧再写一遍这条规则，而是把 legacy 的那段循环提取成
`prescribe_free_active()`，两条路径都调用它；被约束的那些自由度再从 mask 重新应用一次
（合法的前提是「各步边界条件必须相同」已经由 `commit_step_invariants` 按名拒绝）。

值得写下来的不是 bug 本身，而是**它在哪儿**：不在新写的面荷载代码里，而在一处
「只对单步为真」的既有推导里。多分析步这个能力真正的代价，是把每一处
`steps(1)` 的写法重新审一遍。

## 7. 门禁口径

新增两条 N3 反例（多步能力使两条旧反例失效，一并退役并写明原因）：
「一步里两个 gravity」与「各步边界条件不同」，都是 `UNSUPPORTED` / 退出码 3。
`cases/manifest.toml` 的 `modern_gate = false` 机制留在原地（当前无算例使用），
它在每次运行时**打印**豁免而不是静默跳过。

五个新增的 `.loa` 读取站点已按 M1-02 流程包装并登记，逐条带实测证据；
`tools/yl_io_trace.sh` 的 `--adapter=off` 修正见 §5 第 4 条的同类问题。

---

# Phase 4：集中力

状态：**收口**。六个 golden 算例全部由现代输入独立驱动，逐位复现冻结参考。
新增 `loads_2d.beam_point_load`：2 块 756 值，`max|d| = 0`。

## 1. 能力差值：只差集中力本身

`hstar_jobs` 里带点荷载的 deck 共 5 个，最小的一个（`0413_164206_1c44582f`）除点荷载之外
**每一项都已经在白名单里**：126 节点、100 单元、一组、一种弹性材料、一块、Q4 / PROFILE /
LOAD / type_nl 5。一块 1.0 × 0.25 m 的板，两个下角支承，顶边中点受 −10 kN。

选它还有一个理由：**它的体力是真的零**（`gravy = 0`，`factg = (0,0)`）。于是整个位移场
完全由集中力决定——**丢掉集中力，答案不是错的，是恒等于零**，这是自洽的运行藏不住的。

## 2. 最小 schema 扩展

```toml
[[step.load]]
type      = "concentrated"
nset      = "top_centre"
value     = [0.0, -10000.0]
amplitude = "constant"
```

三个字段，正好对应 legacy 点荷载组的三个内容；`nudofn` / `npload` 是两个数组的长度，
不是作者写的东西。节点用**集合名字**引用，荷载里不出现节点号。

顺带收紧了一处**过严**的规则：方向模长为零原先一律拒绝，会逼一个没有体力的 deck 写一个
它并不具有的方向。现在只有 `magnitude` 非零时才是错误。这条放宽的**接受**一半由该 deck
本身验证（它带着 `magnitude = 0.0` / `direction = [0,0]` 通过校验），**拒绝**一半仍由
`lame_cylinder` 上的反例守着。

## 3. ProblemState 与 legacy 原语

`concentrated_t`（`amplitude` / `value` / `nodes`）进入 `load_t`，带 `@off-face` 标记与 map 行。
`commit_point_loads` 是**纯搬运**：legacy 的点荷载记录没有派生计算，`force_external` 直接
消费 `pload`，所以这一轮**没有需要提取的 legacy 原语**——这本身是个有用的对照，说明
「复用而不重写」不是每次都要动 legacy，只在确实有计算时才动。

## 4. `steps(1)` 检查项立刻起了作用

这一能力刚落地，`tools/yl_step_scope_check.py` 就拦下了两处新的 `steps(1)` 读取，要求说明
它们的作用域。答案是 **per_analysis**：legacy 在块循环之前读一次点荷载表（`Fem.f90:1682`）。

但这引出了同一个陷阱的另一半：契约把集中力写在 step 下面，而本 build 取 step 1，
**第 2 步声明的不同集中力会被静默丢掉**。于是把检查项推广成一条通用规则——
凡是 legacy 只读一次、而契约仍写在 step 下的字段，都必须有一条**按名拒绝**；
`commit_step_invariants` 现在比较两步之间全部 29 个此类字段，反例见 N3。

**这正是签收意见要求沉淀的东西**：不是记住 `fixed_mask` 那一个 bug，而是让「把首步状态
固化为全程状态」这一类在下一次发生时被机械地拦住。它第一次发挥作用是在能力落地的同一天。

## 5. 本轮顺带修掉的三处度量缺陷

1. **`yl_state_map.py check` 不在任何门禁里**，因此可以悄悄变红——它确实红了一天：
   一次证据重写把手工维护的 `plasticity.mini_mc` 命中列删掉，八个 map 字段随之失去了
   「谁读它」的记录。现在它和 reader inventory 的 check 一起进了 `runtime` 门禁，
   并把 `mini_mc` 加入追踪集**用实测**恢复了那一列。
2. **gdb 追踪器拿 −O0 的运行去比 −O2 的冻结参考**，把「插桩是否扰动」和「构建独立性」
   混成了一件事。前者才是它能声称的，现在用**同一个二进制、跑两遍（带/不带 gdb）逐字节
   相同**来判定；与参考的差异改为**报告**（`beam_point_load` 6/756 值，`max|d| = 1.3e-10`，
   都是零附近的噪声——那是已登记的构建独立性欠债，不是插桩）。
3. **断点会为没有执行的行触发**，这是 R27 的镜像（一行对多地址 ↔ 一地址对多行）。
   三处 legacy-only 分支因此被记为 `reached_only` 并写明理由，而不是被当作「执行过」。

---

# Phase 5 未启动：梁荷载在语料里没有算例

指示是「先梁荷载，再板荷载」。按方法的第一步——能力差值测量——先找算例，结果是**找不到**。
这不是一句判断，是一次普查。

## 1. 普查

| 范围 | 结果 |
|---|---|
| `HSTAR_Next` 树下全部 `.loa` 文件 | **1203 个** |
| 其中 `nbeamload > 0` | **0 个** |
| 其中 `nplateload > 0` | **0 个** |
| `hstar_jobs` 语料 deck 数 | 230（其中 2 个 `.loa` 为空文件） |

判定方式：取每个文件中 `nbeamload` / `nplateload` 标题行之后的数值。全部为 0。

## 2. 梁**单元**有算例，梁**荷载**没有

`L2`（两节点梁）单元在语料里存在，共 17 个 deck 使用——但它们全是**同一个 3-D 模型**：
17 276 节点、14 584 单元、`ndimn = 3`、10 个组、PARDISO 或 PROFILE、问题类型 Q/E/S。
每一个都远在当前白名单之外，而且 3-D 与 PARDISO 都在暂停清单上。这些 deck 里的梁单元
由重力等方式受载，`nbeamload` 仍然是 0。

所以两件事要分开说：
* **梁荷载记录本身很小**：`aelem, itcurve, gloc(1:ndimn), cc` 一行，schema 扩展不过三四个字段；
* **它依附的梁单元不小**：2-D 下 `nevab = 6`（每节点 3 自由度，`mdofn = 3` 而不是 2）、
  每单元一个 `rotation` 矩阵、梁截面属性。而 `f1..f6` 那段一致节点荷载公式
  （`Load.f90:1028-1033`）确实是一个**值得提取复用**的 legacy 原语。

即：真正的代价在梁单元，不在梁荷载；而梁单元唯一的算例来源是被暂停的那一类。

## 3. 如果没有算例仍然实现，会失去什么

这个项目的完成判据一直是「真实 deck + 最终数值严格等价」。没有真实 deck，可选的只有：

* **自造一个 deck**，以 legacy 的输出为 oracle。这仍然能给出逐位回归——legacy 就是真理——
  但它证明的是「我的实现与 legacy 在我编的输入上一致」，**不证明任何使用者需要这个能力**。
  之前六个 golden 算例都不是这样来的。
* **不实现**，把梁/板荷载按 ADR-0008 §3 记为 legacy-only，等第一个真实 deck 出现。

这两条之间的取舍是范围决策，不是实现细节，所以停在这里等裁定。

## 4. 同一次普查顺带给出的、有算例支撑的下一步

把语料限制在**当前白名单的形状**（2-D、`Q`、`PROFILE`）——58 个 deck——按材料模型分：

| 材料 | deck 数 | 状态 |
|---|---|---|
| 仅 `ELASTIC_ISOTROPIC` | 31 | 已覆盖 |
| `CLASSICALEP`(+弹性) | 10 | 已覆盖（M6.4/M6.5）|
| **含 `CAMCLAY`** | **11** | **未覆盖** |
| `.mat` 未匹配到已知模型 | 6 | 未查 |

再按荷载/过程分：多块 + 边荷载 12 个（`wall_reservoir` 覆盖）、点荷载 1 个
（`beam_point_load` 覆盖）。`.tem` 在 58 个 deck 里**全部为空段**，已按 `empty_section` 处理。

所以在白名单自己的形状里，**唯一一个还有 11 个真实 deck 支撑的未覆盖能力是 CAMCLAY**。
