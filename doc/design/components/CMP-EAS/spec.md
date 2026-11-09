---
layer: design
module: eas
status: planned
updated: 2026-11-09
component: CMP-EAS
---

# CMP-EAS EASClient 组件规格

## 模块卡

- 状态：`active`（只读命令已落地并通过真实网关验证；Sync/正文/附件/发送未实现）
- 单元：组件
- 层 / 类型：L0；技术边界（防腐层）
- 业务价值：把 EAS 的 WBXML、HTTP、状态码、版本差异与网关怪癖挡在领域契约之外。没有它，协议细节会渗进同步编排与 UI。
- 负责 X：HTTP 传输与超时、查询参数与身份头、WBXML 编解码、命令组装、状态码 → 领域错误、协议版本降级、策略 key 生命周期、限流前置判断。
- 不负责 Y：业务状态机（CMP-SYNC）、存储、UI、重试预算与退避策略（由调用方决定）。
- 内部逻辑：每次调用固定拼 `Cmd/User/DeviceId/DeviceType` 与 `X-MS-PolicyKey`；`OPTIONS` 走裸 URL；空 `200` 视为网关吞请求并映射为设备未登记；`Provision` 为两步握手，策略项不解析（D9）。
- 拥有的数据：`device_profiles`（deviceId、deviceType、protocolVersion、userAgent）由其 DeviceProfileStore 唯一写入；PolicyKey 属凭据，存 Keychain，不落普通表。
- 变化轴：服务器实现（Exchange 2016/2019、第三方网关）、协议版本（16.1 → 14.1 → 14.0）。认证固定 Basic + TLS，不做 OAuth/Graph 抽象（D13）。
- 公开契约：实现 `MailGateway` 端口，能力 ID 见下。
- 入口：`Sources/EASClient/EASClient.swift#EASClient`、`Sources/EASClient/WBXML.swift#WBXML`（planned）
- 依赖：URLSession（独立配置）、WBXMLCodec、CredentialProvider（Keychain，Basic only）、DeviceProfileStore。扇出 4。
- 冷热：冷；独立 URLSession、连接数受限，不与热路径共享队列。
- 尺寸预算：≤ 120k token；当前 0。
- 单独运行：`swift test --filter EASClientTests`（planned）；协议探活另有命令行入口，见 playbook §7。
- 删除测试：删掉后 CMP-SYNC 与 CMP-OUT 各自拼 HTTP 与 WBXML，版本降级逻辑复制两份 → 复杂度集中，是真边界。

## 能力清单（MailGateway 实现面）

| 能力 ID | 命令 | 实测状态 | 备注 |
|---|---|---|---|
| `CMP-EAS#options` | `OPTIONS` | ✅ | 必须裸 URL，返回协议版本与命令列表、`Set-Cookie` |
| `CMP-EAS#provision` | `Provision` | ✅ | 两步；PolicyKey 常驻 header |
| `CMP-EAS#folderSync` | `FolderSync` | ✅ | 每次取全量树，增量 key 只用于监测变更 |
| `CMP-EAS#sync` | `Sync` | ✅ | 请求体最小化；窗口 25 |
| `CMP-EAS#fetchBody` | `ItemOperations`/`Fetch` | ✅ | 2 万字符 HTML |
| `CMP-EAS#fetchAttachment` | `ItemOperations` | ✅ | `FileReference` 直取 |
| `CMP-EAS#send` | `SendMail` | ✅ | MIME 为 opaque 原始字节，返回 `200` + 0B |
| `CMP-EAS#moveItems` | `MoveItems` | ⚠️ 未验证 | M1 不依赖；删除/移动先做本地意图 |
| `CMP-EAS#search` | `Search` / `Find` | ❌ | GAL `Store Status=2`；降级本地搜索 |
| `CMP-EAS#ping` | `Ping` | ⚠️ 未验证 | 未通过前按轮询排期 |

实测环境与参数细节见 `design/components/CMP-EAS/playbook.md`（同目录）。

### 实现进度（2026-11-09）

