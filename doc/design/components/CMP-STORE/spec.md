---
layer: design
module: store
status: active
updated: 2026-11-14
component: CMP-STORE
---

# CMP-STORE MailStore 组件规格

## 模块卡

- 状态：`active`（schema v9；账号、文件夹、消息、正文、附件、outbox、FTS 读写均已落地）
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
- 尺寸预算：硬上限 1000 行；当前 1000 行（`MailStore.swift` 761 + `Migrations.swift` 161 + `SyncStoreConformance.swift` 40 + `Values.swift` 38，`wc -l` 2026-11-14；T-1114-14 压实到硬上限 1000，未超限）。
- 单独运行：`./Scripts/swiftw test --filter MailStoreTests`
- 删除测试：删掉后场景、同步、搜索各自拼 SQL 并各自维护 SyncKey → 复杂度分散，是真边界。

## 契约卡：MailStore v9

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
- 兼容性 / 废弃：schema 只前进；v9 只加 `messages.cc` 可空列并把非 `folders` 的 `sync_key` 置 `"0"`，旧库可前滚。`MailStore/Values.swift` 仍保留指向 `MailDomain` 的过渡 `typealias`（未删，见 `design/architecture.md` §10）。
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
