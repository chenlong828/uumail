---
layer: design
module: domain
status: active
updated: 2026-11-24
component: CMP-DOMAIN
---

# CMP-DOMAIN MailDomain 组件规格

## 模块卡

- 状态：`active`
- 单元：模块（值类型 + 端口 + 错误目录的组合组件）
- 层 / 类型：L1 契约；领域
- 业务价值：让场景、数据与协议都只认识一套稳定概念。没有它，每个 target 自带一份值类型，改一个字段要动四处。
- 负责 X：值类型（`AccountID`、`OutboxID`、`Folder`、`Message`、`Attachment`、`Draft`、`OutboxItem`、`FolderListing`、`MessageDelta`、`SyncReport`、`FetchedBody`、`AttachmentRef`、`ServerCapabilities`，2026-11-18 新增的 `ContactAddress`、`ContactEnvelope`、`ContactDirectory`、`RecipientText`，以及 2026-11-24 新增的 `MeetingInvite`、`RecurrenceRule`、`MeetingException`、`MeetingOccurrence`、`MeetingTimeZone`、`MeetingMessageType`、`Weekday`）、端口（`MailGateway`、`MailWriteGateway`、`SyncStore`、`CredentialStore`、`Notifier`、`AttachmentFiles`、`MailClock`）、`MailError`、`ServerConfiguration`。
- 不负责 Y：任何 I/O、持久化、协议编解码、UI 文案。
- 内部逻辑：无 I/O；只有纯值类型与纯函数——`AddressList` 的信封归一化、`ContactDirectory` 的解析/去重/名字回退/匹配排序、`RecipientText` 的尾片段与替换。`FetchedBody` 保留 `text/isHTML/isTruncated`（D10）。
- 拥有的数据：无持久数据。
- 变化轴：领域概念本身的字段与语义（邮件、文件夹、发送意图）。
- 公开契约：`CMP-DOMAIN#MailGateway`、`#MailWriteGateway`（T-1114-10 设计，2026-11-14 已实现；作为非可选生产能力注入）、`#SyncStore`、`#CredentialStore`、`#Notifier`、`#AttachmentFiles`、`#MailClock`、`#ContactAddress`、`#ContactEnvelope`、`#ContactDirectory`、`#RecipientText`（2026-11-18 新增，REQ-0022/SCN-0017）；能力 ID 由各操作名引用（如 `CMP-DOMAIN#fetchBody`、`#ContactDirectory.suggestions`）。
- 入口：`Sources/MailDomain/Values.swift#AccountID`、`Ports.swift#MailGateway`、`Errors.swift#MailError`、`Configuration.swift#ServerConfiguration`、`Contacts.swift#ContactAddress`、`#ContactEnvelope`、`#ContactDirectory`、`#RecipientText`（2026-11-18 新增）
- 依赖：仅 Foundation。扇出 0。
- 冷热：两侧共用；只做值传递。
- 尺寸预算：目标 ≤800 行；当前 545 行（`wc -l` 2026-11-18，`AddressList` 等 5 个文件）；2026-11-18 设计新增 `Contacts.swift` 约 150 行 → 约 695 行，仍低于 800；上限 120k token。
- 单独运行：`./Scripts/swiftw test --filter MailDomainTests`
- 删除测试：删掉后 `Scenes`、`MailStore`、`SyncEngine`、`Outbox` 各自定义同名类型并互相转换 → 复杂度集中，是真边界。

## 契约卡：MailGateway v2

- 所属 / 目的：把服务器能力以本方概念提供给场景与同步。
- 签名：

  ```swift
  public protocol MailGateway: Sendable {
      func probe() async throws -> ServerCapabilities
      func provisionIfNeeded() async throws
      func fetchFolders(syncKey: String) async throws -> FolderListing
      func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta
      func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody
      func fetchAttachment(fileReference: String) async throws -> Data
      func send(mime: Data, clientID: String) async throws
  }
  ```

