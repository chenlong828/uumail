---
layer: design
module: store
status: active
updated: 2026-11-24
component: CMP-OUTBOX-STORE
---

# CMP-OUTBOX-STORE OutboxStore 组件规格

## 模块卡

- 状态：`active`（2026-11-24 由 `T-1124-04` 落地）
- 单元：组件（L1a 数据服务；住 `MailStore` target，**不新增 target**）
- 层 / 类型：L1a；数据
- 业务价值：把「outbox 表的物理读写」从已经超预算的 `MailStore` 剥出来，让每张表只有一个写入口、每个组件各自守 1000 行预算；没有它，日历需求只能在超限的 `MailStore` 上继续加行，或被迫引入跨组件事务。
- 负责 X：outbox 表的行级读写——`enqueue/pending/claim/markSent/markFailed/release/cancel/item`，租约领取 SQL、退避时间与状态列写入、`StoredOutboxItem` 行映射。
- 不负责 Y：投递状态机（`CMP-OUT` 的 `Outbox`）、MIME 组装（`MimeBuilder`）、schema 与迁移（仍由 `MailStore` 的 `MailStoreMigrations` 注册）、邮件/文件夹/正文/附件/同步游标（仍归 `MailStore`）。
- 内部逻辑：所有方法在共享的 `DatabaseQueue` 上执行单条 SQL 或单事务；`claim` 用 `UPDATE … RETURNING` 认领 `queued`/到期 `failed_retryable`/租约过期 `sending`，与既有语义逐字一致（迁移只换位置，不改行为）。
- 拥有的数据：`outbox` 表（唯一写入口）。表仍由 `MailStore` 的 migrator 建立；本组件只读写该表，不碰其它表、不注册迁移。
- 变化轴：投递队列的存储形态（同库共享队列 → 未来独立库/外部队列）。
- 公开契约：`CMP-OUTBOX-STORE#enqueue`、`#pending`、`#claim`、`#markSent`、`#markFailed`、`#release`、`#cancel`、`#item`
- 入口：`Sources/MailStore/OutboxStore.swift#OutboxStore`
- 依赖：`MailDomain`（`OutboxItem`/`Draft`/`AccountID`/`OutboxID`）、GRDB（`DatabaseQueue`）。扇出 2。
- 冷热：冷（投递泵 30s 周期与入队一次），与 UI 热读共享同一队列但事务短。
- 尺寸预算：≤400 行；预计 240 行（现 `MailStore.swift` 的 outbox 段约 210 行 + 行映射）。
- 单独运行：`./Scripts/swiftw test --filter OutboxStoreTests`
- 删除测试：删掉后 outbox SQL 回到 `MailStore`，后者重新超预算且拥有两个无业务关联的数据集 → 复杂度集中，是真边界。

## 契约卡：OutboxStore v1

- 签名（摘要）：

  ```swift
  public struct OutboxStore: Sendable {
      public init(queue: DatabaseQueue)
      public func enqueue(account: AccountID, draft: Draft, state: String) throws -> String
      public func pending(account: AccountID) throws -> [StoredOutboxItem]
      public func claim(account: AccountID, now: Date, lease: Duration) throws -> OutboxItem?
      public func markSent(account: AccountID, outboxID: OutboxID) throws
      public func markFailed(account: AccountID, outboxID: OutboxID, error: String, state: String, nextAttemptAt: Date?) throws
      public func release(account: AccountID, outboxID: OutboxID) throws
      public func cancel(account: AccountID, outboxID: OutboxID) throws
      public func item(account: AccountID, id: OutboxID) throws -> OutboxItem?
  }
  ```

- 不变量：成功投递的行即删除；租约 120s；状态取值沿用 `draft/queued/sending/failed_retryable/failed_permanent/canceled`；`ClientId = outboxID` 不变。
- 错误模式：`MailStoreError.outboxNotClaimable`/`.accountNotFound`/`.database` 原样抛；不重试、不吞错。
- 并发：与 `MailStore` 共享同一 `DatabaseQueue`，跨组件不并发打开第二个连接；单条 SQL 事务。
- 迁移：`v1..v11` 的 outbox 建表/加列全部留在 `MailStoreMigrations`；本组件不注册迁移（避免两套 migrator 争 `grdb_migrations`）。
- 契约测试：`OutboxStoreTests` 从既有 `OutboxTests`/`MailStoreTests` 迁入 10 例（入队、claim 幂等、租约过期、退避、取消、mark*），行为断言逐字沿用。

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 契约不变量 | 租约/幂等/状态机写语义与迁移前逐条一致（用例平移） |
| 失败/降级 | 不可领取状态、未知账号、数据库错误 |
| 冷热/隔离 | 与 `MailStore` 共队列；断言不 import `EASClient`/`Outbox` |
| 数据/迁移 | `MigrationTests` 不回归；v12 只加 `meetings`，不动 outbox |
| 预算 | `wc -l Sources/MailStore/OutboxStore.swift` ≤400；`MailStore` 组件总量降到约 814 行 |

