# M1-01 首条静力路径 reader / 文件 / 游标清单

- 路径：2D Q4 平面应变线弹性、PROFILE、重力体力、单阶段单增量（`cases/golden/static_2d/{cooks_membrane,lame_cylinder}`）
- 源码：`legacy/yl` = `hstarYLOrig@5414e73`（`legacy/source-manifest.json`）
- 权威注册表：`docs/m1/reader-inventory.toml`；静态全集：`docs/m1/io-sites.json`；
  执行证据：`docs/m1/evidence/<case>/hits.json`
- 校验：`python3 tools/yl_io_inventory.py check --evidence docs/m1/evidence/*/hits.json`
- 本文件由 `tools/yl_io_inventory.py render` 生成的表附在叙述之后；改动注册表后重新生成。

## 方法

1. **静态全集**：扫描 17 个源文件中所有 `READ/OPEN/CLOSE/REWIND/BACKSPACE/INQUIRE` 语句（含单行
   `if (cond) read(...)` 形式），共 1022 处，记录文件、行号、例程、单元变量、合并续行后的语句文本
   与锚点哈希。源码按 latin-1 逐字节解码，只按 LF/CRLF 分行（`str.splitlines()` 会把 GBK 注释里的
   0x85 字节当成换行，导致 Fem.f90 行号偏移；已修正）。
2. **执行实证**：`tools/build.sh trace`（`-O0 -g -traceback`，无运行时检查）构建后，`tools/yl_io_trace.sh`
   在隔离副本中用 `gdb -batch` 于每个位点设断点，记录命中次数。两例各约 10 s；运行产物
   `1.flavia.res` 与冻结 reference 逐字节相同，证明插桩未扰动结果。
3. **登记**：每个已执行 read 位点一条 `[[reader]]`，字段契约由语句文本与 deck 记录核对得出；
   `open/rewind` 登记为 `[[cursor_op]]`；未执行候选按单元归并为 `[[not_on_path]]` 并写明 guard 与
   归属阶段。

## 结果概览

| 项 | 数量 |
|---|---|
| 静态全集位点 | 1022（read 886、open 80、rewind 54、close 2） |
| 两例断点命中位点（机器实证） | 211（两例完全相同）——**下限，非精确计数：见下方"盲区与限制"** |
| 其中 read | 153（150 条实际执行 + 3 条 `reached_only`） |
| 其中 open / rewind | 46 / 13（其中 11 条 rewind 与 6 条 open 为 `reached_only`） |
| 未执行候选 | 810 处，54 个单元组 |

`reached_only`：单行 `if (cond) stmt` 的断点在条件为假时同样命中；这些条目记录 `condition_value`，
`executed_by` 为空。本路径上的取值：`meshc=0, rmesh=0, Bparameter=0, nlayer=0, type_abc='FIX', iafile=0`。

## 读取阶段与游标时间线（cooks_membrane，lame_cylinder 相同）

| 顺序 | 单元/文件 | 例程 | 内容 | 阶段 |
|---|---|---|---|---|
| 1 | `inp` | FEM90:93–96 | 标题、运行控制、标题、问题名 | startup |
| 2 | 全部约 40 个单元 | global_data:628–673 | 按 probn 打开所有输入/输出文件 | startup |
| 3 | `.glb` | global_data:675–1069 | 控制记录（尺寸、开关、求解器类型、DOF、块表、输出标志…） | startup |
| 4 | `.ftr` | global_data:834–835 | 表面力计数（全 0） | startup |
| 5 | `.cor` | global_data:1089 ×npoin | 节点坐标 | startup |
| 6 | `.glb` | global_data:1096–1145 | 组记录（单元类型/公式/材料号/DOF 列表） | startup |
| 7 | `.ele` | read_element (Elements.f90:1083) ×nelem | 单元连接 | startup |
| 8 | `.nrt` | global_data:1361–1363 | 插值组计数（0） | startup |
| 9 | `.glb` | global_data:1675–1692 | 节理计数（0） | startup |
| 10 | `inp` | FEM90:177 | runblks | startup |
| 11 | `.mat` | material_set | 曲线计数、注释、材料头、ELASTIC_ISOTROPIC | startup |
| 12 | `.glb` | contact/steel/pipe:3328–4538 | 接触、钢筋、水管计数（0） | startup |
| 13 | `.ifs` | Stiff 四个例程 | FSI/吸收边界计数（0） | startup |
| 14 | `.opr` | output_read | 输出控制（全 0） | startup |
| 15 | `.man` | FEM90:317 | **rewind**（restart 预扫循环 0 次后的游标复位） | cursor_op |
| 16 | `.loa` | external_load_1 | 时间曲线、点荷载计数、边计数 | startup |
| 17 | `.pre` | prescrib_set ×2 集 | 约束集头（8 字段）、节点、值 | startup |
| 18 | `.loa` | external_load_2 | 边荷载计数、重力、组曲线、梁/板荷载计数 | startup |
| 19 | `.tem` | boundt | 温度边界计数（0） | startup |
| 20 | `.sol` | **PROFILE** (Solver.f90:6827–6828) | 求解器控制 | **solver_lazy**：第一次线性求解时才读 |
| 21 | `.man` | **STATIC_U**:3582–3583 | 标题、nincs | **phase_lazy(1)** |
| 22 | `.man` | STATIC_U:3611–3612 | 增量控制（9 字段）、容差 | **increment_lazy(1,1)** |
| 23 | `.rtt` | RESTA_READ_WRITE:16353 | rewind 后写重启文件 | cursor_op（写路径） |

`.man` 的其他读取点（`back_analysis` 2394 起、动力/热/渗流分支、`Qstatic/cwater` 子记录）
在本路径均未执行；`STATIC_U` 入口的两个条件 rewind（3577–3578）条件为假。

## 对 M1-02 / M2-01 的直接输入

- M1-02 checked I/O：`[[reader]]` 的 `file / routine / seq / fields / format` 即错误报文的
  文件、reader、记录、字段；`guard` 说明为何某记录可能不出现。
- M2-01 状态映射：`fields` 中每个字段的 `:目标` 后缀与条目级 `state_target` 直接对应 ADR-0003
  的 ProblemState 对象；`derived` 字段禁止出现在 modern 输入中；`unused_switch` 与 `empty_section`
  字段在 M5 白名单内必须为 0/默认值，否则 `UNSUPPORTED_CAPABILITY`。

## 盲区与限制

- 两例控制文件字节相同，guard 分支只有一个样本；另一侧留待 M1-03 负向探针与后续能力切片。
- 断点计数的是语句到达次数，不区分 list-directed READ 实际跨越的物理记录数；`seq` 是语句
  首次到达时在该单元读序列中的序号，rewind 后的重读会另立条目（本路径没有发生）。
- 读入但未消费的字段（大量 0 值开关）只能靠人工追踪 `consumers`；M2-03 的单变量扰动会验证。
- 未覆盖：`.glb` 中被列表读取忽略的多余数值、`.man` 首记录中 `nincs` 之后被忽略的 3 个值，
  这些在 M1-02 需按"记录多余项"报警而非静默丢弃。