- 不变量：不泄漏 EAS 类型或状态码字符串；`send` 成功当且仅当服务器返回 `200` 且 0 字节 body；`fetchFolders(syncKey:"0")` 返回全量树。
- 错误模式：唯一目录 `MailError`，映射只发生一次（`EASAdapter.map`）：

  | 来源 | `MailError` | 可重试 |
  |---|---|---|
  | `401` 读 | `authFailed` | 否 |
  | `200` 空 body（`FolderSync`/`ItemOperations`） | `deviceNotRegistered` | 否 |
  | `200` 空 body（`Sync` 读或写） | `syncKeyInvalid` | 是（重建；2026-11-17 实测，见 `CMP-EAS` 设计增量） |
  | Sync 响应缺 `Collection/Status` | `syncKeyInvalid` | 是（重建） |
  | `SendMail` 401 | `authFailed` | 否（既有 pinned 行为，本批不改） |
  | Sync 写命令 401 | `deviceNotRegistered` | 否（T-1114-10 设计，2026-11-14 已实现） |
  | `449` / 策略拒绝 | `policyBlocked` | 否 |
  | Sync `3/4` | `syncKeyInvalid` | 是（重建） |
  | `503` + `Retry-After` | `throttled(seconds:)` | 是 |
  | 连接失败/超时 | `offline` | 是 |
  | `444`/`502`/坏 WBXML | `unsupported` | 否 |
  | 本地失败 / 非法输入 | `storage(reason:)` / `invalidInput(reason:)` | 视调用方 |

- 幂等 / 顺序 / 并发：`send` 以 `clientID` 为幂等键；读操作无副作用；单请求语义，不保证跨命令一致。
- 超时 / 取消 / 背压：由实现层设置（单命令 60s、`send` 90s）；取消传播到 URLSession。
- 兼容性 / 废弃：v2 相对 v1 新增 `probe/fetchBody/fetchAttachment/send`；`FetchedBody` 为 D10 决策（`history/decisions/2026-11-13-fetched-body-contract.md`）。
- 契约测试：`MailDomainTests` 值类型；`EASAdapterTests` 错误与正文映射；`EASClientTests` 协议层回放。

## 契约卡：SyncStore

- 所属 / 目的：同步引擎读写本地事实的最小端口，去掉旧的 `StoreAdapter` 与 `async`（D6）。
- 签名：`folders`、`applyFolderSnapshot`、`syncKey`、`applySyncBatch`、`resetCollection`（均为同步 `throws`）；已实现 `markRead`、`commitMarkRead`、`commitDelete`（T-1114-14；见文末设计增量）。
- 不变量：批次与 key 同事务；失败不推进 key；`(account, folder, serverID)` 幂等。
- 错误模式：存储错误以 `MailStoreError` 抛出；`SyncEngine` 原样上抛。
- 并发：`MailStore` 用 `DatabaseQueue` 单写；端口本身不承诺跨实例并发。
- 契约测试：`SyncEngineTests`（fake store）+ `MailStoreTests`（真实 SQLite）。

## 契约卡：平台端口

`CredentialStore`（`load/save/delete`）、`Notifier`（`requestAuthorization/postNewMail`）、`AttachmentFiles`（`cachedURL/store`）、`MailClock`（`now/sleep`）。

- 不变量：端口实现不得反向依赖场景；`AttachmentFiles.store` 原子写并执行 2 GB 最旧优先预算（`history/decisions/2026-11-09-attachment-cache-cap.md`）。
- 错误模式：`storage`、`invalidInput`；凭据错误不吞。
- 契约测试：`FileAttachmentFilesTests`、`CompositionTests` 的装配冒烟；时钟替身让轮询测试即时。

## 设计增量（2026-11-21，Attachment.contentID）

- `Attachment` 增加 `contentID: String?`（MIME `Content-ID`，正文 `cid:` 指向它）；两个 `init` 都带默认值 `nil`，
  属兼容扩展，现有构造点不受影响。
