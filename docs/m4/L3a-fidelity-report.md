# M4 L3-a：逐字段保真度对拍报告

## headline：两组计数都要看，不只看其中一组

本报告有两组计数，故意都放在最前面，不要只引用其中一组：

| | MATCH | MISMATCH | NOT_COMPARABLE | UNVERIFIED |
|---|---|---|---|---|
| **工具原始输出**（`yl_adapter_fidelity` 程序自己打印的 `SUMMARY` 行，两个 golden deck 一致） | 95 | 2 | 1 | 0 |
| **本报告终审判定 — 验收结论**（作者读过每条非 MATCH 背后的源码后给出的分类，见 §2/§3） | **95** | **0** | **3** | 0 |

两组不一致，原因是程序对"两侧都 unset"这类情况的自动 cause 标注只是初筛线索，不是终审结论
（`yl_adapter_fidelity.f90` 模块头原话："this program's tag is a lead, not a verdict"）。终审
判定把程序原始打的 2 个 `MISMATCH` 全部改判为 `NOT_COMPARABLE`（`sections.material_header`／
`sections.material`，真正是下一阶段的派生列，见 §2/§3），程序原始的 `NOT_COMPARABLE=1`
（`mesh.sets.nset`，集合行数不一致）在终审判定里保持不变，合计 3 个 `NOT_COMPARABLE`。
`sections.thickness` 在上一轮曾是本报告唯一的真实 `MISMATCH`（被 team lead 指出后从
"派生列"改判为"缺陷"），这一轮**修复落地、重新对拍后已回归为 `MATCH`**（§0.1、§2、§7），
终审判定的 `MISMATCH` 因此归零。**这是 L3-a 的验收结论：MATCH=95、MISMATCH=0、
NOT_COMPARABLE=3（均已命名下一比对地点，见 §2/§8），任何引用本报告计数的人都应引用终审
判定这一行——但两组数字都必须能在报告里查到，不能只留一个。**

## 0. 本报告回答的问题

**parser 构造出的 problem 是否和权威参照所代表的 problem 一致？** 不是"parser 自己内部一致"——
已有结果（两个 golden deck 均以零 finding 解析通过）只证明了内部一致性，不足以支撑这个问题。
本报告是一次 intent/input-to-model 的保真度关卡：把仓库侧手写 parser（`yl_adapter_fem90` /
`yl_adapter_model` / `yl_adapter_mesh` / `yl_adapter_material` / `yl_adapter_load`）在
`yl_adapter_driver` 的驱动顺序下解析出的 draft，与驱动 REAL legacy reader、从全局变量收割出的
oracle draft（`yl_adapter_harvest.harvest_problem_state`），按 `docs/m2/state-field-map.toml`
的全部 98 个 `ProblemState.*` 行逐字段对拍。

### 0.2 本报告**没有**建立什么

这一点必须显式说出来，免得读者把本报告当成比它实际范围更大的保证：

- **只测 parser 的保真度，不测 pipeline/桥的保真度。** 两侧比较的都是
  `builder_finish` 之后、`prepare_problem` 之前的 draft（§1.1）。`prepare_problem`
  （normalize/validate/capability gate/finalize）、`build_runtime`、
  `commit_legacy_globals` 是否把 parser 产出的东西原样保留下来，本报告一个字都没有验证
  ——那是 `.ccg/tasks/m4-01-legacy-adapter/plan.md` 的 **L3-b**（适配器 →
  `build_runtime` → `commit_legacy_globals` → 与冻结基线比对）的职责，本报告 §2/§8 里
  点名的 3 个 `NOT_COMPARABLE` 字段（真正的 `derived:index_map` 派生列，见 §8）正是等在
  那道关卡门口，目前未落地——注意这不含 `sections.thickness`：那是这一层适配器自己该接住
  却没接住的一个真实缺陷，不是 L3-b 的待办，见 §0.1/§2/§7。
- **不测数值结果是否一致。** 本报告完全不涉及求解（`adapter-contract.md §7` 明令禁止进
  求解器链接链），不产生位移、应力或任何求解结果，因此对"两条路径算出来的答案是否一致"
  这个问题没有发言权——那是 **L3-c 影子进程夹具**（`yl_state_diff`/`yl_state_probe`）的
  职责。
- **只覆盖两个 golden deck（cooks_membrane、lame_cylinder），只覆盖 static-q4/1 白名单。**
  两案例逐行分类完全一致这件事本身是有用的信号（同一套代码在两份不同几何/边界数据上
  行为一致），但不代表对白名单之外的任意 legacy deck 也成立。
- **oracle 本身不是产品路径、也不是终极真理。** `yl_adapter_harvest.f90` 自己的模块头写
  明它是"驱动真 reader、按映射表机械收割"，不套用 ADR-0002 等仓库侧规范（本报告发现的
  `steps0.boundary.amplitude` 缺陷正是被这种机械性反向暴露出来的，见 §7）；oracle 之外
  还有 M2-03 的冻结基线（`cases/golden/*/reference/state/*`）作为更高一层的独立锚点，
  本报告的 GAP_MAN_STATIC_U 十行（§4）用的正是那一层，不是 oracle。

## 0.1 修正记录（保留可见，不是事后悄悄改掉）

- **checkpoint 指向更正**：任务交底把 `GAP_MAN_STATIC_U` 十行的权威源指向
  `cases/golden/*/reference/state/model_ready/*.json`。核实后这是错的——这十行在
  `docs/m2/state-field-map.toml` 里的 `checkpoint` 是 `phase_ready(1)` /
  `increment_ready(1,1)`，`model_ready` 的锚点（`Fem.f90:1909`）早于 STATIC_U 第一次打开
  `.man` 读取自己的记录，`model_ready/steps.json` 里确实没有这十行。详见 §4。
