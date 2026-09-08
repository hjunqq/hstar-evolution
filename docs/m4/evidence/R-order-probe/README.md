# R-order 证伪实验：能否在 `PROGRAM FEM90` 之外驱动 legacy module reader

- 日期：2026-09-08
- 目的：**只有一个**——判定 M4-01 拟采用的"收割预言机"架构是否可行
- 结论：**CONFIRMED**
- 性质：这是规划期的**一次性探针，不是产品代码**。它不进任何构建目标，不进求解器链接链。

## 被证伪的假设

M4-01 计划把"链接真实 legacy 模块、按原顺序调用其 reader、再从全局收割成 `ProblemState`"
作为**预言机**，用来逐字段校验仓库侧新写的解析器。该架构依赖一个未验证前提：

> 脱离 `PROGRAM FEM90` 驱动 legacy 的 module reader，可能依赖 FEM90 才建立的状态。

若该前提成立，预言机方案作废。本实验就是去证伪它。

## 实验设计（最小）

`FEM90` 主体在 `call global_data` 之前只做五件事（`Fem.f90:94-117`）：

1. `call diag_set_mode_from_argv()`
2. `open(inpunit, file='inp', status='old')`
3. 从 `inp` 读四条记录：title、`restart/relis/sysrelis/ADINA/Uopt_R/gamamax`、title、`probn`
4. `call TIME(char_time)`
5. `call global_data`

探针**逐条复刻这五步，别的什么都不做**，然后打印可独立核对的全局量。
随后追加一行 `call material_set`（`Fem.f90:191`，FEM90 的下一个 reader 调用）。

链接面沿用既有的 `runtime-bridge` target 的对象集合（全部 legacy 模块，**排除 `Fem.f90`**）。

## 结果

在 `cases/golden/static_2d/cooks_membrane/legacy/` 的副本上运行，`global_data` 与
`material_set` 均**完整返回、未中止**，产出：

| 全局量 | 探针读到 | 独立核对 |
|---|---|---|
| `npoin` | 289 | `MODEL.md`：289 节点 ✓ |
| `nelem` | 256 | `MODEL.md`：256 单元 ✓ |
| `ndimn` / `ngroup` / `nmats` | 2 / 1 / 1 | 单组 Q4 二维单材料 ✓ |
| `mdofn` / `cdofn` | 2 / 2 | 位移场 X,Y 全启用 ✓ |
| `ntotv` | 578 | = 2 × 289 ✓ |
| `coord(:,2)` | (3.0, 2.75) | `1.cor` 第 2 行：`2  3.0000000000  2.7500000000` ✓ |
| `coord(:,npoin)` | (48.0, 60.0) | Cook 膜右上角 ✓ |
| `element(1)%field(1)%lnods_f` | 1 2 19 18 | `1.ele` 第 1 行：`1  1 2 19 18  1` ✓ |
| `nodfn` | 已分配 (2,289) | 说明 `set_elem_dofs` 也已运行 ✓ |
| `props` | 已分配，size=1 | `material_set` 已运行，与 `nmats=1` 一致 ✓ |

**每一个数值都对着 deck 文件或 MODEL.md 独立核对过**，不是"程序没崩就算过"。

## 结论的确切边界

**CONFIRMED 的范围**：`global_data`（含它内部驱动的 `.cor` / `.ele` 读取与 `set_elem_dofs`
自由度编号）与 `material_set`。按 reader 清单，这覆盖 `.glb` 75 + `.cor` 1 + `.ele` 1 + `.mat` 12
= **89 个白名单站点**。

**未测试**：`external_load_1`（`.loa` 19 站点，`Fem.f90:1682`）、`prescrib_set`（`.pre` 6 站点，
`:1873`）、`PROFILE`（`.sol` 2 站点）。这三个位于 FEM90 流程中段，其间还有约 1500 行代码
（分块、`appear` 激活等）。**它们的可达性是一个独立的、更小的问题**，留到 M4-01 的 L1-a
第一步解决——不在本次最小实验范围内，也不由本实验的 CONFIRMED 覆盖。

**不变**：`Fem.f90` 内的 9 个站点（5 个 `inp` 在 FEM90 主体、4 个 `.man` 在内部子程序
`STATIC_U`）**结构上仍不可达**。Fortran 内部过程无法从宿主程序单元外调用，这与本实验无关。

## 复现

```bash
source tools/env.sh
tools/build.sh runtime-bridge                 # 产出 build/runtime-bridge/release/obj/
OBJ=build/runtime-bridge/release/obj
D=$(mktemp -d) && cp cases/golden/static_2d/cooks_membrane/legacy/* "$D/"
$HSTAR_FC -c -O2 -module "$D" -I $OBJ -I "$HSTAR_MKLROOT/include" \
    docs/m4/evidence/R-order-probe/rorder_probe.f90 -o "$D/probe.o"
$HSTAR_FC -O2 $(ls $OBJ/*.o | grep -v yl_runtime_bridge_test.o) "$D/probe.o" -o "$D/probe" \
    -qopenmp -L"$HSTAR_MKLROOT/lib" -lmkl_intel_lp64 -lmkl_intel_thread -lmkl_core \
    -L"$HSTAR_IOMP_LIBDIR" -liomp5 -lpthread -lm -ldl \
    -Wl,--disable-new-dtags -Wl,-rpath,"$HSTAR_MKLROOT/lib" -Wl,-rpath,"$HSTAR_IOMP_LIBDIR"
cd "$D" && ./probe
```

`probe-output.txt` 是上述命令的实际输出。