- `EASAdapter` 从 `EASAttachment.contentID` 映射；`MailStore` v11 持久化并在 `attachments(...)` 读回。
- 消费方：`InlineImageHTML.matches` 以 `contentID` 优先匹配（见 `CMP-SCN-READ`）。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| 值类型与 `ServerConfiguration`（旧 Keychain 载荷带默认值解码） | ✅ `Values.swift`、`Configuration.swift` | `MailDomainTests` 10 例（含 SCN-0007 增量） |
| `MailError` 9 个 case | ✅ `Errors.swift` | `EASAdapterTests` / `CompositionTests` 断言映射 |
| `MailGateway` v2 + `FetchedBody` | ✅ `Ports.swift`、`Values.swift` | `EASAdapterTests` 4 例 |
| `SyncStore` 同步端口，`MailStore` 直接遵循 | ✅ `Ports.swift`、`MailStore/SyncStoreConformance.swift` | `SyncEngineTests`、`MailStoreTests` |
| 平台端口 | ✅ `Ports.swift` | `FileAttachmentFilesTests` 等 |
| `Message.cc`（可选）与 `AddressList` 归一化 | ✅ `Values.swift`、`AddressList.swift` | `MailDomainTests` 7 例：cc 默认/相等、拆分、形态、去重、集合运算（含 `<team>` 与 `<>` 内 `;` 不二次解析） |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 契约形状 | `MailDomainTests` 值类型默认值与相等性；编译期端口遵循 |
| 错误目录 | `EASAdapter.map` 表驱动断言（401→authFailed 等） |
| 正文契约 | `EASAdapterTests` 的 HTML/纯文本/截断三例（D10） |
| 依赖约束 | `Scripts/check-architecture.sh` 门 1：`MailDomain` 只 import `Foundation` |

## 依赖约束

- 只依赖 Foundation；不 import 任何本仓 target、GRDB、URLSession 包装。
- 上层通过端口与值类型使用；实现只在组合根出现。

## 设计增量：SCN-0007（T-1114-03，2026-11-14 已实现）

- `Message` 增 `cc: String?`，默认 `nil`，放在既有初始化参数尾部；`recipients` 仍是 To。只加可选字段，不改 `MailGateway`/`SyncStore` 签名。
- 新增 `Sources/MailDomain/AddressList.swift` 的纯值类型（无 I/O）：

  ```swift
  public struct AddressList: Equatable, Sendable {
      public private(set) var addresses: [String]
      public init(_ raw: String?)
      public init(_ raws: [String?])
      init(normalized addresses: [String])  // internal: trusts already-normalized addresses
      public var isEmpty: Bool
      public var text: String
      public func appending(_ other: AddressList) -> AddressList
      public func removing(_ address: String?) -> AddressList
      public func subtracting(_ other: AddressList) -> AddressList
  }
  ```

- 规则：顶层按 `;`/`,` 拆，引号内与 `<>` 内不拆；有 `<>` 取内部并保留（非空），否则去掉包裹引号后取整段；无 `<>` 时只保留含 `@`、以 `/` 开头、或含 `=` 且无空白的段；小写去重、保序，输出 `"; "` 连接。裸显示名/裸通讯组名跳过，不展开、不查 GAL；不实现 RFC 5322 完整解析（转义引号、组语法不特殊处理）。
- 集合运算：`appending`/`removing`/`subtracting` 通过内部 `init(normalized:)` 接收已归一化地址，只做小写去重、不再拆分或形态过滤；避免 `Team <team>` 在二次解析时被丢、`Team <a@x;b@y>` 的 `;` 在二次解析时被拆成两址。
- 兼容性：`AddressList` 是 `MailDomain` 内新增值类型，不是新组件/target；本模块仍只依赖 Foundation、无 I/O。
- 定位不变：`AddressList` 是纯值类型上的归一化函数，不读写任何端口；`MailDomain` 仍是「值类型 + 端口 + 错误目录」，不引入业务状态或 I/O。
- 测试：`MailDomainTests` 补 `Message.cc` 默认值/相等性与 `AddressList` 表驱动（引号、尖括号、重复、空输入、DN 形态）；集合运算补 `<team>` 与 `<>` 内 `;` 的回归，锁住「已归一化地址不再解析」；`ComposeScene` 只调用，不复制规则。
- 实现（2026-11-14）：`Values.swift#Message.cc` 默认 `nil`；`AddressList.swift` 按上述规则拆分归一化；集合运算走内部 `init(normalized:)`。`MailDomainTests` 10 例绿（新增 7 例：cc 默认/相等、拆分、形态、去重、集合运算、`<team>` 集合运算回归、`<>` 内 `;` 集合运算回归），全量 167 tests / 37 suites 绿。