- **一个真实的 parser 缺陷，已定位、已修复、已回归**：本报告初版曾把
  `steps0.boundary.amplitude` 的分歧判定为"表征差异，无需修 parser"。这个判断是错的，已
  由 team lead 指出并核实：`docs/m2/state-field-map.toml` 该行的 note 原话是"0 = constant
  (no curve) on both cases; otherwise 1..ntcurve"——0 是**已授权的、有明确含义的**值（"这条
  记录没有幅值曲线"），不是"这条记录没有说话"。`yl_adapter_load.f90`（`parse_pre`）原来的
  `if (itcurve /= 0) call opt_set(...)` 把 legacy 明确写下的 0 静默替换成了 unset——这正是
  ADR-0002 要防止的那种混淆，方向搞反了，也正是本关卡验收标准里明令禁止的
  "no user/input value is silently replaced"。该缺陷已由 parser 作者在
  `yl_adapter_load.f90` 修复（改为无条件 `opt_set(bd%amplitude, int(itcurve, int32))`），
  本报告在修复后重新编译、重新在两个 golden deck 上跑过对拍，确认该字段现在
  `MATCH`。详见 §2 该行与 §7。
- **`sections.thickness` 被错误归类，已更正**：本报告曾把 `sections.thickness` 和
  `sections.material_header`/`sections.material` 归为同一类——"finalize/桥要做但这次还没做
  的派生列"，判定 `NOT_COMPARABLE`。这个归类是错的，已由 team lead 核实并指出：
  `sections.thickness` 的 map 行 `source = ['MAT.material_set.elastic_isotropic']`，是一个
  从 `.mat` **读出的、有作者的 deck 值**，不是派生列；而且 map 行的 note 明确把
  "section→material→thickness 的下标换算"这份工作记在了**这一层适配器**（"is the bridge's
  job"），不是某个更下游的阶段。`yl_adapter_material.f90:205` 确实读出了 `thickness`，
  但 :274-276 明确不存它，因为它的 owner 是 `sections[].thickness` 而不是
  `materials[]`——`material_t` 也确实没有能装它的字段。**这个值被读出来又被扔掉了**，没有
  任何地方接住它，不是"下一阶段会处理"。已更正为 `MISMATCH`，cause=unsupported field /
  dropped input，详见 §2 该行；与另外两个真正的派生列分开列出，不再混为一谈。
- **`sections.thickness`：缺陷 → 报告 → 修复 → 回归确认，修复比看起来的一次性局部改动
  大得多**：字段 owner 没有做一个局部补丁，而是发现 `sections[]` 需要跟 `steps[0]`／
  `solver` 一样，成为第三个"跨文件先攒齐、再一次性发布"的聚合对象（contract §2.4）——
  因为 `sections[]` 由 `parse_glb` 发布，legacy 里 `.glb` 先于 `.mat` 读取，而
  `builder_add_section` 和其它单例 setter 一样，一份 `section_t` 发布之后不能再补。于是：
  `parse_glb` 现在只填 `section_parts_t`、不再发布；`parse_mat` 新增
  `resolve_section_thickness`，通过 `ctx%group_matno` 做 section→material 下标换算，填上
  `thickness`；`yl_adapter_driver.f90` 在两个 parser 都跑完之后统一发布 `sections[]`
  （新增的发布块，见该模块头 2026-09-09 的补充说明）。**这不是本报告最初以为的"一个条件
  判断写错了"那种局部修复，而是一次架构变化**——本报告在 §5 已经记录过一次自己的比较器
  bug，这里额外记一笔：一个看起来是"少存一个值"的缺陷，根因排查下去是"这个字段本来就没有
  正确的发布通道"，值得写进沿革里，而不是当作和 `steps0.boundary.amplitude` 一样的
  局部条件反转来交代。团队还额外做了两件本报告的两个 golden deck 结构上做不到的验证（详见
  §7）：(a) 把 map 要求的"两个 section 共用一个 material 但 thickness 不一致就拒绝"实现
  成对一张"先见值"表的真实比较，并写明了为什么这两个 golden deck（`nmats=ngroup=1`）永远
  触发不了这条分支——记录原因，而不是因为触发不了就跳过；(b) 在一个**合成的**两 section／
  两 material（thickness 1.0 与 2.5）deck 和一个 `imat` 被破坏的 deck 上验证了下标换算
  本身，因为两个 golden deck 的 `nmats=ngroup=1` 从结构上就藏住了 section→material 换算
  这一步，本报告的 oracle 对拍在这两个 deck 上永远看不到换算错了会是什么样子。这次修复后
  本报告重新编译全部七个 adapter 模块（`-warn all -stand f18` 零警告）、重新在两个 golden
  deck 上跑过对拍，`sections.thickness` 回归为 `MATCH`（详见 §2、§7）。

## 1. 比较对象与复现命令

### 1.1 关键设计点：比较**两个 draft**，都在 `prepare_problem` 之前

`yl_adapter_driver.adapt_legacy_deck` 在装配完 draft 之后调用 `prepare_problem`，后者做
normalize / validate / capability gate / finalize（下标映射、字段派生、profile 默认值注入）。
若比较两侧"跑完整条 pipeline之后"的 problem，会把"parser 读得对不对"和"finalize 派生/默认注入
是否一致"混在一起，而且会**恰好掩盖住**本关卡最需要暴露的默认值注入。所以：

- **Candidate**：`src/adapter/yl_adapter_fidelity.f90` 里的 `build_candidate` 逐字复刻
  `yl_adapter_driver.adapt_legacy_deck` 的开单元顺序、`probn` 前缀读取、九个 parser
  的调用顺序（`parse_inp → parse_glb → parse_cor → parse_ele → parse_mat → parse_sol →
  parse_loa → parse_pre → parse_man`）与 `steps[0]`/`solver` 的单例装配，唯一的差别是
  **到 `builder_finish` 为止，不调用 `prepare_problem`**。
