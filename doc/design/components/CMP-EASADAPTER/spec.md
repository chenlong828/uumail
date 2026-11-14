---
layer: design
module: eas
status: active
updated: 2026-11-14
component: CMP-EASADAPTER
---

# CMP-EASADAPTER EASAdapter 组件规格

## 模块卡

- 状态：`active`
- 单元：组件（技术边界 / 防腐层）
- 层 / 类型：L0；把 EAS 协议层挡在 `MailDomain` 契约之外
- 业务价值：EAS 的类型、错误与配置只在这一处出现；协议升级/网关差异只改这里，场景与同步不动。
- 负责 X：实现 `MailGateway` 的 7 个操作；`ServerConfiguration → EASConfiguration` 的构造入口；`EASError → MailError` 的唯一映射；正文类型/截断标记的透传（D10）；MIME 以 opaque 字节送出。
- 不负责 Y：业务判断、重试策略、持久化、UI、MIME 组装（`Outbox/MimeBuilder`）。
- 内部逻辑：每个操作只做「调用 `EASClient` → 映射错误 → 转成领域值」；错误映射集中在 `EASAdapter.map`，不做重试。
- 拥有的数据：无。
- 变化轴：EAS 协议版本与网关差异。
- 公开契约：`CMP-EASADAPTER#MailGateway`（`MailGateway` v2 的唯一生产实现）。
- 入口：`Sources/EASAdapter/EASAdapter.swift#EASAdapter`、`#map`
- 依赖：`MailDomain`、`EASClient`。扇出 2。
- 冷热：冷。
- 尺寸预算：目标 ≤300 行；当前 133 行。
- 单独运行：`./Scripts/swiftw test --filter EASAdapterTests`
- 删除测试：删掉后场景与同步各写一遍错误映射与类型转换 → 错误语义不一致，是真边界。

## 契约卡：MailGateway v2 实现

- 签名：与 `design/components/CMP-DOMAIN/spec.md` 的 `MailGateway` 一致；`init(client: EASClient)`。
- 前置 / 后置：`provisionIfNeeded` 只在 `EASClient.currentPolicyKey()` 为空时握手；`fetchFolders(syncKey:)` 直接透传 key；`fetchBody` 返回 `FetchedBody{text,isHTML,isTruncated}`，不改变正文内容。
- 不变量：任何 `EASError` 都必须映射为 `MailError`，不得把 `EASError` 泄漏出本 target；成功判据沿用 `EASClient`（`send` 为 `200` + 0 字节 body）。
- 错误模式（映射表，`EASAdapter.map`）：

  | `EASError` | `MailError` |
  |---|---|
  | `authFailed` | `authFailed` |
  | `deviceNotRegistered` | `deviceNotRegistered` |
  | `policyRequired` | `policyBlocked` |
  | `syncKeyInvalid` | `syncKeyInvalid` |
  | `throttled(after:)` | `throttled(seconds:)` |
  | `transient` | `offline` |
  | `gatewayRejected` / `protocolRejected` / `permanent` / `malformedResponse` | `unsupported` |

- 幂等 / 顺序 / 并发：无状态 `struct`；并发安全由 `EASClient` 与调用方保证。
- 超时 / 取消：由 `EASClient` 的传输层设置；本层不加超时。
- 一致性 / 可见性：单请求语义。
- 兼容性 / 废弃：实现的是 `MailGateway` v2；v1 的 `EASGateway` 已删除。
- 契约测试：`EASAdapterTests` 4 例（HTML 正文保留 payload/flags、服务端截断可见、纯文本标记、401→authFailed）；其余映射由 `EASClientTests` 的错误表覆盖协议侧。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| `probe/provisionIfNeeded/fetchFolders/fetchMessages` | ✅ `EASAdapter.swift` | `EASAdapterTests`；`SyncEngineTests` 经 fake 端口 |
| `fetchBody` → `FetchedBody`（D10） | ✅ | `EASAdapterTests` 3 例 |
| `fetchAttachment` / `send` | ✅ | `EASClientTests` 协议回放；`OutboxTests` 经 fake gateway |
| 唯一错误映射 | ✅ `EASAdapter.map` | `EASAdapterTests`「401 becomes authFailed in the domain catalog」 |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 错误映射 | 表驱动逐行；`EASClientTests` 覆盖 401/449/444/502/503/空 200/坏 body |
| 正文契约 | HTML、纯文本、截断三例；场景侧 `ReadSceneTests` 再验纯文本转 HTML |
| 依赖边界 | 门 1：只有 `EASAdapter`/`Composition`/`uumailctl` 可 import `EASClient` |
| 回归 | `./Scripts/swiftw test --filter EASAdapterTests` |

## 依赖约束

- 只依赖 `MailDomain` 与 `EASClient`；不 import `MailStore`/`Scenes`/`Presentation`。
- 契约里不出现 `EASClient` 类型；构造只发生在组合根（`GatewayFactory`）。

## 设计增量：Cc 映射（T-1114-04，待实现）

- `EASAdapter.message(_:)` 增加 `cc: message.cc`；`EASMessage.cc` 为空时传 `nil`。
- 不在本层拆分地址、去重或排除自己；这些统一在 `ComposeScene` 调用 `MailDomain.AddressList` 时做。本层只做 EAS → 领域值映射。
- 测试：`fetchMessages` 回放一条含 `Cc` 的 Sync 响应，断言 domain `Message.cc`；既有 HTML/纯文本/截断与 401 映射测试不回归。
