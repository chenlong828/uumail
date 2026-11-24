---
layer: design
module: presentation
status: active
updated: 2026-11-24
component: CMP-PRES
---

# CMP-PRES Presentation 组件规格

## 模块卡

- 状态：`active`
- 单元：模块（薄视图模型 + 展示类型 + 文案/格式化 + UI 偏好适配）
- 层 / 类型：L3；表现
- 业务价值：把用户动作转成一次场景调用，把场景结果映射为可观察状态与中文文案；让视图退化成绑定。没有它，视图直接持有场景并写展示逻辑，状态机无法测试。
- 负责 X：`MailboxViewModel`（文件夹/列表/正文/附件/同步/选择/搜索/自动刷新；T-1114-10 设计新增停留计时、键盘删除、前台状态、搜索模式保持（2026-11-14 已实现））、`ComposeViewModel`（新建/回复/全部回复/转发、入队状态、草稿；2026-11-18 设计新增收件人候选状态与焦点/文本/光标/键盘/选中方法）、`AccountSetupViewModel`（validate/connect、忙碌态、错误）、展示类型（`BodyPresentation`、`BodyNotice`、`SyncPresentation`、`Selection`）、`ErrorText` 唯一文案表、`DisplayFormat`（发件人/日期）、`ThemePreferenceStore`（主题偏好的读/写/回退；2026-11-16 设计新增）、`FontSizePreferenceStore`（字号偏好的读/写/回退；2026-11-17 设计新增，见文末增量）。
- 不负责 Y：业务规则、直接访问 `MailStore`/`MailGateway`/`Outbox`、轮询节奏（`SyncScene`）、缓存优先与补拉（`ReadScene`）、系统外观跟随与主题菜单（`CMP-APP` 的 `preferredColorScheme`/`ThemeCommands`）、字号字体映射/应用与字号菜单（`CMP-APP` 的 `FontSizeStyle`/`FontSizeCommands`）、收件人目录的信封聚合与名字/地址解析/匹配排序（`ComposeScene` + `MailDomain`）。
- 内部逻辑：
  - 每个动作只调一次场景方法；结果映射为状态，不重试、不判断业务分支。
  - 正文：缓存优先 → `.loading`/摘要提示 → `.loaded(html, truncated)` 或 `.failed(text)`；`BodyNotice` 承载「正在补拉」与「摘要回退」。
  - 自动刷新：消费 `SyncScene.startAutoRefresh` 流，映射 `SyncPresentation`；`stopAutoRefresh` 取消消费并停场景循环。
  - `ComposeViewModel.send` 调 `ComposeScene.send`，成功即 `status = .queued` 并触发组合根的投递信号；失败保留编辑文本。
