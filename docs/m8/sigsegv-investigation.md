# SIGSEGV 调查：mini_goodman 与 new_duncan_chang

日期 2026-09-17。范围严格限制为用户裁定的三个问题，不扩 schema、不扩 ProblemState、
不开始 GOODMAN / JANBU / DUNCANCHANG 的现代输入支持、不重构本构。

调查基线：`git archive 5414e73`（legacy 快照的原始提交）解到
scratchpad/orig，用仓库自己的两个 profile 各构建一次：

| 二进制 | 选项 | 用途 |
|---|---|---|
| `orig/build/hstar_orig` | `-O2` | 判断"原始 legacy 是否也崩" |
| `orig/dbg/hstar_dbg` | `-O0 -g -traceback -check bounds,pointers` | 定位**第一**失效点 |

两个 profile 都取自 `tools/build.sh` 已有的 release / debug 定义，没有新增编译口径。
（`-check uninit` 会引入 MemorySanitizer 并在链接期 `undefined reference to __msan_init`，
因此沿用仓库 debug profile 的 `-check bounds,pointers`。）

---

## 1. new_duncan_chang（DUNCANCHANG）

### 问题 1：第一失效点

```
forrtl: severe (408): Attempt to use pointer ISATU when it is not associated with a target
  dep      Stiff.f90:818
  stiff_u  Stiff.f90:402
  static_u Fem.f90:3713
```

`kind_wt` 在 `Stiff.f90:762` 声明，**只在** 790–799 的首访分支里被赋值：

```fortran
if(type_problem=='Q')then
    if ((appear_process(igroup,iblks-1)==0.or. ...) &
        .and.iincs==1.and.istep==inc_step.and.idiv==1.and.iiter==1) then
        ...
        kind_wt=props(matno)%mechanical%solid%kind_wt
        ...
    else
        ...            ! <- 这里没有赋值
    endif
    isat=0
    if(kind_wt/=0) &                                  ! 读未初始化整数
        isat=element(ielem)%field(1)%isatu(igaus)     ! 解引用未关联指针
```

也就是说，第一次进入该高斯点时 `kind_wt` 有定义；**从第二次起**（第二个迭代、第二个
增量、第二个块）走 `else` 分支，`kind_wt` 保持未初始化。它恰好非零时就去解引用
`isatu`——而 `isatu` 只在 `Fem.f90:11842-11849` 的 `if(kind_wt/=0)` 下才分配，
本算例 `kind_wt = 0`，所以从未分配。崩溃就是这个解引用。

这是 legacy 自己的同类站点写法不一致造成的：`Stiff.f90:1134-1136`（SandPZ）在同一个
`type_problem=='Q'` 守卫内**无条件**赋 `kind_wt`，因此没有这个缺陷。

### 问题 2：是否迁移引入

**不是。** 未改动的 5414e73 快照同样崩：

```
new_duncan_chang PRISTINE-5414e73 rc=174 res=5818  severe (174): SIGSEGV
```

legacy 原有缺陷。

### 问题 3：最小修复

符合用户裁定里「修复非常局部且有独立依据」的例外。改动是**一行**，
`legacy/yl/Stiff.f90:818`：

```fortran
kind_wt=props(matno)%mechanical%solid%kind_wt !fix: assigned only in the branch above
isat=0
if(kind_wt/=0) &
    isat=element(ielem)%field(1)%isatu(igaus)
```

独立依据有三条，都是量出来的，不是推断：

1. **形式来自 legacy 自己**——与 `Stiff.f90:1136` 的兄弟站点逐字一致，不是我们发明的写法；
2. **对全部既有算例惰性**——全树 1283 个 `.mat` 里 1810 条 solid 记录，`kind_wt` 分布为
   `{0: 1810}`。没有任何记录非零，因此 `isatu` 在整个语料里从未被分配，被守卫的那一支
   永远走不到；这一行只能把"读未初始化整数"变成"读确定的 0"；
3. **回归实测惰性**——见下方 §3，六个 golden 算例在现代输入与 legacy 两条路径上都逐位不变。

修复后 `new_duncan_chang` 跑通并可重复：

```
run1 rc=0 res=58180 sha=d0434227d2953686
run2 rc=0 res=58180 sha=d0434227d2953686
run3 rc=0 res=58180 sha=d0434227d2953686
```

（原先是 rc=174 / res=5818 的截断输出。）尚未冻结为 golden 参考——按用户裁定，
下一个真实材料能力由用户选定后再做。

---

## 2. mini_goodman（GOODMAN + JANBU）

### 问题 1：第一失效点

```
forrtl: severe (408): Subscript #2 of the array ELCOD has value 4
                      which is greater than the upper bound of 2
  normal_local_inc  Elements.f90:3368
  read_element      Elements.f90:1087
  global_data       Global.f90:1173
```

`read_element` 分配 `elcod(ndimn,nnode)`，然后在 `elcod_local /= 0.` 时调用
`normal_local_inc`，该子程序在 2-D 分支里写 `elcod(:,3)`、`elcod(:,4)`——把线单元的两个
节点沿法向偏移 `elcod_local`，生成零厚度 4 节点接缝单元的另外两个节点。

对 **q4（elkn 索引 5，nnode=4）** 的组，`elcod` 是 (2,4)，写第 3、4 列**在界内**，
而 1194 行 `elcod_f(:,1:nnode)=elcod(:,1:nnode)` 取 1:4，生成的两列被完整保留。
这是这条路径的正常用法：全树 2580 条组定义里有 119 条 `elcod_local /= 0`，
按单元种类分布为 `{5: 95, 9: 22, 23: 1, 20: 1}`。

