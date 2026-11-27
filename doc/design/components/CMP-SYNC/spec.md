---
layer: design
module: sync
status: active
updated: 2026-11-24
component: CMP-SYNC
---

# CMP-SYNC SyncEngine 组件规格

## 模块卡

- 状态：`active`（`syncOnce`/`syncSentOnce` 已落地；`start/stop/stateStream` 未实现）
- 单元：组件（actor）
- 层 / 类型：**L1b 能力**（原 L2，W-SCN-REFACTOR D3 下调）
- 业务价值：把「服务器状态」变成「本地可见的新状态」，并保证每个集合的 SyncKey 不丢不重。没有它，场景会自己直连协议层，SyncKey 逻辑散落。
- 负责 X：Provision 前置、FolderSync 全量、集合 Sync 分页、SyncKey 推进、status 3/4 重建、`throttled` 等待一次后重试一次、内存状态 `SyncState`；T-1114-10 设计新增已读/删除写命令的显式串行门与成功提交（2026-11-14 已实现，T-1114-15）；2026-11-24 新增 Sent Items 按需同步（`syncSentOnce`，REQ-0038，见文末增量）。
- 不负责 Y：刷新节奏、通知、UI 状态、MIME、数据库 schema、持久化实现。
- 内部逻辑：`syncOnce` = `provisionIfNeeded` → `fetchFolders(syncKey:"0")` → 定位收件箱 → 分页 Sync（首轮 key `0` 两请求；每轮新增 < window 即停，最多 `maxRounds` 轮）→ `applySyncBatch`；每轮批次与 key 同事务（由 `SyncStore` 实现保证）。`syncSentOnce` 走同一序列，但定位 `isSentItems` 集合且不碰收件箱的 key 与窗口。
- 拥有的数据：无持久业务数据；只持有内存状态机与失败计数。
- 变化轴：服务器分页/限流行为（沉在 gateway 之下）；触发方式由 `SyncScene` 决定。
- 公开契约：`CMP-SYNC#syncOnce`、`#currentState`；T-1114-10 设计新增 `#markRead`、`#deleteMessage`（2026-11-14 已实现，T-1114-15）；2026-11-24 新增 `#syncSentOnce`（REQ-0038）。
- 入口：`Sources/SyncEngine/SyncEngine.swift#SyncEngine`、`Values.swift#SyncState`
- 依赖：`MailDomain`（`MailGateway`、`SyncStore`）。扇出 1（端口计入 Domain）。
- 冷热：冷；每账号一个 actor。
- 尺寸预算：目标 ≤400 行；当前 **315 行**（`wc -l` 2026-11-24，含 FIFO 门、写命令、reset 内重建与 Sent 入口）。
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
      public func syncSentOnce() async throws -> SyncReport?   // 2026-11-24 新增（REQ-0038）
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
- 契约测试：`SyncEngineTests` 19 例（2026-11-24 实测；含 Sent 入口 2 例）。

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