- 已知缺陷 R17/R18 不影响读取点集合；R18 的触发条目是 `PRE.prescrib_set.set_header` 的
  `itcurve=0`。
- **断点计数法本身有盲区**：`gdb-script` 对每个位点只下一个 `break FILE:LINE`，取行表里该行的
  第一个地址。`LOA.external_load_1.curve_factors`（`Load.f90:231`）在编译后的目标码里对应
  两段不相邻的地址，行表的"第一个地址"恰好是从未被执行到的一段，导致该处执行了但从未计入
  211 这个命中集合——只有手工在正确地址下断点才捕捉到。这是本次两个金标准算例里唯一已知的
  实例，但工具本身无法系统性地发现同类盲区（详见
  `docs/m1/M1-finding-2026-09-08-unwrapped-loa-read.md` "工具根因"一节）。**因此 211 这个数字
  是命中位点数的下限，不是精确测量**——它统计的是"断点生成器能看见的执行"，不是"实际执行"。

## 已执行读取点（reader）

### `inp`（inpunit，5 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `INP.FEM90.title#1` | FEM90 | `Fem.f90:97` | 1 | `text:str` | text_skip | always | startup | FEM90 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `INP.FEM90.run_control` | FEM90 | `Fem.f90:99` | 2 | `restart:int`<br>`relis:int`<br>`sysrelis:int`<br>`ADINA:int`<br>`Uopt_R:int`<br>`gamamax:int` | list_directed | always | startup | FEM90 (restart/relis branches), STATIC_U | `not_migrated` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `INP.FEM90.title#2` | FEM90 | `Fem.f90:101` | 3 | `text:str` | text_skip | always | startup | FEM90 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `INP.FEM90.problem_name` | FEM90 | `Fem.f90:103` | 4 | `probn:str` | list_directed | always | startup | global_data (open of every probn-based file) | `case.name` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `INP.FEM90.runblks` | FEM90 | `Fem.f90:185` | 5 | `runblks:int` | list_directed | always | startup | FEM90 block loop | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.cor`（cunit，1 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `COR.global_data.node_coordinates` | global_data | `Global.f90:1176` | 1 | `i0:int:mesh.nodes[].id`<br>`coord[1:ndimn]:real:mesh.nodes[].xyz` | list_directed | loop ipoin=1..npoin | startup | everything | `mesh.nodes` | static_2d.cooks_membrane:289, static_2d.lame_cylinder:81 |

### `.ele`（iunit，1 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `ELE.read_element.element_connectivity` | read_element | `Elements.f90:1087` | 1 | `i0:int:mesh.elements[].id`<br>`lnods[1:nnode]:int:mesh.elements[].nodes` | list_directed | loop over elements of each group | startup | everything | `mesh.elements` | static_2d.cooks_membrane:256, static_2d.lame_cylinder:64 |

