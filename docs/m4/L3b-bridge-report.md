# M4 L3-b：adapter → build_runtime → commit_legacy_globals 与冻结基线对拍报告

## headline

| MATCH | MISMATCH | NOT_COMPARABLE | UNVERIFIED |
|---|---|---|---|
| **64** | **0** | **28** | **0** |

两个 golden 算例（`cooks_membrane`、`lame_cylinder`）各 46 行 `model_ready` `RuntimeState.*`
map 行，合计 92 行判定。32 个 `compare.rule ≠ ignore` 的行 × 2 案例 = 64，全部 `MATCH`；14 个
`compare.rule = ignore` 的行 × 2 案例 = 28，全部 `NOT_COMPARABLE`（附价值状态账本给出的理由，
见 §3）；`MISMATCH=0`，STOP RULE 未触发；`UNVERIFIED=0`——没有一行因为找不到基线值或管道中途
中止而被跳过。

**直接回答 team lead 的问题：`build_runtime` 的输出与冻结 legacy 基线一致，且这一次是在两个真实
golden deck 上验证的，不是 M3-03 那具结构等价体。** 32 个可比对行里没有一行不一致；14 个
`ignore` 行的"不可比对"是 map 自己声明的性质，不是本次跑出来的缺口。ADR-0004 登记的风险——
"`build_runtime` 的某个派生与 legacy 不等价，缺陷已经积压了整个 M3 阶段"——**没有在这两个
golden 算例上出现**。

## 0. 本报告回答的问题，以及为什么现在才能回答

ADR-0004（`docs/decisions/0004-defer-m3-exit-to-m4.md`）延后了 M3 的出口条件"bridge 后的
state fingerprint 与原路径一致"，理由写得很直接：M3 没有"旧 deck → `problem_state_t`"的通路，
无法把 256 单元的 Cook 膜、64 单元的 Lamé 筒表示成 `problem_state_t` 去跑 `build_runtime` →
`commit_legacy_globals`，M3-03 的 513/513 桥接自检（`yl_runtime_bridge_test.f90`）因此只能用
一个手搭的 1/2 单元结构等价体，**结论被明确标注为 PARTIAL**（`docs/m3/M3-03-runtime.md` §8：
"本任务因此没有任何一行的值与 M2 冻结基线比对过"）。M4-01 的 `yl_adapter_driver.adapt_legacy_deck`
补上了这条通路，本报告就是 ADR-0004 承诺的举证：

```
legacy deck --adapt_legacy_deck--> problem_state_t --build_runtime-->
runtime_state_t --commit_legacy_globals--> 真实 legacy 全局变量
--(本程序自己读回)--> 与 cases/golden/<case>/reference/state/model_ready/*.json 比对
```

程序：`src/adapter/yl_adapter_bridge_test.f90`（新增，PROGRAM，1 个文件，两个 golden 算例都跑）。

## 0.1 本报告**没有**建立什么

- **只比对一个检查点（`model_ready`）。** `phase_ready(1)`／`increment_ready(1,1)` 的
  `RuntimeState.*` 行不在 M3-03 的范围内（`docs/m3/M3-03-runtime.md` 开头："不含…phase_ready
  / increment_ready 属 M4-01"），本报告同样不碰。
- **不是影子进程差分（shadow diff）。** 本报告不驱动求解器、不产生位移/应力，"两条路径算出来的
  最终结果是否一致"这个问题不在这里回答——那是 L3-c 的职责。
- **不是数值结果等价性证明。** 43 行的 `abs_tol` 容差比对（Q4 高斯几何三行）只证明"两条路径在
  同一套坐标和求积表下算出的浮点值在容差内一致"，不证明"求解结果一致"。
- **不重跑 M3-03 自己的自检。** `yl_runtime_selftest`（108/108）与 `yl_runtime_bridge_test`
  （513/513）本次未重跑，假定未改动的文件仍然是绿的——本报告只新增了一个独立的 PROGRAM 文件，
  不改动 `src/runtime/*.f90`。
- **只覆盖两个 golden deck，只覆盖 `static-q4-si/1` 契约标签。** 白名单之外的 legacy deck、
  别的契约版本，本报告没有发言权。
- **14 个 `ignore` 行的"值本身"不在本报告的判定范围内。** 见 §3——它们的分类来自 map 与
  value-state ledger 声明的性质，不是本报告去猜测或验证它们的实际数值。

## 1. 管道与验证方式

