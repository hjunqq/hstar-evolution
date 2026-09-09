# M4 L2-c 折叠设计的对抗性复核 —— `docs/m4/L2c-fold-design.md`

> 本文是**复核记录**，不是设计也不是实施。复核者没有参与该设计的写作。
> 复核期间未改动任何源文件；本次唯一新增的文件是本文。
> 所有数字由 `docs/m2/state-field-map.toml` / `src/state/yl_state_{dump,adapters}.f90` /
> `src/runtime/yl_runtime_{commit,bridge_test}.f90` 程序化枚举或逐行阅读得到（命令见 §7），
> 不是估算。凡我没能验证的，本文写"未验证"，不写"应当如此"。

## headline

| 复核项 | 结论 |
|---|---|
| §1 的行清单与五类分组（A10 / B37 / C1 21 / C2 46 / D2 + 14 个 `not_migrated`） | **完全复现**，一行不差 |
| §headline / §2 的后果切分 **59 / 59 / 2** | **不复现**。正确值是 **24 / 5 / 89 / 2** |
| §6 步 2 的通过判据"第一次产出完整的 162 行快照" | **不成立**。dump 会继续在 `mesh.elements.nodes` 中止 |
| §3 的"9 个调用点" | 实际 **8**；且同文档 §3推荐②/§6步1 写"2 个调用点"，自相矛盾 |
| 折叠能否静默打破 L3-b 全绿的行 | **能**。找到 4 行结构性盲区，见 §2 |
| §5.1 的"把名单改成构造" | **不能**让三处无法漂移，只把三份名单压成两份，且漏掉风险更高的一半 |
| lead 对 14 个 `not_migrated` 行的决定 | 方向对，**给出的理由是错的**；且有一个未被发现的前置阻塞（map 自身矛盾） |

**判定：须修改后实施。** 主干推翻不了（我试过，见 §6）；但上表中标粗的四项必须先改。

---

## 1. §2 的 59 / 59 / 2 不复现，正确值是 24 / 5 / 89 / 2

### 1.1 根因：B 类的宿主记录**今天已经被 commit 分配**，所以容器级守卫不会触发

`src/runtime/yl_runtime_commit.f90:372-376` 今天就 `move_alloc` 了 `element`、`group`、
`prescrib`、`tcurves`。而 `yl_state_dump.f90` 对 B 类绝大多数行的守卫是**容器级**的
——`if (.not. allocated(group)) call state_fail(...)`——容器已分配，守卫不触发。

守卫放行之后 dump 读的是**记录内未被赋值的标量分量**。`group_of_elements`
（`legacy/yl/Global.f90:234-261`）、`unode_elements`（:263-271）、`freedom_prescribe`、
`time_curve` **没有任何默认初值**；`null_group`（`yl_runtime_commit.f90:648-653`）只
nullify 指针并置 `np_unode = 0`，`nelgroup` / `matno` / `nrfields` / `nstre` / `kname` /
`name` / `class` / … 一概不写。

**所以 B 类的 37 行绝大多数落在"未定义初值被当作状态发出"，而不是"dump 中止"。**
设计把整个 B 类记进中止桶，是把"容器有守卫"误当成"分量有守卫"。

### 1.2 B 类 37 行的逐行后果

**确定性中止（2 行）**

| 行 id | 守卫 | 为什么必中止 |
|---|---|---|
| `mesh.elements.nodes` | `yl_state_dump.f90:135` | 无条件 `associated(element(1)%field(1)%lnods_f)`；commit 在 `:622` 把 `lnods_f` nullify 了 |
| `sections.material_header` | `yl_state_adapters.f90:272-278` | `ne = group(g)%nelgroup` 后是**无条件**的 `if (ne < 1) state_fail`；ne≥1 则下一句 `associated(group(g)%list)` 失败。两条路都中止 |

**不确定 —— 中止 *或* 静默发一条空记录（5 行）**