- **Reference**：`yl_adapter_harvest.harvest_problem_state` 本身就在 `builder_finish` 处停止
  （从未调用 `prepare_problem`），是驱动真 legacy reader（`global_data` / `material_set` /
  `external_load_1` / `prescrib_set` / `PROFILE`）之后按映射表 `legacy_symbol` 逐行收割全局
  变量得到的 draft——这是 legacy 对同一份 deck "真正的理解"的权威陈述，不是本报告发明的标准。

两侧因此是**同一个 draft 类型、同一个 pre-pipeline 阶段**的两份实例，可以逐叶子字段对比。

### 1.2 复现命令

```bash
# 1) 编译 runtime-bridge，复用其 legacy .mod/.o（oracle 需要真 legacy 模块）
tools/build.sh runtime-bridge --profile release

# 2) 编译六个 adapter 源文件 + 本文件，复用 runtime-bridge 的 obj 目录
source tools/env.sh
OUT=build/l3a-fidelity/obj; mkdir -p "$OUT"
cp build/runtime-bridge/release/obj/*.mod build/runtime-bridge/release/obj/*.o "$OUT/"
FFLAGS="-O0 -g -traceback -warn all -stand f18"
for f in src/adapter/yl_adapter_parts.f90 src/adapter/yl_adapter_fem90.f90 \
         src/adapter/yl_adapter_model.f90 src/adapter/yl_adapter_mesh.f90 \
         src/adapter/yl_adapter_material.f90 src/adapter/yl_adapter_load.f90 \
         src/adapter/yl_adapter_harvest.f90 src/adapter/yl_adapter_fidelity.f90; do
  "$HSTAR_FC" -c $FFLAGS -module "$OUT" -I "$OUT" -I "$HSTAR_MKLROOT/include" "$f" \
    -o "$OUT/$(basename "${f%.*}").o"
done

# 3) 链接：runtime-bridge 的全部目标文件（去掉它自己的 PROGRAM 主程序）+ 上面新编译的对象
RB=build/runtime-bridge/release/obj
"$HSTAR_FC" -O0 -g -traceback \
  $(ls "$RB"/*.o | grep -v yl_runtime_bridge_test.o) \
  "$OUT"/yl_adapter_{parts,fem90,model,mesh,material,load,harvest,fidelity}.o \
  -o build/l3a-fidelity/yl_adapter_fidelity \
  -qopenmp -L"$HSTAR_MKLROOT/lib" -lmkl_intel_lp64 -lmkl_intel_thread -lmkl_core \
  -L"$HSTAR_IOMP_LIBDIR" -liomp5 -lpthread -lm -ldl \
  -Wl,--disable-new-dtags -Wl,-rpath,"$HSTAR_MKLROOT/lib" -Wl,-rpath,"$HSTAR_IOMP_LIBDIR"

# 4) 把每个 golden deck 拷贝到 scratch（绝不在 cases/golden 原地跑），cd 进去、无参数运行
#    ——不能传目录参数：yl_diag.diag_set_mode_from_argv 会扫描全部 argv 并对未知参数报错退出，
#    所以 candidate 和 oracle 都按"当前工作目录就是 deck 目录"来读文件。
for case in cooks_membrane lame_cylinder; do
  d=/tmp/scratch/$case; mkdir -p "$d"
  cp cases/golden/static_2d/$case/legacy/* "$d/"
  (cd "$d" && /path/to/build/l3a-fidelity/yl_adapter_fidelity)
done
```

编译：`-warn all -stand f18` 全程 clean（仅有 3 条与本报告无关的
"variable has not been used" remark，均是未使用的哑元/占位变量，不是 error/warning）。
链接：需要 `build/runtime-bridge/release/obj` 里的 legacy `.mod`/`.o`（oracle 一侧
`use global_var` / `materials` / `applied_load` / `prescribed` / `stiffness_matrix` /
`temperature` / `output` / `solver` 等 legacy module）。

两个 golden 案例（`cases/golden/static_2d/cooks_membrane`、`.../lame_cylinder`）都跑通，
`candidate build ok: T`、`reference (oracle) build ok: T`；两案例的 98 行分类结果
**逐行相同**（只有数值不同，分类和 cause 完全一致，`diff` 确认）。以下正文以
cooks_membrane 的输出为准，数值差异（如 boundary 记录数 34 vs 18）在括号里注明。

## 2. 逐字段结果（98 行，`docs/m2/state-field-map.toml` 顺序）

除 10 个 `GAP_MAN_STATIC_U` 行外，reference 一栏均为 `harvest_problem_state (oracle)`；这
10 行的 reference 是 `GAP_REFERENCE`（本文件模块头里的常量表，来自对两个 golden deck 的
`.man` 字节的手工解码，并与冻结基线交叉核对，见 §4）。

