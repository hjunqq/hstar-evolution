# M4 L3-c：影子进程差分夹具（旧路径 vs 新路径）报告

## headline

| 运行 | MATCH | MISMATCH | NOT_COMPARABLE | UNVERIFIED |
|---|---|---|---|---|
| **对照：旧 vs 旧**（两个独立进程、两个独立目录，两算例） | **380** | **0** | **158** | **0** |
| **阴性对照**（cooks_membrane，改一个叶子值） | 189 | **1** | 79 | 0 |
| **判据：旧 vs 新**（两算例） | **0** | **0** | **158** | **380** |

**结论：夹具建成并跑通，但 L3-c 现在给不出"新旧一致"或"新旧不一致"的判定——新路径根本产不出一份可比对的
`model_ready` 快照，两个算例都在同一个点上以 exit=6 中止。** 这不是比较器的问题（阴性对照证明比较器会响），
也不是夹具的问题（旧 vs 旧 380/380 全绿）。原因是结构性的，写在 `src/runtime/yl_runtime_commit.f90`
自己的模块头里，并由本次运行实测确认：

```
HSTAR_DIAG schema=1 code=INTERNAL exit=6 severity=fatal stage="runtime"
  site="yl_state_io:state_fail"
  message="state dump failed at checkpoint \"model_ready\" field \"mesh.nodes.xyz\"
           file \"state/model_ready/state.txt\": coord is not allocated"
```

`model_ready` 检查点的快照面是 **162 个字段**；现在的新路径（`adapt_legacy_deck` → `build_runtime`
→ `commit_legacy_globals`）在其中**只有 40 个字段有仓库侧的写入者**（32 个 `RuntimeState.*` 行 + 8 个
被当作 extent 写入的计数标量），**另外 122 个没有任何写入者**。`commit_legacy_globals` 的模块头把这
写成了设计决定而不是疏漏：「Deliberately NOT written: everything that belongs to the ProblemState half
of the bridge -- coordinates, connectivity, materials, sections, solver controls, step controls.
That is M4-01. …the M4-01 change is to FOLD the two halves into one staging pass, not to add a second
commit」。**这次折叠还没有人做**，所以 `coord` 至今没有被分配，`yl_state_dump` 在第 14 个字段上按契约
中止。**这是本任务的阻塞项，已按指令上报，未绕过。**

## 0. 本报告建立了什么、没建立什么

**建立了：**

- 一个可用的影子差分夹具：两个**独立子进程**、两个**独立工作目录**，判据面是 `yl_state_dump` 的检查点
  快照，比较器完全复用 `tools/yl_state.py normalize` + `tools/yl_state_diff.py`，容差与 ignore 语义
  全部取自 `docs/m2/state-field-map.toml` 每一行自己的 `compare.rule`。
- 该夹具的自洽性证据（旧 vs 旧，380 行全 MATCH，两算例）与**阴性对照**（改一个叶子值 → 恰好一个
  MISMATCH 落在该字段上，停止规则触发）。
- 新路径当前能力边界的**实测**（不是推理）：162 行中 13 行被写出，第 14 行中止；40/122 的写入者账目。

**没有建立：**

- **没有任何"新旧路径状态一致"的结论。** MATCH=0，不是"暂时不比"，是"没有可比的证据"。
- **没有比 `model_ready` 更远的东西。** 新路径不跑 solve，`phase_ready(1)` 与 `increment_ready(1,1)`
  的 28 行（11+17）在两个算例上都是 UNVERIFIED，理由是结构性的：这两个检查点是从 FEM90 求解过程内部
  发出的（`Fem.f90:3602`、`:3656`）。
- **没有数值结果等价性。** 本报告不比对位移/应力。
- **没有重跑 L3-b。** L3-b（`docs/m4/L3b-bridge-report.md`）比的是 `build_runtime` 输出与冻结基线，
  已受理；L3-c 是 M4-01 自己的判据（独立进程的新旧差分），是另一件事，本报告不重复它的结论也不依赖它。
- **绝对没有"白名单完备"或"reader 站点已全覆盖"这类结论**——见 §6。

