# M4 L2-b：`UNSUPPORTED_LEGACY_DIALECT` 统一报告

## headline

| 方言行 | 反例 | 断言 | 未覆盖行 | 新增编译诊断 |
|---|---|---|---|---|
| **58** | **58** | **317 / 317** | **0** | **0** |

M3-02 能力表从 15 行扩到 **73 行**：`CAP_STAGE_GATE` 15 行（M3-02 原样未动），
`CAP_STAGE_ADAPT` **58 行**（本任务新增）。8 个适配器模块里 **58 处**临时的方言拒绝
全部改走同一个 raise 口 `reject_dialect`（`src/adapter/yl_adapter_parts.f90`）；
6 个模块里各自私有的 `STAGE_ADAPT = 'adapt'` 替身常量删除，改用
`yl_problem_errors.f90` 新增的 `PE_STAGE_ADAPT`（契约 §4 指派给 L2-b 的那一个）。

falsifiability 套件 `src/adapter/yl_adapter_dialect_test.f90`：**58 个反例，每行一个**，
每个反例都是把 golden legacy deck 的**一条记录**改掉后交给**真实解析器**跑出来的，
两个 golden 算例（`cooks_membrane`、`lame_cylinder`）上都是 317/317 PASS，
release 与 strict 两套 profile 下都跑过。

**没有另起第二张表。** 计划 Layer 2 的约束"扩展 M3-02 能力表而非另起一张"按字面执行：
`CAPABILITIES` 仍然是唯一那一个 `parameter` 数组，只是多了一列 `stage` 把它分成两段。

## 0. 本报告**没有**建立什么

- **不是"适配器覆盖了全部 legacy 方言"的证明。** 58 行是解析器**目前会遇到并明确拒绝**的
  构造，不是 legacy 方言的全集。白名单外还有多少种方言，本任务没有发言权。
- **不改变任何一条拒绝的判定条件。** 本任务搬的是"怎么报"，不是"报不报"。58 处的
  `if` 条件一处未动（唯一的例外见 §5.3 的 `.man`/`.inp` 行为差异说明）。
- **不重跑 L3-a / L3-b / 影子进程。** 本次跑过的是 `problem-types`（485/485）、
  `runtime`（60 rules bijection PASS）与新增的方言套件；`runtime-bridge` 未跑。
- **`yl_adapter_harvest.f90` 的那一处 `PE_UNSUPPORTED` 故意留在外面**，理由见 §3。
- **反例的行号绑定 golden deck 的记录布局。** 套件默认读
  `cases/golden/static_2d/cooks_membrane/legacy`，deck 的记录顺序若变，反例要跟着改——
  这正是"反例是真 deck"要付的代价，见 §4.2。

## 1. 先做清单：三类拒绝不是一回事

指令要求先分类再动代码。8 个适配器模块里所有会往 `problem_errors_t` 里加 finding 的地方，
按**它对读者说了什么**分成三类。三类的分界线不是风格问题：它决定进程退出码
（`exit_class_for_code`：2 / 3 / 6），也决定作者该改 deck、还是该等这个 build 支持、
还是该报 bug。

| 类别 | code | exit class | 意思 | 站点数 |
|---|---|---|---|---|
| A 畸形 deck | `PE_INVALID_INPUT` | 2 | 文件坏了 / 值越界，作者改 deck | 见 §1.1 |
| B 不支持的方言 | `PE_UNSUPPORTED` | 3 | 文件是合法 legacy，本次迁移不覆盖 | **58** |
| C 适配器自身故障 | `PE_INTERNAL` | 6 | 解析器被错误地调用，deck 没问题 | 见 §1.3 |

**只有 B 进入本任务的统一路径。** A 和 C 一行没动。

### 1.1 A 类（畸形 deck，不是方言）

按 rule id 归类，静态 id 共 **24 个**，另有 `A-IO/<reader_id>` 一族（`yl_adapter_load` 的 25 个读取站点各一）：

