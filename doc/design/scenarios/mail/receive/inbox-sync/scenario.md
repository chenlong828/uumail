---
layer: design
module: mail
status: designed
updated: 2026-11-17
flow: mail/receive
scenario: SCN-0003
---

# SCN-0003 收件箱增量同步

**结果**：收件箱新邮件在一次同步后出现在列表顶部；重复同步不产生重复行；SyncKey 失步时全量重建且不丢信、不重信。

## 入口

- `CMP-SCN-SYNC#refresh`、`#startAutoRefresh`
- `CMP-SYNC#syncOnce`（`design/components/CMP-SYNC/spec.md`）
- `CMP-DOMAIN#MailGateway.fetchMessages`（经 `CMP-EASADAPTER`）
- `CMP-STORE#applySyncBatch`（`MailStore` 直接遵循 `CMP-DOMAIN#SyncStore`）

## 运行序

流程 `F-RECEIVE-02`：

1. `SyncEngine` 从 `sync_state` 读该集合的 `sync_key`；无则用 `0`。
2. `fetchMessages(collectionID, key, window=25)`。
3. 若 `SyncKey=0` 首轮只回新 key → 用新 key 立即再 Sync 一次取条目。
4. `applySyncBatch`：数据与 key 同事务提交。
5. 本轮新增少于 `window` 即停；最多 `maxRounds=5` 轮（`MoreAvailable` 不可靠，见 playbook §3）。
6. 成功后 `SyncScene` 按 `added > 0` 发通知（`SCN-0003` 的通知策略归 `SyncScene`）。

失败路径：

- 批次失败 → 整批回滚，key 不推进，退避后重试；
- `Sync/Status=3/4` → `syncKeyInvalid`：`resetCollection` 后按 key `0` 重建；
- `Sync` 回 `200` 空 body 或缺 `Collection/Status` → 同 `syncKeyInvalid`（2026-11-17 实测：网关对「请求被吞」也回 0 字节 `200`，不能当成设备未登记，见 `CMP-EAS` 设计增量）；
- `503` + `Retry-After` → `SyncEngine` 等一次后重试一次，仍失败则本次失败；
- 正文缺失 → 占位，转 `SCN-0004` 的补拉路径。

## 不可变引用

- `MailStore.applySyncBatch` 的「同一事务」与 `(account, folder, server_id)` 幂等键。
- `Sync` 请求体最小化（playbook §3）；多带元素会得到 `Status=4`。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0003-01` | 正 | 空库首同步 30 封 → 列表 30 条，key 推进一次 |
| `T-SCN-0003-02` | 正 | 服务器新增 1 封 → 增量同步只拉 1 条，旧信不重复 |
| `T-SCN-0003-03` | 正 | 同一批响应重复投递 → 行数不变（幂等 upsert） |
| `T-SCN-0003-04` | 反 | 批次写库中途失败 → key 保持旧值，下次同步能取回该批，不丢信 |
| `T-SCN-0003-05` | 反 | `Sync` 回 `200`/0B 或 12 字节残缺体 → 判 `syncKeyInvalid`、重置重建，**不**判设备未登记、不停自动刷新（真机复现 2026-11-17） |

## 状态

`designed`（2026-11-14 核对）。运行序、引用、测试方案与入口已按实现更新；实现与验证如下。

实现：`SyncEngine.syncOnce`（Provision → FolderSync → 收件箱分页 → 落库）已落地；`SyncScene.refresh` 包单飞与通知（`1f0c0b3`）；真机 5 轮 × 25 封（重构前）。`start/stop/stateStream` 仍未实现。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0003-01` | 部分（组件级）：`SyncEngineTests`「first sync is two requests and only the window is written」断言窗口与 key；「列表 30 条」未在测试中断言 |
| `T-SCN-0003-02` | 通过（组件级）：`SyncEngineTests`「incremental sync resumes from the stored key」 |
| `T-SCN-0003-03` | 通过（组件级）：`MailStoreTests`「re-applying the same batch keeps one row per server id」 |
| `T-SCN-0003-04` | 通过（组件级）：`MailStoreTests`「a failed batch does not advance the key」 |
| `T-SCN-0003-05` | 通过（组件级，2026-11-17）：`EASClientTests` 空 `Sync` 读/写与缺 `Collection/Status` 三条 + `SyncSceneTests`「a device rejection does not end the automatic refresh loop」；`FolderSync` 空 body 仍判 `deviceNotRegistered`（pin 住不回归） |

未转 `verified` 的原因：四项都有组件级断言，但场景要求的「列表条数 / UI 可见」没有场景级测试；`stateStream` 未实现，进度态只有 `currentState()`。
