---
layer: design
module: presentation
status: active
updated: 2026-11-16
component: CMP-PRES
---

# CMP-PRES Presentation 组件规格

## 模块卡

- 状态：`active`
- 单元：模块（薄视图模型 + 展示类型 + 文案/格式化 + UI 偏好适配）
- 层 / 类型：L3；表现
- 业务价值：把用户动作转成一次场景调用，把场景结果映射为可观察状态与中文文案；让视图退化成绑定。没有它，视图直接持有场景并写展示逻辑，状态机无法测试。
- 负责 X：`MailboxViewModel`（文件夹/列表/正文/附件/同步/选择/搜索/自动刷新；T-1114-10 设计新增停留计时、键盘删除、前台状态、搜索模式保持（2026-11-14 已实现））、`ComposeViewModel`（新建/回复/全部回复/转发、入队状态、草稿）、`AccountSetupViewModel`（validate/connect、忙碌态、错误）、展示类型（`BodyPresentation`、`BodyNotice`、`SyncPresentation`、`Selection`）、`ErrorText` 唯一文案表、`DisplayFormat`（发件人/日期）、`ThemePreferenceStore`（主题偏好的读/写/回退；2026-11-16 设计新增，见文末增量）。
- 不负责 Y：业务规则、直接访问 `MailStore`/`MailGateway`/`Outbox`、轮询节奏（`SyncScene`）、缓存优先与补拉（`ReadScene`）、系统外观跟随与主题菜单（`CMP-APP` 的 `preferredColorScheme`/`ThemeCommands`）。
- 内部逻辑：
  - 每个动作只调一次场景方法；结果映射为状态，不重试、不判断业务分支。
  - 正文：缓存优先 → `.loading`/摘要提示 → `.loaded(html, truncated)` 或 `.failed(text)`；`BodyNotice` 承载「正在补拉」与「摘要回退」。
  - 自动刷新：消费 `SyncScene.startAutoRefresh` 流，映射 `SyncPresentation`；`stopAutoRefresh` 取消消费并停场景循环。
  - `ComposeViewModel.send` 调 `ComposeScene.send`，成功即 `status = .queued` 并触发组合根的投递信号；失败保留编辑文本。
- 拥有的数据：视图状态（选择、搜索词、加载态、编辑器文本），不持久化；另持有**主题偏好的本地镜像**（`UserDefaults["appearance.theme"]`，注入 store；不是业务数据，真源仍是 App 的 `@State`，见文末增量）。
- 变化轴：窗口形态与交互；主题外观（2026-11-16 新增一档三态主题）。
- 公开契约：`CMP-PRES#MailboxViewModel`（T-1114-10 设计新增 `#visibleMessages`、`#deleteErrorText`、`#setApplicationActive`、`#deleteSelected`（2026-11-14 已实现））、`#ComposeViewModel`、`#AccountSetupViewModel`、`#ErrorText`、`#DisplayFormat`、`#ThemePreference`、`#ThemePreferenceStore`（2026-11-16 新增 public，P2 已确认并实现）；`MailboxDwell`/`MailboxDeletion` 仍是模块内文件。
- 入口：`Sources/Presentation/MailboxViewModel.swift#MailboxViewModel`、`ComposeViewModel.swift#ComposeViewModel`、`AccountSetupViewModel.swift#AccountSetupViewModel`、`ErrorText.swift#ErrorText`、`PresentationTypes.swift#BodyPresentation`、`ThemePreference.swift#ThemePreference/#ThemePreferenceStore`
- 依赖：`Scenes`、`MailDomain`、`Observation`、`Foundation`（`UserDefaults`；不算新组件依赖）。扇出 1。
- 冷热：热（主线程）；主题偏好读/写是低频冷路径，不与 VM 热路径共享状态。
- 尺寸预算：单文件 ≤400 行；当前 `MailboxViewModel` **298**、`ComposeViewModel` 196、`AccountSetupViewModel` 100、`ThemePreference` 50；`Presentation` 共 1104 行（含 Body/Delete/Compose/Dwell/Deletion 拆分）。
- 单独运行：`./Scripts/swiftw test --filter PresentationTests`
- 删除测试：删掉后视图直接持有场景并写展示逻辑，测试无法覆盖状态机 → 复杂度集中，是真边界。