## 设计增量：邮箱写路径（T-1114-10，2026-11-14 设计；T-1114-11/14 已实现）

- 新增窄写端口，不扩 `MailGateway`（只读 fake 与读契约不受影响）：

  ```swift
  public protocol MailWriteGateway: Sendable {
      func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta
      func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta
  }
  ```

- `MessageDelta` 复用为写响应：`added/changed/removedServerIDs/syncKey/moreAvailable` 都有效；适配层不裁剪。一次调用只发一条 Sync 写命令。
- `SyncStore` 增三个方法（签名见 `CMP-STORE/spec.md` 设计增量）：

  ```swift
  func markRead(_ account: AccountID, folder: String, serverID: String) throws -> Bool
  func commitMarkRead(_ account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws
  func commitDelete(_ account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws
  ```

- 不变量：写端口成功当且仅当 `Status=1` + 非空新 key；`commit*` 把响应 delta、本地效果与新 key 放同一事务；失败不推进 key。`MailError` 不新增 case：写 401 → `deviceNotRegistered`、`Status=3/4` → `syncKeyInvalid`、其余按既有目录。
- **非可选能力**：`MailWriteGateway` 不是“可选注入、nil 退化”的能力；`GatewayEndpoints.write`、`SyncEngine.init(writeGateway:)`、`ReadScene.init(writeEngine:)` 都要求非可选实现。生产 target 不提供 `UnsupportedWriteGateway`；只读测试在测试 target 定义该替身并显式注入。
- **命名映射**：`MailWriteGateway.collectionID` 是 EAS 集合 ID；`SyncStore.folder` 是本地文件夹 ID。既有调用以 `MessageRef.folderID` 传 `collectionID`；新增实现必须保持该映射，不得混用。
- 兼容性：`MailGateway` 7 个方法不变；`Message`/`Draft`/`Outbox` 值类型不变；`MailDomain` 仍只依赖 Foundation、无 I/O。尺寸预计 +15 行（515 → 约 530），远低于 800 行目标。
- 契约测试：`MailDomainTests` 只做编译期端口遵循；`EASAdapterTests`/`SyncEngineTests`/`MailStoreTests` 覆盖行为。

**实现（2026-11-14）**：`Ports.swift` 的 `MailWriteGateway` 两方法已落地；`SyncStore` 增三方法，`MailStore` 实现并由 `SyncStoreConformance` 转发。`MailDomainTests` 的测试替身只覆盖端口形状；`MailWriteGateway` 未进入生产 target 的 nil/默认退化路径。全量 239 tests / 44 suites 绿（2026-11-14 回退重跑复测）。

## 设计增量：Draft/OutboxItem 的 HTML 正文（REQ-0021，2026-11-17）

- `Draft` 新增 `public var bodyHTML: String?`（init 末尾可选，默认 nil）；`OutboxItem` 同样新增可选 `bodyHTML`。语义：`body` 始终是纯文本替代（有 HTML 时由编辑器内容生成），`bodyHTML` 是完整 HTML 文档；`nil` 保持旧的纯文本 MIME 形状。
- 兼容性：可选 + 默认 nil，既有 `Draft(...)` 调用、CLI `send`、旧 outbox 行（v10 前读出 nil）全部不破；`Equatable` 对旧值仍相等。`bodyHTML` 为 nil 或纯空白时 `MimeBuilder` 走单段 `text/plain`。
- 不新增端口/错误类型；`MailDomain` 仍只 import Foundation。`body`/`bodyHTML` 的生成与清洗在 `Scenes.HTMLText`/`ComposeScene`，本组件只承载值。
- 验证：编译期由 `ScenesTests`/`PresentationTests`/`OutboxTests` 构造带 HTML 的 `Draft` 覆盖；旧构造调用不回归（全量 292 tests / 51 suites）。

