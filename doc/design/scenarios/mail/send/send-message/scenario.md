---
layer: design
module: mail
status: designed
updated: 2026-11-14
flow: mail/send
scenario: SCN-0006
---

# SCN-0006 发送邮件

**结果**：用户点「发送」后立即回到列表，邮件进入待发队列并在网络恢复后自动投递，最多成功一次；失败时明确标红并说明原因。

## 入口

- `CMP-SCN-COMPOSE#send`、`#saveDraft`、`#retry`、`#cancel`（`design/components/CMP-SCN-COMPOSE/spec.md`）
- `CMP-OUT#enqueue`、`#flushOnce`、`#flushAll`（`design/components/CMP-OUT/spec.md`）
- `CMP-ROOT#OutboxPump`（启动补投、30s、入队信号）
- `CMP-DOMAIN#MailGateway.send`（经 `CMP-EASADAPTER`；MIME 为 opaque 字节）
- `CMP-STORE#claimOutbox`、`#markOutboxSent`、`#markOutboxFailed`
- `CMP-PRES#ComposeViewModel.send`（状态「已加入发件箱」）

## 运行序

流程 `F-SEND-01`：

1. 撰写页点发送 → `ComposeScene` 校验收件人 → `Outbox.enqueue` 只写 outbox 行，立即返回 `OutboxID`，UI 不等网络（`ClientId = outboxID`）。
2. 组合根的 `OutboxPump` 在启动、每 30s 或入队信号时调 `Outbox.flushAll`；CLI `send` 直接 `flushAll`。
3. `flushOnce` → `claimOutbox`（120s 租约）→ 读账号行 → `MimeBuilder` → `MailGateway.send`。
4. 返回 `200` + 0 字节 body → `markOutboxSent` **删除行**（不做本地 Sent 镜像）。
5. 失败 → `markOutboxFailed`：可重试退避（30s→2m→10m→30m→翻倍封顶 24h），永久失败保留内容与原因。

失败路径：

- 离线 → 行保持 `queued`；联网后泵/CLI 重投，最多成功一次；
- 认证失败 → `failed_permanent`，提示重新登录后手动 `retry`；
- 收件人被拒 / 附件超限 / 策略拒绝 → `failed_permanent`，保留内容；
- 投递超时 → 90s 超时视为可重试 `offline`；租约到期后行可被重新领取，`ClientId` 防双发。

## 不可变引用

- `MailGateway.send` 的 opaque MIME 与 `ClientId` 幂等键（playbook §3、§4）。
- 成功判据：`200` 且 body 长度为 0；有 body 视为异常。
- `Outbox` 的状态机、租约与退避（`design/components/CMP-OUT/spec.md`）。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0006-01` | 正 | 在线发送 → 1s 内回到列表，outbox 清空，Sent 出现该信 |
| `T-SCN-0006-02` | 正 | 离线发送 → 入队成功；恢复网络后自动投递且只成功一次 |
| `T-SCN-0006-03` | 正 | 带 72KB 附件发送 → `200` + 0B，附件可被收件端取回 |
| `T-SCN-0006-04` | 反 | 投递超时后重试 → 服务器只收到一封（幂等键生效），不发生双发 |

## 状态

`designed`（2026-11-14 核对）。入口已从 `MailService` 改为 `ComposeScene` + `Outbox` + `OutboxPump`；实现与验证如下。

实现：入队即返回、120s 租约、退避、手动重试、取消、启动补投与 30s 泵已落地（`1f0c0b3`、`fc26985`）；CLI `send` 经同一路径。**未做**：本地 Sent 镜像、撰写加附件、outbox UI 角标；`ClientId` 幂等只在契约测试级验证。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0006-01` | 部分：CLI `send` 真机投递通过（重构前，`history/works/2026-11-09-m4-hardening/result.md`）；2026-11-14 用户真机实测 App 端到端发送与接收通过；「Sent 出现」仍依赖服务器 `SaveInSentItems`，未单独断言 |
| `T-SCN-0006-02` | 通过（组件级）：`ScenesTests`「send enqueues locally and returns immediately without touching the network」；`OutboxTests`「offline enqueue recovers later and delivers exactly once」；`OutboxPumpTests`「start delivers a row queued before the app launched」；`CompositionTests` bootstrap 用例断言泵每行只投一次 |
| `T-SCN-0006-03` | 未实现：撰写不支持加附件 |
| `T-SCN-0006-04` | 未验：`OutboxTests` 断言 `ClientId = outboxID` 与超时归类，但没有「服务器只收到一封」的真实幂等验证 |

未转 `verified` 的原因：01 缺 UI/真机证据，03 未落地，04 缺端到端幂等验证。
