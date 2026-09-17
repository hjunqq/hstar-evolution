# M8 · DUNCANCHANG：材料域的第二个本构

主线不变：输入体系现代化。这一轮要回答的是一个结构问题——统一的 `[[material]]`
对象和 ProblemState 的「每模型一块」形状，在遇到**第二类**非线性材料参数体系时是否还成立。

推进顺序沿用既有方法：**真实能力差值测量 → 最小 authoring schema 扩展 → ProblemState
→ bridge → solver → 严格回归**。

前置：`new_duncan_chang` 此前 SIGSEGV，无法冻结参考。那是 legacy 自身缺陷，
一行修复登记在 [`pre-migration-defects.md`](pre-migration-defects.md) 的 PD-1，
**不计入本轮的现代化能力**。本文的进度从「参考已冻结、现代输入尚不支持」起算。

---

## 1. 能力差值：逐文件量，不靠推断

基准取 `plasticity.mini_mc`——同一套网格（30 节点 / 20 个 Q4）、同一组支座、同样的重力。
`.pre` / `.opr` / `.tem` / `.ftr` / `.ifs` / `.nrt` / `.aqu` **逐字节相同**，`.loa` 只差组数。
于是差值就剩四条：

| 文件 | 差值 | 是不是新能力 |
|---|---|---|
| `.mat` | `DUNCANCHANG` + `EB` 子记录 | **是**，本轮唯一的新能力 |
| `.man` | `nstep` 1 → 10，`miter` 10 → 20 | 否，现有 `[step.controls]` 已覆盖 |
| `.glb` | `type_nl` 4 → 5（`stiffness_update`） | 否，白名单已同时放行 4 和 5 |
| `.glb` | `res_s` 0 → 1 | 否，只控制二进制 `1.res`（Output.f90:3425/3454），不进观察量 |

另一条差值是量出来的、而不是从文件里看出来的：**`hdam`**。它在 `.glb` 里两个算例都是
`0.000`，但只有 DUNCANCHANG 的首访分支会去读它（Stiff.f90:801），而现代提交路径
**从来没有分配过这个数组**——在此之前没有任何 golden 算例碰它。所以 `hdam` 是这一轮
第二个必须补的字段，来源是「谁会读它」，不是「哪一行不一样」。

用适配器跑一遍未修改的 deck，机械地拿到了同样的结论（先失败的那一条）：

```
UNSUPPORTED materials[1].model: material_select (Material.f90:457) has a branch per
constitutive model, each with its own extra records; only ELASTIC_ISOTROPIC and
CLASSICALEP are whitelisted (capability row G3 material.model)
```

## 2. 只迁移这个 deck 真正用到的

legacy 的 DUNCANCHANG 分支能读四条记录，本轮只放行第一条和 `EB` 那条：

| 记录 | 何时读 | 处置 |
|---|---|---|
| `model` + 九个数（Material.f90:504） | 总是 | **迁移** |
| `k1/k2/nd/lamdaMax`（515） | `type_problem == 'F'` | 按名拒绝（本构建白名单是 `Q`） |
| `G/F/Vtf`（524） | `model` 是 `EV`/`CR` | 按名拒绝（没有对应 ProblemState 组件） |
| `Kb/m/dphi`（528） | `model(1:2) == 'EB'` | **迁移** |
| `phi_s/k_s`（539） | `kind_wt > 0` | 公共记录的闸门已按名拒绝非零 `kind_wt` |

拒绝的位置有讲究：`model` 决定**下一条记录的形状**，所以白名单检查放在第一条读完、
第二条读之前——猜错不会给出一个错的数，而是让文件游标错位，之后每一条读都是错的。
这和 `read_classicalep` 里对 `criteria` 的处理是同一条理由。

`phi_s` / `k_s` 是「只提交作者写过的东西」的一个例外，写在 commit 里：legacy 并不读它们，
而是在 533-537 行**派生**——把 `phi` 和 `k` 抄过去，EBMOD 在 `isat > 0` 时才用
（Stiff.f90:6691-6694）。复制那次派生是在复现 legacy 自己的初始化，不是发明数值；
留成毒值反而会在任何一天 `isat` 变非零时与 legacy 路径分叉。

## 3. 统一 `[[material]]`，不另起一套

第二个本构加的是**它独有的**参数，不是一套平行词汇：

- `cohesion` 和 `friction_angle` **共用** `classicalep` 已有的拼写。两个模型都读一个
  凝聚力和一个摩擦角，含义相同，所以每个物理量在 `[[material]]` 里只有一种写法，
  由 `model_requires` 分别向两个模型索取。这正是统一材料对象的意义所在。
- 其余 11 个键是 DUNCANCHANG 独有的，`bulk_modulus_law` 领头，因为它是选择子。
- 「必填」是 (键, 模型) 这一**对**的性质，不是键本身的性质，所以 `model_requires`
  被重写成三组（共用 / 塑性专有 / DUNCANCHANG 专有）走同一个 `group_requires`。
  一个模型时两半可以内联写，两个模型就会被抄三遍——而抄过的「这里要不要这个键」判断，
  正是下一个本构的参数被悄悄接受到错误材料上的地方。

ProblemState 侧同样：`duncan_chang_t` 是 `plasticity_t` 的**兄弟块**，不是
`material_t` 上多出来的 13 个可选组件。类型文件里那句「下一个模型加一个兄弟块」写于
M6，这一轮是它第一次被兑现。