- 拥有的数据：视图状态（选择、搜索词、加载态、编辑器文本、当前邮件远程放行、置读错误提示），不持久化；另持有**两个本地 UI 偏好镜像**——**主题偏好**（`UserDefaults["appearance.theme"]`，`ThemePreferenceStore`）与**字号偏好**（`UserDefaults["appearance.fontSize"]`，`FontSizePreferenceStore`，2026-11-17 设计新增；两个 key 独立、互不读写；不是业务数据，真源仍是 App 的 `@State`，见文末增量）。
- 变化轴：窗口形态与交互；主题外观（2026-11-16 新增一档三态主题）；**字号档位**（2026-11-17 新增五档 100/120/145/175/225%，界面与阅读正文共用同一档位）。
- 公开契约：`CMP-PRES#MailboxViewModel`（T-1114-10 设计新增 `#visibleMessages`、`#deleteErrorText`、`#setApplicationActive`、`#deleteSelected`（2026-11-14 已实现）；2026-11-16 新增 `#headerPresentation`；2026-11-16 设计新增 `#allowsRemoteContent`、`#canAllowRemoteContent`、`#setAllowsRemoteContent(_:)`、`#canMarkSelectedRead`、`#markSelectedRead()`、`#markReadErrorText`（P2 待确认，见文末增量）、`#attachmentErrorText`（2026-11-20 新增，只读；P2 人工确认 A，见文末增量））、`#ComposeViewModel`（2026-11-18 设计新增 `#RecipientField`、`#recipientSuggestions`、`#highlightedSuggestion`、`#recipientFocusChanged(in:)`、`#recipientFocusLost()`、`#recipientTextChanged(in:caretAtEnd:)`、`#recipientCaretChanged(atEnd:)`、`#moveRecipientHighlight(by:)`、`#selectRecipientSuggestion(at:)`、`#selectHighlightedRecipientSuggestion()`、`#dismissRecipientSuggestions()`）、`#AccountSetupViewModel`、`#ErrorText`、`#DisplayFormat`、`#ThemePreference`、`#ThemePreferenceStore`（2026-11-16 新增 public，P2 已确认并实现）、`#FontSizePreference`、`#FontSizePreferenceStore`（2026-11-17 设计新增 public，P2 默认确认未经人工）、`#MessageHeaderPresentation`（2026-11-16 新增 public，P2 已确认，实现见文末增量）；`MailboxDwell`/`MailboxDeletion` 仍是模块内文件。
- 入口：`Sources/Presentation/MailboxViewModel.swift#MailboxViewModel`、`ComposeViewModel.swift#ComposeViewModel`（2026-11-18 新增收件人联想成员）、`AccountSetupViewModel.swift#AccountSetupViewModel`、`ErrorText.swift#ErrorText`、`PresentationTypes.swift#BodyPresentation`、`ThemePreference.swift#ThemePreference/#ThemePreferenceStore`、`FontSizePreference.swift#FontSizePreference/#FontSizePreferenceStore`（2026-11-17 设计新增）、`MessageHeaderPresentation.swift#MessageHeaderPresentation`（2026-11-16 新增）
- 依赖：`Scenes`、`MailDomain`、`Observation`、`Foundation`（`UserDefaults`；不算新组件依赖）。扇出 1。
- 冷热：热（主线程）；主题与字号偏好的读/写都是低频冷路径（启动一次 + 选择一次），不与 VM 热路径共享状态；收件人候选是撰写页主线程内存过滤，不查库、不触网。
- 尺寸预算：单文件 ≤400 行；当前（2026-11-24 实测）`MailboxViewModel` **366**、`MailboxViewModel+List` 69、`CalendarViewModel` **172**、`CalendarProjection` **254**、`ReaderViewModel` 223、`ReaderRouter` 120、`ComposeViewModel` 284；`Presentation` 共 **2721** 行。2026-11-24 预算拆分后所有单文件 ≤400（此前 `MailboxViewModel` 424、`CalendarViewModel` 424）。
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
      /// 2026-11-20 新增：当前正文的渲染投影（`cid:` 已替换为 `data:`）；不持久化，回复引用仍用 `body`。
      public private(set) var inlineImageHTML: String?
      /// 2026-11-20 新增（REQ-0026/SCN-0020）：最近一次附件下载失败的中文文案；公开只读、模块内写。
      public internal(set) var attachmentErrorText: String?
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
  // 2026-11-16 增量（P2 待确认）：allowsRemoteContent / canAllowRemoteContent /
  // setAllowsRemoteContent(_:) / canMarkSelectedRead / markSelectedRead() / markReadErrorText，见文末。

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
- 错误模式：`ErrorText` 只把 `MailError` 映射为中文；非 `MailError` 不直接交给视图，由对应动作先归一为 `MailError`（本批手动置读在 `performMarkRead` 归一为 `.storage(reason:)`），再经 `ErrorText`；不吞错、不自动重试。
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
  - `Sources/Presentation/MailboxDwell.swift`：3 秒计时、前台状态、取消/重启；不读系统时间，sleep 由构造注入；只做计时，不直接访问 `ReadScene`/`MailStore`（2026-11-16 设计）。
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
      init(sleep: @escaping @Sendable (Duration) async throws -> Void)
      var onElapsed: (@MainActor (MessageRef) -> Void)?
      func update(target: MessageRef?, isUnread: Bool, isActive: Bool)
      func cancel()
  }
  ```

  - 2026-11-16 设计把写路径移出计时器：`MailboxDwell` 不再持有 `ReadScene`，只负责 3 秒计时与 `onElapsed` 回调；写/重载/回写由 `MailboxViewModel.performMarkRead` 统一完成，自动与手动入口共用。
  - `update` 是幂等声明式入口：相同 target 且仍可计时 → **不重启**；target 变化/失活/已读/删除 → 取消；回到前台 → 重新起 3 秒。
  - 到点：`MailboxDwell` 调 `onElapsed(ref)` → `MailboxViewModel.performMarkRead(ref)` 调 internal `localMarkRead`（默认 `read.markReadLocally`）；成功 → VM 立即重载（蓝点消失；即使返回 false 是「已被同步置读/已删」也重载一次以纠正陈旧列表）→ 仅当返回 true（发生 0→1）才后台 `Task { await read.writeBackMarkRead(ref) }`；不等待网络、不展示回写错误。VM 设置 `onElapsed` 时用 `[weak self]`，避免 VM↔dwell 循环持有。
  - 本地写失败：`performMarkRead` 在返回前把任意错误归一为 `MailError`（`MailError` 原样，非 `MailError` → `.storage(reason: String(describing:))`）；自动计时路径忽略它（不重载、不回写、不弹错）。
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
- `selectedMessage` 改从 `visibleMessages` 读取，临时隐藏的行不可被选中/打开；`messages` 仍是完整本地列表，不丢数据。`dwell` 在 `MailboxViewModel` 内标 `@ObservationIgnored`（计时状态由 VM 显式刷新驱动），`deletion` 保持 `@Observable`（`visibleMessages`/`deleteErrorText` 依赖它的隐藏集与错误）。删除失败恢复原邮件后，计时从新的 3 秒重新开始（不是继续旧计时）；若产品要求失败后也不计时，另加抑制标志，本批不做。
- 搜索模式：新增 `reloadCurrentList(autoSelect:)`——`selection.searchQuery` 非空时走 `read.search(query, limit:)`，否则走 `read.messages(folderID:)`；`loadCached`/自动刷新 `apply`/删除完成都改用它，避免在搜索结果里删一封或同步一次就切回文件夹列表。`select(folderID:)` 清空 `searchQuery`（视图 `searchText` 经既有 `onChange` 同步清空），让「文件夹列表 / 搜索结果」两种模式只有一个显式来源。`search(_:)` 先 trim 再写 `selection.searchQuery`，空白查询等同清空。**搜索模式下不计时**：`refreshDwell` 传入的 `isActive = isApplicationActive && searchQuery.isEmpty`，进入/停留在搜索都取消已读计时。
- **列表身份（复核新增风险 R23）**：搜索模式的结果跨文件夹，`serverID` 只在集合内唯一（`messages` 主键含 `folder_id`）；`ForEach`/`List(selection:)`/`selectedMessage` 不得只用 `serverID` 作为身份。T-1114-17 先用跨文件夹同 `serverID` fixture 验证；若冲突，改用 `MessageRef`（folder + serverID）或等价复合键。若需要改 `Selection.messageID` 的公开类型/语义，按 P2 契约变更在 T-1114-17 前单独评审，不静默改。
- 不变量：展示层不 import `MailStore`/`SyncEngine`；不判 `MailError` 分支（只用 `ErrorText`）；计时不放进 `ReadScene`；删除不发网络（只经场景）。
- 测试：`MailboxViewModelTests` 补 3 秒触发/取消/后台/重载不重置/幂等/回写失败无错误，并断言注入 sleep 收到 `.seconds(3)`；`MailboxDeletionTests`（或并入 VM 测试）补隐藏即现、连按只一次、失败恢复、切文件夹不强行恢复；O5 用「正文补拉慢/失败」断言删除命令按时发出；R23 用跨文件夹同 `serverID` fixture 断言选中/删除命中正确文件夹；`PresentationTests` 既有用例不回归。

**实现（2026-11-14）**：新增 `MailboxDwell.swift`、`MailboxDeletion.swift`、`MailboxViewModel+Compose.swift`、`MailboxViewModel+Delete.swift`、`MailboxViewModel+Body.swift`；主 `MailboxViewModel.swift` **298 行**（目标 ≤380），Compose/Delete/Body 段已移出，`selectedMessage` 改从 `visibleMessages` 读取并过滤隐藏行。`PresentationTests` **52 例**绿：10 秒触发/切换/文件夹/搜索/删除取消、失活与回前台不足 10 秒、搜索模式进入与停留不计时、重载不重置、幂等、写响应 `Read=0` 不回翻本地、回写失败静默、删除即时隐藏/连按去重/失败恢复正文后重试/not-found 成功/非末条正文切换/R23 跨文件夹同 serverID/O5 慢正文不阻塞删除、隐藏行不可选中/打开。（2026-11-16 起连续停留改为 3 秒；此处 10 秒为当时实现记录，不追溯改写。）R23 用复合 `listKey`（folder + serverID）解决，未改 `Selection.messageID` 公开类型/语义。

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

## 设计增量：阅读页信封头（REQ-0017 / SCN-0012，2026-11-16，P2 已确认、未实现）

- 来源与边界：`REQ-0017`（`accepted`）唯一验收场景 `SCN-0012`（`design/scenarios/mail/read/message-headers/scenario.md`）。头部是纯表现层增量：本地 `Message` 已有 `subject`/`sender`/`recipients`/`cc`/`receivedRaw`，不改 schema、协议、同步、`MailGateway`/`Scenes` 契约，不新增依赖或 target。
- P2 确认（2026-11-16，T-1116-07）：D1–D8 按 `design.md` §9.2 建议答案确认，确认记录见 `doc/history/decisions/2026-11-16-reading-pane-headers.md`；本增量形状不变，未收窄 `Row` 公开面。实现进度见文末追加行。
- 新增 public 类型（**P2 契约增量**，已确认；本节点不代签、不写确认记录）：

  ```swift
  public struct MessageHeaderPresentation: Equatable, Sendable {
      public struct Row: Equatable, Sendable, Identifiable {
          public let label: String
          public let value: String
          public let lineLimit: Int   // 发件人 1 / 收件人 2 / 抄送 2 / 时间 1
          public var id: String { label }
          public init(label: String, value: String, lineLimit: Int)
      }
      public let subject: String
      public let rows: [Row]
      public init(message: Message)   // public：独立 L2 探针要在 Presentation 模块外构造夹具
  }
  ```

- 映射规则（`init(message:)`，纯函数、无 I/O）：

  | 源字段 | 展示 | 行上限 | 为空/缺失 | 格式 |
  |---|---|---|---|---|
  | `subject` | 标题行（无「主题」标签） | 2 | 「(无主题)」 | 去首尾空白 |
  | `sender` | 行「发件人」 | 1 | 整行丢弃 | 去首尾空白，保留显示名与地址原文 |
  | `recipients` | 行「收件人」 | 2 | 整行丢弃 | 同上（To） |
  | `cc` | 行「抄送」 | 2 | 整行丢弃（空白也算空） | 同上 |
  | `receivedRaw` | 行「时间」 | 1 | `messageDate` 返回空则整行丢弃 | `DisplayFormat.messageDate`（既有回退） |

  - 行序固定为「发件人 → 收件人 → 抄送 → 时间」，`subject` 始终第一行；`Row.id = label`（标签集合固定且唯一）。
  - 不新增 `DisplayFormat` 收件人/抄送 API：信封原文已带显示名，`AddressList` 归一化会丢显示名并把 `To`/`Cc` 变成纯地址串，不是头部要的展示值（取舍见设计记录）。
  - 不新增 Bcc/Reply-To/Message-ID/会话/重要性/附件数行。

- `MailboxViewModel` 新增 public 只读派生属性：

  ```swift
  public var headerPresentation: MessageHeaderPresentation? {
      selectedMessage.map(MessageHeaderPresentation.init(message:))
  }
  ```

- 不变量：
  - 纯派生、无存储、无缓存；`headerPresentation == nil` **当且仅当** `selectedMessage == nil`；视图用这个条件区分「无选中」与「已选中但正文未开始」。
  - 头部只读 `selectedMessage`，同一封邮件（含搜索跨文件夹的复合 `listKey`）唯一；选中/搜索/删除/重载后自动跟随，不存在第二份可陈旧的头部状态。
  - 不新增场景调用、不触网、不写库、不写偏好、不写日志；不 import `MailStore`/`SyncEngine`/EAS/Composition。
  - `Equatable`：同一 `Message` 派生相等，避免 SwiftUI 无谓刷新。
- 尺寸/依赖：新文件 `Sources/Presentation/MessageHeaderPresentation.swift` 约 70 行；`MailboxViewModel.swift` 298 → 约 302（预算 ≤400）。仍只 import `Foundation`/`MailDomain`；`Presentation` 扇出不变（架构 §2.5 仍为 1）。
- 测试计划（L1，`Tests/PresentationTests/MessageHeaderPresentationTests.swift`，`@testable import Presentation`）：
  - 完整信封 → `subject` + 4 行，标签/值/行序/`lineLimit` 精确相等。
  - 稀疏：无 `cc` → 无抄送行；`sender`/`recipients`/`cc` 为 nil 或空白 → 对应行不出现；`subject` nil/空白 → 「(无主题)」；`receivedRaw` 畸形 → `prefix(16)` 回退；`receivedRaw` nil → 无时间行。
  - 值去首尾空白；空白 `cc` 不产生空行。
  - `MailboxViewModelTests`：`headerPresentation` 跟随选中与切换、无选中为 nil、`select(folderID:)` 后为 nil、跨文件夹同 `serverID` 命中正确邮件（R23）。
- L2：`HeaderProbe`（编译生产视图 + 同源 Presentation 文件，离屏 `NSHostingView` 读可选中 `Text` 的 `NSTextField.stringValue`）覆盖渲染值、隐藏行、切换与占位；seam 已由设计探针验证，见 `task-spaces/20261116-212545/evidence/header-probe/`。
- 自检：不改既有公开成员（纯新增，兼容）；不新增 `@Observable` 状态；无未登记 skip。
- 实现（2026-11-16，T-1116-08）：`Sources/Presentation/MessageHeaderPresentation.swift`（56 行）与 `MailboxViewModel.headerPresentation` 已落地。`MessageHeaderPresentationTests` 6 例（完整/稀疏/空白/畸形日期/裁剪/相等）与 `MailboxViewModelTests` 新增 4 例（无选中与切文件夹、切换、跨文件夹同 `serverID`、读取不新增网关/正文工作）全绿；`./Scripts/swiftw test --filter PresentationTests` 67 例通过、架构 4 门通过；`MailboxViewModel` 304 行（≤400）。证据：`task-spaces/20261116-212545/evidence/t1116-08-tests.txt`。

## 设计增量：远程图片放行与手动置读（REQ-0018 / REQ-0019 / REQ-0013，2026-11-16，P2 已确认）

- 来源：`REQ-0018`（`accepted`）/ `SCN-0013`、`REQ-0019`（`accepted`）/ `SCN-0014`、`REQ-0013`（`accepted` 重开）/ `SCN-0008`（按 3 秒修订）。本增量只动 `CMP-PRES` 的视图状态与写路径归属；不改 `MailDomain`/`MailStore`/`MailGateway`/`Scenes` 契约、schema、协议、依赖或 target。
- 新增 public 成员（**P2 契约增量，已按 `history/decisions/2026-11-16-remote-toolbar-mark-read.md` 确认**）：

  ```swift
  public private(set) var allowsRemoteContent: Bool      // 当前邮件临时放行；默认 false，不持久化
  public var canAllowRemoteContent: Bool { get }         // 当前选中 + 正文确属该选中且 .loaded
  public func setAllowsRemoteContent(_ allow: Bool)      // true 受 canAllowRemoteContent 守卫；false 总是允许
  public var canMarkSelectedRead: Bool { get }           // 当前选中且 !isRead
  public func markSelectedRead()                         // 本地先行 + 条件回写；归一后的错误写 markReadErrorText
  public private(set) var markReadErrorText: String?     // 本地写失败的中文提示（来源必为 MailError）；成功/换选中清空
  ```

- 远程放行状态（`REQ-0018`）：
  - 单一真源在 `MailboxViewModel`；`MessageBodyView` 不再有 `@State`，只接收 `allowRemoteContent: Bool` 并转交 `MessageWebView`。
  - `selectedListKey` 的 `didSet` 在**选中身份变化**时把 `allowsRemoteContent` 重置为 `false`，并清空 `markReadErrorText`；同一封的列表重载/正文重渲染不重置。
  - `setAllowsRemoteContent(true)` 先检查 `canAllowRemoteContent`：`selectedRef` 必须等于当前正文所属的 `openedBody` 或正在打开的 `openingRef`，且 `body` 为 `.loaded`；不满足则 no-op。这样旧正文尚未被新正文替换的短暂窗口不会把 A 的放行泄漏到 B。关闭（false）不受守卫限制。
  - 不写 `UserDefaults`/Keychain/业务库；不触网；不新增偏好、每封记忆或全局白名单。
- 手动置读（`REQ-0019`）：
  - `markSelectedRead()` 只处理当前选中未读一封：清空 `markReadErrorText` → `performMarkRead(ref)`；已读/无选中/被隐藏时 no-op（入口应已禁用）。
  - 本地失败注入：新增 internal `@ObservationIgnored var localMarkRead: (MessageRef) throws -> Bool`，public init 在 `self.read` 赋值后播种为 `{ try read.markReadLocally($0) }`；`performMarkRead` 调它。`@testable import Presentation` 的测试可覆盖为抛错闭包，验证本地失败分支，不依赖真实磁盘故障；该成员不是 public 契约。
  - 错误归一（2026-11-16 第 2 轮，关闭评审 F1）：`performMarkRead(_ ref:) -> MailError?`（internal）是自动与手动共用的唯一写路径——internal `localMarkRead(ref)` → 成功则重载列表 + `refreshDwell()` → 仅 0→1 时后台 `Task { await read.writeBackMarkRead(ref) }`；本地失败在 `catch` 内返回 `normalizeMarkReadError(error)`，即 `(error as? MailError) ?? .storage(reason: String(describing: error))`。返回类型保证**非 nil 必为 `MailError`**，不会把 `MailStoreError`/GRDB `DatabaseError` 漏给视图；不重载、不回写。手动入口只把该 `MailError` 经 `ErrorText.text(for:)` 写入 `markReadErrorText`（`storage` 分支固定「本地存储失败：…」）；自动计时路径忽略。`ErrorText` 的全局非 `MailError` 兜底与 `ReadScene.markReadLocally` 的错误类型均不改。
  - 回写失败语义与 `SCN-0008` 一致：不回滚、不弹错、不重试；`markReadErrorText` 不因回写失败设置。
  - 幂等/并发：`@MainActor` 串行；第二次 `markReadLocally` 返回 false，不再回写；不新增 `pending_op`/`readDirty`/离线队列。
- 计时器重构（`REQ-0013` 3 秒）：
  - `MailboxDwell` 去掉 `ReadScene` 依赖与 `onMarked`，只保留 `sleep`、`update`、`cancel` 与 `onElapsed`；计时 3 秒。
  - `MailboxViewModel` 在 init 中设置 `dwell.onElapsed = { [weak self] ref in _ = self?.performMarkRead(ref) }`；写/重载/回写只有一处。
  - 这是行为保持的重构：SCN-0008 的触发/取消/本地先行/失败语义不变，仅时长 10→3 秒；实现后必须跑既有 `SCN-0008` 用例并新增 `.seconds(3)` 时长断言。
- 状态栏提示：`MailboxView` 在 `deleteErrorText` 之后、同步状态之前显示 `markReadErrorText`（警告图标 + 单行中文）；文案只经 `ErrorText`。两个动作错误不合并成一个公开属性，避免把删除错误语义与置读错误混淆。
- 尺寸/依赖：`MailboxViewModel` 304 → 预计约 365（≤400）；`MailboxDwell` 70 → 约 55；仍只 import `Foundation`/`MailDomain`/`Scenes`/`Observation`；`Presentation` 扇出不新增。
- 测试计划（L1，`Tests/PresentationTests/MailboxViewModelTests.swift`）：
  - 远程：默认 false；`setAllowsRemoteContent(true)` 在 `.loaded` + 当前正文时置 true；无选中/`.none`/`.loading`/`.failed` 时 no-op；选中 A→B 后 false；选中 B 但正文仍为 A 的 `.loaded` 时 no-op；关闭总是允许；无偏好写入。
  - 手动置读：本地先行持久化、列表刷新、蓝点条件为假；只有一次 0→1 与一次写回、key 推进；已读/无选中 no-op 且不发网络；重复点击幂等；A→B 只影响 B；与 dwell 并发只写一次；回写失败 `markReadErrorText == nil`、本地仍已读；本地失败分两条注入 internal `localMarkRead` 抛错——`MailError.storage(reason:)` 与**非 `MailError`**（`MailStoreError.database("磁盘写入失败")`/`NSError`）——都断言 `markReadErrorText` 含中文（`storage` 前缀「本地存储失败」）、保持未读、零回写。非 `MailError` 走 `performMarkRead` 的同一 `catch` 归一分支，不是只测 `MailError` 的假绿。
  - 错误归一纯函数：另加一条直接断言 `normalizeMarkReadError(.offline) == .offline`、`normalizeMarkReadError(MailStoreError.database("磁盘写入失败")) == .storage(reason: String(describing: ...))`，与行为测试互为防回归。
  - 计时：注入 sleeper 记录 `Duration`，断言 `.seconds(3)`；既有触发/取消/后台/重载不重置/幂等用例按 3 秒更新。
- P2 确认项（详见 `task-spaces/20261116-223645/design.md` §8.2）：D1 放行状态归 VM 与重置/守卫语义；D2 手动置读 API 名/返回/错误面；D3 `MailboxDwell` 仅计时的重构；D4 工具栏/控件形态（`CMP-APP`）。确认记录见 `doc/history/decisions/2026-11-16-remote-toolbar-mark-read.md`（`frozen`，D1–D8 按唯一建议答案确认，无收窄）。
- 实现（2026-11-16，T-1116-12）：`MailboxViewModel` 新增 6 个 public 成员与 internal `performMarkRead -> MailError?`/`normalizeMarkReadError`/`localMarkRead`；`selectedListKey.didSet` 重置放行与错误；`MailboxDwell` 改为 3 秒纯计时并在 init 接 `onElapsed`。`MailboxViewModel.swift` 378 行（≤400）、`MailboxDwell.swift` 59 行（≤70）。`./Scripts/swiftw test --filter PresentationTests` 77 tests / 14 suites 通过（含 `remoteContentResetsOnSelectionChange`、`remoteContentCannotLeakToStaleBody`、`forcedRemoteAllowIsNoOpWhenUnavailable`、`manualMarkReadPersistsBeforeWriteBack`、`manualMarkReadIsIdempotentAndSelectionScoped`、`manualMarkReadRacesDwellOnce`、`manualMarkReadWriteBackFailureKeepsLocal`、`manualMarkReadLocalFailureReportsChinese`、`manualMarkReadNonMailErrorReportsChinese`、`normalizeMarkReadErrorWrapsNonMailError`、`dwellAsksForThreeSecondsAndMarks`）；架构 4 门通过。证据：`task-spaces/20261116-223645/evidence/t1116-12-presentation.txt`。

## 设计增量：字号偏好（REQ-0020 / SCN-0015，2026-11-17，P2 默认确认）

- 来源：`REQ-0020`（`accepted`）/ `SCN-0015`；完整论证、候选与否决、L2 探针见 `task-spaces/20261117-071134/design.md` 与 `evidence/font-size-probe/`；默认确认记录见 `doc/history/decisions/2026-11-17-font-size.md`（`frozen`，**默认确认（未经人工）**）。
- 新增 public 类型（**P2 契约增量**，兼容性新增；本节点不代签）：

  ```swift
  public enum FontSizePreference: Int, CaseIterable, Sendable {
      case percent100 = 100
      case percent120 = 120
      case percent145 = 145
      case percent175 = 175
      case percent225 = 225
      public var scale: Double { get }   // 1.0 / 1.2 / 1.45 / 1.75 / 2.25
      public var title: String { get }   // "100%" … "225%"
  }

  public struct FontSizePreferenceStore {
      public init()                                  // UserDefaults.standard
      init(defaults: UserDefaults)                   // internal，测试注入
      static let defaultsKey = "appearance.fontSize" // internal
      public func load() -> FontSizePreference
      public func save(_ preference: FontSizePreference)
  }
  ```

- 不变量：
  - `load()` 是纯读；任何存储内容都不崩溃。缺失/损坏/未知 → `.percent100`。
  - `title` 是展示字符串（`"100%"`…`"225%"`），无本地化依赖；不参与比较/持久化。
  - `Int` raw 与磁盘 `String` 编码并存：raw 稳定，存储形态为 String；`UserDefaults` 把合法整数桥接为等值字符串时按同档接受，这是显式兼容性承诺，不视为损坏。
  - 存储形态为 `String` raw value（`"100"`…`"225"`），与 `ThemePreferenceStore` 的 string 比较幂等模式一致；`UserDefaults` 把合法整数桥接为 `"175"` 时按同档接受（语义等价），`"purple"`、空串、`"175.5"`、`"250"`、int `999` 等回 100。
  - `save(_:)` 只写 `UserDefaults["appearance.fontSize"]`；同值 no-op；不写业务库/Keychain/网络；不抛错、不回滚调用方状态。
  - store 不是会话真源：`CMP-APP#UumailApp.@State fontSize` 决定当前字号；写失败时本次会话不变、下次启动读旧值/默认。
