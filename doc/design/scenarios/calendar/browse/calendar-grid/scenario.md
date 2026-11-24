---
layer: design
module: calendar
status: verified
updated: 2026-11-24
flow: calendar/browse
scenario: SCN-0024
---

# SCN-0024 日历页月/周视图

**结果**：用户打开侧栏「日历」，在**月视图**里按天看到本月已收到邀请的会议分布，在**周视图**里按固定 08:00–24:00 的时间轴看到本周会议的起止位置（每小时一条灰色虚线）；上/下翻周期与「今天」都在本地完成、零网络；单击一个会议块把它**选中高亮**（不再弹 360×240 详情），双击 / Enter / 空格弹出**浮动阅读窗**显示这场的来源邀请邮件（信封头、只读会议卡、正文，图片默认显示）；浮窗工具栏是「转发」与「在日历中打开」。重复会议在可见范围内按规则展开；同一会议的多封更新只出现一次；已取消的邀请不出现。

## 入口

- `CMP-SCN-CALENDAR#events(from:to:limit:)`（场景编排：范围查询 → 取消过滤 → 重复展开）
- `CMP-STORE#meetings(account:from:to:limit:)`（`mail/meetings` 表范围查询）
- `CMP-DOMAIN#MeetingInvite.occurrences(in:limit:)`（重复展开纯函数）
- `CMP-PRES#CalendarViewModel`（模式、锚点日期、网格投影、选中态）
- `CMP-APP#CalendarView`（月网格 / 周时间轴 / 工具栏 / 选中态；**事件详情 sheet 已移除**，改由浮窗承接）
- `CMP-APP#CalendarHourGrid`（周视图小时网格：固定 08:00–24:00，每列 17 条灰色虚线）
- `CMP-APP#MonthChipClickCatcher` / `#WeekBlockClickCatcher`（AppKit 点击捕获：clickCount 1 = 选中、2 = 打开，见 `probe/click-catcher.txt`）
- `CMP-PRES#ReaderRouter`（浮窗单例路由；日历入口工具栏 = 转发 / 在日历中打开）

## 运行序

流程 `F-CALENDAR-01`：

1. 用户点侧栏「日历」→ `CalendarViewModel.activate()`：`mode = .month`、`anchor = 今天`，向 `CalendarScene` 要一次可见范围的事件。
2. 可见范围：月视图 = 覆盖当月首末日的完整周网格（5–6 行，周一为每周第一天）；周视图 = 当前周 7 天。
3. `CalendarScene.events` → `MailStore.meetings(account:from:to:limit:)`：取 `start_utc <= to` 且（`end_utc >= from` 或 `recurrence IS NOT NULL`）的行；跳过 `is_cancelled = 1` 与 `meeting_message_type = 4` 的行。
4. 每条会议 → `MeetingInvite.occurrences(in: 可见范围, limit:)`：非重复会议只产出自身一次；重复会议按 `RecurrenceRule` 从系列起点逐次推进，直到超出范围/`UNTIL`/`OCCURRENCES`/单系列上限。
5. 汇总为 `[MeetingOccurrence]`，按开始时间排序；总量超过 `limit`（默认 500）时截断并置 `truncated = true`。
6. `CalendarViewModel` 把事件投影成 `MonthGridPresentation`（`weeks[][day]`，每格最多 3 个事件 + 「+N」）或 `WeekGridPresentation`（7 列 × 固定 08:00–24:00 时间轴，每小时一条灰色虚线，事件块按起止比例定位，重叠事件并排）。
7. 渲染；切换月/周、上/下翻、今天：只改 `anchor`/`mode` 并重算投影，**不触网**。
8. 单击事件块 → 置为选中（高亮），**不弹任何 sheet**；双击 / Enter / 空格 → 把该会议的 `(folderID, serverID)` 交 `ReaderRouter` 打开浮窗（`SCN-0025` 同一窗口、同一尺寸口径，工具栏为「转发」「在日历中打开」）。浮窗内会议卡只读，不渲染按钮；「在日历中打开」走 `CMP-SCN-CALENDAR#ics(for:)`，与 `SCN-0023` 的导出一致。打开浮窗**不改侧栏选中**、不切回邮件页。