```
A-COR/malformed-record        A-ELE/malformed-record      A-ELE/count-mismatch
A-GLB/malformed-record        A-MAT/malformed-record      A-SOL/malformed-record
A-MAT/material-id-range       A-MAT/section-material-range A-MAT/thickness-conflict
D0/open-failed                D0/prefix-read-failed
F0/inp-title-1  F0/inp-run-control  F0/inp-title-2  F0/inp-problem-name  F0/inp-runblks
F0/man-title-1  F0/man-nincs  F0/man-increment-control  F0/man-tolerances
F0/man-nincs-range  F0/man-miter-range  F0/man-nstep-range  F0/man-inc-step-range
A-IO/<reader_id>              (yl_adapter_load，25 个读取站点各一)
```

**为什么它们不是方言：** `iostat/=0` 说的是"这条记录读不出来"，而不是"这条记录读出来了、
是本 build 不支持的那个分支"。`F0/man-miter-range`（`miter < 1`）尤其容易被误分——它对应
legacy 自己的 `diag_range` 调用，legacy 也拒绝，所以它是坏输入，不是"legacy 支持而我们不支持"。

### 1.2 B 类（不支持的方言）—— 58 行，按解析器分组

| 解析器 | 文件 | 行数 | rule id 前缀 |
|---|---|---|---|
| `yl_adapter_fem90` | `.inp` / `.man` | 10 | `F1`、`F2` |
| `yl_adapter_model` | `.glb` | 24 | `A-GLB` |
| `yl_adapter_mesh` | `.cor` / `.ele` | 2 | `A-COR`、`A-ELE` |
| `yl_adapter_material` | `.mat` / `.sol` | 11 | `A-MAT`、`A-SOL` |
| `yl_adapter_load` | `.loa` / `.pre` | 11 | `A1` … `A11` |
| 合计 | | **58** | |

24 个 `A-GLB` 里有 14 个是 `docs/m2/state-field-map.toml` 声明 pinned 0 的开关
（`ntlink` / `mat_curve` / `meshc` / `level_set_problem` / `ljdp` / `nlinks` / `block_stab` /
`nbackf` / `ebody` / `ninit` / `state_change` / `Bparameter` / `ntrans` / `uinitial`），
另外 10 个是"值一变、记录形状就变"的分支。

### 1.3 C 类（适配器自身故障）

```
A0/deck-context-not-filled     A-COR/context-not-filled   A-ELE/context-not-filled
A-ELE/context-incomplete       A-MAT/context-not-filled   A-SOL/context-not-filled
F3/ctx-not-filled              D1/procedure-unset         D1/load-mode-unset
oracle.cannot_open_inp         oracle.missing_legacy_state            （yl_adapter_harvest）
```

本任务给这一类**加了一条**：`reject_dialect` 收到一个表里没有的
`(rule_id, condition)` 时，报 `PE_INTERNAL` + exit class 6，见 §2.3。

### 1.4 分类不下去的：**没有**

58 处里没有一处需要硬塞。唯一一处被判定为"不属于这三类"的是
`yl_adapter_harvest` 的 `oracle.path_not_implemented`——它是第四类（预言机自身的实现缺口），
按指令**停在那里没有强行归类**，理由写在 §3。

## 2. 机制：一张表、一个 raise 口、一个对外说法

### 2.1 表：`CAPABILITIES` 加一列，不加一张表

`src/problem/yl_problem_profile.f90`：

- `capability_item_t` **追加**三个分量 `condition` / `stage` / `message`。
  追加而不是插入，因为 M3-02 的 15 行是**位置式** structure constructor，
  中间插一个分量会把它们每一个实参都静默绑到错的分量上；
  `stage` 的默认初值取 `CAP_STAGE_GATE`，所以那 15 行一个字符都不用改就还是 gate 行。
