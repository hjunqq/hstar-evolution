# M10 · PARDISO：第二个线性求解器

本阶段只解决一件事：**authoring solver 选择 → ProblemState → legacy PARDISO 路径 →
可运行真实算例 → 严格回归**。求解器选择属于 numerics，不进入 physics 语义；
性能优化与并行计算不在本线程内。

## 1. 先回答依赖问题：CONCRETE 与 PARDISO **没有**耦合

M9 暂停时的现象是「四个 2-D L2 算例同时需要 CONCRETE 与 PARDISO」，但那是那四个 deck 的
性质，不是两个能力之间的关系。语料普查：**229 个 deck 用 PARDISO**，其中策展库里的 2-D `Q`
型算例按材料分布如下（模型名按 solid 记录形状识别，跳过注释行——`.mat` 头部的
`CLASSICALEP,CAMCLAY,ETC` 是注释，不是材料）：

45 个 PARDISO 算例只用 `ELASTIC_ISOTROPIC`。**不需要联合切片。**

## 2. 切片的选择：用适配器逐个探，读第一条拒绝

对每个 2-D PARDISO 候选跑一次适配器，记录**第一条**拒绝：

| deck | 第一条拒绝 |
|---|---|
| **`benchmark_100x100`** | **`.sol` 记录形状对不上 PROFILE 解析器 —— 只有这一条** |
| `tunnel_lining` / `disc_contact_3d` | 材料属性曲线（`nscurve /= 0`） |
| `gravdam` | `mdofn /= ndimn` |
| `static` / `goodmanLU` / `goodman_evolution` | `runblks > 1` |
| `rc_lining` | `nlocalbeam` / `ndimnrt` |
| `rcbeam` / `tunnel` / `tunnel_sl` | CONCRETE（且属 M9，已暂停） |

**选 `benchmark_100x100`**：10 201 节点 / 10 000 单元、单组、单材料 `ELASTIC_ISOTROPIC`、
`nscurve = 0`、`NBLKS = 1`、`nincs = 1`、`nstep = 1`。它相对 `static_2d.cooks_membrane`
的差值**只有求解器本身**。

一个必须先量、不能假设的风险：deck 写的是 `ncpu = 4`。多线程分解是否逐次可重复？
冻结参考时 3 次运行逐字节相同（2 块 / 61 206 值），据此开始动代码。

**这个结论当时说错了一半，后来被门禁纠正**，记在这里而不是抹掉：
PARDISO **不是**无条件可重复的，它只在**线程被钉住**时可重复。
`yl_run.py` 一直钉着 `OMP_NUM_THREADS=1 / MKL_NUM_THREADS=1 / MKL_DYNAMIC=FALSE`，
冻结走的是它，所以 3 次一致——我把**运行器**的性质当成了 PARDISO 的性质。

实测（两个方向都做了）：

| 环境 | 3 次运行的不同哈希数 |
|---|---|
| 不钉线程 | **3** |
| 钉住线程 | **1**，且等于冻结参考 `f4f124fa38438663` |

差异出现在 1e-21 量级——数值为零的位移——但逐字节比较不在乎差多小，
本项目的判据就是 `atol = rtol = 0`。

这个误读反而查出了更要紧的东西，见 §5。

## 3. `.sol` 的差值就是四条记录

```
 mtype, ncpu, msglvl
  -2  4  0
 isdefault
  0
```

| legacy | 含义 | 处置 |
|---|---|---|
| `mtype` | MKL PARDISO 矩阵类型，`-2` = 实对称不定 | **迁移**，且**按名白名单**（见下） |
| `ncpu` | 线程数 → `iparm(3)`（Solver.f90:7816） | **迁移**：它进入分解，属于复现 deck |
| `msglvl` | 消息级别，0 为静默 | 迁移 |
| `isdefault` | **能力开关**，非零则再读 8 个 iparm 调优值 | **按名拒绝**，不做字段 |

`isdefault` 的处理与 DUNCANCHANG 的 bulk law 同一条规则：条件记录猜错不会给出一个错的数，
而是让文件游标错位，之后每一条读都是错的。