- 显式 FIFO 非重入门（不是「actor 方法互斥」）：actor 内 `busy` + `[CheckedContinuation<Void, Never>]`；`acquire()` 在忙时挂起，`release()` 把所有权交给队首等待者（`busy` 保持 true）。临界区 =「读当前 `syncKey` → 一次 Sync（读或写）→ apply/commit」；读命令遇 `Status=3/4` 时，`resetCollection`、`key = "0"`、bootstrap 与重建后的下一页都在**同一次门持有内**完成，不与写命令交错；`defer` 释放。actor 在 `await` 处可重入，必须有这把门。**2026-11-14 测试暴露**：若 reset 与重建分处两次 acquire，排队的写会在 reset 后、重建前插队并读到空 key；实现已在 `syncRound` 内循环完成 reset+rebuild 后才释放门。
- `syncInbox` 每轮改在门内**重新读** `store.syncKey`，不再沿用循环外局部 `key`；写命令插入轮次之间后，下一轮从新 key 继续。写命令只等一次 Sync，不等整个分页循环/限流 sleep。
- `markRead`：门内 `store.markRead` 再钉一次本地已读（覆盖「同步批次在本地置读前取回、之后才应用」的竞态）→ 读 key → `writeGateway.markRead` → `store.commitMarkRead`。本地已读是终态；回写失败不抛给 PRES 的计时路径。
- `deleteMessage`：门内读 key → `writeGateway.delete` → `store.commitDelete`；服务端确认前不落本地删除，失败不半删。
- key 缺失/为 `"0"` → `.syncKeyInvalid`；写端口非可选，**不存在 `writeGateway == nil` 分支**，生产 target 不提供 `UnsupportedWriteGateway`（只读测试在测试 target 显式注入该替身）；写响应里的 `MoreAvailable` 与整页 delta 是正常分页信号（R16 真机样本：`Collection/MoreAvailable` + 25/100 条 `Add`），与本地效果、新 key 同事务提交，剩余页由下一轮增量同步消费；**不拒绝提交**。not-found 由真机样本确认为 `Collection/Status=1` 的成功 no-op（无逐条状态），不需要额外映射。
- 取消：等待中的写任务被取消后立即移出队列（`withTaskCancellationHandler` 唤醒等待者并让 `acquire` 抛 `CancellationError`）；已获门但尚未越过临界区的，检查 `Task.isCancelled` 后释放门、不读 key、不发写。已读回写取消按失败静默吸收；删除取消由 PRES 按失败恢复并提示。
- 装配：T-1114-21 先提供 `GatewayEndpoints.write`（非可选）；T-1114-15 把该端口传给 `SyncEngine`，并在同一 change 机械更新两处生产组合根（`CMP-ROOT` 仅装配例外）。
- 兼容性：`SyncEngine.init` 新增非可选 `writeGateway` 是公共构造契约变更；两处生产构造点与所有测试构造点同批更新，**不提供**省略该参数的兼容重载（否则又会出现无写端口的引擎）。
- 写响应 delta 交给 `commit*` 时，store 会排除目标 `serverID` 的 `added/changed`（partial echo 不用 nil 覆盖目标信封），只应用 `removedServerIDs` 与其他消息；目标本地效果由写路径决定。
- 实例约束：**一个账号一个 `SyncEngine`**，`SyncScene` 与 `ReadScene` 共用；不得在组合根或场景内 new 第二个实例，否则两把门各自为政、同一 key 互顶（R19）。
- 整轮单飞仍由 `SyncScene` 保证；本门只保证「单次 Sync（读或写）与写命令」互斥，不承诺两个并发 `syncOnce` 循环的语义。调用方不得并发调用 `syncOnce`；若未来需要，另加整轮 `syncing` 标志，不在本批猜。
- 尺寸：实现后 **286 行**（门 + 两个写方法 + 每轮重读 key + reset 内重建），预算 400。
- 测试：`SyncEngineTests` 补「写命令与 `syncOnce` 门串行」「写成功后 key 恰好推进一次」「网关失败不推进 key/不落本地」「两个写命令串行且不重复推进 key（同目标去重由 `MailboxDeletion`/VM 保证，不在引擎层断言）」「`Status=3/4` 的 reset 与写命令互斥：排队写等整个 reset+rebuild，之后从重建后的 key 发；重建期间 fetch 顺序为 stale key → 0 → 新 key」「写响应携带整页 delta 与 `MoreAvailable` 时照常提交」「等待中的写被取消后不发网络」；只读用例用测试 target 的 `UnsupportedWriteGateway` 构造引擎；既有用例不回归。

**实现（2026-11-14）**：`SyncEngine` 增非可选 `writeGateway`、FIFO 门、`markRead`/`deleteMessage`；`syncRound` 在门内重读 key，`Status=3/4` 的 reset+bootstrap+重建页同一次门持有内完成；写响应 `MoreAvailable` 不再拒绝提交。`SyncEngineTests` 17 例绿，含写/同步双向串行、key 只推进一次、失败不提交、写响应整页 delta 提交、reset 与排队写互斥（fetch 顺序 `5 → 0 → 200`、写使用重建后的 key）、取消不发网络。

## 设计增量：发件箱 Sent Items 按需同步（REQ-0038，2026-11-24，P2，已实现）

