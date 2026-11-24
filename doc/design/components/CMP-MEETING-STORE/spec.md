---
layer: design
module: calendar
scope: project:uumail
status: active
updated: 2026-11-24
component: CMP-MEETING-STORE
---

# CMP-MEETING-STORE 会议表读写

- **单元 / 层**：组件 / L1a 数据服务（`meetings` 表，schema v12）
- **业务价值**：为日历与邀请卡提供 `meetings` 行的唯一写入口与范围查询；没有它，同步写路径与日历读取会各自拼 SQL。
- **负责 / 不负责**：
  - 负责：`upsertMeeting`（取消删系列、例外 `InstanceType=3` 合并进系列、`DtStamp` 只升不降）、`deleteMeetings`、
    `meetings(account:from:to:limit:)` 范围查询、`meetingInvite(account:uid:)` 单条、`attachMeetings` 列表装饰、
    行 ↔ `MeetingInvite` 的 JSON 编解码。
  - 不负责：重复规则展开与 `.ics` 序列化（`MailDomain`/`CMP-SCN-CALENDAR`）、同步批次事务（`CMP-STORE` 的 `applySyncBatch` 调用本组件）、
    日历页展示（`CMP-PRES`/`CMP-APP`）。
- **数据所有权**：`meetings` 表（与 `messages` 同库、同队列）；写只发生在 `applyDelta` 的批次事务内。
- **公开契约**：`MailStore.meetings(account:from:to:limit:)`、`MailStore.meetingInvite(account:uid:)`；
  内部契约 `upsertMeeting` / `deleteMeetings` / `attachMeetings`（同 target 内使用）。
- **依赖**：`MailDomain`、GRDB；`MailStore.swift` 只调用、不持有会议 SQL。
- **尺寸预算**：≤400 行；当前 **287**（`MeetingStore+Read.swift` 140 + `MeetingStore+Write.swift` 147，2026-11-24 `wc -l`）；单文件 ≤150。
- **单独运行**：`./Scripts/swiftw test --filter MeetingStoreTests`（`MailStoreTests` 内）。
- **验证计划**：`MeetingStoreTests` 覆盖写入/取消/例外合并/`DtStamp` 顺序/范围查询/列表装饰；`CalendarSceneTests` 回归范围查询与展开。
- **删除测试**：删掉后会议 SQL 会回到 `MailStore.swift`，`CMP-STORE` 再次超 1000 行且会议写入不再有单一 owner → 真边界。
- **来源**：`history/decisions/2026-11-24-risk-review-decisions.md` D1（先拆 `MailStore+Meetings.swift`）；
  2026-11-24 从 273 行单文件拆为读写两个文件，并从 `CMP-STORE` 预算中析出。
