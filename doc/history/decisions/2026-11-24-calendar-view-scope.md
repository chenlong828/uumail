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
- 2026-11-24 复制库实测 `PRAGMA journal_mode = delete`，而文档从 2026-11-09 起写的是「WAL + FTS5」——
  同日在本次决策中一并修正。

用户在 2026-11-24 逐项确认（第一轮三项范围 + 第二轮 6 个 P1 + 第三轮 6 个风险口径 + 拆分/WAL 两问）：

1. 数据源 = **只展示收到的会议邀请**（不同步 Exchange 日历文件夹）；
2. 动作 = **只读 + 「在日历中打开」**（不接受/暂定/拒绝，不调 `MeetingResponse`）；
3. 重复会议 = **完整展开重复规则**；
4. 结构：新场景组件 `CMP-SCN-CALENDAR`、`MailDomain` 承载会议值类型、独立 `meetings` 表、public 视图模型、
   业务树新增 `calendar` 领域；
5. 存储：**先把 outbox 物理读写拆出去**再实现日历（不调 `MailStore` 预算）；账号/文件夹拆分另立工序；
6. 运行环境：SQLite **启用 WAL**（单队列）；
7. 风险口径：时区固定偏移、**不回填历史邀请**、`DtStamp` 只升不降、例外合并、L2 探针先证 seam、网关缺字段时退化为普通邮件。

## 决定

### D1 业务功能树新增领域 `calendar`（结构决定）

- **A（选用）**：新增领域 `calendar`，价值流 `browse`，场景 `SCN-0024`（`calendar/browse/calendar-grid`）。
  理由：日历浏览是「按时间看已收到的会议」，与「读一封邮件」是两个旅程；后续接受/拒绝（B 方案）也会落在同一领域。
- **B（否决）**：把日历页塞进 `mail/read/*`。理由：场景入口、数据、验收都与邮件阅读无关，树会误导后续拆分。
- **C（否决）**：现在就建「日程」领域并预设 `respond` 价值流。理由：拒绝/接受不在本期范围，空价值流违反「反占位」。

### D2 新增场景组件 `CMP-SCN-CALENDAR`，仍住 `Scenes` target

- **A（选用）**：新组件（场景），消费 `MailStore` + `MailDomain` 的 `MeetingInvite` 纯函数，负责范围查询、
  取消/过期过滤、重复展开与 `.ics` 文本。
- **B（否决）**：塞进 `ReadScene`。理由：`ReadScene` 已因写路径超预算（`Scenes` 1006 行），且两者旅程不同。
- **C（否决）**：先做 L1b 能力组件（像 `SyncEngine`）。理由：没有第二个消费方，也无需与同步共享门；过度分层。

不新增 target、不新增依赖：`Scenes` target 内新增两个文件。

### D3 存储用独立 `meetings` 表（schema v12），以 `UID` 为主键

- **A（选用）**：新表 `meetings(account_id, uid, …)`；同步事务内 upsert，`dtstamp` 较旧不覆盖；取消/过期删除；
  同一会议的多封邀请只留一条。`MailStore` 仍是会议室写入的唯一入口。
- **B（否决）**：给 `messages` 加会议列。理由：一条会议横跨多封邮件（新建/更新/取消），列模型无法去重；
  查询范围也要扫全表。
- **C（否决）**：独立 SQLite 库。理由：破坏「同一事务落库」与单写入口，升级/回滚成本高。

**前置拆分**：`MailStore` 现 1024 行、已超 1000 上限 24 行；本批不调预算，而是把 outbox 表的物理读写拆到
`CMP-OUTBOX-STORE`（约 −210 行 → 约 814 行；加 `meetings` 约 110 行 → 约 924 行）。账号/文件夹拆分涉及
`sync_state` 的事务边界（批次与 key 同事务、`discardAccount` 空账号检查），**另立 `W-REFACTOR-02`**，不夹带。

### D4 会议卡位置与 `.ics` 导出

- 卡片放在**信封头与正文之间、正文状态 switch 之外**，`.loading/.loaded/.failed` 都可见；非邀请邮件不渲染占位。
- `.ics` 由 `MailDomain.MeetingInvite.ics` 纯函数生成：`METHOD:PUBLISH`、UTC `Z` 时间、重复系列带 `RRULE`
  与 `EXDATE`、例外用第二个 `VEVENT` + `RECURRENCE-ID`；写临时文件与 `NSWorkspace` 打开在 `CMP-APP`，
  用可注入 opener 便于 L2 断言。**不引入 EventKit、不申请日历权限**。
