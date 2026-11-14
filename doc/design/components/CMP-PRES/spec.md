---
layer: design
module: presentation
status: active
updated: 2026-11-14
component: CMP-PRES
---

# CMP-PRES Presentation 组件规格

## 模块卡

- 状态：`active`
- 单元：模块（薄视图模型 + 展示类型 + 文案/格式化）
- 层 / 类型：L3；表现
- 业务价值：把用户动作转成一次场景调用，把场景结果映射为可观察状态与中文文案；让视图退化成绑定。没有它，视图直接持有场景并写展示逻辑，状态机无法测试。
- 负责 X：`MailboxViewModel`（文件夹/列表/正文/附件/同步/选择/搜索/自动刷新）、`ComposeViewModel`（新建/回复/全部回复/转发、入队状态、草稿）、`AccountSetupViewModel`（validate/connect、忙碌态、错误）、展示类型（`BodyPresentation`、`BodyNotice`、`SyncPresentation`、`Selection`）、`ErrorText` 唯一文案表、`DisplayFormat`（发件人/日期）。
- 不负责 Y：业务规则、直接访问 `MailStore`/`MailGateway`/`Outbox`、轮询节奏（`SyncScene`）、缓存优先与补拉（`ReadScene`）。
- 内部逻辑：
  - 每个动作只调一次场景方法；结果映射为状态，不重试、不判断业务分支。
  - 正文：缓存优先 → `.loading`/摘要提示 → `.loaded(html, truncated)` 或 `.failed(text)`；`BodyNotice` 承载「正在补拉」与「摘要回退」。
  - 自动刷新：消费 `SyncScene.startAutoRefresh` 流，映射 `SyncPresentation`；`stopAutoRefresh` 取消消费并停场景循环。
  - `ComposeViewModel.send` 调 `ComposeScene.send`，成功即 `status = .queued` 并触发组合根的投递信号；失败保留编辑文本。
- 拥有的数据：视图状态（选择、搜索词、加载态、编辑器文本），不持久化。
- 变化轴：窗口形态与交互。
- 公开契约：`CMP-PRES#MailboxViewModel`、`#ComposeViewModel`、`#AccountSetupViewModel`、`#ErrorText`、`#DisplayFormat`
- 入口：`Sources/Presentation/MailboxViewModel.swift#MailboxViewModel`、`ComposeViewModel.swift#ComposeViewModel`、`AccountSetupViewModel.swift#AccountSetupViewModel`、`ErrorText.swift#ErrorText`、`PresentationTypes.swift#BodyPresentation`
- 依赖：`Scenes`、`MailDomain`、Observation。扇出 1。
- 冷热：热（主线程）。
- 尺寸预算：单文件 ≤400 行；当前 `MailboxViewModel` 345、`ComposeViewModel` 196、`AccountSetupViewModel` 约 100；`Presentation` 共 758 行。
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
      public init(read: ReadScene, sync: SyncScene, compose: ComposeScene, account: AccountID, onEnqueued: (@MainActor () -> Void)? = nil)
      public func startAutoRefresh(every: Duration = .seconds(300))
      public func stopAutoRefresh()
      public func refresh() async
      public func loadCached()
      public func select(folderID: String)
      public func select(messageID: String)
      public func openSelected() async
      public func search(_ query: String) async
      public func download(_ attachment: Attachment) async -> URL?
      public func composeNew() -> ComposeViewModel
      public func composeReply() -> ComposeViewModel?
      public func composeReplyAll() -> ComposeViewModel?
      public func composeForward() -> ComposeViewModel?
  }

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