- 不负责：`Font` 映射、环境值、菜单勾选与应用（都在 `CMP-APP`：`FontSizeStyle`/`FontSizeCommands`）；不 import SwiftUI/AppKit；`Presentation` 仍只 import `Foundation`/`MailDomain`/`Scenes`/`Observation`，扇出不新增。
- 尺寸/依赖：新文件 `Sources/Presentation/FontSizePreference.swift` 约 55 行；`Presentation` 由 1229 行增至约 1284，扇出仅加一个 Foundation 文件。
- 测试计划（L1，`Tests/PresentationTests/FontSizePreferenceStoreTests.swift`，`@testable import Presentation`；每个用例经 internal `init(defaults:)` 注入独立 suite 并清理，不碰 `.standard`）：
  - `defaultsTo100WhenUnset`：空 suite → `.percent100`。
  - `roundTripsEachLevel`：五档 save→load。
  - `invalidValueFallsBackTo100`：`"purple"`/`""`/`"0"`/`"250"`/`"175.5"`/int `999` → `.percent100`。
  - `validIntegerIsAcceptedAsSameLevel`：int `175` → `.percent175`（记录 `UserDefaults` 字符串桥接口径，不把等价编码当损坏）。
  - `persistsAndRestoresAcrossInstances`：同一 suite 两个 store 实例模拟重开。
  - `repeatedSaveKeepsSingleValue`：同值 save 两次读回一致、不抛。
  - 写失败不可强制注入（`UserDefaults.set` 无同步失败信号）：以「不抛/不回滚 + 会话状态独立」保证，不伪造失败注入。