## 1. 夹具的形状

```
                 cases/golden/static_2d/<case>/legacy/     （全程只读，从不写入）
                        |                        |
       复制             |                        |            复制
       v                                         v
runs/static_2d.<case>/<utc>_<hash8>_l3c-old/work    build/l3c-shadow/run/<case>/work
  子进程 A：build/release/hstar --dump-state=state     子进程 B：build/l3c-shadow/yl_adapter_shadow
  （由 tools/yl_run.py 驱动）                           --dump-state=state
        |                                                     |
   <run_dir>/state（yl_run.py 已内建 normalize）        tools/yl_state.py normalize
        |                                                     |
        +----------------> tools/yl_state_diff.py <-----------+
                        （--strict --expand-hash，规则取自 map）
```

两个子进程、两个目录不是卫生习惯而是前提：两条路径都写 legacy 全局、都按相对名打开 deck 文件，
共用任何一个都会让比较失去意义。子进程 B 用 `start_new_session=True` 单独成组，`stdin=/dev/null`，
清空 `LD_LIBRARY_PATH`，`OMP_NUM_THREADS=MKL_NUM_THREADS=1`——与 `yl_run.py` 对子进程 A 的处置一致。

**判据面不由本夹具定义。** `tools/yl_shadow_diff.py` 里没有比较器、没有容差、没有 ignore 列表；
它只做进程管理和按 map 行的记账，"两个值是否相等"完全由 `yl_state_diff.py` 依 map 的
`compare.rule` 判定。计划原文（`.ccg/tasks/m4-01-legacy-adapter/plan.md`）明确禁止新建第二套
ProblemState 比较器，理由是第二套容差/ignore 语义正是 ADR-0001/0004 反复标记的漂移模式。

## 2. 分母：269 行，来自 map 自己

| 检查点 | 发出行（`emit ≠ none`） | `ignore` 行 | 合计 |
|---|---|---|---|
| model_ready | 162 | 77 | 239 |
| phase_ready(1) | 11 | 2 | 13 |
| increment_ready(1,1) | 17 | 0 | 17 |
| **合计** | **190** | **79** | **269** |

`compare.rule = "ignore"` 的行与 `emit = "none"` 的行是**同一个 79 行集合**（程序化核对，不是假设：
两个集合的对称差为空）。它们按 map 自己的规则记为 NOT_COMPARABLE，不丢弃、也绝不记为 MATCH。
每个算例 79 行 × 2 算例 = 158，这就是上表 NOT_COMPARABLE 一列在三次运行里都是 158（阴性对照只跑一
个算例，故 79）的来源。

分类规则：**MATCH** = 比较器比过且一致；**MISMATCH** = 比较器比过且不一致；**NOT_COMPARABLE** =
map 自己的 `ignore`；**UNVERIFIED** = 没有可比证据（某一侧结构缺失/畸形，或整个检查点缺失）。
**证据缺失一律不算 MATCH。**

## 3. 对照一：旧 vs 旧（夹具自洽）

同一个 `build/release/hstar`，跑两次，两个独立进程、两个独立 `runs/` 目录，然后拿这两棵树对拍。

| 算例 | MATCH | MISMATCH | NOT_COMPARABLE | UNVERIFIED | `yl_state_diff` 退出码 |
|---|---|---|---|---|---|
| cooks_membrane | 190 | 0 | 79 | 0 | 0（`compared=190 skipped=79 struct=0 mismatch=0`）|
| lame_cylinder | 190 | 0 | 79 | 0 | 0（同上）|

两个算例的两次运行 `state=` 指纹分别相同（`d06d3c4120ce`、`aaa136a3d0d0`）。`git status --porcelain cases/`
在每个算例后检查，全程为空。

**这条对照证明的是：夹具的两个子进程、两个目录、normalize 与 diff 这一整条链是通的，并且旧路径在两个
独立进程里逐字段可重复。** 它不证明任何关于新路径的事。

## 4. 对照二：阴性对照（比较器不是空转）

