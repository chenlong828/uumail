---
layer: design
module: eas
status: active
updated: 2026-11-14
component: CMP-EAS
---

# CMP-EAS EASClient 组件规格

## 模块卡

- 状态：`active`（协议命令已落地；只经 `EASAdapter` 暴露给上层）
- 单元：组件
- 层 / 类型：L0；技术边界（协议实现）
- 业务价值：把 EAS 的 WBXML、HTTP、状态码、版本差异与网关怪癖收在一层。没有它，协议细节会渗进适配层与场景。
- 负责 X：HTTP 传输与超时、查询参数与身份头、WBXML 编解码、命令组装、状态码 → `EASError`、协议版本与 PolicyKey 生命周期、限流前置判断。
- 不负责 Y：业务状态机、存储、UI、重试预算与退避策略（调用方决定）；不直接实现 `MailGateway`（由 `EASAdapter` 负责）。
- 内部逻辑：每次调用固定拼 `Cmd/User/DeviceId/DeviceType` 与 `X-MS-PolicyKey`；`OPTIONS` 走裸 URL；空 `200` 视为网关吞请求并映射为设备未登记；`Provision` 为两步握手，策略项不解析（T9）。
- 拥有的数据：`device_profiles`（设备身份，由组合根/配置构造）；PolicyKey 只存在 `EASClient` 实例内（`private var policyKey`），**不持久化**，新进程首命令前重新握手。
- 变化轴：服务器实现（Exchange 2016/2019、第三方网关）、协议版本（16.1 → 14.1 → 14.0）。认证固定 Basic + TLS，不做 OAuth/Graph 抽象（T13）。
- 公开契约：`EASClient` 的协议方法（见能力清单）；上层只通过 `EASAdapter` 的 `MailGateway` 使用。
- 入口：`Sources/EASClient/EASClient.swift#EASClient`、`WBXML.swift#WBXML`、`URLSessionTransport.swift#URLSessionTransport`
- 依赖：Foundation（URLSession）、WBXML 编解码、传输层。扇出 0 本仓 target。
- 冷热：冷；独立 URLSession、连接数受限。
- 尺寸预算：≤1500 行；当前 1183 行（含 WBXML 与传输）。
- 单独运行：`./Scripts/swiftw test --filter EASClientTests`；协议探活另有命令行入口，见 playbook §7。
- 删除测试：删掉后 `EASAdapter` 要自己拼 HTTP 与 WBXML，版本降级复制两份 → 复杂度集中，是真边界。

## 能力清单

| 能力 ID | 命令 | 代码 | 备注 |
|---|---|---|---|
| `CMP-EAS#options` | `OPTIONS` | ✅ | 必须裸 URL，返回协议版本、命令列表与 `Set-Cookie` |
| `CMP-EAS#provision` | `Provision` | ✅ | 两步；PolicyKey 常驻 header，只在实例内存 |
| `CMP-EAS#folderSync` | `FolderSync` | ✅ | 每次取全量树；增量 key 只用于监测变更 |
| `CMP-EAS#sync` | `Sync` | ✅ | 请求体最小化；窗口 25 |
| `CMP-EAS#syncWrite` | `Sync` + `Commands` | ✅ 已实现（T-1114-12，2026-11-14） | `Change/Read=1` 与 `Delete`；先证网关接受并返回新 key（R16） |
| `CMP-EAS#fetchBody` | `ItemOperations`/`Fetch` | ✅ | 先取 20 万字符 HTML；`Truncated=1` 才免上限重取；返回 `FetchedBody{text,isHTML,isTruncated}` |
| `CMP-EAS#fetchAttachment` | `ItemOperations` | ✅ | `FileReference` 直取，base64 解码 |
| `CMP-EAS#send` | `SendMail` | ✅ | MIME 为 opaque 原始字节；返回 `200` + 0B 判成功 |
| `CMP-EAS#ping` | `Ping` | ✅ 方法存在 / ❌ 网关不支持长轮询 | 三档心跳均 `Status=4`（playbook §5.2）；方法仅作复测 |
| `CMP-EAS#moveItems` | `MoveItems` | ⬜ 未实现 | 移动留 `PendingOps` 工序；本批删除走 Sync `Delete`，不用 `MoveItems` |
| `CMP-EAS#search` | `Search`/`Find` | ❌ 不可用 | GAL `Store Status=2`；降级本地搜索 |

实测环境与线格式见 `design/components/CMP-EAS/playbook.md`（同目录）。

## 契约卡：EASClient v1（协议层）