| 能力 | 代码 | 测试 |
|---|---|---|
| 编解码（NUL 字符串/opaque/code page） | ✅ `WBXML.swift` | golden 字节 + 回环 |
| `options` / `provision` / `folderSync` | ✅ `EASClient.swift` | stub 传输 + 真实网关 |
| `sync` / `fetchBody` / `fetchAttachment` / `send` / `moveItems` / `search` / `ping` | ⬜ | — |

## 契约卡：MailGateway / EASClient v1（planned）

- 签名（只用本方稳定类型）：
  - `folderSync(key: SyncKey) async throws -> FolderSyncResult`
  - `sync(collection: CollectionRef, key: SyncKey, window: Int) async throws -> SyncBatch`
  - `fetchBody(message: CollectionRef, preference: BodyPreference) async throws -> BodyResult`
  - `fetchAttachment(ref: AttachmentRef) async throws -> AttachmentData`
  - `send(_ message: MimeMessage, clientId: ClientId) async throws`
  - `moveItems(_ moves: [MoveRequest]) async throws -> [MoveResult]`
  - `search(_ query: SearchQuery) async throws -> SearchResult`
  - `ping(collection: CollectionRef, key: SyncKey) async throws -> PingResult`
- 不变量：所有请求带 `DeviceId` 与协议版本头；`PolicyKey` 缺失时先 Provision；WBXML 编码以真实样本为准（NUL 结尾字符串、opaque blob）。
- 错误映射（实测）：

| 现象 | 领域错误 | 可重试 | 调用方应对 |
|---|---|---|---|
| HTTP 401 | `authFailed` | 否 | 转登录态；写命令被拒也可能是设备未激活，先查设备状态 |
| HTTP 449 / `X-MS-ASError` | `policyRequired` | 否 | 进 Provision；仍失败则 `policyBlocked` |
| `200` + 0 字节 body | `deviceNotRegistered` | 否 | 提示设备登记；不重试，不做退避 |
| HTTP 502（约 20s 后） | `protocolRejected` | 否 | 请求体格式错（字符串/opaque/Sync 体）；按 playbook §4 校正 |
| HTTP 444 | `gatewayRejected` | 否 | 缺 `Cmd/User/DeviceId/DeviceType` 参数 |
| HTTP 503 + `Retry-After` | `throttled(after:)` | 是 | 按 `Retry-After` 退避 |
| 网络超时 | `transient` | 是 | 交由 CMP-SYNC 退避；不在此层重试 |
| Sync `Status=3/4` | `syncKeyInvalid` | 否 | 清集合后全量重建 |
| 其它 4xx/5xx | `permanent` / `transient` 按码分类 | 视码 | 交调用方分类 |

- 幂等 / 顺序 / 并发：`send` 带 `ClientId`；同账号串行（由 CMP-SYNC 保证）；本层不做跨账号并发假设。
- 超时 / 取消 / 背压：命令级 60s，Ping 独立长超时，附件下载流式写入。
- 一致性 / 可见性：只做单次请求语义，不保证跨命令一致性。
- 兼容性：协议版本按 `16.1 → 14.1 → 14.0` 降级并持久化；降级是兼容性变更，需记录到 ADR。
- 契约测试：golden WBXML round-trip、错误映射表逐行、401/449/503/空 200/坏 body。

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 编解码 | 每命令 XML → 字节 → XML round-trip；样本来自探针脱敏件 |
| 错误映射 | Fake EAS 回放 401/449/444/502/503/空 200 与 Sync 3/4 |
| 协议降级 | 模拟 16.1 失败后降 14.1，断言请求头与能力裁剪 |
| 超时/限流 | 注入慢响应与 `Retry-After`，断言不并发轰炸 |
| 安全 | 断言凭据只走 TLS、不落日志；`X-MS-PolicyKey` 不进普通日志 |

## 依赖与禁止边

- 禁止：CMP-EAS → CMP-STORE / CMP-SYNC（反向上层）；CMP-EAS 契约里出现 WBXML 元素名、HTTP 头、URLQuery。
- 允许：CMP-SYNC、CMP-OUT 通过 `MailGateway` 端口调用；只有组合根能构造本组件具体类型。