- `CAPABILITIES(*)` 由 6 个具名块拼成：`GATE_ROWS` + 5 个按解析器分组的方言块。
  **这不是 6 张表**——拼出来的 `CAPABILITIES` 才是那唯一一个 `parameter` 常量，
  所有访问器只读它。拆成块的原因是语言限制：一条语句最多 255 个续行（F2018 6.3.2.4），
  这些行需要约 290 个。写在源码注释里，免得后来者以为是设计。
- `N_GATE` / `N_ADAPT` 用 `count(CAPABILITIES%stage == ...)` **从表里数出来**，不写死。
- `capability_count()` 现在返回 **gate 段的行数**（仍是 15），不是数组长度。
  这是本次改动里最容易被误读的一行，所以在源码里写了理由：
  `yl_problem_pipeline` 的能力门、它的覆盖走查、它的唯一性检查都在
  `1..capability_count()` 上循环，方言行**不是它该评估的**——方言行在草稿存在之前就已经
  触发，覆盖走查看到它们只会把每一行都报成"没有反例的门禁行"。

### 2.2 raise 口：`reject_dialect`，参数只剩运行期事实

`src/adapter/yl_adapter_parts.f90`（8 个解析器共同的依赖，所以放这里，
表保持纯声明——和 M3-03 里"表在 `yl_runtime_rules`、raiser 在 `yl_runtime_build`"同形）：

```fortran
call reject_dialect(errors, rule_id, condition, loc, actual, expected, idx)
```

调用方只能提供**它读到了什么**（`actual`）、**在 deck 的哪里读到的**（`loc`）、
第几条记录（`idx`）。`code` / `stage` / rule id 的拼装 / `object_path` / `field` / 措辞
全部来自表行。**故意没有 `message` 形参**：一个能传措辞的调用方，就是一个能让表里的措辞
变成谎话而不触发任何失败的调用方。

### 2.3 复合键：两半进去，绝不传拼好的串

指令点名的那个 bug（`raise_row`：把裸 rule id 传到期待复合键的位置）在这里是**结构上做不到**的：
`reject_dialect` 收两个实参，键由它自己在查表成功之后拼
（`dialect_key(j) = rule_id//'/'//condition`）。调用方手里没有那根串，也就没法传错。

为什么键必须复合：`A-MAT/contact-material` 和 `A-MAT/nonlinear-normal-stiffness`
的 `(rule_id, object_path, field)` **完全相同**（都是 `A-MAT` / `materials` / `name`），
只有 `condition` 不同。M3-02 的三元组绑定在这两行上会退化成一行——这正是 M3-03
在 `yl_runtime_rules` 里把 `condition` 提成列的原因，本任务原样沿用。

表里没有的键 → `PE_INTERNAL` + exit class 6，不静默降级。
理由和 `raise_row` 一样：降级的后果是产生一条 rule id 永远匹配不上任何覆盖走查的 finding，
也就是这套机制本身要防的那种腐化，换个马甲（拼写错误）又回来了。

### 2.4 对外说法：`UNSUPPORTED_LEGACY_DIALECT`

`docs/02-migration-plan.md:103` 要求"对未支持方言返回 `UNSUPPORTED_LEGACY_DIALECT`"。
本任务把它落成**一个常量 + 一个谓词**，而**不是**一个新的 `PE_*` code：

- `DIALECT_VERDICT = 'UNSUPPORTED_LEGACY_DIALECT'`（`yl_problem_profile`，全仓唯一一处拼写）
- `dialect_verdict_of(errors)`（`yl_adapter_parts`）：累加器里只要有一条
  `PE_UNSUPPORTED @ PE_STAGE_ADAPT`，就返回该常量，否则返回空串。

**为什么不新增 code：** `docs/m4/adapter-contract.md` §4 已经把方言 finding 的 `code`
钉死在 `PE_UNSUPPORTED`（exit class 3）。再加一个拼法相同、语义相同的 code，
等于多一个要和 `exit_class_for_code` 保持同步的东西，而 `yl_problem_errors.f90`
的注释正好写着这套 code 词汇表存在的目的就是"只存在一份"。**这是一个判断，记在这里备查。**