- 与主题的关系：两个独立 key（`appearance.fontSize` / `appearance.theme`），互不读写；任一变化不触发另一个的写；都不写业务库/网络。
- 确认与实现：P2 默认确认（未经人工，见决策记录）；实现后按上述测试与 `SCN-0015` 的 L2 探针验证，**不翻转任何状态位**。

## 设计增量：HTML 撰写状态与编辑文档（REQ-0021，2026-11-17）

- `ComposeViewModel` 新增：
  ```swift
  public var bodyHTML: String
  public func editorDidLoad(_ html: String)
  public func setEditorHTML(_ html: String)
  public var hasEdits: Bool
  ```
  `body` 仍是纯文本；有 `bodyHTML` 时发送前用 `HTMLText.plainText(from:)` 重新生成，无 HTML（CLI/测试/旧路径）时保留手工 `body`。`editorDidLoad` 只在首次记录归一化基线；`hasEdits` 比较收件人/抄送/主题/body/当前 HTML 与基线，取消确认用。`send`/`saveDraft` 把 `bodyHTML` 放进 `Draft`，仍只入队/写草稿。
- 新增 `public enum ComposeDocument`（`Sources/Presentation/ComposeDocument.swift`）：
  - `editorDocument(emailHTML:allowRemoteContent:)`：清洗后插入 `uumail-editor-csp` meta（`default-src 'none'`、`img-src data:` 或 `data: https: http:`、`style-src 'unsafe-inline'`）、`uumail-editor-style` 样式、`contenteditable`/`spellcheck`；空 HTML 用 `HTMLText.emptyEmailDocument()`。
  - `emailHTML(fromEditorDocument:)`：去掉上述 meta/style/属性，返回可发送的邮件 HTML；发件人 `<style>` 保留。
- `DisplayFormat.quoteHeader`/`longDate`：`yyyy年M月d日 HH:mm` + 原发件人 + `写道：`；缺失回退，格式在 Presentation 层，Scenes 只接收字符串。
- 不变量：`hasEdits` 的「未编辑种子」必须为 false（WebKit 归一化不回弹确认框）；`canSend`/状态机/`onEnqueued` 不变；body 与 bodyHTML 同源。
- 测试：`PresentationTests/ComposeDocumentTests`（round trip、两档 CSP、空文档、抬头格式）、`ComposeViewModelTests.sendCarriesHTML`、`.cancelBaseline`、`.replyNormalisedSeedIsNotDirty`；全量 292 tests / 51 suites。
- 预算：`ComposeViewModel` 263 行、`ComposeDocument` 107 行；`Presentation` 现有依赖不变，只 import Foundation/MailDomain/Scenes/Observation。