`mtype` 单独进白名单，取值只放行 `-2`。理由是它选的是**分解方式**：`2` 是实对称正定，
`11/13` 是非对称。选错不会响，只会按错误的方式分解——这正是需要门禁的情形，
所以未被真实算例证明的取值按名拒绝，并各自有反例。

**`ncpu` 是照搬，不是调优。** 它是 deck 陈述的输入且进入 `iparm(3)`，
复现 deck 就必须带上它；挑一个**好**值是性能问题，属于另一条线程。

## 4. legacy 侧：11 行，行数不变

| 行 | 改动 |
|---|---|
| 21 | `isdefault, ncpu` 从 `MAIN_PARDISO` 的局部声明提升到模块声明 |
| 7759 | 同上，从局部声明里去掉 |
| 7787 | `iparm=0` 保持无条件；**四个默认值加守卫** |
| 7788–7795 | 四条读加 `iostat=`/`iomsg=`/`diag_check_read` 与 `yl_input_enabled` 守卫，`print` 保留 |

**为什么提升到模块作用域**：map 校验器不接受把一个子程序局部变量当作 legacy 符号
（`'ncpu' not declared in module solver`）——这条规则是对的。两种解法里，
提升是两行声明改动，而加一个 supply 例程要新增 prelude + stub 一对；提升更小。
`:3289` 的 `_ctt` 例程保留它自己的同名局部变量，因此完全不受影响。

**为什么 7787 也要守卫**：它在 `MAIN_PARDISO` 内部，即**在桥接提交之后**才执行。
不守卫的话它会静默覆盖已提交的值——`mtype` 变成 2（正定）而 deck 说 -2（不定），
`isdefault` 变成 1 会让 legacy 去找一条文件里根本没有的调优记录。

按既有纪律用 `;` 连接语句，**文件行数不变**，`scan --check` 实测**没有任何 io 站点移动**，
因此六份既有 gdb 证据全部继续有效，无需重采。

## 5. 查出并修掉的门禁缺陷：参考的「环境」没有被门禁沿用

`yl_run.py` 钉住线程环境，**每一份冻结参考都是经它产生的**；
而 `yl_modern_check.py` 与 `yl_fallback_check.py` 是直接 `subprocess.run` 启动求解器的，
**从来没有钉过**。也就是说它们一直在拿「另一个环境下跑出来的结果」去比「这个环境下冻结的参考」。

它一直看不见，因为此前每个 golden 都用 PROFILE——PROFILE 是单线程的，环境怎么设都一样。
第一个 PARDISO 算例进入门禁时它立刻暴露：N2 在 61 206 个值里失败 206 个，
而且**现代路径和 legacy 路径一起失败**，原因两条路径都不沾。

修法：把这套环境提取成 `yl_run.pinned_env()` 一处定义，两个 checker 都用它——
「参考意味着哪个环境」在全仓库只有一个答案。正反两个方向都已验证（见 §2 的表）。

**一个必须如实说清的配对**：deck 写 `ncpu = 4`，桥接忠实地把 4 写进 `iparm(3)`，
而运行器把 MKL 钉在 1 个线程。两件事都成立，也都要写下来：
携带 `ncpu` 是因为**复现 deck** 就得带上它；而参考是**在钉住的环境下**定义的。

## 6. 顺带记下的一个既有缺口（不在本轮修复）

PROFILE 一侧有一个镜像问题：现代路径上 `.sol` 的读被守卫关掉后，
`iafile / icond / ipdchk / ising` **没有任何地方供给**，而 deck 写的是 `ipdchk=1, ising=1`。
静力 golden 仍然逐位复现，说明它们在本切片上不被消费——但那是运气，不是设计。
它早于本里程碑，也不属于 PARDISO，登记在此，不顺手扩大范围。

## 7. 验收判据

1. `benchmark_100x100` 冻结参考：3 次运行逐字节相同 — **`passes: true`**（2 块 / 61 206 值）
2. 现代输入独立驱动该算例，与冻结参考 `atol = rtol = 0` — **`passes: true`**（2 块 / 61 206 值，`max|d| = 0`）
3. 既有七个 golden 算例逐位不变 — **`passes: true`**
4. `solver.pardiso.*` 两个方向都有反例（非 PARDISO 写了设置／PARDISO 没写设置） — 见 §8
5. 不放行未被真实算例证明的 `mtype`、不引入 `isdefault` 字段、不做性能调优 — 设计即满足