**为什么谓词看 stage 而不只看 code：** 能力门（`PE_STAGE_CAPABILITY`）也发
`PE_UNSUPPORTED`，说的却是另一件事——deck 解析得好好的，但描述的模型本 build 跑不了。
两者退出码都是 3，只有 stage 能分开。套件里 `V2` 就是这条断言的反例：
一条门禁发的 `PE_UNSUPPORTED` **不得**被读成方言判决。

## 3. 故意留在表外的一处

`yl_adapter_harvest.f90:332` 的 `oracle.path_not_implemented`（`PE_UNSUPPORTED`，
stage `'oracle'`）**没有**并入方言表。它不属于 §1 的三类中的任何一类：

- 它不是对**用户 deck** 的判决，而是对**预言机自身**覆盖面的声明
  （"这条 legacy 分支不在 R-order-2 已确认的路径上，本预言机没实现"）。
- 并进去会有两个具体后果：其一，预言机的实现缺口会以"你的 deck 不受支持"的面目出现；
  其二，方言覆盖走查会多出一行**只有预言机能触发**的行，而产品路径的反例永远够不着它——
  正好是这套机制存在的目的的反面。

按指令，这里**停下来并如实上报**，而不是硬塞。理由同时写进了
`yl_adapter_harvest.f90` 的常量注释，免得下一个人再问一遍。

## 4. 反例：58 个，每行一个

程序：`src/adapter/yl_adapter_dialect_test.f90`（新增，PROGRAM，643 行）。

### 4.1 三条让它成为"可证伪"而不是"覆盖率报告"的性质

1. **每行都有反例。** 收尾的 `dialect_first_uncovered(all_errs)` 走完整段，
   点名第一个没被任何 finding 触发的行。
2. **每个反例只触发一行。** **逐个反例**检查，不是只看总量。
   没有这条，一个不小心撞上更早那道 guard 的 deck 也会让套件变绿，
   而它本该测的那一行从没被测过——M3-02 的审计当年找到的 6 个无反例行就是这么藏起来的。
3. **反例是真 deck。** 每一个都是 golden legacy deck 改**一条记录**，其余原样。
   套件里没有一处手搓 finding、也没有一处"直接调 `reject_dialect` 再断言它响了"。
   解析器必须在一个到那一点为止都合法的文件上真的走到那道 guard。

### 4.2 第 2 条当场抓到一个错的反例

`A-GLB/crack-beam-nonzero` 的第一版反例只把 `nlocalbeam` 改成 1。
它**没有**触发目标行——因为 `crack_and_beam` 那条记录的 io-list 会随
`nlocalbeam` 一起变长（`listglocbeam(1:nlocalbeam)`），少一个值就先被
`A-GLB/malformed-record` 拦下了。第一次运行报的是

```
FAIL  C   A-GLB/crack-beam-nonzero fires that row ALONE (it fired 0, first was F1/restart)
FAIL  X1  every dialect row has a counter-example (row 32, A-GLB/crack-beam-nonzero, has none)
```

补上尾部那个 `1` 之后通过。**这条记在这里，是因为它就是第 2 条性质要防的那个情况，
而且它真的发生了**——如果套件只统计"有没有 UNSUPPORTED 出现"，这个反例会一直绿着。

### 4.3 5 个反例不改 deck

`A-COR/dimension`、`A-ELE/element-kind`、`A8/restart-linked-boundary-unsupported`、
`A9/mif-boundary-unsupported`、`A11/mif-coordinate-record-unsupported` 这 5 行
（前两个来自 `.cor`/`.ele`，后三个来自 `.pre`）触发条件不在被解析的那个文件里，
而在 `.glb` 建立的 `deck_context_t` 上。套件对它们改的是 ctx 的**一个字段**，
deck 原样使用——改文件反而会测错东西。

