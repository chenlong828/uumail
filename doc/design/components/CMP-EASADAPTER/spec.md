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
- 负责 X：实现 `MailGateway` 的 7 个操作与 `MailWriteGateway` 的 2 个写操作（T-1114-10 设计，2026-11-14 已实现）；`ServerConfiguration → EASConfiguration` 的构造入口；`EASError → MailError` 的唯一映射；正文类型/截断标记的透传（D10）；MIME 以 opaque 字节送出。
- 不负责 Y：业务判断、重试策略、持久化、UI、MIME 组装（`Outbox/MimeBuilder`）。
- 内部逻辑：每个操作只做「调用 `EASClient` → 映射错误 → 转成领域值」；错误映射集中在 `EASAdapter.map`，不做重试。
- 拥有的数据：无。
- 变化轴：EAS 协议版本与网关差异。
- 公开契约：`CMP-EASADAPTER#MailGateway`、`#MailWriteGateway`（`MailGateway` v2 与 `MailWriteGateway` v1 的唯一生产实现）。
- 入口：`Sources/EASAdapter/EASAdapter.swift#EASAdapter`、`#map`
- 依赖：`MailDomain`、`EASClient`。扇出 2。
- 冷热：冷。
- 尺寸预算：目标 ≤300 行；当前 134 行。
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
- 契约测试：`EASAdapterTests` 6 例（HTML 正文保留 payload/flags、服务端截断可见、纯文本标记、401→authFailed；`fetchMessages` 的 `Cc` 映射、缺失/空白 `Cc` 保持 `nil`）；其余映射由 `EASClientTests` 的错误表覆盖协议侧。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| `probe/provisionIfNeeded/fetchFolders/fetchMessages` | ✅ `EASAdapter.swift` | `EASAdapterTests`；`SyncEngineTests` 经 fake 端口 |
| `fetchBody` → `FetchedBody`（D10） | ✅ | `EASAdapterTests` 3 例 |
| `fetchAttachment` / `send` | ✅ | `EASClientTests` 协议回放；`OutboxTests` 经 fake gateway |
| 唯一错误映射 | ✅ `EASAdapter.map` | `EASAdapterTests`「401 becomes authFailed in the domain catalog」 |
| `fetchMessages` → `Message.cc`（T-1114-04） | ✅ `EASAdapter.message(_:)` | `EASAdapterTests` 2 例：Add/Change 映射、缺失/空白为 `nil` |

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

## 设计增量：Cc 映射（T-1114-04，已实现 2026-11-14）

- `EASAdapter.message(_:)` 已把 `EASMessage.cc` 传给 domain `Message.cc`；`EASMessage.cc` 为空时保持 `nil`（`EASClient` 已把空白归一为 `nil`）。
- 不在本层拆分地址、去重或排除自己；这些统一在 `ComposeScene` 调用 `MailDomain.AddressList` 时做。本层只做 EAS → 领域值映射。
- 测试：`EASAdapterTests` 2 例。一次 Sync 回放同时含 `Add` 与 `Change`，断言 domain `Message.cc` 分别取到 `c@x.y; d@x.z` 与 `e@x.y`；缺失与空白 `Cc` 断言 `nil`。既有 HTML/纯文本/截断与 401 映射 4 例不回归。

## 设计增量：写端口映射（T-1114-10，2026-11-14 设计；T-1114-13 已实现）

- `EASAdapter` 追加遵循 `MailWriteGateway`：

  ```swift
  public func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta
  public func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta
  ```

- 每个方法只做三件事：调用 `client.sync(collectionID:syncKey:change:)` → `Self.map(error)` → 把 `SyncResult` 转成 `MessageDelta`（`added/changed/removedServerIDs/syncKey/moreAvailable` 全量透传）。
- 把 `fetchMessages` 里的 `SyncResult → MessageDelta` 映射抽成私有函数，读路径与写路径共用；不复制字段列表。
- 不判断消息是否可读/可删、不决定重试、不拆地址、不落库；业务判断留在 `SyncEngine`/场景。
- 错误：写 401 由 `EASClient` 映射为 `deviceNotRegistered`，本层按表映射为 `MailError.deviceNotRegistered`；`syncKeyInvalid`/`throttled`/`offline`/`unsupported` 沿用现有表；不新增 `MailError` case。
- 装配：生产 `PlatformGateway.make` 返回 `GatewayEndpoints(read: adapter, write: adapter)`，`read`/`write` 是**同一个 `EASAdapter` 实例**；装配测试断言 `write` 的类型/来源，不用 `nil` 表示只读。
- 测试：`EASAdapterTests` 补 `markRead`/`delete` 的 delta 透传与错误映射（写 401、3/4、offline）；既有 6 例不回归。
- 尺寸：当前 134 行；预计 +30，仍低于 300。

**实现（2026-11-14）**：`EASAdapter` 同时遵循 `MailGateway` 与 `MailWriteGateway`；读/写响应共用 `Self.delta` 全量透传。`EASAdapterTests` 9 例绿，含 markRead/delete delta、写 401、3/4、503、500 映射。

## 设计增量：会议邀请映射（REQ-0029 / REQ-0030，2026-11-24，已实现）

- 来源：`CMP-EAS` 的 `EASMeeting`/`EASRecurrence`/`EASMeetingTimeZone`（见其增量）→ `MailDomain.MeetingInvite`。
- `map(message:)` 增补（`EASAdapter.swift` +约 60 行）：
  - 只为 `messageClass == "IPM.Schedule.Meeting.Request"` 生成 `MeetingInvite`；`"IPM.Schedule.Meeting.Canceled"` 生成 `isCancelled = true` 的 `MeetingInvite`（保留 `uid`，由 `MailStore` 删除对应行）；`IPM.Schedule.Meeting.Resp.*` 与 `IPM.Note*` 不生成会议。
  - `EASMeeting` → `MeetingInvite`：`messageType` 缺省按 `.initial`；`interval` 归一为 `max(1, …)`；`weekdays` 由位掩码展开（未知位忽略）；`DayOfWeek == 127` → `lastDayOfMonth = true`；`weekOfMonth` 限定 1…5；`until` 原样（UTC）；`timeZone` 由 `biasMinutes` 转 `offsetSeconds = -bias * 60`，名称保留。
  - `instanceType == 1`（主系列）→ `recurrence` 来自 `Recurrences/Recurrence`；`instanceType == 3`（例外）→ 不带 `recurrence`，由 `MailStore` 合并进主系列的 `exceptions`（按 `recurrenceId`）；`instanceType` 为 2/4 与缺失按单次处理（无法归属时宁可按单次显示，不猜系列）。
  - `start/end` 缺失 → 不生成 `MeetingInvite`（退化为普通邮件，不阻塞信封落库）。
- 不变量：映射不改变信封字段；不触网；EAS 类型不外漏；纯函数（可单测）。
- 测试（`EASAdapterTests`）：请求/取消/其它 Class 三条；位掩码 62/65/127；每月第 3 个周三；`bias -480` → `offsetSeconds 28800`；缺 `start` 退化为无会议。

## 实现（2026-11-24，T-1124-07）

- `EASAdapter.meeting(_:)`：只为 `IPM.Schedule.Meeting.*` 生成会议；取消标记、`instanceType` 例外、
  `biasMinutes → offsetSeconds`、位掩码展开均在映射层归一；`EASAdapter.message` 改为 internal 供测试直接调用。
- 测试：`Tests/EASAdapterTests/EASAdapterTests.swift` 新增 5 例（字段映射、取消、普通邮件、缺时间、例外）。