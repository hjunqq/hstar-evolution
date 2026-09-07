# 当前进度

更新日期：2026-09-07。此文件只登记已经发生的事；阶段验收以证据包为准。

| 项目 | 状态 | 说明 |
|---|---|---|
| 独立仓库与目录 | 完成 | HSTAR Evolution，已建立 origin/main 跟踪 |
| 历史源码和两个种子算例导入 | 完成 | 不等于认证的生产基线 |
| 总体架构和 M0～M9 路线 | 已编写 | modern 直接初始化；事务提交；显式能力范围 |
| 任务/测试/验收手册 | 已编写 | 待执行，不能计为测试通过 |
| M0 开工前文档修正 | 完成 | ADR-0003（CAE 对象模型 + SI）；02/05/06/08 出口条件按环境实证修正；两例标为回归例 |
| M0-01 来源清单与哈希 | IN_REVIEW | 源码/算例逐文件 SHA-256、gidpost 桩入库、脏树 15 组 hunk 分类（3 项待 M0-04c 验证） |
| M0-02 Linux 构建 | IN_REVIEW | `env -i` 下 release/debug 可构建，依赖固定并入 manifest；release 冒烟两例与历史输出逐字节相同；检查型 profile 暴露 R17/R18 |
| M0-05a 模型说明与容差登记 | IN_REVIEW | 两例 MODEL.md / observables.toml / tolerances.toml；两例均为重力回归例 |
| M0-03 隔离运行器 | IN_REVIEW | 七种状态各有反例；两例 COMPLETED |
| M0-04 参考结果 | IN_REVIEW | 两例各 3 次逐值相等（B02）；候选脏树二进制两例与 reference 相同（04c）；reference 已冻结到 `cases/golden/*/reference/` |
| M0-05b M0 报告 | IN_REVIEW | `docs/m0/M0-report.md`；无第二复核人，阶段停在 IN_REVIEW |
| M1-01 reader 清单 | IN_REVIEW | 静态全集 1022 处；两例 gdb 实证命中 211 位点（read 152）；`docs/m1/reader-inventory.toml` 经 `check` 通过 |
| M1-02 checked I/O | IN_REVIEW | `src/diagnostics/yl_diag*`；152 个 reader 与 14 个 open 已包装；两例结果逐字节不变；探针 29/29；`--check-legacy` 可用；新盲区 R19/R21 |
| M1-03 语义守卫 | DONE | 数量/引用/分配守卫（RANGE/REF/DUPLICATE/UNSUPPORTED，`--max-entities`）；R17/R18 关闭；路径上 38 处裸 `stop`（39 条替换，`Temper.f90:455` 一处两条）纳入退出协议；release/debug/strict × 两例精确相同；探针 47/47；注册表 `check` PASS；新契约 R22 |
| M2-01 状态字段映射表 | IN_REVIEW | `docs/m2/state-field-map.toml` 269 字段 / 4 检查点（restart_ready 未覆盖）；`yl_state_map.py check` PASS，39/39 非 skip reader 被引用；锚点 `Fem.f90:1908/3601/3654`；S03 目标钉在 E / 约束值 / 重力；新风险 R23、R24 |
| M2-02 状态序列化与比较器 | DONE | 三检查点导出 190 字段（生成式 dump + 25 adapter）；`yl_state.py normalize` 出 §5 九文件与指纹；`yl_state_diff.py` 结构优先定位到对象/字段；dump 开关 × 三 profile × 两例结果逐值不变、`1.flavia.res` 逐字节相同；S01 三次指纹相同；S02 九类反例 + 四类护栏命中；探针 47/47；新风险 R25、R26 |
| M2-03 两例状态证据 | DONE | S01 两例各 3 次指纹相同、3 对两两 PASS；S03 四条扰动探针 4/4 命中（材料 E、约束值、重力，R24 编码为测试）；状态基线冻结到 `reference/state/`（40 文件/例，附 `frozen.json` provenance）；`yl_state_probe.py --selftest` 47/47 |
| M3-01 ProblemState 类型 | DONE | `src/problem/` 最小类型（24 个类型 / 100 字段，98 项对应 M2 映射表，2 项 M5-only）；`opt_*` 包装区分 unset/zero/empty；独立 `problem-types` 构建目标不入求解器链接链（build-id 不变）；`yl_problem_check.py` 双向核对 + 槽位名黑名单；映射表 6 项缺陷修正 + `legacy_only`(47) |
| M1～M5 实现及验收 | TODO | 尚无 checked I/O、状态比较器、现代初始化或可运行 TOML |
| M6～M9 | BACKLOG | 按真实需求逐能力启动 |

当前没有 production 现代输入能力。构建、求解回归与物理验收尚未在本工程重新执行。
本轮核实了环境（ifx 2025.3、MKL 2026.1、无 gfortran）、原仓库脏树差异、两例 deck 内容与输出路径，
并据此修正文档；没有更改求解器或算例输入。

下一步：M3-01 已复核，进入 M3-02（normalize/validate/finalize）。
