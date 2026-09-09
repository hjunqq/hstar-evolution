# M1-04：R27 关闭报告——把「211 位点」从下界升格为测量值

## headline

| 项 | 关闭前 | 关闭后 |
|---|---|---|
| 一个位点下几个断点 | **1**（`break FILE:LINE`，只绑定行表第一个地址） | **该行编译出的全部地址**（1022 位点 → **5520** 个断点位置） |
| 两例各命中的不同位点 | **211**（机器）+ 1（手工补记 `Load.f90:231`） | **216**（全部机器测得） |
| 新增站点 | — | **4**：`Output.f90:4301` / `:4326` / `:4351`、`Temper.f90:243` |
| 已包装 reader | 153 / 153 | **157 / 157** |
| `yl_io_inventory.py check` | PASS（在不完整的证据上） | **PASS**（在补齐后的证据上；补齐后未修时它先 FAIL 了 8 条） |
| 两例数值 | `max|d| = 0` | **`max|d| = 0`**（DISPLACEMENT 578/162，STRESS 1156/324） |

**差不为 0。** R27 的关闭条件写的是「差为 0 则下界升格为测量值，差不为 0 则每条新站点按 M1-02
流程补包装」——落在后一支：新命中集比旧的多 5 条（其中 `Load.f90:231` 是 2026-09-08 已手工
发现并已包装的那一处，这次由机器自己测到；另外 **4 条是本次新发现**，全部是**带语句标号、
由 `goto` 跳入的 title 读取**，都在已执行路径上、都没有包装）。四条已按 M1-02 流程补包装、
重建、重跑、重测，`check` 与数值核验全绿。

**「211 是下界」这句话现在可以换成「216 是测量值」**——但要带着 §6 的两条剩余假设读。

## 0. 本报告**没有**建立什么

- **不是「1022 个静态站点的执行/不执行判定都被证明」。** 建立的是：在两个 golden 算例上，
  216 个站点执行过（机器断点直接观测），另外 806 个站点的断点没有触发。后者的强度见 §5 的
  指令级对照——它把「没触发」从「工具没看」推进到「该行编译出的每一条指令都下了断点、
  只有 4 条越过 IF 块的收尾跳转触发，读取传输序列一条都没触发」，但仍不是形式证明。
- **不覆盖白名单以外的路径。** 只有 `static_2d` 两例、只有它们各自的 deck。SEISMIC、restart、
  wpgroup≠0 等分支上的读取仍然只有静态清单，没有实证。
- **不改变 R29。** 「适配器覆盖了哪些读取站点」与本报告无关：本报告让命中集成为测量值，
  但没有把命中集与 `! RD:` 标记对上。R29 仍然开着。
- **不重做 M1-01 的分类。** `not_on_path` 仍然是「unit + 计数 + 理由」的聚合形态
  （`M1-finding-2026-09-08` 的建议 2）。本次只把 4 条被这种聚合捎带进去的站点摘了出来，
  没有改变聚合本身。**下一次同类漏判仍然只能靠这个工具、而不能靠分类被发现。**
- **不声称计数是执行次数。** 见 §4 的合并规则：多地址站点的 per-site 数字是各地址命中数的
  **最大值**，它在「一次执行走遍全部地址」与「一次执行只进一个地址」两种情形下精确，
  介于两者之间时是下界。

## 1. 缺陷与它的形状

`tools/yl_io_inventory.py gdb-script` 原来对每个站点发一条 `break FILE:LINE`。gdb 按行号解析
linespec 时只取该行在 DWARF 行表里的**第一个**地址；而 ifx 会把一行编译成**多段**机器码，
每一段的行表条目都标着同一个行号。执行进入的若不是第一段，断点永不触发，而**整条链上没有
任何一步会报错**（`M1-finding-2026-09-08-unwrapped-loa-read.md` 的「五步静默失败链」）。

在本次使用的 trace 二进制上，这个断言可以直接看到：

```
$ gdb -batch -ex "info line Load.f90:231" -ex "break Load.f90:231" build/trace-r27/hstar
Line 231 ... starts at address 0x5a9b16 ... and ends at 0x5a9bba.
Breakpoint 1 at 0x5a9b16: file .../Load.f90, line 231.
```

一个位置。而 `Load.f90:231` 在同一个二进制里有 7 个行表地址，实际执行走的是 `0x5a9e38`。