- **否决**：EventKit 直接写系统日历。理由：需要 TCC 授权与 Info.plist 变更，且会把「导入」变成静默副作用。

### D5 重复展开、排序与例外

- `MailDomain` 纯函数 `MeetingInvite.occurrences(in:limit:)`；`CMP-SCN-CALENDAR` 只编排。
- 支持 EAS `Recurrence` 的 `Type` 0/1/2/3/5/6（**4 不存在**）、`Interval`、`Until`（Compact DateTime，UTC）、
  `Occurrences`、`DayOfWeek` 位掩码（1 日 … 64 六；62 工作日；65 周末；127 每月最后一天，仅 Type 3/6）、
  `DayOfMonth`、`WeekOfMonth`（1–4，5 = 最后）、`MonthOfYear`、`FirstDayOfWeek`。
- **排序**：同一 `UID` 多封邀请按 `DtStamp` **只升不降**；`DtStamp` 缺失时按到达顺序。取消/`MeetingMessageType=4`
  删除整行（邮件信封保留）。
- **例外**：`InstanceType=3` 的例外邀请按 `RecurrenceId` 合并进主系列的 `exceptions`（可改时间/主题/地点或删除该次）；
  `InstanceType=2/4` 与缺失按单次处理，不猜系列。
- **否决**：按到达顺序覆盖（网络乱序会让旧时间盖新时间）；例外独立成条（同一时间出现两条）。

### D6 时区按固定偏移（已知限制）

只解析 blob 的 `Bias`（`offsetSeconds = -bias * 60`）与标准时区名；`StandardDate/DaylightDate/StandardBias/DaylightBias`
不解析，重复系列跨夏令时偏一小时。理由：本部署 `Asia/Shanghai` 无夏令时；完整 TZ 规则解析与 DST 展开另立（Q5）。

### D7 不回填历史邀请（用户确认）

- v12 **不重置游标、不回扫**；升级后日历从空开始，只有升级后新到的邀请出现；升级前的邀请邮件也没有会议卡。
- 用户明确接受「上线当天看起来什么都没有」的代价；空态必须写清覆盖范围，不能静默空白。
- **否决**：升级时回填一个窗口（会多拉 ≤125 封，用户选择不承担）；首次打开日历时补拉（破坏「打开日历零网络」）。

### D8 范围外（明确不做）

不同步日历集合、不调 `MeetingResponse`、不回复邀请、不新建/编辑/删除日程、不做冲突检测/提醒/日视图/年视图、
不做参与人视图、不处理附件 `.ics`（网关不下发）、不做 EventKit 集成、不做正文正则抽取时间。

### D9 outbox 存储拆分（前置，P1）

- 新组件 `CMP-OUTBOX-STORE`（住 `MailStore` target，`Sources/MailStore/OutboxStore.swift`）接管 outbox 表全部 SQL；
  `MailStore` 持有实例并 `public var outbox` 暴露，`Outbox` 依赖由 `MailStore` 换成 `OutboxStore`。
- **同一 `mail.sqlite`、同一 `DatabaseQueue`**；表仍由 `MailStoreMigrations` 建立，本组件不注册迁移；
  每张表一个写入口，事务不跨表。
- 否决：独立 `outbox.sqlite`（多一套路径/备份/迁移）；只拆文件不拆所有权（预算问题没解决）。

### D10 SQLite 启用 WAL（用户确认）

- `MailStore.init(path:)` 显式 `Configuration.journalMode = .wal`，仍单 `DatabaseQueue`（不开 `DatabasePool`）。
- 影响：`-wal`/`-shm` 副文件、备份要一起带走或 `VACUUM INTO`、关闭时 checkpoint；内存库测试不受影响。
- 否决（暂不）：换 `DatabasePool` 做读写真并发（独立 P1，改动面大）。

### D11 风险处置口径（逐项确认）

