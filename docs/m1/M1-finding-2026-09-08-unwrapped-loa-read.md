# M1 发现：一处已执行但未登记、未包装的读取（`Load.f90:231`）

- 日期：2026-09-08
- 发现途径：M4-01 的 `.loa`/`.pre` 解析器作者忠实复刻读取序列时，发现该语句**在 reader 清单里没有 id**
- 影响：**M1-01 与 M1-02 的可签结论**（两者此刻都在等负责人签字）
- 状态：已核实，`Load.f90:231` 本身已修复并数值核验（见"修复"节）。取证过程中另发现一个
  更深的工具根因（断点生成器"一行一地址"假设），**尚未修复**——见"工具根因"节；
  M1-01/M1-02 的签收结论仍需据此重新评估。

## 事实

```fortran
! legacy/yl/Load.f90:230-232（external_load_1）
elseif (type_curve/='ARCLENGTH'.and.type_curve/='EXTRAPOLATION'   &
    .and.type_curve/='HARMONIC'.and.type_curve/='WATERLEVEL') then
 read(loadunit,*)tcurves(itcurve)%dfact_curve(1:ntime) !!one record
endif
```

| 检查 | 结果 |
|---|---|
| 在 `docs/m1/io-sites.json`（1022 静态全集）里 | **在**，`Load.f90:231` |
| 在 `reader-inventory.toml` 的 152 条 reader 里 | **不在**（清单从 `Load.f90:220` 直接跳到 `:239`） |
| 有 `call diag_check_read` 包装 | **没有** |
| 在 gdb 实证命中集（两例各 211 位点）里 | **不在** |
| 两个 golden 算例的 `type_curve` | `LINEAR` |

## 它确实执行了——反证

`1.loa` 的曲线段落：

```
 2  LINEAR  0  2      <- ntime=2, type_curve=LINEAR
 0  1                 <- 两个时间值
 1  1                 <- 两个系数值
 Define point load    <- title#2
```

- `Load.f90:220` 读 `ttime_curve(1:2)`，消费 `0 1`
- `Load.f90:239` 读 title#2，消费 `Define point load`
- **中间的 `1 1` 必须由某处消费。** 唯一的候选就是 `:231`。

若 `:231` 未执行，`:239` 会把 `1 1` 当作字符标题读走（**字符读不会报错**），随后
`:241` 拿 `Define point load` 去读整数——必然运行时错误。而两例均正常完成。

`LINEAR` 同时满足那四个 `≠` 条件，分支本身也成立。**所以 `:231` 执行了，是证据漏了它。**

## 更正（2026-09-08 晚）：不是"没人注意到"，是**有人判断过而判断错了**

本文件最初把这处写成"清单漏采集"。核实映射表后发现**不准确**。
`docs/m2/state-field-map.toml` 的 `amplitudes.points.value` 一行，原注记写着：

> Read by the untracked statement Load.f90:231（same record group as curve_points;
> **not a separate M1 reader**）

**M2-01 的作者看见了这条语句，并明确判定它"不算一个独立的 M1 reader"。**

那个判断对**映射表的目的**说得通——两条记录同属一个字段组，都喂 `amplitudes[].points`。
但对 **M1 的目的**是错的：M1 要的是"每一个可独立失败的读取都有分类诊断"，
而它是一条独立的 `read` 语句、消费一条独立的记录、可以独立失败。

所以失效不是"看漏了"，是**跨阶段的目的错配**：一处语句在 M2 的口径下被正确地判为"非独立字段来源"，
这个结论被沿用到 M1 的口径下，而在那里它是错的。**两个阶段各自的判断都自洽，衔接处没有人对齐口径。**

这比"清单漏了一项"更难防，也更值得记。

## 为什么会漏

`reader-inventory.toml` 的 `not_on_path` 里有一组：

```toml
unit_var = "loadunit", file = ".loa", site_count = 33
reason = ".loa records for point loads, edges, edge loads, beam/plate loads; counts are 0"
```

