---
layer: design
module: outbox
status: active
updated: 2026-11-14
component: CMP-OUT
---

# CMP-OUT Outbox 组件规格

## 模块卡

- 状态：`active`（独立 target；actor；租约、退避、重试、取消、MIME 均在组件内）
- 单元：组件
- 层 / 类型：L1b；领域能力（发送意图与投递状态机）
- 业务价值：发送意图不因网络失败或进程重启丢失，且最多成功一次；用户点「发送」不该盯着转圈，也不该在弱网下收到两封一样的信。
- 负责 X：入队、状态机、120s 租约领取、MIME 组装调用、投递、失败分类、退避、手动重试、取消、状态查询。
- 不负责 Y：撰写编辑与引用规则（`ComposeScene`）、协议（`MailGateway`）、outbox 行存储（`MailStore`）。
- 内部逻辑：
  - `enqueue` 只写本地行并返回 `OutboxID`；`ClientId = outboxID` 作幂等键。
  - `flushOnce` 领取一条（`claimOutbox`）→ 读 `MailStore.account` 取 From/Message-ID 域名 → `MimeBuilder` → `gateway.send`（90s 超时）→ 成功删行/失败标 `failed_retryable` 或 `failed_permanent`。
  - `flushAll` 循环领取直到没有可领取的行；失败行写入未来 `next_attempt_at`，不会在循环里打转。
  - 取消：`queued/failed_*` 直接 `canceled`；`sending` 只记进程内标记，投递返回后落终态（邮件可能已在途）。
- 拥有的数据：`outbox` 状态机语义；行由 `MailStore` 物理持有。
- 变化轴：发送通道（换 `MailGateway.send` 实现即可）。
- 公开契约：见契约卡。
- 入口：`Sources/Outbox/Outbox.swift#Outbox`、`MimeBuilder.swift#MimeBuilder`、`OutboxState.swift#OutboundState`
- 依赖：`MailDomain`、`MailStore`。扇出 2。
- 冷热：入队热（本地事务）、投递冷（独立 actor + 组合根泵）。
- 尺寸预算：≤500 行；当前 344 行（Outbox + Mime + State）。
- 单独运行：`./Scripts/swiftw test --filter OutboxTests`
- 删除测试：删掉后场景直连 SendMail，断网丢信、重启重发、并发双发 → 复杂度集中，是真边界。

## 契约卡：Outbox v1

- 签名：

  ```swift
  public actor Outbox {
      public init(store: MailStore, gateway: any MailGateway, clock: any MailClock,
                  lease: Duration = .seconds(120), sendTimeout: Duration = .seconds(90))
      public func enqueue(_ draft: Draft, account: AccountID) throws -> OutboxID
      public func flushOnce(account: AccountID) async -> DeliveryOutcome?
      public func flushAll(account: AccountID) async -> [DeliveryOutcome]
      public func retry(_ id: OutboxID, account: AccountID) throws
      public func cancel(_ id: OutboxID, account: AccountID) throws
      public func state(of id: OutboxID, account: AccountID) throws -> OutboundState?
      public func pending(account: AccountID) throws -> [OutboxItem]
  }
  ```

- 状态：`OutboundState{ draft, queued, sending, sent, failed_retryable, failed_permanent, canceled }`；`sent` 是终态但不落库（成功即删行）。
- 前置 / 后置 / 不变量：`enqueue` 只写行、立即返回；同一 `ClientId` 最多一次成功投递；永久失败保留内容与原因；`sending` 持 120s 租约，过期可重领。
- 错误模式：`offline`/`throttled` → 可重试；`authFailed`/`deviceNotRegistered`/`policyBlocked`/`unsupported` → 永久失败，手动 `retry` 才再投；`storage`/`invalidInput` 可重试但一般需人工处理；账号行缺失视为永久失败。
- 退避：30s → 2m → 10m → 30m，之后翻倍，封顶 24h；`throttled` 优先用服务器 `Retry-After`（夹在 1s–24h）。
- 幂等 / 顺序 / 并发：每账号一个 actor；跨进程靠 `MailStore.claimOutbox` 的 SQL 原子领取与租约；`flushOnce` 无行返回 `nil`。
- 超时 / 取消 / 背压：`send` 90s；`cancel` 对 `sending` 只置标记；`flushAll` 遇到未到期失败行即停。
- 一致性 / 可见性：成功即删行；失败保留原因与下次时间；`pending` 读行。
- 兼容性：`OutboundState` 取值与 `MailStore` schema v8 一致；MIME 从旧 `AppServices` 迁入本 target；`releaseOutbox` 兼作手动重试写契约（规格未单列 retry）。
- 契约测试：`OutboxTests` 20 例（含表驱动）。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| `enqueue` 只落行、即返回 | ✅ | 「enqueue only writes a queued local row and returns immediately」 |
| `flushOnce` 领取 + `ClientId` + 删行 | ✅ | 「flushOnce sends once with ClientId = outboxID, then removes the row」 |
| 离线恢复只投一次 | ✅ | 「offline enqueue recovers later and delivers exactly once」 |
| 租约与重领 | ✅ | 「an expired sending lease can be reclaimed; a live lease cannot」 |
| 退避（含 `Retry-After`） | ✅ | 30s/2m/10m/30m 与 throttled 用例 |
| 永久失败与手动重试 | ✅ | 「manual retry puts a permanent failure back in the queue and delivers it」 |
| 取消（含 sending 中） | ✅ | 3 例 |
| MIME | ✅ `MimeBuilder` | 「MIME has the headers the gateway needs and a base64 body」 |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 状态机 | 表驱动覆盖迁移与非法迁移（`@Test(arguments:)` 三组） |
| 幂等 | 同一行租约/重领/恢复只成功一次；`ClientId` 断言 |
| 失败分类 | 离线/401/429/超时/账号缺失 |
| 数据 | 成功删行、失败保留内容与 `next_attempt_at` |
| 依赖 | 门 1：只 import `MailDomain`/`MailStore`/`Foundation` |

## 开放问题

- 失败件保留上限 24h / 100 条（T11）尚无清理实现；行会保留到成功、取消或手动重试。
- UI 尚无 pending/failed 角标（`plan/risks.md` R13）。
