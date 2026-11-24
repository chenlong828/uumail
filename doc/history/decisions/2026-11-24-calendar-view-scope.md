---
layer: history
module: calendar
status: frozen
updated: 2026-11-24
---

# 会议邀请日历视图与会议卡范围（2026-11-24）

## 背景

2026-11-24 需求分析，从本机邮箱实证出发：

- 样本「【会议预告】AI时代的软件工程迭代和岗位变迁」不是普通邮件：EAS `ItemOperations/Fetch` 返回
  `MessageClass=IPM.Schedule.Meeting.Request`、`ContentClass=urn:content-classes:calendarmessage` 与完整
  `MeetingRequest`（`StartTime=2026-11-19T01:30:00Z`、`EndTime=04:00:00Z`、`Location/DisplayName=C4519`、
  `Organizer=王权英`、`Reminder=900`、`MeetingMessageType=2`、`UID=040000008200E0…`、`TimeZone` 为
  `Bias=-480` + `China Standard Time` 的 172 字节 blob）。
- 同一封邮件的 `Body` 只回 `Type=2`（HTML）；按 `BodyPreference Type=4` 请求 MIME 时，带 `MIMETruncation`
  直接 `ItemOperations status=2`，去掉后仍回 HTML。**`text/calendar` 原文拿不到**，`.ics` 必须按结构化字段重建。
- 全库 225 封邮件、`.ics` 附件 0 个；「钉钉日程」每周发出的例会邀请是同一形状（`MeetingMessageType=1`），
  说明「按时间聚合会议」在真实邮箱里每天都会用到，而当前客户端把它当普通 HTML 邮件展示。

用户在 2026-11-24 明确三项范围（三选一确认）：

1. 数据源 = **只展示收到的会议邀请**（不同步 Exchange 日历文件夹，也不分期合并）；
2. 动作 = **只读 + 「在日历中打开」**（不接受/暂定/拒绝，不调 `MeetingResponse`，不写服务器）；
3. 重复会议 = **完整展开重复规则**（不是只显示一次，也不是只按 UID 覆盖）。

## 决定

### D1 业务功能树新增领域 `calendar`（结构决定）

- **A（选用）**：新增领域 `calendar`，价值流 `browse`，场景 `SCN-0024`（`calendar/browse/calendar-grid`）。
  理由：日历浏览是「按时间看已收到的会议」，与「读一封邮件」是两个旅程；`mail/read` 下挂日历会制造错误父级，
  后续接受/拒绝（B 方案）也会自然落在同一领域。
- **B（否决）**：把日历页塞进 `mail/read/*`。否决理由：场景入口、数据、验收都与邮件阅读无关，树会误导后续拆分。
- **C（否决）**：现在就建「日程」领域并预设 `respond` 价值流。否决理由：拒绝/接受不在本期范围，空价值流违反「反占位」。

### D2 新增场景组件 `CMP-SCN-CALENDAR`，仍住 `Scenes` target

- **A（选用）**：新组件（场景），消费 `MailStore` + `MailDomain` 的 `MeetingInvite` 纯函数，负责范围查询、
  取消/过期过滤、重复展开与 `.ics` 文本。
- **B（否决）**：塞进 `ReadScene`。否决理由：`ReadScene` 已因写路径超预算（`Scenes` 1006 行），且两者旅程不同，
  塞进去会让「阅读」同时拥有「日历」。
- **C（否决）**：先做 L1b 能力组件（像 `SyncEngine`）。否决理由：没有第二个消费方，也无需与同步共享门；过度分层。

不新增 target、不新增依赖：`Scenes` target 内新增两个文件（`CalendarScene.swift`、`CalendarScene+Expansion.swift`）。

### D3 存储用独立 `meetings` 表（schema v12），以 `UID` 为主键

- **A（选用）**：新表 `meetings(account_id, uid, …)`；同步事务内 upsert，`dtstamp` 较旧不覆盖；取消/过期删除；
  同一会议的多封邀请只留一条。`MailStore` 仍是唯一写入口。
- **B（否决）**：给 `messages` 加会议列。否决理由：一条会议横跨多封邮件（新建/更新/取消），列模型无法去重；
  查询范围也要扫全表。
- **C（否决）**：独立 SQLite 库。否决理由：破坏「同一事务落库」与单写入口，升级/回滚成本高。

`CMP-STORE` 预算 1000 → **1250 行**（现 1024 行已超 24 行；本批 +约 110 行）；新增代码放
`MailStore+Meetings.swift`，主文件保持 ≤800 行。

### D4 会议卡位置与 `.ics` 导出

- 卡片放在**信封头与正文之间、正文状态 switch 之外**，`.loading/.loaded/.failed` 都可见（与信封头同层）；
  非邀请邮件不渲染占位。
