---
layer: design
module: app
status: active
updated: 2026-11-14
component: CMP-APP
---

# CMP-APP AppShell 组件规格

## 模块卡

- 状态：`active`（视图只绑定视图模型；`UumailApp` 只做装配与窗口宿主）
- 单元：组件
- 层 / 类型：L3；UI 外壳
- 业务价值：让用户能看见并操作邮箱；没有它，同步能力只存在于命令行。
- 负责 X：窗口与导航、文件夹选择、邮件列表渲染、正文 WebView、撰写/配置表单、空态与失败态展示；T-1114-10 设计新增列表焦点 Delete/Backspace、`scenePhase` 转发、状态栏删除错误（2026-11-14 已实现，T-1114-18）。
- 不负责 Y：业务编排、状态机、格式化规则、服务装配、网络与持久化。
- 内部逻辑：
  - `UumailApp` 构造 `AppComposition`，按 `route` 显示 `MailboxView` 或 `AccountSetupView`；生命周期交给组合根。
  - 每个视图只接收一个视图模型（`@Bindable`），动作一律 `viewModel.xxx()`；响应式刷新只看 VM 状态。
  - 正文渲染：`MessageWebView`（WKWebView、禁 JS、CSP 阻止远程资源）；附件条点击调 VM。
- 拥有的数据：无；账号凭据归 `CredentialStore`，邮件数据归 `MailStore`。
- 变化轴：窗口形态（单窗口 → 多窗口/菜单栏）、列表与阅读布局。
- 公开契约：无对外契约；只依赖 `Presentation`（`UumailApp` 另依赖 `Composition`）。
- 入口：`Sources/uumail/UumailApp.swift#UumailApp`、`MailboxView.swift#MailboxView`、`MessageBodyView.swift#MessageBodyView`、`ComposeView.swift#ComposeView`、`AccountSetupView.swift#AccountSetupView`
- 依赖：`Presentation`、`Composition`（仅 `UumailApp.swift`）、SwiftUI/AppKit/WebKit。扇出 2。
- 冷热：热（读本地库）。
- 尺寸预算：单文件 ≤300 行；当前 `uumail` 共 493 行。
- 单独运行：`./Scripts/make-app.sh && open dist/uumail.app`（release 构建，产物不入库）
- 删除测试：删掉则只能命令行看信，对终端用户等于没有产品。

## 实现进度（2026-11-14）

| 能力 | 代码 | 验证 |
|---|---|---|
| 启动装配与路由 | `UumailApp.swift` | `CompositionTests`（fake gateway 冒烟）；真机 bootstrap 未跑 |
| 账号配置页 | `AccountSetupView.swift` + `AccountSetupViewModel` | `AccountSetupViewModelTests` 4 例 |
| 文件夹侧栏 + 列表 | `MailboxView.swift` + `MailboxViewModel` | VM 选择/搜索/刷新用例；真机 200 封渲染（重构前） |
| 正文阅读（WKWebView、禁 JS、CSP） | `MessageBodyView.swift` + `MessageBodyView` 状态 | VM 正文状态 5 例；sanitizer 无自动化断言 |
| 附件条下载并打开 | `MessageBodyView.swift` → `VM.download` → `ReadScene` | `ReadSceneTests` 2 例；真机未验 |
| 搜索框（本地 FTS） | `MailboxView` → `MailboxViewModel.search` | VM 搜索用例 |
| 撰写：新建/回复/转发/存草稿/发送 | `ComposeView.swift` + `ComposeViewModel` | 5 例；2026-11-14 用户真机实测：App 端到端发送与接收通过 |
| 全部回复工具栏 | `MailboxView.swift` → `MailboxViewModel.composeReplyAll` | 编译；接线由 `MailboxViewModelTests` 2 例覆盖（T-1114-07）；真机点击冒烟通过（T-1114-09） |
| 刷新节奏（5 分钟轮询） | `MailboxViewModel.startAutoRefresh` → `SyncScene` | `SyncSceneTests`；真机长跑未验 |
| 附件缓存（2 GB 最旧优先） | `FileAttachmentFiles`（Composition） | `FileAttachmentFilesTests` 3 例 |

## 待办 / 残留

- 无 pending/failed outbox 角标：列表/状态栏看不到待发与失败数（`plan/risks.md` R13）。
- 回复未带真实 `Message-ID`（本地只存 ServerId），会话归并依赖服务器。
- 撰写暂不支持加附件；发送成功后无本地 Sent 镜像（依赖服务器 `SaveInSentItems`）。
- 附件 25MB 上限、断点续传、`AttachmentName` 回退未实现；真机下载/打开未验。
- 已读回写/列表键盘删除已实现（T-1114-11…18，2026-11-14）；正文 sanitizer 仍是 CSP + 关脚本的轻量实现。
- 视图层已无 `service` 参数与模型构造（门 1 与 grep 验证），但这是构造性约束，不是行为测试。