## 契约卡：视图模型 v1

- 签名（摘要）：

  ```swift
  @MainActor @Observable public final class MailboxViewModel {
      public private(set) var folders: [Folder]
      public private(set) var messages: [Message]
      public private(set) var body: BodyPresentation
      public private(set) var bodyNotice: BodyNotice?
      public private(set) var attachments: [Attachment]
      public private(set) var sync: SyncPresentation
      public private(set) var selection: Selection
      // T-1114-10 设计新增（已实现）：
      public var visibleMessages: [Message] { get }
      public private(set) var deleteErrorText: String?
      public init(read: ReadScene, sync: SyncScene, compose: ComposeScene, account: AccountID,
                  onEnqueued: (@MainActor () -> Void)? = nil,
                  dwellSleep: @escaping @Sendable (Duration) async throws -> Void = { … })
      public func startAutoRefresh(every: Duration = .seconds(300))
      public func stopAutoRefresh()
      public func refresh() async
      public func loadCached()
      public func select(folderID: String)
      public func select(messageID: String)
      public func openSelected() async
      public func search(_ query: String) async
      public func download(_ attachment: Attachment) async -> URL?
      public func setApplicationActive(_ active: Bool)
      public func deleteSelected() async
      public func composeNew() -> ComposeViewModel
      public func composeReply() -> ComposeViewModel?
      public func composeReplyAll() -> ComposeViewModel?
      public func composeForward() -> ComposeViewModel?
  }
  // 新增的 MailboxDwell / MailboxDeletion 为模块内实现文件，签名见文末设计增量。

  @MainActor @Observable public final class ComposeViewModel: Identifiable {
      public enum Mode { case new, reply, replyAll, forward }
      public enum Status { case editing, sending, queued, saved, failed(String) }
      public var to, cc, subject, body: String
      public private(set) var status: Status
      public var statusText: String?   // 「已加入发件箱」/「草稿已保存」/错误文案
      public var canSend: Bool
      public convenience init(replyingAllTo message: Message, bodyHTML: String?, scene: ComposeScene, account: AccountID, onEnqueued: (@MainActor () -> Void)? = nil)
      public func send() async -> Bool
      public func saveDraft() -> Bool
  }

  @MainActor @Observable public final class AccountSetupViewModel {
      public var displayName, host, account, password, domain, deviceID: String
      public private(set) var isBusy: Bool
      public private(set) var errorText: String?
      public private(set) var connected: ConnectedAccount?
      public var canConnect: Bool
      public func validate() async -> Bool
      public func connect() async -> Bool
  }
  ```

