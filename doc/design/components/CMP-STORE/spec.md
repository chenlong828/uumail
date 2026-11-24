---
layer: design
module: store
status: active
updated: 2026-11-18
component: CMP-STORE
---

# CMP-STORE MailStore 组件规格

## 模块卡

- 状态：`active`（schema v10；账号、文件夹、消息、正文、附件、outbox、FTS 读写均已落地；v10 为 REQ-0021 的 `outbox.body_html`，本批不改存储）
- 单元：组件
- 层 / 类型：L1a；领域基础（数据服务，唯一写入口）
- 业务价值：为列表、阅读、搜索、发送意图提供**唯一权威本地副本**；没有它，同一封邮件会以三种口径出现在三个模块里。
- 负责 X：schema 与迁移、事务、幂等 upsert、列表查询、正文分表、FTS、软删除、outbox 行的物理读写、账号状态。
- 不负责 Y：网络与协议、MIME 组装、发送状态机（归 `Outbox`）、UI 状态。
- 内部逻辑：批次与 SyncKey 同事务；`(account, folder, serverID)` 幂等；列表查询不扫正文；`claimOutbox` 用 `UPDATE … RETURNING` 单句领取，跨进程不双领。
- 拥有的数据：`accounts`、`folders`、`messages`、`message_bodies`、`attachments`、`sync_state`、`outbox`、`fts`（唯一写入口）。
- 变化轴：存储引擎与查询形态（GRDB → 其它）；换引擎只改本组件内部。
- 公开契约：见契约卡；能力 ID `CMP-STORE#applySyncBatch`、`#markRead`、`#commitMarkRead`、`#commitDelete` 等。
- 入口：`Sources/MailStore/MailStore.swift#MailStore`、`SyncStoreConformance.swift`（`MailStore: SyncStore`）
- 依赖：`MailDomain`、GRDB。扇出 2。
- 冷热：读热、写冷热混合；`DatabaseQueue` 单写。
- 尺寸预算：硬上限 1000 行；当前 **952 行**（`MailStore.swift` 591 + `MailStore+Lookup.swift` 73 + `Migrations.swift` 210 + `SyncStoreConformance.swift` 40 + `Values.swift` 38，2026-11-24 `wc -l`）。2026-11-24 起 `meetings` 读写析出到 `CMP-MEETING-STORE`（287 行），outbox 早已独立到 `CMP-OUTBOX-STORE`；账号/文件夹拆分仍归 `W-REFACTOR-02`。
- 单独运行：`./Scripts/swiftw test --filter MailStoreTests`
- 删除测试：删掉后场景、同步、搜索各自拼 SQL 并各自维护 SyncKey → 复杂度分散，是真边界。

## 契约卡：MailStore v10

