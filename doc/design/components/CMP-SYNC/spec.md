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
- 负责 X：Provision 前置、FolderSync 全量、集合 Sync 分页、SyncKey 推进、status 3/4 重建、`throttled` 等待一次后重试一次、内存状态 `SyncState`；T-1114-10 设计新增已读/删除写命令的显式串行门与成功提交（2026-11-14 已实现，T-1114-15）。
- 不负责 Y：刷新节奏、通知、UI 状态、MIME、数据库 schema、持久化实现。
- 内部逻辑：`syncOnce` = `provisionIfNeeded` → `fetchFolders(syncKey:"0")` → 定位收件箱 → 分页 Sync（首轮 key `0` 两请求；每轮新增 < window 即停，最多 `maxRounds` 轮）→ `applySyncBatch`；每轮批次与 key 同事务（由 `SyncStore` 实现保证）。
- 拥有的数据：无持久业务数据；只持有内存状态机与失败计数。
- 变化轴：服务器分页/限流行为（沉在 gateway 之下）；触发方式由 `SyncScene` 决定。
- 公开契约：`CMP-SYNC#syncOnce`、`#currentState`；T-1114-10 设计新增 `#markRead`、`#deleteMessage`（2026-11-14 已实现，T-1114-15）。
- 入口：`Sources/SyncEngine/SyncEngine.swift#SyncEngine`、`Values.swift#SyncState`
- 依赖：`MailDomain`（`MailGateway`、`SyncStore`）。扇出 1（端口计入 Domain）。
- 冷热：冷；每账号一个 actor。
- 尺寸预算：目标 ≤400 行；当前 152 行（`wc -l` 2026-11-14；此前规格误记为 191，191 是 `ReadScene.swift` 的行数）。
- 单独运行：`./Scripts/swiftw test --filter SyncEngineTests`
- 删除测试：删掉后 `SyncScene` 直接编排网关并各自维护 SyncKey → 复杂度集中，是真边界。

## 契约卡：SyncEngine v1

- 签名：

  ```swift
  public actor SyncEngine {
      public init(gateway: any MailGateway, store: any SyncStore, account: AccountRef,
                  writeGateway: any MailWriteGateway,   // T-1114-10 设计新增，非可选（已实现）
                  window: Int = 25, maxRounds: Int = 5, filterType: Int = 5,
                  sleeper: @escaping @Sendable (Duration) async -> Void = { ... })
      public func syncOnce() async throws -> SyncReport
      public func currentState() -> SyncState
      // T-1114-10 设计新增（已实现）
      public func markRead(collectionID: String, serverID: String) async throws
      public func deleteMessage(collectionID: String, serverID: String) async throws
  }
  ```

- 不变量：同账号串行（actor + 显式 FIFO 门；actor 在 `await` 处可重入，不得只靠 actor）；批次与 key 同事务；失败不推进 key、保留旧数据；`throttled` 最多等待并重试一次；分页停止条件为「本轮新增 < window」（`MoreAvailable` 实测不可靠）。
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

## 设计增量：串行写路径（T-1114-10，2026-11-14 设计；T-1114-15 已实现）

- 新增写能力，与 `syncOnce` 共享同一集合 `SyncKey`：

  ```swift
  public init(gateway: any MailGateway, store: any SyncStore, account: AccountRef,
              writeGateway: any MailWriteGateway, …)   // 非可选，无默认值
  public func markRead(collectionID: String, serverID: String) async throws
  public func deleteMessage(collectionID: String, serverID: String) async throws
  ```