- 不变量：不 import 场景之外的逻辑层类型；文案只经 `ErrorText`；选择变化只触发必要的场景调用；同一邮件不重复打开（`openedBody`/在飞 `bodyTask`）；同一附件重复点击不重复下载（场景单飞）。
- 错误模式：把 `MailError`/存储错误映射为中文（`ErrorText.text(for:)`），不吞错、不自动重试。
- 幂等 / 顺序 / 并发：`@MainActor`，状态更新串行；`startAutoRefresh` 重复调用幂等（已有 task 则返回）。
- 超时 / 取消：`stopAutoRefresh` 取消消费 task；`openSelected` 切换邮件时取消上一封正文 task。
- 一致性：动作返回后状态已更新；自动刷新的列表刷新来自本地库。
- 兼容性：相对规格草案新增 `BodyNotice`（摘要回退与补拉提示）与 `onEnqueued`（组合根投递信号）；`BodyPresentation.loaded` 带 `truncated`。
- 契约测试：`PresentationTests` 28 例（`MailboxViewModelTests` 16、`ComposeViewModelTests` 8、`AccountSetupViewModelTests` 4）。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| 文件夹/列表/选择/搜索 | ✅ | `MailboxViewModelTests` 选择、搜索、刷新用例 |
| 正文缓存/补拉/失败/截断 | ✅ | 5 例正文状态机（含「预览不冒充正文」） |
| 同步状态与中文文案 | ✅ | 「a failed sync ... shows the Chinese error text」「MailError maps to the single Chinese table」 |
| 撰写/回复/全部回复/转发/草稿/入队 | ✅ | `ComposeViewModelTests` 8 例（含全部回复预填、Cc 入 outbox、空 To 不可发） |
| 配置页 validate/connect | ✅ | `AccountSetupViewModelTests` 4 例 |
| 附件下载按钮 | ✅ | `download` 委托 `ReadScene`；无独立 VM 测试 |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 状态映射 | fake scenes/真实场景 + fake gateway；断言状态序列 |
| 文案 | 单一映射表逐 case 断言 |
| 选择/并发 | 切换文件夹清正文、同一邮件不重复打开、同一正文 task 合并 |
| 依赖 | 门 1：`Presentation` 只 import `MailDomain`/`Scenes`/`Observation` |

## 依赖约束

- 不 import `MailStore`/`SyncEngine`/`Outbox`/EAS/Composition；只经场景契约。
- 不做业务判断：重试、退避、缓存优先、通知条件都在场景。

## 设计增量：全部回复（T-1114-07，已实现 2026-11-14）

- `ComposeViewModel.Mode` 增 `case replyAll`；新增 convenience init：

  ```swift
  public convenience init(
      replyingAllTo message: Message,
      bodyHTML: String?,
      scene: ComposeScene,
      account: AccountID,
      onEnqueued: (@MainActor () -> Void)? = nil
  )
  ```

- `MailboxViewModel` 新增 `public func composeReplyAll() -> ComposeViewModel?`：取 `selectedMessage` 与 `quotableHTML`，只调一次 `scene.replyAllSeed`，把 `draft.to`/`draft.cc` 绑定到编辑器；不搬地址规则、不读 `Message` 字段做二次处理。
- `canSend` 仍只判断 `to` 非空；全部回复把所有人排除后 `to` 为空，`canSend == false`，用户手填后可发。
- 测试：`ComposeViewModelTests` 补「全部回复预填 To/Cc」与「空 To 时 `canSend == false`」；`MailboxViewModelTests` 补 `composeReplyAll` 的选中邮件接线。`Mode` 增加不改变既有 `new/reply/forward` 行为。

**实现（2026-11-14）**：`ComposeViewModel.Mode` 增 `.replyAll`，新增 `init(replyingAllTo:bodyHTML:scene:account:onEnqueued:)`；`MailboxViewModel.composeReplyAll()` 只取 `selectedMessage`/`quotableHTML` 并调一次 `ComposeScene.replyAllSeed`，地址规则未上移到表现层。新增 5 例测试（`ComposeViewModelTests` 3、`MailboxViewModelTests` 2），`PresentationTests` 28 例绿。

## 设计增量：停留计时与键盘删除（T-1114-10，2026-11-14 设计；T-1114-17 已实现）

- 文件拆分（不新增 target/组件）：
  - `Sources/Presentation/MailboxDwell.swift`：10 秒计时、前台状态、取消/重启；不读系统时间，sleep 由构造注入。
  - `Sources/Presentation/MailboxDeletion.swift`：临时隐藏集、单飞、错误文案；调用 `ReadScene.deleteMessage`。
  - `Sources/Presentation/MailboxViewModel+Compose.swift`：把现有 Compose 段机械移出，给主文件留预算；行为不变。
  - `MailboxViewModel.swift` 目标 ≤380 行（当前 345 + 计时/删除/失活接线约 60 - 移出约 45 ≈ 360）；实测超 400 先停下按流程处理，不静默调预算。
  - Compose 段移出到 extension 文件时，`composeScene`/`account`/`onEnqueued`/`quotableHTML` 需从 `private` 放宽为 `internal`（仅模块内可见，不新增 public API）；若评审不接受放宽，改用私有 `MailboxComposer` helper 持有这几个依赖，不把方法留在主文件。
