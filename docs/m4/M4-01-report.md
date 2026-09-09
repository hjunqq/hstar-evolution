# M4-01 实现报告：静力 Legacy Adapter，与 L2-c 折叠

本文是**实现报告**，不是验收矩阵。验收矩阵（「出口条件 ↔ 证据」的独立核对）由未参与本任务
编码的 `accept-m2m3` 另行建立。本文只回答实现者才知道的三件事：**做了什么、怎么做的、边界在哪**。

## headline

| 面 | 结果 | 范围 |
|---|---|---|
| 影子差分（M4-01 自身判据） | **MATCH=324 MISMATCH=0 NOT_COMPARABLE=158 UNVERIFIED=56** | 仅 `model_ready` |
| L3-b 冻结基线对拍（红线） | **MATCH=64 MISMATCH=0** | 两个 golden 算例，`model_ready` |
| commit 出处账本 `NOT_MIGRATED` | **118 → 0** | 账本关于自身的陈述，见 §3 |
| 释放盲区阳性对照 | **21 个内层释放站点中 6 处**（每数组一处） | 见 §4 |
| R29 | **未关闭** | 见 §5 |

**不得把上表读成「折叠已被验证正确」。** 每一格的范围限定都是判据的一部分，不是免责声明。

## 0. 这条路径是什么

M4 的目标原文：旧 deck **不再由原 reader 直接驱动全局变量**。M4-01 建立的通路是

```
legacy deck --adapt_legacy_deck--> problem_state_t (+ deck_residue_t)
  --build_runtime--> runtime_state_t
  --commit_legacy_globals--> 真实 legacy 全局变量
```

其中 L2-c「折叠」是本报告的主体：`commit_legacy_globals` 此前只写 `RuntimeState` 那一半，
`ProblemState` 那一半的 118 行在出处账本里记作 `NOT_MIGRATED`——**即「这条路径没有写它」**。
折叠把这 118 行并入 **同一次 staging**，不新增第二个 legacy 全局 writer（`plan.md` 的禁止项）。

### 0.1 为什么必须是同一次 staging，而不是「再加一个 writer」

`yl_runtime_commit.f90` 的结构是 VERIFY → STAGE → WRITE，WRITE 段只允许 `move_alloc` 与
标量赋值。两个 writer 意味着两套「什么时候全局才算写完」的语义，而快照（`yl_state_dump`）
在检查点上读全局——它不知道第二个 writer 还没跑完。这不是风格偏好：**总体性是被 dump 强制的**
（设计 §2）。

### 0.2 `deck_residue_t`：ADR-0003 不建模、legacy 却要读的那 27 个值

118 行里有一类既不来自 `problem_state_t` 也不来自 `runtime_state_t`：legacy 读进来、留在
模块变量里、而 ADR-0003 的输入模型刻意不建模的量（温度计数、`runblks`、`nsmat`、
`stab_matde`、`npoinb`、`delgroup` 等）。把它们塞进 `ProblemState` 会污染输入模型
（设计 §3.1 三道闸门否决）。裁定是新增一个**载体**类型 `deck_residue_t`（27 个分量），
由适配器填充，与 `problem` 并列作为 commit 的输入：

```fortran
commit_legacy_globals(problem, residue, runtime, errors)
```

**载体不是 ProblemState 的后门**：它没有 `compare.rule`、不进快照比对面、每个分量都必须
通过 `verify_residue_inputs`（26 个 `opt_is_set` + 1 个 `allocated`）与
`verify_residue_against_gates`（与适配器闸门规则交叉校验）才被读取。后者的模块头**点名了
哪些没有交叉校验**（`stab_matde` 的区间、`npoinb`/`nsmat`/`delgroup` 根本没有闸门规则）——
这三项今天靠的是适配器写对，没有第二道机制。

### 0.3 Staging 投毒：让「漏写」变成红线而不是静默

每个 staging 缓冲在赋值前先写 `STAGE_POISON_I` / `STAGE_POISON_R`（`huge()`）。
删掉一行写入不会得到「碰巧是 0 的旧值」，而是得到一个不可能的值。指针用 `null_*`
覆盖、已赋值的非指针用 `poison_*` 覆盖，两者不重叠。**这是本任务里唯一能把「少写一行」
变成必然失败的机制**——账本只能声明写了，投毒才能让没写显形。

## 1. 判据的确切范围