- 账号：`createAccount(NewAccount)`（`draft`）、`markAccountReady`、`discardAccount`（仅无消息）、`account(_:)`（返回 `displayName/address/host`）、`accounts()`。
- 文件夹与同步：`folders(account:)`、`applyFolderSnapshot(account:folders:syncKey:)`、`applySyncBatch(account:folder:added:changed:removedServerIDs:syncKey:)`、`syncKey(account:collection:)`、`resetCollection(account:folder:)`；已实现 `markRead(account:folder:serverID:)`、`commitMarkRead(account:folder:serverID:delta:)`、`commitDelete(account:folder:serverID:delta:)`（T-1114-14；见文末设计增量）。
- 读：`messages(account:folder:limit:)`、`body(account:folder:serverID:)`、`attachments(account:folder:messageID:)`、`searchLocal(account:query:limit:)`。
- 正文与附件：`applyBody(account:folder:serverID:html:)`、`markAttachmentCached(account:folder:messageID:fileReference:cachePath:)`。
- outbox：`saveDraft`、`enqueueOutbox`、`pendingOutbox`、`claimOutbox(account:now:lease:)`、`markOutboxSent`、`markOutboxFailed`、`releaseOutbox`、`cancelOutbox`、`outboxItem`。
- 前置 / 后置 / 不变量：批次失败整批回滚且 key 不推进；同键重复写入不产生第二行；列表不扫正文；`claimOutbox` 只领取 `queued`、到期 `failed_retryable`、租约过期 `sending`，并同时写 `sending_since`；成功投递删行。`markRead` 只做本地 0→1，不改 key、不触网；`commitMarkRead`/`commitDelete` 把「写响应 delta + 本地效果 + 新 key」放在同一事务，任一步失败整批回滚、key 不推进；目标行不存在时仍提交 delta/key，本地效果幂等为 no-op。
- 错误模式：`MailStoreError`：`folderNotFound`、`accountNotFound`、`invalidFolder`、`outboxNotClaimable`、`accountNotEmpty`、`database`。
- 幂等 / 顺序 / 并发：批次幂等；单写队列；跨进程靠 SQL 原子更新与租约。
- 超时 / 取消 / 背压：单事务目标 ≤2s；批次大小由 `SyncEngine` 控制。
- 一致性 / 可见性：提交后立即可见；信封与正文同生同灭。
- 兼容性 / 废弃：schema 只前进；v9 只加 `messages.cc` 可空列并把非 `folders` 的 `sync_key` 置 `"0"`，v10 只加 `outbox.body_html` 可空列（REQ-0021），v11 只加 `attachments.content_id` 可空列（REQ-0025，2026-11-21），旧库可前滚。`MailStore/Values.swift` 仍保留指向 `MailDomain` 的过渡 `typealias`（未删，见 `design/architecture.md` §10）。
- 契约测试：`MailStoreTests` 38 例、`MigrationTests` 2、`PerformanceTests` 1、`Smoke` 1。

## 数据所有权

| 实体 | 唯一写入口 | 写契约 | 读方 | 一致性 |
|---|---|---|---|---|
| accounts | CMP-STORE | `createAccount/markAccountReady/discardAccount` | CMP-SCN-ACCOUNT、CMP-ROOT | 强 |
| folders | CMP-STORE | `applyFolderSnapshot` | CMP-SCN-READ、CMP-SYNC | 强 |
| messages / message_bodies / attachments | CMP-STORE | `applySyncBatch` / `applyBody` / `markAttachmentCached`；`markRead/commitMarkRead/commitDelete`（T-1114-10 设计，2026-11-14 已实现） | 阅读、搜索 | 强 |
| sync_state | CMP-STORE | `applySyncBatch/applyFolderSnapshot/resetCollection`；`commitMarkRead/commitDelete`（T-1114-10 设计，2026-11-14 已实现） | CMP-SYNC | 强（与批次/写提交同事务） |
| outbox | CMP-STORE（行）/ CMP-OUT（状态机） | `enqueueOutbox/claimOutbox/markOutbox*` | CMP-SCN-COMPOSE、CMP-OUT | 强 |
| fts | CMP-STORE | 随批次/正文事务增量 | 搜索 | 最终（同事务） |

本地库为明文 SQLite（WAL + FTS5），附件缓存同样明文；加密依赖 FileVault，不做 SQLCipher、无审计日志——2026-11-09 安全审计的已知接受项（`plan/risks.md` R12）。

## 设计增量：附件 ContentId（REQ-0025 / SCN-0019，2026-11-21）

- v11：`ALTER TABLE attachments ADD COLUMN content_id TEXT`（additive、forward-only）。
- `applySyncBatch` 的附件 upsert 写入 `content_id`；冲突时
  `content_id = COALESCE(excluded.content_id, attachments.content_id)`，避免只带信封的 `Change` 清空已有值。
  `attachments(...)` 的 SELECT 读回该列。
- 旧行（v11 之前同步）保持 `NULL`，不伪造；v11 同时把非 `folders` 的 `sync_key` 置 `"0"`，升级后首轮
  按窗口重拉最近 ≤125 封并 upsert，`content_id` 随之补齐（正文与附件缓存不动，机制同 v9）。
- 迁移测试：pre-v9 fixture 打开后旧附件读 `nil`；同一消息重新 `applySyncBatch`（带 `contentID`）后可读；
  另断言省略 `ContentId` 的 upsert 不清掉已存值。`MailStoreTests` 同步补 round-trip 用例。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| schema v1→v9 迁移（含 `failed` → `failed_retryable`、消息游标回填） | ✅ | 迁移 2 例 + 各用例 `inMemory()` |