- `MailboxViewModel` 新增：

  ```swift
  public var visibleMessages: [Message] { get }            // messages 减去 deletion.hidden
  public private(set) var deleteErrorText: String? { get }
  public init(…, dwellSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, …)
  public func setApplicationActive(_ active: Bool)
  public func deleteSelected() async
  ```

- `MailboxDwell`：

  ```swift
  @MainActor final class MailboxDwell {
      init(read: ReadScene, sleep: @escaping @Sendable (Duration) async throws -> Void)
      var onMarked: (@MainActor (MessageRef) -> Void)?
      func update(target: MessageRef?, isUnread: Bool, isActive: Bool)
      func cancel()
  }
  ```

  - `update` 是幂等声明式入口：相同 target 且仍可计时 → **不重启**；target 变化/失活/已读/删除 → 取消；回到前台 → 重新起 10 秒。
  - 到点：`read.markReadLocally` 成功 → `onMarked`（VM 立即重载，蓝点消失；即使返回 false 是「已被同步置读/已删」也重载一次以纠正陈旧列表）→ 仅当返回 true（发生 0→1）才后台 `Task { await read.writeBackMarkRead(ref) }`；不等待网络、不展示回写错误。VM 设置 `onMarked` 时用 `[weak self]`，避免 VM↔dwell 循环持有。
  - 本地写失败：不重载、不回写、不弹错。
- `MailboxDeletion`：

  ```swift
  @MainActor @Observable final class MailboxDeletion {
      enum Outcome: Equatable { case deleted, failed, ignored }
      private(set) var hidden: Set<MessageRef>
      private(set) var isDeleting: Bool
      private(set) var errorText: String?
      func begin(_ ref: MessageRef) -> Bool
      func commit(_ ref: MessageRef) async -> Outcome
      func clearHidden(_ ref: MessageRef)
  }
  ```

  - `begin` 立即隐藏并置在飞；已有一个在飞 → `false`，VM 忽略本次按键。
  - `commit` 等待 `ReadScene.deleteMessage`；成功保留隐藏（等 VM 重载后 `clearHidden`），失败移除隐藏并写 `ErrorText` 文案。
