---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-25
---

# W-M3-20 设计：日历页两栏

## 1. 现状

- `MailboxView` 在日历时用 `if section == .calendar { CalendarView }` 替换整个内容；邮件页是 `NavigationSplitView` 两栏。
- `CalendarView` 自己持有 `selectedKey` 私有状态，`CalendarViewModel.selectedOccurrence` 反而闲置。
- `CalendarScene.events` 只返回 `MeetingOccurrence`（主题/组织者/时间/来源 folder+serverID），没有来源邮件的发件人与收件时间。

## 2. 定级与组件

- **P3**（CMP-APP/CMP-PRES/CMP-SCN-CALENDAR 局部 UI/读面；无 schema、无依赖、无公开契约语义变化；`CalendarScene.message(ref)` 是 additive 读方法）。
- 组件：CMP-APP（共用 split、新列表、新 reader 入口、CalendarView 选中）、CMP-PRES（`CalendarMailItem`/`invitationMails`）、CMP-SCN-CALENDAR（按 ref 取源邮件）。

## 3. 修改方案

### 3.1 共用两栏

`MailboxView` 的 `mailSplit` 改为一个始终存在的 `NavigationSplitView`：

- 左列 `Group`：日历 section → `CalendarMailListView(model:)`；邮件 → 原 `mailListColumn`；`.navigationSplitViewColumnWidth(min: 320, ideal: 480)` 放在 Group 上。
- 右详情：日历 → `CalendarView(model:)`；邮件 → 原 `mailReadingPane`。
- 顶部三段 Picker、窗口 toolbar、`ReaderCoordinator.attach` 保持在根视图；邮件工具栏/搜索/撰写 sheet 只在 `mailListColumn` 内。

### 3.2 左列内容

- `CalendarScene.message(ref)`：按 source folder + serverID 从本地 `messages` 表取 `Message?`（additive，只读）。
- `CalendarViewModel.invitationMails`: 由当前 occurrences 按 `(folderID, serverID)` 去重，每个来源一封；`try? scene.message(ref)` 取到则带 envelope，取不到则 `message == nil`。
- `CalendarMailItem`：`message: Message?`、`occurrence`；`title` 取邮件主题/会议主题，`senderText` 取发件人/组织者/「来源邮件不在本机」；`id` 用 folder + serverID。
- 排序按会议开始时间**倒序**（最新在前）；行尾显示会议时间（`MM-dd HH:mm`，全天显示「MM-dd 全天」）；重复会议只显示范围里第一次。
- 左列 `CalendarMailListView`：`List` + `listRowBackground` 选中高亮；行 overlay 复用 `MessageRowClick`（单击选中、双击打开）；底部状态显示「N 封会议邀请」与日历错误。

### 3.3 共享选中与打开

- `CalendarView` 删除私有 `selectedKey`，改用 `model.selectedOccurrence`；单击块 → `model.select`，Esc → `model.clearSelection()`，Enter/空格 → `openSelectedOccurrence()`。
- 新 `CalendarReader.open(occurrence, model, onExportFailure)`：列表与块共用同一条 `ReaderCoordinator.show(style: .calendar)` 路径（工具栏转发 + 在日历中打开）。
- 列表单击 → `model.select(item.occurrence)` → `CalendarView` 的块高亮；块单击 → 模型选中 → 列表按 `selectedID` 高亮并滚动。双击没有来源邮件的块 → `model.hasSourceMail(for:)` 为 false，只选中并弹「来源邮件不在本机」，不打开空阅读窗。
- 列表双击 → `CalendarReader.open`。

## 4. 场景走查

- 正常：切日历 → 左列加载邀请，右日历渲染；点左侧行 → 块高亮；双击左侧行 → 浮窗；点块 → 左侧行高亮。
- 空：没有会议 → 两侧空态；来源邮件缺失 → 行仍显示会议元数据，不报错。
- 失败：日历读失败 → 右日历保留旧投影 + banner，左列保留旧列表并显示错误；来源邮件缺失只影响 envelope 字段。
- 回归：月/周切换、翻页、今天、ICS、浮动阅读窗、Sent/收件箱切换不退化。

## 5. 测试

- L1：`CalendarGridScenarioTests.invitationList`（重复系列只一行、主题/发件人/首个 occurrence）；全量 466 tests / 77 suites。
- L2/人工：真实窗口截图 `task-spaces/20261125-120000-calendar-list/calendar-list.png`（左列 44 封邀请 + 右月视图、同一窗框）；真实点击/双击/分隔条/深色像素为发布前人工项。
- 架构 4/4、`make-app.sh`。

## 6. 决策

- 用同一 `NavigationSplitView` 而不是在 `CalendarView` 内部再套 split：保证左列位置/宽度/滚动与邮件页一致，窗口结构真正不变。
- 列表用来源邮件 envelope，但来源缺失时回退会议元数据：避免「日历有 44 场、左列只有 4 封」的残缺。
- 行尾显示会议时间而不是收件时间：日历页的主要问题是「什么时候开会」；收件时间可由邮件正文/浮窗查看。
- 选中状态放回 `CalendarViewModel.selectedOccurrence`：列表与日历共享一个权威选中，不再各持一份。