## 设计增量：成功同步清掉状态栏旧文案（T-1117-03，SCN-0009/SCN-0014，2026-11-17，P3）

`MailboxDeletion.errorText` 原先只在下一次 `begin(_:)` 时清空，`markReadErrorText` 只在改选/本地置读成功时清空，而状态栏三者的优先级是「删除错误 → 置读错误 → 同步状态」。于是只要有一次删除或本地置读失败，那条警告会一直压住同步状态，即使随后的同步全部成功（用户看到的就是「邮件照收、提示常驻」）。

规则改为：`apply(_ outcome:)` 在 `outcome.report != nil`（本次同步成功）时同时 `deletion.clearErrorText()` 与 `markReadErrorText = nil`——一次成功的同步已经证明账号可达，旧问题不再是当前状态。失败分支不变：错误文案仍然立刻显示、优先级不变；下一次失败会重新写入。

- `MailboxDeletion` 新增 internal `clearErrorText()`；`MailboxViewModel` 不新增公开成员，public 契约不变。
- 测试：`MailboxViewModelTests.successfulSyncClearsDeleteError`、`successfulSyncClearsMarkReadError`（L1：先注入失败，断言文案在；再跑一次成功 `refresh()`，断言 `phase == .idle` 且文案为 nil）。

## 设计增量：收件人输入联想状态（REQ-0022 / SCN-0017，2026-11-18，P1 默认确认、未实现）

- `ComposeViewModel` 新增 public 面（全部 additive，既有 init/成员不变）：

  ```swift
  public enum RecipientField: Equatable, Sendable { case to, cc }

  public private(set) var recipientSuggestions: [ContactAddress]
  public private(set) var highlightedSuggestion: Int?

  public func recipientFocusChanged(in field: RecipientField)
  public func recipientFocusLost()
  public func recipientTextChanged(in field: RecipientField, caretAtEnd: Bool)
  public func recipientCaretChanged(atEnd: Bool)
  public func moveRecipientHighlight(by delta: Int)
  @discardableResult public func selectRecipientSuggestion(at index: Int) -> Bool
  @discardableResult public func selectHighlightedRecipientSuggestion() -> Bool
  public func dismissRecipientSuggestions()
  ```

- 内部状态：`directory: ContactDirectory?`（首次聚焦或首次文本变化时经 `scene.recipientDirectory(account:)` 加载一次并缓存）、`activeField: RecipientField?`、`internal private(set) var directoryLoadCount = 0`（测试 seam，仅供 `@testable import Presentation` 断言「只加载一次」；不进入 public 契约）。不新增 `MailStore` import；目录只经 `ComposeScene` 取得。
- 行为：
  - `recipientFocusChanged` 置当前字段并加载目录（已加载则复用）；`recipientFocusLost` 清当前字段与候选。
  - `recipientTextChanged`：`caretAtEnd == false` → 清候选；否则确保目录已加载（未加载则加载一次并 `directoryLoadCount += 1`）；用 `RecipientText.tailFragment(in:)` 取片段，空 → 清；否则用 `AddressList(prefixBeforeTail)` + 对方字段的完整文本组成已填地址集合，调 `directory.suggestions(for:excluding:limit:8)`；每次文本变化重置 `highlightedSuggestion = nil`（默认不高亮）；输入刷新不重新查库。
  - `recipientCaretChanged`：光标不在末尾 → 清候选；回到末尾且当前字段有片段 → 按当前文本重算。
  - `moveRecipientHighlight`：无候选时清空；`↓` 首次到 0，`↑/↓` 在 `0...count-1` 内夹取，不循环；`selectHighlightedRecipientSuggestion` 只有在 `highlightedSuggestion != nil` 时提交（`Return` 的 VM 侧保证）。
  - `selectRecipientSuggestion(at:)`：用 `RecipientText.replacingTail(in:with: contact.address)` 替换当前字段文本，写回 `to`/`cc`，清候选与高亮；其他字段/主题/正文/编辑器不动；`hasEdits` 由既有文本比较自然变 true。
  - 不自动选中/自动发送；不在每次输入时加载目录或查库；目录加载失败等价于空目录，不显示错误。
- 性能：首次聚焦/首次文本变化同步读一次，`ComposeScene` 已有 500/文件夹、5,000 总计上限；设计目标是在当前 125 封真实库上无可感知卡顿、在 5,000 封夹具上首次加载 ≤100ms（实现期记录，不写成 CI 硬计时断言）。若实测超目标，回设计改为异步加载或降低上限；`CMP-PRES` 不在输入路径上查库。
- IME：VM 不处理键盘事件，也不在 `Return` 上自动提交；「组合态 Return 不选中」由 `CMP-APP` 的 `RecipientTextField` 在 `hasMarkedText()` 时把命令放行给输入法并在 VM 侧保持 `highlightedSuggestion == nil` 来保证。L1 只断言「无高亮时 `selectHighlighted...` 返回 false」；组合态行为由 `T-SCN-0017-03` 的 L2 探针覆盖。
- 兼容性：`ComposeViewModel` 既有 `Mode`/`Status`/`to`/`cc`/`subject`/`body`/`bodyHTML`/`send`/`saveDraft`/`hasEdits` 不变；新成员不影响既有调用；不新增依赖/文件；单文件仍 ≤400。
- 测试：`PresentationTests/ComposeViewModelTests.suggestionsRefreshWithFragment`、`.selectionReplacesTailOnly`、`.ccIsIndependent`、`.selectionWritesPureAddressIntoDraft`、`.noPerKeystrokeDirectoryLoad`（`@testable import Presentation` 断言 `directoryLoadCount` 在多次输入后仍为 1）、`.directoryLoadsOncePerCompose`、`.middleCaretHidesSuggestions`、`.noDefaultHighlightSoReturnDoesNotCommit`、`.escapeDismissesSuggestions`、`.duplicateNotSuggested`、`.rapidTypingUsesLatestFragment`、`.emptyFragmentHasNoSuggestions`、`.blurClearsSuggestions`；既有 `sendEnqueues`/`replyAll*` 不回归。
- 定级/确认：P1（`ComposeViewModel` public 面新增 + 依赖平台级 `MailDomain` 值类型）；默认确认（未经人工）见 `history/decisions/2026-11-18-recipient-autocomplete.md`；A5/A6 见 `history/decisions/2026-11-18-recipient-autocomplete-design-addendum.md`。


## 设计增量：内联图片渲染投影（REQ-0025 / SCN-0019，2026-11-20）

- 来源：`REQ-0025`（`feature`，`accepted`）/ 新场景 `SCN-0019`（`designed`）。完整论证、方案族与 L2 方向证据见 `task-spaces/20261120-111818/design.md`、`evidence/inline-image-current-state-design.md`。
- 新增状态（additive public，只读）：
  - `public private(set) var inlineImageHTML: String?`：当前正文 `cid:` 已替换为 `data:` 的渲染串（由 `ReadScene.renderInlineImages` 返回）；`nil` 表示没有可用替换（无引用/全部失败/尚未完成）。
  - `@ObservationIgnored private var inlineImageTask: Task<Void, Never>?`：当前邮件的图片任务句柄；不进 public 契约。
- 生命周期：
  - `openSelected`/`.cached`/`.loaded` 设置 `body` 后启动 `startInlineImageRender(ref, html)`；`.loading`/`.failed`/临时预览不启动；无被引用的 `src` 时 scene 直接返回 `nil`，不触网。
  - 任务：`let rendered = await read.renderInlineImages(for: ref, html: html)` → 回主线程 → stale guard：`selectedRef == ref && openedBody == ref` 且当前 `.loaded` 的 html 仍是发起时那份；`rendered != nil` 才赋 `inlineImageHTML`，否则保持 `nil`。
  - 切换邮件/清空/重新打开：`inlineImageTask?.cancel()`，`inlineImageHTML = nil`；迟到结果不写到新邮件。
  - 失败/空结果：保持 `inlineImageHTML = nil`，不改 `body`、不弹错、不重试循环；重开同一邮件走附件缓存。
- 不变量：
  - `body` 与 `quotableHTML` **始终是原始 HTML**；data URL 不进 `body`、不进回复引用、不进草稿/外发。
  - 不改 `BodyPresentation`/`BodyNotice`/`attachments`/远程开关状态；图片任务不阻塞 `openSelected` 的正文显示。
  - 不 import `MailStore`/`EASClient`/WebKit；图片只经 `ReadScene` 取；不在 PRES 解析 HTML/读文件。
