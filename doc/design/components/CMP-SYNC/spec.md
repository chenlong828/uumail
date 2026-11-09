---
layer: design
module: sync
status: planned
updated: 2026-11-09
component: CMP-SYNC
---

# CMP-SYNC SyncEngine 组件规格

## 模块卡

- 状态：`active`（`syncOnce` 已落地：文件夹刷新 + 收件箱分页；`start/stop/stateStream` 未实现）
- 单元：组件
- 层 / 类型：L2；整合层用例编排（单账号）
- 业务价值：把「服务器状态」变成「本地可见的新状态」，并保证每个集合的 SyncKey 不丢不重。没有它，UI 会自己直连协议层，SyncKey 逻辑散落各处。
- 负责 X：FolderSync → 集合 Sync → Ping/轮询 → 正文与附件补拉 → 退避与恢复；每账号一个串行 actor。
- 不负责 Y：MIME 生成、数据库 schema、UI 状态、设备策略 UI。
- 内部逻辑：状态机 `idle → folderSync → mailSync → ping → idle`；异常态 `offline / authFailed / deviceNotRegistered / policyBlocked / throttled`，每个态有显式退出条件与重试预算。
- 拥有的数据：**无持久业务数据**；只持有内存状态机与内存队列，持久状态落 CMP-STORE 的 `sync_state`。
- 变化轴：服务器行为差异与限流策略（沉到 CMP-EAS 之下）、同步触发方式（首版轮询/手动，Ping 验证后再加）。
- 公开契约：`CMP-SYNC#start`、`#stop`、`#forceSync`、`#stateStream`。
- 入口：`Sources/SyncEngine/SyncEngine.swift#SyncEngine`（planned）
- 依赖：MailGateway（CMP-EAS 实现）、MailStore、DeviceProfileStore、CredentialProvider（Basic）、Clock。扇出 5，符合热/冷上限。
- 冷热：冷；绝不与 UI 主线程共享队列；单账号串行，避免 SyncKey 竞争。
- 尺寸预算：≤ 120k token；当前 0。
- 单独运行：`swift test --filter SyncEngineTests`（planned）
- 删除测试：删掉后 UI 组件会各自直连 CMP-EAS 并各自维护 SyncKey → 复杂度集中，是真边界。

## 契约卡：SyncEngine v1（planned）

- 签名：
  - `start(account: AccountID) async`
  - `stop(account: AccountID) async`
  - `forceSync() async`
  - `stateStream(account: AccountID) -> AsyncStream<SyncState>`
- 不变量：同一账号同一集合同时只有一个 Sync 在飞；SyncKey 推进只发生在 CMP-STORE 事务成功后；批次失败不推进 key。
- 错误模式：
  - `authFailed`：停止自动重试，转登录态，等用户重新输入凭据；
  - `deviceNotRegistered`：停止并给出设备登记指引（见 CMP-EAS playbook §6），不无限重试；
  - `policyBlocked`：停止同步，保留本地数据；
  - `throttled`：按 `Retry-After` 退避，指数上限 30 分钟；
  - `transient`：退避重试，连续 5 次转 `offline`。
- 幂等 / 顺序 / 并发：单账号串行；`forceSync` 与自动同步合并，不并行两份。
- 超时 / 取消 / 背压：Sync 单命令 60s；Ping 独立超时；附件补拉队列上限 3，超出暂停。
- 一致性 / 可见性：批次提交后列表立即可见；正文缺失显示占位并排入补拉。
- 观测：`last_sync_at`、`last_ping_at`、`sync_key_age`、`batch_size`、`throttle_count`、`sync_duration`。

## 运行序（与场景对应）

| 场景 | 序列 | 失败路径 |
|---|---|---|
| SCN-0002 文件夹树 | `folderSync` → `applyFolderSnapshot` | 失败保留旧树并标 stale；认证失败转 `authFailed` |
| SCN-0003 收件箱同步 | `sync(inbox, key)` → `applySyncBatch` → 若有 `MoreAvailable` 继续 | key 失效（status 3/4）→ 清集合重建；`throttled` → 退避 |
| SCN-0004 正文 | 列表命中 → 缺正文 → `fetchBody` → `applySyncBatch`（更新正文） | 失败保留占位，退避重取 |
| SCN-0005 附件 | `fetchAttachment` → 写 AttachmentCache → 更新元数据 | 断点续传、超限提示 |

### 实现进度（2026-11-09）

| 契约 | 代码 | 测试 |
|---|---|---|
| `syncOnce()`：Provision → FolderSync → 收件箱分页 → 落库 | ✅ `SyncEngine.swift` | 6 个用例（bootstrap、增量、重建、分页、设备拒绝、无收件箱） |
| `start/stop/stateStream` | ⬜（当前状态只可读） | — |
| 退避与限流 | ⬜ | — |

**实测口径**：分页停止条件用「本轮新增 < WindowSize」，`MoreAvailable` 不可靠（见 playbook §3）。

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 契约/状态机 | 状态迁移表驱动；每态至少一个退出用例 |
| 失败/降级 | Fake EAS 注入 401/449/503/空 200/坏 WBXML；断言不推进 key、退避参数 |
| 冷热隔离 | 同步高峰时 UI 列表 P95 不劣化 |
| 并发 | 两账号并行 start（若进首版）、同账号重复 start 幂等 |
| 观测 | 断言状态流事件序列与指标上报 |

## 依赖约束

- 只经 `MailGateway` 端口访问网络，不 import CMP-EAS 具体类型。
- 不直接写 SQL；所有落库经 CMP-STORE 契约。
- 不依赖任何 L0 具体类型（URLSession、WBXML）。