对每个 golden 算例：

1. 把 `cases/golden/static_2d/<case>/legacy/` 复制到 `build/l3b-scratch/<case>/`（**从不写入
   `cases/`**——`adapt_legacy_deck` 本身只以 `status='old'` 打开文件，但指令是"从不写入
   `cases/`"而不是"信任适配器不会写"，所以复制是本程序自己的纪律，不是对适配器的怀疑）。
2. `adapt_legacy_deck(scratch_dir, problem, manifest, errors)` → `problem_state_t`。
3. `build_runtime(problem, CONTRACT_TAG, rt, rmanifest, errors)`（`CONTRACT_TAG =
   'static-q4-si/1'`，来自 `yl_runtime_contract`，未硬编码）→ `runtime_state_t`。
4. `commit_legacy_globals(rt, errors)` → 真实 `global_var` / `prescribed` / `applied_load` /
   `meshfine` 全局变量。
5. **直接读回这些真实全局变量本身**（`use global_var, only: element, group, ...`），不经过
   `rt`——这样比对的是"写穿"这一步本身，不只是 `build_runtime` 的输出。
6. 与 `cases/golden/<case>/reference/state/model_ready/{control,dof,mesh,steps,loads}.json`
   逐行比对，`compare.rule` 取自 `docs/m2/state-field-map.toml`。

链接：`legacy/yl` 全量源码（与 `runtime-bridge` 目标同一份列表，`Fem.f90` 除外）+
`src/state` + `src/problem` + `src/runtime`（含 `yl_runtime_commit.f90`）+ 七个 `src/adapter`
解析器模块 + `yl_adapter_driver.f90` + 本报告的新程序。`tools/build.sh` 未改动（不在本任务的
文件所有权范围内），构建脚本是本次任务专用的临时脚本（复用 `runtime-bridge` 目标的源码列表和
编译/链接参数，未纳入版本库）。编译：`ifx -O2 -warn all -stand f18`，**零告警、零 remark**。

## 2. compare.rule 的三种，以及为什么它们各自足够严格

### 2.1 `exact`（15 行）——elementwise 相等；i32 用 `==`，f64 用位精确比较

15 行中的 7 个 f64 行（`dfact`、`fixed`、`result_zero`、`tofor`、`stfor`、`toforl`、
`toform`）在 `model_ready` 全部按 map 自己的注记（"R24"）恒为全零，所以 atol=rtol=0 的位精确
比较对它们而言不是近似判据，是真的位相等判据。

### 2.2 `hash`（14 行）——elementwise 相等，比重算 sha256 摘要更严格

`docs/m2/state-field-map.toml` 里这 14 行标 `compare.rule = "hash"`，但每一行的基线 JSON
**同时**带着完整的 `values` 数组和 `sha256` 摘要（逐行用
`python3 -c "import json; ..."` 核对过，不是假设）。本程序对每一行都做逐元素比较，不重算
摘要——理由写在程序模块头里：重算摘要需要仓库里没有的哈希实现，且只能证明"某些字节的摘要相
同"；逐元素比较证明的是值本身相等，**逐值相等蕴含任何摘要都相等**，是更强的判据，不是更弱的
替代。

其中 6 行（`leldofix`、`levdofix`、`lefdofix`、`listp_group_listg`、`listp_group_listp`、
`unode_ipoin`/`unode_ne_unode`/`unode_list`，见下）在基线 JSON 里是按记录键分组的嵌套列表
（ragged）。之所以不需要写一个真正的 JSON 解析器就能对上顺序：这些文件里的每个数组都是
Fortran 数组本身的列主序（column-major）展开，按声明形状从**最后一维**到**第一维**重新嵌套
——用 `runtime.gauss.gpcod`／`cartd` 的嵌套深度和外内层顺序反向核对过，与 map 的 `shape`
列（最快变化维在前）完全对应。所以按 legacy 记录顺序（k=1..ndofix 外层、该记录自己的
`lnefix` 长度子数组内层；group 外层、`np_unode` 内层，等等）拼接出来的 legacy 侧序列，和
JSON `values` 做深度优先叶子展开（`flatten_tokens`，不关心嵌套深度）得到的序列，天然逐位
对齐——不需要偏移表，不需要按名字重新配对。程序模块头（`WHY THE RAGGED map ROWS...`）写了
完整推理。

### 2.3 `abs_tol`（3 行）——`atol=1e-14, rtol=1e-12`，来自 map 本身

