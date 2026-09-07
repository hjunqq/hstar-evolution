# 测试层次

```text
unit/             类型、解析、校验、派生和错误处理
state/            新旧路径的 ProblemState/RuntimeState 等价
numerical/        位移、反力、应力、特征值和收敛历史
physics/          解析解、patch test、守恒、能量和消融关系
failure/          坏输入、坏引用、越界尺寸和不支持组合
integration/      从输入到求解结果的完整运行
```

“进程退出码为 0”只能算 integration smoke，不代表 numerical 或 physics 通过。

