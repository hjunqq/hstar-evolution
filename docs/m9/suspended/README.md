# M9 单元域：暂停期存放

本目录存放**已完成但当前无法被证据支持**的东西。它不是废弃物，是可恢复的工作。

| 文件 | 是什么 | 恢复条件 |
|---|---|---|
| `section-area-and-element-whitelist.patch` | 截面面积全链路 + 单元族白名单 + `bcs` 输出，从工作树上原样摘下 | `CONCRETE` 与 `PARDISO` 解除后，rcbeam 可由现代输入驱动 |
| `evidence/rcbeam/` | `elements_2d.rcbeam` 的 gdb 取证（228 个站点，1991 次命中，仪器化惰性已验证） | 同上；届时移回 `docs/m1/evidence/` |

## 为什么取证不放在 `docs/m1/evidence/`

`tools/yl_io_inventory.py check` 会遍历该目录下的每一份证据，并要求其中
**每一个被执行的站点都已注册**。rcbeam 触及 16 个未注册站点，分属四个未迁移的域
（PARDISO 求解器输入、材料属性曲线与 CONCRETE、`.nrt` 插值组、`bcs` 输出）。
注册它们等于同时开启那四个域；把证据留在这里，门禁保持诚实的红/绿，
而证据本身一次也没丢。

## 为什么补丁不直接合进主干

`tools/yl_state_map.py` 有一条规则：任何 map 字段的来源 reader 必须被某个**被接纳的算例**
执行过，否则 `reader ... has empty executed_by`。这正是「没有真实 deck 就不能声称一个字段」
的机制表达。补丁里的 `sections[].cross_section_area` 现在没有这样的算例，所以它不该在主干上。

规则没有被绕过，也没有被放宽。
