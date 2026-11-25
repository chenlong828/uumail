---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-25
---

# W-M3-20 日历页保留两栏：左侧邀请邮件列表

## 背景

用户反馈：切到日历后整窗结构变成一整块日历，「非常不和谐」，希望像收件箱/发件箱那样保留左侧列表、右侧内容的两栏结构。确认口径（2026-11-25）：

- 左侧列**会议邀请邮件**（发件人/主题/会议时间），一封会议邮件一行；重复会议只出现一次；
- 单击选中并高亮右侧日历块，双击打开浮窗；
- 两栏宽度沿用邮件页（列表 min 320 / ideal 480，日历取剩余）。

## 范围

- 改：`MailboxView`（同一个 `NavigationSplitView` 承载左列表/右详情，按 section 换内容）、新增 `CalendarMailListView`/`CalendarReader`、`CalendarView` 改用 `CalendarViewModel.selectedOccurrence` 共享选中、`CalendarViewModel` 新增 `invitationMails`、`CalendarMailItem`、`CalendarScene.message(ref)`。
- 不改：同步、存储 schema、target、依赖、EAS、Outbox、Sent 同步、月/周投影算法。
- 已知：来源邮件已删除/移走的会议，左侧行回退用会议主题/组织者/会议时间，保证列表完整；行尾时间统一显示会议时间（不是收件时间），因为它是日历页。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| `T-1125-01` | design | — | 完成 | 用户口径、`CalendarView`/`CalendarViewModel`/`CalendarScene`、日历截图 |
| `T-1125-02` | change | CMP-SCN-CALENDAR / CMP-PRES | 完成 | `CalendarScene.message`、`CalendarMailItem`、`invitationMails`、测试 |
| `T-1125-03` | change | CMP-APP | 完成 | `MailboxView` 共用 split、`CalendarMailListView`、`CalendarReader`、`CalendarView` 共享选中 |
| `T-1125-04` | verify | — | 完成 | 466 tests / 77 suites、架构 4/4、真实窗口截图、`make-app.sh` |
| `T-1125-05` | doc | — | 完成 | REQ-0040、SCN-0024 增量、组件规格、roadmap、README |

## 验收标准

1. 切到日历时，窗口仍是左列表 + 右日历，不再整窗变成日历。
2. 左列宽度与邮件页一致（min 320 / ideal 480）；日历取剩余宽度。
3. 左列按当前月/周显示会议邀请，一封邮件一行；重复会议只一行；来源邮件不在本机时回退会议元数据。
4. 单击左列/日历块选中同一会议并高亮；双击左列/块打开同一浮窗；Esc 取消选中。
5. 月/周切换、翻页、今天、ICS 导出、Sent/收件箱切换不退化。

## 未决

- 左列行尾显示会议时间而非收件时间（日历页更实用）；如果用户要“收件时间”，可再调整一行。
- 真实点击/双击/分隔条拖拽与深色主题像素验收仍为发布前人工项。
