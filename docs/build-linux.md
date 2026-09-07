# Linux 构建说明（M0-02）

首发平台为 Linux x86-64。Windows/Intel Fortran 工程文件仍保留在 `legacy/yl`，但未在本工程验收。

## 依赖

| 依赖 | 版本（已验证） | 位置 | 说明 |
|---|---|---|---|
| Intel Fortran `ifx` | 2025.3.3 (20260319) | `/opt/intel/oneapi/compiler/2025.3/bin/ifx` | 源码含 `FORM='BINARY'` 等 Intel 扩展，gfortran 不能编译 |
| Intel MKL | 2026.1 | `/opt/intel/oneapi/mkl/2026.1` | PARDISO/VSL 代码需要链接；PROFILE 求解路径本身不调用 MKL |
| `libiomp5.so`、`libimf.so`、`libintlc.so.5` | 随 ifx 2025.3 | `/opt/intel/oneapi/compiler/2025.3/lib` | OpenMP 与 Intel 运行时 |
| gcc | 13.3 | `/usr/bin/gcc` | 只编译 `legacy/stubs/gidpost_stub.c` |
| Python 3 | 3.12 | `/usr/bin/python3` | 清单与构建 manifest，仅标准库 |

`tools/env.sh` 以绝对路径固定上述依赖（`HSTAR_FC`、`HSTAR_MKLROOT`、`HSTAR_IOMP_LIBDIR`），
不依赖 Intel `setvars.sh`，并清除继承的 `LD_LIBRARY_PATH`。改用其他版本时先 `export` 覆盖再
`source`；`build-manifest.json` 记录实际使用的路径、版本和哈希。

## 构建

```bash
tools/build.sh release          # -O2，M0 参考数值构建
tools/build.sh debug            # -O0 -g -traceback -check bounds,pointers
tools/build.sh strict           # debug + -init=snan,arrays -fpe0
tools/build.sh sanitize         # strict + -check uninit（MemorySanitizer）
tools/build.sh release --src /path/to/other/HSTAR --label candidate   # 外部源码树（M0-04c）
```

各 profile 在纯快照 `5414e73` 上对两个种子算例的实际表现（2026-09-07）：

| profile | 结果 | 证据 |
|---|---|---|
| release | 两例正常结束，`1.flavia.res` 与来源仓库历史输出逐字节相同 | M0-02 任务记录 |
| debug | 在 `Fem.f90:12288` 越界读 `tcurves(0)`（`.pre` 约束集 `itcurve=0`）后中止，退出码 152 | `docs/m0/evidence/check-bounds-tcurves-zero.stderr.txt` |
| strict | 更早在 `Elements.f90:2588` 触发 floating invalid：`kinddefine` 对一维单元类型不赋值 `t/u` 即调用 `shfunc`；ifx 对 signalling NaN 即使 `-fpe3` 也会陷入 | `docs/m0/evidence/fpe0-uninit-elements-kinddefine.stderr.txt` |
| sanitize | 未进入 Fortran 代码即被 MemorySanitizer 在未插桩的 OpenMP 运行时中报告；本工具链不可用，记 BLOCKED | `docs/m0/evidence/check-uninit-msan-openmp-runtime.stderr.txt` |

两处中止都是快照中的潜在缺陷（风险 R17、R18），在 release 构建下未影响两例结果。M0 只以
release 作为参考构建；检查型 profile 的“可完整运行”是 M1 的出口条件，不是 M0 的。

产物在 `build/<profile>[-<label>]/`：`hstar`、`obj/`、`build.log`、`build-manifest.json`。
`build/` 已被 `.gitignore` 排除。

构建脚本是 fail-closed 的：

- 使用仓库内快照时先运行 `yl_manifest.py check legacy/source-manifest.json`，不通过则拒绝构建；
- 链接后对二进制运行 `ldd`，任何未解析依赖都使构建失败（退出码 5）；
- manifest 记录编译器版本、全部编译/链接参数、每个源文件与依赖库的 SHA-256、二进制哈希、
  warning/remark 计数、起止时间。

链接使用 `-Wl,--disable-new-dtags` 生成 RPATH 而非 RUNPATH。RUNPATH 不作用于传递依赖，
会导致 MKL 自身需要的 `libintlc.so.5` 在干净环境下找不到；RPATH 则可在无 `LD_LIBRARY_PATH`
的环境直接运行。

干净环境验证方式：

```bash
env -i HOME=$HOME PATH=/usr/bin:/bin bash tools/build.sh release
env -i /usr/bin/ldd build/release/hstar      # 应无 "not found"，且路径均为 env.sh 固定的目录
```

## GiD 输出

`gidpost.F90` 依赖 GiD 后处理库与 HDF5；本工程用 `legacy/stubs/gidpost_stub.c` 提供全部
126 个 `BIND(C)` 符号的空实现，只用于链接。因此 `.post.bin` 等 GiD 二进制输出不会生成；
两个种子算例使用 `outplot=GIDR`，结果由 Fortran 直接写入文本 `1.flavia.res`，不受桩影响。

## 运行时约定

- 参考运行固定单线程：`env.sh` 默认 `OMP_NUM_THREADS=1`、`MKL_NUM_THREADS=1`、`MKL_DYNAMIC=FALSE`；
- 程序从当前目录读取 `inp`，再按其中的问题名打开约 40 个后缀文件（多数为写），必须在隔离
  副本目录中运行，标准输入接 `/dev/null`；
- 旧程序多处 `stop '文本'` 退出码为 0，成功判定必须结合 stderr 关键字与必需输出解析（M0-03）。

## 未覆盖项

- 未验证 gfortran、Windows、其他 oneAPI 版本；
- `-check uninit`（MSan）在本工具链不可用；`-init=snan` 与 `-check bounds` 目前都在快照的已知缺陷处中止，
  两例尚无“检查型 profile 完整运行”的证据；MKL 内部不在任何检查范围；
- 没有 CI 执行环境，B01 在本地以 `env -i` 构建代替，报告中记 CI NOT_RUN。