| `applyFolderSnapshot`（幂等、软删、复活、回滚、未知账号） | ✅ | 6 例 |
| `applySyncBatch`（信封/摘要、幂等、软删、回滚、To/Cc 写入与 COALESCE） | ✅ | 7 例 |
| `applyBody` / `body`（正文分表、摘要不冒充正文） | ✅ | 4 例 |
| 附件元数据 + 缓存标记 | ✅ | 随正文/附件路径 |
| outbox 入队/claim/lease/mark/release/cancel | ✅ | 10 例 |
| `searchLocal`（FTS5 trigram；2 字回退 LIKE；带回 To/Cc） | ✅ | 5 例 |
| 账号 `ready`/`discard` | ✅ | 3 例 |
| `markRead` / `commitMarkRead` / `commitDelete` | ✅ 已实现（T-1114-14，2026-11-14） | 覆盖：只改目标行、已读幂等、delta+本地效果+key 同事务、回滚不推进 key、重复软删幂等、正文/附件不动、partial echo 不清空目标信封 |
| 旧 `page` / `messageDetail` | ⬜ 未按名实现 | 现行读契约是 `messages(folderID:limit:)` / `body(...)` |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 契约不变量 | 幂等 upsert、批次回滚、key 不推进、租约领取 |
| 失败/降级 | 未知账号/文件夹、非法文件夹、不可领取状态 |
| 冷热隔离 | 读写并发用例与 5k 基线 |
| 数据/迁移 | pre-v8 / pre-v9 fixture 前滚；空库建表 |
| 依赖 | 门 1：只 import `Foundation`/`GRDB`/`MailDomain` |

## 开放问题

- 正文裁剪策略（时间窗口 vs 大小）见 `plan/open-questions.md` Q1；未定前不写清理契约。

## 设计增量：schema v9（T-1114-05，已实现 2026-11-14）

- v9 只加可空列并重置消息集合游标：

  ```sql
  ALTER TABLE messages ADD COLUMN cc TEXT;
  UPDATE sync_state SET sync_key = '0' WHERE collection <> 'folders';
  ```

  用 `UPDATE` 而非 `DELETE`，保留 `last_sync_at`；`folders` 的 key 不动。`SyncEngine` 已把 `"0"` 当首次同步处理，本组件不改同步引擎。
- `applySyncBatch` 写入 `cc`；`recipients` 与 `cc` 的 UPDATE 用 `COALESCE(excluded..., messages...)`，避免 EAS `Change` 只带 `Read` 时清空已有 To/Cc。新增消息仍可写 `nil`。
- `messages` 与 `searchLocal` 的 SELECT/映射补 `m.recipients`、`m.cc`；此前这两个读路径会把已入库的 `recipients` 丢掉，不补则全部回复只能看到发件人。
- 历史回填：不调用 `resetCollection`（它会删 `messages` 与 `message_bodies`）；迁移后下一次同步按窗口重拉最近 ≤5×25=125 封并 upsert `cc`，正文/附件/附件缓存完全不动。更早邮件保持 `cc = nil`，不伪造；`folders` key 保留（不被回填改写；`SyncEngine` 的 FolderSync 仍按既有逻辑每次全量树）。
- 预算与拆文件：组件总预算 1000 行（T-1114-05 实测 916 行后由 900 上调）；v1–v9 迁移注册抽到 `Sources/MailStore/Migrations.swift`（`MailStoreMigrations.register(on:)`），`MailStore.swift` 683 行、`Migrations.swift` 161 行，组件总量 1000 行（`wc -l` 2026-11-14，T-1114-14 后压实到硬上限）。
- 迁移测试：pre-v9 fixture 含 `messages`、`message_bodies`、`attachments`、`sync_state`；pre-v8 fixture 补建 `messages`/`sync_state` 以同跑 v8+v9。断言 `cc` 空可读、正文/附件仍在、消息 key `"0"`、folders key 不变；再 `applySyncBatch` 同一条消息 + Cc 后 `cc` 可读。
- 不新增组件/target；`MailStore` 仍是唯一写入口。