## 设计增量：REQ-0029 前置拆分（2026-11-24，P1 已确认、已实现）

- 用户 2026-11-24 拍板「先拆 MailStore」并选择先拆 outbox；`MailStore` 由 1024 行降到约 814 行，加日历 `meetings` 约 110 行后约 924 行，回到 1000 行以内，不再需要调预算。
- 存储边界：**同一 `mail.sqlite` + 同一 `DatabaseQueue`**；`MailStore` 内部持有 `OutboxStore` 并通过 `public var outbox: OutboxStore` 暴露给组合根，`Outbox` 的依赖从 `MailStore` 换成 `OutboxStore`（签名其余不变）。每张表仍只有一个写入口，事务不跨表。
- 账号/文件夹的拆分不在本批：`sync_state` 同时承载消息游标与文件夹游标，`applySyncBatch`/`applyFolderSnapshot`/`discardAccount` 要求同事务，另立 `W-REFACTOR-02` 先设计事务边界。

## 实现（2026-11-24，T-1124-04）

- `Sources/MailStore/OutboxStore.swift`（210 行）接管 outbox 表全部 SQL；`MailStore` 以 `public let outbox` 暴露，
  与 `MailStore` 共享同一 `DatabaseQueue`。
- `Outbox` 的行级调用改为 `outboxStore`，账号只读仍走 `MailStore`；状态机/租约/退避语义逐字不变
  （`Tests/MailStoreTests/MigrationTests.swift` 与 `OutboxTests` 全绿）。
- `MailStore` 由 1024 行降到 586 行（组件合计 842），为 v12 的约 110 行留出预算。

## 设计增量：草稿行读取、覆盖与转队（REQ-0043，2026-11-27，P3，已实现）

- 来源：`REQ-0043` / `SCN-0031`。草稿沿用既有 `outbox` 表与 `state = 'draft'`，不新增 schema。
- `drafts(account:) -> [DraftRecord]`：`WHERE state = 'draft' ORDER BY updated_at DESC, id DESC`；不含 queued/sending/failed 行。
- `updateDraft(account:draftID:draft:) -> Bool`：`UPDATE … WHERE id = ? AND state = 'draft'`，刷新 `updated_at`；返回 `changesCount == 1`，行不存在时调用方回退为插入。
- `sendDraft(account:draftID:draft:) -> Bool`：同一条 `UPDATE` 写最新正文并置 `is_draft = 0, state = 'queued'`、清 `last_error`/`next_attempt_at`；行 id 即 `ClientId`，草稿不可能既被投递又留在草稿箱。
- 不改 `saveDraft`/`enqueueOutbox`/`pendingOutbox`/claim/租约/退避的既有语义；草稿行不进入投递查询。

## 设计增量：草稿服务器绑定与删除墓碑（REQ-0044，2026-11-27，P3，已实现）

- schema v13：`outbox` 增加 `server_id TEXT`、`draft_hash TEXT`；新表 `draft_tombstones(account_id, server_id, created_at, PRIMARY KEY(account_id, server_id))`。
- 新文件拆分：`OutboxStore+Drafts.swift`（列表/单查/同行更新/删除）与 `OutboxStore+DraftSync.swift`（绑定/改指纹/采用服务器版/插入服务器版/复制/解绑/墓碑），均 ≤300 行。
- 关键语义：`duplicateDraft` 复制成 `server_id = NULL` 的新行（冲突「两份都保留」的本地版本）；`sendDraft`/`deleteDraft` 在**同一事务**里读取 `server_id` 并写 tombstone，保证离线发送/删除后服务器副本最终被删；`draft(account:serverID:)` 供拉取按服务器 id 找本地行。