"零 MISMATCH" 也可能是比较器根本没在比。`tools/yl_shadow_diff.py --negative-control FIELD` 在
actual 侧的规范化树里**逐字节**改一个叶子值（不做 JSON 重序列化——重序列化会改变格式，下游工具会因为
别的合法理由报错，那样什么也证明不了），然后重跑同一次比较。

cooks_membrane，`mesh.nodes.xyz` 的首个叶子 `"0000000000000000"` → `"0000000000000001"`：

```
STRUCT stage=model_ready file=mesh.json problem=digest
       expected=71e7e494ba69… actual=380c246a661c…
MISMATCH stage=model_ready field=mesh.nodes.xyz path=mesh.nodes[1].xyz[1] rule=exact
       expected=0e+00(0000000000000000) actual=5e-324(0000000000000001)
       unit=m source=COR.global_data.node_coordinates legacy=global_var.coord
  count=1/578

STOP RULE TRIGGERED: a value-rule row disagrees between the two paths.
  MISMATCH model_ready mesh.nodes.xyz [exact] FAIL(exact)
```

计数从 190/0 变为 **189 MATCH / 1 MISMATCH**，MISMATCH 恰好落在被改的那一行、恰好指到被改的那一个
下标（`count=1/578`）。**比较器与停止规则都被证明会响。** 同时出现的 `problem=digest` 结构发现是预期
的：改了值而不改 `.sha256` 旁挂文件，本身就是比较器必须报的一类发现，两种反应都是"比较器在工作"。

## 5. 判据运行：旧 vs 新（阻塞）

| 算例 | 新路径子进程退出码 | normalize 退出码 | MATCH | MISMATCH | NOT_COMPARABLE | UNVERIFIED |
|---|---|---|---|---|---|---|
| cooks_membrane | 6 | 1（`FAIL problems=152`）| 0 | 0 | 79 | 190 |
| lame_cylinder | 6 | 1（`FAIL problems=152`）| 0 | 0 | 79 | 190 |

`git status --porcelain cases/` 在每个算例后检查，全程为空。

### 5.1 新路径在哪里停下，为什么

`adapt_legacy_deck`、`build_runtime`、`commit_legacy_globals` **三步全部成功**（子进程 stdout 逐条打印
了 `ok`），随后 `yl_state_dump('model_ready')` 写出 **13 个字段记录**（`state.txt` 共 14 行：1 行头 +
13 行字段），在第 14 个字段 `mesh.nodes.xyz` 上按 `yl_state_io:state_fail` 的契约中止，理由
`coord is not allocated`。两个算例的中止点、字段、消息完全相同。

`yl_state.py normalize` 因此拒收（这是它 fail-closed 的正确行为，不是缺陷），实测 **152 个问题**，
分解逐项数过：

| `problem=` | 条数 | 内容 |
|---|---|---|
| `missing` | 149 | `model_ready` 的 147 个字段（162 − 13 − 2，那 2 个改由 `reconstruct` 报出）+ `phase_ready(1)` / `increment_ready(1,1)` 两棵根本不存在的 `state.txt` |
| `reconstruct` | 2 | `derived.dof.active_flags`（`runtime.dof.lmdofn absent`）、`sections.material_header`（`mesh.sets.elset / mesh.elements.material absent`）|
| `truncated` | 1 | 没有 `HSTAR_STATE_END` |

没有可比对的 actual 树，190 行全部 UNVERIFIED。

### 5.2 结构性原因，及其量化

`model_ready` 的 162 个发出行按能否被仓库侧写入分账（按 map 的 `owner` 与 `legacy_symbol` 逐行统计）：

| 类别 | 行数 | 写入者 |
|---|---|---|
| `RuntimeState.*` 行（非 ignore） | **32** | `commit_legacy_globals` |
| 被当作 extent 一并写入的计数标量 | **8** | 同上（`derived.counts.{npoin,nelem,ngroup,ntcurve,mdofn,ndofix}`、`mesh.dimension`、`derived.dof.cdofn`）|
| **其余** | **122** | **无** |