## 设计增量：本地置读与写成功提交（T-1114-10，2026-11-14 设计；T-1114-14 已实现）

- 新增三个公开方法，schema 不变（仍 v9；不建 `pending_op`、不加 `read_dirty`）：

  ```swift
  public func markRead(account: AccountID, folder: String, serverID: String) throws -> Bool
  public func commitMarkRead(account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws
  public func commitDelete(account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws
  ```

- `markRead`：本地事务只做
  `UPDATE messages SET is_read = 1, updated_at = ? WHERE account_id = ? AND folder_id = ? AND server_id = ? AND is_read = 0 AND deleted_at IS NULL`；
  `changesCount == 1` 表示刚发生 0→1；不改 `sync_state`、不触网、不动正文/附件/FTS。
- `commitMarkRead` / `commitDelete`（服务器写成功后调用，三者同事务）：
  1. 校验账号与文件夹（与 `applySyncBatch` 相同）；
  2. 应用 `delta.added/changed/removedServerIDs`，复用既有 upsert、软删、附件元数据、preview、FTS 与 `deleted_at = NULL` 复活逻辑；
  3. 施加本地效果：`is_read = 1`（markRead）或 `deleted_at = now`（delete，已删则 no-op）；
  4. 写 `sync_state.sync_key = delta.syncKey`；
  5. 任一步抛错整批回滚，key 不推进。
- 顺序：先应用响应 delta，再施加本地效果；服务器回包里的 `Read=0`/复活不得覆盖本次本地置读/删除。目标行不存在时仍提交 delta 与 key，本地效果幂等为 no-op（不伪造行）。
- **目标行保护**：`commitMarkRead`/`commitDelete` 应用 delta 时先排除目标 `serverID` 的 `added/changed`（写命令的 partial echo 可能只带 `Read`/`ServerId`，若直接 upsert 会用 nil 清空 `subject`/`sender`/`received_raw`）；`removedServerIDs` 仍应用，其他消息照常 apply。目标由本地效果决定，不靠回包重建。
- 既有边界（本批不改）：普通 `applySyncBatch` 只对 `recipients`/`cc`/`preview` 用 `COALESCE`，`subject`/`sender`/`received_raw` 仍可能被 partial `Change` 的 nil 覆盖。本批只在 `commit*` 保护写路径目标；若要在普通同步统一 COALESCE，属 SCN-0003 的语义变更，另立 CMP-STORE 任务（R21）。
- 删除只软删 `messages`，不删 `message_bodies`/`attachments`/FTS 行；列表与搜索的 `deleted_at IS NULL` 过滤不变。
- 复用：把 `applySyncBatch` 的批次应用逻辑抽成私有 `applyDelta(db, account:folder:delta:)`，`applySyncBatch` 与 `commit*` 共用，避免复制 upsert/软删/附件/FTS 规则；`applySyncBatch` 的公开签名不变。
- 端口遵循：`Sources/MailStore/SyncStoreConformance.swift` 增三个 `_ account:` 转发器，调用上述 `account:` 版本（与现有 `folders`/`applySyncBatch` 等 5 个转发器同构）；`MailStore` 仍可直接调用自己的 `account:` 版本。
- 预算：T-1114-14 实测组件 **1000 行**（硬上限 1000，未超）；通过共享 `applyDelta` helper 与压缩注释把净增收敛。`MailStoreTests` 48 例绿。
- 并发：`DatabaseQueue` 单写；`commit*` 的原子性由 `dbQueue.write` 保证；与 `SyncEngine` 的门配合，不假设跨进程锁。
- 测试：`MailStoreTests` 补「只改目标行」「已读幂等」「commit 与 key 同事务」「rollback 不推进 key」「重复软删幂等」「正文/附件表不动」「partial echo 不清空目标 subject/sender/date」；`MigrationTests` 不新增（无 schema 变更）。

