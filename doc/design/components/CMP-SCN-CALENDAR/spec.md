---
layer: design
module: scenes
status: active
updated: 2026-11-25
component: CMP-SCN-CALENDAR
---

# CMP-SCN-CALENDAR CalendarScene 组件规格

## 模块卡

- 状态：`active`（`CalendarScene` 已实现，2026-11-24 `T-1124-09`；2026-11-25 增量补 `message(_:)` 只读读面，见文末）
- 单元：组件（场景，`Sendable` 值类型）
- 层 / 类型：L2；日程浏览与 iCalendar 导出
- 业务价值：把「按可见范围取会议 → 过滤取消/过期 → 展开重复 → 有界截断 → 生成 iCalendar」收在一处；没有它，网格视图会自己查库、自己展开重复、自己拼 `.ics`，规则散落且无法纯函数化测试。
- 负责 X：`events(from:to:limit:)` 的范围查询与重复展开编排；`meeting(uid:)` 单条会议读取；`ics(uid:)` 单条会议导出文本。拥有「同一 `UID` 只出一条、取消不出、展开有界」这三条规则。
- 不负责 Y：网络与同步（`SyncScene`）、会议字段的协议解析（`CMP-EAS`）、持久化与迁移（`CMP-STORE`）、网格布局与文案（`CMP-PRES`）、`.ics` 落盘与唤起日历应用（`CMP-APP`）。
- 内部逻辑：
  - `events`：本地库读 `meetings` 范围行 → 跳过 `is_cancelled`/`message_type = 4` → 每条调 `MeetingInvite.occurrences(in:limit:)` → 合并、排序、按 `limit` 截断；任一行的重复规则不可解析时记入 `unexpandedUIDs`，其余照常返回。
  - `ics`：读该 `UID` 的会议行 → `MeetingInvite.ics(now:)`（VTIMEZONE 或 UTC `Z` 形式二选一，见 `CMP-DOMAIN` 增量）→ 返回文本；不写文件。
  - 全部方法**零网络**；读失败直接抛 `MailStoreError`，不包装、不重试。
- 拥有的数据：无持久数据；只读 `meetings` 与 `messages`（主题 join）。
- 变化轴：日历视图形态（月/周 → 日/列表）、是否扩展到 Exchange 日历集合、是否支持接受/拒绝（后续 B 方案）。
- 公开契约：`CMP-SCN-CALENDAR#events`、`#meeting`、`#ics`、`#message`（2026-11-25 新增，REQ-0040）
- 入口：`Sources/Scenes/CalendarScene.swift#CalendarScene`
- 依赖：`MailStore`、`MailDomain`（`MeetingInvite`/`MeetingOccurrence`/`RecurrenceRule`）。扇出 2（与 `ReadScene` 的 3 不同，不新增端口）。
- 冷热：热（打开日历页、翻月/翻周均为本地读，主线程外一次查询）。
- 尺寸预算：≤260 行；预计 `CalendarScene.swift` 约 150 行、`CalendarScene+Expansion.swift` 约 60 行（拆分触发：`Scenes` 再次超过 `design/architecture.md` §10 登记的上限时另评）。
- 单独运行：`./Scripts/swiftw test --filter CalendarSceneTests`
- 删除测试：删掉后 `CalendarViewModel` 直接持 `MailStore` 并内联重复展开，展示层出现业务规则 → 复杂度集中，是真边界。

## 契约卡：CalendarScene v1

- 签名：

  ```swift
  public struct CalendarScene: Sendable {
      public init(store: MailStore, account: AccountID)

      /// 可见范围 [from, to] 内所有会议实例；同一 UID 只出一条来源；
      /// 重复会议按规则展开，单系列与总量都有上限。
      public func events(from: Date, to: Date, limit: Int = 500) throws -> CalendarEvents

      /// 单条会议读取（供阅读页卡片与导出）；无会议时 nil。
      public func meeting(uid: String) throws -> MeetingInvite?

      /// 按 UID 生成 iCalendar 文本（`METHOD:PUBLISH`；重复会议带 RRULE）。
      public func ics(uid: String, now: Date = Date()) throws -> String
  }

  public struct CalendarEvents: Equatable, Sendable {
      public var occurrences: [MeetingOccurrence]   // 按 start 升序
      public var truncated: Bool
      public var unexpandedUIDs: [String]           // 重复规则无法解析的系列
  }
  ```