| Field id | Reference | 分类 | Cause（仅非 MATCH） | 说明 |
|---|---|---|---|---|
| `case.name` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.dimension` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.nodes.id` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.nodes.xyz` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.elements.id` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.elements.nodes` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.elements.kind` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.elements.group` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.elements.material` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.sets.elset` | harvest_problem_state (oracle) | MATCH | — | — |
| `mesh.sets.nset` | harvest_problem_state (oracle) | NOT_COMPARABLE | unsupported field | candidate 侧 `mesh.nsets[]` 恒为空集合（0 项），因为该字段是 M3-02 finalize 阶段的 `derived:index_map` 派生列，需要从 `steps0.boundary[]` 的 prescrib 记录去重后重建；本对拍在 `prepare_problem` 之前停止，finalize 从未运行。oracle 侧在 `harvest_mesh` 里手工复刻了同样的去重聚合逻辑，因此两侧集合大小不同（0 vs 2），个体条目不可比较。不是 parser 缺陷：candidate 的 parser 从未打算填充这一列（`yl_adapter_parts.f90` 的 leaf 归属表与 M3-02 `yl_problem_pipeline_selftest.f90` 的 derived-row 清单均未把它记在任何 parser 名下）。**下一比对地点（命名，未落地）**：map 行本身的 `checkpoint=model_ready`、`snapshot_file=constraints.sha256`；也就是说这一行要在 candidate 走完整条 `prepare_problem`（finalize 的 index_map 派生）之后，与 `cases/golden/*/reference/state/model_ready/constraints.json`/`.sha256` 冻结基线对拍——这正是 `.ccg/tasks/m4-01-legacy-adapter/plan.md` 的 **L3-b**（"适配器 → `build_runtime` → `commit_legacy_globals` → 与冻结基线比对"）要做的事。核实：`docs/m4/` 目录下目前**没有** L3-b 的报告，尚未落地，不是本报告能替它下结论的。 |
| `materials.id` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.kind` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.name` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.phase` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.model` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.density` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.ratio` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.thickness` | harvest_problem_state (oracle) | **MATCH（修复后回归确认；曾是真实 MISMATCH，见下）** | — | **本行曾是一个真实的、已修复的缺陷，不是派生列（§0.1）**：map 行 `source = ['MAT.material_set.elastic_isotropic']`——`thickness` 是从 `.mat` **读出的、有作者的 deck 值**；map note 明确把 section→material→thickness 的下标换算记在 "the bridge's job"，也就是这一层适配器自己的职责。修复前，`yl_adapter_material.f90:205` 读出了 `thickness` 但 :274-276 不存它（owner 是 `sections[]` 不是 `materials[]`，而当时没有任何字段能接住它），值被读出来又被原地扔掉，candidate 侧永远 unset，违反 "no field is silently dropped"。消费者：`STIFF_U`（`Stiff.f90:116`）与 `gravity`（`Load.f90:1230`）；两个 golden deck 上该值恰好都是 `1.0`（冻结基线 `groups.json`），所以修复前没有数值后果，但任何 `thickness≠1.0` 的 deck 都会静默丢失这个值。**修复不是局部条件反转，而是把 `sections[]` 提升为第三个跨文件先攒齐、再一次性发布的聚合对象**（`section_parts_t`，contract §2.4）：`parse_glb` 只填不发布，新增的 `parse_mat.resolve_section_thickness` 通过 `ctx%group_matno` 做 section→material 换算并填上 `thickness`（连带实现了 map 要求的"两 section 共用 material 但 thickness 不一致就拒绝"，对一张先见值表做真实比较，并写明两个 golden deck 为何永远触发不到这条分支），`yl_adapter_driver.f90` 统一发布。字段 owner 额外在一个**合成的**两 section/两 material（1.0 vs 2.5）deck 和一个损坏 `imat` 的 deck 上验证了换算本身——这两个 golden deck 的 `nmats=ngroup=1` 从结构上就藏住了这一步，本报告的 oracle 对拍在这两个 deck 上永远看不到换算出错的样子，这条证据是本报告的对拍**结构上产生不出来**的（详见 §0.1、§7）。修复后重新编译全部七个 adapter 模块（`-warn all -stand f18` 零警告）、重新对拍两个 golden deck，确认现在 `MATCH`。 |
| `materials.E` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.nu` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.thermal_expansion` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.icreep` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.kind_wt` | harvest_problem_state (oracle) | MATCH | — | — |
| `materials.jliqu` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.element` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.name` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.element_kind` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.class` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.fields` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.special` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.formulation` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.material_header` | harvest_problem_state (oracle) | NOT_COMPARABLE（**手工从程序原始打的 `MISMATCH` 改判，理由见下**） | unsupported field | 程序把这一行原始打成了 `MISMATCH`（candidate unset、oracle=1，逐字节看就是"值不一致"）；本报告改判为 `NOT_COMPARABLE`，理由是——不同于 `sections.thickness`——map 行 `source = ["derived:index_map"]`：这是 M3-02 **finalize 阶段**从 `mesh.elements[].material` 反推的派生列，`yl_adapter_model.f90:55-60,975-980` 的模块头明确写"NOT set here"，即这一层 parser 从设计上就不该填它（不是漏填）。candidate 侧从未尝试填它；oracle 侧在 `harvest_sections` 里手工算了等价值（`element(group(g)%list(1))%matno`，即 Fem.f90:1717 覆盖后的组头材料号）。**下一比对地点（命名，未落地）**：map 行 `checkpoint=model_ready`、`snapshot_file=groups.json`；finalize（`yl_problem_pipeline.f90` 的 index_map 派生，`yl_problem_pipeline_selftest.f90` 已单独验证过这条派生规则本身）跑完之后，应与 `cases/golden/*/reference/state/model_ready/groups.json` 冻结基线对拍——落在 L3-b 范围内，`docs/m4/` 下目前没有对应报告，尚未落地。 |
| `sections.material` | harvest_problem_state (oracle) | NOT_COMPARABLE（**手工从程序原始打的 `MISMATCH` 改判，理由同上**） | unsupported field | 与 `sections.material_header` 同一原因、同一行注释（`source = ["derived:index_map"]`）：candidate 的 `.glb` parser 显式不填它（module 头逐字写明，设计如此，不是漏填），oracle 直接读 `group(g)%matno`。**下一比对地点**：同 `sections.material_header`，`checkpoint=model_ready`、`snapshot_file=groups.json`，L3-b，未落地。 |
| `sections.type_nalgo` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.type_stiff` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.type_ecoint` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.ilayer` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.elcod_local` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.uplift_ic` | harvest_problem_state (oracle) | MATCH | — | — |
| `sections.liquj` | harvest_problem_state (oracle) | MATCH | — | — |
| `amplitudes.type` | harvest_problem_state (oracle) | MATCH | — | — |
| `amplitudes.points.time` | harvest_problem_state (oracle) | MATCH | — | — |
| `amplitudes.points.value` | harvest_problem_state (oracle) | MATCH | — | — |
| `interactions.absorbing.type` | harvest_problem_state (oracle) | MATCH | — | — |
| `solver.linear` | harvest_problem_state (oracle) | MATCH | — | — |
| `solver.symmetric` | harvest_problem_state (oracle) | MATCH | — | — |
| `solver.profile.iafile` | harvest_problem_state (oracle) | MATCH | — | — |
| `solver.profile.icond` | harvest_problem_state (oracle) | MATCH | — | — |
| `solver.profile.ipdchk` | harvest_problem_state (oracle) | MATCH | — | — |
| `solver.profile.ising` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.procedure` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.load_mode` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.controls.nonlinear_type` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.load.gravity.enabled` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.load.gravity.magnitude` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.load.gravity.direction` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.load.gravity.amplitude` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.activation.active` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.activation.material` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.stress_averaging` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.format` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_u` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_s` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_ms` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_f` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_rot` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_v` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_a` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_T` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_P` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_Pv` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_ep` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_Y` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_FC` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_Ns` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_Ss` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_Mxy` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_bem` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_wh` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_wv` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.output.field.gid_bcs` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.boundary.set` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.boundary.dof` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.boundary.amplitude` | harvest_problem_state (oracle) | **MATCH（修复后回归确认；曾是 MISMATCH，见下）** | — | **本行曾是一个真实缺陷，已修复，不是可接受的表征差异**（修正见 §0.1）。map 行的 note 明文规定 "0 = constant (no curve) on both cases; otherwise 1..ntcurve"：legacy 在每条 `set_header` 记录上都**明确写下**了 itcurve，0 是一个有定义的值（"这条记录没有幅值曲线引用"），不是"记录没有说话"。修复前，`yl_adapter_load.f90` 的 `if (itcurve /= 0) call opt_set(bd%amplitude, ...)` 把 itcurve=0 静默丢成了 unset——`grep -a` 核对两个 golden deck 的 `.pre` 字节确认 itcurve 在全部 34（cooks_membrane）/18（lame_cylinder）条记录上都是 0，而冻结基线 `cases/golden/static_2d/cooks_membrane/reference/state/model_ready/constraints.json` 把这个字段导出为字面 `[0, 0, ..., 0]`（34 个 0，已核实），不是 unset。真值是"deck 写了 0"，candidate 曾把它变成"deck 什么都没写"——这是本关卡验收标准里明令禁止的 "no user/input value is silently replaced"，判定 cause=**default injection / silent substitution**（本报告判为 silent substitution：不是下游注入了一个默认值，而是 parser 自己的守卫逻辑把已授权的输入值替换成了缺省态）。已由 parser 作者在 `yl_adapter_load.f90` 改为无条件 `call opt_set(bd%amplitude, int(itcurve, int32))` 并在源码里补充了说明；本报告重新编译、重新在两个 golden deck 上跑过，该字段现在两侧都是 `0`，`MATCH`。 |
| `steps0.boundary.nodes` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.boundary.value` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.boundary.record_reaction` | harvest_problem_state (oracle) | MATCH | — | — |
| `steps0.controls.increments` | GAP_REFERENCE（`.man` 字节手工解码 + 冻结基线交叉核对） | MATCH | — | 见 §4 |
| `steps0.controls.max_iterations` | GAP_REFERENCE | MATCH | — | 见 §4 |
| `steps0.controls.time_increment` | GAP_REFERENCE | MATCH | — | 见 §4 |
| `steps0.output.frequency_nodes` | GAP_REFERENCE | MATCH | — | 见 §4 |
| `steps0.output.frequency_fields` | GAP_REFERENCE | MATCH | — | 见 §4 |
| `steps0.controls.steps` | GAP_REFERENCE | MATCH | — | 见 §4 |
| `steps0.controls.step_increment` | GAP_REFERENCE | MATCH | — | 见 §4 |
| `steps0.controls.restart_frequency` | GAP_REFERENCE | MATCH | — | 见 §4 |
| `steps0.controls.tolerance_force` | GAP_REFERENCE | MATCH | — | 见 §4 |
| `steps0.controls.tolerance_dof` | GAP_REFERENCE | MATCH | — | 见 §4 |

