---
layer: design
module: outbox
status: active
updated: 2026-11-09
component: CMP-OUT
---

# CMP-OUT Outbox 组件规格

## 模块卡

- 状态：`active`（M2 简化：状态机与队列暂驻 `AppServices` + `MailStore.outbox`，未拆独立 target；契约面与本文一致）
- 单元：组件
- 层 / 类型：L1b；领域能力（发送意图与投递状态机）
- 业务价值：发送意图不因网络失败丢失，且最多成功一次——用户点「发送」后不该盯着转圈，也不该在弱网下收到两封一样的信。
- 负责 X：入队、幂等键、重试退避、失败分类、取消、草稿状态迁移。
- 不负责 Y：MIME 组装细节（调 MIME）、SyncKey 与收信、UI 展示。
- 内部逻辑：状态机 `queued → sending → sent / failed_retryable / failed_permanent / canceled`；`sending` 期间持有本地发送锁，防重复进入；`failed_permanent` 必须携带用户可读原因。
- 拥有的数据：`outbox` 表（行由 CMP-STORE 物理持有，状态机与迁移规则归本组件；CMP-STORE 只提供 `enqueueOutbound` / `markOutboundResult` 两个写契约）。
- 变化轴：无（首版固定 EAS SendMail）。若将来更换通道，只换 `MailGateway` 实现与 MIME 组装，不动状态机；不为此预留抽象（D13）。
- 公开契约：`CMP-OUT#enqueue`、`#observe`、`#cancel`、`#retry`。
- 入口：`Sources/Outbox/Outbox.swift#Outbox`（planned）
- 依赖：MailGateway（发送）、MailStore、MIME 编码、Clock、IDGenerator。扇出 4。
- 冷热：入队热（本地事务，毫秒级）、投递冷；与收信同步队列隔离，互不阻塞。
- 尺寸预算：≤ 120k token；当前 0。
- 单独运行：`swift test --filter OutboxTests`（planned）
- 删除测试：删掉后 UI 直接调 SendMail，断网即丢信、重试无幂等 → 复杂度集中，是真边界。

## 契约卡：Outbox v1（planned）

- 签名：
  - `enqueue(_ request: SendRequest) throws -> OutboxID`
  - `observe(_ id: OutboxID) -> AsyncStream<OutboundState>`
  - `cancel(_ id: OutboxID) async`
  - `retry(_ id: OutboxID) async`
- 前置 / 后置 / 不变量：
  - `enqueue` 立即返回本地 ID 并在同一事务写入本地「已发送」占位与 outbox 行；
  - 同一幂等键只允许一次成功投递；
  - 取消只对 `queued` / `failed_retryable` 生效，`sending` 中先置取消标记，投递返回后再落 `canceled`。
- 错误模式：
  - `failed_retryable`：网络、5xx、`throttled`；退避 30s → 2m → 10m → 30m，上限 24h；
  - `failed_permanent`：认证失败、收件人被拒、附件超限、策略拒绝；不自动重试，UI 标红并可手动重试；
  - 保留上限：24h / 100 条（2026-11-09 确认）；超出后提示用户清理，不静默丢弃。
- 幂等 / 顺序 / 并发：每账号一个投递串行队列；`ClientId` 作为幂等键上送；发送中记录本地锁防止双发。
- 超时 / 取消 / 背压：单次 SendMail 90s；失败件不占同步队列。
- 一致性 / 可见性：投递成功回调后同一事务更新本地消息状态、清 outbox 行、写 Sent 镜像（服务器 `SaveInSentItems` 不回显时本地自维护）。
- 观测：`outbox_pending`、`outbox_failed`、投递延迟、重试次数。

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 状态机 | 表驱动覆盖全部迁移与非法迁移 |
| 幂等 | 同一请求重复 enqueue / 投递超时后重试，断言只成功一次 |
| 失败分类 | 注入 401/449/503/收件人拒绝/附件超限，断言落入正确终态与文案 |
| 冷热隔离 | 投递失败堆积时列表与阅读不受影响 |
| 数据 | 投递成功后 Sent 镜像与 outbox 清理同事务 |

## 开放问题

- 失败件保留上限已定 24h / 100 条；草稿与 outbox 是否拆表待 M2。
- 草稿是否与 outbox 共用表：当前走同一张表加 `is_draft` 标记，M2 再定是否拆表。