- 签名（摘要）：

  ```swift
  public struct EASConfiguration: Sendable { host, account, password, domain, deviceID, deviceType, protocolVersion, allowInsecureTLS }
  public struct EASClient {
      public init(configuration: EASConfiguration, transport: any EASHTTPTransport)
      public func options() async throws -> EASServerCapabilities
      public func provision() async throws -> String
      public func currentPolicyKey() -> String?
      public func folderSync(syncKey: String = "0") async throws -> FolderSyncResult
      public func sync(collectionID:syncKey:window:filterType:bodyPreviewCharacters:change:) async throws -> SyncResult
      public func fetchBody(collectionID:serverID:truncationSize:) async throws -> FetchedBody
      public func fetchAttachment(fileReference:) async throws -> Data
      public func send(mime:clientID:) async throws -> String
      public func ping(collectionID:heartbeatSeconds:) async throws -> PingResult
  }
  ```

- 不变量：所有请求带 `DeviceId` 与协议版本头；`PolicyKey` 缺失时先 `provision()`；WBXML 以真实样本为准（NUL 结尾字符串、opaque blob）；`fetchBody` 必须读 `Truncated` 与 `Type`。
- 错误映射（`EASError`，实测）：

  | 现象 | `EASError` | 可重试 |
  |---|---|---|
  | HTTP 401（读） | `authFailed` | 否 |
  | Sync 写命令 401 | `deviceNotRegistered` | 否 |
  | `SendMail` 401 | `authFailed` | 否（既有 pinned 行为，本批不改） |
  | HTTP 449 / 策略拒绝 | `policyRequired` | 否（先 Provision） |
  | Sync `Status=3/4` | `syncKeyInvalid` | 是（重建） |
  | HTTP 503 + `Retry-After` | `throttled` | 是 |
  | HTTP 502（约 20s 后） | `protocolRejected` | 否 |
  | HTTP 444 | `gatewayRejected` | 否 |
  | 网络超时 | `transient` | 是 |
  | 其它 4xx/5xx | `permanent` / `malformedResponse` | 视码 |

- 幂等 / 顺序 / 并发：`send` 带 `ClientId`；同账号串行由调用方保证；本层不做跨账号并发假设。
- 超时 / 取消 / 背压：命令级 60s；取消传播到 URLSession；附件整包读取（未流式落盘）。
- 一致性 / 可见性：只做单次请求语义。
- 兼容性：协议版本按 `16.1 → 14.1 → 14.0` 降级并持久化；PolicyKey 不持久化（见模块卡）。
- 契约测试：`EASClientTests` 21 例 + `WBXMLTests` 6 例（golden 字节、错误映射表、401/449/503/空 200/坏 body、截断重取）。

## 实现进度（2026-11-14）

| 能力 | 代码 | 测试 |
|---|---|---|
| 编解码（NUL 字符串/opaque/code page） | ✅ `WBXML.swift` | golden 字节 + 回环 6 例 |
| `options/provision/folderSync` | ✅ | stub 传输 + 真机 |
| `sync`（信封、key、status 3/4、MoreAvailable） | ✅ | 4 例（含 `To`/`Cc` 回放与空白归一） |
| Sync 写命令（`Change/Read=1`、`Delete`） | ✅ 已实现（T-1114-12，2026-11-14） | golden 请求 + 写 401/3/4 测试绿；R16 真机/录制网关接受性仍未取证 |
| `fetchBody`（HTML/纯文本/截断重取） | ✅ | 3 例 |
| `fetchAttachment` / `send` | ✅ | 1 例 + 3 例 |
| `ping` | ✅ 方法 | 真机三档均 `Status=4` |
| `moveItems` / `search` | ⬜ / ❌ | — |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 编解码 | 每命令 XML → 字节 → XML round-trip；样本来自探针脱敏件 |
| 错误映射 | stub 传输回放 401/449/444/502/503/空 200 与 Sync 3/4 |
| 协议降级 | 模拟 16.1 失败后降 14.1，断言请求头（按需补） |
| 超时/限流 | 慢响应与 `Retry-After`；不在本层重试 |
| 安全 | 凭据只走 TLS、不落日志；`X-MS-PolicyKey` 不进普通日志 |

## 依赖与禁止边

- 禁止：`EASClient` → `MailStore`/`SyncEngine`/`Scenes`；契约里出现 WBXML 元素名、HTTP 头、URLQuery（`EASAdapter` 转换后不泄漏）。
- 允许：`EASAdapter` 构造并使用；`uumailctl` 诊断命令直连（D8 例外）；只有组合根构造具体类型。

