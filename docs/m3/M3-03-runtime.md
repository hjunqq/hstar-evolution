# M3-03：build_runtime 与 commit_legacy_globals

- 日期：2026-09-08
- 范围：ProblemState + 版本化执行契约 → RuntimeState，以及迁移期唯一的旧全局写入口。
  **不含** parse/reader（M4/M5）、求解器推进（`phase_ready` / `increment_ready` 属 M4-01）
- 依赖：M3-02（`6cccf95`）的流水线、错误累积器与 manifest

## 1. 组成

| 模块 | 作用 |
|---|---|
| `yl_runtime_types` | `runtime_state_t` 及成员类型。**无别名分量**：整个文件不出现指针关键字，门禁就是一条 grep。因为分配状态即所有权记录，`runtime_free` 是一次内建赋值即总的 |
| `yl_runtime_contract` | 带版本的执行契约 `static-q4-si/1`。承载 ProblemState 不含的三类前提：D（有序场自由度、场-节点归属、激活策略）、C（冷启动/路径策略）、G（Q4 求积与形函数）。与 `yl_problem_profile` 同构的 `parameter` 表 + 访问器 |
| `yl_runtime_rules` | 可遍历规则表，60 行 = 5 `check` + 46 `derive` + 6 `invariant` + 3 `net`，外加 `(rule_id, input_map_id)` 边表 |
| `yl_runtime_build` | `build_runtime`：只读输入，产出 46 个 `model_ready` 行、值状态账本与派生 manifest |
| `yl_runtime_commit` | `commit_legacy_globals`：迁移期唯一写 `global_var`/`prescribed`/`applied_load`/`meshfine` 的地方。**不接线进求解器** |
| `yl_runtime_selftest` | 108 条断言：B-ok / B-neg / B-cov / T01 / T02 |
| `yl_runtime_bridge_test` | 隔离可执行文件，链接真实 legacy 模块（排除 `Fem.f90`），513 条断言 |

## 2. 契约

```
build_runtime(problem, contract_in, runtime, manifest, errors, declared_ndofix, fail_at)
commit_legacy_globals(runtime, errors)
```

- **无部分提交**，两处都是结构性保证而非注释保证：
  - `build_runtime` 全程建在局部 candidate 上，末尾两个 `move_alloc` 之前的每个子构建都有 errors 计数闸门；
  - `commit_legacy_globals` 分 VERIFY+STAGE 与 WRITE 两段，WRITE 段只有 `move_alloc` 与标量赋值，无分配、无转换、无失败路径。
- `fail_at` 是 **T01 测试钩子**：12 个编号分配点，套件逐个注入并断言先前那个好 runtime 逐位存活、manifest 未增条目。
- `commit_release` 幂等，先释放指针目标再释放数组；`commit_owned` 守卫保证**只释放本模块分配过的存储**。
- 六个记录数组全局（`element` / `group` / `listp_group` / `prescrib` / `tcurves` / `trans`）在 `commit_owned` 为假时若已被分配，**拒绝提交**——见 §7。

## 3. 值状态账本：三种 `ignore` 不是一回事

46 行里 14 行的 `compare.rule = ignore`，冻结基线对它们的值不作断言。但"被排除"有三种互不相同的原因，
把它们混为一谈就是宣称了没证明的东西：

| 状态 | 含义 | 数量 |
|---|---|---|
| `DEFINED`（`built`） | 已计算、可读、可比 | 35 |
| `RESERVED`（`reserved`） | 存储已分配、形状已定，**内容未定义，不得读** | 9 |
| `ABSENT`（`unallocated`） | 本路径上刻意不分配，**缺席本身就是被断言的性质** | 2 |

分配状态能不可伪造地把 `ABSENT` 与另外两者分开，**但分不开 `RESERVED` 与 `DEFINED`**——
"这些字节没有意义"不是数组的结构性质。所以它逐行记在 `runtime%field_status` 里，
并由 `run_nets` 对每个 produced 行断言账本状态 == 规则表 `condition` 列声明的状态。

## 4. 规则集

**实现**（每条都有反例）：B1 受约束节点未附着于任何单元、B2 边界自由度越界、B3 顺时针连通性导致非正雅可比、
B4 重复的 prescribed 对（表内为 B6）、B8 声明 `ndofix` 与派生值不符。

**一处刻意与 legacy 分歧并已写明**：legacy 对解析不出变量号的约束记录静默跳过（契约条目
`boundary.skip_unnumbered_record`）。B1 把其中"受约束节点根本不挂任何单元"单独拎出来拒绝——
legacy 下它的唯一症状是一条悄悄什么也不做的约束。两例 golden 上两者无差异。

