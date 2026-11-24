---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-24
---

# W-M3-18 设计：四条界面反馈（P3）

## 1. 现状与根因

| # | 现象 | 根因（证据） | 落点 |
|---|---|---|---|
| 1 | 列表默认太窄 | `MailboxView` 列表列 `min:280/ideal:380`；1440 窗口实测列表 380（改造前口径） | `MailboxView` 列宽 |
| 2 | 其他文件夹空 | 不是界面 bug：`SyncEngine.runSync` 只取 `folders.first(where:\.isInbox)` 并只同步该 collection；本地库 `messages` 只有 folder `13`（收件箱）125 封，`sync_state` 只有 `folders` 与 `13` | 不改；登记开放问题 |
| 3 | 双击不打开 | 行上 `.onTapGesture(count:2)` 在 `List(selection:)` 内被列表点击消费，真实双击不触发；用户实测只有 Enter/空格（`onKeyPress`）有效 | `MessageRowClick` + AppKit `ClickCatcher` |
| 4 | 浮窗太偏 | `ReaderCoordinator.position` 固定 `setFrameTopLeftPoint(main.maxX-40, main.maxY-40)`，即主窗右上角；`setFrameAutosaveName("uumail.reader")` 还会恢复旧右上角 frame | `ReaderCoordinator` + `ReaderRouter.centeredOrigin` |
| 5 | 周视图无小时线 | 周视图每小时是一块 `Rectangle().fill(secondary.opacity(0.08))` 实心带，不是线；`CalendarProjection.week` 的 `startHour/endHour` 按会议最早/最晚伸缩（默认 8–18） | `CalendarHourGrid` + 固定 8–24 |

第 2 条只读证据（2026-11-24）：

```text
folders: 20 条，messages: folder 13 = 125，其余 19 个文件夹 = 0
sync_state: folders=1, 13=2003995747
```

## 2. 定级与组件

- **P3**：单模块 UI 局部；无 schema、无 target、无依赖、无热路径失败语义变更；`ReaderRouter.centeredOrigin` 是 additive public 纯函数（CMP-PRES 记一句）。
- 组件：
  - `CMP-APP`：`MailboxView`（列宽、行入口）、`MessageRowClick`（新）、`CalendarSelection`（ClickCatcher 延迟可配）、`CalendarView`/`CalendarBlocks`/`CalendarHourGrid`（新）、`ReaderCoordinator`（居中/记忆）。
  - `CMP-PRES`：`CalendarProjection.week`（固定 8/24）、`ReaderRouter.centeredOrigin`（纯函数）。
- 不受影响：`Scenes`、`Composition`、`MailDomain`、`MailStore`、`Package.swift`、同步与存储 schema。

## 3. 修改方案

### 3.1 列表列宽（REQ-0034）

`MailboxView.mailSplit` 的 content 列：`min 280/ideal 380` → `min 320/ideal 480`。侧栏保持 180/220，阅读区取剩余宽度；窗口变窄时先压阅读区，列表保持理想宽，低于 320 才收缩。L2 探针在 1440/1000/900/760 四档验证。

### 3.2 列表双击（REQ-0031 修复）

- 新增 `MessageRowClick`：把行包成整行 AppKit 点击目标，`ClickCatcher(singleClickDelay: 0)`。
- `ClickCatcherView` 增加实例级 `singleClickDelay`，默认 0.28 保持日历块「延迟选中避免闪」的行为；列表传 0，第一次点击立即选中。
- 单击：`messageSelection.wrappedValue = listKey`（走既有 `MailboxViewModel.select`，同步 `attachmentActions`） + `messageListFocused = true`。
- 双击：`openReader(message)`，与 Enter/空格同一条路径。
- 删除行上的 `.onTapGesture(count: 2)`。
- 点击选中不再触发 `.onChange(of: selectedListKey)` 的 `scrollTo(center)`：记录 `clickSelectionKey`，鼠标选中的行不自动居中，避免第一击后列表滚动、第二击落到别的行；刷新/定位等程序化选中仍居中。

### 3.3 浮窗默认居中（REQ-0035）

- `ReaderRouter.centeredOrigin(in:size:visible:)`：`container` 中心减半宽高，再夹到 `visible.min...visible.max-size`；尺寸大于屏幕时贴 `visible.min`。
- `ReaderCoordinator`：
  - autosave 名改为 `uumail.reader.centered`（一次性迁移，不恢复旧右上角 frame）；
  - 有保存 frame 且 `uumail.reader.userMoved == true` → `setFrameUsingName` 沿用位置与尺寸；
  - 否则按目标尺寸 + `centeredOrigin` 居中；
  - `windowDidMove` 且 `NSApp.currentEvent?.type == .leftMouseDragged` → 记 `userMoved = true`；程序化 `setFrameOrigin` 不记。
- 复用已有窗口时不移动（用户当前位置优先）。

### 3.4 周视图固定与虚线（REQ-0036）

- `CalendarProjection.week`：`startHour = 8`、`endHour = 24`，删除 `minMinute/maxMinute`。
- 新增 `CalendarHourGrid`：一个 `Path` 画 `8...24` 共 17 条水平线，`Color.gray.opacity(0.45)`、`lineWidth 1`、`dash [4,4]`；每列 ZStack 用它替代原来的实心 `Rectangle` 带。
- 坑：`Path.stroke(Color.secondary, …)` 在本机 SwiftUI 预览里完全不渲染；改用 `Color.gray.opacity(0.45)`，并把该坑写进 CMP-APP 增量。

## 4. 场景走查

- 正常：启动 → 列表默认 480；单击选中 → 双击打开浮窗；浮窗首次居中；切日历周视图 → 8–24 虚线。
- 失败：双击未命中行（点击空白）→ 不打开；浮窗主窗不可得（首启）→ 不居中但不阻塞；保存 frame 损坏 → `setFrameUsingName` 返回 false → 回默认尺寸 + 居中。
- 扩展：新增窗口尺寸档不影响列宽规则；新增会议时间不改变周视图高度。
- 回归：Enter/空格、删除、列表选中、日历单击选中/双击打开、浮窗尺寸记忆、就地撰写不变。

## 5. 测试

- L1：`ReaderViewModelTests` 新增 centeredOrigin 三组；`CalendarViewModelTests`/`CalendarScenarioTests` 期望 8/24；全量 461 tests / 77 suites。
- L2：
  - `probe/message-row-click.txt`：生产 `MessageRowClick` + `List(selection:)`，1→仅选中、1,2→选中+打开、2→仅打开、`window.sendEvent` hitTest 命中。
  - `probe/column-width.txt`：1440/1200/1000/900/760 三列宽度。
  - `probe/hour-grid.png`：生产 `CalendarHourGrid` 预览，17 条虚线可见。
- 架构 4 门；`make-app.sh` 收口。
- 未覆盖（发布前人工）：真实鼠标双击、拖动浮窗后重启沿用位置、深色主题下周视图像素验收。

## 6. 决策与备选

- 列宽：只调大默认值，不引入列宽持久化（用户明确选「只调大默认列宽」）。
- 双击：复用日历已有的 AppKit ClickCatcher，不新写事件处理；否决 `.simultaneousGesture`（同样是 SwiftUI 手势，根因未除）。
- 浮窗位置：居中为默认，但保留「用户拖动后记住」；否决「每次打开都居中」（会覆盖用户手动摆放）。
- 周视图：固定 8–24（用户明确选择），否决保留自适应；8 点前/24 点后的会议块会被时间窗裁掉，属已确认口径。
