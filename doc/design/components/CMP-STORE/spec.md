---
layer: design
module: store
status: active
updated: 2026-11-09
component: CMP-STORE
---

# CMP-STORE MailStore 组件规格

## 模块卡

- 状态：`active`（schema v1 与文件夹快照已落地；消息、正文、outbox、FTS 未实现）
- 单元：组件
- 层 / 类型：L1a；领域基础（数据服务）
- 业务价值：为列表、阅读、搜索、发送占位提供**唯一权威本地副本**；没有它，同一封邮件会以三种口径出现在三个模块里。
- 负责 X：schema 与迁移、事务、幂等 upsert、游标分页、正文与列表分表、FTS 索引维护、软删除。
- 不负责 Y：网络与协议、MIME 组装、通知策略、UI 状态。
- 内部逻辑：同一账号同一集合的 Sync 批次「数据变更 + SyncKey 推进」在一个事务内完成；`upsert` 以 `(account_id, folder_id, server_id)` 幂等；`page` 用 `(received_at, server_id)` 游标而非 offset。
- 拥有的数据：`accounts`、`device_profiles` 之外的全部业务表——`folders`、`messages`、`message_bodies`、`attachments`、`sync_state`、`outbox`、`fts`。`device_profiles` 由 CMP-EAS 的 DeviceProfileStore 写。
- 变化轴：本地存储引擎与查询形态（GRDB/SQLite → 其它）。换引擎只改适配器与本组件内部，不牵动契约。
- 公开契约：见下节契约卡，能力 ID 形如 `CMP-STORE#applySyncBatch`。
- 入口：`Sources/MailStore/MailStore.swift#MailStore`（planned，落地时校验符号）
- 依赖：SQLiteAdapter（GRDB）、Clock、值类型（Folder/MessageEnvelope/SyncKey）。扇出 ≤ 4。
- 冷热：读热（列表分页、详情、搜索）、写冷（同步批次、发信结果）；单写 actor，读走只读连接（WAL）。
- 尺寸预算：≤ 120k token（源码 + 规格 + 测试）；当前 0。
- 单独运行：`swift test --filter MailStoreTests`（planned；骨架入库后此命令为验收入口）
- 删除测试：删掉则 UI、同步、搜索各自拼 SQL 并各自维护 SyncKey → 复杂度分散且不一致，是真边界。

## 契约卡：MailStore v1（planned）

- 所属模块 / 目的：持久化邮件事实，让读路径不触网。
- 签名（只用本方稳定类型）：
  - `applySyncBatch(account: AccountID, folder: FolderID, adds: [MessageEnvelope], changes: [MessageEnvelope], deletes: [ServerID], newSyncKey: SyncKey) throws`
  - `applyFolderSnapshot(account: AccountID, folders: [Folder], removed: [ServerID]) throws`
  - `page(folder: FolderID, before: Cursor?, limit: Int) throws -> Page`
  - `messageDetail(id: MessageID) throws -> MessageDetail?`
  - `searchLocal(query: String, limit: Int) throws -> [MessageHit]`
  - `enqueueOutbound(_ request: SendRequest) throws -> OutboxID`
  - `markOutboundResult(id: OutboxID, result: SendResult) throws`
- 前置 / 后置 / 不变量：
  - 批次失败整批回滚，`sync_state.sync_key` 保持旧值；
  - 同一 `(account, folder, server_id)` 重复写入不产生第二行；
  - 列表查询不扫正文表；`deleted_at` 软删除与服务器删除同步。
- 错误模式：`conflict`（同键不同内容，保留服务器版本并记日志）、`staleCursor`（游标失效，返回首页）、`storageFull`（可重试，提示清理）、`corruptIndex`（重建 FTS 后可重试）。前三个不可重试，后者可重试一次。
- 幂等 / 顺序 / 并发：批次幂等；同集合串行写；读连接可并发，WAL 下不阻塞写。
- 超时 / 取消 / 背压：单事务 ≤ 2s；超过则拆批（由调用方 CMP-SYNC 决定批次大小）。
- 一致性 / 可见性：提交后立即可见（读己之写）；跨表事务保证信封与正文同生同灭。
- 兼容性 / 废弃：schema 迁移只前进；破坏性变更按 P1 处理。
- 契约测试：重复批次、半批失败、key 不推进、并发读写、1 万封分页、FTS 命中与重建。

## 数据所有权

| 实体 | 唯一写入口 | 写契约 | 读方 | 一致性 |
|---|---|---|---|---|
| folders | CMP-STORE | `applyFolderSnapshot` | CMP-SYNC、UI | 强一致 |
| messages / message_bodies / attachments | CMP-STORE | `applySyncBatch` | UI、搜索 | 强一致 |
| sync_state | CMP-STORE | `applySyncBatch` | CMP-SYNC | 强一致（与批次同事务） |
| outbox | CMP-STORE | `enqueueOutbound` / `markOutboundResult` | CMP-OUT、UI | 强一致 |
| fts | CMP-STORE | 随批次事务增量更新 | 搜索 | 最终一致（≤ 1 批次延迟） |

### 实现进度（2026-11-09）

| 契约 | 代码 | 测试 |
|---|---|---|
| schema v1：accounts / device_profiles / folders / sync_state | ✅ | 迁移随 `MailStore.inMemory()` 走通 |
| `applyFolderSnapshot` | ✅ | 幂等、软删、复活、回滚、未知账号 |
| `applySyncBatch` | ✅ | 5 个用例 |
| `applyBody` / `body`（正文分表，HTML 标记） | ✅ | 2 个用例 |
| `attachments` 元数据表 + 缓存标记 | ✅ | 随正文/同步用例 |
| outbox / 草稿（入队、失败重试、草稿不排队） | ✅ | 3 个用例 |
| `searchLocal`（FTS5 trigram；≥3 字走索引，2 字回退 LIKE） | ✅ | 4 个用例 |
| `page` / `messageDetail` | ⬜ | — |

`createAccount` 目前返回 `draft` 态账号；账号状态机随 UI 工序补齐。

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 契约不变量 | `MailStoreTests`：幂等 upsert、批次回滚、key 不推进 |
| 失败/降级 | 注入存储错误、磁盘满、索引损坏；断言可重试分类 |
| 冷热隔离 | 写事务进行时并发读列表，P95 不劣化 |
| 数据/迁移 | 空库建表、旧版本迁移、双写回放 |
| 观测 | `batch_size`、`sync_duration`、`fts_rebuild_count` |

## 开放问题

- 正文裁剪策略（按时间窗口还是按大小）见 `plan/open-questions.md` Q1，M1 用真实邮箱规模定后写回本组件。
- `outbox` 表与 CMP-OUT 的所有权边界：表由本组件持有，状态机归 CMP-OUT（见 R10 与 CMP-OUT 规格）。