- 显式 FIFO 非重入门（不是「actor 方法互斥」）：actor 内 `busy` + `[CheckedContinuation<Void, Never>]`；`acquire()` 在忙时挂起，`release()` 把所有权交给队首等待者（`busy` 保持 true）。临界区 =「读当前 `syncKey` → 一次 Sync（读或写）→ apply/commit」；读命令遇 `Status=3/4` 时，`resetCollection` 与 `key = "0"` 也在**同一临界区**内完成，不与写命令交错；`defer` 释放。actor 在 `await` 处可重入，必须有这把门。
- `syncInbox` 每轮改在门内**重新读** `store.syncKey`，不再沿用循环外局部 `key`；写命令插入轮次之间后，下一轮从新 key 继续。写命令只等一次 Sync，不等整个分页循环/限流 sleep。
- `markRead`：门内 `store.markRead` 再钉一次本地已读（覆盖「同步批次在本地置读前取回、之后才应用」的竞态）→ 读 key → `writeGateway.markRead` → `store.commitMarkRead`。本地已读是终态；回写失败不抛给 PRES 的计时路径。
- `deleteMessage`：门内读 key → `writeGateway.delete` → `store.commitDelete`；服务端确认前不落本地删除，失败不半删。
- key 缺失/为 `"0"` → `.syncKeyInvalid`；写端口非可选，**不存在 `writeGateway == nil` 分支**，生产 target 不提供 `UnsupportedWriteGateway`（只读测试在测试 target 显式注入该替身）；写响应 `moreAvailable == true` → `.unsupported` 且不提交（协议异常，等 T-1114-12 样本再定 drain）。
- 取消：等待中的写任务被取消后立即移出队列（`withTaskCancellationHandler` 唤醒等待者并让 `acquire` 抛 `CancellationError`）；已获门但尚未越过临界区的，检查 `Task.isCancelled` 后释放门、不读 key、不发写。已读回写取消按失败静默吸收；删除取消由 PRES 按失败恢复并提示。
- 装配：T-1114-21 先提供 `GatewayEndpoints.write`（非可选）；T-1114-15 把该端口传给 `SyncEngine`，并在同一 change 机械更新两处生产组合根（`CMP-ROOT` 仅装配例外）。
- 兼容性：`SyncEngine.init` 新增非可选 `writeGateway` 是公共构造契约变更；两处生产构造点与所有测试构造点同批更新，**不提供**省略该参数的兼容重载（否则又会出现无写端口的引擎）。
- 写响应 delta 交给 `commit*` 时，store 会排除目标 `serverID` 的 `added/changed`（partial echo 不用 nil 覆盖目标信封），只应用 `removedServerIDs` 与其他消息；目标本地效果由写路径决定。
- 实例约束：**一个账号一个 `SyncEngine`**，`SyncScene` 与 `ReadScene` 共用；不得在组合根或场景内 new 第二个实例，否则两把门各自为政、同一 key 互顶（R19）。
- 整轮单飞仍由 `SyncScene` 保证；本门只保证「单次 Sync（读或写）与写命令」互斥，不承诺两个并发 `syncOnce` 循环的语义。调用方不得并发调用 `syncOnce`；若未来需要，另加整轮 `syncing` 标志，不在本批猜。
- 尺寸：当前 152 行；预计 +60～70（门 ~25、两个写方法 ~35、每轮重读 key ~5），约 212～222 行，仍低于 400。
- 测试：`SyncEngineTests` 补「写命令与 `syncOnce` 门串行」「写成功后 key 恰好推进一次」「网关失败不推进 key/不落本地」「两个写命令串行且不重复推进 key（同目标去重由 `MailboxDeletion`/VM 保证，不在引擎层断言）」「`Status=3/4` 的 reset 与写命令互斥，reset 后下一轮从 key=0 继续」「写响应 `moreAvailable` 不提交」「等待中的写被取消后不发网络」；只读用例用测试 target 的 `UnsupportedWriteGateway` 构造引擎；既有 7 例不回归。

**实现（2026-11-14）**：`SyncEngine` 增非可选 `writeGateway`、FIFO 门、`markRead`/`deleteMessage`；`syncRound` 在门内重读 key、bootstrap 与一页 Sync 同临界区，`Status=3/4` 的 reset 同门。`SyncEngineTests` 15 例绿，含写/同步双向串行、key 只推进一次、失败不提交、MoreAvailable 拒绝、取消不发网络。