### 4.4 套件本身的可证伪性（negative control）

把 `yl_adapter_load.f90` 里 A6 那道 guard 改成 `if (.false.)`（只在 scratch 副本上），
重编重跑：

```
FAIL  C   A6/beam-load-unsupported fires on its counter-example
FAIL  C   A6/beam-load-unsupported fires that row ALONE (it fired 0, first was F1/restart)
FAIL  C   A6/beam-load-unsupported makes the adapter answer UNSUPPORTED_LEGACY_DIALECT
FAIL  X1  every dialect row has a counter-example (row 53, A6/beam-load-unsupported, has none)
-- 314/318 checks passed
== FAIL (4 checks failed) ==   EXIT=1
```

套件确实会红，不是空转。仓库里的文件未被改动，改的是 scratch 副本。

### 4.5 表与 raiser 的断言（非反例部分）

| id | 断言 |
|---|---|
| T1 | gate 段仍是 M3-02 的 15 行 |
| T2 | 两段行数之和 == `CAPABILITY_ROW_TOTAL` |
| T4 | 两段**连续且 gate 在前**——所有访问器都假设这一点，只有走完整表能证明 |
| T5 | 每个方言行 rule_id / condition / deck 符号 / object_path / message 都非空 |
| T6 | 没有一列被 `LEN_COND` / `LEN_MESSAGE` / `LEN_PATH` / `LEN_KEY` 截断 |
| T7 | 方言行不带 payload（`PROFILE_KIND_NONE`） |
| T8 | 58 个复合键两两不同 |
| T9 | `dialect_find` 对每一行都能回环 |
| T10 | 导出行越界为空、在界内以对外判决名开头 |
| T11 | 没有方言行的 deck 符号和 gate 行的 item 撞名 |
| R1 | 已声明的行 → `PE_UNSUPPORTED` + `PE_STAGE_ADAPT` + **复合**键 + 表里的 path/message + 调用方的 `actual` + exit class 3 |
| R2 | **未**声明的键 → `PE_INTERNAL` + exit class 6，且不触发任何行 |
| R3 | 把拼好的键当 rule id 传进去**不会**误命中该行 |
| V1–V3 | 空累加器无判决；门禁的 `PE_UNSUPPORTED` 不是方言判决；一条方言 finding 即产生判决 |

## 5. 行为差异，逐条说明（不是"零差异"）

### 5.1 `stage`：`.inp`/`.man` 的 10 行由 `'builder'` 改成 `'adapt'`

原来 `yl_adapter_fem90` 的方言拒绝走 `builder_note_failure`，那条路把 finding 打上
`stage='builder'`（`yl_problem_builder.f90:119`），和 `docs/m4/adapter-contract.md` §4
要求的 `PE_STAGE_ADAPT` **相矛盾**。统一之后是 `'adapt'`。这是修正，不是回归。

### 5.2 `.inp`/`.man` 的方言拒绝不再置 `b%failed`

同一处的连带影响：`builder_note_failure` 顺手把 builder 标记为失败，`reject_dialect` 不碰
builder（`yl_adapter_parts` 不依赖 builder 的私有状态，也没有公开的"只标记不报错"入口）。
**已核实这不改变任何调用者的行为：** `parse_inp` / `parse_man` 的两个调用者
（`yl_adapter_driver.f90:251,285`、`yl_adapter_fidelity.f90:315,347`）都是按
`errors%count()` 增长 fail-fast，不看 `builder_failed`；两个解析器自己在拒绝后立即 `return`。
`reject_nonzero` 的 `b` 形参因此一并删掉，而不是留一个没人读的参数。

### 5.3 三处 finding 的 `actual` 从"嵌在 message 里"改成独立字段