**实现（2026-11-14）**：`applySyncBatch` 与两个 `commit*` 共用 `applyDelta`；目标 `serverID` 的 `added/changed` 在写路径被排除，`removedServerIDs` 仍应用；`markRead` 只改目标未读行。`MailStoreTests` 48 例绿（写路径 6 例），组件总量 1000 行。

## 设计增量：outbox v10 body_html（REQ-0021，2026-11-17）

- 新增迁移 `v10_outbox_html`：`ALTER TABLE outbox ADD COLUMN body_html TEXT`。additive、forward-only；旧行保持 `NULL`，读出为 `OutboxItem.bodyHTML == nil`，投递仍走单段 `text/plain`。
- 写路径：`enqueueOutbox` 的 INSERT 增加 `body_html`（来自 `Draft.bodyHTML`，可为 NULL）；`pendingOutbox`/`claimOutbox RETURNING`/`outboxItem`/`outboxItem(row:)` 全部带该列。`saveDraft` 复用同一写路径，草稿行同样保留 HTML。
- 不变量：`body` 列仍必填；`body_html` 只在有 HTML 时写；schema 变更不改 `messages`/`message_bodies`/FTS/附件；不新增第二写入口。
- 测试：`ScenesTests/ComposeSceneTests.replyAllUsesBackfilledCc` 的 pre-v9/v10 fixture 读到旧草稿 `bodyHTML == nil`；`OutboxTests/OutboxDeliveryTests.deliversHTML` 验证入队读出 HTML 并投递；`MigrationTests` pre-v9 fixture 已补 outbox 表，v10 在旧库上可执行。

## 设计增量：收件人联想不改本组件（REQ-0022 / SCN-0017，2026-11-18）

- **不改 schema**：不建 `contacts` 表、不注册 v11、不回填、不改 `applySyncBatch` 的 upsert；schema 保持 v10。
- **不加查询**：`ComposeScene.recipientDirectory(account:)` 复用既有只读契约 `folders(account:)` 与 `messages(account:folder:limit:)`，按文件夹取信封后在 `Scenes`/`MailDomain` 内存聚合；本组件不新增 public 方法、不新增 SQL。
- **预算**：本批对 `MailStore` 目标新增 0 行；既有 1008/1000 的 8 行超出与本批无关，登记 R45。若后续要把联系人做成持久派生表（v11 `contacts` + 回填 + upsert），先按 P1 立项、拆分 `MailStore` 或调预算，再动本组件。
- **数据所有权**：`messages` 仍是 `CMP-STORE` 唯一写入口；联系人目录是会话内只读投影，不持久、不是第二真相；旧邮件清理、未同步文件夹或超出 500/文件夹、5,000 总计上限后名字/联系人不出现，已在 `SCN-0017` 失败路径、R46 与决策记录中接受。
- **验证**：本组件无新增测试；`MailStoreTests` 既有用例不回归即可。聚合行为由 `ScenesTests/ComposeSceneTests.recipientDirectory*` 覆盖。

## 设计增量：schema v12 会议邀请（REQ-0029 / REQ-0030，2026-11-24，P1 已确认、已实现）

- 来源：`REQ-0029`（日历视图）/`REQ-0030`（会议卡与导出）；数据来自 EAS `Sync` 信封里的 `MessageClass`+`MeetingRequest`（见 `CMP-EAS` 增量），由 `applySyncBatch` 在同一事务落库。
- **新表**（`Migrations.swift` 注册 `v12_meetings`）：

  ```sql
  CREATE TABLE meetings (
      account_id TEXT NOT NULL,
      uid TEXT NOT NULL,
      folder_id TEXT NOT NULL,          -- 来源邮件（用于跳回与导出）
      server_id TEXT NOT NULL,
      subject TEXT,
      start_utc REAL NOT NULL,
      end_utc REAL NOT NULL,
      is_all_day INTEGER NOT NULL DEFAULT 0,
      location TEXT,
      organizer TEXT,
      reminder_minutes INTEGER,
      response_requested INTEGER NOT NULL DEFAULT 0,
      busy_status INTEGER,
      message_type INTEGER NOT NULL,    -- 1 初始 / 2 更新 / 3 信息 / 4 过期 / 5/6 委派
      is_cancelled INTEGER NOT NULL DEFAULT 0,
      dtstamp REAL,
      timezone_name TEXT,
      timezone_offset_minutes INTEGER,
      recurrence TEXT,                  -- JSON 编码的 RecurrenceRule；NULL = 单次
      updated_at REAL NOT NULL,
      PRIMARY KEY (account_id, uid)
  );
  CREATE INDEX idx_meetings_range ON meetings(account_id, start_utc);
  ```

  以 `uid` 为键（不是 `(folder, server)`）：同一会议会有「新建 / 更新 / 取消」多封邀请，视图只能出现一条。
