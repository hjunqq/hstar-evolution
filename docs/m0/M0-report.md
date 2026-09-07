# M0 报告：可重复基线（候选接受 ID `M0-static2d-001`）

- 阶段/完整能力组合：M0 基线；2D、Q4、平面应变、线弹性各向同性、单阶段单增量静力、重力体力、
  固定位移约束、PROFILE 求解器、位移与节点应力输出；Linux x86-64、ifx 2025.3、MKL 2026.1、单线程
- 候选提交：本报告所在提交；参考源码：`legacy/yl` = `hstarYLOrig@5414e73`
- 比较器版本：`tools/yl_compare.py`（本提交）
- 日期：2026-09-07；实现人：Huijun（Claude 辅助）；复核人：**未指定**；接受负责人：未指定
- 判决：**IN_REVIEW**（所有必需门 PASS 或有依据的 NOT_APPLICABLE；缺独立复核签收）

## 证据包

| 条目 | 位置 |
|---|---|
| source-manifest | `legacy/source-manifest.json`（39 文件，含 `stubs/gidpost_stub.c`） |
| input-manifest | `cases/golden/static_2d/{cooks_membrane,lame_cylinder}/input-manifest.json` |
| build manifest | `cases/golden/static_2d/*/reference/build-manifest.json`（release，二进制 `6df6ea8d…`） |
| run manifest | `cases/golden/static_2d/*/reference/run-manifest-{1,2,3}.json` |
| 参考结果 | `cases/golden/static_2d/*/reference/results.json` + `repeat-report.json` |
| 模型/观察量/容差 | `cases/golden/static_2d/*/{MODEL.md,observables.toml,tolerances.toml}` |
| 脏树对照 | `docs/m0/orig-worktree-diff.md`、`docs/m0/evidence/candidate/` |
| 检查型构建证据 | `docs/m0/evidence/*.stderr.txt` |
| 任务记录 | `docs/tasks/M0-01.md` … `M0-05a.md` |

## 质量门

| 门 | 必需测试 ID | 状态 | 证据 | 备注 |
|---|---|---|---|---|
| Build | B01 | PASS | `env -i` 下 release/debug 构建；manifest 依赖全部解析 | CI NOT_RUN（无 ifx 环境） |
| Repeat | B02 | PASS | 两例各 3 次逐值精确相等 | 单线程 |
| Isolation | B03 | PASS | 七种状态各有反例；golden 前后哈希不变 | |
| Input/Failure | I01–I03 | NOT_APPLICABLE | M1 才适用 | |
| State | S01–S03 | NOT_APPLICABLE | M2 才适用；比较器反例已先行通过 | |
| Numerical | N01 | NOT_APPLICABLE | M4 才适用；04c 用同一比较器通过 | |
| Physics | P01/P02 | NOT_APPLICABLE | 两例为重力回归例（R08 已证实）；M5 新建探针 | |
| Capability/Docs | — | PASS | `cases/manifest.toml` 状态 `reference-frozen`；`docs/build-linux.md` | |

## 观察量与量级

| 算例 | 观察量 | 单位 | 节点 | 最大绝对值 | 三次重复最大差 |
|---|---|---|---|---|---|
| cooks_membrane | DISPLACEMENT | m | 289 | 7.568e-3 | 0 |
| cooks_membrane | STRESS（4 分量） | Pa | 289 | 4.002e6 | 0 |
| lame_cylinder | DISPLACEMENT | m | 81 | 见 results.json | 0 |
| lame_cylinder | STRESS（4 分量） | Pa | 81 | 1.468e5 | 0 |

量级与 MODEL.md 的尺度估计一致（Cook 位移尺度 2.2e-3 m、应力尺度 1.1e6 Pa）。
这不是物理验证；两例只证明“固定环境下旧程序的确定性输出”。

## 差异与风险

- 无 REGRESSION / INTENTIONAL_FIX / EXPECTED_REFORMULATION：candidate 与 reference 逐值相同。
- 新登记风险 R13～R18；其中 R17（`kinddefine` 未初始化 `t/u`）、R18（`tcurves(0)` 越界）
  为快照潜在缺陷，release 下未影响结果，进入 M1-03。
- 已关闭调查：R04（只打开小写 `.loa`，两文件相同）、R08（已证实并改判回归例）、R15（写出已确认）。
- golden 未变：三次参考运行与 candidate 运行的前后哈希检查全部通过。

## 限制（limitations）

- 平台：仅 Linux x86-64 + ifx 2025.3 + MKL 2026.1；未验证其他版本、Windows、gfortran。
- 检查盲区：MSan 不可用；bounds/snan 检查在快照已知缺陷处中止，未完整覆盖两例；MKL 内部无检查。
- 输出：只解析 `1.flavia.res`；无反力；`.gpv/.chk` 未解析。
- 容差：跨路径容差为临时值，须在独立任务定稿。
- 复核：单人项目，无独立复核人；本阶段不得标 ACCEPTED。
- 历史输出对照为非正式证据（来源构建未登记）。

## 签收

- 必需门是否全部通过：是（B01/B02/B03 PASS，其余 NOT_APPLICABLE 有依据）。
- 证据能否从干净检出重现：构建与运行可重现（`tools/build.sh release` + `tools/yl_run.py`）；
  reference 哈希登记于 `repeat-report.json`。
- 接受的精确范围：仅上表能力组合；不包含现代输入、其他单元/材料/分析类型。
- 复核结论/负责人接受记录：**待填写（不得代填）**。