### `.ftr`（ftfread，2 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `FTR.global_data.title#1` | global_data | `Global.f90:878` | 1 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `FTR.global_data.force_counts` | global_data | `Global.f90:880` | 2 | `nforce:int`<br>`ngaps:int`<br>`nforce_gaps:int`<br>`nsafety_gaps:int` | list_directed | always | startup | surface force / gap safety | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.glb`（gunit，75 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `GLB.global_data.title#1` | global_data | `Global.f90:691` | 1 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.sizes_and_switches` | global_data | `Global.f90:694` | 2 | `npoin:int:derived(mesh.nodes)`<br>`npoinb:int:derived`<br>`nelem:int:derived(mesh.elements)`<br>`ndimn:int:mesh.dimension`<br>`nmats:int:derived(materials)`<br>`ngroup:int:derived(sections)`<br>`ntlink:int:unused_switch`<br>`outplot:str:output_control`<br>`kstab:real:unused_switch`<br>`mat_curve:int:unused_switch`<br>`meshc:int:unused_switch`<br>`rmesh:int:unused_switch`<br>`level_set_problem:int:unused_switch`<br>`ljdp:int:unused_switch`<br>`stab_matde:int:unused_switch` | list_directed | always | startup | global_data allocations; every reader | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#2` | global_data | `Global.f90:720` | 3 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#3` | global_data | `Global.f90:725` | 5 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#4` | global_data | `Global.f90:759` | 6 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.init_and_blocks` | global_data | `Global.f90:762` | 7 | `ninit:int:unused_switch`<br>`kinit:int:unused_switch`<br>`winit:int:unused_switch`<br>`nblks:int:derived(steps)`<br>`nlinks:int:unused_switch`<br>`nonsym:int:solver.symmetric`<br>`outinp:int:output_control`<br>`outintr:int:output_control`<br>`outintw:int:output_control`<br>`neuman:int:unused_switch`<br>`equvs:int:unused_switch`<br>`type_ABC:str:interactions(absorbing)`<br>`block_stab:int:unused_switch`<br>`nbackf:int:unused_switch`<br>`nbspring:int:unused_switch`<br>`ebody:int:unused_switch`<br>`outind:int:output_control`<br>`nbackdT:int:unused_switch`<br>`ninistn:int:unused_switch` | list_directed | always | startup | global_data, process_analysis, prescrib_set (type_ABC), FEM90 (nbackf) | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#5` | global_data | `Global.f90:786` | 8 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.problem_type` | global_data | `Global.f90:789` | 9 | `type_problem:str:steps[0].procedure`<br>`type_solver:str:solver.linear`<br>`type_load:str:steps[0].load_mode`<br>`type_nl:int:steps[0].controls`<br>`stabpw:int:unused_switch`<br>`nlayer:int:unused_switch`<br>`kglb:int:unused_switch`<br>`state_change:int:unused_switch`<br>`Bparameter:int:unused_switch`<br>`balgor:int:unused_switch`<br>`upliftin:int:unused_switch` | list_directed | always | startup | process_analysis dispatch (Q -> STATIC_U), PROFILE | `steps[0].procedure` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#6` | global_data | `Global.f90:807` | 10 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#7` | global_data | `Global.f90:812` | 12 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.material_class_counts` | global_data | `Global.f90:815` | 13 | `nmass:int:unused_switch`<br>`nsmat:int:derived`<br>`nhmat:int:unused_switch`<br>`nqmat:int:unused_switch`<br>`nldfl:int:unused_switch`<br>`kgmat:int:unused_switch`<br>`nswkw:int:unused_switch`<br>`uwcpl:int:unused_switch`<br>`NGRAV:int:steps[0].load(gravity)`<br>`nflow:int:unused_switch`<br>`ECWPIPE:int:unused_switch` | list_directed | always | startup | material_set, external_load_2 (NGRAV) | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#8` | global_data | `Global.f90:818` | 14 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#9` | global_data | `Global.f90:830` | 15 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.special_counts` | global_data | `Global.f90:833` | 16 | `ntsmat:int:unused_switch`<br>`nthmat:int:unused_switch`<br>`kstat:int:unused_switch`<br>`ground_inf:int:unused_switch`<br>`src:int:unused_switch`<br>`nextrf:int:unused_switch`<br>`submodel:int:unused_switch` | list_directed | always | startup | global_data | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#10` | global_data | `Global.f90:948` | 17 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.mdofn` | global_data | `Global.f90:950` | 18 | `mdofn:int` | list_directed | always | startup | global_data DOF map, every field loop | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.lmdofn` | global_data | `Global.f90:955` | 19 | `lmdofn[1:mdofn]:int` | list_directed | always | startup | global_data DOF map, Output, prescrib_set | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.order_time_mdofn` | global_data | `Global.f90:957` | 20 | `order_time_mdofn[1:mdofn]:int` | list_directed | always | startup | dynamic time integration | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#11` | global_data | `Global.f90:959` | 21 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.newmark` | global_data | `Global.f90:961` | 22 | `beeta1:real`<br>`beeta2:real`<br>`theta1:real` | list_directed | always | startup | dynamic time integration | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#12` | global_data | `Global.f90:973` | 23 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.equvs_process` | global_data | `Global.f90:976` | 24 | `equvs_process[1:ngroup]:int` | list_directed | always | startup | global_data | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#13` | global_data | `Global.f90:980` | 25 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.appear_level` | global_data | `Global.f90:983` | 26 | `appear_level[1:ngroup]:int` | list_directed | always | startup | global_data | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#14` | global_data | `Global.f90:985` | 27 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.appear_process` | global_data | `Global.f90:989` | 28 | `appear_process[1:ngroup,iblk]:int` | list_directed | loop iblk=1..nblks (1) | startup | process_analysis activation of groups per block | `steps[0].activation` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#15` | global_data | `Global.f90:994` | 29 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.matno_process` | global_data | `Global.f90:998` | 30 | `matno_process[1:ngroup,iblk]:int` | list_directed | loop iblk=1..nblks (1) | startup | material assignment per block | `sections[].material` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#16` | global_data | `Global.f90:1012` | 31 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.force_process` | global_data | `Global.f90:1015` | 32 | `force_process[1:ngroup]:int` | list_directed | always | startup | global_data | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#17` | global_data | `Global.f90:1021` | 33 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.average_appear` | global_data | `Global.f90:1023` | 34 | `average_appear[1:ngroup]:int` | list_directed | always | startup | Output nodal stress averaging | `steps[0].output.stress_averaging` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#18` | global_data | `Global.f90:1025` | 35 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.gid_flags` | global_data | `Global.f90:1027` | 36 | `gid_u:int`<br>`gid_s:int`<br>`gid_ms:int`<br>`gid_f:int`<br>`gid_rot:int`<br>`gid_v:int`<br>`gid_a:int`<br>`gid_T:int`<br>`gid_P:int`<br>`gid_Pv:int`<br>`gid_ep:int`<br>`gid_Y:int`<br>`gid_FC:int`<br>`gid_Ns:int`<br>`gid_Ss:int`<br>`gid_Mxy:int`<br>`gid_bem:int`<br>`gid_wh:int`<br>`gid_wv:int`<br>`gid_bcs:int` | list_directed | always | startup | Output OUT_GID_WRITE | `steps[0].output.field` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#19` | global_data | `Global.f90:1030` | 37 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.res_flags` | global_data | `Global.f90:1032` | 38 | `res_u:int`<br>`res_s:int`<br>`res_ms:int`<br>`res_f:int`<br>`res_rot:int`<br>`res_v:int`<br>`res_a:int`<br>`res_T:int`<br>`res_P:int`<br>`res_Pv:int`<br>`res_ep:int`<br>`res_Y:int`<br>`res_FC:int`<br>`res_Ns:int`<br>`res_Ss:int`<br>`res_Tv:int`<br>`res_Pa:int` | list_directed | always | startup | Output binary .res writer | `output_control` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#20` | global_data | `Global.f90:1056` | 39 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.fsi_params` | global_data | `Global.f90:1058` | 40 | `Icaddmass:int`<br>`swlifs2006:real`<br>`toth:real`<br>`ifswater:int`<br>`ifsgravity:real`<br>`absorb:real`<br>`alfa_p4:real`<br>`stiff_p4:real` | list_directed | always | startup | fluid-structure / absorbing boundary | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#21` | global_data | `Global.f90:1060` | 41 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.crack_and_beam` | global_data | `Global.f90:1062` | 42 | `ftcrack:real`<br>`coefMpa:real`<br>`ikindks:int`<br>`doubsig:int`<br>`ktan1:real`<br>`ktan2:real`<br>`nlocalbeam:int`<br>`ndimnrt:int`<br>`listglocbeam[1:nlocalbeam]:int`<br>`lelenrt[1:ndimnrt]:int` | list_directed | always | startup | concrete damage, beam local axes | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#22` | global_data | `Global.f90:1073` | 43 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.transform_and_mif` | global_data | `Global.f90:1075` | 44 | `ntrans:int`<br>`nlaymif:int`<br>`epsMIFb:real`<br>`gamaMIF:real`<br>`ifixvar0_inpb:int`<br>`camif:real`<br>`dxmif:real` | list_directed | always | startup | global_data (.nrt reading when ntrans/=0), MIF boundary | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#23` | global_data | `Global.f90:1077` | 45 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.hdam` | global_data | `Global.f90:1079` | 46 | `hdam[1:nblks]:real` | list_directed | always | startup | water load | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#24` | global_data | `Global.f90:1082` | 47 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.water_level` | global_data | `Global.f90:1084` | 48 | `water_level[1:nblks]:real` | list_directed | always | startup | water load / uplift | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#25` | global_data | `Global.f90:1087` | 49 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.modf_dis_blocks` | global_data | `Global.f90:1089` | 50 | `modf_dis_blocks[1:nblks]:int` | list_directed | always | startup | displacement reset between blocks | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#26` | global_data | `Global.f90:1091` | 51 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.uinitial` | global_data | `Global.f90:1093` | 52 | `uinitial[1:nblks]:int` | list_directed | always | startup | initial displacement | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#27` | global_data | `Global.f90:1099` | 53 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#28` | global_data | `Global.f90:1140` | 54 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#29` | global_data | `Global.f90:1155` | 55 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#30` | global_data | `Global.f90:1192` | 56 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#31` | global_data | `Global.f90:1195` | 57 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#32` | global_data | `Global.f90:1197` | 58 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#33` | global_data | `Global.f90:1199` | 59 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#34` | global_data | `Global.f90:1201` | 60 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.group_header` | global_data | `Global.f90:1216` | 61 | `name:str:sections[].element`<br>`kname:str:sections[].name`<br>`index:int:sections[].element_kind`<br>`class:str:sections[].class`<br>`nrfields:int:derived`<br>`fieldid:str:sections[].fields`<br>`special:str`<br>`sptype:str:sections[].formulation`<br>`nelgroup:int:derived(elset size)`<br>`matno:int:sections[].material`<br>`type_algo:int`<br>`type_stiff:int`<br>`type_ecoint:int`<br>`ilayer:int`<br>`elcod_local:real`<br>`group_inf:int`<br>`uplift_ic:int`<br>`liquj:int` | list_directed | loop igroup=1..ngroup (1) | startup | global_data, read_element (nelgroup), Stiff, Output | `sections[]` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.group_mass_damping` | global_data | `Global.f90:1242` | 62 | `type_mass[1:nrfields]:int`<br>`alfa:real`<br>`beta:real` | list_directed | loop igroup | startup | dynamic mass/damping | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.group_order_time` | global_data | `Global.f90:1245` | 63 | `order_time[:,1:nrfields]:int` | list_directed | loop igroup | startup | dynamic | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.group_nfdof` | global_data | `Global.f90:1255` | 64 | `nfdof:int` | list_directed | loop igroup x nrfields | startup | DOF allocation per field | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.group_listdof` | global_data | `Global.f90:1263` | 65 | `listdof_f[1:nfdof]:int` | list_directed | loop igroup x nrfields | startup | DOF allocation per field | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#35` | global_data | `Global.f90:1809` | 66 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.tension_joint_count` | global_data | `Global.f90:1812` | 67 | `tsel:int` | list_directed | always | startup | joint elements | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.title#36` | global_data | `Global.f90:1826` | 68 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.contact_joint_count` | global_data | `Global.f90:1829` | 69 | `tsel:int` | list_directed | always | startup | joint elements | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.contact_point_to_point.title#1` | contact_point_to_point | `Global.f90:3466` | 70 | `text:str` | text_skip | always | startup | contact_point_to_point | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.contact_point_to_point.contact_control` | contact_point_to_point | `Global.f90:3469` | 71 | `ngaps:int`<br>`ngapb:int`<br>`contactpe:int`<br>`miter_bt:int`<br>`tor_bt:real`<br>`iblks_bt:int`<br>`nonsbt:int`<br>`xlwsol:int`<br>`method_gapi:int`<br>`miter_state:int`<br>`type_solver_ctt:str`<br>`restart_ctt:int`<br>`damp_ctt:real`<br>`istatec:int` | list_directed | always | startup | contact_point_to_point, STATIC_U (recttunit reads when ngapb/=0) | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.link_concrete_and_steel.title#1` | link_concrete_and_steel | `Global.f90:4678` | 72 | `text:str` | text_skip | always | startup | link_concrete_and_steel | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.link_concrete_and_steel.rc_steel_count` | link_concrete_and_steel | `Global.f90:4681` | 73 | `nrcsteel:int` | list_directed | always | startup | reinforcement | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.link_concrete_and_water_pipe.title#1` | link_concrete_and_water_pipe | `Global.f90:4542` | 74 | `text:str` | text_skip | always | startup | link_concrete_and_water_pipe | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.link_concrete_and_water_pipe.water_pipe_count` | link_concrete_and_water_pipe | `Global.f90:4545` | 75 | `nwcpipe:int` | list_directed | always | startup | cooling pipes | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.reached_only_Global_691` | global_data | `Global.f90:722` | — | *reached only*: `if(rmesh/=0)read(gunit,*,iostat=yl_ios,iomsg=yl_msg)valv1,valv2` | — | rmesh/=0 is false (rmesh=0) | — | — | — | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `GLB.global_data.reached_only_Global_772` | global_data | `Global.f90:810` | — | *reached only*: `if(nlayer==2)read(gunit,*,iostat=yl_ios,iomsg=yl_msg) type_nl_layer1,type_nl_lay` | — | nlayer==2 is false (nlayer=0) | — | — | — | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.ifs`（ifsunit，8 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `IFS.stiff_interface_fluid_solid.title#1` | stiff_interface_fluid_solid | `Stiff.f90:10216` | 1 | `text:str` | text_skip | always | startup | stiff_interface_fluid_solid | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `IFS.stiff_interface_fluid_solid.ifs_group_count` | stiff_interface_fluid_solid | `Stiff.f90:10218` | 2 | `nifsgroup:int` | list_directed | always | startup | stiff_interface_fluid_solid | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `IFS.stiff_absorb_fluid.title#1` | stiff_absorb_fluid | `Stiff.f90:10320` | 3 | `text:str` | text_skip | always | startup | stiff_absorb_fluid | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `IFS.stiff_absorb_fluid.absorb_fluid_count` | stiff_absorb_fluid | `Stiff.f90:10322` | 4 | `nabsfgroup:int` | list_directed | always | startup | stiff_absorb_fluid | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `IFS.stiff_absorb_solid.title#1` | stiff_absorb_solid | `Stiff.f90:10419` | 5 | `text:str` | text_skip | always | startup | stiff_absorb_solid | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `IFS.stiff_absorb_solid.absorb_solid_count` | stiff_absorb_solid | `Stiff.f90:10421` | 6 | `nabssgroup:int`<br>`exx:real`<br>`uxx:real`<br>`densxx:real` | list_directed | always | startup | stiff_absorb_solid | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `IFS.stiff_ifs2006.title#1` | stiff_ifs2006 | `Stiff.f90:9581` | 7 | `text:str` | text_skip | always | startup | stiff_ifs2006 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `IFS.stiff_ifs2006.ifs_edge_count` | stiff_ifs2006 | `Stiff.f90:9583` | 8 | `ifsnedge:int` | list_directed | always | startup | stiff_ifs2006 | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.loa`（loadunit，20 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `LOA.external_load_1.title#1` | external_load_1 | `Load.f90:143` | 1 | `text:str` | text_skip | always | startup | external_load_1 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_1.curve_count` | external_load_1 | `Load.f90:145` | 2 | `ntcurve:int` | list_directed | always | startup | external_load_1 | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_1.curve_header` | external_load_1 | `Load.f90:156` | 3 | `ntime:int:derived`<br>`type_curve:str:amplitudes[].type`<br>`nstoch_curve:int`<br>`nline:int` | list_directed | loop itcurve=1..ntcurve (1) | startup | external_load_1, dfact_time_curve | `amplitudes[]` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_1.curve_points` | external_load_1 | `Load.f90:220` | 4 | `ttime_curve[1:ntime]:real:amplitudes[].points` | list_directed | type_curve=='LINEAR' (branch selected by type) | startup | dfact_time_curve | `amplitudes[]` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_1.curve_factors` | external_load_1 | `Load.f90:231` | 5 | `dfact_curve[1:ntime]:real:amplitudes[].factors` | list_directed | type_curve/='SEISMIC' .and. type_curve/='ARCLENGTH' .and. type_curve/='EXTRAPOLATION' .and. type_curve/='HARMONIC' .and. type_curve/='WATERLEVEL' | startup | dfact_time_curve | `amplitudes[]` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_1.title#2` | external_load_1 | `Load.f90:240` | 6 | `text:str` | text_skip | always | startup | external_load_1 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_1.point_load_count` | external_load_1 | `Load.f90:242` | 7 | `nplgroup:int`<br>`kpload:int` | list_directed | always | startup | external_load_1 | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_1.title#3` | external_load_1 | `Load.f90:364` | 8 | `text:str` | text_skip | always | startup | external_load_1 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_1.edge_count` | external_load_1 | `Load.f90:366` | 9 | `nedge:int` | list_directed | always | startup | external_load_1 edge definitions | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.title#1` | external_load_2 | `Load.f90:750` | 9 | `text:str` | text_skip | always | startup | external_load_2 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.title#2` | external_load_2 | `Load.f90:752` | 10 | `text:str` | text_skip | always | startup | external_load_2 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.edge_load_groups` | external_load_2 | `Load.f90:755` | 11 | `edge_load_group:int`<br>`delgroup:int` | list_directed | always | startup | external_load_2, STATIC_U (delgroup gates coef_water reads) | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.title#3` | external_load_2 | `Load.f90:911` | 12 | `text:str` | text_skip | always | startup | external_load_2 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.gravity` | external_load_2 | `Load.f90:913` | 13 | `gravy:real:steps[0].load(gravity).magnitude`<br>`factg[1:ndimn]:real:steps[0].load(gravity).direction`<br>`factf[1:ndimn]:real` | list_directed | always | startup | gravity / gravity1 / gravity2 body force assembly | `steps[0].load` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.gravity_curve_title` | external_load_2 | `Load.f90:920` | 14 | `text:str`<br>`nline:int` | list_directed | always | startup | external_load_2 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.gravity_curves` | external_load_2 | `Load.f90:922` | 15 | `tcurvegravity[1:ngroup]:int:steps[0].load(gravity).amplitude` | list_directed | always | startup | gravity subroutines (0 = no gravity in group) | `steps[0].load` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.title#4` | external_load_2 | `Load.f90:932` | 16 | `text:str` | text_skip | always | startup | external_load_2 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.beam_load_count` | external_load_2 | `Load.f90:934` | 17 | `nbeamload:int` | list_directed | always | startup | beam loads | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.title#5` | external_load_2 | `Load.f90:1013` | 18 | `text:str` | text_skip | always | startup | external_load_2 | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `LOA.external_load_2.plate_load_count` | external_load_2 | `Load.f90:1015` | 19 | `nplateload:int` | list_directed | always | startup | plate loads | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.man`（mainunit，4 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `MAN.STATIC_U.title#1` | STATIC_U | `Fem.f90:3593` | 1 | `text:str` | text_skip | type_problem=='Q' (STATIC_U) | phase_lazy(1) | STATIC_U | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAN.STATIC_U.nincs` | STATIC_U | `Fem.f90:3595` | 2 | `nincs:int` | list_directed | STATIC_U | phase_lazy(1) | STATIC_U increment loop | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAN.STATIC_U.increment_control` | STATIC_U | `Fem.f90:3627` | 3 | `miter:int:steps[0].controls.max_iterations`<br>`ditime:real:steps[0].controls.time_increment`<br>`noutn:int:steps[0].output.frequency`<br>`noutf:int:steps[0].output.frequency`<br>`nstep:int:steps[0].controls.steps`<br>`inc_step:int:steps[0].controls.step_increment`<br>`nresta:int:steps[0].controls.restart_frequency`<br>`cwater:int`<br>`Qstatic:int` | list_directed | loop iincs=lincs+1..nincs (1) | increment_lazy(1,1) | STATIC_U step loop, RESTA_READ_WRITE (nresta) | `steps[0].controls` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAN.STATIC_U.tolerances` | STATIC_U | `Fem.f90:3633` | 4 | `toler_force:real:steps[0].controls.tolerance_force`<br>`toler_var[1:mdofn]:real:steps[0].controls.tolerance_dof` | list_directed | loop iincs | increment_lazy(1,1) | convergence checks in STATIC_U | `steps[0].controls` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.mat`（munit，12 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `MAT.material_set.title#1` | material_set | `Material.f90:243` | 1 | `text:str` | text_skip | always | startup | material_set | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.curve_count` | material_set | `Material.f90:245` | 2 | `nscurve:int` | list_directed | always | startup | material_set | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.comment_line_count` | material_set | `Material.f90:261` | 3 | `nline:int` | list_directed | always | startup | material_set | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.comment_line#1` | material_set | `Material.f90:264` | 4 | `text:str` | text_skip | loop 1..nline (10) | startup | material_set | `title_skip` | static_2d.cooks_membrane:10, static_2d.lame_cylinder:10 |
| `MAT.material_set.title#2` | material_set | `Material.f90:270` | 5 | `text:str` | text_skip | always | startup | material_set | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.nmats` | material_set | `Material.f90:272` | 6 | `mmats:int` | list_directed | always | startup | material_set | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.title#3` | material_set | `Material.f90:281` | 7 | `text:str` | text_skip | always | startup | material_set | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.material_header` | material_set | `Material.f90:283` | 8 | `property:str:materials[].kind`<br>`name:str:materials[].name`<br>`imat:int:materials[].id` | list_directed | loop imat=1..mmats (1) | startup | material_set | `materials[]` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.material_nphase` | material_set | `Material.f90:298` | 9 | `nphase:int` | list_directed | loop imat | startup | material_set | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.material_phase` | material_set | `Material.f90:302` | 10 | `phase:str` | list_directed | loop imat x nphase | startup | material_set | `materials[].phase` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.elastic_isotropic` | material_set | `Material.f90:310` | 11 | `material:str:materials[].model`<br>`density:real:materials[].density`<br>`ratio:real`<br>`thickness:real:sections[].thickness`<br>`e:real:materials[].E`<br>`nu:real:materials[].nu`<br>`alfa:real:materials[].thermal_expansion`<br>`icreep:int`<br>`kind_wt:int`<br>`jliqu:int` | list_directed | material=='ELASTIC_ISOTROPIC' | startup | Stiff element stiffness, gravity body force | `materials[]` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `MAT.material_set.elastic_extra` | material_set | `Material.f90:313` | 12 | `iE:int`<br>`iNu:int`<br>`density_w:real` | list_directed | material=='ELASTIC_ISOTROPIC' | startup | material_set | `unused_switch` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.nrt`（nrtunit，3 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `NRT.global_data.title#1` | global_data | `Global.f90:1492` | 1 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `NRT.global_data.title#2` | global_data | `Global.f90:1494` | 2 | `text:str` | text_skip | always | startup | global_data | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `NRT.global_data.transgroup` | global_data | `Global.f90:1496` | 3 | `transgroup:int` | list_directed | always | startup | global_data interpolation groups | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.opr`（outpread，5 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `OPR.output_read.title#1` | output_read | `Output.f90:4154` | 1 | `text:str` | text_skip | always | startup | output_read | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `OPR.output_read.title#2` | output_read | `Output.f90:4156` | 2 | `text:str` | text_skip | always | startup | output_read | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `OPR.output_read.output_control` | output_read | `Output.f90:4159` | 3 | `irecover:int`<br>`wpgroup:int`<br>`wegroup:int`<br>`wggroup:int`<br>`wjgroup:int` | list_directed | always | startup | Output writers (.opw/.oew/.ogw/.ojw) | `output_control` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `OPR.output_read.title#3` | output_read | `Output.f90:4163` | 4 | `text:str` | text_skip | always | startup | output_read | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `OPR.output_read.title#4` | output_read | `Output.f90:4165` | 5 | `text:str` | text_skip | always | startup | output_read | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.pre`（punit，6 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `PRE.prescrib_set.title#1` | prescrib_set | `Prescrib.f90:211` | 1 | `text:str` | text_skip | always | startup | prescrib_set | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `PRE.prescrib_set.set_count` | prescrib_set | `Prescrib.f90:213` | 2 | `nfixsets:int`<br>`nline:int` | list_directed | always | startup | prescrib_set loop | `derived` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `PRE.prescrib_set.set_header` | prescrib_set | `Prescrib.f90:220` | 4 | `ifixvar:int:steps[0].boundary[].dof`<br>`nfixnods:int:derived(nset size)`<br>`itcurve:int:steps[0].boundary[].amplitude`<br>`tfixvar:real`<br>`outfix:int`<br>`jfixvar:int`<br>`gamawx:real`<br>`nextr:int` | list_directed | type_abc/='MIF' (true) ; loop ifixset=1..nfixsets | startup | prescrib_set, modf_var_prescribed (itcurve -> R18 when 0) | `steps[0].boundary[]` | static_2d.cooks_membrane:2, static_2d.lame_cylinder:2 |
| `PRE.prescrib_set.set_nodes` | prescrib_set | `Prescrib.f90:235` | 5 | `list_fix[1:nfixnods]:int:mesh.sets(nset)` | list_directed | loop ifixset | startup | prescrib_set -> iffix | `mesh.sets` | static_2d.cooks_membrane:2, static_2d.lame_cylinder:2 |
| `PRE.prescrib_set.set_values` | prescrib_set | `Prescrib.f90:242` | 6 | `val_fix[1:nfixnods]:real:steps[0].boundary[].value` | list_directed | loop ifixset | startup | prescrib_set -> fixed() | `steps[0].boundary[]` | static_2d.cooks_membrane:2, static_2d.lame_cylinder:2 |
| `PRE.prescrib_set.reached_only_Prescrib_213` | prescrib_set | `Prescrib.f90:218` | — | *reached only*: `if (type_abc=='MIF')read(punit,*,iostat=yl_ios,iomsg=yl_msg)ifixvar,ifixvar0,nfi` | — | type_abc=='MIF' is false (type_abc='FIX') | — | — | — | static_2d.cooks_membrane:2, static_2d.lame_cylinder:2 |

