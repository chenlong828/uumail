---
layer: design
module: calendar
scope: project:uumail
status: active
updated: 2026-11-24
component: CMP-MEETING-DOMAIN
---

# CMP-MEETING-DOMAIN 会议值类型与重复展开

- **单元 / 层**：组件 / L1 值域（纯值类型与纯函数；新 target `MeetingDomain`）
- **业务价值**：把「一场会议」从 EAS 字段到日历投影的全部规则（时间、地点、组织者、重复规则、例外、取消、
  `MeetingOccurrence` 展开与 `.ics` 序列化）收在一个稳定契约里；日历、邀请卡与导出都只依赖它。
- **负责 / 不负责**：
  - 负责：`MeetingInvite` / `MeetingOccurrence` / `RecurrenceRule` / `RecurrenceRule.Frequency` / `Weekday` /
    `MeetingException` / `MeetingTimeZone` / `MeetingMessageType` / `MeetingResponseType` 等值类型，
    `occurrences(in:limit:)` 重复展开、`ics(now:)` iCalendar 序列化、`exceptionRecurrenceID` 语义。
  - 不负责：EAS WBXML 解析与字段映射（`CMP-EAS` / `CMP-EASADAPTER`）、`meetings` 表读写（`CMP-MEETING-STORE`）、
    日历页状态与投影（`CMP-PRES`/`CMP-APP`）、同步批次事务（`CMP-SYNC-CONTRACT`）。
- **数据所有权**：无（纯值类型；不持久化、不读库）。
- **公开契约**：`MeetingInvite`（可构造、`Equatable`/`Sendable`，含 `ics(now:)` 与 `occurrences(in:limit:)`）、
  `MeetingOccurrence`、`RecurrenceRule` 及其 `Frequency`/`Weekday`、`MeetingException`、`MeetingTimeZone`、
  `MeetingMessageType`。契约里不出现存储、网络或 EAS 类型。
- **依赖**：`Foundation` only（叶子 target，零依赖）。
- **尺寸预算**：≤800 行；当前 **682**（`Sources/MeetingDomain/Meeting.swift`，2026-11-24 `wc -l`）。
- **单独运行**：`./Scripts/swiftw test --filter MeetingDomainTests`。
- **验证计划**：`MeetingDomainTests` 覆盖重复展开（日/周/月/年、间隔、UNTIL/COUNT、跨月跨年、DST 固定偏移）、
  `.ics` 字段与转义、取消/例外语义；`CalendarSceneTests` 与 `EASAdapterTests` 回归消费侧。
- **删除测试**：删掉后会议规则会散回 `MailDomain` 与 `CMP-PRES`，日历与导出各写一套重复展开 → 真边界。
- **来源**：`history/decisions/2026-11-24-meeting-domain-split.md`（R77，P1）；原 `Sources/MailDomain/Meeting.swift`，
  2026-11-24 迁至新 target `MeetingDomain`，`Message` 不再携带 `meeting`。