`Load.f90` 中未包装的 `loadunit` 读取**恰好 33 处**，与该组计数吻合——即这 33 处被**整体**归入
"点荷载/边/梁板荷载，计数为 0"而未包装。

但 `:231` **不属于那一类**：它是幅值曲线的 `dfact` 记录，门控条件是 `type_curve` 不等于四个特殊
类型，与任何"计数为 0"无关。它被这一整组的理由**顺带扫了进去**。

`yl_io_inventory.py check` 仍然 PASS，因为它的 `not_on_path` 规则是**按 unit 粒度**
（工具第 249-254 行："every census unit must be either registered or explained"），
而 `loadunit` 被这一组解释了。**check 没有失职，它只是没有能力发现这件事**——
聚合到 unit + 计数 + 理由的分类，无法区分"这个站点被审视后判为路径外"与"它被一句概括捎带过去"。

## 后果

1. **M1-01**：`not_on_path` 分类对至少一处是错的。
2. **M1-02**：「152 个 reader 与 14 个 open 已包装 / 152」的**分母**不含这一处，
   因此「所选路径的读取全部包装」**未被证明**。已执行路径上存在一处裸读——
   `.loa` 的这条记录若畸形，得到的是 Fortran 原生错误或静默错位，而不是 M1 的分类诊断。
   这正是 M1-02 立项要消灭的那一类。
3. **gdb 实证**：211 位点的命中集有缺口，至少漏掉一处确实执行的读取。

## 严重性与边界

- **不影响既有数值结果**：两个 golden 算例的 deck 是良构的，该读取正常成功。
  求解器二进制、参考结果、状态基线均不受影响。
- **影响的是"输入可控失败"这一 M1 的核心主张**在该处不成立。
- **只发现了一处**。同类问题是否还有——本次没有系统排查，
  且现有工具**查不出来**（unit 粒度的分类无法逐站点核对）。这一点本身是最值得注意的。

## 另一处候选：`Global.f90:1250`（已排查，**不是**同类）

M4-01 的 `.glb` 解析器作者也报告了一处"清单里没有 id"的读取：
`if(group%index==20/21/22/26) read point_direct`（`Global.f90:1250`）。

**它与 `Load.f90:231` 不同，是真正的路径外**：门控是单元类型 index 属于 20/21/22/26，
全为非 Q4，两个 golden 算例的 gdb 命中集里都没有它。它同样在 1022 全集内、由
`gunit` 的 not_on_path 组按 unit 粒度解释——分类**结论正确**，只是同样无法逐站点核对。

记在这里是为了说明：本次排查看了两处候选，**一处误判、一处正确**。
这恰好说明问题不在"分类做错了"，而在"分类无法被逐项检验"。

## 第三处候选：`Prescrib.f90:173/174/176`（路径外，但**组里给的理由盖不住它**）

`.loa`/`.pre` 解析器作者随后对这两个文件的 reader **做了系统排查**，报出第三处：

```fortran
! Prescrib.f90:171-178 —— restart 预扫描
if (restart==1) then
   do jblks=1,iblks-1
      read(punit,*)text          ! :173
      read(punit,*)nfixsets,nline ! :174
      do ifixset=1,nline
         read(punit,*)text        ! :176
      end do
   end do
end if
```

三处均在 1022 全集内，**清单里一条 `Prescrib.f90:1xx` 都没有**，也无 `diag_check_read`。

**它确实不可达，而且论证比"两例未命中"更强**：`prescrib_set` 只在
`do iblks=lblks+1,runblks`（`Fem.f90:1683`）内被调用，白名单把 `nblks` 固定为 1、冷启动 `lblks=0`，
故 `iblks==1`，预扫描的循环界 `do jblks=1,iblks-1` 即 `do jblks=1,0`——**结构性为空，
与 `restart` 取何值无关**。这是白名单范围内的保证，不只是这两个算例的观测。