### `.sol`（solveunit，2 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `SOL.PROFILE.title#1` | PROFILE | `Solver.f90:6829` | 1 | `text:str` | text_skip | type_solver=='PROFILE' | solver_lazy | PROFILE | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `SOL.PROFILE.profile_control` | PROFILE | `Solver.f90:6831` | 2 | `iafile:int`<br>`icond:int`<br>`ipdchk:int`<br>`ising:int` | list_directed | PROFILE first call | solver_lazy | PROFILE (iafile selects scratch-file storage; ising singularity check) | `solver` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

### `.tem`（tunit，9 条）

| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |
|---|---|---|---|---|---|---|---|---|---|---|
| `TEM.boundt.title#1` | boundt | `Temper.f90:124` | 1 | `text:str` | text_skip | always | startup | boundt | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `TEM.boundt.temp_surface_count` | boundt | `Temper.f90:126` | 2 | `ntemp_surface:int` | list_directed | always | startup | boundt | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `TEM.boundt.title#2` | boundt | `Temper.f90:152` | 3 | `text:str` | text_skip | always | startup | boundt | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `TEM.boundt.temp_edge_count` | boundt | `Temper.f90:154` | 4 | `ntedge:int` | list_directed | always | startup | boundt | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `TEM.boundt.title#3` | boundt | `Temper.f90:244` | 5 | `text:str` | text_skip | always | startup | boundt | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `TEM.boundt.temp_elgroup_count` | boundt | `Temper.f90:246` | 6 | `ntelgroup:int` | list_directed | always | startup | boundt | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `TEM.boundt.title#4` | boundt | `Temper.f90:305` | 7 | `text:str` | text_skip | always | startup | boundt | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `TEM.boundt.title#5` | boundt | `Temper.f90:307` | 8 | `text:str` | text_skip | always | startup | boundt | `title_skip` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |
| `TEM.boundt.pipe_count` | boundt | `Temper.f90:310` | 9 | `npipe:int`<br>`algo_pipe:int` | list_directed | always | startup | boundt cooling pipes | `empty_section` | static_2d.cooks_membrane:1, static_2d.lame_cylinder:1 |

