# 工具规划

M0～M5 需要的命令：

```text
yl-case hash          计算并检查算例输入哈希
yl-case clean         只清理 manifest 声明的可再生产物
yl-check legacy       旧输入预检查
yl-check modern       现代输入预检查
yl-state dump         导出第一次组装前状态
yl-state diff         对比两个状态摘要
yl-run                运行并生成 build/run manifest
yl-import-case        从登记来源导入算例，不导入运行垃圾
```

工具实现必须 fail-closed：无法判断时返回未验证，不得返回通过。