**这个 gdb 怎么枚举一行的全部地址——实测而非假设。** 试过四条路：
`info line FILE:LINE` 只报第一段的起止；`break FILE:LINE` 只产生一个 location（不是
multi-location breakpoint，上面的 `info breakpoints` 已经确认）；`rbreak` / `-qualified`
解决的是符号名歧义，与一行多段无关。**可用的是 `maint info line-table`**：它按编译单元
打印 gdb 自己持有的行表（INDEX / LINE / REL-ADDRESS / UNREL-ADDRESS / IS-STMT）。
两个实测的坑：

- 不先 `maint expand-symtabs`，`maint info line-table` **一行都不打印**（符号表是惰性展开的）；
- 该命令**只对已展开的编译单元**打印，因此工具是「先展开全部、再一次性 dump」，
  而不是对 17 个源文件各跑一次 `list FILE:1`（`Vartype.f90` 没有代码，`list` 会报错并
  中止整个 batch 脚本）。

工具另加一条 fail-closed：若行表的 REL-ADDRESS ≠ UNREL-ADDRESS（PIE 重定位），
`break *ADDR` 的语义就不成立，直接退出。本二进制是非 PIE 可执行文件，两列相等。

## 2. 设计走过一次弯路，被对照实验推翻

**第一版**把行表切成「同一行号的、地址相邻的极大连续段（run）」，只在每段的**起始地址**下断，
理由是段内其余行是落空延续（fall-through），逐条下断会把一次执行数成多次。1022 站点 →
1259 个断点，101 个站点有多段，`Load.f90:231` 得到 `0x5a9b16` 与 `0x5a9e38` 两段——
阳性对照过了，两例的命中集是 212（= 旧 211 + `Load.f90:231`），**差看起来正好是 0（除去那处已知的）**。

按 `docs/07-acceptance-and-release.md` 的纪律，「绿是最需要怀疑的颜色」，所以补了一次
**敏感度对照**：对同一个二进制、同一个算例，改成对**行表的每一条记录**下断（5508 个位置）。

**结果推翻了第一版**：全地址版找到 4 个 run-start 版找不到的站点
（`Output.f90:4301` / `:4326` / `:4351`、`Temper.f90:243`）；而且在 `Load.f90:231` 那个
永不触发的第一段内部，**有 6 个内部地址触发了**（`0x5a9bba`、`0x5a9c20`、`0x5a9c5f`、
`0x5a9c89`、`0x5a9da8`、`0x5a9df4`），而段首 `0x5a9b16` 依旧没有。也就是说段内地址是跳转目标，**段首不是段的必经点**——
第一版携带的是与 R27 同一类的缺陷，只是更隐蔽。

工具因此改为**对行表的每一个地址下断**：1022 站点 → 5520 个断点位置（补包装后的二进制），
643 个站点有 >1 个地址。`tools/yl_io_inventory.py:line_addresses` 的注释里记了这次推翻，
以免有人再把它「优化」回 run-start。

**这一条按纪律记为一次没打中的预期**：`docs/m1/evidence-r27/predictions.md` 的 E12
（「全地址与 run-start 会得到相同的站点集」）是在跑之前口头陈述、跑完之后才补写进文件的，
因此在那份文件里它被降级为非正式预期。事前说出、事后补记，证据力低于事前写下，如实登记。

## 3. 对照实验（全部在跑之前写下预期，见 `docs/m1/evidence-r27/predictions.md`）

四次跑用的是**同一个** trace 二进制 `build/trace-r27/hstar`
（sha256 `361e7b28…`，源码 = 修改前的工作树），因此新旧差异只能归因于**工具**，
不能归因于二进制或 deck。

