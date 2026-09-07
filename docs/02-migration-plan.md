# 迁移总计划

本计划按质量门推进，不按日历强行切换。工期取决于每种能力暴露出的计算核心缺陷；后续阶段
只有在前一阶段出口条件全部满足后才开始生产迁移。

执行细则以 `05-execution-backlog.md`、`06-test-specification.md` 和
`07-acceptance-and-release.md` 为准。M1～M5 首先只覆盖一条经 M0 核实的二维静力路径。
允许提前设计下一阶段，但不得提前宣称通过。历史源码快照并非已经认证的生产基线。

## M0：独立建仓与可重复基线

目标：新项目拥有明确边界，任何后续结果都能追溯到固定源码和算例。

任务：

- 导入已提交的 YL 源码基线并记录来源提交；
- 建立独立构建脚本，区分 Debug、Sanitize、Release；
- 记录编译器、MKL、GiD 库和平台版本；
- 建立算例 manifest、输入哈希和输出清理规则；
- 固定 `cooks_membrane`、`lame_cylinder` 两个首批基准；
- 保存退出码、关键结果、收敛历史和运行时间基线；
- CI 至少能够编译并运行一个小算例。

出口条件：

- 干净克隆在 `env -i` 下可以构建，外部依赖（ifx、MKL、gidpost 桩）在 build manifest 中有路径、版本和哈希；
- 两个基准在单线程下各运行三次，解析后的 `1.flavia.res` 逐值精确相等，最大差记录为后续 atol 下限；
- 基线输入和二进制来源有哈希；
- 运行前后对 golden 目录重哈希无变化（不能依赖 `git status`，因为 `.gitignore` 屏蔽了运行产物）；
- CI 在无 ifx 许可的环境记 NOT_RUN，以本地一键脚本代替，不宣称 CI 已通过。

## M1：Crash Firewall——旧输入可控失败

目标：输入问题不能再通过越界、未分配数组或 Fortran I/O 异常表现为崩溃。

任务：

- 建立 `ErrorList`、错误码、严重级别和来源位置；
- 包装首条能力路径消费的输入 `open/read/close`，统一 `iostat/iomsg`；其余 reader 登记为未迁移；
- 为数量、范围、枚举、引用和数组乘积设置前置检查；
- 增加 `--check-legacy`，只读和检查，不进入求解；
- 增加故障注入算例：缺行、错类型、负数量、无效材料号、坏节点号、曲线引用缺失；
- Debug 构建启用 bounds、uninitialized、floating-point 检查；
- 将输入错误、初始化错误、求解失败和内部错误分成不同退出码。

出口条件：

- 已登记的输入故障探针全部返回结构化错误；
- 不允许产生 core dump、访问越界或交互式等待；
- 正常基准的状态和结果不变。

## M2：状态观测——冻结求解器入口

目标：明确 YL 第一次组装前真正消费的全部状态。

任务：

- 登记首次组装、阶段开始、增量参数装载和重启恢复后的检查点；YL 存在延迟读取，不能假设所有输入在启动时已经消费；
- 为控制量、网格、组、DOF、材料、荷载、约束、阶段和 numerics 导出规范化快照；
- 浮点值采用明确的序列化和容差策略；
- 指针、地址、未初始化填充和非决定性顺序不得进入摘要；
- 建立状态 diff 工具，错误定位到对象和字段；
- 为首批算例冻结 state fingerprint。

出口条件：

- 相同输入三次运行得到相同摘要；
- 人为修改一个材料、约束或荷载时，diff 能指出准确位置；
- 摘要生成不改变求解结果。

## M3：ProblemState 与事务式初始化

目标：把“边读边改全局变量”改成“完整构建后一次提交”。

任务：

- 定义最小 `ProblemState`，先覆盖二维线弹性静力，顶层结构按 ADR-0003 的 CAE 对象模型（case、mesh、materials、sections、amplitudes、steps、solver）；
- 将 mesh、sets、materials、sections、amplitudes、steps（boundary/load/controls/output）、solver 分成有所有权的类型；YL 的“组”拆为 elset、section、material；
- 明确 unset、zero、empty 三者语义，避免使用模糊哨兵值；
- 实现 normalize、validate、finalize 和 manifest；
- 实现唯一 `commit_legacy_globals`；
- 失败路径释放临时对象且不修改旧全局状态；
- 添加类型级单元测试和 allocation/ownership 测试。

出口条件：

- `ProblemState` 可以完整表示两个首批基准；
- 无半初始化提交；
- 所有派生数量和默认值可在 manifest 中追踪；
- bridge 后的 state fingerprint 与原路径一致。