`A2/curve-type-unsupported` 原来把 `type_curve` 的实际值拼进 message
（`"type_curve = 'XXX': ..."`）；`A8`/`A11` 原来完全没有 `actual`。
现在 message 是表里那句固定措辞，读到的值走 `actual`。这符合契约 §4
"具体的行号、读到的值、期望值 → `message` / `actual` / `expected` / `index`"，
也是表能持有 message 的前提（message 里不能有运行期值）。

其余 55 行的 `code` / `rule_id` / `object_path` / `field` / `message` / `actual` / `expected`
逐字未变。

### 5.4 删掉的重复

- 6 个模块各自的 `character(len=*), parameter :: STAGE_ADAPT = 'adapt'` 替身
  （mesh / model / material / load / fem90 / driver）→ `PE_STAGE_ADAPT`。
  `yl_adapter_fidelity.f90` 的同名替身**没动**（不在本任务所有权内），
  它仍然自带一份字面量。
- `yl_adapter_model.fail_unsupported`（删除）、`reject_pinned`（保留但只剩 `condition`+值）、
  `yl_adapter_material.mat_reject`（保留但只剩 `condition`+行号+值）、
  `yl_adapter_load.reject_unsupported`（删除）、
  `yl_adapter_fem90.reject_nonzero`（保留但只剩两半键）。

## 6. 构建与运行证据

工具链：`tools/env.sh` 的固定 `ifx 2025.3`。

| 目标 | 结果 |
|---|---|
| `tools/build.sh problem-types`（release） | **PASS 485/485**（`yl_problem_pipeline_selftest`）+ `yl_problem_selftest` |
| `tools/build.sh problem-types --profile strict` | **PASS 485/485** |
| `tools/build.sh runtime`（release） | **PASS**，rule-table ↔ map 双向双射 60 rules / 46 produce 46 |
| 适配器链 `-O2 -warn all -stand f18` | 干净 |
| 适配器链 strict flags（`-check bounds,pointers -init=snan,arrays -fpe0 -warn all -stand f18`） | 干净 |
| `yl_adapter_dialect_test`（release，cooks_membrane） | **PASS 317/317** |
| `yl_adapter_dialect_test`（release，lame_cylinder） | **PASS 317/317** |
| `yl_adapter_dialect_test`（strict，cooks_membrane） | **PASS 317/317** |
| `yl_adapter_harvest` / `yl_adapter_fidelity` / `yl_adapter_bridge_test` 重编 | 干净（本任务未改这三个文件的接口） |

**编译诊断基线：** 改动前后都是同样的 3 条 `remark #7712`（未使用的 dummy 参数：
`yl_adapter_material.parse_sol` 的 `b`、`yl_adapter_load.parse_pre` 的 `b`、
`yl_adapter_fem90.parse_inp` 的 `ctx`）。**没有新增任何 warning 或 remark**，
也没有顺手消掉这 3 条既有的（它们不属于本任务）。

`runtime-bridge` 目标本次**未运行**。

## 7. 改动的文件

| 文件 | 改动 |
|---|---|
| `src/problem/yl_problem_profile.f90` | 表加 `stage`/`condition`/`message` 列 + 58 个方言行 + 分区访问器 |
| `src/problem/yl_problem_errors.f90` | **仅新增** `PE_STAGE_ADAPT = 'adapt'`（契约 §4 指派） |
| `src/adapter/yl_adapter_parts.f90` | `reject_dialect` / `dialect_verdict_of` / 覆盖走查 |
| `src/adapter/yl_adapter_mesh.f90` | 2 处改走统一口 |
| `src/adapter/yl_adapter_model.f90` | 24 处 + 删 `fail_unsupported` |
| `src/adapter/yl_adapter_material.f90` | 11 处 + `mat_reject` 瘦身 |
| `src/adapter/yl_adapter_load.f90` | 11 处 + 删 `reject_unsupported` |
| `src/adapter/yl_adapter_fem90.f90` | 10 处 + `reject_nonzero` 瘦身（见 §5.1/5.2） |
| `src/adapter/yl_adapter_driver.f90` | 替身常量删除 + 模块头说明对外判决怎么问 |
| `src/adapter/yl_adapter_harvest.f90` | 仅常量注释（说明为何不并入，§3） |
| `src/adapter/yl_adapter_dialect_test.f90` | **新增**，58 反例套件 |
| `docs/m4/L2b-dialect-report.md` | 本文件 |