三行都是 Q4 高斯几何（`runtime.gauss.djacb`／`gpcod`／`cartd`），容差值取自
`docs/m2/state-field-map.toml` 每行自己的 `compare = { rule = "abs_tol", atol = 1e-14,
rtol = 1e-12, ... }`，不是本程序发明的常数。判据：`|baseline - runtime| <= atol +
rtol*|baseline|`，逐元素检查，报告记录实测的最大 `|diff|`。

### 2.4 `ignore`（14 行）——NOT_COMPARABLE，理由取自 value-state ledger 而非本程序猜测

**没有一行因为 `compare.rule = "ignore"` 就被记成 MATCH。** 每一行的 NOT_COMPARABLE 理由
来自 `docs/m3/M3-03-runtime.md` §3 定义的三种情形之一，本次逐行核对 `yl_runtime_build.f90`
里 `publish_reserved`／`publish_absent`／`publish_check_vacuous` 的调用点（不是读注释猜测）
才确定分类，然后在程序里用 `runtime_status_get`——`yl_runtime_types` 公开的、只读
`runtime%field_status` 账本的安全接口，**从不触碰原始 legacy 内存**——对每一行做了一次交叉
校验：本次构建产生的账本状态是否与预期一致。92 次交叉校验（46 行 × 2 案例）**全部一致**，
没有一条 `LEDGER_MISMATCH`／`LEDGER_MISSING`（若有会作为独立日志行出现，本次运行的日志里
一条也没有）。

三种情形与本次的 14 行对应关系：

| 情形 | 含义 | 行 |
|---|---|---|
| RESERVED（9 行） | 已分配、内容在 `model_ready` 未定义，**不得读** | `runtime.element.tload`／`eload`／`rload`、`runtime.vectors.delitfi`／`deltafi`、`runtime.cursor.lineload`（经 `publish_check_vacuous` 记为 RESERVED）／`line_load_block`／`linet`／`line_temp_block` |
| ABSENT（2 行） | 本路径刻意不分配，缺席本身是被断言的性质 | `runtime.topology.unode_np_unode`、`runtime.topology.unode_patch_nod` |
| DEFINED 但不采集（3 行） | 已计算、确定性、但 map 出于别的理由排除出快照 | `runtime.gauss.djacb_mass`／`gpcod_mass`（mass 求积规则算出来但 static_2d 无消费者读）、`runtime.element.elcod_f`（`mesh.nodes.xyz` 的冗余拷贝） |

**ABSENT 的两行为什么连"确认缺席"这个结构事实都没有在程序里直接触碰内存去验证**：
`unode_patch_nod`（指针分量）在 M3-03 自己的模块头里写明"在这条路径上甚至调用
`associated()` 都不安全"；`unode_np_unode`（标量分量）是"未定义"而不是"结构性的缺席
指标"（数组是否分配是结构事实，标量的值是不是垃圾不是）。本报告因此**只用 ledger 的安全
接口**做这两行的交叉校验，不去读它们本该缺席的存储——这本身就是对 M3-03 该项设计的一次
真实使用，不是回避。

## 3. 逐行表（32 个可比对行；两个案例分类相同，故只列一次；数值见 §4/日志）