- 尺寸：`MailboxViewModel` 381 → 约 389；`MailboxViewModel+Body` 109 → 约 139；不新增文件；单文件 ≤400。
- 测试：`PresentationTests/MailboxViewModelInlineImageTests` 覆盖「图片到达后 `inlineImageHTML` 含 data URL 而 `body`/`quotableHTML` 不含」「切换/清空丢弃迟到结果」「空/失败结果保持 raw HTML」「远程开关不影响内联 data URL」。
- 定级/确认：**P2**（视图模型公开面 additive、跨组件接线；无 schema/`MailDomain` 契约/依赖/热路径失败语义变更）。`inlineImageHTML` 公开面已**人工确认 pass（A，2026-11-20）**，记录见 `doc/history/decisions/2026-11-20-inline-image-render-public-surface.md`；D3–D6 仍为默认确认（未经人工），见 `task-spaces/20261120-111818/design2.md` §8。
- 实现进度（2026-11-20，`T-1120-03`）：`MailboxViewModel.inlineImageHTML` 以 `public internal(set)` 实现（公开面只读；`+Body.swift` 跨文件生命周期需要 internal setter，`inlineImageTask` 为 internal 且 `@ObservationIgnored`，不进 public 契约）；`openSelected`/`.cached`/`.loaded` 启动图片任务，`clearBody`/切换取消并清空，迟到结果经 `selectedRef`+`openedBody`+源 HTML 三重 stale guard 丢弃；`body`/`quotableHTML` 保持 raw。新增 `Tests/PresentationTests/MailboxViewModelInlineImageTests.swift`（4 例）；`PresentationTests` 117 例绿、架构 4 门 PASS。

## 设计增量：附件下载失败文案（REQ-0026 / SCN-0020，2026-11-20，P2 公开面已人工确认 A）

- 来源：`REQ-0026`（`feature`，`accepted`）/ 新场景 `SCN-0020`（`mail/read/attachment-access`，`designed`）。完整论证与验证计划见 `task-spaces/20261120-160446/design3.md`（第 3 轮，按评审 `review2` B1–B3 修订；第 2 轮见 `design2.md`）；公开面确认见 `doc/history/decisions/2026-11-20-attachment-error-surface.md`。
- 现状归因：`download(_:)` 用 `try? await read.downloadAttachment(...)` 吞错、只返回 `URL?`；视图只能判断 nil，下载失败对用户静默。
- 新增状态（**additive public，只读**；人工确认 A）：
  - `public internal(set) var attachmentErrorText: String?`：最近一次附件下载失败的中文文案；`public` 只读，`internal` setter 供同 target 的 `MailboxViewModel+Attachments.swift` 写入。与 `body`/`inlineImageHTML` 一样是「公开读、模块内写」。
  - 不新增 `retry`/`report`/`exporter` 方法；另存为失败由 APP 层 `saveErrorText` 承载，不混入本属性。
- 行为：
  - `download(_:)` **签名不变**（`public func download(_ attachment: Attachment) async -> URL?`）：
    - 无选中邮件（`selectedRef == nil`）→ 返回 nil，不写文案；
    - 成功（缓存命中或下载完成）→ 清空 `attachmentErrorText`，返回 URL；
    - 失败 → 把 `MailError`（非 `MailError` 归一为 `.storage(reason: String(describing:))`）经 `ErrorText.text(for:)` 写入，返回 nil；不吞错静默、不打开。
  - 清空点：`selectedListKey.didSet`（现有每邮件状态重置点，与 `allowsRemoteContent`/`markReadErrorText` 同处）与 `clearSelection()`；同一 listKey 的 reload 不清空。成功下载也清空；下一次失败覆盖。
  - **迟到结果 guard（B3）**：`selectedListKey.didSet` 在选择真正变化时递增 internal `selectionGeneration: UInt64`；`download` 开始时捕获 `generation` 与发起 key，`await` 回来后仅当二者仍匹配才写 `attachmentErrorText`/清空/返回 URL；不匹配则返回 nil 且不写、不清、不打开。A→B→A 也按代际丢弃旧结果（同 key reload 不递增，不误丢）。**APP 不读该成员**：APP 的打开/另存为动作代际在 `uumail` 内自建（`AttachmentActionModel`，见 `CMP-APP`），不新增/不改本 public 面。
  - **取消（B3）**：`download` 在入口与 `await` 回来后检查 `Task.isCancelled`；调用方任务已取消 → 返回 nil，**不写、不清** `attachmentErrorText`；同时 `catch is CancellationError` 返回 nil（防御）。`ReadScene.classify` 目前会把 `CancellationError` 归一为 `.storage`，本批不改 `Scenes`；用户取消路径由调用方取消覆盖（唯一取消来源是 APP 的另存为任务）。
  - 下载仍只经 `read.downloadAttachment`；PRES 不 import AppKit/WebKit、不读写文件、不碰缓存目录；**N3 缺文件重下不在 PRES**（由 APP 在 origin 仍当前时重下一次）。
- 尺寸：`MailboxViewModel.swift` 当前 385 行，新增 `attachmentErrorText`、`selectionGeneration` 与 1 处递增/清空 ≈ 390；`download` 移到 **`Sources/Presentation/MailboxViewModel+Attachments.swift`**（新，≤80 行），主文件仍 ≤400。不新增 target/依赖；`Package.swift`、`MailDomain`/`Scenes` 契约不动。
- 测试（L1，`PresentationTests/MailboxViewModelAttachmentTests`）：
  - 已缓存 → 0 网关、返回 URL、文案 nil；
  - 未缓存 → 1 次 `fetchAttachment`、`markAttachmentCached` 1 次、返回 URL；
  - `offline` → 返回 nil、文案 = `ErrorText.text(for: .offline)`；
  - 非 `MailError` 存储错误 → 返回 nil、文案为 `storage` 中文（不崩溃）；
  - 失败后成功/切换邮件 → 文案清空；同 key reload 不清；
  - **迟到失败**：A 下载在飞 → 切 B → A 失败，`attachmentErrorText` 不写、B 的文案不被覆盖（`T-SCN-0020-01f`）；
  - **迟到成功**：A 下载在飞 → 切 B（B 有错误文案）→ A 成功，B 的文案不被清空、A 不被打开（`T-SCN-0020-01f/09`）；
  - **A→B→A**：代际变化，旧 A 结果仍丢弃；当前选中的 A 新请求正常写；
  - **下载阶段调用方取消（B3）**：`Task` 取消后 `download` 返回 nil、`attachmentErrorText` 不写/不清；未取消的当前选中失败仍正常写（`T-SCN-0020-01g`）；
  - 并发两次 `download` → 共享一次下载（既有 `FlightBoard`），返回同一 URL。
- 定级与确认：**P2**（跨 `Presentation`/`uumail`；一个 additive public 只读成员 + APP 层内部文件）。`attachmentErrorText` 已**人工确认 A（2026-11-20）**：批准只读属性，`download` 签名不变；`selectionGeneration` 为 internal、不新增 public；D1–D18 仍为默认确认（未经人工，D16–D18 见 `design3.md` §8）。回退：删除属性/代际与 `download` 内写入/清空，APP 层改回通用失败文案；无数据/契约迁移。
- 实现进度：未实现（设计落卡 2026-11-20；第 2 轮按评审 B3 增加迟到 guard 与 L1 用例；**第 3 轮按 `review2` B3 增加取消分支与 `01g`，APP 不引用 `selectionGeneration`**）。
- 实现进度（2026-11-20，`T-1120-06`）：`attachmentErrorText` 以 `public internal(set)` 落地；`selectionGeneration` 为 internal `@ObservationIgnored`，只在 `selectedListKey` 真正变化时递增并清空文案；`download` 签名不变，迁入新 `MailboxViewModel+Attachments.swift`（36 行），入口/`await` 后 `Task.isCancelled`、`catch is CancellationError`、`generation+key` guard 全部实现。新增 `Tests/PresentationTests/MailboxViewModelAttachmentTests.swift` 10 例覆盖 `T-SCN-0020-01a–01g`（迟到失败/成功、A→B→A、取消、当前选中失败正常写）；`PresentationTests` 127 例绿、架构 4 门 PASS；`MailboxViewModel.swift` 388 行、`+Attachments.swift` 36 行。

## 设计增量：附件条内联图投影（REQ-0028 / SCN-0022，2026-11-23，P2）

- 来源：`REQ-0028` / `SCN-0022`；决策 `doc/history/decisions/2026-11-23-table-adapt-inline-attachment-filter.md`。
- 变更：`MailboxViewModel.attachments` 的语义从「全量附件」收窄为「附件条展示集」（签名不变，仍 `public internal(set)`）。`MailboxViewModel+Body.startInlineImageRender(_:html:)` 在启动渲染前：
  1. `InlineImageReferences.attachmentIDs(inHTML: html, attachments: attachments)`；
  2. `attachments.removeAll { ids.contains($0.fileReference) }`；
  3. 再启动既有内联渲染任务。