失败路径：

- `MailStore` 读失败 → `CalendarViewModel.errorText` 中文文案 + 空态；保留上一次成功投影，不清空。
- 会议 `UID` 相同但 `DtStamp` 乱序到达 → 以库中最接近的一条为准（写入端已按 `DtStamp` 取最新，本层不再判）。
- `Recurrence` 无法解析或展开超上限 → 该系列只展示已知的第一次，并在事件详情标注「重复规则无法完整展开」；不阻塞其它事件。
- 时区偏移缺失或畸形 → 按 `+00:00` 处理并在事件详情标注「时区未知」，不崩、不改写存储。
- 无可见会议 → 空态：「本期没有收到会议邀请」，并提示「日历只展示升级后新收到的邀请」（不回填历史，见 `REQ-0029` 约束）。

## 2026-11-24 增量（`REQ-0032`）：去掉详情、选中与双击打开

本增量**替换**上面「点事件块 → 事件详情 → 打开邮件跳回邮件页」的旧口径，原因与取舍见
`doc/history/decisions/2026-11-24-floating-reader-window.md`（D10/D11）。

- 单击：0.28s 判定窗口后进入选中态（决策 D5，避免双击前闪一下选中）；月/周同一时刻只有一个选中；Esc 取消选中。旧详情 sheet 删除。双击会取消待生效的选中并直接打开。
- 双击 / Enter / 空格：等价打开浮窗。双击第一下按系统语义先产生 `clickCount=1`（选中）、第二下 `clickCount=2`（打开），
  即「选中后打开」；探针 `task-spaces/20261124-152611/probe/click-catcher.txt` 证实该映射（1→仅选中、1,2→选中+打开、2→仅打开）。
- 浮窗：复用 `SCN-0025` 的单例窗口与尺寸/记忆；日历入口工具栏 = 转发 + 在日历中打开；无回复/全部回复。
- 来源邮件不在当前列表页：按 `(folderID, serverID)` 走 `CMP-SCN-READ#message(_:)`；取不到给「找不到这封邀请邮件」，
  工具栏「在日历中打开」仍可用（只依赖会议行）。
- 远程图片：日历入口浮窗同样默认显示 + 顶部静态提示（口径同 `SCN-0025`）。
- 旧「打开邮件」按钮与详情里的导出按钮**删除**；导出只在浮窗工具栏，避免同一动作两个入口。

## 2026-11-24 增量（`REQ-0036`）：固定 08:00–24:00 与小时虚线

本增量**替换**周视图「按本周会议最早/最晚时刻自适应时间轴」的旧口径（默认 8–18 会随会议伸缩）。决策见 `REQ-0036`。

- 固定范围：`CalendarProjection.week` 取 `startHour = 8`、`endHour = 24`，时间轴恒为 16 小时；只有一场 09:30–12:00 的会议时，
  08:00–09:30 仍留白，会议块落在真实位置，不再贴顶。周视图总高恒定，翻周不跳动。
- 小时线：新增 `CalendarHourGrid`，每列画 **17 条**灰色虚线边界（08:00…24:00 含两端；24:00 贴底边不溢出），
  替代原来每小时一块实心灰带；线只作参考，不填充背景。
- 会议块：定位与重叠 lane 算法不变，仍按起止分钟相对 08:00 计算；本次只改时间窗与网格线。
- 边界口径：08:00 前开始或 24:00 后结束的会议不进入周视图时间轴（已确认），月视图仍按天展示；不因该会议拉伸网格。

## 不可变引用

