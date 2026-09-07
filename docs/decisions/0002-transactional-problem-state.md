# ADR-0002：输入必须事务式构建和提交

- 状态：接受
- 日期：2026-09-07

## 背景

YL reader 在读取过程中分配数组并修改 `global_var`。中途失败会留下部分有效、部分未初始化
的状态，使后续错误难以定位，并可能直接进入计算阶段。

## 决策

两种输入适配器都先构建临时 `ProblemState draft`。只有 parse、normalize、semantic check、
capability check 和 finalize 全部通过后，才构建 `RuntimeState` 并一次提交。

`unset`、数值零和空集合必须使用类型系统明确区分，不用 `-1` 或 `-huge` 同时承担多个含义。

## 后果

- 初始化阶段可以安全中止；
- 错误能够关联到原始输入对象；
- 旧全局变量需要一个受控 bridge；
- 长期可逐步让计算模块直接消费只读问题状态和显式运行状态。

