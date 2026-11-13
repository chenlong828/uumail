---
layer: design
module: mail
status: designed
updated: 2026-11-13
flow: mail/send
scenario: SCN-0006
---

# SCN-0006 发送邮件

**结果**：用户点「发送」后立即回到列表，邮件进入待发队列并在网络恢复后自动投递，最多成功一次；失败时明确标红并说明原因。

## 入口

- `MailService.send`（内部 `MailStore.enqueueOutbox`；`observe` 未实现）
- `CMP-EAS#send`
- `MailStore.markOutboxSent` / `markOutboxFailed`（`markOutboundResult` 未实现）
- 回复/转发复用同一通道，仅多 `In-Reply-To` / `References` 头。

## 运行序

流程 `F-SEND-01`：

1. 撰写页点发送 → MIME 组装（multipart/alternative，附件走 multipart/mixed）。
2. `CMP-OUT#enqueue`：同一事务写 outbox 行与本地「已发送」占位，立即返回 ID，UI 不等网络。
3. 投递队列（冷路径）取队首：`CMP-EAS#send(mime, clientId)`，`Mime` 以 opaque 原始字节送出，`SaveInSentItems=1`。
4. 返回 `200` + 0 字节 body → 成功：同一事务更新本地消息状态、清 outbox、写 Sent 镜像。
5. 失败按错误分类落 `failed_retryable` 或 `failed_permanent`；可重试项退避重投。

失败路径：

- 离线 → 保持 `queued`，联网后自动投递；
- 认证失败 → `failed_permanent`，提示重新登录后手动重试；
- 收件人被拒 / 附件超限 / 策略拒绝 → `failed_permanent`，标红并保留草稿内容；
- 投递超时 → 保持 `sending` 锁，恢复后先查状态再决定重投，避免双发。

## 不可变引用

- `CMP-EAS#send` 的 opaque MIME 与 `ClientId` 幂等键（playbook §3、§4）。
- 成功判据：`200` 且 body 长度为 0；有 body 视为异常。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0006-01` | 正 | 在线发送 → 1s 内回到列表，outbox 清空，Sent 出现该信 |
| `T-SCN-0006-02` | 正 | 离线发送 → 入队成功；恢复网络后自动投递且只成功一次 |
| `T-SCN-0006-03` | 正 | 带 72KB 附件发送 → `200` + 0B，附件可被收件端取回 |
| `T-SCN-0006-04` | 反 | 投递超时后重试 → 服务器只收到一封（幂等键生效），不发生双发 |

## 状态

`designed`（2026-11-13 核对）。运行序、引用、测试方案与入口齐；实现与验证如下。

实现：`enqueueOutbox` → `MailService.send`（入队后立即尝试，成功 `markOutboxSent`，失败 `markOutboxFailed`）；`ComposeView` / `ComposeModel` 覆盖新建、回复、转发、存草稿；`SendMail` 走 opaque MIME + `SaveInSentItems`，真机自测信投递成功、outbox 清空（`history/works/2026-11-09-m4-hardening/result.md`）。**未做**：离线自动重投（无后台队列消费）、本地 Sent 镜像、撰写加附件、`ClientId` 幂等实测。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0006-01` | 部分：CLI `send` 真机投递通过、outbox 清空；UI 点击后回列表与「Sent 出现」未验（依赖服务器 `SaveInSentItems`） |
| `T-SCN-0006-02` | 未满足：失败件只标 `failed`，没有联网后自动投递 |
| `T-SCN-0006-03` | 未实现：撰写不支持加附件 |
| `T-SCN-0006-04` | 未验：无超时重试与幂等用例 |

未转 `verified` 的原因：只有 01 有一部分真机证据，其余三项未落地或未验。
