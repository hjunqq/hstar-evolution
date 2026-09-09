# M0 验收判据 → 证据映射表

- 候选接受 ID：`M0-static2d-001`（`docs/m0/M0-report.md`）
- 编制日期：2026-09-08；编制人：Claude subagent（只读复核，未重建求解器、未重跑算例）
- 本文件本身不是签收；签字页留空，由负责人填写。

## 一句话结论

**证据链绝大部分可签：18 项判据中 15 项有可独立重现的证据，与 `M0-report.md` 所记数字逐一
核对一致；但有 3 项目前只是断言而非独立证据——七种隔离运行状态的反例只有文字叙述、
跨路径容差是无噪声支撑的量纲估算、以及最关键的复核签收本身从未发生。最后一项是结构性的
（`docs/m0/M0-report.md` 自身写明「复核结论：待填写（不得代填）」）。** 是否现在签收、
是否要求先补齐前两项断言，是负责人的判断，不是这份文件能替代的证据。

## 验收判据 → 证据映射表

判据引自 `docs/07-acceptance-and-release.md` M0 行「来源/哈希、干净构建、隔离运行、
两例重复结果、模型及容差说明」，并入 `docs/02-migration-plan.md` §M0 出口条件逐条展开。

| # | 判据 | 支撑证据（路径 + 具体字段/数字） | 复核命令 | 结论 |
|---|---|---|---|---|
| 1 | 干净克隆在 `env -i` 下可以构建 | `cases/golden/static_2d/{cooks_membrane,lame_cylinder}/reference/build-manifest.json`：`profile="release"`，两例引用同一二进制 `sha256=6df6ea8d18c9fa5d4a5c8a74268ad0105bb78c48fc93a5ed666cf328dffcc98a` | `tools/build.sh release`（`env -i` 下执行，见 `docs/build-linux.md`）；本次复核未重新执行构建，仅核对已记录 manifest 与 `docs/m0/M0-report.md` 一致 | 独立证据支撑 |
| 2 | 外部依赖（ifx、MKL、gidpost 桩）在 build manifest 中有路径、版本和哈希 | 同上 manifest：`toolchain.HSTAR_FC=/opt/intel/oneapi/compiler/2025.3/bin/ifx`，`fc_version="ifx (IFX) 2025.3.3 20260319"`，`HSTAR_MKLROOT=/opt/intel/oneapi/mkl/2026.1`；`runtime_dependencies` 长度 12，`unresolved_runtime_deps=[]` | `python3 -c "import json;d=json.load(open('cases/golden/static_2d/lame_cylinder/reference/build-manifest.json'));print(len(d['runtime_dependencies']),d['unresolved_runtime_deps'])"` → `12 []`（已跑，结果一致） | 独立证据支撑 |
| 3 | 来源哈希：源码基线逐文件 SHA-256 | `legacy/source-manifest.json`（39 文件，含 `stubs/gidpost_stub.c`） | `python3 tools/yl_manifest.py check legacy/source-manifest.json` → `PASS: legacy/source-manifest.json (39 files verified)`（已跑） | 独立证据支撑 |
| 4 | 来源哈希：两例输入文件逐文件 SHA-256 | `cases/golden/static_2d/{cooks_membrane,lame_cylinder}/input-manifest.json`（各 16 文件） | `python3 tools/yl_manifest.py check cases/golden/static_2d/cooks_membrane/input-manifest.json` 与 `lame_cylinder` 同名文件 → 均 `PASS (16 files verified)`（已跑） | 独立证据支撑 |
| 5 | 来源哈希：gidpost 桩与旧 `BIND(C)` 声明的符号对应 | `legacy/yl/gidpost.F90` 133 处 `BIND(C…)` 中 126 处带 `NAME=`；`legacy/stubs/gidpost_stub.c` 定义 126 个 `GiD_*` 函数 | `grep -cE "BIND\(C.*NAME=" legacy/yl/gidpost.F90` → `126`；`grep -cE "^(void\|int\|GiD_FILE\|CPostFile)\s.*GiD_" legacy/stubs/gidpost_stub.c` → `126`（已跑，与 `docs/in-review-audit-2026-09-08.md` 一致） | 独立证据支撑 |
| 6 | 隔离运行：七种运行状态各有反例 | `docs/tasks/M0-03.md`「实际结果」一节的**文字叙述**：称假二进制套件 8/8 触发了 TIMEOUT、CRASHED、FAILED×2、MISSING_OUTPUT×2、GOLDEN_MODIFIED、随后 INPUT_HASH_MISMATCH | `runs/` 已整目录 `.gitignore`（`grep -n "^runs/" .gitignore` → 命中），仓库内未找到对应假二进制脚本或保留的反例 run-manifest（`find . -iname "*fake*binary*"` 等均为空、`find docs -iname "*M0-03*"` 只有任务文档本身）；`schemas/run-manifest.schema.json` 的 13 值 `status.enum` 只证明状态**可以被表示**，不证明七种反例**曾被实际触发** | **仅有断言** — 七种状态各有反例这句话目前只有 `M0-03.md` 的叙述作支撑，没有可独立重放的脚本或保留下来的反例产物（`runs/` 被 gitignore，本次复核未找到任何持久化的假二进制或对应 run-manifest）。要升级为独立证据，需要把 B03 的假二进制套件固化为仓库内脚本（例如 `tests/`or `tools/` 下），使复核人可以重新触发并核对七种状态 |
| 7 | 隔离运行：两例正常运行状态为 COMPLETED | `cases/golden/static_2d/{cooks_membrane,lame_cylinder}/reference/run-manifest-1.json`：`status="COMPLETED"` | `python3 -c "import json;print(json.load(open('cases/golden/static_2d/cooks_membrane/reference/run-manifest-1.json'))['status'])"` → `COMPLETED`（cooks、lame 均已跑，一致） | 独立证据支撑 |
| 8 | 运行前后对 golden 目录重哈希无变化 | `tools/yl_run.py:260` `GOLDEN_MODIFIED` 分支 + 源码第 510 行注释「golden must be untouched」；两例 `run-manifest-*.json` 均无 `GOLDEN_MODIFIED` | 读 `tools/yl_run.py` 第 260、510 行确认机制存在；未重新执行运行器，机制本身未被本次复核以外的独立脚本验证 | 独立证据支撑（机制代码 + 历史运行记录一致；本次未重放） |
| 9 | 两个基准在单线程下各运行三次，解析后逐值精确相等，最大差记为 atol 下限 | `cases/golden/static_2d/{cooks_membrane,lame_cylinder}/reference/repeat-report.json`：三次 `flavia_res_sha256` 完全相同（cooks 三次均为 `5b92878e6a331e4e8b4118f60919781a48404942db5cfc699be1d01f7db18961`，lame 三次均为 `ebfd0a204c2fdf4e67f4ce5fb86f20d72f29f939e7d1237bc924c1a09e83be73`），`max_abs_diff_across_repeats=0.0`，`threads={"OMP_NUM_THREADS":"1","MKL_NUM_THREADS":"1"}` | `python3 -c "import json;d=json.load(open('cases/golden/static_2d/cooks_membrane/reference/repeat-report.json'));print([r['flavia_res_sha256'] for r in d['runs']],d['max_abs_diff_across_repeats'])"`（已跑，lame 同理） | 独立证据支撑 |
| 10 | 基线（候选）二进制与 reference 结果逐值比较通过 | `docs/m0/evidence/candidate/compare-{cooks_membrane,lame_cylinder}.json`：`passed=true`，全部 block `max_abs_diff=0.0`；候选二进制哈希 `dea1a66d0b57daf400a3bd21c906e760c1a9ff02dc952f0e29fa62de408fc68c`（与 reference 的 `6df6ea8d…` 不同，属预期——分别来自 `build/release-candidate` 与 `build/release`） | `python3 -c "import json;d=json.load(open('docs/m0/evidence/candidate/compare-cooks_membrane.json'));print(d['passed'],[b['max_abs_diff'] for b in d['blocks']])"`（已跑，两例一致） | 独立证据支撑 |
| 11 | 模型说明：两例节点/单元规模与 MODEL.md 描述一致 | `cases/golden/static_2d/cooks_membrane/legacy/1.cor`/`1.ele` 非空行数 289/256；`lame_cylinder` 为 81/64；`MODEL.md` 量级估计「位移尺度 ρgL²/E ≈ 2.2e-3 m … 应力尺度 ρgL ≈ 1.1e6 Pa」与 `repeat-report.json` 的 `observables_summary.max_abs`（cooks：位移 7.568e-3、应力 4.002e6）同数量级 | `grep -acv '^\s*$' cases/golden/static_2d/cooks_membrane/legacy/1.cor` → `289`；`.../1.ele` → `256`；`lame_cylinder` 同法 → `81`/`64`（已跑） | 独立证据支撑 |
| 12 | 容差说明：B02（重复）容差 | `tolerances.toml`（两例）：`[repeat] atol=0.0 rtol=0.0`，与「三次逐值精确相等」一致 | `cat cases/golden/static_2d/cooks_membrane/tolerances.toml`（已读，lame 同）——本条容差有 B02 实测支撑（判据 9） | 独立证据支撑 |
| 13 | 容差说明：跨路径（M4 用）容差 | `tolerances.toml` `[cross_path]`：`status="provisional"`；cooks `atol=2.2e-12,rtol=1e-9`（位移）/`atol=1.1e-3,rtol=1e-9`（应力）；lame `atol=3.8e-15`/`atol=4.7e-5`，`rtol=1e-9`；`basis` 字段自称「按量纲估算，待 M0-04b 噪声数据复核」 | `cat cases/golden/static_2d/{cooks_membrane,lame_cylinder}/tolerances.toml`（已读） | **仅有断言** — 数字本身是量纲估算（`atol ≈ 1e-9 × 量级`），因 B02 三次重复逐字节相同（判据 9），没有任何观测噪声支撑这两个具体数值；`[cross_path].status` 字段自己写着 `"provisional"`。这是文档自曝，不是复核新发现 |
| 14 | 干净构建：CI 状态如实标注，未虚报通过 | `docs/m0/M0-report.md` Build 门备注「CI NOT_RUN（无 ifx 环境）」 | `grep -n "CI NOT_RUN" docs/m0/M0-report.md`（已读） | 独立证据支撑（NOT_RUN 本身即证据，无需另外复现） |
| 15 | 检查型构建（debug/strict）暴露的缺陷已处置或明确记录为风险 | `docs/08-risk-register.md`：R17「CLOSED（M1-03，2026-09-07）：… strict profile 两例 COMPLETED 且与 reference 精确相同」；R18「CLOSED（M1-03…）：… debug profile 两例 COMPLETED 且精确相同」；stderr 原始证据 `docs/m0/evidence/{fpe0-uninit-elements-kinddefine,check-bounds-tcurves-zero,check-uninit-msan-openmp-runtime}.stderr.txt` | `grep -n "R17\|R18" docs/08-risk-register.md`（已跑）；三份 `.stderr.txt` 存在于仓库 | 独立证据支撑 |
| 16 | 历史输出对照（脏树 vs candidate）中悬而未决项已关闭 | `docs/m0/orig-worktree-diff.md`：「下表 3 个 VERIFY 项全部改判 DEFER」；`docs/STATUS.md` M0-01 行文字现为「3 项待 M0-04c 验证」的括注已更新为「已由 M0-04c 判定为 DEFER，见 docs/m0/orig-worktree-diff.md」 | `grep -n "DEFER" docs/m0/orig-worktree-diff.md`；`grep -n "M0-01" docs/STATUS.md`（均已读） | 独立证据支撑（此前审计发现的文字未同步问题，STATUS 已订正，本次复核确认订正已落地） |
| 17 | 干净构建/隔离运行的“干净”前提：候选提交与参考源码身份明确、可追溯 | `M0-report.md` 头部：候选提交=本报告所在提交；参考源码=`legacy/yl` = `hstarYLOrig@5414e73` | `git log --oneline -1 -- docs/m0/M0-report.md`；`git log -1 5414e73 2>&1 \| head -3`（外部仓库提交，未必在本地可达，仅可核对字符串记录一致性） | 独立证据支撑（本地可核对记录内容；`5414e73` 若指向外部历史仓库，其可达性本身超出本仓库只读复核范围，不影响本条判据——判据只要求候选提交与参考源码身份**明确**） |
| 18 | 复核与负责人签收 | `M0-report.md` 签收节：「复核结论/负责人接受记录：**待填写（不得代填）**」 | `grep -n "复核结论" docs/m0/M0-report.md` → 命中该行（已跑） | **仅有断言**——严格说这是「尚无断言」：五项子任务的技术证据链齐全，但从未有独立于实现人的第二个人读过并签字。`docs/07` 的判决规则要求「范围和复核签名明确」，这里签名字段本身是空的 |

