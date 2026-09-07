# 使用 Sanitizer 检测内存/线程问题（Intel oneAPI Fortran）

## 地址/内存错误与泄漏
- 打开 AddressSanitizer：编译时加 `-qsanitize=address -g -traceback`（等价于 GCC/Clang 的 `-fsanitize=address`）。
- 建议用 Debug/小规模输入运行，Sanitizer 会在越界、重用、泄漏时输出带行号的报告，末尾给出泄漏摘要。

## 线程数据竞争/死锁
- 打开 ThreadSanitizer：编译时加 `-qsanitize=thread -g -traceback`（等价于 `-fsanitize=thread`）。
- 用小规模输入测试，报告会标出数据竞争的线程栈。

## 使用提示
- 在 VS 配置中，将目标配置的 Fortran 编译附加选项增加相应的 `-qsanitize=...` 开关；若追求符号信息，保持 `-g`。
- Sanitizer 有额外时间/内存开销，建议使用较小输入数据集进行诊断。
- 与 OpenMP 一般兼容，但可先用较低优化级（如 `-O0/-O1`）便于调试。
- 运行结束若无报告，说明本次执行未触发检测；如需泄漏列表，确保 AddressSanitizer 开启并查看程序退出时的汇总。
