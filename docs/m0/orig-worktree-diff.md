# 原仓库未提交修改逐 hunk 分类（M0-01）

- 原仓库：`/home/huijun/HSTAR_Next/hstarYLOrig`，HEAD 与导入快照相同（`5414e73`）。
- 工作树相对快照：`HSTAR/` 下 6 个文件，+389 / −66 行（`git diff --stat`）。
- 《修改报告.md》描述的是接触罚函数、PARDISO 装配等改动，与本工作树实际 diff **不符**；
  本表以实际 diff 为准（风险 R13）。
- 静力切片可达性按两个种子算例判定：`TYPE_PROBLEM=Q`、`ntrans=0`、`MDOFN=2` 全自由度、
  `NGRAV=1`、`TYPE_SOLVER=PROFILE`、材料 ELASTIC_ISOTROPIC。

分类：`EXCLUDE` 不导入；`DEFER` 不在静力切片路径，留待对应阶段；`VERIFY` 可能影响
静力切片，M0-04c 用脏树 candidate 二进制对照后决定；`ADOPT` 已确认必需（本表暂无）。

| 文件 | 位置 | 内容 | 触发条件 | 两例可达 | 分类 |
|---|---|---|---|---|---|
| Fem.f90 | 2820, 3421, 4154, 5310, 6171, 6399, 8141, 8451, 9220 | 9 处 `if(type_problem=='F') call energy_audit` | 动力分析 | 否 | DEFER（M7） |
| Fem.f90 | 10183–10197 | `block` 求 `sum_M_elem_diag`、`sum_K_diag` 写 unit 7（fort.7），调试用 | 所在分支需核对 | 待核 | VERIFY（若可达则为纯输出，仍不得导入） |
| Fem.f90 | 10732–10889 | 新增 `SUBROUTINE ENERGY_AUDIT`，只写 `.chk`，声明不改求解状态 | 仅被上述 F 分支调用 | 否 | DEFER（M7） |
| Fem.f90 | 10992–11023 | tfix2026：TRAL/trans 插值从属自由度预测后同步主自由度 | `trans(itotv)%nintf/=0`，即 `ntrans>0` | 否（ntrans=0） | DEFER（M6.2 局部坐标/插值） |
| Fem.f90 | 13355, 13770–13782, 13991–14000 | audit2026：VIE 吸收边界 `tofor` 前后差 → `vie_base_force` | 动力 + 吸收边界 | 否 | DEFER（M7.5） |
| Fem.f90 | 14165–14181 | audit2026 P0-2：`type_problem=='F'` 时统计 `base_ext_force` | 动力 | 否 | DEFER（M7） |
| Global.f90 | 全文 | 编码 ISO-8859 → UTF-8、LF → CRLF、删除中文注释；`git diff -w` 后仅新增 `vie_base_force(3)`、`base_ext_force(3)` 两个声明 | 与 audit 代码配套 | 否 | DEFER；编码转换单独任务（R05） |
| Output.f90 | 226 | 跳过无 `valun` 的热分析组 | 单场热分析 | 否 | DEFER（M8） |
| Output.f90 | 3882–3920 | tfix2026：`lcdofn(jdofn)` 改为 `lmdofn(jdofn)`，并加 `idofn>=1` 越界保护 | 输出分支；注释称“全自由度 deck 两者相同” | 是（输出路径） | VERIFY（预期结果不变，须 04c 证实） |
| Output.f90 | 3956–4030 | 无 `gpvar`/`gapg`/`ntstress` 的单元写 0 | 热/非接触单元 | 部分（非接触） | VERIFY（预期对 Q4 实体无影响） |
| Output.f90 | 4417, 4604, 4953, 5031, 5111, 5281 | 热材料无 mechanical 段时 `material=' '` | `props(matno)%mechanical` 未关联 | 否 | DEFER（M8） |
| Stiff.f90 | 2422 | `factw=0.0_irk`，密度循环前初始化 | 组装体力/质量时 | **是**（NGRAV=1） | **VERIFY（重点）**：若快照结果依赖未初始化值，属 INTENTIONAL_FIX，需独立提交与前后对照 |
| Stiff.f90 | 3361–3372 | `use_duncanchang` 拆开求值，避免热材料空指针 SIGSEGV | 热材料组 | 否（弹性材料指针已关联） | DEFER（M8）；语义对弹性材料等价 |
| hstar.vfproj | 29 | Windows 链接选项 | Windows 构建 | 不适用 | EXCLUDE |
| inp | 全文 | 本地绝对路径的算例列表 | — | 不适用 | EXCLUDE |
| `*.bak_*`、`objs/`、`hstar-yaml/`、`next/` | 未跟踪 | 备份与其他工程 | — | 不适用 | EXCLUDE |

## M0-04c 判定规则

1. 用同一构建脚本分别构建纯快照 `reference` 与脏树 `candidate`；
2. 两例各运行一次，解析 `1.flavia.res` 逐值比较；
3. 逐值相同：所有 VERIFY 项改为 DEFER，记录“不在静力切片路径”；
4. 存在差异：先看 `factw` 项，把该 hunk 单独打到快照上再跑；差异消失则该项为
   `INTENTIONAL_FIX`，保留快照基线并另存修复后基线；其余 hunk 逐个重复此过程；
5. 不允许整体覆盖快照，也不允许因 candidate “能跑”而替换基线。