`src/problem/yl_problem_errors.f90` 不在任务给的所有权清单里，但
`docs/m4/adapter-contract.md` §4 明确写着 `PE_STAGE_ADAPT`"由 L2-b 新增此常量"，
且 8 个适配器模块的注释都在等它。改动是**一行常量 + 注释**，未触碰该文件其它任何部分。
**在此显式上报，供 lead 复核这一步是否越界。**

## 8. 遗留

- **`yl_adapter_fidelity.f90` 仍带一份 `STAGE_ADAPT = 'adapt'` 字面量**（禁止触碰清单里的文件）。
  现在 `PE_STAGE_ADAPT` 已经存在，它可以在自己的任务里换掉——不换也不会错，只是多一份拼写。
- **反例的行号绑定 golden deck 的记录布局。** 见 §0。
- **`yl_adapter_dialect_test` 未接入 `tools/build.sh`**（该文件在禁止触碰清单里）。
  它需要按依赖序编到 problem 层 + 5 个解析器之后，运行时接两个可选参数
  `[DECK_DIR] [SCRATCH_DIR]`，默认 `cases/golden/static_2d/cooks_membrane/legacy` 和 `.`。
  接进哪个 target 由 lead 决定。

## 独立复核（lead，2026-09-09）

**1. 越界改动已审并接受。** `src/problem/yl_problem_errors.f90` 不在 L2-b 的所有权清单内，
但改动是 8 行纯新增（`PE_STAGE_ADAPT` 一个 parameter + 注释），`docs/m4/adapter-contract.md` §4
确实把该常量指派给 L2-b，且 L2-b 主动上报而非隐瞒。接受。

**2. 补跑了 L2-b 未跑的门禁。** L2-b 自述未运行 `runtime-bridge`，而它改的
`yl_problem_errors.f90` 正是该套件的依赖。lead 补跑：

| 门禁 | 结果 |
|---|---|
| `tools/build.sh problem-types` | 485/485 |
| `tools/build.sh runtime`（含反向双射） | PASS，60 规则，46↔46 双射 |
| `tools/build.sh runtime-bridge` | **581/581**（本次补跑，无回归） |

**3. 最关键的回归检查：L3-b 的 46 行没有被碰坏。** 适配器被本任务改动，而 L3-b 的
64 个 MATCH 是 ADR-0004 刚刚结清的债。lead 用 **L2-b 之后的适配器源码**重新编译
`yl_adapter_bridge_test` 并重跑：`MATCH=64 MISMATCH=0 NOT_COMPARABLE=28 UNVERIFIED=0`，
与折叠前逐字相同。

**4. 58 反例套件复现。** 首次复核跑出 200/317，原因是 lead 的调用参数传错（该传
`<case>/legacy` deck 目录，误传了 `<case>`）。按 `Usage` 正确调用后两个算例均
**317/317 PASS**，L2-b 报的数属实。

**5. 阴性对照。** 在 scratch 副本里注释掉 `yl_adapter_load.f90:575` 的 A6 raise，套件
**314/318 报红**并点名该行；同时 `X1 每个方言行都有反例` 一并报红——**没有反例的行藏不住**。
套件不是只会打印 PASS。

**6. 未强行分类的那一个站点，判断正确。** `yl_adapter_harvest.f90:332`
`oracle.path_not_implemented` 是对**预言机覆盖面**的陈述，不是对用户 deck 的裁决。
把它折进方言表会让预言机的缺口读起来像是对 deck 的判决，并给覆盖走查塞进一行只有预言机
能触发的规则。留在外面是对的。

**复核结论：L2-b 可以入库。**