## M4：Legacy Adapter 影子迁移

目标：旧 deck 不再由原 reader 直接驱动全局变量。

任务：

- 将旧 reader 拆成只构建 `ProblemState` 的适配器；
- 首先覆盖白名单静力切片，而不是追求读取全部历史方言；
- 影子模式在两个独立子进程和目录中运行原路径与适配路径，在对应检查点比较状态，避免共享全局变量及文件游标污染；
- 对比两者 state fingerprint；
- 等价后切换白名单算例，保留命令行回退开关；
- 对未支持方言返回 `UNSUPPORTED_LEGACY_DIALECT`。

出口条件：

- 首批基准状态逐字段等价；
- 两条路径的关键结果在容差内一致；
- 新 Legacy Adapter 成为白名单切片默认入口；
- 回退开关经过测试，但不会自动触发。

## M5：首个现代输入闭环

目标：二维 Q4 线弹性静力不依赖任何旧输入文本。

白名单：

- 2D、Q4、位移场；
- 线弹性各向同性材料；
- 单阶段静力；
- 固定/给定位移；
- 重力、节点力、简单边压力；
- PROFILE（现有两套输入声明的求解器）；PARDISO 作为后续单独验证的变体；
- 位移、应力和反力输出。

任务：

- 定义 `case.toml` v1 authoring schema（CAE 对象模型，SI 单位，见 ADR-0003）；
- 实现 TOML → Authoring AST → ProblemState；
- 增加 SI 单位声明、材料参数合理范围警告、名称引用和未知字段检查；
- 让 `npoin/nelem/ngroup/nmats/mdofn` 等数量全部派生；
- 增加 `check`、`dump-state`、`dry-assemble`、`run` 四个命令；
- 为两个金标准编写现代输入；
- 新建 patch test 探针和符合解析假设的 Lamé 探针（种子算例只作回归例，不承担解析判据）；
- 新建输出反力的探针，补齐外力与反力平衡判据（种子算例关闭了反力输出）；
- 用户输入目标控制在 30～50 行，不以隐藏物理选择为代价。

出口条件：

- modern 路径不打开 `.glb/.mat/.pre/.loa/.man/.sol/.opr`；
- 两个基准状态与数值结果通过；
- 物理 benchmark 通过；
- 白名单以外的字段或组合明确拒绝。

## M6：静力能力扩展

按以下子阶段逐个交付，每个子阶段独立过门：

1. 3D 与更多连续体单元；
2. 多材料、多组和局部坐标；
3. 非线性迭代与增量控制；
4. Mohr-Coulomb / Drucker-Prager / Duncan-Chang；
5. 混凝土损伤；
6. Goodman、接触和薄层；
7. 施工阶段、激活、材料替换和重启；
8. 梁、钢筋与粘结。

每个子阶段必须新增：最小 probe、旧路径等价算例、独立物理 benchmark、能力声明和故障探针。

## M7：模态与动力

顺序：

1. 模态分析与质量矩阵；
2. 固定边界动力；
3. 阻尼和时间曲线；
4. 静力预载 → 动力阶段依赖；
5. VIE 固体吸收边界；
6. 流固耦合、附加质量与流体吸收；
7. MIF 和其他特殊边界。

特殊质量门：模态正交性、单自由度解析解、零激励保持、重启连续性、能量收支及吸收边界
反射能量关系。VIE 分支结构上禁止固定基底加速度，避免双重激励。

## M8：温度、渗流与多场耦合

顺序：稳态温度 → 瞬态温度 → 稳态渗流 → 瞬态渗流 → 温度应力 → 渗流应力 → 完整多场。

每阶段必须定义场 DOF、初边值条件、材料参数单位、阶段间状态传递和守恒判据。温度、孔压和
位移不能继续依赖同一个整数槽位在不同开关下改变含义。

## M9：长尾能力与 legacy 收缩

覆盖反分析、可靠度、网格细化、冷却水管、子模型和历史专用文件。只有具备真实需求、旧算例
和验证判据的能力才迁移；其余明确标记为 legacy-only 或 retired。

当某项能力的 modern 路径稳定两个发布周期后：

- 禁止新增该能力的旧 deck；
- legacy reader 转为只读兼容；
- 记录弃用期限；
- 最终删除对应自动回退和混合状态代码。

## 长期发布等级

- `experimental`：开发可用，不承诺结果稳定；
- `state-equivalent`：求解器入口状态与基线等价；
- `numerically-verified`：数值回归通过；
- `physics-verified`：独立物理判据通过；
- `production`：错误路径、文档、平台和性能门均通过。

只有 `production` 能力默认开放。