## 游标操作（cursor_op）

| ID | 语句 | 单元 | 例程 | 锚点 | 文件 | 说明 |
|---|---|---|---|---|---|---|
| `INP.FEM90.open_Fem_92` | open | inpunit | FEM90 | `Fem.f90:95` | inp |  |
| `GLB.global_data.open_Global_628` | open | gunit | global_data | `Global.f90:631` | .glb |  |
| `COR.global_data.open_Global_629` | open | cunit | global_data | `Global.f90:633` | .cor |  |
| `ELE.global_data.open_Global_630` | open | eunit | global_data | `Global.f90:635` | .ele |  |
| `PRE.global_data.open_Global_631` | open | punit | global_data | `Global.f90:637` | .pre |  |
| `MAT.global_data.open_Global_632` | open | munit | global_data | `Global.f90:639` | .mat |  |
| `LOA.global_data.open_Global_633` | open | loadunit | global_data | `Global.f90:641` | .loa |  |
| `CHKUNIT.global_data.open_Global_634` | open | chkunit | global_data | `Global.f90:643` | .chk |  |
| `SOL.global_data.open_Global_635` | open | solveunit | global_data | `Global.f90:644` | .sol |  |
| `MAN.global_data.open_Global_636` | open | mainunit | global_data | `Global.f90:646` | .man |  |
| `OPR.global_data.open_Global_637` | open | outpread | global_data | `Global.f90:648` | .opr |  |
| `OUTPWRITE.global_data.open_Global_638` | open | outpwrite | global_data | `Global.f90:650` | .opw |  |
| `OUTEWRITE.global_data.open_Global_639` | open | outewrite | global_data | `Global.f90:651` | .oew |  |
| `OUTGWRITE.global_data.open_Global_640` | open | outgwrite | global_data | `Global.f90:652` | .ogw |  |
| `OUTJWRITE.global_data.open_Global_641` | open | outjwrite | global_data | `Global.f90:653` | .ojw |  |
| `OUTDIS.global_data.open_Global_642` | open | outdis | global_data | `Global.f90:654` | .dis |  |
| `OUTACT.global_data.open_Global_643` | open | outact | global_data | `Global.f90:655` | .act |  |
| `OUTGPVAR.global_data.open_Global_644` | open | outgpvar | global_data | `Global.f90:656` | .gpv |  |
| `INITUNIT.global_data.open_Global_645` | open | initunit | global_data | `Global.f90:657` | .ini |  |
| `INITWUNIT.global_data.open_Global_646` | open | initwunit | global_data | `Global.f90:658` | .inw |  |
| `TEM.global_data.open_Global_649` | open | tunit | global_data | `Global.f90:661` | .tem |  |
| `FTFUNIT.global_data.open_Global_650` | open | ftfunit | global_data | `Global.f90:663` | .ftf |  |
| `FTR.global_data.open_Global_651` | open | ftfread | global_data | `Global.f90:664` | .ftr |  |
| `IFS.global_data.open_Global_652` | open | ifsunit | global_data | `Global.f90:666` | .ifs |  |
| `MWAQU_UNIT.global_data.open_Global_653` | open | mwaqu_unit | global_data | `Global.f90:668` | .aqu |  |
| `NRT.global_data.open_Global_654` | open | nrtunit | global_data | `Global.f90:669` | .nrt |  |
| `OUTBAR.global_data.open_Global_655` | open | outbar | global_data | `Global.f90:671` | .bar |  |
| `OUTBEAM.global_data.open_Global_656` | open | outbeam | global_data | `Global.f90:672` | .bem |  |
| `OUTCONTACT.global_data.open_Global_657` | open | outcontact | global_data | `Global.f90:673` | .ctr |  |
| `OUTGOODMAN.global_data.open_Global_658` | open | outgoodman | global_data | `Global.f90:674` | .gdm |  |
| `STOCUNIT.global_data.open_Global_659` | open | stocunit | global_data | `Global.f90:675` | .sto |  |
| `RESTAUNIT.global_data.open_Global_661` | open | restaunit | global_data | `Global.f90:677` | .rtt |  |
| `MIDSTIF.global_data.open_Global_662` | open | midstif | global_data | `Global.f90:678` | .stf |  |
| `RESUNIT.global_data.open_Global_664` | open | resunit | global_data | `Global.f90:680` | .res |  |
| `RESBUNIT.global_data.open_Global_665` | open | resbunit | global_data | `Global.f90:681` | .resb |  |
| `FAIUNIT.global_data.open_Global_671` | open | faiunit | global_data | `Global.f90:687` | .fai |  |
| `RECTTUNIT.global_data.open_Global_673` | open | recttunit | global_data | `Global.f90:689` | .ctt |  |
| `OUT_GID_MSH.global_data.open_Global_701` | open | out_gid_msh | global_data | `Global.f90:734` | .flavia.msh |  |
| `OUT_GID_DIS.global_data.open_Global_703` | open | out_gid_dis | global_data | `Global.f90:736` | .flavia.res |  |
| `OUT_GID_DIS.global_data.open_Global_704` | open | out_gid_dis | global_data | `Global.f90:737` | .flavia.res |  |
| `OUTINDUNIT.global_data.open_Global_733` | open | outindunit | global_data | `Global.f90:768` | .oid |  |
| `OUTINPUNIT.global_data.open_Global_735` | open | outinpunit | global_data | `Global.f90:770` | .oip |  |
| `TELOAW.global_data.open_Global_739` | open | teloaw | global_data | `Global.f90:774` | .tlw |  |
| `STNUNIT.global_data.open_Global_743` | open | stnunit | global_data | `Global.f90:778` | .stn |  |
| `SUB_MSH_UNIT.global_data.open_Global_792` | open | sub_msh_unit | global_data | `Global.f90:836` | .sub.msh |  |
| `MAN.FEM90.rewind_Fem_317` | rewind | mainunit | FEM90 | `Fem.f90:326` | .man | rewind after the restart pre-scan loop, which runs 0 times when restart=0; pure cursor reset before STATIC_U reads .man from the top |
| `LOA.external_load_1.rewind_Load_138` | rewind | loadunit | external_load_1 | `Load.f90:140` | .loa |  |
| `LOA.external_load_1.rewind_Load_139` | rewind | loadunit | external_load_1 | `Load.f90:141` | .loa |  |
| `PRE.prescrib_set.rewind_Prescrib_177` | rewind | punit | prescrib_set | `Prescrib.f90:180` | .pre |  |
| `PRE.prescrib_set.rewind_Prescrib_178` | rewind | punit | prescrib_set | `Prescrib.f90:181` | .pre |  |
| `TEM.boundt.rewind_Temper_68` | rewind | tunit | boundt | `Temper.f90:70` | .tem |  |
| `TEM.boundt.rewind_Temper_69` | rewind | tunit | boundt | `Temper.f90:71` | .tem |  |
| `SOL.PROFILE.rewind_Solver_6825` | rewind | solveunit | PROFILE | `Solver.f90:6827` | .sol |  |
| `SOL.PROFILE.rewind_Solver_6826` | rewind | solveunit | PROFILE | `Solver.f90:6828` | .sol |  |
| `IAFILE.PROFILE.open_Solver_6829` | open | iafile | PROFILE | `Solver.f90:6833` | (iafile) |  |
| `MAN.STATIC_U.rewind_Fem_3577` | rewind | mainunit | STATIC_U | `Fem.f90:3588` | .man |  |
| `MAN.STATIC_U.rewind_Fem_3578` | rewind | mainunit | STATIC_U | `Fem.f90:3589` | .man |  |
| `UPLIFTUNIT.STATIC_U.rewind_Fem_3579` | rewind | upliftunit | STATIC_U | `Fem.f90:3590` | .upf |  |
| `RESTAUNIT.RESTA_READ_WRITE.rewind_Fem_16353` | rewind | restaunit | RESTA_READ_WRITE | `Fem.f90:16382` | .rtt | rewind of the unformatted restart file before RESTA_READ_WRITE rewrites it at the end of the increment (write path) |