**不实现并记入文档**：零雅可比条件（需先有行列式运算）、build 阶段 amplitude 检查（与 V18 重复）。

**不变量的两类可达性**（沿用 M3-02 的区分，后者有失效日期）：

| 类别 | 不变量 |
|---|---|
| 因构造不可达 | `INV-DOF-DENSE`、`INV-NEVAB`、`INV-COMMIT-TOTAL`、`INV-GATED-SHAPE`、`INV-BOUNDARY-ATTACH` |
| 因能力上限不可达（会失效） | `INV-NTOTV-POSITIVE`（注 `review 2026-12-31: fields widen`） |

`B0`：契约标签与本次构建的 `CONTRACT_TAG` 不符即 `INVALID_INPUT`。它**刻意不在规则表里**，
理由与 M3-02 的 `P0` 相同——它守的是这张表本身是否适用，不该要求覆盖走查为它交代。

## 5. 数值保真

Gauss 几何按 legacy 语句逐句复刻，不是按数学等价重写：

- 求积字面量在**默认实精度**求值后加宽。`getgauss` 的 `cnst3` 声明为 `real(irk)`，
  但 RHS `1./3.**0.5` 无 kind 后缀，故在单精度求值（Elements.f90:2352）。契约里是 `real(1./3.**0.5, real64)`。
  4×4 质量规则的 `g1`/`g2`/`w` 同理。**不要"修正"成 real64，除非同时刷新冻结基线。**
- `jacob`（Elements.f90:3245-3253）用显式累加循环，这里也用显式循环，不用 `MATMUL`；
  `gpcod` 用 `SUM` 对应 :1260；`djacb*weigp` 保持该次序（:1363）。两者在末位比特上不同，基线按 rtol 1e-12 比。
- 形函数保持 legacy 的代数形式 `(1-t-s+st)*0.25` 而非因式分解形式：二者精确算术下相等，浮点下不逐位相等。

## 6. 验证记录（2026-09-08）

| 项 | 结果 |
|---|---|
| `tools/build.sh runtime` | 108/108，零告警 |
| 反向双射（`yl_state_map.py runtime-rules`） | 60 rules，46 生产 46 个 model_ready 行，双向 |
| `tools/build.sh runtime-bridge` | 513/513，**结论标注为 PARTIAL** |
| `tools/build.sh problem-types` | 485/485（M3-01/02 回归） |
| 映射表 / ProblemState 交叉校验 / 工具自检 | PASS / PASS / 97-97 |
| 别名门禁 `grep -ni point'er' yl_runtime_types.f90` | 无匹配 |
| 求解器 GNU build-id | `b10f13ba56944d16f857cbe0c70d5943669e01ad`，与 `cded7f4` 一致 |

**探针 47 / 状态探针 4 / 两例 `yl_compare` 未重跑**。理由：求解器二进制逐位相同
（本任务对链入求解器的文件的唯一改动，是 `yl_state_dump.f90` 里一行记录映射表 sha256 的 provenance 注释），
算例输入未动，故探针结果不可能变化。**这是一条论证，不是一次执行。**

## 7. 审查发现：一个病根，七种形态

Round 1 报出 3 Critical + 4 Warning，**全部落在 lead 自己写的 Layer 2 代码里**，两位 Builder 交付的测试文件一条没有。
七条是同一个病根的不同形态：**注释宣称的比代码做到的多**。

| 形态 | 实况 |
|---|---|
| `NET-SNAN` 称"每个 DEFINED f64 行" | 13 行只查 4 行 |
| `NET-EMPTY-RT` 称通用兜底网 | 只查 4 个数组 |
| `verify_registered` 称 TOTAL | 两条 ABSENT 性质只查索引 1 |
| `condition` 列 | 无人校验，已漂 6 行 |
| 两趟附着 | 查了超填没查欠填 |
| `move_alloc` 前提 | "legacy reader 分配的绝不释放"属实，但它改为被**静默泄漏**，未写明 |
| 暂存记录的指针分量 | 49 行 pointer 声明、零默认初始化，只 nullify 了 7 个 → `associated()` 是 UB |

**修法一律是"让代码变强"，不是"把注释改小"**。其中 `NET-SNAN`/`NET-EMPTY-RT` 的修法值得单记：
两张网不再点名行，而是**走账本**——`inspect_row` 逐行报告存储事实，网按状态套用统一规则，
并且**探针不认识的行会让构建失败**。所以"新增 map 行却忘了接线"从此是红，不是悄悄没检查。

### 7.1 Round 2 再发现：清单式守卫漏了第六项