## 设计增量：Sync Cc（T-1114-02，已实现 2026-11-14）

- 网关可达性已证（2026-11-14 真机 Sync 回放，收件箱窗口 25 封）：抽样邮件的 `ApplicationData` 同时返回 `To` 与 `Cc`，`Cc` 为可选字符串；因此按 REQ-0012 继续实现，不触发「不返回则停止」分支。证据见 `CMP-EAS/playbook.md` §5.3。
- `EASMessage` 增 `cc: String?`，放在初始化参数尾部、默认 `nil`；`parseMessage` 从 `ApplicationData/Cc` 读取，去掉首尾空白，空字符串/纯空白归一为 `nil`。
- `EASClientTests.syncResponse` fixture 已补 `To`/`Cc`：`parsesEnvelopes` 同时断言 `EASMessage.to`、`EASMessage.cc`；`blankCcIsNil` 钉住空白与缺失都归一为 `nil`。
- 线格式 token 已具备（`Sources/EASClient/Resources/eas_tokens.json` 的 Email page 2 `Cc` token 23）；不在场景层拼 WBXML，不改错误映射与协议命令。

## 设计增量：Sync 写命令（T-1114-10，2026-11-14 设计；T-1114-12 已实现）

- 新增值类型与可选参数（读请求默认 `nil`，既有调用点不变）：

  ```swift
  public enum EASSyncChange: Equatable, Sendable {
      case read(serverID: String)
      case delete(serverID: String)
  }
  public func sync(collectionID: String, syncKey: String = "0", window: Int = 25,
                   filterType: Int = 5, bodyPreviewCharacters: Int = 500,
                   change: EASSyncChange? = nil) async throws -> SyncResult
  ```

- 写请求（`change != nil`）只发最小体：
  `Sync/Collections/Collection/{SyncKey, CollectionId, Commands}`；不带 `WindowSize`、`Options`、`BodyPreference`。
  - `.read`：`<Commands><Change><ServerId>…</ServerId><ApplicationData><Read>1</Read></ApplicationData></Change></Commands>`
  - `.delete`：`<Commands><Delete><ServerId>…</ServerId></Delete></Commands>`
  - 元素顺序与 token 页以 playbook §3/§4 与 golden fixture 为准；一次只发一条命令。
  - 删除语义：不显式带 `DeletesAsMoves`，按 EAS 默认（移到「已删除邮件」）处理；T-1114-12 探针必须确认目标进入「已删除邮件」而非被永久删除。若网关默认是永久删除，停下并补 `DeletesAsMoves=1` 或重议 REQ-0014 的「不永久删除」约束。
- 响应沿用现有解析：`Collection/Status=1`、`SyncKey` 必须存在；`Commands` 里的 `Add/Change/Delete` 照常解析；`MoreAvailable` 原样返回。写响应若返回其它变更，由上层 `commit*` 与本地效果同事务应用；`moreAvailable == true` 由 `SyncEngine` 拒绝提交，不在此层猜测。
- 错误：写命令 HTTP 401 → `EASError.deviceNotRegistered`（playbook §6）；读 401 仍 `authFailed`；`SendMail` 既有 401 → `authFailed` 不改（pinned test）。`Status=3/4` → `syncKeyInvalid`；缺失 `SyncKey`/坏 body → `malformedResponse`。
- 前置门（R16，T-1114-12）：先用录制网关或真机样本证一条 `Change/Read=1` 与一条 `Delete` 被接受并返回新 key；记录响应是否含其它命令/`MoreAvailable`/逐条状态。被拒则停止，按 `REQ-0013`/`REQ-0014` 重议，不用 `MoveItems` 作未验证备胎。
- 测试：`EASClientTests` 补两条 golden 请求字节、写响应新 key、写 401、读 401 不回归、`Status=3/4`、缺失 key；既有 27 例不回归。
- 尺寸：`EASClient` 当前 759 行、组件 1183 行；预计 +50～60，仍低于 1500。

**实现（2026-11-14）**：`EASClient.sync(change:)` 支持 `.read`（`Change/ApplicationData/Read=1`）与 `.delete`（`Delete/ServerId`），写请求只带 `SyncKey/CollectionId/Commands`；写 401 → `deviceNotRegistered`，读 401 仍 `authFailed`。`EASClientTests` 31 例绿，含两条 golden 请求体、写 key、写 401/3/4。**R16 未取证**：本次没有可用真机/录制网关样本，不能声称网关已接受写命令；建议收尾前补真机探针。