- **写入**（`applyDelta` 内，与信封 upsert 同一事务）：
  - `added/changed` 里 `message.meeting != nil` → `INSERT … ON CONFLICT(account_id, uid) DO UPDATE`，仅当 `excluded.dtstamp >= meetings.dtstamp`（`NULL` 视为最旧）才覆盖，避免迟到的旧邀请盖掉新时间；
  - `message.meeting.isCancelled == true` 或 `messageType == .outdated` → `DELETE FROM meetings WHERE account_id = ? AND uid = ?`；该邮件信封仍然入库（用户还能在列表里看到「已取消」邮件）；
  - `removedServerIDs` → 删除 `folder_id/server_id` 匹配的行（同一 `uid` 的另一封邀请保留）；
  - 会议邮件被软删（`messages.deleted_at`）不删会议行：删除是本地软删，日历以「最新一封邀请」为准；若最新一封被删，下一次同步的更新/取消会修正。
- **读**（`MailStore` 新方法，住 `Sources/MailStore/MailStore+Meetings.swift`，约 90 行）：
  - `meetings(account:from:to:limit:) throws -> [MeetingOccurrence]`：`start_utc <= to AND (recurrence IS NOT NULL OR end_utc >= from)`，`is_cancelled = 0 AND message_type != 4`，`ORDER BY start_utc`，`LIMIT`；`subject` 从 `messages` 按 `(folder_id, server_id)` join，缺失时用会议行自带 `subject`；
  - `meeting(account:uid:) throws -> MeetingInvite?`；
  - `meeting(account:uid:) throws -> MeetingInvite?`（阅读页卡片按 `uid` 取）；
  - **列表读**：`messages(folderID:limit:)` 与 `searchLocal` 的 SELECT 左连 `meetings`（按 `folder_id`+`server_id`）填 `Message.meeting`，卡片不再二次查库；连接走 `idx_meetings_range` 之外的 `(account_id, folder_id, server_id)` 主键等值，单页 ≤200 行。
- **迁移**：`v12_meetings` 建表 + 索引；同时把非 `folders` 的 `sync_key` 置 `"0"`（沿用 v9/v11 机制），升级后首轮按窗口重拉最近 ≤125 封补齐会议行；正文/附件缓存不动。旧邮件不会被伪造会议。
- **迁移测试**（`MailStoreTests/MigrationTests`）：pre-v12 fixture 打开后可建表、旧邮件可读、游标归零；新库直建；重复 `applySyncBatch` 幂等；迟到旧邀请不覆盖新时间；取消删除行但邮件保留。
- **预算（2026-11-24 拆分后实测）**：`CMP-STORE` **952/1000**（`MailStore.swift` 591 + `MailStore+Lookup.swift` 73 + `Migrations.swift` 210 + `SyncStoreConformance.swift` 40 + `Values.swift` 38）；`MailStore+Meetings.swift`（273 行）已拆为 `MeetingStore+Read.swift` 140 + `MeetingStore+Write.swift` 147，并归 `CMP-MEETING-STORE`（≤400）。账号/文件夹拆分仍另立 `W-REFACTOR-02`，本批不夹带。
- **不变量**：`MailStore` 仍是唯一写入口；会议行只随同步事务写；不改 `messages`/`message_bodies`/FTS/附件 schema；不新增第二写入口。

## 设计增量：启用 WAL（2026-11-24，人工确认）

