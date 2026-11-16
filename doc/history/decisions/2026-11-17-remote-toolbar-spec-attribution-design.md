---
layer: history
module: mail
status: frozen
updated: 2026-11-17
---

# W-M3-06 两段组件规格设计增量的归属追认（设计节点落盘，2026-11-17）

## 背景

`REQ-0018`（远程图片开关并入工具栏）、`REQ-0019`（手动标记已读）与 `REQ-0013`（连续停留 3 秒）的设计由 2026-11-16 设计节点（run `20261116-223645`）完成，设计增量写入 `CMP-PRES`/`CMP-APP`，契约与取舍见该 run 的 `design.md` §5.1–§5.5、§8.2 与 §11。设计节点在 `design.md` §11 第 5 条明确「本节点未 commit」；设计批次 `62499e5` 的提交范围不含 `CMP-PRES/spec.md`/`CMP-APP/spec.md`，两段已写好的设计正文随后由实现 commit `edd90ce`（`T-1116-12`）与 `7b722e8`（`T-1116-13`）一并带入版本库。

2026-11-17 的代码评审（`task-spaces/20261117-060443/review.md` §4 B1）判定：`T-1116-12`/`T-1116-13` 的出口「`CMP-PRES`/`CMP-APP` 增量只追加实现进度行」未满足，要求补一条设计节点的 `frozen` 归属追认记录。本记录按该修复方向（additive，不改写历史）由**设计节点**落盘，只追溯归属，不重写设计内容，也不改写历史 commit。

## 落盘主体与替代关系

- 本记录由 2026-11-17 的运行代录（承接 run `20261116-223645` 的设计产物与结论），**不声称由设计节点手签**；设计正文的归属与实现 commit 的落地授权以 `2026-11-17-wm306-implementation-landing-authorization.md` 为准。
- 2026-11-17 的开发运行曾在 `5f9ec82` 提交一份同名追认记录，正文自述「由运行代录」「不伪造设计节点或任务发起人签字」。该记录不是设计节点落盘，且落在 `T-1116-12`/`T-1116-13` 允许范围之外（`roadmap.md:234-235`）。本 commit 撤回该记录并以本记录替代；`5f9ec82` 保留在历史中，不重写、不 amend、不 reset。
- 本记录只追认设计正文的归属，不新增、不收窄、不改选任何设计决定；D1–D8 的人工确认仍以 `doc/history/decisions/2026-11-16-remote-toolbar-mark-read.md` 为准。

## 追认事实

| 项 | 事实 |
|---|---|
| 设计来源 | 设计节点 run `20261116-223645`：`design.md` §5.1（`MailboxViewModel` 6 个 public 成员与不变量）、§5.2（`performMarkRead`/错误归一）、§5.3（`MailboxDwell`）、§5.4（`MailboxToolbar`）、§5.5（`MessageBodyView`）、§8.2（D1–D8）、§11 |
| 设计正文位置 | `CMP-PRES/spec.md:306-342`（「## 设计增量：远程图片放行与手动置读」，37 行）；`CMP-APP/spec.md:129-175`（「## 设计增量：工具栏归位、远程图片放行与手动置读」，47 行） |
| 实际入库 | `edd90ce`（`T-1116-12`）与 `7b722e8`（`T-1116-13`）；`git show --stat 62499e5` 不含这两份 spec |
| 原因 | 设计节点未 commit，设计批次的提交范围遗漏这两份文件；实现 commit 按工作树现状把已写好的设计正文一并提交，不是实现节点另写了一份设计 |
| 进度行 | `CMP-PRES/spec.md:343`、`CMP-APP/spec.md:176` 的「实现（2026-11-16，T-1116-12/13）」才是实现进度行 |
| 复核结论 | 设计节点按 `design.md` §5.1–§5.5、§8.2 的 D1–D8 与 `history/decisions/2026-11-16-remote-toolbar-mark-read.md` 逐段核对：两段正文与设计节点的契约、不变量、取舍和测试计划一致；未发现收窄或改选（D1–D8 均按唯一建议答案）；没有 `design.md` 之外的新契约、新组件、新依赖或新 schema |
| 与设计评审的关系 | 设计评审 `task-spaces/20261116-223645/review.md` 的通过结论（`split.md:25` 记 `pass`，N1–N9 非阻塞）覆盖了这两段设计增量；本记录只补「设计节点落盘/归属」这一形式缺口，不重开设计结论 |

## 归属结论

1. `CMP-PRES/spec.md:306-342` 与 `CMP-APP/spec.md:129-175` 是**设计产物正文（设计增量）**，不是 `T-1116-12`/`T-1116-13` 的实现进度行。
2. 这两段在 `edd90ce`/`7b722e8` 中的出现读作「**设计正文代录 + 末尾一条实现进度行**」。本记录是设计节点对该读法的追认；不据此认定实现任务有权写设计正文，也不把这两笔实现 commit 回溯改写成设计 commit。
3. 自本记录起，`T-1116-12`/`T-1116-13` 及后续实现 commit 对上述两份 spec 只追加实现进度行；若需改契约/形状/测试断言，回设计节点，不在任务里自行扩。
4. 本记录不改变两段正文的内容，不改变 P2 确认（D1–D8，`history/decisions/2026-11-16-remote-toolbar-mark-read.md`，`frozen`）的效力，不翻转任何 `verified`/`delivered`/任务状态。

## 边界与回退

- 本 commit 只动 `doc/history/decisions/`：新增本记录、撤回 `5f9ec82` 的开发代录件；不改 `Sources/`/`Tests/`/`Package.swift`/`Scripts/`，不改两段规格正文，不改场景卡/需求卡/roadmap 门状态。
- 不改写历史：`62499e5`/`edd90ce`/`7b722e8`/`5f9ec82` 的哈希保持不变；拆分 commit 属破坏性历史重写，未获授权，不做。
- 回退方式：删除本记录并恢复被撤回的记录即可；纯文档、可逆，无数据/schema 残留。
- 本记录不代替代码、测试、L2 证据或最终状态翻转；这些仍按 `doc/plan/roadmap.md` §W-M3-06 的 `T-1116-12`…`T-1116-16` 执行。

## 落点

- 规格：`doc/design/components/CMP-PRES/spec.md`（`:306-342` 设计正文、`:343` 实现进度行）、`doc/design/components/CMP-APP/spec.md`（`:129-175` 设计正文、`:176` 实现进度行）。
- 设计依据：`task-spaces/20261116-223645/design.md` §5.1–§5.5、§8.2、§11；`task-spaces/20261116-223645/split.md:25`（设计评审 `pass`）。
- 人工确认：`doc/history/decisions/2026-11-16-remote-toolbar-mark-read.md`（`frozen`，D1–D8；记录由 run `20261117-060443` 按发起人指令代录）。
- 评审依据：`task-spaces/20261117-060443/review.md` §4 B1、§9；本记录由设计节点在回退重跑中落盘，单独 commit。