- `deleteSelected` 顺序：记录删除项索引与当时的 `folderID`/`searchQuery` → `begin` 隐藏 → 取消计时 → 从隐藏后的 `visibleMessages` 取 `min(index, count-1)` 作为下一选中（空则 nil）→ 启动正文加载（缓存优先；网络补拉在独立 task 中继续，**不 await、不阻塞删除提交**）→ `commit` → 成功重载并清隐藏；失败重载、恢复原选中与正文、状态栏错误，并在恢复后调 `refreshDwell()`（取消「下一封」的计时，按恢复项重新判定）。等待期间用户切文件夹/搜索/改选：完成回调只在当前 `folderID` 与 `searchQuery` 仍匹配且选中未被用户改动时恢复，不跨列表强行插入；**无论是否切走，成功后都 `clearHidden`**（失败由 `commit` 移除）。VM 另用 `isDeleteInFlight` 覆盖整个 `deleteSelected`（含恢复/重开正文），入口即拒绝连按；`MailboxDeletion.isDeleting` 只覆盖网络 await。若 `openSelected()` 内部会 await 网络补拉，T-1114-17 必须拆出非等待的启动入口或把补拉 task 与 `commit` 分离；验收断言「正文补拉慢/失败不影响删除命令按时发出」。
- `selectedMessage` 改从 `visibleMessages` 读取，临时隐藏的行不可被选中/打开；`messages` 仍是完整本地列表，不丢数据。`dwell` 在 `MailboxViewModel` 内标 `@ObservationIgnored`（计时状态由 VM 显式刷新驱动），`deletion` 保持 `@Observable`（`visibleMessages`/`deleteErrorText` 依赖它的隐藏集与错误）。删除失败恢复原邮件后，计时从新的 10 秒重新开始（不是继续旧计时）；若产品要求失败后也不计时，另加抑制标志，本批不做。
- 搜索模式：新增 `reloadCurrentList(autoSelect:)`——`selection.searchQuery` 非空时走 `read.search(query, limit:)`，否则走 `read.messages(folderID:)`；`loadCached`/自动刷新 `apply`/删除完成都改用它，避免在搜索结果里删一封或同步一次就切回文件夹列表。`select(folderID:)` 清空 `searchQuery`（视图 `searchText` 经既有 `onChange` 同步清空），让「文件夹列表 / 搜索结果」两种模式只有一个显式来源。`search(_:)` 先 trim 再写 `selection.searchQuery`，空白查询等同清空。**搜索模式下不计时**：`refreshDwell` 传入的 `isActive = isApplicationActive && searchQuery.isEmpty`，进入/停留在搜索都取消已读计时。
- **列表身份（复核新增风险 R23）**：搜索模式的结果跨文件夹，`serverID` 只在集合内唯一（`messages` 主键含 `folder_id`）；`ForEach`/`List(selection:)`/`selectedMessage` 不得只用 `serverID` 作为身份。T-1114-17 先用跨文件夹同 `serverID` fixture 验证；若冲突，改用 `MessageRef`（folder + serverID）或等价复合键。若需要改 `Selection.messageID` 的公开类型/语义，按 P2 契约变更在 T-1114-17 前单独评审，不静默改。
- 不变量：展示层不 import `MailStore`/`SyncEngine`；不判 `MailError` 分支（只用 `ErrorText`）；计时不放进 `ReadScene`；删除不发网络（只经场景）。
- 测试：`MailboxViewModelTests` 补 10 秒触发/取消/后台/重载不重置/幂等/回写失败无错误；`MailboxDeletionTests`（或并入 VM 测试）补隐藏即现、连按只一次、失败恢复、切文件夹不强行恢复；O5 用「正文补拉慢/失败」断言删除命令按时发出；R23 用跨文件夹同 `serverID` fixture 断言选中/删除命中正确文件夹；`PresentationTests` 既有 28 例不回归。

**实现（2026-11-14）**：新增 `MailboxDwell.swift`、`MailboxDeletion.swift`、`MailboxViewModel+Compose.swift`、`MailboxViewModel+Delete.swift`、`MailboxViewModel+Body.swift`；主 `MailboxViewModel.swift` **298 行**（目标 ≤380），Compose/Delete/Body 段已移出，`selectedMessage` 改从 `visibleMessages` 读取并过滤隐藏行。`PresentationTests` **52 例**绿：10 秒触发/切换/文件夹/搜索/删除取消、失活与回前台不足 10 秒、搜索模式进入与停留不计时、重载不重置、幂等、写响应 `Read=0` 不回翻本地、回写失败静默、删除即时隐藏/连按去重/失败恢复正文后重试/not-found 成功/非末条正文切换/R23 跨文件夹同 serverID/O5 慢正文不阻塞删除、隐藏行不可选中/打开。R23 用复合 `listKey`（folder + serverID）解决，未改 `Selection.messageID` 公开类型/语义。

## 设计增量：主题偏好（REQ-0016，2026-11-16，P2 已确认；实现 2026-11-16）

- 新增 public 类型（P2 契约变更，2026-11-16 已确认，见 `doc/history/decisions/2026-11-16-theme-appearance.md`）：
  - `ThemePreference`：`system/light/dark` 三态，`String` raw value，`CaseIterable`、`Sendable`。
  - `ThemePreferenceStore`：内部注入 `UserDefaults` 的本地 UI 偏好适配器（public `init()` 用 `.standard`）；`load()` 缺失/损坏/未知 → `.system`；`save(_:)` 只写一个 key、比较原始字符串幂等、不抛错。
  - 不引入存储协议/工厂/单例；测试用独立 `UserDefaults(suiteName:)`，不污染真实偏好。