## 3. 计数

| 分类 | 工具原始输出（程序 `SUMMARY` 行，两个 golden 案例一致） | 本报告终审判定 — 验收结论 |
|---|---|---|
| MATCH | 95 | **95** |
| MISMATCH | 2 | **0** |
| NOT_COMPARABLE | 1 | **3**（`mesh.sets.nset`、`sections.material_header`、`sections.material`，均为真正的派生列，各自的下一比对地点见 §2） |
| UNVERIFIED | 0 | 0 |

（共 98 行，两个 golden 案例逐行一致；`steps0.boundary.amplitude` 与 `sections.thickness`
均已修复并回归为 `MATCH`——见下方沿革。）

**沿革**（四次计数，都是真实跑出来的，不是笔误——把每一次的错误也留在这里，而不是只留
最后一次看起来"干净"的结果）：

1. **初版**（`steps0.boundary.amplitude` 缺陷修复前）：MATCH=93 / MISMATCH=1（把该缺陷误判
   为可接受的"normalization difference"）/ NOT_COMPARABLE=4（把 `sections.thickness` 和
   两个真正的派生列混在一起）。
2. **`steps0.boundary.amplitude` 修复后重新跑**：回归为 `MATCH`；工具原始输出变为
   `MATCH=94|MISMATCH=3|NOT_COMPARABLE=1`，本报告当时仍把 3 个 `MISMATCH` 全部改判为
   `NOT_COMPARABLE`（沿用了初版对 `sections.thickness` 的错误归类）。
