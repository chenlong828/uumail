---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-25
---

# W-M3-20 结果：日历页两栏与邀请列表

## 结论

切到「日历」不再整窗变成日历：窗口保持与收件箱/发件箱相同的两栏结构，左列是当前月/周的会议邀请邮件，右侧是月/周网格。左列与日历块共享选中；单击选中/高亮，双击打开浮窗。

## 验收

| 项 | 结果 | 证据 |
|---|---|---|
| 两栏结构 | 左列 480（min 320）+ 右日历；同一 `NavigationSplitView` | 真实窗口截图 `calendar-list.png` |
| 邀请列表可打开 | 只列仍有来源邮件的邀请；缺失来源的会议只在日历显示，底部计数；按会议时间倒序 | 截图；`CalendarGridScenarioTests.invitationList` |
| 来源缺失处理 | 不进入左列，只在右侧日历；双击块给「来源邮件不在本机」提示，不再弹「找不到这封邮件」空阅读窗 | 实现走查 + 截图底部计数 |
| 选中共享 | 左列/块共用 `CalendarViewModel.selectedOccurrence`；单击高亮、双击浮窗 | L1 模型选中 + 真实窗口（点击为人工项） |
| 测试/架构/发布 | 466 tests / 77 suites、架构 4/4、`make-app.sh` 成功 | `dist/build-info.txt` |
| 行预算 | `MailboxView` 296、`CalendarView` 297、`CalendarMailListView` 114、`CalendarReader` 32、`CalendarViewModel` 214 | `wc -l` |

## 残余（发布前人工项）

- 真实鼠标单击/双击左列与日历块、分隔条拖拽、深色主题整窗像素验收。
- 左列行尾显示会议时间而非收件时间（日历页语义，已在设计记录）；若用户要收件时间可再调整一行。
- 来源邮件缺失的行显示会议元数据（组织者/「来源邮件不在本机」）；不补历史已删邮件。

## 结论落点

- 需求：`REQ-0040`（日历页两栏与邀请列表）`delivered`。
- 场景：`SCN-0024` 增量重验（`T-SCN-0024-10/11`）。
- 组件：`CMP-APP`/`CMP-PRES`/`CMP-SCN-CALENDAR` 增量。
- 计划：`plan/roadmap.md` W-M3-20。