- `SCN-0003`：收件箱增量同步的批次与 `SyncKey` 同事务、`sync_key` 重建语义；本卡只消费其产出，不改同步。
- `SCN-0004`：阅读路径缓存优先、`ReadScene.open` 零网络；日历页与阅读页共享同一条「UI 读本地库」不变量。
- `MailStore` 唯一写入口：日历页只读 `meetings`，不写；写仍只发生在 `applySyncBatch`。
- `MailboxView` 现有三栏邮件结构与工具栏语义；本卡只在侧栏增加一个入口与一处分栏切换，不改邮件列表的单击/选中语义。
- `SCN-0025`：浮动阅读窗本体（单例、尺寸/记忆、工具栏、远程图片默认显示、就地撰写）；本卡只消费其窗口，不重复认领那些断言。
- `SCN-0023`：`.ics` 序列化与系统日历导入；本卡只把入口从详情移到浮窗工具栏，导出行为不变。
- 不新增第三方依赖、不新增 target、不改 `Package.swift`。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0024-01` | 正 | 库里 2026-11 有 2 封邀请（11-19 09:30–12:00、11-23 16:00–17:00）→ 月视图 11 月网格：19 日格 1 个事件、23 日格 1 个事件，其余天空；标题行是「周一…周日」。**已通过**（`T-SCN-0024-01`，L1） |
| `T-SCN-0024-02` | 正 | 周视图（11-16 那周，固定 08:00–24:00 网格）→ 19 日列出现一块，纵向位置与 09:30 对齐、高度覆盖到 12:00；同一起止时间在月视图的「+N」计数一致。**已通过**（`T-SCN-0024-02`，L1 投影几何：`startMinute=570`/`endMinute=720`/两条 lane） |
| `T-SCN-0024-03` | 正 | 每周一次的邀请（周一 16:00，无限期）→ 取 4 周范围展开 4 次，每次都是周一 16:00；跨月边界后仍连续；单系列上限与总量上限都不触发截断。**已通过**（`T-SCN-0024-03`，2026-11 五次周一） |
| `T-SCN-0024-04` | 反 | 同一 `UID` 先收到 11-23 16:00、后收到 11-16 的更新（`DtStamp` 更早）→ 只出现一条且时间取 `DtStamp` 最新那条；再收到 `MeetingMessageType=4`/取消 → 该会议从月/周视图消失，其它会议不受影响；超过上限时截断标记为真且渲染不崩。**已通过**（`T-SCN-0024-04`，含 `limit: 3` 截断） |
| `T-SCN-0024-05` | 正 | 单击月/周事件块 → 该块选中高亮，且**没有** sheet 出现；再单击另一块 → 选中转移；Esc → 取消选中（L2 视图探针：选中态与 sheet 计数） |
| `T-SCN-0024-06` | 正 | 双击月视图事件块 → 浮窗出现且标题/正文 = 该会议的来源邮件；主窗口侧栏仍选中「日历」；周视图同一断言；Enter 与空格对选中块等价（L2，窗口用 `ReaderWindowController` 探针替身） |
| `T-SCN-0024-07` | 正 | 浮窗工具栏恰为「转发」「在日历中打开」；点「转发」→ 就地进撰写（收件人为空、主题为转发前缀）；点「在日历中打开」→ 生成 `.ics` 文本并调用 opener 1 次（L1 `ics` + L2 按钮接线） |
| `T-SCN-0024-08` | 反 | 来源邮件已被删除（`message(ref)` 返回 nil）→ 窗内「找不到这封邀请邮件」，工具栏导出仍可用；`ReaderRouter` 处于撰写态时双击另一会议 → 内容不变 + 提示（复用 `SCN-0025` 规则）（L1 + L2） |
| `T-SCN-0024-09` | 正 | 固定范围 + 虚线：库里只有一场 09:30–12:00 的会议 → `CalendarProjection.week` 的 `startHour == 8`、`endHour == 24`（L1 `CalendarViewModelTests` / `CalendarScenarioTests`）；周视图渲染 16 小时网格、每列 17 条灰色虚线（含 08:00 与 24:00 两条边界），会议块仍在 09:30–12:00 位置且 lane 不变；预览截图 `task-spaces/20261124-233500-feedback5/probe/hour-grid.png`（生产 `CalendarHourGrid` 预览，17 条虚线可见），预览源 `HourGridPreview.swift`，命令 `./hour-grid-preview`。像素级全量视觉在发布前人工项 |

## 状态

`verified`（2026-11-24 实现并验证；本次 `REQ-0032` 增量：去掉事件详情、新增选中与双击/键盘打开、工具栏替换；同日 `REQ-0036` 增量：固定 08:00–24:00 与小时虚线）。

- 增量实现：`CalendarView` 去详情 sheet；单击经 `ClickCatcher` 选中（高亮描边）、双击/Enter/空格打开浮窗；
  浮窗工具栏 = 转发 + 在日历中打开（导出复用 `CalendarExport`）；月/周块视图抽到 `CalendarBlocks.swift`。
- 增量证据（L2）：`task-spaces/20261124-152611/evidence/calendar-click/calendar-click.txt`——生产 `CalendarSelection.swift`
  的点击捕获被 `hitTest` 命中；`clickCount=1` 立即不选中、延迟 0.28s 后选中 1 次；`1,2` 取消选中并只打开 1 次。
- 未覆盖（发布前人工项）：双击后浮窗真实出现（需真实点击与窗口），选中描边的像素验收，Esc 实测。

- 2026-11-24 增量（`REQ-0036`）：周视图固定 `startHour = 8` / `endHour = 24`，删除按会议最早/最晚伸缩；
  小时边界改 `CalendarHourGrid` 的灰色虚线（每列 17 条，`8...24` 含两端），替代实心灰带。
- 增量证据（L1）：`Tests/PresentationTests/CalendarViewModelTests.swift`（`startHour == 8`、`endHour == 24`）与
  `CalendarScenarioTests.swift`（只有 9:30 会议时仍为 8/24）；全量 461 tests / 77 suites、架构 4/4。
- 增量证据（L2/预览）：`task-spaces/20261124-233500-feedback5/probe/hour-grid.png`——生产 `CalendarHourGrid` 预览，
  17 条虚线可见；预览源 `HourGridPreview.swift`，命令 `./hour-grid-preview`（6 秒后自动退出）。
- 增量未覆盖（发布前人工项）：深色主题/不同字号下的虚线可见性、整页滚动与像素级视觉验收。

- 实现：`T-1124-03`…`T-1124-12`（WAL、outbox 拆分、EAS 解析、领域值、映射、v12 存储、场景、PRES、APP、ROOT）。
- 证据（L1，组件级）：`Tests/PresentationTests/CalendarScenarioTests.swift` 的 `T-SCN-0024-01..04`，
  配合 `CalendarProjectionTests`/`CalendarViewModelTests`/`CalendarSceneTests`/`MeetingStoreTests`/
  `MeetingRecurrenceTests`/`MeetingICSTests`。全量 437 tests / 71 suites 绿，架构 4 门过（当时发布构建已完成）。
- 跳回邮件：`MailboxViewModel.reveal(folderID:serverID:)` + 列表滚动，`MailboxRevealTests` 3 例；见 `history/pitfalls.md` P1。
- L2 说明：月/周网格的像素与帧位置未做无头探针（`plan/risks.md` R59）；网格算法与文案在 L1 断言，
  视觉冒烟登记为发布前人工项，与 A5 同类。

- 入口符号在实现前可能 miss，属 `designed` 允许项；实现任务 `T-1124-09`（`CMP-SCN-CALENDAR`）转 `active` 后回填。
- 测试归属：`T-SCN-0024-01/03/04` 走 L1（`CalendarSceneTests` + `MailStoreTests` + `MailDomainTests` 的展开用例）；`T-SCN-0024-02` 需 L2 视图探针（月/周网格文本与几何），探针先行，失败则按 `plan/risks.md` R41 处理，不用 L1 投影冒充 L2。
