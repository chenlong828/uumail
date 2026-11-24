---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-24
---

# W-M3-18 用户反馈四条界面修复（列表列宽 / 双击 / 浮窗位置 / 周视图刻度）

## 背景

用户在 2026-11-24 提出 5 条反馈：

1. 邮件列表默认太窄，每次要手动拉宽；
2. 左侧抽屉里除收件箱外其他目录没有邮件；
3. 列表只有 Enter 能打开阅读浮窗，双击无效；
4. 日历页弹出的阅读浮窗位置太偏，应在基础窗体居中；
5. 周视图时间轴固定 8:00–24:00，每小时要有虚线横线。

第 2 条经排查**不是界面 bug**：`SyncEngine` 只同步收件箱（`sync_state` 只有 `folders` 与 `13` 两条记录，`messages` 表只有 folder `13` 的 125 封）。本次只回答原因并把「选中文件夹按需同步」登记为开放问题，不改同步范围。其余 4 条按 P3 修复。

## 范围

- 改：`Sources/uumail/MailboxView.swift`（列宽、行双击入口）、`MessageRowClick.swift`（新）、`CalendarSelection.swift`（ClickCatcher 延迟参数）、`ReaderCoordinator.swift`（居中与位置记忆）、`CalendarView.swift`/`CalendarHourGrid.swift`/`CalendarBlocks.swift`（虚线网格）、`Sources/Presentation/CalendarProjection.swift`（固定 8–24）、`Sources/Presentation/ReaderRouter.swift`（居中纯函数）。
- 不改：同步、存储、schema、target、依赖、公开读面；`Package.swift` 零改动。
- 文档：REQ-0034/0035/0036、REQ-0031 修复记录、SCN-0027 新建、SCN-0025/SCN-0024 增量、CMP-APP/CMP-PRES 增量、roadmap、open-questions。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| `T-1124-22` | design | — | 完成 | 用户 5 条反馈、现状代码、数据库实测、本地库 schema |
| `T-1124-23` | change | CMP-APP | 完成 | `MailboxView`/`MessageRowClick`/`CalendarSelection`/`CalendarView`/`CalendarHourGrid` + L2 探针 |
| `T-1124-24` | change | CMP-PRES | 完成 | `ReaderRouter`/`CalendarProjection` + `PresentationTests` |
| `T-1124-25` | change | CMP-APP | 完成 | `ReaderCoordinator` + 居中/autosave 迁移 |
| `T-1124-26` | verify | — | 完成 | L1 全量 + L2 探针 + 架构 4 门 + `make-app.sh` |
| `T-1124-27` | doc | — | 完成 | REQ/SCN/CMP/roadmap/open-questions 收口 |

## 装载清单（≤250k）

- `Sources/uumail/MailboxView.swift`、`MessageRowView.swift`、`MailboxView+Reader.swift`
- `Sources/uumail/CalendarSelection.swift`、`CalendarView.swift`、`CalendarBlocks.swift`、`CalendarHourGrid.swift`
- `Sources/uumail/ReaderCoordinator.swift`、`Sources/Presentation/ReaderRouter.swift`
- `Sources/Presentation/CalendarProjection.swift`、`CalendarViewModel.swift`
- `Tests/PresentationTests/ReaderViewModelTests.swift`、`CalendarViewModelTests.swift`、`CalendarScenarioTests.swift`
- `doc/design/components/CMP-APP/spec.md` §浮动阅读窗、`CMP-PRES/spec.md` §浮窗路由
- 本地库只读实测：`~/Library/Application Support/uumail/mail.sqlite`

## 验收标准

1. 1440 窗口下邮件列表列宽 480（原 380），900 窗口（应用最小宽）下仍 480 且不低于 320；侧栏 220。
2. 列表行单击只选中；双击（真实 `clickCount=1` 后 `2`）选中并打开浮窗；纯双击也打开；非选中行同样可打开。
3. 浮窗首次打开相对主窗口居中并夹在屏幕可用区；用户拖动后记住位置，未拖动则每次启动重新居中。
4. 周视图始终 08:00–24:00，每小时一条虚线；会议块按分钟定位不退化。
5. `./Scripts/swiftw test` 全绿、`bash Scripts/check-architecture.sh` 4/4、`./Scripts/make-app.sh` 成功。

## 未决

- 「其他文件夹没有邮件」的按需同步未做；口径与代价登记在 `plan/open-questions.md`。
- 真实鼠标双击、拖动浮窗后重启沿用位置、周视图像素级视觉验收仍需发布前人工冒烟。
