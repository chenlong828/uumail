---
layer: design
module: scenes
status: active
updated: 2026-11-18
component: CMP-SCN-COMPOSE
---

# CMP-SCN-COMPOSE ComposeScene 组件规格

## 模块卡

- 状态：`active`
- 单元：组件（场景，`Sendable` 值类型）
- 层 / 类型：L2；撰写、草稿与发送意图
- 业务价值：把回复/转发的引用规则、草稿保存与「发送只入队」收在一处；视图模型不再拼 MIME、不再调发送服务。
- 负责 X：`replySeed/forwardSeed` 的收件人与主题规则、引用文本、`saveDraft`、`send`（校验 + 入队）、`pending/retry/cancel`。
- 不负责 Y：编辑器 UI、MIME 细节（`Outbox/MimeBuilder`）、投递（`Outbox`）。
- 内部逻辑：
  - 回复：`Re:` 前缀（已有则不加）、取发件人地址、正文加 `--- 原邮件 ---` 引用；空主题回退 `(无主题)`。
  - 转发：`Fwd:` 前缀、收件人为空、正文加 `--- 转发邮件 ---` 引用。
  - `send` 只做 `to` 去空白与空值校验，然后 `Outbox.enqueue`；无网络、无 MIME。
  - `saveDraft` 写草稿行（`isDraft = true`），不入队、不投递。
- 拥有的数据：无持久数据；草稿文本由 `Presentation` 持有。
- 变化轴：撰写形态（纯文本/富文本、附件）。
- 公开契约：`CMP-SCN-COMPOSE#replySeed`、`#replyAllSeed`、`#forwardSeed`、`#saveDraft`、`#send`、`#pending`、`#retry`、`#cancel`、`#recipientDirectory(account:)`（2026-11-18 设计新增，REQ-0022/SCN-0017）
- 入口：`Sources/Scenes/ComposeScene.swift#ComposeScene`、`#ComposeScene.recipientDirectory(account:)`
- 依赖：`MailStore`、`Outbox`、`MailDomain`。扇出 2。
- 冷热：热（入队本地事务）；`recipientDirectory` 为一次本地只读聚合（撰写页首次聚焦），不触网、不阻塞打开 sheet。
- 尺寸预算：≤500 行；当前 `ComposeScene.swift` 165 行（`wc -l` 2026-11-18；随 `Scenes` 共 947 行）；本次设计新增约 45–55 行，预计 ≤220 行。
- 单独运行：`./Scripts/swiftw test --filter ScenesTests`
- 删除测试：删掉后视图直接操作 outbox 并拼 MIME → 规则散落，是真边界。

## 契约卡：ComposeScene v1

- 签名：

  ```swift
  public struct ComposeScene: Sendable {
      public init(store: MailStore, outbox: Outbox)
      public func replySeed(to message: Message, bodyHTML: String?) -> Draft
      public func replyAllSeed(to message: Message, bodyHTML: String?, account: AccountID) -> Draft
      public func forwardSeed(from message: Message, bodyHTML: String?) -> Draft
      public func saveDraft(_ draft: Draft, account: AccountID) throws -> OutboxID
      public func send(_ draft: Draft, account: AccountID) async throws -> OutboxID
      public func pending(account: AccountID) async throws -> [OutboxItem]
      public func retry(_ id: OutboxID, account: AccountID) async throws
      public func cancel(_ id: OutboxID, account: AccountID) async throws
  }
  ```

  说明：`Outbox` 是 actor，故 `send/pending/retry/cancel` 为 `async`；这是实现期与规格草案的唯一签名偏差（草案把 `send` 写成同步）。