| 对照 | 预期 | 实测 | 结论 |
|---|---|---|---|
| **阳性对照** `Load.f90:231`（R27 指定） | 新脚本必须绑定 `0x5a9b16` **与** `0x5a9e38`，且 hits.json 里机器测得 ≥1 | 两个地址都下了断；站点命中 1 次；run-start 版的 `hits_by_range` 里只有 `0x5a9e38` 触发 | **通过** |
| **必须保持沉默** `0x5a9b16` | 该地址永不触发（`M1-finding` 里手工反汇编得出的结论） | 三轮跑的 `hits_by_range` 里都没有 `0x5a9b16`（发布版还显示同段内另有 6 个地址触发，见 §2） | **通过**，手工结论首次被机器复现 |
| **阴性对照** HEAD 版脚本、同一二进制、同两例 | `Load.f90:231` 必须**缺席**，站点数 211 | 两例都是 211，`Load.f90:231` 缺席 | **通过**，差异归因于工具 |
| **旧脚本 vs 既有记录** | 211 条站点与计数逐条相同（重建对命中集是惰性的） | 新增 0、缺失 0、计数差 0 | **通过** |
| **必须保持沉默** `Global.f90:1250`、`Prescrib.f90:173/174/176` | 结构性不可达，新脚本下仍必须缺席 | 两例都缺席 | **通过**（若出现则说明地址枚举过宽） |
| **断点记账** | `LOCATIONS N N`，gdb 实际建立的断点数 = 脚本请求数 | 5508 / 5508（修前）、5520 / 5520（修后） | **通过**（不等则 `hits` 直接报错退出） |
| **数值不受扰动** | 两例 gdb 下的 `1.flavia.res` 与冻结 reference 相同 | 四次 trace 全部 `OK ... results identical to reference` | **通过** |

## 4. 计数怎么合并——以及为什么不是求和

一次执行会触发同一行的多个断点，**求和等于把执行次数乘上代码布局**。合并规则取
**该行各地址命中数的最大值**：

- 一次执行走遍该行全部地址时（ifx 把数组段读取拆成逐元素片段就是这样），max 精确；
- 一次执行只进入其中一段时（`Load.f90:231` 就是这样），max 同样精确；
- 介于两者之间时，max 是下界。

**这个规则是被实测选中的，不是猜的**：在既有的 211 条记录上，max 逐条复现了全部旧计数
（差 0），而求和会把其中 **11 条**放大（`Global.f90:1027` 1→12、`Global.f90:1216` 1→16、
`Prescrib.f90:235` 2→4 等）。原始的逐地址计数保留在 `hits.json` 的 `hits_by_range` 里，
合并规则可以从证据本身重新推导；`breakpoint_hits_raw` 记录未合并的总触发数
（cooks 3454 / lame 1854，合并后 772 / 372）。

## 5. 新增的 4 个站点，以及它们为什么以前看不见

四条都是**带语句标号、由 `goto` 跳入**的 title 读取：

| 站点（修前行号） | 语句 | 谁跳进来 |
|---|---|---|
| `Output.f90:4301` | `1   read(outpread,*)text` | `Output.f90:4167` `if (wpgroup==0)goto 1` |
| `Output.f90:4326` | `2   read(outpread,*)text` | `Output.f90:4302` `if (wegroup==0) goto 2` |
| `Output.f90:4351` | `3   read(outpread,*)text` | `Output.f90:4328` `if (wggroup==0) goto 3` |
| `Temper.f90:243` | `11    read(tunit,*)text` | `Temper.f90:161` `if (ntedge==0) goto 11` |

`break FILE:LINE` 给这些行绑定的是「顺序落入」的入口地址，而两个算例的 `w*group` / `ntedge`
全为 0，执行是**跳进来**的，落在同一行的另一个地址上——与 `Load.f90:231` 同一形状。
它们此前被 `outpread`（13 站点）与 `tunit`（26 站点）的 `not_on_path` 组按 unit 粒度整体
解释掉了；两组的理由（「观测点列表；irecover/w*group 为 0」「零计数之外的温度边界数据」）
**都盖不住这四条**——它们恰恰是 `w*group==0` / `ntedge==0` 时**必然执行**的那一条。
这与 `M1-finding-2026-09-08` 的总账是同一句话：**分类的结论多数正确，但理由经不起逐项对照。**

### 5.1 门禁确实会因此变红

补齐证据、尚未包装时，`check` 给出：

```
FAIL: 8 problems
  executed site Output.f90:4301 (read, outpread) in static_2d.cooks_membrane is not registered
  ... （4 站点 × 2 算例）
```

即 `check` 的「completeness」规则本来就有能力抓住这一类，**它以前抓不住只是因为证据里没有
这几条**——这正是 R27 描述的「check 校验的是清单与证据一致，不是证据完整」。

### 5.2 按 M1-02 流程补包装

1. `docs/m1/reader-inventory.toml` 新增 4 条 `[[reader]]`：
   `OPR.output_read.label{1,2,3}_title`、`TEM.boundt.label11_title`；
   `outpread` 的 `not_on_path` 组 13→10、`tunit` 组 26→25，两组理由改为点名摘除并指回本文档。