| 行 id | 位置 | 形状 |
|---|---|---|
| `mesh.sets.elset` | `yl_state_adapters.f90:376-388` | `ne = group(g)%nelgroup` |
| `sections.dof_count` | `:300-308` | `nf = group(g)%nrfields` |
| `sections.dof_list` | `:334-353` | `nf = group(g)%nrfields`，再 `nd = group(g)%dof(f)%nfdof` |
| `amplitudes.points.time` | `:465-472` | `nt = tcurves(c)%ntime` |
| `amplitudes.points.value` | `:498-505` | `nt = tcurves(c)%ntime` |

五处是同一个代码形状：

```fortran
n = <未定义的标量分量>
call need_count(w, id, '...', n)          ! n < 0  -> 中止
if (n > 0_ink) then                        ! n > 0  -> associated 检查失败 -> 中止
  if (.not. associated(<指针>)) call state_fail(...)
  ...
end if
call begin_field(w, id, ..., [int(n, int64)], ...)   ! n == 0 -> 发一条长度 0 的记录，不中止
```

**`n` 恰好为 0 时不中止，发出一条空记录。** 这既不是"中止"，也不是设计所说的
"未定义值被发出"——它是一条**看起来结构完好、长度为 0 的记录**，会直接进入差分，
在 `ngroup`/`ntcurve` 恰好也让它对上时可能被记成 MATCH。而且它**跨运行不稳定**：
同一份代码两次运行可以一次中止一次不中止。

这一点值得单独强调：设计 §2 的整个论证是"未定义值比错值更糟，因为不可复现"。
这 5 行把不可复现性升级了一级 —— **连失败模式本身都不可复现**。设计的二分法在它们身上不成立。

**纯未定义值（30 行）** —— `group` 的 18 行（`sections.{element,name,element_kind,class,
fields,special,formulation,elset_size,material,type_nalgo,type_stiff,type_ecoint,ilayer,
elcod_local,uplift_ic,liquj}` + `derived.counts.{nrfields,nstre}`）、`element` 的 3 行
（`mesh.elements.{kind,group,material}`）、`prescrib` 的 7 行、`tcurves` 的 2 行
（`amplitudes.points.count`、`amplitudes.type`）。

### 1.3 修正后的 §2 表

| 不写的后果 | 行数 | 组成 |
|---|---|---|
| `yl_state_dump` 中止（确定） | **24** | C1 21 + `control.glb.uinitial` 1 + B 类 2 |
| 中止 **或** 静默发空记录（不确定） | **5** | B 类 5 |
| 未定义初值被当作状态发出 | **89** | C2 46 + 13 个 `not_migrated` 标量 + B 类 30 |
| 无事发生 | **2** | D 类 |
| | **120** | |

设计的定性结论（折叠必须全覆盖）**不受影响，反而更强**：落在"未定义/不稳定"桶里的
从 59 涨到 94。错的只是切分本身，以及下面这条依赖它的实施判据。

### 1.4 直接后果：§6 步 2 的通过判据不成立

步 2 只写 C1 的 21 行 + `uinitial`，即 24 个确定性中止里的 22 个。
剩下 2 个（`mesh.elements.nodes`、`sections.material_header`）属 B 类，排在步 3。
所以步 2 之后 dump **仍然中止**，只是中止点从 `coord`（`yl_state_dump.f90:119`）
移到 `element%field(1)%lnods_f`（`:135`）。

- §6 步 2 的通过判据"**这一步第一次让新路径产出完整的 162 行 `model_ready` 快照**"是假的；
- 检查点 ★ 的第 3 条（"影子差分首次跑出完整快照，且没有一行是 MISMATCH"）在步 2 **无法执行**。

改法二选一：把检查点 ★ 后移到步 3 之后；或把 `mesh.elements.nodes`（`element%field%lnods_f`）
与 `sections.material_header`（`group%list` + `group%nelgroup`）从步 3 提到步 2。
后者更符合设计自己"检查点要能真跑一次差分"的意图，代价是步 2 要碰 `element`/`group` 记录。

