# W-M3-16 设计走查（2026-11-24）

## 1. 现状盘点（只读）

- `EASClient.parseMessage` 只取 `ServerId/Subject/From/To/DateReceived/Read/Importance/Body/Attachments/Cc`；`MessageClass`、`MeetingRequest`、`ContentClass` 全部丢弃。
- `MailDomain.Message` 无会议字段；`MailStore` 无会议表/查询；`Scenes` 无日历场景；`Presentation` 无日历视图模型；`uumail` 无日历入口。
- 本机库 225 封邮件、`.ics` 附件 0 个；实探 `ItemOperations` 拿不到 MIME。
- 结论：数据在信封里已经在，缺的是「解析 → 落库 → 聚合 → 展示」四段。

## 2. 候选方案与被否决项

| 决策 | 采用 | 否决 |
|---|---|---|
| 业务树 | 新领域 `calendar` / `browse` / `calendar-grid` | 挂 `mail/read`（错误父级）；预建 `respond`（空占位） |
| 场景组件 | 新 `CMP-SCN-CALENDAR`（住 `Scenes`） | 塞 `ReadScene`（已超预算、旅程不同）；先做 L1b 能力（无第二消费方） |
| 存储 | 独立 `meetings` 表、`UID` 主键、v12 | `messages` 加列（无法按会议去重）；独立库（破坏同事务） |
| 导航 | 侧栏顶部「日历」行 + 顶层二分支 `NavigationSplitView` | 独立窗口（不够 Outlook-like）；改 `MailboxViewModel` 承担日历状态（职责混淆） |
| 导出 | 本地生成 `.ics` → `NSWorkspace` 打开 | EventKit 直接写（需 TCC/plist、静默副作用） |
| 重复 | `MailDomain` 纯函数展开 + 例外合并 | 只显示一次；只按 UID 覆盖不展开 |

## 3. 数据流

```
EAS Sync (Inbox)
  └─ MessageClass + MeetingRequest (+ Recurrences)
      └─ EASClient.parseMessage → EASMessage.meeting
          └─ EASAdapter.map → MailDomain.Message.meeting: MeetingInvite?
              └─ MailStore.applySyncBatch（同事务）→ meetings (v12, PK uid)
                  ├─ CalendarScene.events(from:to:) → 展开 → MeetingOccurrence[]
                  │    └─ CalendarViewModel → MonthGrid/WeekGrid → CalendarView
                  └─ CalendarScene.ics(for:) → MeetingInvite.ics → CalendarExport → Calendar.app
```

## 4. 契约 diff（摘要）

- `MailDomain`：新增 `MeetingInvite`/`RecurrenceRule`/`MeetingException`/`MeetingOccurrence`/`MeetingTimeZone`/`MeetingMessageType`/`Weekday`；`Message.meeting` additive。
- `EASClient`：`EASMessage.messageClass`/`meeting`，`EASMeeting`/`EASRecurrence`/`EASMeetingTimeZone`（additive）。
- `MailStore`：schema v12 + `applySyncBatch` 写会议 + 三个读方法（`MailStore+Meetings.swift`）；预算 1000→1250（P1）。
- `CalendarScene`：`events(from:to:limit:)`/`meeting(for:)`/`ics(for:)`（新组件契约）。
- `Presentation`：`CalendarViewModel` + `MonthGridPresentation`/`WeekGridPresentation`/`MeetingCardPresentation` + `MailboxViewModel.meetingCard`（additive）。
- `uumail`：`CalendarView`/`MeetingCardView`/`CalendarExport` + `MailboxView` 侧栏入口与分支；`AppComposition` +10 行（≤200）。

## 5. 冷热路径

- 热：打开日历页、翻月/翻周、打开邀请邮件（全部本地读，零网络）。
- 冷：同步窗口内落库（随既有 Sync）、`.ics` 临时文件写（点击时一次）。
- 隔离：日历页不触网、不写库、不参与同步门；`CalendarScene` 无网络依赖，架构门 1 可守。

## 6. 验证计划

| 层 | 证据 |
|---|---|
| L1 | `EASClientTests`（MeetingRequest/Recurrence/TZ blob/缺字段）、`EASAdapterTests`（Class 映射/位掩码）、`MailDomainTests`（展开/ICS）、`MailStoreTests`（v12/upsert/取消/迁移）、`ScenesTests`（范围/截断/例外）、`PresentationTests`（网格/投影/卡片） |
| L2 | 月格文本与「+N」、周块几何、卡片文本、导出点击与临时文件清理（`NSHostingController` + `NSTextField`/`NSToolbar` seam） |
| 回归 | `SCN-0003`/`SCN-0004`/`SCN-0012` 不退化；全量测试 + 架构 4 门 + `make-app.sh` |

## 7. 未决

- `T-1124-02` P1 六项（新组件/领域契约/schema v12/PRES 公开面/`MailStore` 预算/业务树），未过不写实现。
- Q5–Q7 默认值已登记，评审可改。
- L2 探针 seam（R59）需在 `T-1124-09` 前先证；不可行则由场景卡声明 L3。

## 8. 2026-11-24 拍板结果（逐项）

| 问题 | 结论 |
|---|---|
| 新场景组件 | 新增 `CMP-SCN-CALENDAR`（住 `Scenes`） |
| `MailDomain` 契约 | 会议值类型进 `MailDomain`，`Message.meeting` additive |
| 存储形态 | 独立 `meetings` 表、主键 `(account, uid)` |
| 展示层公开面 | public `CalendarViewModel` + 网格/卡片展示类型 |
| `MailStore` 预算 | **先拆 outbox**（`CMP-OUTBOX-STORE`），预算保持 1000；账号/文件夹另立 `W-REFACTOR-02` |
| 业务树 | 新增领域 `calendar` |
| outbox 存储边界 | 同一 `mail.sqlite` + 同一 `DatabaseQueue`；表仍由 `MailStoreMigrations` 建 |
| SQLite 日志模式 | 启用 WAL（`Configuration.journalMode = .wal`，单队列） |
| 时区/DST | 固定偏移 + 标注（Q5 默认 A） |
| 历史回填 | **不回填**，接受升级后空日历与旧邀请无卡片 |
| 多封邀请覆盖 | `DtStamp` 只升不降 |
| 重复例外 | `InstanceType=3` 合并进系列 |
| L2 探针 | 先证 seam，失败声明 L3 |
| 网关缺字段 | 退化为普通邮件 + 空态提示 |

任务表按此重排：`T-1124-03` WAL → `T-1124-04` outbox 拆分 → `T-1124-05..07` 协议/领域/映射 →
`T-1124-08` v12 存储 → `T-1124-09..12` 场景/展示/视图/装配 → `T-1124-13..15` 验证与发布。