3. **`sections.thickness` 归类更正**（尚未修复）：team lead 核实指出它不是派生列（map
   `source` 是一个真实 deck 读数，不是 `derived:*`；且 note 明确把下标换算记在"the
   bridge's job"，即这一层适配器自己），是一个"值被读出来又被扔掉、没有任何地方接住"的
   真实缺陷，改判为 `MISMATCH`。终审判定当时是 **94/1/3/0**，工具原始输出仍是
   **94/3/1/0**。
4. **`sections.thickness` 修复后重新跑（本次，验收结论）**：字段 owner 把 `sections[]`
   提升为第三个跨文件先攒齐、再一次性发布的聚合对象（`section_parts_t`，contract
   §2.4，详见 §0.1），重新编译全部七个 adapter 模块（零警告）后重新对拍，该字段回归为
   `MATCH`。终审判定定格在 **95/0/3/0**，工具原始输出 **95/2/1/0**——两者都保留在
   headline 和上表，避免只留一组数字掩盖了历次改判本身。

上表右列"终审判定"与左列"工具原始输出"不一致，是**故意的**：程序对"两侧都 unset"这种情况
的自动 cause 标注只是初筛线索，不是终审结论（`yl_adapter_fidelity.f90` 模块头原话："this
program's tag is a lead, not a verdict"）。这也是为什么本报告要把两组数字都摆在最前面
（headline）和这里，而不是只留改判后的数字。程序里已修的一个 bug 把 `mesh.sets.nset` 从
"假 MATCH"纠正为 `NOT_COMPARABLE`（见 §5），这一条改判从第一次起就没再变过。

## 4. GAP_MAN_STATIC_U：oracle 覆盖不到的 10 行

`yl_adapter_harvest.f90` 自己的模块头列出了 10 行它无法触达的字段：STATIC_U（`Fem.f90:
3593-3633`）里的四条 `.man` 读取，STATIC_U 是 `PROGRAM FEM90` 的内部子程序，触达它就是进
求解器链接链，被 `adapter-contract.md §7` 明令禁止。任务说明指向
`cases/golden/*/reference/state/model_ready/*.json` 作为这 10 行的替代权威源——**这个指向
需要更正**：这 10 行在 `docs/m2/state-field-map.toml` 里自己的 `checkpoint` 是
`phase_ready(1)`（`steps0.controls.increments`）和 `increment_ready(1,1)`（其余 9 行），
根本不是 `model_ready`——`model_ready` 的锚点在 `Fem.f90:1909`，早于 STATIC_U 第一次打开
`.man` 读取自己的记录，`model_ready` 目录下的 `steps.json` 里确实没有这 10 行（已核实）。

正确的权威源是 `phase_ready(1)/steps.json` 与 `increment_ready(1,1)/steps.json`。两个 golden
deck 的 `.man` 文件字节完全相同（`diff` 确认），手工解码四条记录：

```
record 1 (title,  不读): "nincs,cdtest,earthquake_curve(1:ndimn)"
record 2 (nincs)      : "  1  0  0  0"                     -> nincs=1
record 3 (increment_control)
                       : "  5  1.0  1  1  1  1  1  0  0"
                         -> miter=5 ditime=1.0 noutn=1 noutf=1 nstep=1
                            inc_step=1 nresta=1 cwater=0 qstatic=0
record 4 (tolerances, mdofn=2)
                       : "  3*1.0e-05"   (Fortran 重复计数：三个 1.0e-05)
                         -> toler_force=1.0e-05, toler_var(1:2)=[1e-05, 1e-05]
```

与冻结基线交叉核对（两个 golden 案例的值完全相同）：

| Baseline 文件 | 字段 | 值 |
|---|---|---|
| `phase_ready(1)/steps.json` | `steps0.controls.increments` | `1` |
| `increment_ready(1,1)/steps.json` | `max_iterations` | `5` |
| 同上 | `restart_frequency` / `step_increment` / `steps` | `1` / `1` / `1` |
| 同上 | `time_increment` | hex `3FF0000000000000` = 1.0 |
| 同上 | `tolerance_force` / `tolerance_dof[1:2]` | hex `3EE4F8B588E368F1` = 1.0e-05（两项相同） |
| 同上 | `frequency_nodes` / `frequency_fields` | `1` / `1` |

手工解码与冻结基线**完全吻合**，本报告把这十个值当常量表（`yl_adapter_fidelity.f90` 的
`GAP_INCREMENTS` 等 `GAP_*` 参数）与 candidate 的 `parse_man` 输出对拍，全部 `MATCH`。

## 5. 一个在开发过程中发现并修正的程序 bug（不是 parser 的 bug）

初版对拍程序对"集合行数不同"（如 `mesh.nsets[]` candidate=0、reference=2）的处理是
"只比较 `min(n_c, n_r)` 个条目"，当 `min` 为 0 时循环体不执行、`all_ok` 保持初值
`.true.`，于是把 `mesh.sets.nset` 打成了 `MATCH`——这正是团队交底里明令禁止的
"没有证据反驳就记 MATCH"。已在 `yl_adapter_fidelity.f90` 里加入 `cmp_field_sizes`：
集合行数不一致时，该集合下的每个字段一律先发 `NOT_COMPARABLE`，不再退化成对截断前缀的
比较（`cmp_count`/`cmp_field_sizes` 的注释里写明了这条规则本身）。修复后重新编译、
重新在两个 golden deck 上跑过，本报告 §2/§3 的数字是修复后的结果。

## 6. 归一化与容差规则（一次性声明，适用于全部比较）

- `docs/m2/state-field-map.toml` 的全部 98 个 `ProblemState.*` 行 `compare.rule` 均为
  `exact`（已用脚本核实，无一例外）。