---

## 2. 最危险的发现：4 行 `emit = "none"` 的 `RuntimeState` 分量是结构性盲区

这是 lead 问题 2 的答案：**能**，而且不需要任何巧合。

### 2.1 盲区的构造

`model_ready` 的 46 个 `RuntimeState` 行里有 **14 行** `emit = "none"` + `compare.rule = ignore`
（`tools` 的 R3/R5 与 L3-b 的 28 个 `NOT_COMPARABLE` 说的就是它们，28 = 14 × 2 案例）。
它们**由 commit 写入，却永远不进快照** —— `tools/yl_shadow_diff.py` 结构上看不见它们。

于是这 14 行的唯一防线是 `src/runtime/yl_runtime_bridge_test.f90` 对**提交后全局值**的断言。
我逐个查了这 14 行，其中 **4 行没有任何这样的断言**：

| map 行 | 旧全局 | commit 写在哪 | bridge_test 断言 |
|---|---|---|---|
| `runtime.topology.unode_np_unode` | `group%unode%np_unode` | `yl_runtime_commit.f90:306`（置 0） | **无** |
| `runtime.topology.unode_patch_nod` | `group%unode%patch_nod` | `:659` `null_unode` nullify | **无** |
| `runtime.cursor.lineload` | `global_var.lineload` | `:204` / `:353`（置 0） | **无**（连 `use` 都没有） |
| `runtime.cursor.linet` | `global_var.linet` | `:205` / `:353`（置 0） | **无** |

其余 10 行（`djacb_mass`、`gpcod_mass`、`elcod_f`、`tload`/`eload`/`rload`、`delitfi`、
`deltafi`、`line_load_block`、`line_temp_block`）在 `yl_runtime_bridge_test.f90:419-463`
有对全局值的断言，**覆盖到了**。

### 2.2 三个"看起来有守卫"的守卫都守错了对象

1. **`yl_runtime_bridge_test.f90:472`** 断言 `group(ig)%np_unode == size(...)`。
   那是 `group_of_elements` 自己的 `np_unode`（`Global.f90:236`），
   和 `unode_elements%np_unode`（`Global.f90:265-267`）**同名不同物**。
   `:475-483` 只断言 `unode%ipoin`、`%ne_unode`、`%list`。
2. **`yl_adapter_bridge_test.f90:458`** 的
   `check_ledger(cn, ulog, rt, 'runtime.topology.unode_np_unode', RUNTIME_VALUE_ABSENT)`
   断言的是 **runtime 的账本**，不是提交后的全局。
3. **设计 §5.2 点 1 自己指出的守卫**：`verify_registered` 在
   `yl_runtime_commit.f90:565` 检查 `allocated(runtime%topology%sections(i)%nodes(j)%patch_nodes)`
   —— 同样是 **runtime 侧**。它拒绝一个"分配了 patch_nodes 的 runtime"，
   **它管不到 commit 往 `group%unode%patch_nod` 里放了什么**。

### 2.3 具体的静默破坏场景

步 3 折叠 `group` 的 21 个分量时，需要重写 `yl_runtime_commit.f90:290-308` 那段
`s_group` / `unode` 循环。只要这次重写丢掉 `call null_unode(...)` 或 `%np_unode = 0_ink`
（设计 §5.2 自己写的"很容易顺手动到它"），结果是：

- `group%unode%patch_nod` 成为**未定义指针**（不是 null，是未初始化的位模式）
- `group%unode%np_unode` 成为未定义值
- `yl_runtime_bridge_test`：**全绿**（不断言这两个）
- `yl_runtime_selftest`：**全绿**（走的是 runtime 侧）
- `tools/yl_shadow_diff.py`：**无变化**（`emit = none`）
- L3-b 的 64 行：**仍然 MATCH=64 / MISMATCH=0**