2. `gen-fortran` 重新生成 `src/diagnostics/yl_diag_registry.f90`（153→157 readers）。
3. `tools/yl_wrap_reads.py`：dry-run 报 **4 edits in 2 files**，实跑同样 4 处，
   `git diff` 只有 4 处 `iostat=/iomsg=` 与 4 行 `call diag_check_read`，
   语句标号原样保留；`grep -c $'\xef\xbf\xbd'` 两个文件都是 0（没有 GBK 注释被 U+FFFD 污染）。
4. 用 `--line-map` 重锚：216 个 `site =` 字段按行位移重写，4 条改写过的语句重算 anchor，
   **其余 anchor 一条都没漂**（重锚脚本只报了这 4 条）。
5. 重建 trace 与 release、重跑两例、重测、`check`。

### 5.3 包装是有效的，不是装饰——EOF 反例

把 `1.opr` 截到 7 行（label3 那条读取撞 EOF），同一 deck 分别喂两个二进制：

| 二进制 | rc | HSTAR_DIAG |
|---|---|---|
| `build/release-r27/hstar`（本次修后） | **2** | `code=EOF exit=2 stage="startup" file=".opr" unit="outpread" reader="OPR.output_read.label3_title" site="Output.f90:4353" seq=8 iostat=-1` |
| `build/release/hstar`（修前，源码 = git HEAD） | **24** | **0 条**（`forrtl` 原生栈回溯） |

`1.tem` 截到 4 行同理：修后 rc=2 且 `reader="TEM.boundt.label11_title" site="Temper.f90:243"`，
修前 rc=24、无诊断。**必须保持沉默的一条**：诊断里不得出现其它 reader id（label1/label2、
`title#4` 等已成功消费记录的读取）——实测每次只有一条 HSTAR_DIAG，且 id 正确。

## 6. 剩余的两条假设（关闭 R27 不等于把它变成定理）

1. **行表之外的入口无法排除。** 工具对「该行的全部地址」的定义是 **DWARF 行表为该行登记的
   每一个地址**。若 ifx 没有为某个跳入点登记行表条目，而执行恰好从那里进入某条 read 的传输
   序列，本工具仍看不见。为给这条假设一个上界，做了**指令级对照**：对本工具报告为
   **未执行**的 806 个站点，把它们行范围内的**每一条指令**都下断（**47 965** 个断点，
   cooks_membrane，gdb 4 分 32 秒，`LOCATIONS 47965 47965`，`EXIT 0`）。
   结果 **4 条 HIT**，逐条查过反汇编，四条是同一个形状：

   | 站点 | 命中地址 | 该行指令数 | 命中地址在行内的位次 | 指令 |
   |---|---|---|---|---|
   | `Material.f90:339` | `0x523abb` | 308 | **308 / 308（最后一条）** | `jmp 0x523ac0` |
   | `Material.f90:454` | `0x52827b` | 169 | **169 / 169** | `jmp 0x528280` |
   | `Load.f90:171` | `0x5a7195` | 162 | **162 / 162** | `jmp 0x5a719a` |
   | `Fem.f90:3648` | `0xa937fc` | 131 | **131 / 131** | `jmp 0xa93801` |

   四条都是该行范围的**最后一条指令**，且都是一条跳到**下一条语句首地址**的 `jmp`——
   即 IF 块不成立时绕过块体的收尾跳转，行表把它记在块内最后一行的名下。
   **读取传输序列一条指令都没触发**（每个站点 131～308 条指令里只触发了这 1 条），
   而且若这些 read 真的执行过，它们会各消费一条记录、让其后的读取全线错位——
   两例的结果与 reference 逐值相同（`max|d|=0`），排除了这种可能。
   **结论：指令级粒度会在块尾跳转上产生假阳性；行表记录粒度既没有这些假阳性，
   在这 806 个站点上也没有暴露出假阴性。** 这是本次能给出的最强的一条，
   仍然只覆盖一个算例、一个二进制。
2. **计数对多地址站点是下界，不是执行次数**（§4）。站点集合是测量值；**per-site 的次数不是**。
   目前 11 个多地址且被命中的站点里，max 与旧计数一致，没有观察到分歧。

## 7. 复现

