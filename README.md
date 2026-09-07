# HSTAR Evolution

HSTAR Evolution 是 YL 版 HSTAR 的渐进式现代化工程。目标不是重写有限元算法，也不是再做一个
生成旧 `.glb/.man/.loa` 文件的前处理器，而是在保持计算核心可回归的前提下，建立一个可靠、
可验证、最终可由简洁输入直接初始化的求解器入口。

## 核心边界

```text
旧 deck ──> Legacy Adapter ──┐
                             ├──> ProblemState ──> validate/finalize ──> RuntimeState ──> YL kernel
case.toml ─> Modern Reader ──┘
```

- 新输入路径不得生成旧 deck 再交给原始 `READ`。
- 旧输入长期保留，但只作为一种 Legacy Adapter。
- 所有输入先进入临时 `ProblemState`，完整校验后才提交运行时；`ProblemState` 采用通用 CAE 的
  模型/历史对象模型（mesh、sets、materials、sections、amplitudes、steps、solver），单位固定 SI（ADR-0003）。
- 不支持的能力必须拒绝，禁止静默默认和自动回退。
- 迁移单位是“可独立验证的分析能力”，不是单个文件后缀。

## 仓库布局

```text
legacy/                 固定版本的 YL 基线，只做兼容与对照
src/input/               旧/新输入适配器
src/problem/             ProblemState 与语义校验
src/runtime/             向计算核心提交的 RuntimeState
src/diagnostics/         结构化错误、状态摘要和崩溃前诊断
src/solver/              逐步迁入的求解器调度与计算模块
schemas/                 人工输入 schema
cases/golden/            冻结的金标准算例
cases/migration/         当前阶段正在迁移的算例
cases/probes/            单一能力和故障注入探针
tests/                   单元、状态等价、数值和物理测试
tools/                   导入、检查、状态比较和运行工具
docs/                    架构、计划、质量门和决策记录
```

## 当前状态

当前为 `M0 — 可重复基线`（IN_REVIEW，等待独立复核）：

- 已导入 YL 基线源码；
- 已加入 `cooks_membrane` 与 `lame_cylinder` 两个二维静力回归例（已核实均为重力体力模型，非经典解析基准）；
- 已冻结总体架构和迁移禁区；
- Linux 固定工具链构建、隔离运行器、参考结果（两例各 3 次逐值相等）已建立，见 `docs/m0/M0-report.md`；
- 尚未声明任何现代输入能力可用。

详细执行顺序见 [docs/02-migration-plan.md](docs/02-migration-plan.md)。

## 迁移工作入口

从 [执行与任务拆分](docs/05-execution-backlog.md) 开始。测试按
[测试规格](docs/06-test-specification.md) 执行，阶段结项使用
[验收与发布流程](docs/07-acceptance-and-release.md) 和
[验收模板](docs/templates/acceptance.md)。当前进度见
[STATUS.md](docs/STATUS.md)，风险见 [风险登记表](docs/08-risk-register.md)。

这些文件描述待实施契约；目录、Schema 或算例存在不代表功能实现或验证通过。

## 开始工作的规则

1. 先在 `cases/manifest.toml` 登记能力和验证等级。
2. 先保存旧程序的状态摘要与数值基线，再修改 reader 或初始化路径。
3. 每个阶段只打开白名单能力；未在白名单中的组合必须失败。
4. 任何导致结果变化的提交都必须说明是修复、预期改变还是回归。
5. `legacy/yl` 不做无计划清理；修改必须由迁移任务和对照测试驱动。