- 不变量：`send` 不触网，返回即本地事务已提交；空收件人 → `invalidInput`，不入队；`saveDraft` 永不投递；回复/转发主题前缀不重复。
- 错误模式：`invalidInput(reason:)`（空收件人）、`storage`（存储失败）；投递错误不在此返回，异步经 `Outbox` 状态。
- 幂等 / 顺序 / 并发：每次 `send` 生成新 `outboxID`（`ClientId`）；重复点击由 UI `canSend` 禁用。
- 超时 / 取消：入队无超时；取消/重试经 `Outbox` 的行级契约。
- 一致性：`send` 返回时行已落库；`pending` 只读 outbox 行。
- 兼容性：`replySeed/forwardSeed` 行为照搬旧 `ComposeModel`，未改引用规则。
- 契约测试：`ScenesTests/ComposeSceneTests.swift` 9 例；`PresentationTests/ComposeViewModelTests.swift` 8 例。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| `send` 只入队、不触网 | ✅ | 「send enqueues locally and returns immediately without touching the network」 |
| 空收件人拒绝 | ✅ | 「an empty recipient is rejected before anything is enqueued」 |
| `saveDraft` 不入队 | ✅ | 「saveDraft stores a draft row that is never queued」 |
| 回复/转发种子规则 | ✅ | 「reply seed uses Re:, the sender address and the quote marker」「forward seed uses Fwd:」「existing prefixes and empty subjects follow the old rules」 |
| `replyAllSeed`（发件人+To+Cc、去重、排除自己、Cc 减 To） | ✅ | 3 例（正常合并、畸形/重复/自己、账号不可读） |
| `pending/retry/cancel` | ✅ | 经 `Outbox`；`OutboxTests` 覆盖状态机 |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 入队语义 | fake gateway 调用为 0；返回后 `pendingOutbox` 有一行 |
| 校验 | 空/空白收件人抛 `invalidInput` 且无行 |
| 引用规则 | 主题前缀、地址提取、引用标记三组断言 |
| 依赖 | 门 1/2：不 import EAS、不与其它场景互调 |

## 依赖约束

- 只依赖 `MailStore`、`Outbox`、`MailDomain`；不 import EAS/Composition。
- MIME 与投递全部在 `Outbox`；本组件不构造 MIME。

## 设计增量：replyAllSeed（T-1114-06，已实现 2026-11-14）

- 新增公开契约：

  ```swift
  public func replyAllSeed(
      to message: Message,
      bodyHTML: String?,
      account: AccountID
  ) -> Draft
  ```

- 行为：主题/引用直接复用 `replySeed`；`to` = 原发件人 + 原 `recipients`，`cc` = 原 `cc`；两栏都经 `MailDomain.AddressList` 去重、排除当前账号地址，`cc` 再减去已在 `to` 的地址。账号地址经 `store.account(account)` 读取；读取失败/缺失时不排除、不抛错、不崩溃。`Draft.cc` 为空写 `nil`。
- 实现：`Sources/Scenes/ComposeScene.swift#replyAllSeed` 只做一次 `replySeed` 复用、一次 `store.account` 读取和 `AddressList` 的 `removing`/`subtracting` 组装；地址解析/归一化仍在 `MailDomain.AddressList`，本组件不新增解析逻辑。`store.account` 的读取失败按契约降级为「不排除自己」，是本组件唯一不向外抛错的读取路径（设计增量明确要求）。
- 不变：`replySeed` 与 `forwardSeed` 的行为（单回复仍只填发件人、Cc 空；转发收件人为空）；`send`/`saveDraft` 的入队语义。
- 尺寸：`ComposeScene.swift` 127 → 152 行（新增 25 行，含注释）；未把解析逻辑搬进 `Scenes`。
- 测试：`ScenesTests/ComposeSceneTests.swift` 6 → 9 例，新增「正常发件人+To+Cc」「畸形头/重复/自己」「账号不可读不排除」；正常例同时断言 `Re:` 与引用规则，账号不可读例断言既有 `RE:` 前缀不重复。

## 设计增量：HTML 引用种子与 quotedHeader（REQ-0021，2026-11-17）

- 公开签名扩展（兼容，默认参数）：
  ```swift
  public func replySeed(to message: Message, bodyHTML: String?, quotedHeader: String? = nil) -> Draft
  public func replyAllSeed(to message: Message, bodyHTML: String?, account: AccountID, quotedHeader: String? = nil) -> Draft
  public func forwardSeed(from message: Message, bodyHTML: String?, quotedHeader: String? = nil) -> Draft
  ```
- 行为：`HTMLText.quotedEmail(header:originalHTML:)` 生成完整 HTML 文档（`uumail-reply-start` 空行、全宽引文容器、12px 灰字抬头、清洗后的原正文）；`body` 由 `HTMLText.plainText(from:)` 同源生成。`quotedHeader` 由 `Presentation.DisplayFormat.quoteHeader` 传入（日期+发件人+写道：）；nil 时回退 `原邮件`，转发回退 `---------- 转发邮件 ----------`。不缩进、不用 `<blockquote>`/`margin-left`。`replyAllSeed` 只把 `bodyHTML` 带过去，地址规则不动。
- 不变：`send` 只入队、`saveDraft` 不入队、主题前缀规则、`In-Reply-To`/`References` 既有行为；不新增依赖。
- 测试：`ScenesTests/ComposeSceneTests.replySeedRules`、`.replySeedSanitisesOriginal`、`.forwardSeedRules`、`.replyAllFillsSenderAndOriginalRecipients`、`.replyAllUsesBackfilledCc`（旧行 nil）；全量 292 tests / 51 suites。