## 明确不能据此声称的事

按 `docs/07-acceptance-and-release.md` M0 行「不能据此声称：历史算例物理正确、现代输入可用」，
具体化到本项目现有产出：

- **不能声称 Cook's membrane / Lamé cylinder 的旧程序输出在物理上是对的。** 两例已被
  `docs/08-risk-register.md` R08 改判为「回归例」——只证明两个静力算例只受重力体力，
  且旧程序对同一输入给出确定性输出；没有任何解析解、实验值或独立参考解与之比对。
  `M0-report.md` 原文：「这不是物理验证；两例只证明固定环境下旧程序的确定性输出」。
- **不能声称现代（modern）输入路径可用。** M0 全部证据只覆盖 legacy 输入文件
  （`.cor/.ele/.mat/.loa/...`）经旧程序求解的路径；`case.toml` 等现代 authoring 格式
  尚未定义（见 `docs/02-migration-plan.md` M5 才出现），M0 阶段未产出、未测试任何现代输入。
- **不能声称已覆盖除本组合外的任何能力。** 接受范围严格限定在 `M0-report.md` 头部所列
  的组合：2D、Q4、平面应变、线弹性各向同性、单阶段单增量静力、重力体力、固定位移约束、
  PROFILE 求解器、位移与节点应力输出、Linux x86-64、ifx 2025.3、MKL 2026.1、单线程。
  不包含其他单元类型、材料模型、分析类型、平台或多线程。