| map id | compare.rule | 参照文件 | 两案例分类 |
|---|---|---|---|
| runtime.amplitudes.dfact | exact | loads.json | MATCH |
| runtime.dof.lmdofn | exact | dof.json | MATCH |
| runtime.increment.iblks_at_model | exact | control.json | MATCH |
| runtime.increment.lblks_at_model | exact | control.json | MATCH |
| runtime.activation.appear | exact | steps.json | MATCH |
| runtime.dof.iffix | exact | dof.json | MATCH |
| runtime.dof.fixed | exact | dof.json | MATCH |
| runtime.dof.ntotv | exact | dof.json | MATCH |
| runtime.dof.trans_nintf | exact | dof.json | MATCH |
| runtime.vectors.result_zero | exact | dof.json | MATCH |
| runtime.vectors.tofor | exact | dof.json | MATCH |
| runtime.vectors.stfor | exact | dof.json | MATCH |
| runtime.vectors.toforl | exact | dof.json | MATCH |
| runtime.vectors.toform | exact | dof.json | MATCH |
| runtime.element.ice0 | exact | mesh.json | MATCH |
| runtime.boundary.ldofix | hash | dof.json | MATCH |
| runtime.boundary.lnefix | hash | dof.json | MATCH |
| runtime.boundary.leldofix | hash | dof.json | MATCH |
| runtime.boundary.levdofix | hash | dof.json | MATCH |
| runtime.boundary.lefdofix | hash | dof.json | MATCH |
| runtime.dof.nodfn | hash | dof.json | MATCH |
| runtime.dof.ldofs | hash | dof.json | MATCH |
| runtime.dof.ldofs_f | hash | dof.json | MATCH |
| runtime.topology.listp_group_mgroup | hash | mesh.json | MATCH |
| runtime.topology.listp_group_listg | hash | mesh.json | MATCH |
| runtime.topology.listp_group_listp | hash | mesh.json | MATCH |
| runtime.topology.unode_ipoin | hash | mesh.json | MATCH |
| runtime.topology.unode_ne_unode | hash | mesh.json | MATCH |
| runtime.topology.unode_list | hash | mesh.json | MATCH |
| runtime.gauss.djacb | abs_tol (atol=1e-14, rtol=1e-12) | mesh.json | MATCH |
| runtime.gauss.gpcod | abs_tol (atol=1e-14, rtol=1e-12) | mesh.json | MATCH |
| runtime.gauss.cartd | abs_tol (atol=1e-14, rtol=1e-12) | mesh.json | MATCH |

14 个 `ignore` 行（分类理由见 §2.4）：`runtime.gauss.djacb_mass`、`runtime.gauss.gpcod_mass`、
`runtime.element.elcod_f`、`runtime.element.tload`、`runtime.element.eload`、
`runtime.element.rload`、`runtime.vectors.delitfi`、`runtime.vectors.deltafi`、
`runtime.cursor.lineload`、`runtime.cursor.line_load_block`、`runtime.cursor.linet`、
`runtime.cursor.line_temp_block`、`runtime.topology.unode_np_unode`、
`runtime.topology.unode_patch_nod` —— 全部 `NOT_COMPARABLE`（两个案例一致）。

## 4. abs_tol 三行的实测最大偏差

| map id | cooks_membrane 实测 max\|diff\| | lame_cylinder 实测 max\|diff\| | atol | rtol |
|---|---|---|---|---|
| runtime.gauss.djacb | 0.000e+00 | 2.255e-17 | 1e-14 | 1e-12 |
| runtime.gauss.gpcod | 7.105e-15 | 2.220e-16 | 1e-14 | 1e-12 |
| runtime.gauss.cartd | 0.000e+00 | 1.243e-14 | 1e-14 | 1e-12 |

三行、两案例，六个实测偏差全部严格小于容差（最接近容差上限的是 `lame_cylinder` 的
`runtime.gauss.cartd`：1.243e-14 < atol=1e-14 + rtol·|baseline|，其中 `|baseline|` 项贡献
了余量——不是 atol 单独兜住的）。没有一个偏差是 0 又碰巧等于容差上限，也没有一个逼近到需要
另加说明的地步。

## 5. MISMATCH：0（STOP RULE 未触发）

两个案例、全部 46 行、两轮跑（含一次从干净 scratch 副本重新复制、重新构建、重新对拍的复现
跑）均未产生任何 `MISMATCH`。STOP RULE（"任何 `exact` 规则行不一致就停"）没有被触发过一次。

**没有发现"`build_runtime` 的某个派生与 legacy 不等价"这类缺陷**——ADR-0004 登记的风险在这
两个 golden 算例上没有兑现。

## 6. 复现

```
source tools/env.sh
# 编译（临时脚本，未纳入 tools/build.sh，复用 runtime-bridge 目标的源码列表/参数）：
#   legacy/yl 全量源码（Fem.f90 除外）+ src/state + src/problem + src/runtime
#   （含 yl_runtime_commit.f90）+ 七个 src/adapter 解析器模块 + yl_adapter_driver.f90
#   + src/adapter/yl_adapter_bridge_test.f90
# ifx -O2 -warn all -stand f18，零告警。
./<built-binary> .          # 参数：仓库根目录（默认 '.'）
# stdout：每行的 MATCH/MISMATCH/NOT_COMPARABLE + 明细；退出前打印四个计数汇总。
# l3b_bridge_results.log：case|map_id|rule|classification|detail 的完整逐行记录（*.log 已
#   在 .gitignore 中，不入库）。
```

## 7. 文件清单