- 整数、文本：位/字符精确相等；文本额外做 `trim()`（两侧都做，映射表注释里的既定约定，
  如 `case.name` 一行的 note）。
- 实数：`yl_problem_optional.opt_equal` 做 IEEE binary64 位模式比较
  （`transfer(x%value, 0_int64)`），**不是** epsilon 容差。理由：两侧读的是**同一份 deck
  文件里同一个十进制字面量**，通过**同一个 Fortran list-directed real64 读**解析，同一
  个编译器下必然产生位相同的值；在这条规则下出现不相等，才是真正的语义分歧（不同字面量、
  单位换算、重新计算得到的值），而不是"编译器噪声"——所以这条规则没有例外可留。
- 集合（节点、单元、材料、截面、幅值曲线、边界记录、激活记录）按 **1 基、记录序** 逐项对
  应比较；两侧都是按同一批底层 deck 记录的顺序遍历的（节点 i0=1..npoin、单元 i0=1..nelem、
  组 1..ngroup、材料 1..nmats、prescrib 记录 1..ndofix、激活按组 1..ngroup、幅值曲线
  1..ntcurve、幅值点 1..ntime）——这不是为了方便才做的假设，而是"同一条 deck 记录"这句话
  在两条路径上本来就是这个意思，写在这里是为了让它可被证伪，而不是被默默信任。
- **集合行数不一致时不做逐项比较**（见 §5），一律 `NOT_COMPARABLE`。

## 7. 每一处 silent substitution / default injection 的检查

- **发现过一处 silent substitution，已修复、已回归确认**：`steps0.boundary.amplitude`
  （§0.1、§2）。legacy 在每条 `.pre` `set_header` 记录上都明确写下了 `itcurve`，map 行的
  note 把 0 定义为"constant (no curve)"——一个**有意义的输入值**，不是缺席。修复前的
  `yl_adapter_load.f90` 用 `if (itcurve /= 0) call opt_set(...)` 把 `itcurve=0` 静默替换成
  了 unset：deck 说了"0"，candidate 却让 ProblemState 看起来像"deck 什么都没说"。这正是
  验收标准里"no user/input value is silently replaced"要防止的那种缺陷，本报告最初把它
  误判成了可接受的表征差异——那个判断是错的，已被 team lead 指出并核实（冻结基线
  `constraints.json` 把该字段导出为字面 `0`，不是 unset，实锤了"deck 说了 0"这一事实）。
  已由 `yl_adapter_load.f90` 的作者修复为无条件写值，本报告修复后重新编译、重新对拍两个
  golden deck，确认现在两侧都是 `0`，`MATCH`。
- **发现过一处字段被静默丢弃（silent drop of an authored input），已修复、已回归确认**：
  `sections.thickness`（§0.1、§2）。这一行**不属于**"下一阶段该做的派生"一类——map 行
  `source = ['MAT.material_set.elastic_isotropic']` 说明 `thickness` 是从 `.mat` 读出的、
  有作者的 deck 值，map note 把 section→material→thickness 的下标换算明确记在
  **这一层适配器**（"the bridge's job"）名下，不是某个下游阶段。修复前，
  `yl_adapter_material.f90:205` 读出了这个值，:274-276 却因为"owner 是 sections[] 不是
  materials[]"而不存它，且没有任何其它 parser 接住它——**值进来了，出去时不见了**，没有
  中间某个阶段"稍后会做"，判定 cause=**unsupported field / dropped input**：consumer 是
  `STIFF_U`（`Stiff.f90:116`）和 `gravity`（`Load.f90:1230`），两个 golden deck 上该值
  恰好都是 `1.0`（冻结基线 `groups.json`），修复前没有数值后果，但任何 `thickness≠1.0`
  的 deck 都会在这条路径上丢失这个输入——这正是验收标准 "no field is silently dropped"
  要防止的情形。**本报告最初把这一行和另外两个真正的派生列混为一谈，判定为可推迟的
  `NOT_COMPARABLE`，这个归类是错的**，已由 team lead 核实指出并更正为 `MISMATCH`。
  字段 owner 随后修复了它——不是一个条件判断的局部反转，而是把 `sections[]` 提升为第三个
  跨文件先攒齐、再一次性发布的聚合对象（`section_parts_t`，contract §2.4：`parse_glb` 只
  填不发布，`parse_mat` 新增的 `resolve_section_thickness` 通过 `ctx%group_matno` 做
  section→material 换算并填上 `thickness`，`yl_adapter_driver.f90` 统一发布），详见
  §0.1。**本报告的对拍本身证明不了这次修复是对的**，只能证明"两个 golden deck 上现在
  MATCH 了"——两个 golden deck 都是 `nmats=ngroup=1`，section→material 换算这一步在这两
  个 deck 上从结构上就是平凡的（1 对 1），本报告的 oracle 对拍看不出换算错了会是什么样子。
  字段 owner 额外在一个**合成的**两 section／两 material（thickness 1.0 vs 2.5）deck 和
  一个损坏 `imat` 的 deck 上验证了换算本身，并把 map 要求的"两 section 共用 material 但
  thickness 不一致就拒绝"实现成对一张先见值表的真实比较（而不是因为在两个 golden deck 上
  永远触发不到就跳过，理由写在了 `yl_adapter_material.f90` 里）——这份证据本报告的方法
  论**结构上产生不出来**，是对本报告覆盖盲区的补充，不是本报告自己的结论，如实记在这里。
  本报告在修复落地后重新编译全部七个 adapter 模块（零警告）、重新对拍两个 golden deck，
  确认现在 `MATCH`。
- **没有发现 default injection**：candidate 侧全程未调用 `prepare_problem`，而
  `sections[].stress_components` 这类唯一已知的 M3-02 profile 默认值注入点属于 finalize
  阶段（`yl_problem_pipeline_selftest.f90` 的 `check_default` 断言），本次对拍范围之外，
  预期之中，不构成本报告意义上的"发现"。
