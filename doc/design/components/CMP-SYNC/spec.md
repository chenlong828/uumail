---
layer: design
module: sync
status: active
updated: 2026-11-14
component: CMP-SYNC
---

# CMP-SYNC SyncEngine 组件规格

## 模块卡

- 状态：`active`（`syncOnce` 已落地；`start/stop/stateStream` 未实现）
- 单元：组件（actor）
- 层 / 类型：**L1b 能力**（原 L2，W-SCN-REFACTOR D3 下调）
- 业务价值：把「服务器状态」变成「本地可见的新状态」，并保证每个集合的 SyncKey 不丢不重。没有它，场景会自己直连协议层，SyncKey 逻辑散落。
- 负责 X：Provision 前置、FolderSync 全量、集合 Sync 分页、SyncKey 推进、status 3/4 重建、`throttled` 等待一次后重试一次、内存状态 `SyncState`。
- 不负责 Y：刷新节奏、通知、UI 状态、MIME、数据库 schema、持久化实现。
- 内部逻辑：`syncOnce` = `provisionIfNeeded` → `fetchFolders(syncKey:"0")` → 定位收件箱 → 分页 Sync（首轮 key `0` 两请求；每轮新增 < window 即停，最多 `maxRounds` 轮）→ `applySyncBatch`；每轮批次与 key 同事务（由 `SyncStore` 实现保证）。
- 拥有的数据：无持久业务数据；只持有内存状态机与失败计数。
- 变化轴：服务器分页/限流行为（沉在 gateway 之下）；触发方式由 `SyncScene` 决定。
- 公开契约：`CMP-SYNC#syncOnce`、`#currentState`。
- 入口：`Sources/SyncEngine/SyncEngine.swift#SyncEngine`、`Values.swift#SyncState`
- 依赖：`MailDomain`（`MailGateway`、`SyncStore`）。扇出 1（端口计入 Domain）。
- 冷热：冷；每账号一个 actor。
- 尺寸预算：目标 ≤400 行；当前 191 行。
- 单独运行：`./Scripts/swiftw test --filter SyncEngineTests`
- 删除测试：删掉后 `SyncScene` 直接编排网关并各自维护 SyncKey → 复杂度集中，是真边界。

## 契约卡：SyncEngine v1

- 签名：

  ```swift
  public actor SyncEngine {
      public init(gateway: any MailGateway, store: any SyncStore, account: AccountRef,
                  window: Int = 25, maxRounds: Int = 5, filterType: Int = 5,
                  sleeper: @escaping @Sendable (Duration) async -> Void = { ... })
      public func syncOnce() async throws -> SyncReport
      public func currentState() -> SyncState
  }
  ```

- 不变量：同账号串行（actor）；批次与 key 同事务；失败不推进 key、保留旧数据；`throttled` 最多等待并重试一次；分页停止条件为「本轮新增 < window」（`MoreAvailable` 实测不可靠）。
- 错误模式：`MailError` 原样上抛（`syncKeyInvalid` 触发 `resetCollection` 后重建）；`SyncState.failed(SyncFailure)` 记录错误、文件夹与连续失败数；无收件箱抛 `unsupported`。
- 幂等 / 顺序 / 并发：单账号 actor；重复 `syncOnce` 从已存 key 继续。
- 超时 / 取消：单命令超时由 gateway 层；本组件无额外超时。
- 一致性 / 可见性：批次提交后读库即可见；失败保留旧数据。
- 兼容性：`store` 参数为 `any SyncStore`（无 `StoreAdapter`）；`MailGatewayError` 已并入 `MailError`；`SyncState` 仍在 `SyncEngine` target，`FolderSummary` 等过渡 `typealias` 未删。
- 契约测试：`SyncEngineTests` 7 例。

## 运行序（与场景对应）

| 场景 | 序列 | 失败路径 |
|---|---|---|
| SCN-0002 文件夹树 | `fetchFolders("0")` → `applyFolderSnapshot` | 失败保留旧树；认证失败转 `authFailed` |
| SCN-0003 收件箱同步 | `sync(inbox, key)` → `applySyncBatch` → 新增 < window 即停 | key 失效（3/4）→ `resetCollection` 重建；`throttled` → 等一次重试一次 |
| SCN-0004 正文 | 不在本组件：补拉归 `ReadScene` | — |
| SCN-0005 附件 | 不在本组件：下载归 `ReadScene` | — |

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| `syncOnce()`：Provision → FolderSync → 收件箱分页 → 落库 | ✅ | 7 例（bootstrap、增量、重建、分页预算、设备拒绝、无收件箱、throttled 重试一次） |
| `start/stop/stateStream` | ⬜ 未实现 | 刷新节奏由 `SyncScene` 负责；进度态只有 `currentState()` |
| 退避与限流 | ✅ `throttled` 等一次（1–300s）后重试一次 | 「a throttled run waits for Retry-After and retries once」 |
| 轮询驱动 | 已迁出本组件：`SyncScene.startAutoRefresh`（5 分钟） | `SyncSceneTests` |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 契约/状态机 | `SyncEngineTests` 覆盖状态与 key 行为；每态至少一个退出用例 |
| 失败/降级 | fake gateway 注入 401/449/503/空 200/坏 body；断言不推进 key |
| 冷热隔离 | 单账号 actor；同步不占 UI 队列 |
| 依赖 | 门 1：只 import `MailDomain`/`Foundation`，不 import `MailStore`/EAS |

## 依赖约束

- 只经 `MailGateway` 端口访问网络，`SyncStore` 端口落库；不 import `MailStore` 具体类型、URLSession、WBXML。
- 不写 SQL；不做通知与节奏判断。
