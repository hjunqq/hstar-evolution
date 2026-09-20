# 能力前沿测量（2026-09-20）

不是按最近活动、也不是按源码站点数排的。**按真实 deck、可验收性、依赖关系排。**

方法：对策展库 `HSTAR_Next/cases/cases` 的 88 个算例，每个跑两遍——
① `--adapter=on`（默认，legacy-deck 适配器路径）取**第一条**拒绝；
② `--adapter=off`（legacy 读取器）看它**是否真的能跑出结果**。
凡是算例自带 `inp` 的用它自己的（`runblks` 取自第 5 行）；没有 `inp` 的合成一个最小的，
并在下表里不作为 `runblks` 证据。

## 1. 总体分布

| 适配器路径 | 算例数 |
|---|---|
| **接受并跑通**（rc=0） | **22** |
| 点名拒绝（rc=3，UNSUPPORTED） | 54 |
| 更早的输入/方言错（rc=2） | 11 |
| 无 `.glb` | 3 |

54 个被拒算例中，**33 个在 legacy 路径上 rc=0 且产出结果**——也就是说，
**前沿不是"没有算例"，而是"有算例、被能力表按名挡住"**。

## 2. 前沿：按「真实可跑 deck 数」排序

| 首条拒绝 | deck 数 | 其中 legacy 可跑 | 属哪个未迁移域 |
|---|---|---|---|
| **`derived.counts.runblks`：runblks 必须为 1** | 14 | **10** | 施工/加载过程（多分析块） |
| **`steps[].controls.nonlinear_type`：ALGORT** | 10 | **8** | 动力/模态 + 非线性求解控制 |
| **`derived.counts.mdofn`：单位移场** | 9 | **4** | 多场耦合（渗流/温度/固结） |
| **`mesh.dimension`：只放行 2-D** | 5 | **5** | 3-D |
| `control.glb.bparameter` | 7 | **0** | 反分析（xfj 族），且都跑不起来 |
| `interactions.absorbing.type`：MIF | 2 | 2 | 动力边界（VIE/MIF），输出 100–170 MB |
| `steps[].load`：`nedge/=0` | 2 | 2 | 面荷载（**authoring 已支持**，见 §4） |
| `steps[].load`：`nplgroup/=0` | 1 | 1 | 集中力（**authoring 已支持**，见 §4） |
| `control.glb.stab_matde` | 1 | 1 | 边坡稳定 |
| `materials[].name==CONTACT` | 1 | **0** | 接触（deck 本身缺参数，见 m12） |
| `control.glb.nlocalbeam/ndimnrt` | 1 | 0 | 局部坐标梁 |
| `control.glb.kstab` | 1 | 0 | — |

## 3. 最小差值算例（本项目一贯的切片判据）

按「相对已覆盖算例只差一条能力」筛，两条前沿各有现成的最小 deck：

| deck | 规模 | 与 `cooks_membrane` 的差值 | legacy 结果 |
|---|---|---|---|
| **`mini_3d`** | 27 节点 / 8 单元 | **只有 `ndimn=3`**（Q / PROFILE / 单组 / 单材料 `ELASTIC_ISOTROPIC` / `nscurve=0` / `runblks=1`） | rc=0，5 409 B |
| **`mini_gravdam`** | 46 节点 / 32 单元 | **只有 `runblks=2`**（2-D / Q / PROFILE / Q4 / `ELASTIC_ISOTROPIC` / `nscurve=0`） | rc=0，14 464 B |
| `test_gen` | 46 / 32 | 同上（两种材料） | rc=0，14 464 B |
| `gravdam_static_demo` | 64 / 44 | 同上 | rc=0，20 008 B |
| `train01_gravdam_static` | 1 705 / 1 600 | 同上，大一号 | rc=0，713 106 B |

`mini_rebar`（29 节点）看着也小，但它同时带 **3-D + CAMCLAY + L2 三条**未覆盖能力，
不是最小差值算例。

## 4. 本次测量查出的一件要紧事：两条路径已经分叉

把九个 golden 算例的 **legacy deck** 交给适配器路径，逐个测：

| golden 算例 | `--adapter=on` |
|---|---|
| `cooks_membrane` / `lame_cylinder` / `mini_mc` / `slope_srm` / `new_duncan_chang` / `benchmark_100x100` / `concrete_gravdam` / `rcbeam` | **rc=0** |
| **`loads_2d/wall_reservoir`** | **rc=3** `derived.counts.runblks: runblks must be 1` |
| **`loads_2d/beam_point_load`** | **rc=3** `steps[0].load: nplgroup /= 0` |

**M7 的两项能力（面荷载+多分析步、集中力）只在 authoring 路径上成立；
legacy-deck 适配器路径仍停在 M4-02 的单块静力。** 两者都已按窄口径签收——
签收口径写的是「现代输入独立驱动 + 与冻结参考严格等价」，**没有**声称
legacy-deck 路径也能驱动它们，所以签收本身没有虚报；但
**「两条路径等价」这条 M4-02 立下的红线，事实上已经破了，而且此前没有任何东西会报出来。**

这正是 **R34** 的实际代价：回退门禁只遍历 `state-field-map.toml` 里的两个静力算例
（`cooks_membrane` / `lame_cylinder`），于是从 M6 起每一个新域都只在 authoring 一条路径上
被检验过。R34 因此不只是"门禁口径不准"，它**掩盖了一处真实的架构分叉**。