命名按 ADR-0003 用现代拼写，legacy 的缩写留在 map 行的 `legacy_symbol` 里。
有一个是读代码读出来的，不是猜出来的：legacy 的 `Nur` 在 EBMOD 里是
`Kur*Pa*(p3/Pa)**Nur` 的**指数**，不是泊松比，所以叫 `unload_modulus_exponent`。

## 4. `hdam` 进 step，不进 case

`hdam` 是**高程**不是厚度：所有消费者用的都是它以下的深度
`hdam(iblks) - gpcod(ndimn)`。legacy 一条记录读完整个数组，但**按块索引**，
而分期填筑正是这个高程会逐块抬升的情形。所以契约把它写在 step 下，
step-scope 归类为 `per_block`，不做跨 step 一致性拒绝——这与 step-scope 规则一致：
该规则要拒绝的是「legacy 只读一次、契约却放在 step 下」的字段，`hdam` 不是那一类。

它是物理选择，因此不带默认值：0.0 是一个真实高程，不是「未指定」。
`initial_stress_requires` 两个方向都拒绝：有 DUNCANCHANG 材料而某个 step 没写它，
以及没有任何模型会读它却写了它。commit 侧对没写的 step 保留 `huge()` 毒值——
毒值乘以密度是一个会让计算停下来的荒谬应力，而静默的 0.0 与「作者就是想写海平面」
无法区分。

## 5. 复用 legacy 本构，不重写

现代路径一行本构计算都没有。它要做的只是把
`props(matno)%mechanical%solid%DuncanChang` 填对，之后 `tangceDC`（Stiff.f90:1246）
→ `EBMOD`（6665）→ `ecmat` 全是 legacy 自己的代码，与 legacy 路径走的是同一份目标文件。

## 6. 顺带修掉的两个门禁缺陷

都是在为这一轮**取证**时撞上的，不是顺手重构。

**(a) 读者普查文件长期与源码脱节。** `yl_io_inventory.py check` 把 inventory 与
`docs/m1/io-sites.json` 互校，而那个普查文件是提交进仓库的产物，**没有任何门禁强制它是新的**。
于是一次不改语句文本、只移动行号的源码改动（M5 的 `yl_input_enabled` 守卫、
Phase-3 从 `prescrib_set` 抽出 `prescribe_free_active`）就让 25 行注册站点、
以及据此下断点采集的**全部证据**，指向了错误的行——而门禁一路全绿，因为 inventory
和普查是**一起**过期的。锚点校验也拦不住：锚点是语句文本的散列，纯行号漂移不改文本。

修法两条：`scan --check` 用一次新扫描与提交的普查逐站点比对，进 `build.sh` 失败即停；
六个算例的 gdb 证据全部重采。

**(b) 扫描器看不见 `;` 连接的语句。** M5 与 M4-02 有意把守卫调用接在已有行尾，
好让文件行数不变、检查点锚点和读者站点原地不动。代价是一条语句可能位于**行中**：

```fortran
if (yl_input_enabled) call yl_modern_prelude(); if (.not. yl_input_enabled) open(inpunit,...)
```

只看行首的扫描器根本看不见那个 `open`，站点就这样悄悄离开了普查——
`INP.FEM90.open_Fem_92` 消失正是如此。现在按顶层 `;` 切分后逐段匹配。

## 7. 回归证据

收口判据是「现代输入独立驱动，且与冻结参考严格等价」。七个 golden 算例全部逐位一致，
`atol = rtol = 0`：

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
  N4 plasticity.slope_srm                  PLASTICSTRAIN non-zero values: 18924
  N4 nonlinear_elastic.new_duncan_chang    DISPLACEMENT  non-zero values: 440

FALLBACK PASS: default path == fallback path == frozen reference on every golden case
BUILD OK (adapter/release): bridge + dialect suites passed on both golden decks;
             reader coverage accounted for
BUILD OK (runtime/release): 100/100, 58/58, step-scope, state-map, reader inventory
```

新增的五条反例，**运行前先写下预期**，五条全部按预期落地：

| 反例 | 预期 | 实测 |
|---|---|---|
| `bulk_modulus_law = "EV"` | exit 3，指名键与值 | rc=3 ✓ |
| 删掉 `failure_ratio` | exit 2，指名键 | rc=2 ✓ |
| DUNCANCHANG 算例删掉 `fill_elevation` | exit 2，指名键 | rc=2 ✓ |
| 无该模型的算例写了 `fill_elevation` | exit 2，指名键 | rc=2 ✓ |
| 弹性材料上写 DUNCANCHANG 参数 | exit 2，指名键 | rc=2 ✓ |

**必须保持沉默的**：另外六个 golden 算例的 N2 比较一个都不许动——七条 `max|d| = 0` 就是它。

适配器侧两条 dialect 反例也各自单独触发自己那一行（`C 一行独发` 判据）：
`A-MAT/duncanchang-bulk-law` 与 `A-MAT/duncanchang-f-problem`。后者的上下文来自
`deck_context_t` 的新 `PROB_F` 变体而不是第二个 deck 文件——`.mat` 要按 `type_problem`
分支，这个事实本来就住在 context 里。

### 第三个门禁缺陷

`must_be_nonzero` 过去是拿 observable 的 `components` 去匹配**块名**的。唯一用到它的
算例恰好块名等于它唯一的分量名（`PLASTICSTRAIN`），所以一直看着是对的。本轮给
`DISPLACEMENT`（分量是 ux/uy）加上这条断言时，它匹配不到任何块——**断言什么也没断言，
门禁照常全绿**。现在 observable 显式写 `block`，且一条指向不存在块的断言会让门禁失败：
一条什么都不检查的 `must_be_nonzero` 比没有更糟，因为它会被当成证据读。