**M4-01 的判据是影子差分，不是任何自检套件的绿。** 结果（`d7d8867` 之后，harness 由 lead
修好 `--expect-checkpoints` 之后跑出）：

```
MATCH=324  MISMATCH=0  NOT_COMPARABLE=158  UNVERIFIED=56
```

三个非零的非 MATCH 桶各自意味着不同的事，**不能合并读**：

- **`NOT_COMPARABLE=158`**：map 自己声明 `compare.rule = ignore` 的行。它们的「不可比对」
  是映射表的性质，不是本次跑出来的缺口。
- **`UNVERIFIED=56`**：**新路径不驱动求解，到不了那两个检查点**（`phase_ready` /
  `increment_ready`），所以这些行没有被比较过——既不是通过，也不是失败，是**没测**。
- **`MATCH=324` 只覆盖 `model_ready` 这一个检查点。**

因此本报告能签收的是：**在 `model_ready` 这个面上、在两个 golden 算例上、在
`static-q4-si/1` 契约下，新旧两条路径的状态一致**。超出这个面的任何说法都没有证据。
求解结果是否一致、别的方言、别的检查点——**都不在内**。

红线 `MATCH=64 MISMATCH=0`（L3-b 对冻结基线）在整个 L2-c 期间每一步之后重测，未移动过。

## 2. 折叠怎么做的：一个记录数组一个提交

实施顺序（设计 §6）是被风险形状决定的，不是按大小切的：

| 步 | 内容 | 提交 |
|---|---|---|
| 1–3b | 账本、投毒、C1 类可分配全局、dump 的两处中止 | `e5b99bb` … `1bdbc9c` |
| 4 | B 类记录数组，**一个数组一个提交** | `9478499`（group）`f17b0f8`（prescrib）`b72c3e4`（tcurves）`348376d`（element）`08c989a`（四个 derived 行） |
| 4b | `.tem` 解析器——补上最后一个 reader 缺口 | `9511832` |
| 5a | 填载体，并在 commit 读它之前守住 | `aed4d07` |
| 5b | 最后 60 行；`NOT_MIGRATED` 归零 | `d7d8867` |
| 6 | 释放盲区的仪器与阳性对照 | `81ad7f2` |

**一个数组一个提交**不是流程洁癖：每个记录数组引入的是不同的指针目标形状（一层 / 两层链），
而释放路径的错误（§4）在套件里完全不可见。合并提交会让「哪一个数组带进了哪一处泄漏」不可归因。

### 2.1 两处需要单独说明的实现裁定

**`prescrib` 的对齐前提：拒绝而不是猜。** commit 按位置读 `problem%steps(1)%boundary` 与
`build_runtime` 采纳的 `ndofix`。两者不等长时，无法在不重新推导 dof 编号的前提下知道**哪一条
记录被跳过**。实现选择是发一条点名两个数字的拒绝，而不是取较小者继续。

**`sections.dof_list` 的标签跟随实现，不写 note。** 前提成立时
`active_to_component(1:nfdof)` 与 `1..nfdof` 是同一序列，因此**在该能力门允许的每一个 deck 上**
都不存在能区分「拷贝」与「计算」的断言。这不是夹具的巧合，是按构造不可测。处置：标签跟随
实现（`state` 的定义就是「commit 从哪里读到」，无歧义），不可测性写进提交信息——
**不写 note**（用 note 代替机制正是本任务反复拒绝的做法）。Layer 4 已把这条分诊进 `docs/04`。

## 3. `NOT_MIGRATED = 0` 是账本关于自身的陈述

这一点不因任何攻击被挡而改变。

**步 1 时，把 118 个表项从 `NOT_MIGRATED` 改成 `FROM_RUNTIME`，就得到 `NOT_MIGRATED=0` 且
四个门禁全绿——出口条件被一个谎言满足。** 折叠完成后重跑同一攻击并补了两个方向，三次都被挡：

| 攻击 | 实得 |
|---|---|
| 其余 118 行全翻成 `FROM_RUNTIME` | rc=6，**120 个问题**（多出的 2 由 P8 独立抓到） |
| 单行 `FROM_PROBLEM` → `DERIVED` | 恰好 1 |
| 单行 `FROM_DECK` → `FROM_PROBLEM` | 恰好 1 |

明细与消息在 `docs/m4/L2c-fold-design.md`「出口条件的谎言检测」。