- 全部附件仍由 `ReadScene` 自己取；内联渲染/下载不受投影影响。缓存正文与补拉成功共用 `startInlineImageRender`，因此两条路径都会过滤；纯文本预览没有 `cid:`，不过滤；切换邮件从 store 重新取全量再过滤。
- 时序/并发：过滤在 main actor 同步执行，正文 349KB/55 cid 为毫秒级；重复调用幂等。不改 `download`/`openSelected` 签名，不改 `inlineImageHTML` 的迟到 guard。
- 验证：`PresentationTests/MailboxViewModelInlineImageTests` 新增「隐藏命中项、保留真实附件」「按 `contentID` 命中」「无 `cid:` 保留全部」「歧义保留」；`SCN-0019` 既有 4 例回归。
- 残余：内联图渲染失败时该附件已不在附件条，用户无保存入口；属用户 2026-11-23 确认的代价。
- 实现进度（2026-11-23，`T-1123-03`）：`MailboxViewModel+Body.startInlineImageRender` 先算 `InlineImageReferences` 再 `removeAll` 命中项（`+Body.swift` 150 行）；`MailboxViewModelInlineImageTests` 新增 4 例（`hidesReferencedInlineAttachment`、`hidesInlineAttachmentByContentID`、`keepsAttachmentsWithoutCID`、`ambiguousInlineReferenceKeepsAttachments`），该 suite 8 例绿；全量 384 tests/59 suites、架构 4/4。

## 设计增量：日历视图与会议卡（REQ-0029 / SCN-0024、REQ-0030 / SCN-0023，2026-11-24，P1 已确认、已实现）

- 来源：`REQ-0029`/`SCN-0024`（月/周视图）与 `REQ-0030`/`SCN-0023`（阅读页会议卡）；结构决策与候选方案见 `doc/history/decisions/2026-11-24-calendar-view-scope.md`。
- 新增 public `CalendarViewModel`（`@MainActor @Observable`，`Sources/Presentation/CalendarViewModel.swift`，预计 ≤260 行）：

  ```swift
  @MainActor @Observable public final class CalendarViewModel {
      public enum Mode: Sendable { case month, week }
      public private(set) var mode: Mode
      public private(set) var anchor: Date
      public private(set) var month: MonthGridPresentation
      public private(set) var week: WeekGridPresentation
      public private(set) var isLoading: Bool
      public private(set) var errorText: String?
      public private(set) var isTruncated: Bool
      public private(set) var selectedOccurrence: MeetingOccurrence?
      public init(calendar: CalendarScene, now: @escaping @Sendable () -> Date = Date.init)
      public func activate() async
      public func reload() async
      public func setMode(_ mode: Mode) async
      public func showPrevious() async
      public func showNext() async
      public func showToday() async
      public func select(_ occurrence: MeetingOccurrence, in day: Date) async
      public func icsText(for occurrence: MeetingOccurrence) -> String?   // 失败时置 errorText
      public var selectedSource: (folderID: String, serverID: String)? { get }
  }
  ```

- 新增 public 展示类型（`Sources/Presentation/CalendarPresentation.swift`，预计 ≤180 行）：`MonthGridPresentation{weeks: [MonthWeek], dayTitle, isCurrentMonth}`、`MonthWeek{days:[MonthDay]}`、`MonthDay{date, isInMonth, isToday, chips:[CalendarChip], hiddenCount}`、`WeekGridPresentation{days:[WeekColumn], hourRange}`、`WeekColumn{date, blocks:[WeekBlock]}`、`WeekBlock{startMinute, endMinute, lane, title, occurrence}`、`MeetingCardPresentation{time, location, organizer, recurrence, isRecurring}`。
- `MailboxViewModel` 新增只读计算属性 `meetingCard: MeetingCardPresentation?`（由 `selectedMessage.meeting` 生成；非邀请返回 nil）。**不改** `select`/`openSelected`/正文状态机；`selectedSource` 由 `MailboxView` 从 `selectedMessage.folderID/serverID` 读取，不在 VM 新增公开面。
- 网格投影规则（纯函数，L1 可测）：
  - 周起始固定周一（`Calendar.firstWeekday = 2` 的本地副本，不读系统偏好，避免跨机差异）；月网格固定 6 行 × 7 列（不足的月用相邻月日期补灰格），保证翻月高度稳定；
  - 每个日格最多 3 个事件 chip，其余折成「+N」；`hiddenCount` 参与 L1 断言；
  - 周视图时间轴范围取「本周最早事件的整点向下取整 − 0」到「最晚事件整点向上取整 + 1」，最小 8:00–18:00；重叠事件按 `lane` 并排；
  - 全天事件不出现在周时间轴，集中在周视图顶栏一行（与 Outlook 一致）。
- 文案：时间范围/全天/重复摘要/时区未知提示统一进 `DisplayFormat`（新增 `meetingTimeRange(_:)`、`meetingDay(_:)`、`recurrenceSummary(_:)`、`meetingZoneNote(_:)`），`CalendarViewModel` 与 `MeetingCardPresentation` 共用，视图不拼字符串。
- 错误与空态：`errorText = ErrorText.text(for:)` 只接收 `MailError`；`CalendarScene` 抛的非 `MailError` 在 VM 内归一为 `.storage(reason:)`（沿用 `performMarkRead` 的口径）。空态文案归 `CMP-APP`，VM 只给 `isLoading`/`errorText`/`isTruncated`。
- 冷热与并发：`activate/reload` 在 `@MainActor` 上串行；同一时刻只允许一个刷新任务（新请求取消旧任务），迟到结果按 `anchor`/`mode` 代际丢弃（沿用 `MailboxViewModel+Body` 的代际写法人模式）。
- 尺寸：`Presentation` 现 1669 行 + 约 440 行 → 约 2109 行；`MailboxViewModel.swift` 388 → 约 400（`meetingCard` 计算属性 ≤12 行），仍在 400 上限；不新增 target/依赖。
- 测试（L1，`PresentationTests/CalendarViewModelTests` + `CalendarProjectionTests`）：月网格 6×7 与补灰格、周一为首列、3+1 折叠、周时间轴范围与 lane、翻月/翻周不触网（fake scene 计数）、错误文案映射、截断标记、`meetingCard` 的 nil/非 nil 与重复摘要。
- 定级与确认：**P1**（新 public 视图模型 + 新 public 展示类型 + 依赖新场景组件）；P1 已于 2026-11-24 确认（`history/decisions/2026-11-24-calendar-view-scope.md`）。

## 实现（2026-11-24，T-1124-10）

- `Sources/Presentation/CalendarViewModel.swift`：`CalendarViewModel` + `CalendarProjection` + `MeetingFormat`；
  `Sources/Presentation/CalendarPresentation.swift`：月/周/卡片展示值；`MailboxViewModel.meetingCard` 只读计算属性。
- 测试：`Tests/PresentationTests/CalendarViewModelTests.swift` 11 例（6×7 网格、+N、周 lane 与整点范围、全天、
  模式切换、翻页、ICS、卡片字段/全天/无卡片）。
## 设计增量：浮窗阅读状态、单例路由与列表 30 天窗口（REQ-0031 / REQ-0033，2026-11-24，P2）