- 契约：

  ```swift
  public enum ThemePreference: String, CaseIterable, Sendable {
      case system, light, dark
  }

  public struct ThemePreferenceStore {
      public init()                                 // 使用 .standard
      init(defaults: UserDefaults)                  // internal；测试用 @testable 注入
      static let defaultsKey = "appearance.theme"   // internal
      public func load() -> ThemePreference
      public func save(_ preference: ThemePreference)
  }
  ```

- 公开面（第 2 轮复核 D4）：`UserDefaults` 与 key 不进入公开契约；app 用 `ThemePreferenceStore()`，测试用 `@testable import Presentation` + `ThemePreferenceStore(defaults: suite)`。行为与第 1 轮提案一致，只收窄 `init`/key 的可见性；若评审要求跨模块注入，再改回 public `init(defaults:)`，本批不预付。
- 不变量：
  - `load()` 是纯读，任何存储内容都不崩溃；非法原始值回退 `.system`。
  - `save(_:)` 只写 `UserDefaults["appearance.theme"]`；不写业务库/Keychain/网络；不抛错、不回滚调用方状态；已是同一合法原始值则 no-op。
  - 损坏值 `"purple"` → `save(.system)` 写入 `"system"`（按原始字符串比较，而不是按 `load()` 的 fallback 结果比较），清理脏值。
  - store 不是会话真源：`CMP-APP#UumailApp.@State theme` 决定当前外观；写失败时本次会话不变、下次启动读旧值/默认。
- 不负责：`preferredColorScheme` 的应用、菜单勾选、系统外观监听（都在 `CMP-APP`）；业务判断与网络。
- 并发：`UserDefaults` 线程安全；`ThemePreferenceStore` 不加锁、不做异步/缓存；只在主线程启动读与选择写。
- 测试计划（`PresentationTests`，新增 `ThemePreferenceStoreTests`）：
  测试文件用 `@testable import Presentation`；每个用例经 `ThemePreferenceStore(defaults: suite)` 注入独立 `UserDefaults(suiteName:)` 并在结束时清理，不碰 `.standard`。
  - `defaultsToSystemWhenUnset`：空 suite → `.system`。
  - `roundTripsEachPreference`：三态 save→load。
  - `invalidValueFallsBackToSystem`：写入 `"purple"`/空串/大小写不符 → `.system`；`save(.system)` 后原始值被清理为 `"system"`。
  - `persistsAndRestoresAcrossInstances`：同一 suite 两个 store 实例 → 后一个读到前一个写的值（模拟重开）。
  - `repeatedSaveKeepsSingleValue`：同值 save 两次，读回一致、不抛错。
  - 写失败不可强制注入：`UserDefaults.set` 无同步失败信号；设计以「不抛/不回滚 + 会话状态独立」保证，若评审要求强制注入，另评最小存储协议（本批不预付）。
- 第 2 轮复核（2026-11-16，run `20261116-154416`）：与现状代码核对无结构性漂移；按 D4 收窄公开面（`UserDefaults` 与 key 转 internal），行为不变；`Presentation` 扇出按 `architecture.md` §2.5 仍为 1（`Scenes`；`MailDomain` 值类型不重复计）。
- 确认与实现（2026-11-16，T-1116-01/02）：Q5 A + Q6 A + P2 确认（含 D4 公开面收窄）；`Sources/Presentation/ThemePreference.swift` 已落地 public `init()` + internal `init(defaults:)`，`load()`/`save(_:)` 按上述不变量实现；`Tests/PresentationTests/ThemePreferenceStoreTests.swift` 5 例通过，`PresentationTests` 共 57 例。`SCN-0011` 已落 `settings/appearance/theme-switch` 并转 `designed`；证据见 `task-spaces/20261116-154416/evidence/`。