## 设计增量：收件人联想目录（REQ-0022 / SCN-0017，2026-11-18，P1 默认确认、未实现）

- 新增 `Sources/MailDomain/Contacts.swift`，public 纯值类型（只依赖 Foundation，无 I/O）：

  ```swift
  public struct ContactAddress: Equatable, Sendable, Identifiable {
      public let name: String?
      public let address: String
      public var id: String { address.lowercased() }
      public init(name: String?, address: String)
  }

  public struct ContactEnvelope: Equatable, Sendable {
      public let sender: String?
      public let recipients: String?
      public let cc: String?
      public let receivedRaw: String?
      public init(sender: String?, recipients: String?, cc: String?, receivedRaw: String?)
  }

  public struct ContactDirectory: Equatable, Sendable {
      public init(envelopes: [ContactEnvelope], excluding: [String] = [])
      public var isEmpty: Bool { get }
      public func suggestions(
          for fragment: String,
          excluding: [String] = [],
          limit: Int = 8
      ) -> [ContactAddress]
  }

  public enum RecipientText {
      public static func tailFragment(in text: String) -> String
      public static func prefixBeforeTail(in text: String) -> String
      public static func replacingTail(in text: String, with address: String) -> String
  }
  ```

- 解析规则：信封按顶层 `;`/`,` 拆分，引号内与 `<>` 内不拆；有 `<>` 取内部为地址、`<>` 前为显示名（去包裹引号、折叠空白）；无 `<>` 且含 `@` 的整段为地址、名字为 nil；只接受**恰好一个 `@`、local/domain 非空、无空白且不含 `;`/`,`/`<`/`>`/引号**的 SMTP 地址，跳过裸显示名、通讯组名、Exchange DN、未闭合/空 `<>`、以及 `Team <a@x;b@y>` 这类 `<>` 内塞多地址的畸形段。名字为空、与地址相同、或形如 RFC 2047 编码词（`=?...?=`）时按「无可用名字」，不显示编码乱码。不展开通讯组、不查目录、不做拼音/首字母/模糊音。
- 去重与排序：按小写地址去重；同一地址多个名字取**最近一次非空名字**（`receivedRaw` 降序近似最近，同值按输入顺序稳定）；构建时排除 `excluding`（当前账号地址），查询时再排除 `excluding`（已填地址，大小写不敏感、trim 后为空则忽略；`excluding` 只收地址字符串，调用方先用 `AddressList` 归一出纯地址）。`suggestions` 大小写不敏感，排序键为「地址前缀 → 显示名前缀 → 地址子串 → 显示名子串 → 最近出现 → 地址小写」，结果可复现；空/纯空白片段返回空；`limit` 夹取到 `0...8`，0/负数返回空。每文件夹 500/总计 5,000 的读取上限是 `CMP-SCN-COMPOSE` 的策略，不在本组件。
- `RecipientText`：尾片段 = 最后一个顶层 `;`/`,` 之后的文本（trim 后返回）；`prefixBeforeTail` 返回该分隔符及其前文本（无分隔符返回空串）；`replacingTail` 用纯地址替换尾片段并补 `; `，保留前缀，空地址原样返回。光标在中间/有选区时由调用方禁止调用，不在本类型判断 UI。
- 解析器归位：把 `AddressList` 的私有 `split`/段解析抽成模块内 `EnvelopeParser`（internal），`AddressList` 与 `ContactDirectory` 共用；`AddressList` 的公开拆分/取址/去重输出不变（既有 `MailDomainTests` 钉住），`ContactDirectory` 只额外使用 `isSMTP` 过滤与显示名。
- 错误模式：无 throwing；畸形段跳过，构建/查询失败等价于空目录；不做失败重试、不产生用户可见错误。
- 兼容性：纯增量 public 值类型；不改 `AddressList` 公开行为、不改 `MailGateway`/`SyncStore`/`Message`/`Draft`；不新增依赖/target；`MailDomain` 仍只 import Foundation、无 I/O。
- 测试：`MailDomainTests/ContactDirectoryTests`（名字保留/回退、最近非空名字、去重、匹配排序、畸形/DN/RFC 2047、limit/排除、空片段、引号内逗号/未闭合 `<>`、`Team <a@x;b@y>`/`a@x,b@y` 不产生候选）与 `RecipientTextTests`（尾片段/前缀/替换、引号与 `<>`、空片段）；`AddressList` 既有用例必须全绿（尤其保留 `/O=…`、`CN=z`、`Team <team>` 等非 SMTP 形状，不得因共享解析器归位而收窄）。场景/视图模型测试见 `SCN-0017`。
- 定级/确认：本增量属 P1（平台级扇入模块新增 public 契约）；默认确认（未经人工）见 `history/decisions/2026-11-18-recipient-autocomplete.md`，交评审判断；A1–A6 细化见 `history/decisions/2026-11-18-recipient-autocomplete-design-addendum.md`。

