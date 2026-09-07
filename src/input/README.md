# input

输入适配器层。规划模块：

- `legacy_adapter_*`：从旧 deck 构建 `ProblemState draft`；
- `toml_reader`：从现代 TOML 构建 Authoring AST；
- `normalize`：名称、单位、坐标系和引用归一化；
- `source_location`：保留文件、行、列和对象路径。

本层不得调用求解器、分配求解工作数组或直接修改旧 `global_var`。