`commit_release`（`:422-427`）只 `deallocate (group(i)%unode(ig)%list)`，不碰 `patch_nod`
——今天这是对的（它是 null），此后就是一个**未定义指针留在全局里**。
legacy 侧任何 `associated(patch_nod)` 都是未定义行为，而 `null_group` 自己的注释
（`yl_runtime_commit.f90:642-645`）点名的正是这个危险：
*"an unset bit pattern there is exactly the same undefined `associated()` hazard as any other component"*。

**这与模块头记录的 `trans` 缺陷是同一类：一道守卫覆盖的对象不是它声称覆盖的对象。**
区别是 `trans` 那次至少还有 §6 的消息解析在事后把它逼出来；这次连解析都没有。

### 2.4 必须补的东西（阻塞步 3）

在动 `group` 之前，`yl_runtime_bridge_test` 要补上对**提交后全局**的断言，至少覆盖上表 4 行：
`group%unode%np_unode == 0`、`.not. associated(group%unode%patch_nod)`（以及
`patch_sta`/`patch_load`）、`lineload == 0`、`linet == 0`。
并且这张"`emit = none` 的 14 行 → 谁断言它"的对照表应当写进设计，
因为它正是 §4 的出处账本**无法覆盖的那一部分**（账本按 map 的发出行建表，
这 14 行不在发出行里）。

---

## 3. 释放路径：§5.1 的"构造"提案只压掉三分之一的漂移面

lead 问的是"真的让三张名单无法漂移，还是只是请实现者保持同步"。答案偏向后者。

**1. 探针表本身仍是手抄名单。** `[allocated(element), allocated(group), ...]` 要人写。
Fortran 没有反射，`move_alloc(s_X, X)` 必须字面写出名字对，**无法由表生成**。
加第八个可分配全局时，表和 `move_alloc` 段仍然要人同时改。提案把三处压成两处，是改进，
但"三处一起变或一处都不变"这句话本身不成立。

**2. 更关键：`commit_release` 根本不是一张扁平名单。** 它是一次嵌套的指针目标遍历
（`yl_runtime_commit.f90:397-448`）：

```
element%field%{ldofs_f, elcod_f, tload, eload, rload}
element%egaus%{djacb, gpcod, cartd}
element%ldofs
group%unode%list
listp_group%{listg, listp}
prescrib%{leldofix, levdofix, lefdofix}
```

一张全局**名字**表表达不了这个结构。而泄漏恰恰住在这一半 —— 模块头自己讲得很清楚：
`move_alloc` 释放数组、**泄漏挂在上面的指针目标**。设计 §5.1 把"8 个可分配全局"和
"至少 8 类新指针目标"并列写出来，"构造"方案却只覆盖前者；**后者仍然是"请实现者保持同步"**。
`props(i)%mechanical` / `props(i)%mechanical%solid` 这条两级链（C1 类 15 行）
会把这块没有机制覆盖的面积再放大。

**3. 现成的守卫也不覆盖 `commit_release`。** §5.2b 提到的
`check_guard_names_match` 只把 **W4 拒绝消息**与测试自己的 `NAMES` 绑在一起
（`yl_runtime_bridge_test.f90:703-`）。一个全局加进了 W4 名单和 `move_alloc` 段、
**忘在 `commit_release` 里**，W4 解析照过、T02 重复提交在进程内也看不出来
（模块头："a process cannot observe its own leaks"），全部测试通过。

**4. 检查点 ★ 第 2 条"逐个 grep，不看描述"是人工复核，不是机制。**
它和当年让 `trans` 溜过去的那一步是同一种东西。

**建议（不阻塞，但应写进设计）**：明说"构造"只覆盖可分配全局那一半；
指针目标那一半没有仓库内机制，唯一的检查是外部工具。
因此设计 §5.2 末尾"建议把 valgrind/ASan 从待办提升为出口条件"**不是建议，
是这条路线成立的必要条件** —— 我同意这个提升，并认为它的措辞应当加强。

---

## 4. 对 lead 关于 14 个 `not_migrated` 行的决定的攻击