**但这只说明没找到能通过的谎言。** 不等于不存在这样的谎言，只等于攻了三个方向都没进去——
而步 1 时第一个方向就进去了。计数归零的真正作用是：**让影子差分第一次可运行**。判据是影子
差分，不是这个计数。

`commit-inputs` 覆盖门（staging 读到的每个输入叶子都必须在读之前被检查过）现在覆盖
**两个面**（`problem` 与 `residue`）。这道门自己曾犯它要防的错，见 §6。

## 4. 步 6：释放盲区

### 4.1 实质偏离：用的是 ASan，不是 valgrind

设计 §5.4 写的出口条件是「外部内存工具」，实施计划里写作 valgrind。**本机没有 valgrind，
uid 1000 非 root，装不了。** 改用 `ifx -fsanitize=address` 的 ASan/LeakSanitizer，新增
`tools/build.sh` 的 `asan` profile（`81ad7f2`）。

### 4.2 这一步最重要的发现：第一次阳性对照什么都没报

按「先跑阳性对照再谈干净」，故意删掉一处释放后**期望看到泄漏报告，实得一片安静**。
逐项二分后定位：

**Intel OpenMP 运行时库会静默禁用 LeakSanitizer。** 同一个故意泄漏：直接链接 → 报出；
链 MKL 不链 OpenMP → 报出；加 `-qopenmp` → 静默；只加 `-liomp5` 不加 `-qopenmp` → 静默；
`-liomp5` 且显式调用 `__lsan_do_leak_check()` → 仍然静默。`ASAN_OPTIONS=detect_leaks=1`
**不能覆盖**。ASan 本身全程活着（运行时初始化正常、1809 个符号）——**只有泄漏检测那一半死了，
而且不报错**。

处置：`asan` profile 专用的链接参数（顺序版 MKL、不链 OpenMP 运行时、保留
`$HSTAR_IOMP_LIBDIR` 以解析 `libimf`），配一个只在该 profile 下编译的
`tools/asan/omp_stub.c`（`omp_get_max_threads()` 返回 1）。单线程不是这个 stub 引入的
近似：**M0 参考结果本来就是在 `OMP_NUM_THREADS=1 MKL_NUM_THREADS=1` 下跑的**。

**这条本身就是 `docs/07` 那类发现的实例：仪器可以在「关着」的时候表现得像「开着」。**
如果当时没有先跑阳性对照，一片安静会被读成「没有泄漏」。

### 4.3 六个阳性对照

删掉一处内层释放，构建 `runtime-bridge --profile asan`，验证泄漏被报出并归因到正确的分配行。
每次删除都用 assert-guard 脚本（目标文本必须恰好出现一次），每次都在一个钉在 HEAD 的
worktree 里做，跑完丢弃。

| 数组 | 删掉的释放 | 预测归因 | 实测归因 | 记录数 | 套件 |
|---|---|---|---|---|---|
| `props` | `props(i)%mechanical%solid` | `:1100` | `:1100` | 7 | 全绿 |
| `prescrib` | `prescrib(i)%leldofix` | `:1012` | `:1012` | 7 | 全绿 |
| `element` | `element(i)%field(ig)%lnods_f` | `:785` | `:785` | 7 | 全绿 |
| `group` | `group(i)%dof(ig)%listdof_f` | `:927` | `:927` | 7 | 全绿 |
| `listp_group` | `listp_group(i)%listg` | `:973` | `:973` | 7 | 全绿 |
| `tcurves` | `tcurves(i)%ttime_curve` | `:1154` | `:1154` | 7 | 全绿 |

**「套件全绿」是本表的发现，不是噪声**：释放总体性断言一处都看不见。
阴性对照（干净树、同一仪器、当次重测）：rc=0、零泄漏记录、字符串 `LeakSanitizer` 零次出现。

`:1012` / `:973` / `:1154` 是覆盖两三个指针的合并 `allocate` 语句，因此归因定位到**语句**
而非分量；`:785` / `:927` 是单对象语句，定位到分量。此限制在跑之前写下，不是事后补。

lead 独立复核时另挑了 `listp_group(i)%listg` 重跑（不照本清单），`:973` 是唯一被点名的站点。

### 4.4 `prescrib%leldofix` 证明的是什么

