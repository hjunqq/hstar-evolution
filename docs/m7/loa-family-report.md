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