## 设计增量：全部回复按钮（T-1114-08，已实现 2026-11-14）

- `MailboxView` 工具栏在「回复」与「转发」之间加「全部回复」按钮；`viewModel.selectedMessage == nil` 时 disabled，动作只调 `viewModel.composeReplyAll()`。
- 视图不读 `Message` 字段、不拼地址、不判断 `Cc` 是否为空；所有地址规则在 `ComposeScene`/`AddressList`。
- `ComposeView` 已有「抄送」输入框，不需要新增控件或绑定逻辑。
- 验证：编译 + `MailboxViewModelTests` 接线；真机冒烟已执行（2026-11-14，T-1114-09 第 2 轮）：带 Cc 多人邮件（From 自己）→ 点「全部回复」→ To/Cc 正确、自己不出现在任一栏 → 点「发送」→ outbox 行与 MIME 均带 Cc。为避免向真实同事投递，冒烟用本地录制网关（MIME 落盘后返回 `offline`，outbox 行保留），未向真实邮箱发信。

**实现（2026-11-14）**：`MailboxView` 工具栏在「回复」「转发」之间加「全部回复」（`arrowshape.turn.up.left.2`），无选中邮件时 disabled，按钮动作只调 `MailboxViewModel.composeReplyAll()`；视图未新增 `Message` 字段读取或地址拼接。`./Scripts/swiftw build` 通过；全量 182 tests / 38 suites 与架构 4 门全绿。按钮渲染与点击的真机冒烟已执行（2026-11-14，T-1114-09 第 2 轮，本地录制网关，未向真实邮箱投递）。

## 设计增量：列表焦点删除与前台状态（T-1114-10，2026-11-14 设计；T-1114-18 已实现）

- 列表焦点：`MailboxView` 给消息列表加 `@FocusState` 与 `.focusable()`，在聚焦容器上挂 `.onDeleteCommand { Task { await viewModel.deleteSelected() } }`；若最小探针证明 `List` 不吃 `onDeleteCommand`，改用 `.onKeyPress(.delete)`（仅列表聚焦时）。**不用全局 `NSEvent` 监听器**，避免抢搜索框/正文/撰写页的按键。
- 焦点排他：绑定只挂在列表上；搜索框、正文 WebView、撰写 sheet、配置页各自持有焦点，不进入删除路径。验收含「焦点在搜索框按 Delete/Backspace 不删除」。
- 前台状态：`@Environment(\.scenePhase)` + `onAppear`/`onChange` 调 `viewModel.setApplicationActive(phase == .active)`；视图只转发，不判计时。若实测 macOS 窗口失焦时 `scenePhase` 不变，改用 `NSApplication.didBecomeActiveNotification`/`willResignActiveNotification`，仍只转发。
- 列表与状态栏：`ForEach`/空态/计数改用 `viewModel.visibleMessages`；状态栏优先显示 `viewModel.deleteErrorText`（带警告图标），否则显示同步状态。视图不判 `MailError`、不拼中文。
- 列表身份（R23）：搜索模式跨文件夹结果不得只用 `serverID` 作 `ForEach`/`List(selection:)`/tag 的身份；按 `CMP-PRES` 的 `MessageRef`/等价复合键方案接线，否则同 ID 邮件会选错/删错。若需要改 `Selection.messageID` 的公开类型/语义，按 P2 契约变更另评。
- 不改：工具栏按钮、搜索框绑定、正文渲染、撰写 sheet；仍单选中。
- 验证：编译 + `MailboxViewModelTests` 的删除/计时接线；T-1114-18 先做焦点/按键最小探针（AX 或真机），证据入 `evidence/`；探针失败则停下上报，不用全局监听器兜底。
- 尺寸：`MailboxView` 当前 175 行，预计 +20～25，仍低于 300。

**实现（2026-11-14）**：`MailboxView` 列表使用 `visibleMessages` 与复合 `listKey`，加 `@FocusState`/`.focusable()`、`.onDeleteCommand` 主路径与 `.onKeyPress(.delete)` 备选、`scenePhase` 转发、状态栏 `deleteErrorText`。最小 UI 探针（SwiftUI + `NSEvent`，见 `task-spaces/20261114-232232/evidence/ui-delete-probe*`）：列表聚焦时 `deleteCommands=1`、搜索框聚焦时 `deleteCommands=0`，证明命中与焦点排他；`keyPresses=0` 说明 `.onDeleteCommand` 已消费按键。**真机窗口未跑**，探针是独立最小宿主，不等于真机 AX 证据。