它是**一层指针，M3-03 时期就存在**，lead 实测过它在 release 与 MSan 下都全绿。
现在它报出 7 条记录。所以这个盲区**自 M3-03 起就开着，今天第一次可测**——
证明的不只是「新代码的泄漏可见」。

### 4.5 覆盖面（不得放宽）

**21 个内层释放站点里覆盖 6 处，每个数组一处不是每个站点一处，其余 15 处不在结论之内。**
（站点数用 §7 的命令现测；26 个 `deallocate` 减去 5 个容器释放。）

两条仪器限制：

- **LeakSanitizer 只报不可达块。仍被活的模块变量引用的内存对它不算泄漏，无论持有它多么错误。**
  「全局跨 commit 留着一个陈旧句柄」是另一类缺陷，本 profile 按构造看不见。
- `commit_legacy_globals` 没有线程，所以今天不存在这类被线程持有的泄漏可被漏掉；
  **若这一点改变，该 profile 就不再充分。**

第三条，关于两个 profile 的关系：**MSan 与 ASan/LSan 是互为反面，不是互相替代。**
`sanitize` profile 查未初始化读取、永远查不出泄漏；`asan` profile 查泄漏、永远查不出
未初始化读取。**两道门都必须跑。**

## 5. R29 未关闭

`docs/m1/reader-inventory.toml` 的站点 id 与 `src/adapter/**` 里的 `! RD:` 标记之间
**没有机械核对**。因此：

> **任何形如「适配器覆盖了全部读取站点」「这条路径上再无未解析的读取」的断言，
> 目前既无法证实也无法证伪。**

本报告不作任何此类断言。M4-01 关掉的是它的一个**子集**：落在 `model_ready` 比对面上、
有真实比较规则的未覆盖行恰好 4 个，全部源自 `TEM.boundt.*`，由步 4b 的 `.tem` 解析器覆盖。
这是**逐行的**结论，不是覆盖率的结论。关闭条件见 `docs/08-risk-register.md` R29。

同一形状还有一条在 Layer 4 分诊时登记为 **R30**：出处账本里 `PROV_VIA_RUNTIME` 的
「值来自哪个 runtime 量」是**散文，无机械对账**。若有人把实现从「拷贝
`active_to_component`」改成「计算 `1..nfdof`」而不改标签，P6 集合等式照样通过、字节照样
相同、**没有门禁会响**。这是 §3「账本关于自身的陈述」在另一个维度上的同一个限制。

## 6. 本任务中我自己的缺陷

这一节是本报告最有价值的部分。写成可复用的判断，不是谦辞。
方法论层面的一般化已由 Layer 4 分诊进 `docs/04` / `docs/07`（过程见
`docs/m4/L4-findings-backlog.md`）；此处只记指向实现者的那几条，不重复。

**6.1 `nmats` / `nblks` 写进了同名局部变量，而缺陷的形状是两条断言「通过」。**
WRITE 段赋的是局部量，不是 use-associated 的全局量——名字相同，编译器无话可说。
`group_sentinels` 抓到它，靠的是**翻转哨兵的方向**（把这两个从「不该被碰」改成「必须被写」）。
可复用的判断：**在一个 use-associated 全局的作用域里声明同名局部，是一个静默的写入丢失机制。**
（修法就是改名为 `n_materials` / `n_steps`。）

**6.2 一条断言的名字声称了夹具做不到的区分**（`group%matno`）。
更糟的是——**设计 §5.2 早已写下这个风险，写下来并没有阻止它**。
可复用的判断：**风险登记在文档里不构成防护；只有会响的东西才构成防护。**

**6.3 拒绝之后的路径有未定义行为，导致同一份编辑在我和 lead 手里得到不同结果，两个都不是证据。**
commit 被拒绝后套件继续读全局，读到的是未定义内存，「测到了什么」取决于内存布局。
修法是 `skip_landed(site)` 打印一条**可见的 SKIP**——它刻意不是一个 check。
可复用的判断：**一个因为前提未成立而没跑的检查，不能读起来像通过，也不能读起来像失败。**
（`faa6484`；同形的还有 `check_guard_names_match` 断言自身前提，`81525fd`。）

**6.4 覆盖门自己犯了它要防的那个错。** `commit_input_coverage` 原先只把**当前被检面**的检查
子程序从 staging 文本里切掉。而 `opt_is_set(residue%x)` 在正则眼里就是一次对 `residue%x` 的
**读取**——于是**一个守卫的文本会替另一个守卫充当覆盖证据**。修法：切掉**每一个**检查子程序。
可复用的判断：**机制不豁免于它所防的缺陷。**