122 这个数不是本报告的判断，是 `commit_legacy_globals` 模块头自己声明的范围（"WHAT IS WRITTEN" 只列
46 个 `model_ready` `RuntimeState.*` 行加它们自己的 extent；ProblemState 那一半"Deliberately NOT
written … That is M4-01"）在 map 上的投影。**把 ProblemState 那一半折叠进同一次 staging 的工作，
M4-01 目前没有任何一层做了**（L2-a 产出的是 `problem_state_t`，L3-b 明确记录 `src/runtime/*.f90`
未改动）。在它落地之前，新路径无法产出 `model_ready` 快照，L3-c 的判据面就无法成立。

### 5.3 一个附带发现：未写入的全局会被当成状态发出

以下是**手工**从两侧原始 `state.txt` 上做的逐行比对（cooks_membrane），**不是本夹具的判定**——
normalize 已经拒收了截断的 dump，比较器根本没有跑过这 13 行。列在这里是因为它对下一步有直接影响：

13 行中 **8 行相同、5 行不同**，而这 5 行**全部**是 `commit_legacy_globals` 不写的全局，取的是
Fortran 的默认初值，却被 `yl_state_dump` 当作状态发了出去：

| 字段 | legacy 符号 | 旧路径 | 新路径 |
|---|---|---|---|
| `case.name` | `global_var.probn` | `x31`（"1"）| 70 个 `00` 字节 |
| `derived.counts.runblks` | `global_var.runblks` | 1 | 0 |
| `derived.counts.npoinb` | `global_var.npoinb` | 289 | 0 |
| `derived.counts.nmats` | `global_var.nmats` | 1 | 0 |
| `steps0.output.format` | `global_var.outplot` | `x47494452`（"GIDR"）| 40 个 `00` 字节 |

含义：即使将来的折叠只覆盖一部分 ProblemState 行，**剩下没被写的行不会缺席，而会以默认值出现**，
在影子差分里表现为 MISMATCH——既不是真实的新旧分歧，也不是比较器故障。折叠必须是全覆盖的，
或者需要一个"这条路径写了哪些行"的声明面（`yl_runtime_types` 的 value-state ledger 已经是这种东西
的现成形状）。**这是给 lead 的一条设计输入，本报告不替 `src/runtime/**` 或 map 的所有者做决定。**

## 6. R27：本报告不能说的话

`docs/08-risk-register.md` 的 **R27** 记录：M1 的 "两例各命中 211 个 reader 站点" 是**下界，不是
测量值**——`tools/yl_io_inventory.py` 的 gdb 脚本对每个站点只下一条 `break FILE:LINE`，假设一行编译
成一个地址，而 ifx 会把一条数组段读取编译成两段不相连的地址范围（实测 `Load.f90:231`）。R27 归属
M1-04，**未关闭**；它自己的关闭条款还写着"M4 的影子差分会以 M1 的完备性为前提"。

因此，本报告**不作**任何下述形式的断言，将来即使旧 vs 新全绿也不能由本夹具单独得出：

- ❌ "白名单是完备的" / "路径上的 reader 站点已全部覆盖"
- ❌ "新解析器读到的东西和 legacy 读到的东西一样多"
- ❌ 任何以"没有发现差异"升级为"不存在未覆盖读取"的推断

本夹具能支持的断言只有一种形状：**在 map 声明的 190 个可比行上，两条路径的状态一致/不一致**。
一个 map 没有登记的状态，本夹具看不见；一个 M1 漏记的 reader 站点若恰好只影响 map 未登记的状态，
本夹具也看不见。这条限制在 R27 关闭前不会变。

## 7. 文件与放置理由

- **新增 `src/adapter/yl_adapter_shadow.f90`**（PROGRAM，新路径子进程）。放在 `src/adapter/` 而不是
  `tools/`：它必须链接 legacy 模块 + `src/state` + `src/problem` + `src/runtime`（含 commit）+ 七个
  适配器模块，与 `src/adapter/yl_adapter_bridge_test.f90` 是同一类构件。它刻意做成与 `hstar` 可互换：
  cwd 即 deck 目录、用同一个 `diag_set_mode_from_argv` 解析 `--dump-state=state`、用同一个
  `yl_state_dump` 发快照，所以夹具对两侧的处置可以完全对称。**它自己不含任何比较逻辑。**