- **不能声称跨路径（新旧对照）数值容差已经过实证定案。** 判据 13：`[cross_path]` 容差
  自标 `provisional`，量纲估算，无噪声数据支撑，须在 M0-04b 之后另开任务定案。
- **不能声称 CI 已验证任何内容。** Build 门明确 `CI NOT_RUN`，全部证据来自本地一键脚本。
- **不能声称本阶段已完成负责人签收。** 判据 18：签收字段为空；`docs/07` 明文
  「自动全绿不等于负责人签收」。

## 仍属断言而非独立证据的项

| 判据 | 当前状态 | 升级为独立证据所需 |
|---|---|---|
| 判据 6：七种隔离运行状态各有反例 | 只有 `docs/tasks/M0-03.md`「实际结果」一节的文字叙述；假二进制套件和对应反例 run-manifest 均未持久化（`runs/` 整目录 gitignore，仓库内无保留脚本或产物） | 把假二进制反例套件固化为仓库内可重放脚本（或至少把七种反例各自的 run-manifest 摘录进仓库，例如 `docs/m0/evidence/` 下），使复核人能独立重新触发或核对每一种状态，而不是只读一段叙述 |
| 判据 13：跨路径容差（`atol=2.2e-12` / `rtol=1e-9` 等四组数字） | 量纲估算，`status="provisional"`，B02 三次重复为逐字节精确相等，没有任何非零噪声观测支撑当前具体数值 | 按 `docs/02-migration-plan.md` M0-04b 的既定路径，取得同一二进制在不同线程数/不同运行环境下的重复噪声分布，用实测噪声上界重新定案 `[cross_path]` 的 atol/rtol，并将 `status` 由 `provisional` 改为定案状态 |
| 判据 18：复核结论/负责人接受 | `M0-report.md` 签收节留空；`docs/in-review-audit-2026-09-08.md` 的九项审计不构成独立复核（其自身声明「这不是签收」） | 需要一位不同于实现人的复核人，实际读取本文件第 1～17 条列出的证据（或独立重跑判据 1、8 等未被本次复核重放的项），在 `M0-report.md` 签收节和本文件签字页填写结论 |