- 现状与文档不一致：`MailStore` 用 `DatabaseQueue(path:)` 的默认配置，2026-11-24 复制库实测 `PRAGMA journal_mode = delete`，而架构与组件规格从 2026-11-09 起一直写「WAL + FTS5」。
- 决定：`MailStore.init(path:)` 显式配置 `Configuration.journalMode = .wal`（仍用 `DatabaseQueue`，单连接串行；不开 `DatabasePool`）。WAL 模式是持久化在库文件里的，旧库首次打开即切换；`-wal`/`-shm` 副文件出现在库旁边。
- 影响：崩溃恢复更好、写少阻塞读（单队列下仍串行）；备份必须同时带上 `mail.sqlite`、`mail.sqlite-wal`（如有）、`mail.sqlite-shm`，或改用 `VACUUM INTO` 导出一致副本；关闭连接时 GRDB 默认 checkpoint。
- 测试：`inMemory()` 库不支持 WAL，配置需按路径分支（内存库保持默认），既有用例不改；新增一条「文件库打开后 `PRAGMA journal_mode` 为 `wal`」的断言。
- 不改：任何表的 schema、迁移顺序、API 签名；不改 `DatabaseQueue` → `DatabasePool`（读写真并发另立 P1）。

## 设计增量：outbox 物理读写拆出（2026-11-24，P1，人工确认）

- 新组件 `CMP-OUTBOX-STORE`（住 `MailStore` target，`Sources/MailStore/OutboxStore.swift`）接管 `outbox` 表的全部 SQL；`MailStore` 内部持有实例并以 `public var outbox: OutboxStore` 暴露给组合根，`Outbox` 的依赖由 `MailStore` 换成 `OutboxStore`（状态机与 MIME 不动）。
- 表仍由 `MailStoreMigrations` 建立（v1..v11 的 outbox 迁移不搬），避免两套 migrator 争 `grdb_migrations`；本组件不注册迁移。
- 同一 SQLite、同一 `DatabaseQueue`：每张表一个写入口，事务不跨表；跨组件不另开连接。
- 拆分收益：`MailStore` 约 1024 → 814 行，为 `meetings`（约 110 行）腾出空间，预算保持 1000；`OutboxStore` 单独 ≤400 行。
- 测试迁移：`OutboxTests`/`MailStoreTests` 中 outbox 行级用例平移到 `OutboxStoreTests`，断言逐字保留；`CompositionTests` 只改装配引用。

## 实现（2026-11-24，T-1124-03/04/08）

- WAL：`MailStore.init` 设置 `Configuration.journalMode = .wal`（文件库），新增 `DatabaseJournalModeTests` 2 例。
- outbox 拆出：`OutboxStore.swift`（210 行）+ `MailStore.outbox`；`Outbox` 依赖切换；`MailStore` 586 行。
- v12：`v12_meetings` 建表/索引；`applySyncBatch` 同事务 upsert（`DtStamp` 只升不降）、取消删除、例外合并；
  `MailStore+Meetings.swift` 提供 `meetings(account:from:to:limit:)`/`meetingInvite(account:uid:)`，列表页左连会议。
- 不回填：迁移不重置游标（与 v9/v11 不同），`MEETING` 历史为空是已确认口径。
- 测试：`MeetingStoreTests` 6 例 + `MigrationTests` v12 1 例 + WAL 2 例；`MailStore` 59 tests 全绿。
## 设计增量：按引用取单封与列表时间窗（REQ-0031 / REQ-0033，2026-11-24，P1 已确认）

- 触发：浮动阅读窗要打开「不在当前列表页」的邮件（日历旧邀请、其它文件夹），列表则要从「取 200 条」改为「最近 30 天全部」。
- 决定（`history/decisions/2026-11-24-floating-reader-window.md` D12，P1 已人工确认）：新增两个只读查询，均为 additive，
  不改既有查询签名、不改 schema。