lead 的方向（不改 map、写值、账本打标签）我认为是对的：
plan 禁止项 5 明确禁止改变哪些 key 参与快照，而且 `uinitial` 是硬阻塞，不写就没有快照。
**但 lead 给出的理由是错的，而错的理由会让实现走偏。** 三点。

### 4.1 这 14 行不是"legacy 默认值"，是**牌面输入字段**

lead 的表述是"map-recorded legacy defaults ... each value sourced to the legacy line that sets it"。
map 里没有这个东西。我枚举了 14 行的 `source`，**全部指向 deck 读入字段**：

| 行 | `source` |
|---|---|
| `control.run.{restart,relis,adina}` | `INP.FEM90.run_control` |
| `control.glb.{nlayer,state_change,bparameter}` | `GLB.global_data.problem_type` |
| `control.glb.{block_stab,nbackf,ebody,ninit,nlinks}` | `GLB.global_data.init_and_blocks` |
| `control.glb.uinitial` | `GLB.global_data.uinitial` |
| `control.glb.stab_matde` | `GLB.global_data.sizes_and_switches` |
| `control.glb.ntrans` | `GLB.global_data.transform_and_mif` |

`stab_matde` 的 note 甚至写明了字段位置："1.glb record 2, field 15"。
map 的 `reason`/`note` 记的是**消费点**（`Fem.f90:xxxx` 的 guard）和
**两个 golden deck 上观察到的值**（"0 on both golden cases"），
**不是赋值点**。唯一带分配点的是 `uinitial`（`Global.f90:965`），而那是 `allocate`；
值来自 `:1093` 的 `read(gunit,*) uinitial(1:nblks)`。

**所以：往这 14 个全局写常量，就是用硬编码值替换牌面提供的输入。**
回答 lead 的原话："is writing a value the deck never supplied a violation" ——
问题问反了：deck **供了**这些值，是新路径没有读它们。
这不改变"必须写"的结论（不写就没快照），但它改变了这件事该被叫什么：
不是"补一个默认值"，是**在两个 golden deck 上把观察到的值钉死进 commit**。
设计和实现都必须这么写，否则第三个 deck 上会有人以为这里有依据。

### 4.2 打 `DEFAULTED` 标签**不能**防止它被当成迁移证据，只是把问题换了个形状

lead 问"tagging it in the ledger actually prevent it from being read later as migrated evidence,
or does it just move the problem"。答案是**移动了问题**，而且移到了一个更暗的地方。

今天这 14 行进不了 MATCH 桶 —— 因为 dump 在 `coord` 就中止了，快照根本产不出来。
这是一次**响亮的失败**。折叠之后打上 `DEFAULTED`，它们进 `NOT_MIGRATED` 桶 ——
一个按设计**不被任何 STOP RULE 看的桶**。在第三个 deck 上 `stab_matde = 3`
（map 自己说 `stab_matde > nblks` 才是被支持的条件），新路径写常量、
差分把它归入 `NOT_MIGRATED`、没有人看到红线。**静默豁免比静默假绿更难发现**，
因为假绿至少还在 MATCH 计数里，豁免连计数都不在。

要让标签真的起作用，`NOT_MIGRATED` 桶必须是**封闭**的：
桶里的行 id 集合必须逐字等于生成的那张 14 行清单，**多一行或少一行都让差分失败**。
设计 §4.3 只说"记为第五个桶 `NOT_MIGRATED`，既不算 MATCH 也不算 MISMATCH"，
没有说这个桶封闭。这是必须补的一句，而且它和 §4.3 第 3 点的"总体性闸门"是同一条理由。

### 4.3 前置阻塞：map 在这 14 行上有一处硬矛盾，正好落在设计引用的那一行

`docs/m2/state-field-map.toml:157`，`control.run.restart` 的 `note` 是一整段
**关于 `stab_matde` 的**更正文字：

> "CORRECTED 2026-09-08 (M4-01 integration): ... Both golden decks carry 99999
> (1.glb record 2, field 15) ... 99999 is a disable sentinel.
> The supported condition is `stab_matde > nblks`, not `stab_matde == 0`."