## 补充：M1 侧的新发现（2026-09-08，晚于本矩阵编制）

M4-01 的解析器作者发现 `Load.f90:231` 是一处**已执行、但未登记也未包装**的读取，
详见 `docs/m1/M1-finding-2026-09-08-unwrapped-loa-read.md`。它不影响 M0 的任何判据
（M0 不依赖 reader 清单），但**影响 M1-01 与 M1-02 的可签结论**，
且与本矩阵判据 6 是**同一个证据形态问题**：分类做在聚合层级（unit + 计数 / 状态枚举），
无法逐项核对，因而无法区分"被审视后判为不适用"与"从未被看过"。

## 签字页

- 复核人：**Huijun（负责人）**。记录人：Claude，依会话中的明示指令代为记录，非代为决定。
- 日期：**2026-09-09**
- 结论（接受 / 有条件接受 / 退回）：**接受**
- 条件或退回理由：

  负责人行使了本文件第 13 行点明的那个判断——「是否要求先补齐前两项断言，是负责人的判断，
  不是这份文件能替代的证据」——选择**不要求先补齐**。因此：

  1. **判据 6 与判据 13 在签收后仍属断言，不属独立证据。** 签字不改变证据形态。二者转为
     登记债务 **R28**（`docs/08-risk-register.md`），各自的升级路径沿用上表「升级为独立证据
     所需」一列，不得因本次签收而删除或淡化。
  2. **判据 18 只满足了一半。** 本次签收提供的是「负责人接受」；「一位不同于实现人的复核人
     实际读取第 1～17 条证据」这一半，在单人项目里结构性缺席，仍未满足。R28 一并记录。
  3. **接受范围不因签收而扩大**，仍严格限于上文「不能声称」六条所划定的边界：非物理验证、
     不含现代输入路径、不含所列组合以外的任何能力、跨路径容差未定案、CI 未运行。

  换言之，本次签收使 M0 **在其自述范围内**可以进入已验收状态，并解除后续阶段对 M0 签收的
  等待；它**不**把任何一条断言变成证据。
