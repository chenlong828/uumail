---
layer: design
module: store
status: active
updated: 2026-11-14
component: CMP-STORE
---

# CMP-STORE MailStore 组件规格

## 模块卡

- 状态：`active`（schema v8；账号、文件夹、消息、正文、附件、outbox、FTS 读写均已落地）
- 单元：组件
- 层 / 类型：L1a；领域基础（数据服务，唯一写入口）
- 业务价值：为列表、阅读、搜索、发送意图提供**唯一权威本地副本**；没有它，同一封邮件会以三种口径出现在三个模块里。
- 负责 X：schema 与迁移、事务、幂等 upsert、列表查询、正文分表、FTS、软删除、outbox 行的物理读写、账号状态。
- 不负责 Y：网络与协议、MIME 组装、发送状态机（归 `Outbox`）、UI 状态。
- 内部逻辑：批次与 SyncKey 同事务；`(account, folder, serverID)` 幂等；列表查询不扫正文；`claimOutbox` 用 `UPDATE … RETURNING` 单句领取，跨进程不双领。
- 拥有的数据：`accounts`、`folders`、`messages`、`message_bodies`、`attachments`、`sync_state`、`outbox`、`fts`（唯一写入口）。
- 变化轴：存储引擎与查询形态（GRDB → 其它）；换引擎只改本组件内部。
- 公开契约：见契约卡；能力 ID `CMP-STORE#applySyncBatch` 等。
- 入口：`Sources/MailStore/MailStore.swift#MailStore`、`SyncStoreConformance.swift`（`MailStore: SyncStore`）
- 依赖：`MailDomain`、GRDB。扇出 2。
- 冷热：读热、写冷热混合；`DatabaseQueue` 单写。
- 尺寸预算：目标 ≤900 行；当前 852 行（`MailStore.swift` 818 + `SyncStoreConformance.swift` 34，`wc -l` 2026-11-14；此前记 890 为旧值）。
- 单独运行：`./Scripts/swiftw test --filter MailStoreTests`
- 删除测试：删掉后场景、同步、搜索各自拼 SQL 并各自维护 SyncKey → 复杂度分散，是真边界。

## 契约卡：MailStore v8

- 账号：`createAccount(NewAccount)`（`draft`）、`markAccountReady`、`discardAccount`（仅无消息）、`account(_:)`（返回 `displayName/address/host`）、`accounts()`。
- 文件夹与同步：`folders(account:)`、`applyFolderSnapshot(account:folders:syncKey:)`、`applySyncBatch(account:folder:added:changed:removedServerIDs:syncKey:)`、`syncKey(account:collection:)`、`resetCollection(account:folder:)`。
- 读：`messages(account:folder:limit:)`、`body(account:folder:serverID:)`、`attachments(account:folder:messageID:)`、`searchLocal(account:query:limit:)`。
- 正文与附件：`applyBody(account:folder:serverID:html:)`、`markAttachmentCached(account:folder:messageID:fileReference:cachePath:)`。
- outbox：`saveDraft`、`enqueueOutbox`、`pendingOutbox`、`claimOutbox(account:now:lease:)`、`markOutboxSent`、`markOutboxFailed`、`releaseOutbox`、`cancelOutbox`、`outboxItem`。
- 前置 / 后置 / 不变量：批次失败整批回滚且 key 不推进；同键重复写入不产生第二行；列表不扫正文；`claimOutbox` 只领取 `queued`、到期 `failed_retryable`、租约过期 `sending`，并同时写 `sending_since`；成功投递删行。
- 错误模式：`MailStoreError`：`folderNotFound`、`accountNotFound`、`invalidFolder`、`outboxNotClaimable`、`accountNotEmpty`、`database`。
- 幂等 / 顺序 / 并发：批次幂等；单写队列；跨进程靠 SQL 原子更新与租约。
- 超时 / 取消 / 背压：单事务目标 ≤2s；批次大小由 `SyncEngine` 控制。
- 一致性 / 可见性：提交后立即可见；信封与正文同生同灭。
- 兼容性 / 废弃：schema 只前进；v8 只加列/扩取值，旧库可前滚。`MailStore/Values.swift` 仍保留指向 `MailDomain` 的过渡 `typealias`（未删，见 `design/architecture.md` §10）。
- 契约测试：`MailStoreTests` 35 例、`MigrationTests` 1、`PerformanceTests` 1、`Smoke` 1。

## 数据所有权