- **新增 `tools/yl_shadow_diff.py`**（夹具）。放在 `tools/` 而不是 Fortran 侧：旧路径那一半是
  `tools/yl_run.py`，比较器是 `tools/yl_state_diff.py` 和 `tools/yl_state.py`，一个 Fortran 驱动
  无法驱动它们。
- **新增本文件 `docs/m4/L3c-shadow-report.md`**。
- **未改动**：`legacy/yl/**`、`cases/**`（全程只读，每次运行后 `git status --porcelain cases/` 为空）、
  `docs/m2/state-field-map.*`、`src/runtime/**`、`src/problem/yl_problem_profile.f90`、
  `src/adapter/yl_adapter_{bridge_test,parts,mesh,model,material,load,fem90,harvest,driver}.f90`、
  `tools/build.sh`。构建用的是会话临时脚本（复用 `runtime-bridge` 目标的对象与参数），未入库。

## 8. 复现

```bash
source tools/env.sh

# 1) 旧路径的二进制（若尚无）
tools/build.sh                 # -> build/release/hstar

# 2) 新路径的二进制。先建 runtime-bridge（全部 legacy 模块除 Fem.f90 + src/state
#    + src/problem + src/runtime 含 yl_runtime_commit.f90），再用它的 obj/ 追加编译
#    六个 L1 解析器 + yl_adapter_driver + yl_adapter_shadow，链接成
#    build/l3c-shadow/yl_adapter_shadow。
#    编译参数与 runtime-bridge 目标一致：ifx -O2 -warn all -stand f18。
#    （本任务未修改 tools/build.sh；脚本是会话临时脚本。若 lead 认为该目标应长期存在，
#      建议新增 tools/build.sh 的 `shadow` 目标——由 lead 决定，本任务不自行改。）
tools/build.sh runtime-bridge  # 581/581

# 3) 对照一：旧 vs 旧（夹具自洽）
python3 tools/yl_shadow_diff.py --old-vs-old -o /tmp/oldold.json
#   期望：TOTALS MATCH=380 MISMATCH=0 NOT_COMPARABLE=158 UNVERIFIED=0

# 4) 对照二：阴性对照（证明比较器会响）
python3 tools/yl_shadow_diff.py --old-vs-old --cases cooks_membrane \
        --negative-control mesh.nodes.xyz -o /tmp/negctl.json
#   期望：MATCH=189 MISMATCH=1，MISMATCH 落在 mesh.nodes.xyz，停止规则触发

# 5) 判据：旧 vs 新
python3 tools/yl_shadow_diff.py -o /tmp/oldnew.json
#   当前期望：两个算例的新路径子进程 exit=6（coord is not allocated），
#             TOTALS MATCH=0 MISMATCH=0 NOT_COMPARABLE=158 UNVERIFIED=380
```

每次运行后夹具自动执行 `git status --porcelain cases/`，非空即以退出码 2 失败（`--no-check-clean` 可关，
本报告的所有运行都开着）。逐行结果（`checkpoint|field|rule|class|detail`，每算例 269 行）在 `-o` 的
JSON 里。

### 8.1 复现所用的树状态（重要）

本报告的全部数字来自 **`src/adapter/**` 的 HEAD（`234640a`）版本** 加本任务新增的两个文件。
写报告期间 dev-l2b 正在 L2-b 上改 `src/adapter/yl_adapter_parts.f90` 与 `yl_adapter_mesh.f90`
（工作树 09:52 / 09:53 的改动），**这两个文件当前的工作树版本编译不过**
（`yl_adapter_parts.f90:364/380`，`dialect_key` / `dialect_count` 在 PURE 上下文中缺显式接口）。
那是别人正在进行中的工作，本任务没有碰。

因此复现时若直接用工作树会在编译期失败；用 HEAD 的适配器源码即可逐字复现上表：