- 来源：`REQ-0038` / `SCN-0029`。发送侧早已带 `<SaveInSentItems/>`（`CMP-EAS`），副本由服务器写入 Sent Items；本增量只把该集合按需拉进本地，**不做本地 Sent 镜像**。
- 泛化：原 `syncInbox` 改名/泛化为 `syncFolder(_ folder: FolderSummary, folderCount: Int)`，只改名字与入参——窗口、分页停止条件（本轮新增 < window）、`Status=3/4` 重建、FIFO 门与「批次与 key 同事务」全部不变。`runSync` 仍只取 `isInbox` 的集合，`syncOnce()` 的语义与 `throttled` 等待一次后重试一次不变。
- 新增 public 入口：

  ```swift
  public func syncSentOnce() async throws -> SyncReport?
  ```

  - 序列：`provisionIfNeeded` → `refreshFolders()`（`FolderSync(syncKey:"0")` + `applyFolderSnapshot`）→ `folders.first(where: \.isSentItems)`（type `5`，见 `CMP-DOMAIN` 同日增量）→ 只对该 collection 走 `syncFolder`。
  - 返回：`report.folders` 是文件夹总数；`added/changed/removed/rounds/syncKey` 只反映 Sent 这一轮；状态依次 `.syncingFolders → .syncingMessages(folder: sent) → .idle`。
  - 不变量：收件箱的 SyncKey 与窗口不动（Sent 的 key 独立存在 `sync_state`）；一次只同步一个集合，不与写命令交错；重复调用从已存的 Sent key 继续。
  - 无 Sent：返回 `nil`，状态回 `.idle`，不进入 `.syncingMessages`、不计失败、不写消息批次（`refreshFolders` 仍按既有逻辑刷新文件夹树）。
  - 失败：与 `syncOnce` 共用 `recordFailure(_:)`（同一 `MailError` 分类、连续失败计数、`.failed(SyncFailure)`），抛出归一后的错误；`throttled` 的等待重试只在 `syncOnce` 外层，本入口不额外重试。
- `SyncScene` 新增：

  ```swift
  public func refreshSent() async -> RefreshOutcome
  ```

  - 只调 `engine.syncSentOnce()`；返回 `nil` 时给「无 report、无 error」的 `RefreshOutcome`（调用方据此静默保持列表）。
  - **不发新邮件通知**：发件副本不是来信；`Notifier.postNewMail` 仍只在 `refresh` 的新增判定里调用，本入口不申请通知授权、不改 `autoRefreshPaused`。
  - 错误：`MailError` 原样放进 `outcome.error`，非 `MailError` 归一为 `.offline`（与 `refresh` 同一兜底），不抛给视图。
  - 单飞：不加入 `refresh` 的 scene 级单飞（`isRefreshing`/waiters）；与收件箱刷新之间只由引擎的 FIFO 门串行。
- 测试（`Tests/SyncEngineTests/SyncEngineTests.swift` 新增 2 例；该 suite 共 19 例）：
  - `syncSentOnce syncs only Sent Items and leaves the inbox key alone`：`report.added == 2`、`report.folders == 2`、Sent key 推进到 `401`、inbox key 仍 `101`、批次只含 Sent 的两条 serverID、`currentState == .idle`。
  - `syncSentOnce is a no-op when the account has no Sent Items folder`：返回 `nil`、零批次。
  - `refreshSent` 的「不发通知」本轮无独立断言（VM 用例只断言列表与 `phase`），登记为残余。
- 尺寸：`SyncEngine.swift` **315 行**（预算 ≤400）；无 schema/依赖/target 变化；`CMP-EAS` 零改动。

## 设计增量：草稿双向合并同步（REQ-0044，2026-11-27，P3，已实现）

- `SyncEngine.init` 增加可选 `draftStore: (any DraftSyncStore)? = nil`（CLI/旧测试不传即关闭）；新增 `syncDraftsOnce() -> DraftSyncReport?`，与消息同步共用同一网关/写端口/FIFO gate。
- 拉：按 `Folder.isDrafts` 取文件夹，`fetchMessages` + 逐条 `fetchBody`；指纹比较判定本地/服务器是否改过；两边都改 → 先 `duplicateDraft` 复制本地版本，再 `adoptServerDraft` 采用服务器版本；服务器删除且本地改过 → `unbindDraft`，否则删行；同步键只写草稿集合（不进 `messages`）。
- 推：未绑定 → `createDraft`（ClientId = 本地行 id）→ `bindDraft(serverID, 指纹)`；已绑定且指纹不同 → `updateDraft` → `setDraftHash`；tombstone → `deleteDraft` → 清墓碑；每次写回包更新草稿集合 SyncKey。
- 单飞在 `SyncScene.syncDrafts()`，失败返回 `MailError` 不动本地数据。
- 网关实测修正：写响应的 SyncKey 不可用（status 3/4），故每次 create/update/delete 后重新 `SyncKey=0` 引导取新 key（`freshKey`）；草稿集合首次拉取也先引导再取窗口。
- 测试：`Tests/SyncEngineTests/DraftSyncTests.swift` 6 例（下载绑定、上传绑定、冲突两份、删除墓碑、发送墓碑、墓碑不被拉取复活）；真实网关冒烟 PASS（`task-spaces/20261127-152500-draft-smoke/probe/`）。