**6.5 预测未命中，逐次记录，不四舍五入。**

| 预测 | 实得 | 根因 |
|---|---|---|
| `commit-inputs` 53 | 55 | **分母沿用**：拿未重测的基线算增量 |
| SKIP 6 | 7 | **分母沿用**（发生在被指出之后） |
| 断言 985 | 979 | 按新增断言数推算，没算它执行多少次 |
| R2 collateral 8 | 10 | 断言了调用顺序 |
| dialect 检查 +12 | +20 | 同上 |
| landing walk 8 | 7 | — |
| 「adapter 红线必须移动」 | 类别错误 | **对着一个我没查过它数什么的数字做预测** |

前两条是同一根因连续两次，第二次发生在被指出之后。**纪律因此必须改成动作而非记忆：
每次预测之前把分母重新跑一遍再写。** 最后一条是不同的错误：不是算错，是**对一个我并不知道
它在计什么的量发预测**——它天然不可能命中，也不可能有信息量。

**6.6 一次提交里自查出三个测试代码缺陷，三个全部由运行发现，无一由阅读发现**
（哑元未加进参数表、按单 section 规格给逐 section 数组定尺寸、在消息里找一个实际属于
error location 的字段）。

## 7. 复现

**凡是会随后续工作增长的计数，本报告指向命令而不是登记数字。**

```bash
source tools/env.sh

# 三道构建门（每一步之后都跑过）
tools/build.sh runtime-bridge                     # 自检套件 + 交叉核对门
tools/build.sh adapter                            # 红线：MATCH=64 MISMATCH=0
tools/build.sh runtime-bridge --profile sanitize  # MSan：未初始化读取

# 泄漏门（步 6 的仪器；与 sanitize 互为反面，两道都要跑）
tools/build.sh runtime-bridge --profile asan

# 出处账本的行数与分桶（不要抄本文的数）
tools/build.sh runtime-bridge 2>&1 | grep 'provenance entries'
# staging 读取 ⊆ 输入检查
python3 tools/yl_state_map.py commit-inputs

# M4-01 自身判据
python3 tools/yl_shadow_diff.py

# §4.5 的站点分母（26 个 deallocate 减 5 个容器释放 = 21）
sed -n '/subroutine commit_release/,/end subroutine commit_release/p' \
    src/runtime/yl_runtime_commit.f90 \
  | grep -oE 'deallocate \([a-z_]+\(i\)%[a-z_%()]+\)' | sort | uniq -c
```

阳性对照的复现方式：`git worktree add --detach <dir> HEAD`，用 assert-guard 脚本（目标文本
必须恰好出现一次）删掉表中某一处释放，`tools/build.sh runtime-bridge --profile asan
--out <dir> --allow-external-out`，跑完 `git worktree remove`。**不要在工作树里做**——
构建产物与源码修改会互相污染，且并发构建写同一个 `--out` 会损坏模块文件（本任务实测过）。

## 8. 结论

在本报告声明的范围内可以签收的：

- 旧 deck 经新适配器产出的状态，在 `model_ready` 检查点、两个 golden 算例、
  `static-q4-si/1` 契约下与旧路径一致（`MISMATCH=0`）。
- 冻结基线红线 `MATCH=64 MISMATCH=0` 全程未移动。
- `commit_legacy_globals` 保持单一 writer、单次 staging；出处账本对每一行都有条目，
  `NOT_MIGRATED` 桶为空，且三个方向的谎言检测都被挡住。
- 释放盲区从「无仓库内机制」变成「有仪器且仪器已被证明会响」，六个记录数组各有一处阳性对照。

**未建立的**（每一条都是主动声明，不是遗漏）：

- 求解结果等价。影子差分不驱动求解，`UNVERIFIED=56` 就是那两个到不了的检查点。
- `phase_ready` / `increment_ready` 面上的任何结论。
- 白名单之外的 deck、`static-q4-si/1` 之外的契约。
- 21 个内层释放站点里的其余 15 处。
- 「适配器覆盖了全部读取站点」——R29 未关闭，该断言无法证实也无法证伪。
- 「折叠已被验证正确」。**已验证的是 `model_ready` 那一个面。**