而这一行自己的 `reason` 仍然是 "guard switch outside the static_2d slice; **pinned 0** on both
golden cases"，并且 **`restart` 这一行现在没有任何关于 `restart` 的 note**。

与此同时，`control.glb.stab_matde`（`:1871`）自己的 `note` **仍是被上面那段更正宣布为错的旧文字**：

> "with stab_matde=0 and iblks=1 the condition is TRUE, so stab_initialize (:2342-2376)
> runs every step ..."

也就是说 2026-09-08 的更正（提交 `022674f`）**打在了错误的行上**。

对设计的直接后果：§1.6 方案 (i) 的取值规则是"取值来自 map 每行自己的 `reason`/`note`
记录的 legacy 默认值"。按这条规则：

- `control.glb.stab_matde` 会读到**两个互相矛盾的答案** —— `reason` 说 99999，`note` 说 0；
- `control.run.restart` 会读到一段**与 restart 无关**的文字。

**在这处更正被修好之前，方案 (i) 没有可执行的取值来源。**
这是 lead 决定的一个前置条件，不是实现细节，而且它只能由 map 的所有者修
（复核者是 source 只读的）。

顺带：设计 §1.6 说 "`control.glb.stab_matde` 在两个 deck 上都是 **99999**（map 的 note：一个禁用哨兵）"
—— 那段文字在 `restart` 的 note 里，不在 `stab_matde` 的 note 里。设计引对了值、引错了位置。

---

## 5. 声称但未验证的项

| # | 设计里的说法 | 复核结果 |
|---|---|---|
| E1 | §4.3：行清单表"与 dump 同源同 sha256 标注"，以此防漂移 | **这个标注现在就是漂的，而且没有闸门看它。** HEAD 的 `docs/m2/state-field-map.toml` 整文件 sha256 = `5224c8aa06f7`（`tools/yl_state_map.py:1307` 对整文件取哈希），而 `src/state/yl_state_dump.f90:4` 写的是 `8ec26e625672`。HEAD 提交 `cded7f4` 的信息正是 "regenerate the state dump so its provenance line matches the map" —— 它没有做到。`tools/build.sh` 不校验这一行。生成的**代码**本身很可能一致（`022674f` 只改了两处 note），我没有重跑生成器去证明，**记为未验证**；但"标注即权威"这个前提已被证伪 |
| E2 | §3：签名变更"9 个调用点，3 个文件（shadow 1 / adapter_bridge_test 2 / runtime_bridge_test 6）" | 实际 **8 个**：`yl_adapter_shadow.f90:114`、`yl_adapter_bridge_test.f90:204`、`yl_runtime_bridge_test.f90:{131,550,617,647,675,721}`。`yl_adapter_bridge_test.f90:18` 是注释，不是调用点。文件数 3 正确 |
| E3 | §3 推荐②与 §6 步 1 都写"**2 个**调用点" | 与同文档 §3 表的 9 自相矛盾，与实际的 8 也不符。按"2 个"执行会漏 6 处、编译不过。步 1 的通过判据要改 |
| E4 | §5.2 点 1：`verify_registered` 会拒绝一个分配了 `patch_nodes` 的 runtime | 这句**本身为真**（`yl_runtime_commit.f90:565`），但被当作折叠 `group%unode` 时的守卫使用，而它守的是另一个对象。见 §2.2 |
| E5 | §5.1："8 个可分配全局" | **复现**：`coord`、`props`、`appear_process`、`matno_process`、`average_appear`、`factg`、`tcurvegravity`、`uinitial` |
| E6 | §1.6：`uinitial` 是 allocatable、`Global.f90:186-187` 声明、`:965` 分配、dump 在 `yl_state_dump.f90:491` 有守卫 | **全部复现**（声明在 `:187`，读在 `:1093`） |
| E7 | §5.3：`appear_process(1:ngroup, 0:nblks)`，列 0 参与比对 | **复现**：`yl_state_adapters.f90:815-817` 显式断言 `lbound(...,2) == 0`，`:823` 从 `b = 0` 起遍历 |
| E8 | §1.2 的 A/B 记账差异（本文 10 行 vs L3-c 的 8 行） | **本文的 10 是对的**。`derived.dof.active_flags` 与 `derived.dof.lcdofn` 分别读 `lmdofn` / `lcdofn(1:cdofn)`，两者由 `yl_runtime_commit.f90:355-356` 的 `move_alloc` 写入。设计主动标出这处差异并把两个数都写下来，是本文档处理得最好的一段 |