唯一的 **索引 20（b2，nnode=2）** 就是 mini_goodman 的 `Joint` 组：

```
Q4    Joint          20 CO     1 U   ST   PE           4  3  0  1  1  1       2.000E-02  0  0  0
```

此时 `elcod` 是 (2,2)，写第 3、4 列越界，即崩溃点。

### 问题 2：是否迁移引入

**不是**——未改动的快照同样崩（`rc=174 res=0`）——但也**不是 legacy 代码缺陷**：
这是**算例本身的缺陷**，而且是一个我们自己生成的算例。

判据是算例内部自相矛盾，与 `normal_local_inc` 无关：

- `1.ele` 全部 12 条记录都是 4 节点（`id n1 n2 n3 n4`），三个组 2 + 4 + 6 = 12 条；
- 声明成 b2 的 `Joint` 组只会按 `read(iunit,*)i0,lnods(1:2)` 读 2 个节点，
  在列表导向读里会跨行吞掉后续数字，与 4 节点表根本对不上；
- 该目录带 `gen_all.py`，是生成出来的合成算例，不是真实工程 deck。

把该行索引从 20 改成 5 作为对照实验，崩溃点确实消失，但改在更靠后的地方失败
（`severe (59): list-directed I/O syntax error, unit 1, file .../1.glb`）——因为 b2 组的
组尾行数与 q4 不同。换句话说这份 deck 是按 b2 写的组尾、按 q4 写的单元表，
两边都不自洽，**没有一个局部改动能把它变成一个正确的模型**。

### 问题 3：是否修复

**不修。** 按用户裁定，自造算例不能作为迁移优先级证据，也不值得为它改 legacy 或改 deck。
记为明确边界：`mini_goodman` 不是 GOODMAN/JANBU 的能力证据。

顺带量到（只记录，不在本轮追查）：语料里真实的 GOODMAN + JANBU deck 是
`cases/cases/goodmanLU` 与 `cases/cases/goodman_evolution`，两者都把接缝组声明为
q4 + `elcod_local = 2.0E-02`，与上面说的正常用法一致。但目前：

| deck | legacy 路径 | 现象 |
|---|---|---|
| `goodmanLU` | rc=2 | `1.ftr` 读到文件尾，M1 守卫按设计拦下（`FTR.global_data.title#1`，`Global.f90:878`）——deck 不完整 |
| `goodman_evolution` | rc=174 | SIGSEGV，未定位 |

因此 GOODMAN 目前**没有**「真实 deck + 可运行参考」同时成立的算例。是否把
`goodman_evolution` 作为下一步，由用户决定；本轮不推进。

---

## 3. 修复的回归证据

`legacy/yl/Stiff.f90` 一行改动用字节拼接落盘（latin-1 源，Edit/Write 会损坏编码），
并通过"删掉插入行后与改前逐字节比较"证明改动恰好只有这一行。
`legacy/source-manifest.json` 重新生成，语义比对显示 39 个文件里只有 `yl/Stiff.f90`
的散列变化。

重建 release 后两道 fail-closed 门禁全绿：

```
MODERN PASS: every golden case runs from case.toml + mesh alone and reproduces
             the frozen legacy reference exactly; a rejected deck stops with the key named
  N2 static_2d.cooks_membrane    blocks=2   values=1734    max|d|=0.000e+00
  N2 static_2d.lame_cylinder     blocks=2   values=486     max|d|=0.000e+00
  N2 plasticity.mini_mc          blocks=3   values=210     max|d|=0.000e+00
  N2 plasticity.slope_srm        blocks=600 values=541200  max|d|=0.000e+00
  N2 loads_2d.wall_reservoir     blocks=4   values=552     max|d|=0.000e+00
  N2 loads_2d.beam_point_load    blocks=2   values=756     max|d|=0.000e+00

FALLBACK PASS: default path == fallback path == frozen reference on every golden case
```

legacy 路径（`--adapter=off`）单独再比一次，同样逐位一致：cooks 1734 / lame 486 /
mini_mc 210 / wall_reservoir 552 / beam_point_load 756，`max|d| = 0`。

### 顺带修掉的一个门禁自身缺陷

`tools/yl_fallback_check.py` 的 F4 用 `cwd=<临时 deck 目录>` 启动二进制，却直接传入
`--binary` 的原样路径。F1–F3 经 `yl_run.py` 会自行解析成绝对路径，所以只有 F4 会在
传相对路径时 `FileNotFoundError`——门禁在这种调用下**根本没跑完最后一项**。
改成 `Path(a.binary).resolve()`。

---

## 结论

| deck | 第一失效点 | 归属 | 处置 |
|---|---|---|---|
| `new_duncan_chang` | `Stiff.f90:818`，`kind_wt` 未初始化 → 解引用未关联的 `isatu` | legacy 原有缺陷 | 一行修复（形式取自 legacy 兄弟站点，全语料惰性，六例逐位回归为证）；算例已跑通且可重复，未冻结参考 |
| `mini_goodman` | `Elements.f90:3368`，`elcod` 第 2 维越界 | **算例缺陷**，且是自造算例；legacy 代码对正常的 q4 接缝用法是正确的 | 不修，记为边界；不作为 GOODMAN/JANBU 的能力证据 |

两个算例都已查清。材料域的下一个能力由用户选定；本文只提供证据，不做推荐。
