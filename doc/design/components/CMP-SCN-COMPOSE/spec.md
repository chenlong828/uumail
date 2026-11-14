---
layer: design
module: scenes
status: active
updated: 2026-11-14
component: CMP-SCN-COMPOSE
---

# CMP-SCN-COMPOSE ComposeScene 组件规格

## 模块卡

- 状态：`active`
- 单元：组件（场景，`Sendable` 值类型）
- 层 / 类型：L2；撰写、草稿与发送意图
- 业务价值：把回复/转发的引用规则、草稿保存与「发送只入队」收在一处；视图模型不再拼 MIME、不再调发送服务。
- 负责 X：`replySeed/forwardSeed` 的收件人与主题规则、引用文本、`saveDraft`、`send`（校验 + 入队）、`pending/retry/cancel`。
- 不负责 Y：编辑器 UI、MIME 细节（`Outbox/MimeBuilder`）、投递（`Outbox`）。
- 内部逻辑：
  - 回复：`Re:` 前缀（已有则不加）、取发件人地址、正文加 `--- 原邮件 ---` 引用；空主题回退 `(无主题)`。
  - 转发：`Fwd:` 前缀、收件人为空、正文加 `--- 转发邮件 ---` 引用。
  - `send` 只做 `to` 去空白与空值校验，然后 `Outbox.enqueue`；无网络、无 MIME。
  - `saveDraft` 写草稿行（`isDraft = true`），不入队、不投递。
- 拥有的数据：无持久数据；草稿文本由 `Presentation` 持有。
- 变化轴：撰写形态（纯文本/富文本、附件）。
- 公开契约：`CMP-SCN-COMPOSE#replySeed`、`#replyAllSeed`、`#forwardSeed`、`#saveDraft`、`#send`、`#pending`、`#retry`、`#cancel`
- 入口：`Sources/Scenes/ComposeScene.swift#ComposeScene`
- 依赖：`MailStore`、`Outbox`、`MailDomain`。扇出 2。
- 冷热：热（入队本地事务）。
- 尺寸预算：≤500 行；当前 `ComposeScene.swift` 152 行（随 `Scenes` 共 691 行）。
- 单独运行：`./Scripts/swiftw test --filter ScenesTests`
- 删除测试：删掉后视图直接操作 outbox 并拼 MIME → 规则散落，是真边界。

## 契约卡：ComposeScene v1

- 签名：

  ```swift
  public struct ComposeScene: Sendable {
      public init(store: MailStore, outbox: Outbox)
      public func replySeed(to message: Message, bodyHTML: String?) -> Draft
      public func replyAllSeed(to message: Message, bodyHTML: String?, account: AccountID) -> Draft
      public func forwardSeed(from message: Message, bodyHTML: String?) -> Draft
      public func saveDraft(_ draft: Draft, account: AccountID) throws -> OutboxID
      public func send(_ draft: Draft, account: AccountID) async throws -> OutboxID
      public func pending(account: AccountID) async throws -> [OutboxItem]
      public func retry(_ id: OutboxID, account: AccountID) async throws
      public func cancel(_ id: OutboxID, account: AccountID) async throws
  }
  ```

  说明：`Outbox` 是 actor，故 `send/pending/retry/cancel` 为 `async`；这是实现期与规格草案的唯一签名偏差（草案把 `send` 写成同步）。
- 不变量：`send` 不触网，返回即本地事务已提交；空收件人 → `invalidInput`，不入队；`saveDraft` 永不投递；回复/转发主题前缀不重复。
- 错误模式：`invalidInput(reason:)`（空收件人）、`storage`（存储失败）；投递错误不在此返回，异步经 `Outbox` 状态。
- 幂等 / 顺序 / 并发：每次 `send` 生成新 `outboxID`（`ClientId`）；重复点击由 UI `canSend` 禁用。
- 超时 / 取消：入队无超时；取消/重试经 `Outbox` 的行级契约。
- 一致性：`send` 返回时行已落库；`pending` 只读 outbox 行。
- 兼容性：`replySeed/forwardSeed` 行为照搬旧 `ComposeModel`，未改引用规则。
- 契约测试：`ScenesTests/ComposeSceneTests.swift` 9 例；`PresentationTests/ComposeViewModelTests.swift` 8 例。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| `send` 只入队、不触网 | ✅ | 「send enqueues locally and returns immediately without touching the network」 |
| 空收件人拒绝 | ✅ | 「an empty recipient is rejected before anything is enqueued」 |
| `saveDraft` 不入队 | ✅ | 「saveDraft stores a draft row that is never queued」 |
| 回复/转发种子规则 | ✅ | 「reply seed uses Re:, the sender address and the quote marker」「forward seed uses Fwd:」「existing prefixes and empty subjects follow the old rules」 |
| `replyAllSeed`（发件人+To+Cc、去重、排除自己、Cc 减 To） | ✅ | 3 例（正常合并、畸形/重复/自己、账号不可读） |
| `pending/retry/cancel` | ✅ | 经 `Outbox`；`OutboxTests` 覆盖状态机 |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 入队语义 | fake gateway 调用为 0；返回后 `pendingOutbox` 有一行 |
| 校验 | 空/空白收件人抛 `invalidInput` 且无行 |
| 引用规则 | 主题前缀、地址提取、引用标记三组断言 |
| 依赖 | 门 1/2：不 import EAS、不与其它场景互调 |

## 依赖约束

- 只依赖 `MailStore`、`Outbox`、`MailDomain`；不 import EAS/Composition。
- MIME 与投递全部在 `Outbox`；本组件不构造 MIME。

## 设计增量：replyAllSeed（T-1114-06，已实现 2026-11-14）

- 新增公开契约：

  ```swift
  public func replyAllSeed(
      to message: Message,
      bodyHTML: String?,
      account: AccountID
  ) -> Draft
  ```

- 行为：主题/引用直接复用 `replySeed`；`to` = 原发件人 + 原 `recipients`，`cc` = 原 `cc`；两栏都经 `MailDomain.AddressList` 去重、排除当前账号地址，`cc` 再减去已在 `to` 的地址。账号地址经 `store.account(account)` 读取；读取失败/缺失时不排除、不抛错、不崩溃。`Draft.cc` 为空写 `nil`。
- 实现：`Sources/Scenes/ComposeScene.swift#replyAllSeed` 只做一次 `replySeed` 复用、一次 `store.account` 读取和 `AddressList` 的 `removing`/`subtracting` 组装；地址解析/归一化仍在 `MailDomain.AddressList`，本组件不新增解析逻辑。`store.account` 的读取失败按契约降级为「不排除自己」，是本组件唯一不向外抛错的读取路径（设计增量明确要求）。
- 不变：`replySeed` 与 `forwardSeed` 的行为（单回复仍只填发件人、Cc 空；转发收件人为空）；`send`/`saveDraft` 的入队语义。
- 尺寸：`ComposeScene.swift` 127 → 152 行（新增 25 行，含注释）；未把解析逻辑搬进 `Scenes`。
- 测试：`ScenesTests/ComposeSceneTests.swift` 6 → 9 例，新增「正常发件人+To+Cc」「畸形头/重复/自己」「账号不可读不排除」；正常例同时断言 `Re:` 与引用规则，账号不可读例断言既有 `RE:` 前缀不重复。