## 设计增量：收件人联想目录（REQ-0022 / SCN-0017，2026-11-18，P1 默认确认、未实现）

- 新增 public 同步方法：

  ```swift
  public func recipientDirectory(account: AccountID) -> ContactDirectory
  ```

- 内部常量：`recipientDirectoryFolderLimit = 500`、`recipientDirectoryTotalLimit = 5_000`（`internal static`，供 `@testable` 测试构造夹具；不进入 public 契约）。
- 行为：
  1. `try store.account(account)?.address` 取当前账号地址；读取失败/缺失 → `nil`（不排除自己），不抛错。
  2. `try store.folders(account:)` 取文件夹；跳过 `Drafts(3)`/`Deleted Items(4)`/`Sent Items(5)`/`Outbox(6)`，其余文件夹按存储顺序处理（Inbox 优先）。
  3. 对每个保留文件夹调用 `try store.messages(account:folder:limit:500)`（只读信封，不读正文/附件），把 `sender`/`recipients`/`cc`/`receivedRaw` 映射为 `ContactEnvelope`；**累计到 5,000 封即停止**，避免大邮箱首次聚焦时把主线程拖住。
  4. 返回 `ContactDirectory(envelopes: envelopes, excluding: [ownAddress].compactMap { $0 })`。
  5. 任一步 store 读取抛错 → 返回 `ContactDirectory(envelopes: [], excluding: [])`，静默降级；不把存储错误显示成收件人错误。
- 边界：本组件只做「取数 + 映射 + 交给 `MailDomain`」，不复制解析/匹配/排序规则；不逐键调用（由 `ComposeViewModel` 缓存一次）；不新增 `MailStore` 方法/schema/依赖；不触网。每文件夹 500、总计 5,000 是**性能上限**，超出部分的旧邮件联系人不出现，属已接受降级（R46），不是持久性承诺。
- 不变量：`replySeed`/`replyAllSeed`/`forwardSeed`/`send`/`saveDraft` 行为不变；`recipientDirectory` 是纯读、无副作用、非 throwing；返回的目录只含当前账号、且来自非 Drafts/Deleted/Sent/Outbox 文件夹的信封。
- 尺寸：`ComposeScene.swift` 165 → 预计约 220 行（新增约 55 行），低于 500；`Scenes` 总行数约 947（2026-11-18 实测）+ 约 55，不新增 target。
- 测试：`ScenesTests/ComposeSceneTests.recipientDirectoryAggregatesLocally`（Inbox + 自定义文件夹聚合、名字/地址、排除自己）、`.recipientDirectorySkipsNonMailFoldersAndOwnAddress`（Sent/Drafts/Deleted/Outbox 不贡献）、`.recipientDirectoryCapsFolderAndTotal`（文件夹 500/总计 5,000 截断，用 `@testable` 常量构造小 fixture）、`.recipientDirectoryDegradesToEmpty`（空库/读失败等价）；`ComposeSceneTests` 既有种子/发送用例不回归。
- 定级/确认：P1（场景 public 契约 + 平台级 `MailDomain` 值类型）；默认确认（未经人工）见 `history/decisions/2026-11-18-recipient-autocomplete.md`；A4 总计上限与 A6 内部常量见 `history/decisions/2026-11-18-recipient-autocomplete-design-addendum.md`。

## 设计增量：草稿读取、同行保存与转队发送（REQ-0043，2026-11-27，P3，已实现）

- 来源：`REQ-0043` / `SCN-0031`。`drafts(account:)` 读本地草稿（store 失败归为 `MailError.storage`）。
- `saveDraft(_:account:draftID:)`：`draftID` 非空先 `updateDraft`，返回 `false`（行已删）再插入新草稿；`isDraft = true` 语义不变。
- `send(_:account:draftID:)`：`draftID` 非空先 `sendDraft`，成功返回该 id；行已删回退 `Outbox.enqueue`。收件人校验、只入队、`ClientId` 规则不变。
- 既有不带 `draftID` 的调用（CLI/测试）签名兼容（默认参数）。

## 设计增量：草稿删除（REQ-0044，2026-11-27，P3，已实现）

- `ComposeScene.deleteDraft(_:account:)` 删本地草稿行；已绑定服务器副本时由 store 在同一事务写 tombstone，等待草稿同步删除服务器副本。
