---
layer: design
module: mail
status: draft
updated: 2026-11-09
flow: mail/send
scenario: SCN-0006
---

# SCN-0006 发送邮件

**结果**：用户点「发送」后立即回到列表，邮件进入待发队列并在网络恢复后自动投递，最多成功一次；失败时明确标红并说明原因。

## 入口

- `CMP-OUT#enqueue` / `#observe`
- `CMP-EAS#send`
- `CMP-STORE#markOutboundResult`
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

`draft`：运行序与测试方案齐；`Fake EAS` 与 Outbox 未落地。