| 实体 | 唯一写入口 | 写契约 | 读方 | 一致性 |
|---|---|---|---|---|
| accounts | CMP-STORE | `createAccount/markAccountReady/discardAccount` | CMP-SCN-ACCOUNT、CMP-ROOT | 强 |
| folders | CMP-STORE | `applyFolderSnapshot` | CMP-SCN-READ、CMP-SYNC | 强 |
| messages / message_bodies / attachments | CMP-STORE | `applySyncBatch` / `applyBody` / `markAttachmentCached` | 阅读、搜索 | 强 |
| sync_state | CMP-STORE | `applySyncBatch/applyFolderSnapshot/resetCollection` | CMP-SYNC | 强（与批次同事务） |
| outbox | CMP-STORE（行）/ CMP-OUT（状态机） | `enqueueOutbox/claimOutbox/markOutbox*` | CMP-SCN-COMPOSE、CMP-OUT | 强 |
| fts | CMP-STORE | 随批次/正文事务增量 | 搜索 | 最终（同事务） |

本地库为明文 SQLite（WAL + FTS5），附件缓存同样明文；加密依赖 FileVault，不做 SQLCipher、无审计日志——2026-11-09 安全审计的已知接受项（`plan/risks.md` R12）。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| schema v1→v8 迁移（含 `failed` → `failed_retryable`） | ✅ | 迁移 1 例 + 各用例 `inMemory()` |
| `applyFolderSnapshot`（幂等、软删、复活、回滚、未知账号） | ✅ | 6 例 |
| `applySyncBatch`（信封/摘要、幂等、软删、回滚） | ✅ | 5 例 |
| `applyBody` / `body`（正文分表、摘要不冒充正文） | ✅ | 4 例 |
| 附件元数据 + 缓存标记 | ✅ | 随正文/附件路径 |
| outbox 入队/claim/lease/mark/release/cancel | ✅ | 10 例 |
| `searchLocal`（FTS5 trigram；2 字回退 LIKE） | ✅ | 4 例 |
| 账号 `ready`/`discard` | ✅ | 3 例 |
| 旧 `page` / `messageDetail` | ⬜ 未按名实现 | 现行读契约是 `messages(folderID:limit:)` / `body(...)` |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 契约不变量 | 幂等 upsert、批次回滚、key 不推进、租约领取 |
| 失败/降级 | 未知账号/文件夹、非法文件夹、不可领取状态 |
| 冷热隔离 | 读写并发用例与 5k 基线 |
| 数据/迁移 | pre-v8 fixture 前滚；空库建表 |
| 依赖 | 门 1：只 import `Foundation`/`GRDB`/`MailDomain` |

## 开放问题

- 正文裁剪策略（时间窗口 vs 大小）见 `plan/open-questions.md` Q1；未定前不写清理契约。

## 设计增量：schema v9（T-1114-05，待实现）

- v9 只加可空列并重置消息集合游标：

  ```sql
  ALTER TABLE messages ADD COLUMN cc TEXT;
  UPDATE sync_state SET sync_key = '0' WHERE collection <> 'folders';
  ```

  用 `UPDATE` 而非 `DELETE`，保留 `last_sync_at`；`folders` 的 key 不动。`SyncEngine` 已把 `"0"` 当首次同步处理，本组件不改同步引擎。
- `applySyncBatch` 写入 `cc`；`recipients` 与 `cc` 的 UPDATE 用 `COALESCE(excluded..., messages...)`，避免 EAS `Change` 只带 `Read` 时清空已有 To/Cc。新增消息仍可写 `nil`。
- `messages` 与 `searchLocal` 的 SELECT/映射补 `m.recipients`、`m.cc`；现状这两个读路径把已入库的 `recipients` 丢掉了，不补则全部回复只能看到发件人。
- 历史回填：不调用 `resetCollection`（它会删 `messages` 与 `message_bodies`）；迁移后下一次同步按窗口重拉最近 ≤5×25=125 封并 upsert `cc`，正文/附件/附件缓存完全不动。更早邮件保持 `cc = nil`，不伪造；`folders` key 保留（不被回填改写；`SyncEngine` 的 FolderSync 仍按既有逻辑每次全量树）。
- 预算与拆文件：组件总预算保持 900 行；把 v1–v9 迁移注册抽到 `Sources/MailStore/Migrations.swift`（`MailStoreMigrations.register(on:)`），`MailStore.swift` 约 700 行，组件总量约 887 行。T-1114-05 落地时以 `wc -l` 为准；若超 900，先停下并按流程把预算调到 1000，不静默超。
- 迁移测试：pre-v9 fixture 必须含 `messages`、`message_bodies`、`attachments`、`sync_state`（现有 pre-v8 fixture 只建 accounts/outbox，不能直接复用）；断言 `cc` 空可读、正文/附件仍在、消息 key `"0"`、folders key 不变；再 `applySyncBatch` 同一条消息 + Cc 后 `cc` 可读。
- 不新增组件/target；`MailStore` 仍是唯一写入口。