| 风险 | 处置 |
|---|---|
| R56 时区/DST | 固定偏移 + 事件详情标注；要求精确再按 Q5-B 另立 |
| R57 多封邀请覆盖 | `DtStamp` 只升不降，缺失按到达；取消删除整行 |
| R58 历史回填 | **不回填**（D7），空态说明覆盖范围 |
| R59 L2 探针 | 先证 seam；证不到则场景声明 L3 并留截图/AX 证据，不拿 L1 冒充 |
| R60 网关不下发会议字段 | 退化为普通邮件、不崩；日历空态提示「未识别到会议邀请」；不猜正文时间 |
| Q7 例外 | 合并进系列（D5） |

## P1 确认清单（2026-11-24 已确认）

1. 新增场景组件 `CMP-SCN-CALENDAR`（仍住 `Scenes` target）。
2. `MailDomain` 新增 public `MeetingInvite`/`RecurrenceRule`/`RecurrenceRule.Frequency`/`MeetingException`/
   `MeetingOccurrence`/`MeetingTimeZone`/`MeetingMessageType`/`Weekday` 与 `Message.meeting`（additive）。
3. `MailStore` schema **v12** `meetings` 表、`applySyncBatch` 会议写入与取消删除、三个读方法。
4. `CMP-PRES` 新增 public `CalendarViewModel`、`MonthGridPresentation`/`WeekGridPresentation`/`MeetingCardPresentation`。
5. **outbox 表物理读写拆至新组件 `CMP-OUTBOX-STORE`**（替代原「预算 1000→1250」提案；预算保持 1000）。
6. 业务功能树新增领域 `calendar`。
7. **SQLite 启用 WAL**（`Configuration.journalMode = .wal`，单队列）。

## 确认记录

- **2026-11-24 人工确认（第一轮）**：数据源 = 只展示收到的邀请；动作 = 只读 + 「在日历中打开」；重复 = 完整展开。
- **2026-11-24 人工确认（第二轮，6 项 P1）**：新场景组件（选 A）；`MailDomain` 承载会议值类型（选 A）；
  独立 `meetings` 表 + `UID`（选 A）；public 视图模型（选 A）；**先拆 `MailStore`**（未选预算上调）；
  新增 `calendar` 领域（选 A）。
- **2026-11-24 人工确认（拆分范围）**：先只拆 outbox（`CMP-OUTBOX-STORE`），账号/文件夹另立 `W-REFACTOR-02`；
  存储边界选「同一 SQLite + 共享 `DatabaseQueue`」。
- **2026-11-24 人工确认（第三轮，风险口径）**：固定偏移（A）；**不回填**（C，已二次确认接受空日历）；
  `DtStamp` 只升不降（A）；例外合并（A）；先证 seam、不行则 L3（A）；网关缺字段退化为普通邮件（A）。
- **2026-11-24 人工确认（运行环境）**：SQLite 启用 WAL、仍单队列（B）。
- **2026-11-24 默认确认（未经人工，均可独立否决）**：D3 的 `UID` upsert 细节（`dtstamp` 比较、取消删除）、
  D4 的 `METHOD:PUBLISH` 与 UTC `Z` 形式、D5 的例外合并数据结构、`.ics` 的 `EXDATE`/`RECURRENCE-ID` 生成方式、
  各任务的拆分粒度（见 `plan/roadmap.md` §W-M3-16）。

## 影响与后续

- 需求：`REQ-0029`、`REQ-0030`（`accepted`）；场景：`SCN-0024`、`SCN-0023`（`designed`）。
- 组件：`CMP-SCN-CALENDAR`、`CMP-OUTBOX-STORE`（新，`planned`）；`CMP-DOMAIN`/`CMP-EAS`/`CMP-EASADAPTER`/
  `CMP-STORE`/`CMP-OUT`/`CMP-PRES`/`CMP-APP`/`CMP-ROOT` 各一条设计增量；`CMP-SYNC`/`CMP-CLI` 无改动。
- 风险：R56–R60、新增 R61（WAL 副文件与备份）；开放问题：Q5–Q7；任务表：`plan/roadmap.md` §W-M3-16。
- 后续（B 方案）若要做接受/拒绝：`MeetingResponse`（`CollectionId`=收件箱、`RequestId`=邮件 `ServerId`、
  `UserResponse` 1/2/3、`SendResponse` 决定是否发回执）、日历集合同步与本地状态回读；本记录不为其预埋契约。
