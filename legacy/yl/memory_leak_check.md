# Fortran 内存泄露定位与修正指引

## 1) 用 Intel Inspector 定位泄露
- 建议 Debug/小规模输入，编译加 `-g -traceback -check:all -warn:interfaces`，便于符号回溯。
- 64 位命令行示例（oneAPI 自带）：
  ```bat
  "C:\Program Files (x86)\Intel\oneAPI\inspector\latest\bin64\inspxe-cl.exe" ^
    -collect mi3 -result-dir insp_leaks ^
    -- "G:\BB\hstarYLOrig\HSTAR\x64\Profile\hstar.exe"
  ```
  - `mi3` 最彻底；先可用 `mi1` 轻量确认，再用 `mi3` 精细。
  - 跑完用 Inspector GUI 或生成的报告查看 "Memory leak" 条目，栈回溯会指向 `ALLOCATE`/调用者。

## 2) 常见漏点检查
- 在循环/重复调用中 `ALLOCATE` 无对应 `DEALLOCATE`，或提前 `RETURN`/错误分支未清理。
- `POINTER/TARGET` 未 `NULLIFY/DEALLOCATE`，反复指向新地址。
- `ALLOCATE` 未检查 `stat=`，失败后跳过释放。
- C/GiD/HDF5 等外部资源：每个 `malloc/free` 或 `H5F/H5D/H5S/H5A` 都需配对关闭。

## 3) 代码层防漏建议
- 能用 `allocatable` 就不用 `pointer`；`allocatable` 在作用域结束时自动释放。
- 封装分配/释放便于统计：
  ```fortran
  module mem_guard
    integer :: n_live = 0
  contains
    subroutine my_alloc(arr,n,who)
      real(8), allocatable, intent(out) :: arr(:)
      integer, intent(in) :: n
      character(*), intent(in) :: who
      integer :: istat
      allocate(arr(n), stat=istat)
      if (istat /= 0) stop "alloc fail "//who
      n_live = n_live + 1
    end subroutine
    subroutine my_free(arr)
      real(8), allocatable, intent(inout) :: arr(:)
      if (allocated(arr)) then
        deallocate(arr)
        n_live = n_live - 1
      end if
    end subroutine
  end module
  ! 程序结束时输出 n_live 是否为 0
  ```
- 在可能提前退出的子程序中，统一用 `cleanup:` 分支集中 `DEALLOCATE`，或用 `block` 作用域让 `allocatable` 自动回收。

## 4) 如果 Inspector 不可用
- 使用编译器检查：`-check:all -debug full`，并在 VS 里开启运行时内存调试。
- 仍需人工对照分配/释放点，但 Inspector 是最直接的定位方式。