```bash
# 断点脚本（需要 trace 二进制：地址来自它的行表）
python3 tools/yl_io_inventory.py gdb-script --binary build/trace-r27b/hstar \
    --log /tmp/hits.log -o /tmp/bp.gdb --locations /tmp/bp-locations.json
# 两例 trace（--out 用自己的目录）
tools/yl_io_trace.sh static_2d.cooks_membrane --binary $PWD/build/trace-r27b/hstar --out $PWD/docs/m1/evidence/cooks_membrane
tools/yl_io_trace.sh static_2d.lame_cylinder  --binary $PWD/build/trace-r27b/hstar --out $PWD/docs/m1/evidence/lame_cylinder
python3 tools/yl_io_inventory.py check --evidence docs/m1/evidence/*/hits.json
python3 tools/yl_wrap_reads.py --dry-run          # 必须是 0 edits
```

`yl_io_trace.sh` 的 `--binary` **必须给绝对路径**：gdb 在算例工作副本里启动，相对路径找不到
二进制，而 gdb 的失败不会让脚本非零退出——它会走到「0 sites, 0 hits」再在结果比对处才失败。
本次踩过一次，记在这里。

## 8. 证据与产物

| 路径 | 内容 |
|---|---|
| `docs/m1/evidence-r27/predictions.md` | 五轮跑之前写下的预期（含被推翻的 E12） |
| `docs/m1/evidence-r27/<case>/old-script-control/` | HEAD 版脚本、同一二进制的 211 站点阴性对照 |
| `docs/m1/evidence-r27/<case>/new/` | 全地址脚本、**补包装前**的 216 站点（差分就是在这里做的） |
| `docs/m1/evidence-r27/<case>/new-wrapped/` | 全地址脚本、补包装后（`gen-fortran` 前的一版二进制） |
| `docs/m1/evidence-r27/insn-control/` | 指令级对照的生成脚本与过滤后的日志（4 条 HIT） |
| `docs/m1/evidence/<case>/` | **现行证据**，已用补包装后的最终二进制重取；新增 `bp-locations.json` |

二进制：`build/trace-r27`（修前源码，sha256 `361e7b28…`）、`build/trace-r27b`（最终，`4e793d9c…`）、
`build/release-r27`（最终 release，`fca1a7e3…`）、`build/release`（修前 release，`1e40e0d3…`）。
trace 与 release 都是用 `--src <scratch symlink>` 构建的（改动期间 `legacy/source-manifest.json`
尚未重生成）；最终的 manifest 已重生成并 `yl_manifest.py check` PASS。

## 9. 改了哪些文件

| 文件 | 改动 |
|---|---|
| `tools/yl_io_inventory.py` | `gdb-script` 改为按行表全地址下断（新增 `--binary`、`--locations`）；`hits` 记录逐地址计数、max 合并、断点数记账 fail-closed |
| `tools/yl_io_trace.sh` | 传 `--binary`/`--locations`，产出 `bp-locations.json` |
| `legacy/yl/Output.f90`、`legacy/yl/Temper.f90` | 4 处 read 加 `iostat=/iomsg=` + `diag_check_read`（M1-02 流程，字节级拼接，`git diff` 仅这 8 行） |
| `docs/m1/reader-inventory.toml` | +4 条 reader，TEM 的 seq 重排，两组 `not_on_path` 计数与理由，216 个 site 重锚 |
| `docs/m1/io-sites.json` | `scan` 重新生成（行位移） |
| `docs/m1/reader-inventory.md` | `render` 的表重新生成；叙述部分的「211 是下限」与结果概览按本次结论改写（叙述是手写的，只替换了 `## 已执行读取点` 之后的生成段） |
| `src/diagnostics/yl_diag_registry.f90` | `gen-fortran` 重新生成（153→157） |
| `legacy/source-manifest.json` | 重新生成，note 追加本次改动 |
| `docs/m1/evidence/**` | 用最终二进制重取的现行证据 |

**对其他人的影响**：`legacy/yl/{Output,Temper}.f90` 变了，因此**任何在 2026-09-09 10:03Z 之前
构建的求解器二进制都已过期**，`legacy/source-manifest.json` 也已重生成（旧 manifest 不再校验通过）。
需要重建的同事请重跑 `tools/build.sh <profile>`。数值行为未变（两例 `max|d|=0`）。

**需要别人改、本报告没有改的**（不属本任务所有权）：`docs/08-risk-register.md` 的 R27 行
（关闭条件已满足，处置栏应改写为已关闭并指向本文档）、`docs/STATUS.md:18-19`
（M1-01 / M1-02 的「有条件接受」条件已消除，但两者的分母从 153 变成 157，签收结论需要
按新数字复核）。