- 新契约（`CMP-STORE` 公开方法，`MailStore`）：
  - `message(account: AccountID, folder: String, serverID: String) throws -> StoredMessage?`
    - SQL：`SELECT ... FROM messages WHERE account_id = ? AND folder_id = ? AND server_id = ? LIMIT 1`；
    - 命中主键/唯一索引路径，返回单行或 nil；不返回错误（只有数据库层失败抛 `storage`）。
  - `messages(account: AccountID, folder: String, since: Date) throws -> [StoredMessage]`
    - SQL：`... WHERE account_id = ? AND folder_id = ? AND julianday(received_raw) >= julianday(?) ORDER BY received_raw DESC`；
    - **不带 LIMIT**（`REQ-0033` 明确不封顶）；`since` 由 `CMP-SCN-READ` 计算，本层不猜自然日。
    - 窗口比较用 `julianday` 而不是字符串 `>=`：`received_raw` 是网关原样字符串（实测 `2026-11-18T02:00:00Z`，
      也可能带毫秒 `.000Z`），混格式时字符串比较会在边界上错一秒；`julianday` 接受 `Z` 后缀，
      代价是 `(account_id, folder_id, received_raw DESC)` 索引只用于排序段、过滤段为范围扫描——5,000 行量级已由
      `SCN-0026` 的 1s 阈值兜住，不做表达式索引或新增列（避免 schema 变更，见 D12 的「不改 schema」）。
  - 既有 `messages(account:folder:limit:)` 保留，`MailboxViewModel` 不再调用它（`SCN-0004`/`SCN-0009` 不依赖该默认值）。
- 不变量：
  - `received` 时间解析沿用既有 `StoredMessage` 映射（服务器 `DateReceived` 原样字符串 → `Date` 的既有解析器），
    本增量不新造时间解析规则；解析失败的行与既有列表一致地按「无时间」排序兜底。
  - 单封读取与时间窗读取都只读，不写、不改 `sync_state`。
- 预算：`MailStore.swift` 当前约 814 行（2026-11-24），本增量约 +45 行，组件 ≤1,000 行不调；
  新查询放既有文件（与 `messages(account:folder:limit:)` 相邻），不新增文件。
- 验证（`MailStoreTests` 新增）：
  - 命中 / 不存在 / 同 serverID 跨文件夹不串（复合键）；
  - `since` 边界：等于 `since` 的行包含、早 1 秒排除；空文件夹返回空数组；
  - 排序为 `received` 倒序；5,000 行夹具下两种查询的耗时被记录（`T-SCN-0026-03` 复用）。

## 实现（2026-11-24，T-1124-17）

- 新文件 `Sources/MailStore/MailStore+Lookup.swift`（73 行）：`message(account:folder:serverID:)`（单行、`LIMIT 1`、
  软删排除）与 `messages(account:folder:since:)`（`julianday` 窗口、无 LIMIT、时间倒序、无法解析的时间保留）。
  新查询放新文件而不是 `MailStore.swift`，因为后者已 591 行且组件整体超预算（R45）。
- 测试：`Tests/MailStoreTests/MessageLookupTests.swift` 4 例（单封命中/缺失/跨文件夹同 id/软删不可见、
  窗口边界含等值秒、250 行不被截断、排序、文件夹隔离）；`PerformanceTests.windowBaseline`
  在 5,000 封窗口内数据上实测 `messages(since:)` **0.047s / 5,000 行**（阈值 1s）。
- 既有 `messages(account:folder:limit:)` 保留但不再被列表调用；`MessageLookupTests` 同时钉住它的旧形状。

## 实现（2026-11-24，R77 会议契约解耦）

- `MessageDelta` 与同步端口迁至 `CMP-SYNC-CONTRACT`；`MailStore` 仍实现 `SyncStore`（新增 `import SyncContract`）。
- 读侧不再 `attachMeetings`：`messages(account:folder:limit:)` / `messages(account:folder:since:)` / `message(account:folder:serverID:)`
  与搜索都只返回 `Message`；邀请卡改走 `MailStore.meeting(account:folder:serverID:)`（由 `CMP-MEETING-STORE` 提供）。
- 写侧 `applySyncBatch(account:folder:added:changed:removedServerIDs:syncKey:meetings:)` 新增 `meetings`（默认 `[]`），
  `MessageDelta.meetings` 在 `applyDelta` 的同一事务内写入；`CMP-STORE` 实测 952/1000 不变。