## 未在本路径执行的读取候选（not_on_path）

| 单元 | 候选数 | 例程 | guard / 原因 | 归属阶段 |
|---|---|---|---|---|
| mainunit | 156 | FEM90, GHM2ADINA, STATIC_U, STATIC_U_P, STATIC_U_PW, STATIC_U_PWm, STATIC_U_reli, STATIC_rigid_1, STATIC_rigid_reli, back_analysis, back_d_analysis, explicit, frequency_analysis, parameter_back_analysis_verify, parameter_back_analysis_verify_read, response_spectrum, time_dependent | .man records for back_analysis, dynamic (F), thermal (T), seepage, VIE/MIF excitation, cwater/Qstatic sections | M6.7/M7/M8 |
| munit | 104 | material_set | .mat records for property curves and non-elastic material models | M6.4/M6.5 |
| gunit | 52 | contact_point_to_point, estif_semi_space, estif_semi_space_center, global_data, link_concrete_and_steel, link_concrete_and_water_pipe | .glb records for layers, links, backf, level-set, contact pairs, steel, pipes; all counts are 0 on this path | M6~M9 per feature |
| back_ctl_unit | 47 | global_data, matrix_nodal_value, matrix_rigid_dis, output_read, parameter_back_analysis_read, parameter_back_analysis_verify_read, trust_region_back_analysis_read | back_analysis parameter file (.btl); opened only when nbackf/=0 | M9 反分析 |
| nrtunit | 40 | global_data | interpolation group data beyond transgroup=0 | M6.2 |
| glbunitl | 37 | fixpc, globaldate, readbondary, readinitial, readprescrib, static_pressure | level-set mesh files (_l.glb); level_set_problem/=0 | M9 网格细化/水平集 |
| loadunit | 32 | external_load_1, external_load_2 | .loa records for point loads, edges, edge loads, beam/plate loads; counts are 0. Load.f90:231 (amplitude dfact factors, gated on type_curve, not on any zero count) was misclassified into this group and has been pulled out into its own reader, LOA.external_load_1.curve_factors -- see M1-finding-2026-09-08. | M5.pressure/M6 |
| solveunit | 29 | JPCG, MAIN_PARDISO, PBCG, PROFILE, PROFILEW, SSORPBCG | .sol records for PARDISO / other solver branches and iafile/=0 | M5 PARDISO variant |
| unitread | 29 | read_initial | generic reread of restart/intermediate files; restart/=0 or meshc/=0 | M6.7 重启 |
| restaunit | 28 | RESTA_READ_WRITE | restart file .rtt is only read when restart/=0; on this path it is written | M6.7 重启 |
| tunit | 26 | boundt | temperature boundary data beyond the zero counts read on this path | M8 |
| punit | 20 | GHM2ADINA, prescrib_set, time_dependent | .pre records for MIF/VIE boundaries and interpolation slaves; type_abc/='FIX' or ntrans/=0 | M7.5/M7.7 |
| stocunit | 18 | STATIC_U_reli, STATIC_rigid_reli | stochastic/reliability data (.sto); sysrelis/relis/=0 | M9 可靠度 |
| recttunit | 16 | STATIC_U, STATIC_U_PW, STATIC_U_reli, STATIC_rigid_1, STATIC_rigid_reli, back_analysis, back_d_analysis, time_dependent | contact matrix scratch (.ctt) read only when ngapb/=0 | M6.6 接触 |
| ftfread | 13 | global_data | surface force lists beyond the zero counts | M6.2 |
| outpread | 13 | output_read | .opr observation-point lists; irecover/w*group are 0 | M5 output |
| ifsunit | 13 | stiff_absorb_fluid, stiff_absorb_solid, stiff_ifs2006, stiff_interface_fluid_solid | fluid-solid / absorbing boundary definitions beyond the zero counts read on this path | M7.5/M7.6 |
| resbunit | 12 | global_data, value_submodel_boundary | binary result reread for restart/relis | M6.7 |
| observ_unit | 11 | OUT_record_WRITE, global_data, observe_back_analysis_read, parameter_back_analysis_verify_read | observation data (.obsc) for back analysis; nbackf/=0 | M9 反分析 |
| vcor_unit | 10 | FEM90, global_data | moving-coordinate file (.vcor); nvarp_U/=0 | M6.2 |
| mwaqu_unit | 10 | stiff_ifs2006 | aquifer/seepage data (.aqu); nflow/=0 | M8.3 渗流 |
| observc_unit | 9 | global_data | observation data for back analysis; nbackf/=0 | M9 反分析 |
| bouunitl | 7 | boundary, globaldate | level-set boundary file; level_set_problem/=0 | M9 |
| 1 | 6 | readm, readmi | hard-coded unit 1 (level-set / mesh refinement helpers) | M9 |
| gamamaxunit | 6 | process_analysis, readgamamax, writegamamax | gamamax storage; gamamax/=0 | M9 |
| outindunit | 5 | global_data, modf_var_prescribed, prescrib_set | write-only output unit (.oid) opened only when outind/=0 | n/a |
| iafile | 5 | pivots | PROFILE scratch file; iafile/=0 | M5 PARDISO variant |
| outint | 5 | FEM90, modf_var_prescribed | intermediate result file (.oit, FORM=BINARY) opened only when outintr/outintw/=0 | M6.7 重启 |
| midstif | 5 | kdelt, neuman_expan, write_stiff_u | stiffness scratch file reread; kstab/=0 or restart | M6.7 |
| upliftunit | 4 | FEM90, STATIC_U_PW, modf_var_prescribed, time_dependent | uplift pressure file (.upf); upliftin/=0 | M8 |
| lquunit | 4 | liquifaction_judge, time_dependent | liquefaction data; jliqu/=0 | M6.4 |
| stnunit | 4 | read_permanent_strain | permanent-strain file read by read_permanent_strain when ninistn/=0 | M6.7 |
| bem_msh_unit | 3 | OUT_GID_WRITE, OUT_GID_WRITE_BIN, global_data | beam GiD mesh writer; open/rewind only, gid_bem=0 | n/a (output) |
| mxy_msh_unit | 3 | OUT_GID_WRITE, OUT_GID_WRITE_BIN, global_data | plate GiD mesh writer; open/rewind only, gid_Mxy=0 | n/a (output) |
| out_cosm_dis | 2 | global_data | COSMOS displacement writer; outplot/='COSM' | n/a (output) |
| out_cosm_gpvar | 2 | global_data | COSMOS Gauss-point writer; outplot/='COSM' | n/a (output) |
| out_msh | 2 | FEM90, global_data | alternative mesh writer; open/rewind only | n/a (output) |
| bcs_msh_unit | 2 | OUT_GID_WRITE, global_data | boundary-condition GiD mesh writer; gid_bcs=0 | n/a (output) |
| out_gid_msh | 2 | OUT_GID_WRITE, OUT_GID_WRITE_BIN | GiD mesh writer rewinds inside OUT_GID_WRITE; the open at Global.f90:701 is executed and registered as a cursor_op | n/a (output) |
| omgunit | 2 | time_dependent | optimisation output | M9 |
| outinpunit | 2 | modf_var_prescribed | prescribed-value echo file (.oip) reread; outinp/=0 | n/a (output) |
| adnunit | 2 | GHM2ADINA | ADINA import (.in); ADINA/=0 | M9 |
| bem_res_unit | 1 | global_data | beam GiD result writer; gid_bem=0 | n/a (output) |
| bcs_res_unit | 1 | global_data | boundary-condition GiD result writer; gid_bcs=0 | n/a (output) |
| mxy_res_unit | 1 | global_data | plate GiD result writer; gid_Mxy=0 | n/a (output) |
| cunit | 1 | contact_point_to_point | coordinate reread for moving mesh (rmesh/=0) | M9 |
| out_gid_dismax | 1 | OUT_GID_MAX | max-displacement writer OUT_GID_MAX; not called on the static path | n/a (output) |
| initwunit | 1 | OUT_NEXT_WRITE | initial water file (.inw) | M8 |
| bounchsl | 1 | globaldate | level-set boundary mesh writer (globaldate); level_set_problem/=0 | M9 |
| gidmshl | 1 | globaldate | level-set GiD mesh writer; level_set_problem/=0 | M9 |
| gidresl | 1 | globaldate | level-set GiD result writer; level_set_problem/=0 | M9 |
| chkunitl | 1 | globaldate | level-set check file; level_set_problem/=0 | M9 |
| disunit | 1 | time_dependent | displacement reread (d.dis) | M9 |
| pmtunit | 1 | time_dependent | parameter file for optimisation; Uopt_R/=0 | M9 |
