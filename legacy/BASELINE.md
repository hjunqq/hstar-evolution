# YL 基线来源

本目录从以下已提交版本导入，而不是从带本地修改的工作树复制：

```text
source repository: /home/huijun/HSTAR_Next/hstarYLOrig
source commit:     5414e737484edf2f53efbfd2bafd3702ebbbb88a
commit date:       2026-02-09T22:55:22+08:00
commit subject:    Phase 1
source tree:       HSTAR/
```

`legacy/yl` 是回归参考与渐进迁移起点。禁止无目标格式化、重命名或大规模整理。每项修改必须
关联到 `docs/02-migration-plan.md` 的具体阶段，并由状态或数值测试保护。

原基线包含 Windows/Intel Fortran 工程及预编译库。M0 将新增独立的可重复构建描述，但不会
删除这些参考文件。