```bash
mkdir -p /tmp/l3c-head
for f in parts model mesh material load fem90 driver; do
    git show 234640a:src/adapter/yl_adapter_$f.f90 > /tmp/l3c-head/yl_adapter_$f.f90
done
cp src/adapter/yl_adapter_shadow.f90 /tmp/l3c-head/
# 按 §8 第 2 步的顺序与参数编译 /tmp/l3c-head/*.f90，链接成 build/l3c-shadow/yl_adapter_shadow
```

这次"从 HEAD 源码重建 + 重跑"已经实际执行过，结果与 §5 表格逐字相同
（两算例 exit=6、同一条 `coord is not allocated`、TOTALS 0/0/158/380）。

## 9. 给 lead 的三条

1. **阻塞项（必须先决）**：把 ProblemState 那一半折叠进 `commit_legacy_globals` 的同一次 staging。
   在它落地前 L3-c 无法给出判定。这是 `src/runtime/yl_runtime_commit.f90` 的改动，不在本任务的文件
   所有权内，**未动**。
2. **折叠必须是全覆盖的，或者需要一个"本路径写了哪些行"的声明面**——否则未写入的全局会以默认值进入
   快照并伪装成 MISMATCH（§5.3 的五行实测）。
3. **是否给 `tools/build.sh` 加一个 `shadow` 目标**：新路径二进制目前靠会话临时脚本构建。若 L3-c 要
   进常规门禁，需要一个正式目标；`tools/build.sh` 不在本任务所有权内，**未动**。

## 独立复核（lead，2026-09-09）

本报告未按撰写者自述签收。lead 独立复核三项：

**1. 「不新建比较器」这条约束确实被遵守。** `tools/yl_shadow_diff.py` 内无任何自有的
容差、`isclose`、绝对值比较或 ignore 清单；`grep` 到的 `ignore` 全部是读映射表自己的
`compare.rule`。判定全部 shell out 给既有的 `tools/yl_state.py normalize` +
`tools/yl_state_diff.py`，规则经 `yl_state_map.load_map` 从 `docs/m2/state-field-map.toml` 取。
这正是 plan「影子差分比什么面」一节要求的形态——不存在第二套需要手工与映射表保持一致的语义。

**2. 旧 vs 旧逐字复现。** lead 自行运行 `--old-vs-old`，得
`MATCH=380 MISMATCH=0 NOT_COMPARABLE=158 UNVERIFIED=0`，与报告相同。

**3. 阴性对照逐字复现，且是决定性的。** `--old-vs-old --negative-control mesh.nodes.xyz`：

```
yl_state_diff exit=2 summary={'compared': 190, 'mismatch': 1, 'skipped': 79, 'struct': 1}
  MISMATCH model_ready mesh.nodes.xyz path=mesh.nodes[1].xyz[1] rule=exact
           expected=0e+00(0000000000000000) actual=5e-324(0000000000000001) count=1/578
STOP RULE TRIGGERED
TOTALS  MATCH=189  MISMATCH=1  NOT_COMPARABLE=79  UNVERIFIED=0
```

MISMATCH 恰好一个、恰好落在被篡改的那一个下标。**比较器与停止规则均被证明会响**，
"旧 vs 新零 MISMATCH"这类结论日后不会是空转的产物。

**4. 一处易用性瑕疵（非正确性）。** `--negative-control` 不配 `--old-vs-old` 时不报参数
组合错误，而是退化为 190 行全 UNVERIFIED（因为新路径二进制被阻塞）。它**没有谎报 MATCH**，
所以不影响任何结论；记在此处以免后来者误读那次运行。

**复核结论：夹具本身成立并可以入库；判据尚未运行。** 阻塞原因（`commit_legacy_globals`
不写 ProblemState 那一半，折叠从未实现）已由 lead 独立从映射表与源码证实：`model_ready`
共 239 行，owner 分布为 `ProblemState 84 / not_migrated 77 / RuntimeState 46 / derived 32`，
而 `coord` 在 `src/runtime/yl_runtime_commit.f90` 中出现 0 次、该文件自 `1c5d0d5` 起未改动。
折叠设计另立 L2-c 处理（`docs/m4/L2c-fold-design.md`）。