- 新增：`src/adapter/yl_adapter_bridge_test.f90`（本任务的全部代码；PROGRAM，无外部脚本
  依赖，唯一的 I/O 是读 golden 案例的 `legacy/` 目录副本、读 `reference/state/model_ready/
  *.json`、写自己的 `l3b_bridge_results.log`）。
- 新增：本文件 `docs/m4/L3b-bridge-report.md`。
- 未改动：`src/runtime/*.f90`、`src/adapter/yl_adapter_driver.f90` 及其余六个解析器模块、
  `tools/build.sh`、`cases/golden/**`（全程只读，逐次运行前用一份新的 scratch 副本，从不在
  `cases/` 下打开任何文件）。

## 8. 结论

**`build_runtime` 的输出与冻结 legacy 基线一致**：46 个 `model_ready` `RuntimeState.*` 行，
32 个有值判据的行在两个真实 golden 算例上逐值/逐哈希/容差比对全部通过（MATCH=64），14 个
`ignore` 行的"不可比对"由 value-state ledger 的交叉校验确认为设计使然而非疏漏
（NOT_COMPARABLE=28），零 MISMATCH，零 UNVERIFIED。ADR-0004 延后到 M4-01 的这条 M3 出口
证据，**在本报告的范围内（两个 golden 算例、`model_ready` 一个检查点、`static-q4-si/1` 契约）
可以签收**。

仍然未建立、留给后续阶段的：`phase_ready`／`increment_ready` 检查点的 `RuntimeState.*` 行
（未来若有）、影子进程差分（L3-c）、任意契约版本或 golden 算例之外的 deck、以及 M3-03 已经
写明未做的用后释放/泄漏检测。

## 9. 独立复核（lead，2026-09-09）

本报告的结论没有按撰写者自述签收。lead 用**自己的**编译链重建并重跑，另加一次阴性对照：

**9.1 分母是对的，而且由映射表背书。** 报告说 46 行，映射表里 `checkpoint = "model_ready"`
且 `id` 以 `runtime.` 开头的行是 **53** 行、`ignore` 是 **21** 个。差的 7 行
（`element.{area,estif,icbound,jblks,ktotg,minedge,neqcy}`）在映射表中全部是
`owner = not_migrated` / `emit = none`——映射表自己就把它们排除在已迁移 RuntimeState 面之外，
`yl_runtime_commit.f90` 的 "WHAT IS WRITTEN" 也独立地写着 46。46/14 成立，且不是循环论证。

**9.2 独立重跑一致。** `tools/build.sh runtime-bridge`（581/581）后，用 lead 自建的 8 模块
适配器链 + 本程序链接，在真实树上得到 `MATCH=64 MISMATCH=0 NOT_COMPARABLE=28 UNVERIFIED=0`，
与报告逐字相同；`git status cases/` 全程为空。

**9.3 阴性对照：比较器确实在比。** "零 mismatch" 也可能是比较器空转。把
`cooks_membrane` 基线 `mesh.json` 中 `runtime.element.ice0` 的 `values` 首元素做**逐字节**
改动（`0` → `1`，不重排 JSON、不重序列化），程序立即报

```
MISMATCH  runtime.element.ice0  [exact]  first mismatch at flat index 1 of 256: baseline=1 runtime=0
STOP RULE TRIGGERED: an exact-rule row disagrees with the frozen baseline.
```

并按停止规则 `error stop`。**比较器与停止规则均已被证明会响**，不是只会打印 MATCH。
（注：用 `json.dump` 重写基线的对照是无效的——紧凑重序列化会让本程序的文本扫描定位不到字段，
表现为 UNVERIFIED 而非 MISMATCH。阴性对照必须逐字节改。）

**9.4 复核中发现并修掉的一个鲁棒性缺陷。** 暂存拷贝命令的缓冲原为 `character(len=512)`，
而该命令要拼进 `scratch` 与 `legacy_src` 各两次。仓库根路径较长（本次约 110 字符）时命令被
截断，`cp` 失败，整个算例退化为 92 行全 UNVERIFIED。**行为是响的**（程序打印 ABORT 并把每行
标为 UNVERIFIED，没有静默算过），但结果无谓丢失。已把 `cmd` 放宽到 `len=2048`；修复后真实树
结果不变（仍 64/0/28/0），长路径下不再整例失败。

**复核结论：L3-b 的结果成立。** ADR-0004 延后的 M3 出口证据在本报告声明的范围内可以签收。