---

## 6. 我试图推翻但没能推翻的部分

为免"没有发现"被读成"没有尝试"，逐条记下：

1. **五类分组的行清单。** 我用 map 独立重算了一遍（按 `legacy_symbol` 基名 × commit
   今天 `move_alloc`/赋值的全局集合分组），得到：已分配容器上的发出行 79，
   其中 `RuntimeState` 32、其余 47；47 减去完全写好的 A 类 10 = **37**，与 B 类吻合。
   未触碰全局上的发出行 83，减 D 类 2 = 81 = C1 21 + C2 46 + `uinitial` 1 + 13 个
   `not_migrated` 标量。**一行不差。** 这是设计最扎实的部分。
2. **"今天已有写入者 42"。** 32（发出的 `RuntimeState` 行）+ 10（A 类）= 42，复现。
   注意 46 个 `RuntimeState` 行里只有 32 个 `emit ≠ none`，L3-b 的 64 = 32 × 2 与此一致。
3. **否决选项 B 的理由。** R3 的判据、R5 + `verify_registered` 的计数等式、
   `yl_runtime_types` 的 `@map` 双射，三道闸门都在，B 确实要同时改三处判据。
   （R3 的行为 lead 已独立核过，我未重复。）
4. **"账本的轴是出处而不是写没写"。** §1 的修正让这一条更成立：
   94 行落在"未定义或不稳定"桶里，"写没写"确实不是自由变量。
5. **`element%matno` / `sections.material_header` 的雷**（§5.2 点 1 第二条）。
   `yl_state_adapters.f90:370-373` 的注释与 map 的说法一致，
   两者在 golden deck 上相等因而错了也看不出来 —— 这个观察是对的，我没能反驳。
6. **extent 的第二个推导源**（§5.2 点 2）与它给出的规则（extent 仍只从 runtime 推、
   ProblemState 侧只许断言一致）—— 我认为这条规则是对的，而且检查点 ★ 第 5 条
   给了可 grep 的判据，是设计里少数几处真正可机检的地方。

---

## 7. 复现本文每一个数