- 前置条件：`from < to`；`limit > 0`。`to - from` 超过 400 天时按 400 天截断（防误用）。
- 后置条件：`occurrences` 全部落在 `[from, to]`；`start <= end`；`truncated == true` 时 `occurrences.count == limit`。
- 不变量：零网络；同一 `UID` 只出现一条来源；`is_cancelled`/`message_type = 4` 的系列不出现；单次调用最多 `limit` 条。
- 错误模式：`MailStoreError.database`/`.accountNotFound` 原样抛；`ics` 在会议行缺失时抛 `CalendarSceneError.meetingNotFound`；调用方（VM）映射为中文，不自动重试。
- 幂等 / 顺序 / 并发：纯读；同参数重复调用结果一致（库不变时）；无内部可变状态，可并发读。
- 超时 / 取消：无网络、无长任务；展开循环受 `limit` 与范围双重约束（最坏 O(limit)）。
- 一致性 / 可见性：读的是 `MailStore` 当前提交的数据；同步事务提交后立即可见（同库同连接池）。
- 兼容性：新增组件，无既有调用方；契约只出现 `MailDomain` 值类型与 `MailStore`。
- 契约测试：`ScenesTests/CalendarSceneTests`（范围过滤、取消过滤、重复展开、截断、`unexpandedUIDs`、`ics` 文本）。

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 契约不变量 | 范围外事件不出现、同 UID 一条、取消不出现、`limit` 截断 |
| 规则 | 每日/每周/每月按日/每月按周/每年四类的展开点数与首次时间 |
| 失败/降级 | 坏 `Recurrence` → `unexpandedUIDs` 且其余正常；会议行缺失 → `meetingNotFound` |
| 冷热/隔离 | 纯本地读，无网络依赖；断言 `CalendarScene` 不 import `EASClient`（架构门 1 自动覆盖） |
| 数据/迁移 | 依赖 `MailStoreTests/MigrationTests` 的 v12 fixture |
| 观测 | 无需新增指标；`truncated`/`unexpandedUIDs` 仅在视图提示 |

## 设计增量：REQ-0029 / SCN-0024（2026-11-24，已实现）

- 为何新增组件而不是塞进 `ReadScene`：阅读场景已因写路径超预算（`Scenes` 1006 行，`design/architecture.md` §10），且日历浏览与「打开一封邮件」的旅程不同；按「一条业务流一个场景」的收口规则（D1），日程浏览独立成 `CMP-SCN-CALENDAR`，仍然住在既有 `Scenes` target，**不新增 target**。
- 与 `ReadScene` 的关系：两者共享 `MailStore` 与「读本地零网络」不变量，但互不调用；视图层需要「从日历跳回邮件」时只交出 `(folderID, serverID)`，由 `CMP-APP` 转调 `MailboxViewModel.select`。
- 不拥有写路径：不调 `SyncEngine`，不做已读回写；打开日历不改变任何邮件状态。
- 展开细节：`MeetingInvite.occurrences` 是 `CMP-DOMAIN` 的纯函数，`CalendarScene` 只负责「取行 → 调纯函数 → 合并」，不复制规则。
- 导出细节：`ics` 只生成文本；临时文件与 `NSWorkspace` 唤起在 `CMP-APP`（见 `CMP-APP` 增量），因此本组件可在无 UI 的测试里完整验证。

## 实现（2026-11-24，T-1124-09）

- `Sources/Scenes/CalendarScene.swift`（约 90 行）：`events(from:to:limit:)`、`meeting(uid:)`、`ics(uid:now:)`；
  查询多取一行以识别截断，单系列上限 200，范围上限 400 天。
- 测试：`Tests/ScenesTests/CalendarSceneTests.swift` 5 例（范围/排序、重复展开与截断、取消隐藏、ICS 与缺失、非法范围）。
- 零网络：不 import `EASClient`/`SyncEngine`；`Scenes` 总量未新增 target。

## 设计增量：按引用取来源邮件（REQ-0040，2026-11-25，P3，已实现）

- 来源：`REQ-0040` / `SCN-0024` 增量。日历页左列要显示邀请邮件的主题与发件人，`MeetingOccurrence` 只有 folder + serverID 与会议字段，读不到信封；本增量给场景补一条按引用取邮件的只读入口。消费方是 `CMP-PRES` 的 `CalendarViewModel`（去重后逐条取信封），视图见 `CMP-APP` 同日增量。
- 新增 public 方法：

  ```swift
  public func message(_ ref: MessageRef) throws -> Message?
  ```

  - 只读：转调 `MailStore.message(account:folder:serverID:)`，不改会议行/邮件行、不推进游标、不触发同步、不写已读。
  - 缺失返回 nil：邮件已删除、被移走或从未落库时不抛业务错误，调用方照常保留该行（回退用会议元数据）。
  - 存储错误原样上抛（`MailStoreError`），不在场景内包装或重试；`CMP-PRES` 用 `try?` 收口为 nil。
  - 复合键语义：folder + serverID 一起定位，同 serverID 不同 folder 不串。
- 消费方与次数：`CalendarViewModel.reload` 只在去重后的来源邮件上逐条调用一次，刷新一次最多 N 次本地索引读（N = 去重后的邀请邮件数）；不遍历邮件表、不做 join、不缓存。
- 不改契约与写路径：`events`/`meeting`/`ics` 的签名与语义不变；不新增端口、不改 schema/迁移、不新增字段；不调 `SyncEngine`/`MailWriteGateway`，日历页仍零网络、零写；`CalendarScene` 仍不 import `EASClient`/`SyncEngine`（架构门 1 覆盖）。
- 尺寸：`CalendarScene.swift` 98 行（≤260）；不新增文件/target/依赖。
- 验证：`CalendarSceneTests` 既有用例不回归；信封命中与缺失回退由 `T-SCN-0024-10`（经 `CalendarViewModel`）间接覆盖，断言原文以场景卡为准；全量 466 tests / 77 suites、架构 4/4。
- 定级：**P3**（场景 additive 只读方法；无 schema/写路径/同步契约变化）。