## 设计增量：会议邀请值类型与 iCalendar（REQ-0029 / REQ-0030，2026-11-24，P1 已确认、已实现）

- 来源：`REQ-0029`/`REQ-0030`；协议字段见 `CMP-EAS` 增量；存储见 `CMP-STORE` v12。
- 新增 public 值类型（`Sources/MailDomain/Meeting.swift`，约 260 行）：

  ```swift
  public enum MeetingMessageType: Int, Sendable { case initial = 1, update = 2, informational = 3, outdated = 4, delegatorCopy = 5, delegated = 6 }
  public enum Weekday: Int, Sendable, CaseIterable { case sunday = 1, monday = 2, tuesday = 4, wednesday = 8, thursday = 16, friday = 32, saturday = 64 }

  public struct MeetingTimeZone: Equatable, Sendable {
      public var name: String?
      public var offsetSeconds: Int          // -bias(分钟) * 60
  }

  public struct RecurrenceRule: Equatable, Sendable {
      public enum Frequency: Int, Sendable { case daily = 0, weekly = 1, monthlyDay = 2, monthlyWeekday = 3, yearlyDay = 5, yearlyWeekday = 6 }
      public var frequency: Frequency
      public var interval: Int               // >= 1
      public var until: Date?                // UTC；与 occurrences 互斥
      public var occurrences: Int?           // 1...999
      public var weekdays: Set<Weekday>      // Type 0 带 DayOfWeek 视为 weekly
      public var dayOfMonth: Int?            // 1...31
      public var weekOfMonth: Int?           // 1...4，5 = 最后
      public var monthOfYear: Int?           // 1...12
      public var firstDayOfWeek: Weekday     // 默认 .monday
      public var lastDayOfMonth: Bool        // DayOfWeek=127 的特殊语义（Type 3/6）
  }

  public struct MeetingException: Equatable, Sendable {
      public var recurrenceId: Date          // 原始实例开始（UTC）
      public var start: Date?
      public var end: Date?
      public var subject: String?
      public var location: String?
      public var isDeleted: Bool
  }

  public struct MeetingInvite: Equatable, Sendable {
      public var uid: String
      public var subject: String?
      public var start: Date
      public var end: Date
      public var isAllDay: Bool
      public var location: String?
      public var organizer: String?
      public var reminderMinutes: Int?
      public var responseRequested: Bool
      public var busyStatus: Int?
      public var messageType: MeetingMessageType
      public var isCancelled: Bool
      public var dtstamp: Date?
      public var timeZone: MeetingTimeZone?
      public var recurrence: RecurrenceRule?
      public var exceptions: [MeetingException]
      // 来源（folderID/serverID）不在这里：适配器不知道所在文件夹，
      // 由 MailStore 在读时填进 MeetingOccurrence。

      /// 可见范围内的实例；有界：<= limit，且不早于系列起点。
      public func occurrences(in range: ClosedRange<Date>, limit: Int = 200) -> [MeetingOccurrence]
      /// iCalendar 文本（单次事件或整个系列）；METHOD:PUBLISH。
      public func ics(now: Date = Date()) -> String
  }

  public struct MeetingOccurrence: Equatable, Sendable {
      public var uid: String
      public var start: Date
      public var end: Date
      public var isAllDay: Bool
      public var subject: String?
      public var location: String?
      public var organizer: String?
      public var isRecurringInstance: Bool
      public var folderID: String
      public var serverID: String
  }
  ```

