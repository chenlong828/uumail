---
layer: design
module: global
scope: project:uumail
status: active
updated: 2026-11-24
component: CMP-SYNC-CONTRACT
---

# CMP-SYNC-CONTRACT 同步契约（消息 + 会议）

- **单元 / 层**：组件 / L1 契约（新 target `SyncContract`，依赖 `MailDomain` + `MeetingDomain`）
- **业务价值**：一次 EAS Sync 响应同时带来邮件信封与会议邀请；两者必须同批、同事务落库。把「一个同步批次」定义为
  唯一的契约类型，让网关、同步引擎与存储在同一个类型上对齐，同时把 `MailDomain` 与会议子域隔开。
- **负责 / 不负责**：
  - 负责：`MessageDelta`（新增 `meetings: [MeetingDeltaEntry]`）、`MeetingDeltaEntry`（serverID + 主题 + `MeetingInvite`）、
    `MailGateway`、`MailWriteGateway`、`SyncStore` 三个端口。
  - 不负责：协议编解码（`CMP-EAS`）、端口实现（`CMP-EASADAPTER` / `CMP-STORE`）、同步节奏与重试（`CMP-SYNC`）、
    会议值语义（`CMP-MEETING-DOMAIN`）。
- **数据所有权**：无（只定义类型与端口；没有存储、没有状态）。
- **公开契约**：
  - `MessageDelta { added, changed, removedServerIDs, syncKey, moreAvailable, meetings }`；
    `meetings` 默认 `[]`，与会话批次同事务写入。
  - `MailGateway.fetchMessages(...) -> MessageDelta`：一次响应同时交邮件与会议。
  - `SyncStore.applySyncBatch(account:folder:delta:)`：批次与 `sync_key` 同事务；会议也在这一个事务内写。
  - `MailWriteGateway`：已读/删除写命令仍返回 `MessageDelta`。
- **依赖**：`MailDomain`（`Message`/`Folder`/`AccountID` 等）与 `MeetingDomain`（`MeetingInvite`）；不依赖任何上层。
- **尺寸预算**：≤400 行；当前 **87**（`Sources/SyncContract/SyncContract.swift`，2026-11-24 `wc -l`）。
- **单独运行**：由实现方测试覆盖（无独立测试 target），见下。
- **验证计划**：契约由 `SyncEngineTests`（批次与 key 同事务、写响应）、`MailStoreTests`（会议随批次落库、
  `MeetingStoreTests` 的 `upsertAndRead`/`dtstampMonotonic`/`exceptionMerges`）、`EASAdapterTests`（`delta.meetings`
  = `EASAdapter.meeting` 的映射）共同覆盖；`CompositionTests` 冒烟装配。
- **删除测试**：删掉后 `MailDomain` 要么重新依赖会议子域、要么每个网关/存储各自发明批次类型 → 真边界。
- **来源**：`history/decisions/2026-11-24-meeting-domain-split.md`（R77，P1）；2026-11-24 从 `MailDomain`
  迁出 `MessageDelta` 与三个同步端口。

## 设计增量：草稿写端口与草稿存储端口（REQ-0044，2026-11-27，P3，已实现）

- `MailWriteGateway` 增加 `createDraft/updateDraft/deleteDraft`（参数 `DraftPayload`，返回 `DraftWriteResult`：新 SyncKey 与 Add 的 ServerId）；协议扩展给默认实现抛 `MailError.unsupported`，既有测试假实现不必改。
- 新增 `DraftPayload`、`DraftWriteResult` 与 `DraftSyncStore`（草稿列表/绑定/指纹/采用服务器版/复制/解绑/墓碑/同步键），`MailStore` 在 `DraftSyncStoreConformance.swift` 适配。