**但 `.pre` 那一组 not_on_path 给的理由是**「MIF/VIE 与插值从属；`type_abc/='FIX'` 或 `ntrans/=0`」
——**只字未提 `restart`**。结论对，理由盖不住。

## 三处候选的总账

| 站点 | 结论 | 组里给的理由 |
|---|---|---|
| `Load.f90:231` | **错**——确实执行，且未包装 | 盖不住（"计数为 0"与它无关） |
| `Global.f90:1250` | 对 | 盖得住 |
| `Prescrib.f90:173/174/176` | 对 | **盖不住**（未提 `restart`） |

所以问题的形状比最初判断的更清楚：**分类的结论多数正确，但它的理由经不起逐项对照**。
三处里有两处的归类理由与实际门控条件对不上，其中一处因此判错。

**排查范围**：解析器作者只系统扫了 `Load.f90` 与 `Prescrib.f90`（它自己负责的两个文件），
结论是这两个文件的已执行路径上再无其它未包装/无 id 的读取。
`Global.f90`（75 站点）、`Elements.f90`、`Material.f90`、`Solver.f90` **尚未系统排查**。

## 建议（属 M1，不属 M4-01）

1. 把 `:231`（以及同分支的 `:224` SEISMIC 记录）从 `not_on_path` 的 33 项里摘出，
   补进 reader 清单并加 `diag_check_read` 包装。
2. **更重要**：把 `not_on_path` 从"unit + 计数 + 理由"改为**逐站点枚举**，
   使"这个站点被判为路径外"成为可核对的断言，而不是一句概括。
   否则同类漏判无法被发现——本次是靠 M4-01 的解析器作者偶然撞见的。
3. 在 M1-01/M1-02 的签收材料里如实记录本发现，**不要在修复前签字**。

## 修复（2026-09-08，同日）

`Load.f90:231` 已按建议 1 处理：给 read 加 `iostat=`/`iomsg=`，紧跟
`call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_curve_factors,0)`，
写法与 `:220` 的姊妹语句一致。`reader-inventory.toml` 新增 `LOA.external_load_1.curve_factors`
（site `Load.f90:231`），`loadunit` 的 `not_on_path` 组 33→32，理由文本改为点名摘除的这一处
并指回本文档。`src/diagnostics/yl_diag_registry.f90` 已重新生成，153 个 reader。
建议 1 括号里提到的 `:224`（SEISMIC 记录）**不在本次修复范围内**——它在这两个金标准算例上
不可达（`type_curve` 恒为 `LINEAR`），仍属 `not_on_path`，留给触及 SEISMIC 路径的白名单切片处理。
建议 2、3 未处理，见下节——建议 2 现在看是**必须做**，而不是"更重要"这么温和。

## 工具根因：断点生成器的"一行一地址"假设是错的

修复后按流程重新取 gdb 实证时，两例的 `hits.json` 都**没有** `Load.f90:231` 的命中记录——
尽管重建后两例仍与 reference 逐字节相同（说明程序行为没变，只是这一条没被断点看见）。

深挖后的根因，用反汇编直接确认：

- `tools/yl_io_inventory.py gdb-script` 给每个位点下一条 `break FILE:LINE`；gdb 按行号解析时，
  只取该行在行表（line table）里的**第一个**地址。
- 这条 `read` 语句（数组段 `tcurves(itcurve)%dfact_curve(1:ntime)`，前面还有一个 `SEISMIC` 分支）
  被 ifx 编译成**两段不相邻**的机器码，行表对两段都标注为第 231 行：
  - `0x5a9b16–0x5a9bba`——`break Load.f90:231` 选中的这一段，只在这条 read 自己的越界/负跨度
    检查逻辑内部、某个条件为真时才会跳进来；
  - `0x5a9e38–0x5a9f6c`——`elseif` 分支条件为真时**真正**跳入的入口，`break FILE:LINE`
    从未选中它。