```bash
cd /home/huijun/HSTAR_Next/hstar-evolution

# §6.1 五类分组的独立重算（79 / 47 / 37 / 83 / 81）
python3 - <<'EOF'
import tomllib, collections
d = tomllib.load(open('docs/m2/state-field-map.toml','rb'))
f = [x for x in d['field'] if x['checkpoint']=='model_ready']
e = [x for x in f if x.get('emit')!='none']
written = set("lmdofn lcdofn nodfn iffix fixed appear result_zero tofor stfor toforl toform "
              "delitfi deltafi line_load_block line_temp_block ice0 trans element group "
              "listp_group prescrib tcurves npoin nelem ngroup ndimn mdofn cdofn ntotv "
              "ndofix ntcurve iblks lblks".split())
base = lambda s: s.split('.',1)[1].split('%')[0].split('(')[0] if '.' in s else s
on  = [x for x in e if base(x['legacy_symbol']) in written]
off = [x for x in e if base(x['legacy_symbol']) not in written]
print('emitted', len(e), '| on-container', len(on), collections.Counter(x['owner'].split('.')[0] for x in on))
print('off-container', len(off))
EOF

# §4.1 14 行 not_migrated 的 source 全部是 deck 读入字段
python3 - <<'EOF'
import tomllib
d = tomllib.load(open('docs/m2/state-field-map.toml','rb'))
for x in d['field']:
    if x['checkpoint']=='model_ready' and x['owner'].split('.')[0]=='not_migrated' and x.get('emit')!='none':
        print(f"{x['id']:32s} {x['source']}")
EOF

# §4.3 更正打错了行
sed -n '141,157p'   docs/m2/state-field-map.toml   # control.run.restart 的 note 讲的是 stab_matde
sed -n '1871,1890p' docs/m2/state-field-map.toml   # stab_matde 自己的 note 仍是被更正宣布为错的旧文字

# §5 E1 provenance 已漂
git show HEAD:docs/m2/state-field-map.toml | sha256sum | cut -c1-12   # 5224c8aa06f7
git show HEAD:src/state/yl_state_dump.f90  | sed -n '4p'              # ... sha256 8ec26e625672
grep -n 'hashlib.sha256(map_path.read_bytes())' tools/yl_state_map.py # :1307 整文件哈希

# §5 E2 实际调用点 8 个
grep -rn 'call commit_legacy_globals' src/

# §1.2 五处"中止或静默发空记录"的代码形状
sed -n '272,278p;300,308p;334,353p;376,388p;465,472p;498,505p' src/state/yl_state_adapters.f90

# §2.1 四行盲区：commit 写了、emit=none、bridge_test 无断言
grep -n 'np_unode\|patch_nod\|lineload\|linet' src/runtime/yl_runtime_commit.f90
grep -n 'unode\|lineload\|linet\b'             src/runtime/yl_runtime_bridge_test.f90

# §1.1 legacy 记录类型没有默认初值
sed -n '234,271p' legacy/yl/Global.f90
```

---

## 8. 判定与必改项

**判定：须修改后实施。**

设计的主干我尝试推翻但没能推翻：方案 A 的选择、折叠必须一次全覆盖、账本的轴是"出处"、
最大风险在释放路径而不在 46 行回归 —— 这四条都站得住，且 §1 的行清单逐行复现。
选项 B 的否决理由是实的。设计主动标出与 L3-c 的记账差异并把两个数都写下来，是好的做法。

必须改的四处（按阻塞程度排序）：

1. **§2 的 59/59/2 → 24/5/89/2，并把那 5 行"中止或静默发空记录"的不确定行单列。**
   连带 §6 步 2 的通过判据与检查点 ★ 第 3 条必须改 —— 步 2 之后 dump 仍会在
   `mesh.elements.nodes` 中止。要么把检查点后移到步 3 之后，要么把
   `mesh.elements.nodes` + `sections.material_header` 提到步 2。
2. **在折叠 `group` 之前，补上对 `group%unode%{np_unode,patch_nod,patch_sta,patch_load}`
   与 `lineload`/`linet` 的 bridge_test 断言 —— 断言提交后的全局，不是 runtime 的账本。**
   并把"14 个 `emit = none` 的 `RuntimeState` 行 → 谁断言它"这张对照表写进设计，
   因为出处账本按发出行建表，结构上覆盖不到这 14 行。
3. **§1.6 方案 (i) 的两个前置条件**：(a) 先修 `state-field-map.toml:157` 那处打错行的
   更正（map 所有者的事）；(b) `NOT_MIGRATED` 桶必须封闭 —— 行 id 集合逐字等于生成的
   14 行清单，多一行少一行都让差分失败。并把这 14 行的性质如实写成
   "在两个 golden deck 上钉死的牌面输入值"，不是 "legacy 默认值"。
4. **§3/§6 的调用点数字统一为 8**，步 1 的通过判据跟着改。

非阻塞但应写进设计：§5.1 的"构造"提案要明说它只覆盖可分配全局那一半，
指针目标遍历那一半仓库内没有机制；因此 §5.2 末尾把 valgrind/ASan 提为出口条件
**不是建议而是必要条件**，措辞应当加强。