- `.ics` 由 `MailDomain.MeetingInvite.ics` 纯函数生成：`METHOD:PUBLISH`、UTC `Z` 时间、重复系列带 `RRULE`
  与 `EXDATE`、例外用第二个 `VEVENT` + `RECURRENCE-ID`；写临时文件与 `NSWorkspace` 打开在 `CMP-APP`，
  用可注入 opener 便于 L2 断言。**不引入 EventKit、不申请日历权限**（用户确认的「只读 + 在日历中打开」）。
- **否决**：直接调用 EventKit 写系统日历。否决理由：需要 TCC 授权与 Info.plist 变更，且会把「导入」变成静默副作用；
  `.ics` + 系统日历应用更接近 Outlook 的「打开」语义。

### D5 重复展开与例外

- 展开实现放在 `MailDomain`（纯函数）：`MeetingInvite.occurrences(in:limit:)`；`CMP-SCN-CALENDAR` 只编排。
- 支持 EAS `Recurrence` 的 `Type` 0/1/2/3/5/6（**4 不存在**）、`Interval`、`Until`（Compact DateTime，UTC）、
  `Occurrences`、`DayOfWeek`（位掩码：1 日 … 64 六；62 = 工作日；65 = 周末；127 = 每月最后一天，仅 Type 3/6）、
  `DayOfMonth`、`WeekOfMonth`（1–4，5 = 最后）、`MonthOfYear`、`FirstDayOfWeek`。
- `InstanceType=3` 的例外邀请按 `RecurrenceId` 合并进主系列的 `exceptions`（可覆盖时间/主题/地点，可删除该次）；
  `InstanceType=2/4` 与缺失按单次处理，不猜系列。
- 展开必须有界：可见范围 + 单系列 200 + 单次查询 500；超出置 `truncated`，坏规则进 `unexpandedUIDs`，
  不让一条坏数据拖垮整页。

### D6 时区按固定偏移（已知限制）

只解析 blob 的 `Bias`（`offsetSeconds = -bias * 60`）与标准时区名；`StandardDate/DaylightDate/StandardBias/DaylightBias`
不解析，重复系列跨夏令时偏一小时。理由：本部署 `Asia/Shanghai` 无夏令时；完整 TZ 规则解析与 DST 展开另立（Q5）。

### D7 范围外（明确不做）

不同步日历集合、不调 `MeetingResponse`、不回复邀请、不新建/编辑/删除日程、不做冲突检测/提醒/日视图/year 视图、
不做参与人视图、不处理附件 `.ics`（网关不下发）、不做 EventKit 集成。

## P1 确认清单（阻塞实现）

1. 新增场景组件 `CMP-SCN-CALENDAR`（仍住 `Scenes` target）。
2. `MailDomain` 新增 public `MeetingInvite`/`RecurrenceRule`/`RecurrenceRule.Frequency`/`MeetingException`/
   `MeetingOccurrence`/`MeetingTimeZone`/`MeetingMessageType`/`Weekday` 与 `Message.meeting`（additive）。
3. `MailStore` schema **v12** `meetings` 表、`applySyncBatch` 会议写入与取消删除、三个读方法。
4. `CMP-PRES` 新增 public `CalendarViewModel`、`MonthGridPresentation`/`WeekGridPresentation`/`MeetingCardPresentation`。
5. `CMP-STORE` 预算 1000 → 1250 行。
6. 业务功能树新增领域 `calendar`。

## 确认记录

- **2026-11-24 人工确认**：数据源 = 只展示收到的邀请；动作 = 只读 + 「在日历中打开」；重复 = 完整展开。
- **2026-11-24 默认确认（未经人工）**：D1（新领域）、D2（新场景组件）、D3（独立表 + 按 UID + 预算调整）、
  D4（卡片位置 + `METHOD:PUBLISH` + 不引入 EventKit）、D5（展开与例外处理）、D6（固定偏移）、D7（范围外清单）。
  评审可独立否决；否决任一项先回设计，不直接进实现。
- 未确认前不写实现代码（`T-1124-02` 确认门；见 `plan/roadmap.md` §W-M3-15）。

## 影响与后续

- 需求：`REQ-0029`、`REQ-0030`（`accepted`）；场景：`SCN-0024`、`SCN-0023`（`designed`）。
- 组件：`CMP-SCN-CALENDAR`（新，`planned`）、`CMP-DOMAIN`/`CMP-EAS`/`CMP-EASADAPTER`/`CMP-STORE`/`CMP-PRES`/
  `CMP-APP`/`CMP-ROOT` 各一条设计增量；`CMP-SYNC`/`CMP-OUT`/`CMP-CLI` 无改动。
- 风险：R56–R59；开放问题：Q5–Q7；任务表：`plan/roadmap.md` §W-M3-15。
- 后续（B 方案）若要做接受/拒绝：需 `MeetingResponse` 命令（`CollectionId`=收件箱、`RequestId`=邮件 `ServerId`、
  `UserResponse` 1/2/3、16.x 的 `SendResponse` 决定是否发回执）、日历集合同步与本地状态回读；本记录不为其预埋契约。