- 触发：`REQ-0031` 的浮动阅读窗需要「按引用读一封、就地回复、打开即已读」；`REQ-0033` 把列表加载从 200 条改为最近 30 天。
- 新文件（`Sources/Presentation/`，public additive）：
  - `ReaderViewModel.swift`（≈180 行）：
    - 持有：`ref`、`message`、`header: MessageHeaderPresentation?`、`meetingCard: MeetingCardPresentation?`、
      `body: BodyPresentation`、`bodyNotice`、`markReadErrorText`、`isMissing`、`isComposing`。
    - `load(_ ref: MessageRef)`：`ReadScene.message(ref)` 命中 → 生成头/卡/正文（缓存优先 + `open(ref)` 补拉）；
      未命中 → `isMissing = true`（不抛错）。
    - 打开即已读：`markReadOnOpen()` → `ReadScene.markReadLocally`（失败写 `markReadErrorText`）+ 本地 0→1 时
      `ReadScene.writeBackMarkRead`（失败静默）；与 `MailboxViewModel.performMarkRead` 同一语义，不另造写路径。
    - 远程资源：本实例常量 `allowsRemoteContent = true`；**不写回** `MailboxViewModel.allowsRemoteContent`。
    - 撰写种子：`composeReply()` / `composeReplyAll()` / `composeForward()` 用**本窗 message 与 quotableHTML**，
      与 `MailboxViewModel+Compose` 的三个入口同规则；不读主窗口选中态。
    - 依赖仅 `Scenes`/`MailDomain`，不 import AppKit；不感知窗口。
  - `ReaderRouter.swift`（≈70 行）：
    - `currentRef`、`isComposing`、`blockedNotice: String?`；
    - `open(_ ref:, geometry: ReaderGeometry)`：撰写态 → 只置 `blockedNotice` 并返回 `.blocked`；否则替换 ref 并返回
      `.replaced` / `.created`（由 App 层据此建窗或置前）；
    - `readerSize(for geometry: ReaderGeometry) -> CGSize`（纯函数）：`宽 = max(480, geometry.readingPaneWidth)`、
      `高 = max(460, min(geometry.windowHeight * 0.85, geometry.screenHeight))`；几何缺失时用 1280×720 兜底。
    - `ReaderGeometry` 为值类型（阅读区宽、主窗口高、屏可用高），由 App 层测点写入；PRES 不读 `NSWindow`。
- `MailboxViewModel` 改动（拆迁见 `+Compose` / `+Body` 既有拆分纪律）：
  - 列表加载：`read.messages(folderID:limit: 200)` → `read.messages(folderID:since: startOfDay(now − 30d))`；
    计数与状态栏仍取 `visibleMessages.count`，不加封顶、不加提示。
  - 新增 `makeReaderModel() -> ReaderViewModel`（放在 `MailboxViewModel+Compose.swift`）：注入 `read`、`composeScene`、
    `account`、`onEnqueued`；主文件 `MailboxViewModel.swift` **本批不增长**（实测 416 行，见 `plan/risks.md` R70；列表改动是
    就地替换一次调用，factory 进 `+Compose` 扩展）。该文件已超 ≤400 预算属**既有欠账**，本批不夹带拆分；若实现后仍在 400 以上，
    按 R70 的方案另立拆分任务，不以「反正已经超了」为理由继续加。
- 数据所有权：浮窗阅读态（ref、正文、撰写态）是**每窗一份**的展示状态，由 `ReaderViewModel`/`ReaderRouter` 持有；
  邮件与正文真源仍是 `CMP-STORE`，浮窗不复用也不写主窗口的 `selection`/`body`/`allowsRemoteContent`。
- 不变量：
  - 浮窗与主窗口同时打开同一封时，两边的正文各走各的缓存读取，不共享可变状态；
  - 已读只有一条写路径（`markReadLocally` + `writeBackMarkRead`），浮窗不新增写命令；
  - 路由的「撰写态拒绝替换」是显式状态迁移，不用视图层标志位。
- 预算：`Presentation` 当前约 1,700+ 行 → 约 1,950；两新文件合计 ≈250；`MailboxViewModel` 416 → 不增长（R70 另有拆分任务）；
  新文件单文件 ≤250，`MailboxViewModel+Compose.swift` 增加约 12 行。
- 验证（`PresentationTests`）：
  - `ReaderRouter`：created/replaced/blocked 三态、撰写态替换被拒、尺寸纯函数的 480/460 下限与屏高上限、几何缺失兜底；
  - `ReaderViewModel`：命中/缺失、缓存命中不触网、补拉失败文案、打开即已读只写一次、三种种子与主窗口一致；
  - 列表窗口：`since` 由固定时钟注入计算（30 天前 00:00）、不再出现 200 条截断、计数 = 返回行数。

## 实现（2026-11-24，T-1124-19）

- 新文件：`ReaderViewModel.swift`（218 行）、`ReaderRouter.swift`（107 行）、`MailboxViewModel+Reader.swift`（35 行：
  `listWindowStart` / `makeReader` / `reloadListAfterExternalChange`）。
- `MailboxViewModel.reloadCurrentList` 改为 30 天窗口；新增私有写 `sync.phase` 的小方法 `presentLocalListFailure`
  （extension 在本文件外无法写 `sync`）。
- 预算：`MailboxViewModel.swift` **424 行**（原 416，本批 +8：窗口加载一行 + 失败回填 helper），仍超 ≤400，
  已登记 `plan/risks.md` R70；拆分不在本批夹带。
- 测试 `Tests/PresentationTests/ReaderViewModelTests.swift` 10 例（3 套件）：路由尺寸/三态、缓存正文与即读写一次、
  缺失 ref、回复种子、预览不可引用、窗口边界与无 200 条截断、空文件夹。

## 实现（2026-11-24，W-REFACTOR-03 预算拆分）

- `MailboxViewModel.swift` 424 → **366**：列表加载与选中（`reloadFolders`/`reloadCurrentList`/`select(_:open:)`/`clearSelection`/`isHidden`）
  移到 `MailboxViewModel+List.swift`（69 行）。
- `CalendarViewModel.swift` 424 → **172**：纯网格数学 `CalendarProjection` 移到 `CalendarProjection.swift`（254 行）。
- **公开面变更（P2）**：`MailboxViewModel.messages` 与 `.folders` 的 setter 由 `private(set)` 放宽为 `internal(set)`，供同模块扩展写；
  公开读面与语义不变，app/组合根仍只读。`MailboxViewModel.selection` 仍是 `internal(set)`（既有）。
- 验证：`PresentationTests` 全绿；`MailboxViewModel` 单文件 366/400。

## 实现（2026-11-24，R77 会议契约解耦）

- `MailboxViewModel.meetingCard` 改为由 `meetingInvite` 派生；`meetingInvite: MeetingInvite?` 在选中/刷新时由
  `refreshSelectedMeeting()` 调 `ReadScene.meeting(for:)` 取一次（setter `internal(set)`，公开读面不变）。
- `ReaderViewModel.load` 同样经 `ReadScene.meeting(for:)` 取卡；不再有 `Message.meeting`。
- 选中切换、刷新保留选中、删除后清空三条路径都覆盖：`select(_:open:)` 刷新、`clearSelection()` 置空。

## 设计增量：浮窗居中与周视图固定时间窗（REQ-0035 / REQ-0036，2026-11-24，P3，已实现）

- 来源：`REQ-0035`（浮窗默认居中）/ `REQ-0036`（周视图固定为 8:00–24:00）；`CMP-APP` 同日增量负责 AppKit
  放置与小时虚线绘制，本节只收纯函数与投影规则。
- `ReaderRouter` 新增 additive public 纯函数：

  ```swift
  public static func centeredOrigin(
      in container: CGRect,
      size: CGSize,
      visible: CGRect
  ) -> CGPoint
  ```

- 不变量：
  - 以 `container` 的中心为浮窗中心：`x = container.midX - size.width / 2`，`y` 同理；
  - 再夹进 `visible`：x 的上界为 `max(visible.minX, visible.maxX - size.width)`，y 同理；
    尺寸不超过屏幕时结果完整落在 `visible` 内；
  - 尺寸大于 `visible` 时上界退化为 `visible.minX`/`minY`，即贴 min 边，不把窗口放到负方向；
  - 纯函数：不读 `NSWindow`/`NSScreen`、不写状态、不触网；App 层只传
    `mailbox.frame`、窗口 `frame.size`、`screen.visibleFrame` 三个矩形。
- `CalendarProjection.week` 固定 `startHour = 8` / `endHour = 24`：删除按会议最早/最晚的
  `minMinute`/`maxMinute` 伸缩；时间轴固定从 8:00 开始、到 24:00 结束，高度不再随本周会议变化；
  `WeekGridPresentation` 的字段与消费方不变。
- 公开面：`ReaderRouter.centeredOrigin` 是本次唯一新增 public 面，additive；`open`/`reset`/
  `beginComposing`/`endComposing`/`readerSize`/`ReaderGeometry` 与 `CalendarViewModel`/
  `CalendarProjection` 既有签名均不变；不改 schema/依赖/target。
- L1：`ReaderViewModelTests` 的 `centeredOrigin` 覆盖居中（1200×800 容器 + 600×400 浮窗 → `(400,300)`）、
  贴边夹取与完整落在 `visible` 内；`CalendarViewModelTests` 与 `CalendarScenarioTests` 断言
  `week.startHour == 8 && week.endHour == 24`。全量 461 tests / 77 suites、架构 4/4。
- 定级：**P3**（单模块内部定位/投影规则；additive public 纯函数；无 schema/依赖/公开契约语义变化）。