- **另外 3 个 NOT_COMPARABLE 不是"字段被静默丢弃"，但也不是"已了结"**：`mesh.sets.nset` /
  `sections.material_header` / `sections.material`（不含上面单独列出的
  `sections.thickness`）的"不填"都在各自 parser 的模块头里**逐字写明并给出理由**（引用见
  §2 各行），且都对应 map 行 `source = ["derived:index_map"]`——设计上就该由更下游的
  finalize 阶段计算，不是这一层遗漏。但"有理由的 scope 边界"不等于"保真度已验证"——§2 已
  为每一行指名了下一次应该在哪里、用哪个冻结基线文件核实（均落在
  `.ccg/tasks/m4-01-legacy-adapter/plan.md` 的 L3-b，当前**尚未落地**），不是把它们悬空
  留在这里。

**STOP RULE 检查**：`steps0.boundary.amplitude` 和 `sections.thickness` 各自都触发过一次
"发现即停"——都符合"可能意味着输入被重新解释了语义/被静默丢弃"的描述，均已按 STOP RULE 的
要求单独报告（先于继续扩大覆盖面或粉饰归类），都交给了对应 parser/字段的 owner 定位修复，
本报告都没有自行改比较规则去让它们"通过"或"看起来可以推迟"，两者现在都已修复并回归确认为
`MATCH`。修复后重新跑本关卡本身也是 STOP RULE 流程的一部分——**不是"报告了就算数"，是
"修复后必须让同一个关卡再验一遍，且验的结果必须真的是 MATCH，不能只是不再报错"**（这条
在 `sections.thickness` 上被明确要求过："若不是 MATCH，STOP，因为那意味着换算算错了，比
原来的缺陷更糟"——本次重新跑确认了是 `MATCH`，没有触发这第二层 STOP）。其余 3 个
NOT_COMPARABLE（真正的派生列）逐一读过对应的 parser/oracle 源码之后，没有一个指向"输入被
重新解释了语义"或"被丢弃"——都是已登记的、有理由的 scope 边界（下一阶段该做的事这次还
没做，具体去处见 §2），因此没有对它们触发"发现即停"。

## 8. 结论：parser 正确性是否得到了独立支持？

对 **95/98**（96.9%）行——包括全部网格几何（节点坐标、单元连通性、单元种类/材料/组）、
全部材料属性、**全部**截面属性（含修复后的 `sections.thickness`）、全部幅值曲线、
interactions、solver（含 PROFILE 四个控制参数）、`steps[0]` 的
procedure/load_mode/controls.nonlinear_type/gravity/activation/output（含全部 20 个 GID
输出请求标志）、`steps0.boundary[]` 的**全部 6 个**分量、以及全部 10 个
`GAP_MAN_STATIC_U` 行——**是**：candidate parser 与驱动真 legacy reader 的独立 oracle
逐字段精确相等（10 个 GAP 行则与 `.man` 字节的手工解码 + 冻结基线的独立交叉核对精确相等），
这是此前"两个 golden deck 零 finding"从未证明过的、真正意义上的 input-to-model 保真度
证据。这 95 行里包含了**两次**真实的、被本报告找到并促成修复的缺陷（`steps0.boundary.
amplitude` 的 silent substitution，`sections.thickness` 的 dropped input，见
§0.1/§2/§7）——这本身就是"零 finding 不足以支撑 input-to-model 保真度"这个论点的直接证据：
内部一致性检查从未也不可能发现这两个缺陷，因为候选 parser 自己是自洽的（it never
contradicted itself），只有跟一个独立于它的权威源逐字段对拍才会暴露；`sections.thickness`
尤其如此——它的根因（`sections[]` 缺一个跨文件发布通道）在两个 golden deck 上完全不产生
可观察的内部矛盾，是纯粹靠对拍才浮出水面的一类缺陷。

对以下 3 行，本报告**不能**给出"已确认一致"的结论，但理由是同一类，且已逐一命名去处：

- **`mesh.sets.nset`、`sections.material_header`、`sections.material`——3 行是下一阶段
  该做、这次对拍范围内还没做的工作**（终审判定 `NOT_COMPARABLE`）：candidate 在这次比较
  的阶段边界内**正确地**什么都没做（均为 map 行 `source = ["derived:index_map"]`，设计上
  由 finalize 计算——这一点已单独跟 `sections.thickness` 核实区分过，见 §0.1、§7，不再是
  一次可能的误判）。§2 已为每一行指名了具体的下一比对地点（`checkpoint=model_ready`，
  `snapshot_file=groups.json`/`constraints.sha256`，对应
  `.ccg/tasks/m4-01-legacy-adapter/plan.md` 的 **L3-b**）——核实：`docs/m4/` 目录下目前
  **没有** L3-b 的报告，这三行的保真度因此是**已命名、待兑现**的义务，不是被本报告悄悄
  收纳掉的灰色地带。

终审判定 MISMATCH=0、NOT_COMPARABLE=3（均为真正的派生列，已逐一给出下一比对地点），
**本次是 L3-a 的验收结论**：在本次对拍覆盖的 98 个 `ProblemState.*` 字段范围内，parser 的
input-to-model 保真度在 95 行上获得了独立于"零 finding"之外的第二重证据（其中 2 行——
`steps0.boundary.amplitude` 与 `sections.thickness`——是靠这重证据才发现并纠正的真实
缺陷，均已修复并回归确认为 `MATCH`）；其余 3 行的保真度不在本报告的比较阶段内，去处已经
点名，等 L3-b 落地后应用同样的方法在那里重新核实。**没有遗留的 MISMATCH，也没有遗留的
UNVERIFIED**，本报告到此认为 L3-a 覆盖范围内的 parser 保真度已获独立支持，验收决定交
team lead。
