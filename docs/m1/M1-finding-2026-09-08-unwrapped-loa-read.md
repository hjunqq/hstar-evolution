# M1 发现：一处已执行但未登记、未包装的读取（`Load.f90:231`）

- 日期：2026-09-08
- 发现途径：M4-01 的 `.loa`/`.pre` 解析器作者忠实复刻读取序列时，发现该语句**在 reader 清单里没有 id**
- 影响：**M1-01 与 M1-02 的可签结论**（两者此刻都在等负责人签字）
- 状态：已核实，未修复。修复属 M1 范围，不在 M4-01 内。

## 事实

```fortran
! legacy/yl/Load.f90:230-232（external_load_1）
elseif (type_curve/='ARCLENGTH'.and.type_curve/='EXTRAPOLATION'   &
    .and.type_curve/='HARMONIC'.and.type_curve/='WATERLEVEL') then
 read(loadunit,*)tcurves(itcurve)%dfact_curve(1:ntime) !!one record
endif
```

| 检查 | 结果 |
|---|---|
| 在 `docs/m1/io-sites.json`（1022 静态全集）里 | **在**，`Load.f90:231` |
| 在 `reader-inventory.toml` 的 152 条 reader 里 | **不在**（清单从 `Load.f90:220` 直接跳到 `:239`） |
| 有 `call diag_check_read` 包装 | **没有** |
| 在 gdb 实证命中集（两例各 211 位点）里 | **不在** |
| 两个 golden 算例的 `type_curve` | `LINEAR` |

## 它确实执行了——反证

`1.loa` 的曲线段落：

```
 2  LINEAR  0  2      <- ntime=2, type_curve=LINEAR
 0  1                 <- 两个时间值
 1  1                 <- 两个系数值
 Define point load    <- title#2
```

- `Load.f90:220` 读 `ttime_curve(1:2)`，消费 `0 1`
- `Load.f90:239` 读 title#2，消费 `Define point load`
- **中间的 `1 1` 必须由某处消费。** 唯一的候选就是 `:231`。

若 `:231` 未执行，`:239` 会把 `1 1` 当作字符标题读走（**字符读不会报错**），随后
`:241` 拿 `Define point load` 去读整数——必然运行时错误。而两例均正常完成。

`LINEAR` 同时满足那四个 `≠` 条件，分支本身也成立。**所以 `:231` 执行了，是证据漏了它。**

## 为什么会漏

`reader-inventory.toml` 的 `not_on_path` 里有一组：

```toml
unit_var = "loadunit", file = ".loa", site_count = 33
reason = ".loa records for point loads, edges, edge loads, beam/plate loads; counts are 0"
```

`Load.f90` 中未包装的 `loadunit` 读取**恰好 33 处**，与该组计数吻合——即这 33 处被**整体**归入
"点荷载/边/梁板荷载，计数为 0"而未包装。

但 `:231` **不属于那一类**：它是幅值曲线的 `dfact` 记录，门控条件是 `type_curve` 不等于四个特殊
类型，与任何"计数为 0"无关。它被这一整组的理由**顺带扫了进去**。

`yl_io_inventory.py check` 仍然 PASS，因为它的 `not_on_path` 规则是**按 unit 粒度**
（工具第 249-254 行："every census unit must be either registered or explained"），
而 `loadunit` 被这一组解释了。**check 没有失职，它只是没有能力发现这件事**——
聚合到 unit + 计数 + 理由的分类，无法区分"这个站点被审视后判为路径外"与"它被一句概括捎带过去"。

## 后果

1. **M1-01**：`not_on_path` 分类对至少一处是错的。
2. **M1-02**：「152 个 reader 与 14 个 open 已包装 / 152」的**分母**不含这一处，
   因此「所选路径的读取全部包装」**未被证明**。已执行路径上存在一处裸读——
   `.loa` 的这条记录若畸形，得到的是 Fortran 原生错误或静默错位，而不是 M1 的分类诊断。
   这正是 M1-02 立项要消灭的那一类。
3. **gdb 实证**：211 位点的命中集有缺口，至少漏掉一处确实执行的读取。

## 严重性与边界

- **不影响既有数值结果**：两个 golden 算例的 deck 是良构的，该读取正常成功。
  求解器二进制、参考结果、状态基线均不受影响。
- **影响的是"输入可控失败"这一 M1 的核心主张**在该处不成立。
- **只发现了一处**。同类问题是否还有——本次没有系统排查，
  且现有工具**查不出来**（unit 粒度的分类无法逐站点核对）。这一点本身是最值得注意的。

## 建议（属 M1，不属 M4-01）

1. 把 `:231`（以及同分支的 `:224` SEISMIC 记录）从 `not_on_path` 的 33 项里摘出，
   补进 reader 清单并加 `diag_check_read` 包装。
2. **更重要**：把 `not_on_path` 从"unit + 计数 + 理由"改为**逐站点枚举**，
   使"这个站点被判为路径外"成为可核对的断言，而不是一句概括。
   否则同类漏判无法被发现——本次是靠 M4-01 的解析器作者偶然撞见的。
3. 在 M1-01/M1-02 的签收材料里如实记录本发现，**不要在修复前签字**。

## 附带说明

本发现是 M4-01 适配器契约「每一次读都必须可追溯到 reader 清单」那条要求的直接产物。
若没有它，解析器作者会按"清单里没有就不用读"跳过这条记录，
而那会让 `.loa` 其后的每一次读取错位——**一个静默的解析缺陷，恰好由一条文档纪律挡住了。**