W4 的守卫检查"记录数组已被分配但 `commit_owned` 为假"，但只列了 5 个全局，漏了 `trans`
（`interpolation_group`，含 `listf`/`rintf` 两个指针，走同一个 `move_alloc`）。
**它要防的那个泄漏，在六扇门里仍有一扇敞着。**

加重情节：桥接的 513 条断言里**没有一条碰过这个守卫**。所以漏项不是"测试没测出来"，是根本没测。
处置：补全清单、header 由"记录数组类"改为逐个列名，并要求桥接**用清单驱动遍历六个全局**，
使守卫清单与测试清单发生分歧时能红。

> **方法论自评**：这与 §7 的"点名四行却宣称覆盖全部"是**同一类缺陷**，只是从描述换到了枚举。
> 描述性的宣称（"记录数组"）和枚举式的实现（五个名字）之间的落差，靠读注释发现不了——
> 第一轮我逐条核实了七个发现却没看出这一条，是第二轮换了干净上下文才暴露。
> 结论沿用 M3-02：**通用断言优先于逐例修复；覆盖走查必须能看见自己的证据。**

### 7.2 与 M3-02 的绑定缺陷是同一类，方向相反

M3-02 的教训是 finding 绑到规则**族**而非 `(rule, condition)` **行**，一个反例替十一个条件背书。
M3-03 从另一侧重演了它：规则表在 Layer 1 就写明"这是 raise 点应当传的字符串"是复合键，
Layer 2 的 26 个 raise 点全传了裸族名，于是 `build_rule_exercised` 一个都认不出，
**覆盖走查报 0/5，而每个反例其实都在正确触发**。一个看不见自己证据的护栏，比没有护栏更糟——
它读起来像是测试有缺口，而不是绑定有缺陷。

处置是表驱动的 `raise_row`：复合键、object、field、code 全部从表里读，**调用点已无法拼错四元组**。

## 8. 明确未证明

- **与冻结基线的逐值比对未执行**。B-ok 的"32 项逐值一致"与 Bridge 的"选定字段与基线一致"都需要
  真实 golden 网格的 `problem_state_t`，而仓库里**没有任何 deck → ProblemState 的通路**
  （M3-02 的 fixture 是缩到 1 个 Q4 的结构等价体，不是 256 单元的 Cook 网格）。该适配器属 **M4-01**。
  本任务因此**没有任何一行的值与 M2 冻结基线比对过**。
- **求解器等价性**：属 M4-01，本任务不涉及。
- **用后释放与泄漏**：进程无法观测自己的泄漏。需要 ASan/valgrind 目标与 shell 层比对，本任务**未做**。
- **14 个 ignore 行的值正确性**：快照不覆盖，本任务也不覆盖。
- **`NET-SNAN` 的强度分档**：`release` 下未初始化内存只有碰巧是 NaN 才被抓（**弱检查**）；
  `strict` 下 `-init=snan,arrays -fpe0` 使信号 NaN 作为比较操作数触发 invalid，
  进程**中止而非返回 finding**——调用方不应指望在 `errors` 里看到它。两种都不静默，但差别必须写明。
- **`INV-BOUNDARY-ATTACH` 的欠填半边当前不可达**：上游 V6 已拒绝单元内重复节点 id，那是唯一能让
  去重后计数短缺的网格形状。它被正确地标为因构造不可达，是防御性检查而非可触发规则。
- **本轮审查未经外部模型交叉验证**：codex 在裸连通性探针上即以 `codex_models_manager` 超时失败
  （与 2026-09-07 M1-03 同一故障）。改用两个干净上下文、视角不重叠的 Claude reviewer 替代。
- **Fortran 侧无自动化质量/安全门禁**：CCG 的 `verify-quality` / `verify-security` 对 `src/runtime`
  **扫描 0 文件**——它们不识别 `.f90`。这约 5000 行的质量保证实际来自编译器 `-warn all -stand f18` 零告警、
  621 条自检、反向双射校验与人工审查。**该缺口属工具链，非本次改动引入**；已登记为后续任务。

## 9. 依赖登记

- **M4-01 折叠 commit**：`element(:)` 在本模块是**整体重建**而非就地打补丁。M4-01 加入 ProblemState 那一半时，
  必须把两半**折叠进同一次 staging**，不能加第二个 writer——那会重新引入本模块存在的理由所要消灭的部分提交状态。
- **restart 一旦被接纳**：`runtime.cursor.lineload` 需要真实来源，其 manifest `check` 条目须停止空判。
- **能力门放宽 section 数或场数**：D 类契约条目需逐条重新决定，不能翻一个布尔了事。