## 8. 回归证据

```
MODERN PASS: every golden case runs from case.toml + mesh alone and reproduces the
             frozen legacy reference exactly; a rejected deck stops with the key named
  N2 static_2d.cooks_membrane              blocks=2   values=1734    max|d|=0.000e+00
  N2 static_2d.lame_cylinder               blocks=2   values=486     max|d|=0.000e+00
  N2 plasticity.mini_mc                    blocks=3   values=210     max|d|=0.000e+00
  N2 plasticity.slope_srm                  blocks=600 values=541200  max|d|=0.000e+00
  N2 loads_2d.wall_reservoir               blocks=4   values=552     max|d|=0.000e+00
  N2 loads_2d.beam_point_load              blocks=2   values=756     max|d|=0.000e+00
  N2 nonlinear_elastic.new_duncan_chang    blocks=30  values=2100    max|d|=0.000e+00
  N2 solver_2d.benchmark_100x100           blocks=2   values=61206   max|d|=0.000e+00
  N4 solver_2d.benchmark_100x100           DISPLACEMENT non-zero values: 20200

FALLBACK PASS: default path == fallback path == frozen reference on every golden case
```

三条新反例，**运行前先写下预期**，三条全部按预期落地：

| 反例 | 预期 | 实测 |
|---|---|---|
| `matrix_type = 2` | exit 3（能力），指名键与值 | rc=3 ✓ |
| 删掉 `matrix_type` | exit 2，指名键 | rc=2 ✓ |
| PROFILE 算例写 `[solver.pardiso]` | exit 2，指名键 | rc=2 ✓ |

能力表一侧另有两条反例：`G4 unsupported linear solver`（原本用 PARDISO 作反例，
PARDISO 被放行后它**不再是反例**，套件当场报出来，改指 `SSORPBCG`）与
`G4 unsupported pardiso matrix type`。

**必须保持沉默的**：另外七个 golden 算例的 N2 比较一个都不许动——八条 `max|d| = 0` 就是它。

## 9. 本轮修掉的门禁缺陷

**一条根因**：一个只见过一两个相似输入的检查，等于没有被真正试过。
第八个 golden 算例带来的是「多线程求解器 + 不同材料 + 不同块结构」，
于是四个潜伏的缺陷同时现形。它们**都没有改变任何结果**，改变的是门禁**能查出什么**。

| # | 缺陷 | 为什么一直看不见 | 修法 |
|---|---|---|---|
| 1 | 冻结参考带着**线程环境**，而两个 checker 没沿用 | 此前每个 golden 都用 PROFILE，单线程，环境怎么设都一样 | `yl_run.pinned_env()` 一处定义，两个 checker 都用 |
| 2 | `yl_anchor_order.py` 把算例目录拼成 `static_2d/<name>` | 它只能走到两个静力算例 | 改为从 `cases/manifest.toml` 取 |
| 3 | 同一工具把 `executed_by` 当成**全局布尔**，而它是**逐算例列表** | 见 2：只走两个算例时它们读取集几乎相同 | 改为 `case_id in executed_by`，与 `yl_io_inventory` 一致 |
| 4 | `PHASE_BUCKET` 没有 `block_lazy(2)` | 见 2：够不到 M7 的 `wall_reservoir` | 按「三个检查点都在 block 1 内」的语义补 bucket 3，并由工具**回验** |

缺陷 2 与 3 是**叠加**的：先修好路径，布尔那条才暴露出来（84 条报告，无一为真）。

另外两处是**工具按设计拦下的，不算缺陷**，但同样值得记：

* `T1` 能力表行数是钉死的，源码里写明「只与理由一起移动，绝不为了让构建变绿而动」。
  加了 `solver.pardiso.matrix_type` 之后它立刻失败；正确做法是**连同理由**把 11 改成 12。
* `G4 unsupported linear solver` 原本拿 PARDISO 当反例。PARDISO 被放行后它**不再是反例**，
  套件当场报出来，改指 `SSORPBCG`。这正是「反例会失效并伪装成结论」那条纪律。