- `Message` 新增 `public var meeting: MeetingInvite?`（additive 默认 `nil`，不影响既有构造点；`init` 参数追加在末尾并给默认值，源兼容）。
- **展开规则**（纯函数，`occurrences(in:limit:)`）：
  - 起点 = `start`；按 `frequency`/`interval` 逐次推进；`Type 0 + weekdays 非空` 按每周处理（规范规定）；`monthlyWeekday` 取第 N 个或最后一个 `weekday`；`yearlyWeekday` 取 `monthOfYear` 的第 N 个或最后一个 `weekday`；
  - 结束条件：超出 `range.upperBound`、或越过 `until`、或达到 `occurrences`、或达到 `limit`；
  - 例外：先按规则生成，再用 `exceptions` 按 `recurrenceId` 替换/删除对应实例；
  - 时间推进用固定 `timeZone.offsetSeconds`（默认本机时区偏移），不做 DST 过渡；跨 DST 的偏差登记为限制（Q5）。
  - 复杂度保证：从系列起点线性推进，但以「首次进入 range」为目标做快进（按天/周/月步进累加，最多 `limit + 365` 步），避免 2010 年起的系列每次扫全量。
- **iCalendar**（`ics(now:)`）：`BEGIN:VCALENDAR`/`VERSION:2.0`/`PRODID:-//uumail//uumail//CN`/`CALSCALE:GREGORIAN`/`METHOD:PUBLISH`/一个 `VEVENT`；`DTSTAMP`=now(UTC)；`DTSTART`/`DTEND` 用 UTC `Z` 形式（全天用 `VALUE=DATE`）；`SUMMARY`/`LOCATION`/`ORGANIZER`；`UID` 用会议 `UID`；重复系列带 `RRULE`（`FREQ`/`INTERVAL`/`BYDAY`/`BYMONTHDAY`/`BYSETPOS=1|-1`/`COUNT`/`UNTIL`/`WKST`）与 `EXDATE`（被删除的例外）；例外覆盖用第二个 `VEVENT` + `RECURRENCE-ID`；文本按 RFC 5545 转义（`\,` `\;` `\n`）并 75 字节折行、CRLF 行尾。
- 不变量：无 I/O；`start <= end`；`occurrences` 只返回落在 range 内的实例；`ics` 输出可被 Calendar.app 导入（L1 断言关键行，L2 冒烟真实导入可选）。
- 错误模式：构造由适配器完成，域内结构保证合法（`interval >= 1` 由适配器归一）；`occurrences` 不抛错，坏规则返回空数组。
- 尺寸：`MailDomain` 现约 1100 行 + 约 260 行；`Meeting.swift` 单文件 ≤300 行。
- 兼容性：纯 additive；`Message` 新字段默认 `nil`；`MailDomain` 扇入平台级（6+），本批属 P1 契约变更，需确认门。
- 测试（`MailDomainTests/MeetingRecurrenceTests`、`MeetingICSTests`）：每日/每周（周一二三）/每月按日（31 号跳月）/每月第 2 个周四/最后一天/每年按日/每年第 N 个周一；`until`/`occurrences`/`limit` 边界；例外替换与删除；`.ics` 关键行与转义、折行、CRLF、`RRULE` 生成。

## 实现（2026-11-24，T-1124-06）

- `Sources/MailDomain/Meeting.swift`（约 520 行）：`MeetingInvite`/`RecurrenceRule`/`MeetingException`/
  `MeetingOccurrence`/`MeetingTimeZone`/`MeetingMessageType`/`Weekday`/`MeetingEntry`，以及 `occurrences(in:limit:)`
  与 `ics(now:)`；`Message.meeting` additive。
- 测试：`Tests/MailDomainTests/MeetingTests.swift` 12 例（单次/每日/每周/每月按日与第 N 个/最后/每年/边界/
  例外/全天/ICS 三例）。