---
layer: design
module: calendar
status: verified
updated: 2026-11-24
flow: calendar/browse
scenario: SCN-0024
---

# SCN-0024 日历页月/周视图

**结果**：用户打开侧栏「日历」，在**月视图**里按天看到本月已收到邀请的会议分布，在**周视图**里按时间轴看到本周会议的起止位置；上/下翻周期与「今天」都在本地完成、零网络；点一个会议块能看到主题/时间/地点/组织者，并跳回来源邮件。重复会议在可见范围内按规则展开；同一会议的多封更新只出现一次；已取消的邀请不出现。

## 入口

- `CMP-SCN-CALENDAR#events(from:to:limit:)`（场景编排：范围查询 → 取消过滤 → 重复展开）
- `CMP-STORE#meetings(account:from:to:limit:)`（`mail/meetings` 表范围查询）
- `CMP-DOMAIN#MeetingInvite.occurrences(in:limit:)`（重复展开纯函数）
- `CMP-PRES#CalendarViewModel`（模式、锚点日期、网格投影、选中态）
- `CMP-APP#CalendarView`（月网格 / 周时间轴 / 工具栏 / 事件详情）

## 运行序

流程 `F-CALENDAR-01`：

1. 用户点侧栏「日历」→ `CalendarViewModel.activate()`：`mode = .month`、`anchor = 今天`，向 `CalendarScene` 要一次可见范围的事件。
2. 可见范围：月视图 = 覆盖当月首末日的完整周网格（5–6 行，周一为每周第一天）；周视图 = 当前周 7 天。
3. `CalendarScene.events` → `MailStore.meetings(account:from:to:limit:)`：取 `start_utc <= to` 且（`end_utc >= from` 或 `recurrence IS NOT NULL`）的行；跳过 `is_cancelled = 1` 与 `meeting_message_type = 4` 的行。
4. 每条会议 → `MeetingInvite.occurrences(in: 可见范围, limit:)`：非重复会议只产出自身一次；重复会议按 `RecurrenceRule` 从系列起点逐次推进，直到超出范围/`UNTIL`/`OCCURRENCES`/单系列上限。
5. 汇总为 `[MeetingOccurrence]`，按开始时间排序；总量超过 `limit`（默认 500）时截断并置 `truncated = true`。
6. `CalendarViewModel` 把事件投影成 `MonthGridPresentation`（`weeks[][day]`，每格最多 3 个事件 + 「+N」）或 `WeekGridPresentation`（7 列 × 时间轴，事件块按起止比例定位，重叠事件并排）。
7. 渲染；切换月/周、上/下翻、今天：只改 `anchor`/`mode` 并重算投影，**不触网**。
8. 点事件块 → 事件详情（主题、时间、地点、组织者、重复说明、来源邮件主题）；「打开邮件」→ 交出 `MessageRef`，由视图层切回邮件页并选中。

失败路径：

- `MailStore` 读失败 → `CalendarViewModel.errorText` 中文文案 + 空态；保留上一次成功投影，不清空。
- 会议 `UID` 相同但 `DtStamp` 乱序到达 → 以库中最接近的一条为准（写入端已按 `DtStamp` 取最新，本层不再判）。
- `Recurrence` 无法解析或展开超上限 → 该系列只展示已知的第一次，并在事件详情标注「重复规则无法完整展开」；不阻塞其它事件。
- 时区偏移缺失或畸形 → 按 `+00:00` 处理并在事件详情标注「时区未知」，不崩、不改写存储。
- 无可见会议 → 空态：「本期没有收到会议邀请」，并提示「日历只展示升级后新收到的邀请」（不回填历史，见 `REQ-0029` 约束）。

## 不可变引用

- `SCN-0003`：收件箱增量同步的批次与 `SyncKey` 同事务、`sync_key` 重建语义；本卡只消费其产出，不改同步。
- `SCN-0004`：阅读路径缓存优先、`ReadScene.open` 零网络；日历页与阅读页共享同一条「UI 读本地库」不变量。
- `MailStore` 唯一写入口：日历页只读 `meetings`，不写；写仍只发生在 `applySyncBatch`。
- `MailboxView` 现有三栏邮件结构与工具栏语义；本卡只在侧栏增加一个入口与一处分栏切换，不改邮件列表/阅读交互。
- 不新增第三方依赖、不新增 target、不改 `Package.swift`。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0024-01` | 正 | 库里 2026-11 有 2 封邀请（11-19 09:30–12:00、11-23 16:00–17:00）→ 月视图 11 月网格：19 日格 1 个事件、23 日格 1 个事件，其余天空；标题行是「周一…周日」。**已通过**（`T-SCN-0024-01`，L1） |
| `T-SCN-0024-02` | 正 | 周视图（11-16 那周）→ 19 日列出现一块，纵向位置与 09:30 对齐、高度覆盖到 12:00；同一起止时间在月视图的「+N」计数一致。**已通过**（`T-SCN-0024-02`，L1 投影几何：`startMinute=570`/`endMinute=720`/两条 lane） |
| `T-SCN-0024-03` | 正 | 每周一次的邀请（周一 16:00，无限期）→ 取 4 周范围展开 4 次，每次都是周一 16:00；跨月边界后仍连续；单系列上限与总量上限都不触发截断。**已通过**（`T-SCN-0024-03`，2026-11 五次周一） |
| `T-SCN-0024-04` | 反 | 同一 `UID` 先收到 11-23 16:00、后收到 11-16 的更新（`DtStamp` 更早）→ 只出现一条且时间取 `DtStamp` 最新那条；再收到 `MeetingMessageType=4`/取消 → 该会议从月/周视图消失，其它会议不受影响；超过上限时截断标记为真且渲染不崩。**已通过**（`T-SCN-0024-04`，含 `limit: 3` 截断） |

## 状态

`verified`（2026-11-24 实现并验证）。

- 实现：`T-1124-03`…`T-1124-12`（WAL、outbox 拆分、EAS 解析、领域值、映射、v12 存储、场景、PRES、APP、ROOT）。
- 证据（L1，组件级）：`Tests/PresentationTests/CalendarScenarioTests.swift` 的 `T-SCN-0024-01..04`，
  配合 `CalendarProjectionTests`/`CalendarViewModelTests`/`CalendarSceneTests`/`MeetingStoreTests`/
  `MeetingRecurrenceTests`/`MeetingICSTests`。全量 437 tests / 71 suites 绿，架构 4 门过，`make-app.sh` 成功。
- L2 说明：月/周网格的像素与帧位置未做无头探针（`plan/risks.md` R59）；网格算法与文案在 L1 断言，
  视觉冒烟登记为发布前人工项，与 A5 同类。

- 入口符号在实现前可能 miss，属 `designed` 允许项；实现任务 `T-1124-09`（`CMP-SCN-CALENDAR`）转 `active` 后回填。
- 测试归属：`T-SCN-0024-01/03/04` 走 L1（`CalendarSceneTests` + `MailStoreTests` + `MailDomainTests` 的展开用例）；`T-SCN-0024-02` 需 L2 视图探针（月/周网格文本与几何），探针先行，失败则按 `plan/risks.md` R41 处理，不用 L1 投影冒充 L2。