- 两个金标准算例这条 read 走的都是第二段，第一段从未到达——所以 211 命中集合里没有它。
- 直接证明：在同一份 trace 二进制（`binary_sha256` 见下）上手动
  `gdb -batch -ex "break *0x5a9e38" -ex run`，断点命中一次，停在
  `type_curve=='LINEAR'` 已确认成立之处；再往下走，`text` 被正确读入下一条 `title#2`——
  与"这条记录确实被消费"的推断完全吻合。这不再是反证法，是直接观测。

**这是手工取得的证据，不是机器生成的**：`docs/m1/evidence/{cooks_membrane,lame_cylinder}/hits.json`
里为此新增了 `"Load.f90:231": 1`，并附一个 `manual_additions` 字段说明上述方法、地址与复现方式，
与其余 211 个位点的自动断点计数区分开来。`tools/yl_io_inventory.py` 本身未改动。

### 五步静默失败链

这次漏判不是"分类理由碰巧没覆盖到"那么简单，而是一条从工具假设开始、完全在自动化范围内、
**没有任何一步会报错**的链条：

1. `:231` 执行了；
2. 断点生成器的"一行一地址"假设让断点从未命中它；
3. 它因此不在 `hits.json` 的命中集合里；
4. 它因此从未被写进 `reader-inventory.toml`；
5. 它因此从未被 `diag_check_read` 包装。

`yl_io_inventory.py check` 看不出这条链条——它拿清单去对照证据（`hits.json`）和源码（锚点），
而清单本来就是**从证据反推出来的**：没被命中的位点根本不会被写进清单去接受检查。
check 校验的是"清单与证据一致"，不是"证据完整"；这次的缺口恰好出在证据本身。

### 无法排除同类缺口——211 是下限，不是测量值

清单没法反过来暴露还有多少个这样的位点：除 3 个显式标注 `reached_only` 的条目外，
清单里**每一条 reader 的命中数都非零**——因为它们本来就是从命中数非零筛出来的。
这种循环结构意味着，凡是复合分支结构导致 ifx 把某条语句拆成不相邻两段、且已执行的那段
恰好不是行表第一个地址的位点，都会重复这条五步链，且不会被现有工具、现有清单、现有
check 命令中的任何一个环节发现。本次两个金标准算例上**只找到这一处**，但那是因为
本次没有对 1022 个静态全集位点逐一反汇编核对——不是因为工具确认了没有更多。

**结论**：把两例的机器断点命中集合（211 个不同位点）当作"这两例实际执行了哪些语句"的
精确测量是不成立的。它是一个**下限**：至少这些位点执行了，但工具在多大范围内低估了
执行集合，现有材料无法回答。M1-01「已执行位点清单」与 M1-02「所选路径读取全部包装」的
签收结论都建立在这个数字之上，需要据此重新评估，而不是止步于把 `Load.f90:231` 这一处补上。

### 重建与数值核验

- `legacy/source-manifest.json` 已用新源码重新生成并通过 `yl_manifest.py check`。
- release 构建二进制 GNU build-id：修复前 `b10f13ba56944d16f857cbe0c70d5943669e01ad` →
  修复后 `00e20806b876958aa6d81f2e2f9d96ac508a065b`（源码变了，预期之内的漂移）。
- 两例用新 release 二进制重跑，`tools/yl_compare.py`（默认 `atol=rtol=0`）逐分量精确核对：
  `cooks_membrane` DISPLACEMENT n=578 / STRESS n=1156，`lame_cylinder` DISPLACEMENT n=162 /
  STRESS n=324，两例 `max|d|=0.000e+00`——数值结果与 `cases/golden/*/reference/` 完全一致，
  求解器可观测行为未变。
- `tools/yl_wrap_reads.py --dry-run` → 0 edits（清单与源码里的包装已经一致，无需再改）。

## 附带说明

本发现是 M4-01 适配器契约「每一次读都必须可追溯到 reader 清单」那条要求的直接产物。
若没有它，解析器作者会按"清单里没有就不用读"跳过这条记录，
而那会让 `.loa` 其后的每一次读取错位——**一个静默的解析缺陷，恰好由一条文档纪律挡住了。**
