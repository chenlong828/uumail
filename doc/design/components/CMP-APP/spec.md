---
layer: design
module: app
status: active
updated: 2026-11-25
component: CMP-APP
---

# CMP-APP AppShell 组件规格

## 模块卡

- 状态：`active`（视图只绑定视图模型；`UumailApp` 只做装配与窗口宿主）
- 单元：组件
- 层 / 类型：L3；UI 外壳
- 业务价值：让用户能看见并操作邮箱；没有它，同步能力只存在于命令行。
- 负责 X：窗口与导航、顶部三段邮箱切换（收件箱/发件箱/日历；2026-11-24 起替代文件夹侧栏）、窗口主工具栏（`MailboxToolbar`）、邮件列表渲染、正文 WebView、附件条取用交互（单击选中/双击/右键/另存为，2026-11-20 设计新增）、撰写/配置表单、空态与失败态展示；T-1114-10 设计新增列表焦点 Delete/Backspace、前台状态转发（实测后改用 `NSApplication` 通知）、状态栏删除错误（2026-11-14 已实现，T-1114-18）；2026-11-18 设计新增撰写页收件人/抄送字段控件与候选浮层（`RecipientTextField`/`RecipientSuggestionList`/`RecipientForm.swift` 的 `ComposeRecipientForm`）。
- 不负责 Y：业务编排、状态机、格式化规则、服务装配、网络与持久化。
- 内部逻辑：
  - `UumailApp` 构造 `AppComposition`，按 `route` 显示 `MailboxView` 或 `AccountSetupView`；生命周期交给组合根。
  - 每个视图只接收一个视图模型（`@Bindable`），动作一律 `viewModel.xxx()`；响应式刷新只看 VM 状态。
  - 正文渲染：`MessageWebView`（WKWebView、禁 JS、CSP 阻止远程资源）；附件条由 `AttachmentStripView` 呈现，取用动作经 `MailboxView` 调 VM/保存流（2026-11-20 设计）。
- 拥有的数据：无；账号凭据归 `CredentialStore`，邮件数据归 `MailStore`。
- 变化轴：窗口形态（单窗口 → 多窗口/菜单栏）、列表与阅读布局、字号档位（2026-11-17 新增五档 UI 偏好）。
- 公开契约：无对外契约；只依赖 `Presentation`（`UumailApp` 另依赖 `Composition`）。
- 入口：`Sources/uumail/UumailApp.swift#UumailApp`、`MailboxView.swift#MailboxView`、`AttachmentStripView.swift#AttachmentStripView`（2026-11-20 设计新增，internal；双击/右键/选中/键盘/错误 banner）、`AttachmentExport.swift#SystemSavePanel`/`#AttachmentFileCopy`/`#AttachmentSaveFlow`/`#AttachmentActionGate`/`#AttachmentActionModel`（2026-11-20 设计新增，internal；`AttachmentActionModel` 为第 3 轮 APP 动作代际协调者）、`MailboxToolbar.swift#MailboxToolbar`（2026-11-16 设计新增）、`MessageBodyView.swift#MessageBodyView`、`ComposeView.swift#ComposeView`、`RecipientForm.swift#ComposeRecipientForm`（2026-11-18 设计新增，internal；方案设计复核从 `ComposeView.swift` 拆出，供 L2 探针单独编译）、`RecipientTextField.swift#RecipientTextField`/`#RecipientSuggestionList`（2026-11-18 设计新增，internal）、`AccountSetupView.swift#AccountSetupView`、`FontSizeStyle.swift#EnvironmentValues.fontSizePreference`/`#View.scaledFont(_:)`/`#View.scaledInheritedFont(_:)`/`#FontSizePreference.font(for:)`、`FontSizeCommands.swift#FontSizeCommands`、`EmptyState.swift#EmptyState`（2026-11-17 设计新增，internal；第 2 轮修正入口符号）
- 依赖：`Presentation`、`Composition`（仅 `UumailApp.swift`）、SwiftUI/AppKit/WebKit。扇出 2。
- 冷热：热（读本地库）；收件人候选只读 VM 内存状态，不触网、不查库。
- 尺寸预算：单文件 ≤300 行；当前 `Sources/uumail` 共 **3813 行**（2026-11-24 `wc -l`；`MailboxView` **293**、`CalendarView` 293、`MessageBodyView` 267，其余见文末增量）；单文件均 ≤300，不新增 target/依赖。
- 单独运行：`./Scripts/make-app.sh && open dist/uumail.app`（release 构建，产物不入库）；`swift run` 为无 bundle `Info.plist` 的可执行，**没有 ATS 域策略**，明文 http 图片本来即可加载（REQ-0024 L2 实测，见文末 2026-11-19 增量）
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
- 撰写暂不支持加附件；发送成功不做本地 Sent 镜像——副本由服务器 `SaveInSentItems` 保存，打开「发件箱」时按需同步（2026-11-24）。
- 附件 25MB 上限、断点续传、`AttachmentName` 回退未实现；真机下载/打开未验。
- 已读回写/列表键盘删除已实现（T-1114-11…18，2026-11-14）；正文 sanitizer 仍是 CSP + 关脚本的轻量实现。
- 视图层已无 `service` 参数与模型构造（门 1 与 grep 验证），但这是构造性约束，不是行为测试。
- 其他文件夹（草稿/已删除/垃圾邮件等）不渲染、不同步、无入口；2026-11-24 按用户选择定案（`REQ-0038` 非目标），不是缺陷。

## 设计增量：全部回复按钮（T-1114-08，已实现 2026-11-14）

- `MailboxView` 工具栏在「回复」与「转发」之间加「全部回复」按钮；`viewModel.selectedMessage == nil` 时 disabled，动作只调 `viewModel.composeReplyAll()`。
- 视图不读 `Message` 字段、不拼地址、不判断 `Cc` 是否为空；所有地址规则在 `ComposeScene`/`AddressList`。
- `ComposeView` 已有「抄送」输入框，不需要新增控件或绑定逻辑。
- 验证：编译 + `MailboxViewModelTests` 接线；真机冒烟已执行（2026-11-14，T-1114-09 第 2 轮）：带 Cc 多人邮件（From 自己）→ 点「全部回复」→ To/Cc 正确、自己不出现在任一栏 → 点「发送」→ outbox 行与 MIME 均带 Cc。为避免向真实同事投递，冒烟用本地录制网关（MIME 落盘后返回 `offline`，outbox 行保留），未向真实邮箱发信。

**实现（2026-11-14）**：`MailboxView` 工具栏在「回复」「转发」之间加「全部回复」（`arrowshape.turn.up.left.2`），无选中邮件时 disabled，按钮动作只调 `MailboxViewModel.composeReplyAll()`；视图未新增 `Message` 字段读取或地址拼接。`./Scripts/swiftw build` 通过；全量 182 tests / 38 suites 与架构 4 门全绿。按钮渲染与点击的真机冒烟已执行（2026-11-14，T-1114-09 第 2 轮，本地录制网关，未向真实邮箱投递）。

## 设计增量：列表焦点删除与前台状态（T-1114-10，2026-11-14 设计；T-1114-18 已实现）

- 列表焦点：`MailboxView` 给消息列表加 `@FocusState` 与 `.focusable()`，在聚焦容器上挂 `.onDeleteCommand { Task { await viewModel.deleteSelected() } }`；若最小探针证明 `List` 不吃 `onDeleteCommand`，改用 `.onKeyPress(.delete)`（仅列表聚焦时）。**不用全局 `NSEvent` 监听器**，避免抢搜索框/正文/撰写页的按键。
- 焦点排他：绑定只挂在列表上；搜索框、正文 WebView、撰写 sheet、配置页各自持有焦点，不进入删除路径。验收含「焦点在搜索框按 Delete/Backspace 不删除」。
- 前台状态：`onAppear` 读 `NSApp.isActive`，并监听 `NSApplication.didBecomeActiveNotification` / `willResignActiveNotification` 调 `viewModel.setApplicationActive(...)`；视图只转发，不判计时。**2026-11-14 实测**：真实 SwiftUI `WindowGroup` 窗口的 `@Environment(\.scenePhase)` 始终 `.active`，即使应用失活/回焦（`NSApp.isActive` 与两个通知会变），所以不用 `scenePhase` 作为前台信号（备用方案转正）。
- 列表与状态栏：`ForEach`/空态/计数改用 `viewModel.visibleMessages`；状态栏优先显示 `viewModel.deleteErrorText`（带警告图标），否则显示同步状态。视图不判 `MailError`、不拼中文。
- 列表身份（R23）：搜索模式跨文件夹结果不得只用 `serverID` 作 `ForEach`/`List(selection:)`/tag 的身份；按 `CMP-PRES` 的 `MessageRef`/等价复合键方案接线，否则同 ID 邮件会选错/删错。若需要改 `Selection.messageID` 的公开类型/语义，按 P2 契约变更另评。
- 不改：工具栏按钮、搜索框绑定、正文渲染、撰写 sheet；仍单选中。
- 验证：编译 + `MailboxViewModelTests` 的删除/计时接线；T-1114-18 先做焦点/按键最小探针（AX 或真机），证据入 `evidence/`；探针失败则停下上报，不用全局监听器兜底。
- 尺寸：`MailboxView` 当前 175 行，预计 +20～25，仍低于 300。

**实现（2026-11-14）**：`MailboxView` 列表使用 `visibleMessages` 与复合 `listKey`，加 `@FocusState`/`.focusable()`、`.onDeleteCommand` 主路径与 `.onKeyPress(.delete)` 备选、`NSApplication` 前台通知转发、状态栏 `deleteErrorText`。焦点 UI 探针（SwiftUI + `NSEvent`，见 `task-spaces/20261114-232232/evidence/ui-delete-probe-focus.txt`）逐上下文验证：列表 `deleteCommands=1`；搜索框 / 正文 `NSTextView` / 撰写 sheet / 配置页均 `deleteCommands=0`，并记录各自 firstResponder 证明按键落在目标控件上。真实 SwiftUI `WindowGroup` 前台探针（`evidence/scene-phase-probe.txt`）：`scenePhase` 始终 `.active`，`NSApp.isActive` 与 `willResignActive`/`didBecomeActive` 通知会变化；实现已改用通知，视图只转发。探针是独立宿主，不是 `uumail` bundle 的 AX 驱动；列表命中/排他与前台信号机制均已实测。

## 设计增量：菜单主题与深色阅读白底（2026-11-16，P2 已确认；实现 2026-11-16）

- 来源：`REQ-0015` / `REQ-0016`；完整设计论证、候选取舍与探针见 `task-spaces/20261116-145040/design.md`、`evidence/`；确认记录见 `doc/history/decisions/2026-11-16-theme-appearance.md`；正式场景卡 `SCN-0010`（`doc/design/scenarios/mail/read/dark-reading-pane/`）与 `SCN-0011`（`doc/design/scenarios/settings/appearance/theme-switch/`）已于 2026-11-16 转 `designed`。
- 阅读白底（`REQ-0015`，`SCN-0010`）：
  - `MessageWebView.makeNSView` 把画布固定为不透明浅色：沿用现有 KVC `setValue(true, forKey: "drawsBackground")`（macOS 的 `WKWebView` 没有公开 `drawsBackground` 属性，不引入新的私有 API）、`underPageBackgroundColor = .white`、`appearance = NSAppearance(named: .aqua)`；`updateNSView` 在 `lastRender` guard 之前复确认 appearance（R24），`lastRender` 未变时不调用 `loadHTMLString`。
  - `MessageWebView.baseStyle` 与 `sanitized` 抽到新文件 `Sources/uumail/MessageBodyStyle.swift`（`enum MessageBodyStyle`，internal，无 SwiftUI/WebKit 依赖）；`baseCSS` 增 `html, body { background-color: #ffffff; color-scheme: light; }`；CSP 两档策略与注入顺序不变；`MessageBodyView` 只保留视图与占位/附件/banner。
  - 范围只限正文画布；附件条、截断提示、侧栏/列表/工具栏（含远程图片开关）仍随主题（Q6 A，2026-11-16 确认）。
  - 语义取舍：正文 `prefers-color-scheme` 固定 light，作者 dark-media 变体不生效；作者显式背景/文字色/表格/图片保留。若产品要保留暗色变体，先改 `REQ-0015`/`SCN-0010`。
- 菜单主题（`REQ-0016`，`SCN-0011`）：
  - `UumailApp` 拥有 `@State theme: ThemePreference` 与 `private let store: ThemePreferenceStore`（`init` 先构造本地 store 再赋 `self.store`、`_theme = State(initialValue: store.load())`、`_composition`，不在 `self` 未初始化时调用 store），根视图 `.preferredColorScheme(theme.colorScheme)`，Scene `.commands { ThemeCommands(theme:store:) }`。
  - 新文件 `Sources/uumail/ThemeCommands.swift`：`CommandGroup(after: .sidebar)` + `Picker("主题", selection:)`，三项「跟随系统/浅色/深色」；`Binding` setter 用 `guard newValue != theme` 保证重复选择幂等，变化时 `theme = newValue; store.save(newValue)`；`ThemePreference → ColorScheme?` 映射在本文件。
  - 机制选 `preferredColorScheme`，不用 `NSApp.appearance`；真实 SwiftUI App 探针证明覆盖窗口标题栏与 sheet、运行时切换、`nil` 跟随系统。菜单勾选只在父 View 菜单打开时刷新，测试须先打开父菜单。
- 不改：`MailboxView`/`ComposeView`/`AccountSetupView` 作为消费者；`Package.swift` 依赖/target；`CMP-ROOT`；`CMP-SCN-READ`；`MailDomain`/`MailStore`/`Scenes` 契约；schema。
- 预算：`UumailApp` 45→57、`ThemeCommands` 45、`MessageBodyStyle` 41、`MessageBodyView` 164→146；单文件仍 ≤300，CMP-APP 实测总行数 608。
- 验证：`PresentationTests` 的 `ThemePreferenceStoreTests`；独立 `AppearanceProbe`（编译生产 `MessageBodyStyle.swift`）与 `ThemeProbe`；真实 app 截图/AX 冒烟；证据入 `task-spaces/<run>/evidence/`。不新增 `uumail` 测试 target。
- 夹具精度（第 2 轮复核 D2）：`T-SCN-0010-03` 的作者背景断言须用 body 级背景或把采样点落在作者着色元素内；`#123456` 的 `takeSnapshot` 实测约 `rgba(21,69,105,1.00)`（sRGB），断言用容差（±2/通道），不对源 hex 精确相等；页面中心落在未着色区域时采样为白色是兜底生效，不是作者样式被覆盖。
- 第 2 轮复核（2026-11-16，run `20261116-154416`）：与现状代码逐项核对，无结构性漂移；补充 KVC 与采样夹具口径；实现后实测 CMP-APP 608 行，单文件最大 `MailboxView` 210 行，仍 ≤300。
- 确认（2026-11-16，T-1116-01）：Q5 A（`settings/appearance/theme-switch` + 系统 View「主题」子菜单）、Q6 A（只正文画布）、P2 确认（白底机制 A、应用机制 A、偏好归属 B、菜单 A、测试载体 B′、`MessageBodyStyle` 抽文件，含 D1/D2/D4 与「作者 dark-media 变体不生效」）。确认来源见 `doc/history/decisions/2026-11-16-theme-appearance.md`；正式卡已落并转 `designed`，任务拆分见 `plan/roadmap.md` §W-M3-04。
- 实现（2026-11-16，T-1116-02…04）：`Sources/Presentation/ThemePreference.swift`、`Sources/uumail/ThemeCommands.swift`、`Sources/uumail/MessageBodyStyle.swift`、`UumailApp.swift`、`MessageBodyView.swift` 已按本节落地；`ThemePreferenceStoreTests` 5 例、`AppearanceProbe`/`ThemeProbe` 探针通过，原始输出见 `task-spaces/20261116-154416/evidence/`。实测行数见本节末。

## 设计增量：阅读页信封头（REQ-0017 / SCN-0012，2026-11-16，P2 已确认、未实现）

- 来源：`REQ-0017`（`accepted`）/ `SCN-0012`；映射与格式化在 `CMP-PRES`（见其设计增量），本组件只渲染展示值。
- P2 确认（2026-11-16，T-1116-07）：D1–D8 按 `design.md` §9.2 建议答案确认，确认记录见 `doc/history/decisions/2026-11-16-reading-pane-headers.md`；本增量形状不变。实现进度见文末追加行。
- 新文件 `Sources/uumail/MessageHeaderView.swift`（internal，约 45 行，CMP-APP 内部，不新增 target/组件）：
  - 入参 `header: MessageHeaderPresentation`；只读 `header.subject` 与 `header.rows`，不接触 `Message` 原始字段、不拼地址、不判空。
  - 布局：`VStack(alignment: .leading, spacing: 4)`；主题 `.headline` + `.lineLimit(2)`；每行 `HStack`：`Text(label)` 固定宽 44pt、右对齐、`.secondary`；`Text(value)` 左对齐、`lineLimit(row.lineLimit)`、`.frame(maxWidth: .infinity, alignment: .leading)`；外边距水平 12pt / 垂直 8pt。
  - `.textSelection(.enabled)` 只加在头部块上：用户可复制信封信息；这也是 L2 `HeaderProbe` 读取渲染文本的 seam（SwiftUI 可选中 `Text` 由 `NSTextField` 承载）。不提供复制按钮/地址菜单/按发件人搜索（非目标）。
  - 不写强制前景/背景色，标签用 `secondary`，随应用主题；不读主题偏好。
- `MessageBodyView` 变更（签名新增第一个入参，内部视图，无 public 契约）：

  ```swift
  struct MessageBodyView: View {
      let header: MessageHeaderPresentation?
      let bodyPresentation: BodyPresentation
      …
  }
  ```

  - 结构：`VStack(spacing: 0) { if let header { MessageHeaderView(header: header); Divider() }; bodyContent }` —— 头部**在正文状态 switch 之外**，`.loading`/`.loaded`/`.failed` 结构上共享，不靠各分支重复渲染（R28）。
  - `.none` 两义收口：`header != nil`（已选中、正文任务未开始）归入「正在获取正文」分支（与 `.loading` 同一 `ProgressView("正在获取正文…")`）；`header == nil` 只显示占位 `ContentUnavailableView("选择一封邮件", systemImage: "envelope.open")`，并给它加 `.textSelection(.enabled)` 使占位可被 L2 探针读到（也允许用户选中文字）。
  - `case .none where header == nil` 先判占位，其余 `.none` 与 `.loading` 合并；`.failed`/`.loaded` 分支内容不变（附件条、截断 banner、`MessageWebView` 均在头部之下；远程图片入口已移出正文，见文末 2026-11-16 增量）。
- `MailboxView`：`MessageBodyView(header: viewModel.headerPresentation, bodyPresentation: viewModel.body, …)`；不再新增字段读取、不判空、不拼文案。
- 不改：`MessageWebView` 的 KVC 白底/`.aqua` 外观/CSP/禁 JS（`SCN-0010`）、附件条与下载、截断 banner、工具栏、列表、搜索、主题菜单、`UumailApp`（远程图片开关的位置由 `SCN-0013`/`REQ-0018` 的工具栏增量修改，不在本信封头增量）。
- R27 上限：主题 ≤2 行，发件人/时间各 ≤1 行，收件人/抄送各 ≤2 行；头部文本块 ≤170pt；默认窗口下限 900×560 下正文区域仍 ≥300pt 且 WebView 自身可滚动。设计探针实测长值夹具（200 字主题 + 12 收件人，无 Cc）文本块 107pt、320pt 面板下方余 204pt；含 Cc 最坏约 130pt。
- 预算：`MessageBodyView` 146 → 约 165、`MailboxView` 210 → 211、新文件约 45；单文件 ≤300、`Sources/uumail` 约 608 → 约 655。
- 验证：L2 `HeaderProbe`（离屏 `NSHostingView`；设计阶段已证 `.none`/`.loading`/`.failed` 三种正文态下的头部渲染与占位）。`T-SCN-0012-03` 的 `.loaded` 一段需实现节点把探针面板换成生产 `MessageBodyView`/`MessageBodyStyle` 并链 WebKit（`SCN-0010` 的 `AppearanceProbe` 已有离屏 WKWebView 先例）；头部在 switch 之外，`.loaded` 复用同一渲染路径，但不因此免测。探针编译命令与限制见 `task-spaces/20261116-212545/evidence/header-probe/`。`SCN-0004`/`SCN-0010` 回归覆盖正文白底与 CSP。
- 不做：可折叠/展开头部、每封布局切换、头像/发件人卡片、地址点击菜单、Bcc/Reply-To、真实 `Sent`。
- 实现（2026-11-16，T-1116-09）：`Sources/uumail/MessageHeaderView.swift`（31 行）、`MessageBodyView.swift`（161 行，新增 `header:` 与 `.none` 两义收口）、`MailboxView.swift`（211 行，接线 `viewModel.headerPresentation`）已落地；`MessageWebView` 的白底/`.aqua`/CSP/禁 JS 未改。生产路径 `HeaderProbe` 覆盖 `T-SCN-0012-01..04` 与长 Cc 夹具，51 条断言全 `PASS`、`RESULT PASS`；R27 实测：完整头 96pt/正文 216pt（320pt）、默认窗口 900×560 下 96pt/456pt、长主题+12 收件人 107pt/204pt、长 Cc 127pt/184pt、`.loaded` 正文 194pt（320pt 面板）。`./Scripts/swiftw build`、`./Scripts/swiftw test`（254 tests / 47 suites）、架构 4 门通过。证据：`task-spaces/20261116-212545/evidence/header-probe/header-probe-prod.txt`、`evidence/t1116-09-build-test-arch.txt`。

## 设计增量：工具栏归位、远程图片放行与手动置读（REQ-0018 / REQ-0019，2026-11-16，P2 已确认）

- 来源：`REQ-0018` / `SCN-0013`、`REQ-0019` / `SCN-0014`。本增量只动 `CMP-APP` 的视图/工具栏；状态与写路径在 `CMP-PRES`（见其 2026-11-16 增量）；不改 `MessageWebView` 的 CSP/禁 JS/白底，不改 `MailDomain`/`MailStore`/`Scenes`，不新增 target/依赖。
- 新文件 `Sources/uumail/MailboxToolbar.swift`（internal `ToolbarContent`，约 85 行；不新增组件/target）：

  ```swift
  struct MailboxToolbar: ToolbarContent {
      struct State: Equatable {
          var hasSelection: Bool
          var allowsRemoteContent: Bool
          var canAllowRemoteContent: Bool
          var canMarkSelectedRead: Bool
          var isSyncing: Bool
      }
      struct Actions {
          var newMessage: () -> Void
          var reply: () -> Void
          var replyAll: () -> Void
          var forward: () -> Void
          var setAllowRemoteContent: (Bool) -> Void
          var markSelectedRead: () -> Void
          var refresh: () -> Void
      }
      let state: State
      let actions: Actions
      var body: some ToolbarContent { … }
  }
  ```

  - 单一 `ToolbarItemGroup(placement: .primaryAction)`，顺序固定：新建 → 回复 → 全部回复 → 转发 → 加载远程图片 → 标记为已读 → 刷新。仍是**唯一**窗口工具栏，不新增第二条工具条/第二处入口。
  - 远程图片入口用**带状态 Button**（`photo` / 开启时 `photo.fill`，`accessibilityLabel("加载远程图片")`、`accessibilityValue("已开启"/"已关闭")`、`.help` 动态文案），`!state.canAllowRemoteContent` 时禁用；点击 `actions.setAllowRemoteContent(!state.allowsRemoteContent)`。否决 `Toggle(.button)`：功能可行（设计探针也通过），但工具栏图标模式下按压态不如实心/描边图标直观；否决菜单项：隐藏入口、与「并列」不符。
  - 「标记为已读」用 `Button`（`envelope.open`），`!state.canMarkSelectedRead` 时禁用，点击 `actions.markSelectedRead()`；只标已读，不做未读/批量/右键/快捷键。
  - 既有动作的禁用条件不变：回复/全部回复/转发依赖 `hasSelection`，刷新依赖 `!isSyncing`，新建始终可用。
  - 所有文案/图标集中在 `MailboxToolbar`；`MailboxView` 不读 `Message` 字段、不拼 CSP、不判业务。
- `MailboxView` 变更：
  - `.toolbar { MailboxToolbar(state: …, actions: …) }`；`state` 由 `viewModel` 派生（`hasSelection = selectedMessage != nil`、`allowsRemoteContent`、`canAllowRemoteContent`、`canMarkSelectedRead`、`isSyncing = sync.phase == .syncing`）。
  - `actions` 只做接线：新建/回复/全部回复/转发设置 `compose`；刷新 `Task { await viewModel.refresh() }`；远程 `viewModel.setAllowsRemoteContent($0)`；置读 `viewModel.markSelectedRead()`。
  - 状态栏：`deleteErrorText` 优先，其后显示 `markReadErrorText`（警告图标 + 单行中文），否则同步状态；不新增第二套文案。
  - 阅读区传 `MessageBodyView(…, allowRemoteContent: viewModel.allowsRemoteContent)`；不新增 `@State`。
- `MessageBodyView` 变更（internal 签名，无 public 契约）：
  - 删除 `@State private var allowRemoteContent` 与 `.loaded` 分支里的 `Toggle("加载远程图片")` 行（R33 的结构修复：视图不再拥有放行状态）。
  - 新增 `let allowRemoteContent: Bool`，只转交 `MessageWebView(html:allowRemoteContent:)`；正文状态机、附件条、截断 banner、头部均不变。`.loaded` 的远程入口行移除后，WebView 直接接在附件条/banner 之后。
  - `MessageWebView` 的 `allowRemoteContent` 入参、`lastRender` guard、KVC 白底/`.aqua`/CSP 不变。
- 尺寸：`MailboxView` 211 → 约 190（工具栏移出约 35 行、新增接线约 15 行）、`MessageBodyView` 161 → 约 150、新 `MailboxToolbar` 约 85；单文件 ≤300，`Sources/uumail` 655 → 约 710。
- 验证：L2 工具栏探针（设计阶段已证：生产形状 `MailboxToolbar` + 离屏 `NSHostingController`，`NSToolbar.items` 可读 label/visible，`window.sendEvent` 可驱动/禁用，33 条断言 PASS；证据 `task-spaces/20261116-223645/evidence/toolbar-probe/`）。实现时把探针源换成生产 `Sources/uumail/MailboxToolbar.swift` 复跑 `RemoteContentToolbarProbe`/`ManualMarkReadProbe`（覆盖 `T-SCN-0013-01..04`/`T-SCN-0014-01..04` 的入口部分）；正文侧用 `RemoteContentBodyProbe` 编译生产 `MessageBodyView`/`MessageWebView`/`MessageBodyStyle`。不新增 `uumail` 测试 target。
- 不改：工具栏以外的列表/侧栏/搜索/主题菜单/撰写/配置；`MessageWebView` 的白底/CSP/禁 JS；附件条/头部/banner；`UumailApp` 窗口下限（仍 900×560）。
- P2 确认项：D4 工具栏形态/顺序；D5 远程入口用带状态 Button 而非 Toggle/菜单；D6 不可用时禁用而非隐藏；D7 L2 载体；D8 是否抽 `MailboxToolbar` 文件。详见 `task-spaces/20261116-223645/design.md` §8.2；确认记录见 `doc/history/decisions/2026-11-16-remote-toolbar-mark-read.md`（`frozen`，含 N6：`MailboxToolbar` 为 `CMP-APP` 内部文件、非新组件）。
- 实现（2026-11-16，T-1116-13）：新 `Sources/uumail/MailboxToolbar.swift`（75 行，7 个紧凑图标入口，固定顺序）；`MailboxView.swift`（202 行）接入 `MailboxToolbar`、状态栏错误与阅读区放行参数；`MessageBodyView.swift`（155 行）删除正文 `@State` 与独立开关行，改为只读 `Bool`；`MessageWebView` 的 CSP/禁 JS/白底/`lastRender` 未改。`./Scripts/swiftw build` 通过，`./Scripts/swiftw test` 264 tests / 49 suites 通过，架构 4 门通过。L2 探针编译生产 `MailboxToolbar.swift`：`RemoteContentToolbarProbe` 28 PASS/0 FAIL、`ManualMarkReadProbe` 5 PASS/0 FAIL；`RemoteContentBodyProbe` 编译生产 `MessageBodyView`/`MessageWebView`/`MessageBodyStyle`，9 PASS/0 FAIL（正文无独立开关行、头部在开关前后保留、Bool→CSP 两档重载、CSP 精确值）。证据：`task-spaces/20261116-223645/evidence/t1116-13-build-test-arch.txt`、`evidence/t1116-13-toolbar/`。

## 设计增量：界面与阅读字体大小（REQ-0020 / SCN-0015，2026-11-17，P2 默认确认）

- 来源：`REQ-0020`（`accepted`）/ `SCN-0015`；完整论证、候选与否决、175/225% 预算与 L2 探针见 `task-spaces/20261117-071134/design.md` 与 `evidence/font-size-probe/round2/`；默认确认记录见 `doc/history/decisions/2026-11-17-font-size.md` 与第 2 轮 `2026-11-17-font-size-round2.md`（`frozen`，**默认确认（未经人工）**）。
- **第 2 轮修正（2026-11-17，评审 fail 后）**：① 100% 不再装根 `.font`，原来源继承默认字体的点改用 `scaledInheritedFont`（100% 不加修饰；实测装根 `.font` 会把两行默认文本 32.0→31.5pt）；② 225% 只 cap 头部会只剩 147.5pt 视口，改为 175/225% cap 整个元数据区（头部+附件条+banner）220pt，480 高实测 259pt；③ 根级数据库错误页纳入 `EmptyState`；④ 生产头部 100% 实测 159.5pt（第 1 轮 158.5pt 是 fixture/补丁副本拟合值）；⑤ 225% 几何来自“生产源 + 设计 diff 副本”，生产源复跑标为实现期 L2。
- 本增量只动 `CMP-APP` 与 `CMP-PRES`；不改 `MailDomain`/`MailStore`/`Scenes`/`MailGateway`/`Composition` 契约、schema、协议、依赖或 target；不改 `Package.swift`。
- 新文件（均为 `CMP-APP` 内部文件，不新增组件/target）：
  - `Sources/uumail/FontSizeStyle.swift`（约 110 行）：`EnvironmentValues.fontSizePreference`、`View.scaledFont(_:)`（原 `.font(style)` 点）、`View.scaledInheritedFont(_:)`（原默认字体点；100% 不加任何字体修饰，>100% 才加）、`FontSizePreference.font(for:)`。100% 返回原语义字体（`.caption`/`.body`/`.headline`/…），其余档用 `NSFont.preferredFont(forTextStyle:)` 的 descriptor 缩放 point size，保持家族与字重；根 **仅 >100%** 写 `.environment(\.font, fontSize.font(for: .body))` 覆盖默认文本、`TextField` 与 `Form` 输入，100% 不装（否则默认行高漂移）。
  - `Sources/uumail/FontSizeCommands.swift`（约 35 行）：`CommandGroup(after: .sidebar)` + `Picker("字体大小", selection:)`，五项 `100%/120%/145%/175%/225%`；binding setter `guard newValue != fontSize` 保证重复选择 no-op，变化时先改 binding 再 `store.save`；只写本地偏好。
  - `Sources/uumail/EmptyState.swift`（约 110 行）：`ContentUnavailableView` 与字符串标题 `Button` 不响应环境字体（本机实测 100%→225% 尺寸比 1.00）。100% 分支保留原 `ContentUnavailableView` 的初始化参数与字体修饰（逐点相等；description 为默认 body 时不装 `.font`，caption 时保留 `.font(.caption)`）；>100% 分支用 `Image + 缩放字体` 自绘（icon `52×scale`、**title 按实测 26pt 基 × scale（不是 `.title2` 的 17pt 基，否则 120% 会小于 100%）**、description 按原样式 body 13/caption 10 缩放、单一 action 的 label 缩放），支持 selectable。**title 基值需在最低 macOS 14 上复测 `ContentUnavailableView` 标题（本机 macOS 26 为 26pt），不能把 26 当跨系统常量；120% 实际比例必须 1.2**。100%→120% 会切换这个无状态占位子树的视图类型；不重置选中/滚动/搜索/草稿（显式例外，见 design.md §5.2）。`UumailApp` 根级数据库错误页、`MailboxView` 空态/同步中、`MessageBodyView` 选择/加载/失败态都走它。
- `UumailApp`：`@State fontSize: FontSizePreference` + `private let fontStore: FontSizePreferenceStore`；`init` 先构造 store 再赋 `self.fontStore`、`_fontSize = State(initialValue: store.load())`、`_composition`；根 Group 加 `.environment(\.fontSizePreference, fontSize)`，**仅 `fontSize != .percent100` 时再加 `.environment(\.font, fontSize.font(for: .body))`**；`composition == nil` 的根级数据库错误页改 `EmptyState(title: "无法打开本地数据库", systemImage: "externaldrive.badge.xmark", description: "请检查 ~/Library/Application Support/uumail 的读写权限。")`；`.commands { ThemeCommands(...); FontSizeCommands(fontSize: $fontSize, store: fontStore) }`（声明顺序保证 View 菜单「主题 → 字体大小」相邻；L2 实测）。
- 界面文字覆盖（逐项）：
  - `MailboxView`：侧栏文件夹与列表主题显式 `.scaledInheritedFont(.body)`（原来源继承默认字体；100% 不加修饰、保持原行高，>100% 缩放；不依赖 `List` 是否继承环境字体）；发件人/日期/状态栏 `.font(.caption)` 改 `.scaledFont(.caption)`；状态栏计数 `.layoutPriority(1)`（225% 下同步/错误文案尾部截断，「N 封」保可见）；列表空态换 `EmptyState`。
  - `MessageHeaderView`：主题 `.font(.headline)` 改 `.scaledFont(.headline)`；标签/值 `.scaledInheritedFont(.body)`（原来源继承默认字体；100% 不加修饰，避免 32.0→31.5pt 行高漂移；实测 100% 生产头部 159.5pt、225% 312.5pt）；标签列宽 `44` 改 `44 × preference.scaleFactor`（100% 仍 44；225% 99，值列起点 115，实测不重叠）；行序/行数/`lineLimit`/`textSelection` 不变。
  - `MessageBodyView`：失败描述/截断 banner `.font(.caption)` 改 `.scaledFont(.caption)`；附件按钮 label 用 `scaledInheritedFont(.body)`（100% 无修饰）；空态/占位/失败态换 `EmptyState`；**175%/225%** 把「头部 + 附件条 + banner」整体包 `ScrollView` 并 `.frame(height: 220)`，100–145% 保持生产嵌套（不包 cap；实测 100% 视口 273pt/480 高、与生产逐点相等；120% 242.5、145% 205、175/225 259）；banner retry 按钮 100% 保留字符串标题（自定义 label 会差 1pt）、>100% 显式缩放 label；向 `MessageWebView` 传 `fontSize`。否决第 1 轮 `ViewThatFits` 只 cap 头部：真实栈里 100% 也会选中 ScrollView（`CapDiag.txt`），且 225% 视口只有 147.5pt。
  - `ComposeView`：`TextEditor` 用 `scaledInheritedFont(.body)`（100% 无修饰），状态文本 `.scaledFont(.caption)`；「存草稿」「发送」按钮 100% 保留字符串标题、>100% 显式缩放 label（环境字体到不了按钮字符串标题，实测；字符串/自定义 label 的 100% 高度差 1pt，故按档位分支）。
  - `AccountSetupView`：说明/错误 `.font(.caption)` 改 `.scaledFont(.caption)`；「连接」按钮 100% 保留字符串标题、>100% 显式缩放 label。
  - `MailboxToolbar`：**不改**；系统工具栏不随字号缩放，7 个动作/顺序/禁用不变；L2 实测 900×560 下 100% 与 225% 均 7 项可见（无溢出），若未来溢出由系统 overflow menu 承接，动作仍可达。
  - 系统 chrome：窗口标题栏、菜单栏、搜索框、系统对话框/文件面板/tooltip 不缩放；登记为系统能力边界，不在本景断言。
- 正文（`MessageWebView`）：
  - 新增 `let fontSize: FontSizePreference`；`makeNSView` 创建 WebView 时先设一次 `pageZoom`（避免启动首帧 1.0 跳到目标档），`updateNSView` 在 `lastRender` guard **之外**执行 `if webView.pageZoom != CGFloat(fontSize.scale) { webView.pageZoom = CGFloat(fontSize.scale) }`。
  - `lastRender` 键仍为 `"\(allowRemoteContent)|\(html)"`，**不纳入字号**（纳入会触发 `loadHTMLString` 重载，违反即时性）。
  - `pageZoom` 是整页渲染缩放：默认 13px 文本、作者显式 `px`、图片、表格一起按真实渲染比例缩放；`MessageBodyStyle.baseCSS`（100% 13px/1.55）、白底、CSP、禁 JS、`.aqua` 全部不改。代价：固定宽度大表在 225% 下可能需要横向滚动；图片随页面放大，`max-width:100%` 仍生效。
  - 实测：1.0→2.25 导航增量 0；作者 20px 元素渲染高度 40→90 设备像素（2.250×）、默认 13px 26→59（2.269×）；滚动 200 保持；深色窗口下四角仍白；五档来回扫无重载；切换到新邮件时只加载一次、`pageZoom` 保持 2.25。证据 `task-spaces/20261117-071134/evidence/font-size-probe/WebProbe.txt`。
- 175%/225% 预算（默认 900×560；480pt 为保守可用高）：元数据区（头部+附件条+banner）cap 220pt；100% 生产头部 159.5pt、225% 312.5pt；标签宽 99pt；**正文视口 480 高实测 259pt（≥200 下限，达 260 目标）**；120%/145% 不 cap（242.5/205pt，145 仍 ≥200）；560 高下 225% 视口 339pt；工具栏 7 动作可见、状态栏计数保宽、列表行高由字体撑开、撰写/配置表单可滚动；不新增窗口最小尺寸（仍 900×560）。
- 尺寸：`UumailApp` 57→约 69、`MailboxView` 202→约 207、`MessageHeaderView` 31→约 35、`MessageBodyView` 155→约 175、`ComposeView` 45→约 48、`AccountSetupView` 48→约 50、新 `FontSizeStyle`/`FontSizeCommands`/`EmptyState` 约 255；`Sources/uumail` 715→约 900；单文件仍 ≤300，`CMP-APP` 尺寸预算成立。
- 验证（L2，不新增 `uumail` 测试 target；见 `SCN-0015`）：
  - `FontSizeProbe`：真实 SwiftUI App + 生产 `ThemeCommands`/`FontSizeCommands`（父菜单打开后读五项与勾选，R26）；`NSHostingView` + `.textSelection` 读 `NSTextField.font`（100% 恒等/225% 29.25pt）；**未修改生产 `MessageHeaderView` 100% 基线**（159.5pt/44pt 列）与设计 diff 副本 225%（312.5pt、99pt 列、值列起点 115、不重叠；生产源复跑标实现期 L2）；**完整 `MessageBodyView`**（header+附件+banner+divider+真实 `WKWebView`）在 320×480/560 的实测视口（100% 273、120% 242.5、145% 205、175/225% 259；只 cap 头部 A 变体 225% 147.5）；`EmptyState`/按钮/根错误页 100/120/225 字体与按钮 fitting（`EmptyState` 为新增文件，设计期用原型，实现期换生产文件复跑）；离屏 `WKWebView` 快照 + 导航计数（pageZoom 不重载）；生产 `MailboxToolbar` + `NSToolbar.visibleItems`（7 动作）。
  - 非 `textSelection` 文本不在 AppKit 层暴露 `NSTextField`：用「生产同一 `scaledFont`/根环境 + 探针宿主逐样式测量 + 源码覆盖审计（每个 `.font(` 调用点要么缩放、要么在系统 chrome 清单内）」组合；不把 L1 映射冒充 L2。若实现期 seam 失效，由场景卡声明 L3，不静默降级。
  - 既有回归：`SCN-0010`/`SCN-0011`/`SCN-0012`/`SCN-0013`/`SCN-0014` 在 100% 不退化；`SCN-0001`/`SCN-0006`/`SCN-0004` 只做外观/输入/不触网回归。
- 不改：`MailboxToolbar` 的 7 个动作与顺序、主题菜单三项、`MessageBodyStyle` 的 100% `baseCSS`、`MessageWebView` 的 CSP/白底/禁 JS、`lastRender` 键、窗口下限、`MailDomain`/`MailStore`/`Scenes` 契约、schema/协议/依赖/target。
- P2 默认确认项（未经人工）：D1 界面机制；D2 正文 pageZoom；D3 偏好形态；D4 菜单/相邻；D5 100% 恒等；D6 225% 预算；D7 空态/按钮；D8 测试载体；D9 回归口径；D10 级别。详见 `task-spaces/20261117-071134/design.md` §10.2；确认记录见 `doc/history/decisions/2026-11-17-font-size.md`。
- 实现状态：**未实现**（本节点只落设计）。实现后按 `SCN-0015` 的 `T-SCN-0015-01..04` 验证；不翻转 `verified`/`delivered`。

## 设计增量：HTML 撰写 sheet、格式栏、取消与等宽（REQ-0021，2026-11-17）

- `ComposeView`（172 行）重写：标题（新邮件/回复/全部回复/转发）+ 右上 `xmark`；收件人/抄送/主题 `Form`；`ComposeFormatBar`；`ComposeEditor`；底部「取消 / 状态 / 存草稿 / 发送」。发送/存草稿/取消前先 `await editor.capture()` 并 `setEditorHTML`；取消用 `hasEdits` 决定直接关闭或 `confirmationDialog("放弃这封邮件？")`；`.interactiveDismissDisabled()`；成功发送/存草稿后 `onClose()`。按钮沿用「100% 字符串标题、>100% 显式缩放 label」的字号基线规则。
- `ComposeEditor`（173 行）/`ComposeEditorHandle`：WKWebView、`allowsContentJavaScript = true`、非持久数据仓库、白底、`pageZoom = fontSize.scale`；`didFinish` 把光标放到 `uumail-reply-start` 并滚到顶部，再 `outerHTML` → `ComposeDocument.emailHTML(fromEditorDocument:)` 作为 `editorDidLoad` 基线；`capture()` 用 continuation 回读；`perform(_:)` 先让 WebView 成为 first responder 再注入 `ComposeFormatCommand`（`execCommand` + Range 字号）。`updateNSView` 只更新 `pageZoom`，不重载文档。
- `ComposeFormatBar`（75 行）：加粗/斜体/下划线/删除线、字号（13/16/20/24pt）、左/中/右对齐、项目符号/编号、清除格式；按钮 `.focusable(false)` 保留 WebView 选区；横向 ScrollView 适配窄 sheet。
- `MailboxView`：`@State readingPaneSize`；detail 列 `GeometryReader` 的 `onAppear`/`onChange` 更新；`ComposeView(preferredWidth:preferredHeight:)` 宽 = `max(detailWidth, 480)`、高 = `460…820`，sheet 居中。阅读区/窗口最小尺寸不变。
- 安全/不变：编辑器 CSP 无 `script-src`，发件人脚本不执行；格式命令由 app 注入；发送内容不含编辑器 CSP/样式/contenteditable；远程图片沿用阅读区开关。
- 测试：`PresentationTests/ComposeDocumentTests` + `ComposeViewModelTests`（L1）；L2 真实 App 冒烟：sheet `1441×820`、detail `1440×987`（等宽）、「取消」/格式栏/抬头/全宽正文可见（`history/works/2026-11-17-html-reply/evidence/ui-smoke.md`）；WebKit 探针：contenteditable/`execCommand`/outerHTML/CSP（`evidence/webkit-smoke.txt`）。
- 尺寸：`Sources/uumail` 新增两个文件 248 行，`ComposeView` 172、`ComposeEditor` 173、`ComposeFormatBar` 75，单文件均 ≤300；无新增 target/依赖。

## 设计增量：收件人输入联想控件与候选浮层（REQ-0022 / SCN-0017，2026-11-18，P1 默认确认、未实现）

- 新增 internal `Sources/uumail/RecipientTextField.swift`：
  - `RecipientTextField`：`NSViewRepresentable`，包一个 **字段-only** 的 `NSTextField`（标签由 Form 的 `LabeledContent` 提供）；绑定 `to`/`cc`。外观按现状 SwiftUI `TextField` 的 AppKit 载体实测拟合（`task-spaces/20261118-082503/evidence/design-probe/{textfield-probe,field-probe}.txt`）：`isBordered=false`、`drawsBackground=true`、`backgroundColor=.textBackgroundColor`、字体 13pt、文本左右 inset 4pt、100% 行高 24pt；随 `fontSizePreference` 按 `scaleFactor` 设置 `NSFont` 与行高（100% 恰为 24pt），保留焦点环。
  - `updateNSView` 只在文本不同时写回；`currentEditor()?.hasMarkedText() == true` 时跳过写回，避免打断输入法组合态。外部写入（选中补全）后，若字段仍是 first responder，把 field editor 光标设到文本末尾；否则只更新 `stringValue`。
  - 回调：`onFocusChange(Bool)`、`onCaretChange(atEnd: Bool)`（由 `currentEditor()?.selectedRange` 判断；仅有零长度光标在末尾才为 `true`，选区一律 `false`）、`onCommand(RecipientCommand) -> Bool`，命令含 `.moveUp`/`.moveDown`/`.commit`/`.dismiss`。
  - `control(_:textView:doCommandBy:)`：`moveUp:`/`moveDown:` → `.moveUp`/`.moveDown`；`insertNewline:`/`insertTab:` → `.commit`，但 `textView.hasMarkedText()` 时返回 `false` 放行给输入法；`cancelOperation:`：`hasMarkedText()` 且有候选时消费 `.dismiss`（只收候选、不让输入法取消组合），无候选时返回 `false`；非组合态有候选时消费 `.dismiss`，否则 `false`；其他命令返回 `false`。
  - `RecipientSuggestionList`：SwiftUI 行列表；每行 `Text(name)` + `Text(address)`（secondary）或只 `Text(address)`；`lineLimit(1)`、地址 `truncationMode(.middle)`，整行 `.help(name.map { "\($0) <\($1)>" } ?? address)` 供悬停查看完整地址；`Button` 点击选中；hover 只变底色、不改 VM 高亮；`.accessibilityElement(children: .ignore)` + `accessibilityLabel(name.map { "\($0), \($1)" } ?? address)`；容器 `.accessibilityLabel("收件人建议")`；行 `Button` 加 `.focusable(false)`、`.buttonStyle(.plain)`。
- 新增 internal `Sources/uumail/RecipientForm.swift`（方案设计复核从 `ComposeView.swift` 拆出，使 L2 探针只编译这一个生产文件 + `RecipientTextField.swift`，不必拉整棵 `ComposeView` 依赖树）：
  - `ComposeRecipientForm`：`Form` 内用 `LabeledContent("收件人")`/`LabeledContent("抄送")` 承载字段；`LabeledContent` 的标签列与现状 `TextField("收件人", …)` 对齐（设计探针实测字段起点同为 x=59），`@ViewBuilder` 承接主题行；保留既有 12pt padding 与行间距。
  - 每个字段用 `GeometryReader` 把 frame 写入 `PreferenceKey`（坐标空间为 `ComposeRecipientForm`）；候选浮层用 **`.overlay(alignment: .topLeading)`** 挂在 `Form` 上，**不用 ZStack**：设计探针实测 ZStack 会把 200pt 浮层计入布局并把后续内容下推 60pt，`.overlay` 不参与布局、后续内容位置不变（`task-spaces/20261118-082503/evidence/design-probe/overlay-probe.txt`）。
  - 浮层按**当前聚焦字段**的 `minX/maxY+4` 定位、宽度=字段宽；`ComposeView` 给 `ComposeRecipientForm` 在 VStack 中 `.zIndex(10)`，确保浮层绘制在 Divider/格式栏/编辑器之上，不被后续兄弟覆盖。
  - 浮层高度取 `min(内容高度, 240×scaleFactor, 字段下方可用高度)`，超出滚动；225% 不撑破 sheet、不遮挡当前字段；跟随五档字号与浅/深色语义色。
  - `@State` 保存当前聚焦字段与 `caretAtEnd`；`.onChange(of: viewModel.to/cc)` 只在对应字段聚焦时调 `viewModel.recipientTextChanged(...)`；焦点/光标/命令转发到 VM；失焦/切字段调 `recipientFocusLost()`。
  - 不改变 sheet 宽度计算、格式栏、HTML 编辑器、取消确认、发送/存草稿按钮与快捷键。
- 交互：默认不高亮；`↓` 第一次高亮 0、`↑/↓` 夹取；`Return`/`Tab` 只在 VM `highlightedSuggestion != nil` 时提交；`Esc` 收起；点击行直接选中；输入法组合态不提交；失焦/切字段/关 sheet 收起；不残留浮层。点击候选行时若字段先失焦，视图用 `suggestionClickInFlight` 守卫把清空延后到下一 runloop，点击仍用原字段 index 完成选中，随后 `makeFirstResponder` 把焦点还给原字段；L2 必测该顺序。
- 100% 基线：字段 24pt 高、13pt 字、4pt 文本 inset，候选浮层关闭时表单总高不变；L2 允许 ±0.5pt 渲染误差，超出即红。
- 可访问性：字段的「收件人」「抄送」标签由 `LabeledContent` 提供；候选行有完整「名字, 地址」标签；键盘可达；不抢焦点。
- 尺寸：`RecipientTextField.swift` 约 200 行、`RecipientForm.swift` 约 80 行、`ComposeView` 约 180 行；单文件 ≤300；不新增 target/依赖。
- 验证：`ComposeAutocompleteProbe`（L2，生产 `RecipientTextField.swift` + `RecipientForm.swift`，链接已构建的 `Presentation`/`Scenes`/`MailDomain`/`MailStore`/`Outbox`，离屏 `NSHostingView`/`NSWindow`）覆盖 `T-SCN-0017-03`：浮层位置/不撑高、100% 字段 24pt、人名+邮箱、无名字回退、点击/失焦顺序、方向键+Return、IME 组合态 Return/Esc、深色/225% 语义色与 frame；证据入 `task-spaces/<run>/evidence/compose-autocomplete-probe/`。不做 L3 截图/OCR、不做 L4 AX。
- 方案设计复核 A1–A6（浮层 overlay、`RecipientForm.swift` 拆分、字段外观/标签、点击/IME、测试 seam）见 `history/decisions/2026-11-18-recipient-autocomplete-design-addendum.md`（默认确认，未经人工）。

## 设计增量：候选行显示名的可读宽度（REQ-0023 / SCN-0017，2026-11-19，P3 默认确认）

- 来源：`REQ-0023`（`quality`，`accepted`）/ `SCN-0017`（`designed`）；第 2 轮按 `review.md` B1–B3 修订。完整论证、现状归因、方案族与设计期 L2 实测见 `task-spaces/20261119-164437/design2.md` 与 `evidence/name-width-probe/round2/`。
- 现状归因（L2 实测，第 1 轮不变）：字段宽 = sheet 宽 − 71（480→409、700→629、900→829），浮层宽 `max(字段宽, 200)` 恒等于字段宽、右侧已到 sheet 内容右缘；行宽跟随浮层宽。`SuggestionRowView.layout` 的名字列 `min(固有宽, 可用宽 × 0.45)` 是唯一起作用的约束：100%×480 下 15 字组织名只显示 13.6/14.9 字；145%/175%/225%×480 分别只剩 9.4/7.8/5.8 字（225% 即「周…」级）。
- 修改：在 `Sources/uumail/RecipientTextField.swift` 增加 internal `RecipientSuggestionLayout`，常量 `horizontalInset=8`、`gap=6`、`preferredAddressFloor=130`、`representativeNameCharacters=15`；`available = max(0, rowWidth-16)`；有名字 → `targetNameWidth = 15×名字字号`、`addressMinimum = ceil(width(地址首字符 + "…@" + 域名首字符))`、`addressFloor = max(addressMinimum, min(130, available-6-targetNameWidth))`、`name = min(max(0, nameIntrinsic), max(0, available-6-addressFloor))`、`address = max(0, available-6-name)`；无名字 → `name=0`、`address=available`。`layout()` 同时使用返回的 `name` 与 `address`（不再另算地址宽），并用 `shortenedAddress` 写回邮箱显示串。130/`addressMinimum` 与 15 都是列宽分配参数/代表样例，不写成「超 N 必截断」的契约。
- 地址显示串（新增 internal `shortenedAddress`）：完整地址放不下时，按「本地前缀 + `…` + `@` + 域名前缀」选可见字符最多的组合，保证 `@` 与两侧各至少 1 字符；完整地址保留在 `fullAddress`，`.help`/无障碍/选中仍用完整地址；结果按 `(地址, 宽, 字号)` 缓存。无名字行不缩短。
- 不改：浮层宽/锚点/高度 cap（`panelSize`）、`RecipientSuggestionRow.sizeThatFits`、行高 24×scale、sheet 宽高、`.help`、无障碍标签、字体/语义色、候选数据/匹配/排序/上限/插入、键盘/IME/点击/失焦；不改 `RecipientForm.swift`。`nameLabel`/`addressLabel` 从 private 改 internal 仅用于 L2 按身份取值，不新增 public。
- 设计候选实测（第 2 轮，生产源 + 设计 diff 副本；实现期换生产源复跑）：100%×480 的 15 字名 `176.8→193.5`（13.6→14.9 字，完整）、邮箱 193.5（完整 115.5）；700/900/1200 的 15 字名不变（原本完整）；40 字名 100%×480 `176.8→257`、邮箱 130（`long-name@corp.test` 127.2 完整）；145%×480 名字 `176.8→280.5`（9.4→14.9 字，看全）、邮箱 106.5（显示 `hr-…@corp.t`，`@` 两侧可见）；**175%×480 名字 `176.8→325`（7.8→14.9 字，完整，不再降级）**、邮箱 62（`h…@c`）；225%×480 名字 `169.2→298`（5.8→10.7 字）、邮箱 72（`h…@c`）、行高 54。无名字行名字 hidden/宽 0、邮箱仍占满可用宽（393）。
- 尺寸：`RecipientTextField.swift` 165 → 约 253 行，`RecipientTextField+AppKit.swift` 265 → 约 293 行（均 ≤300）；不新增文件/target/依赖；`Package.swift`、schema、`MailStore`、发送链路不动。
- 验证：`T-SCN-0017-03`（L2）新增 `.nameWidthsAtMinAndDefaultSheet`/`.longNameKeepsAddressFloor`/`.nameWidthsAt175Percent`/`.nameWidthsAt225Percent`/`.addressKeepsAtVisibleAtZoom`/`.noNameRowUsesLabelIdentity`/`.columnWidthsEdgeClamp`；断言邮箱显示串含 `@` 两侧且 `显示串宽 ≤ 帧宽 + 0.5`，完整地址仍在行上；证据入 `task-spaces/<run>/evidence/compose-autocomplete-probe/`。`T-SCN-0017-04` 不新增。
- 定级与确认：**P3**（单组件内部布局/显示规则、无 public 契约/schema/依赖/热路径失败语义变化）；默认确认 D1–D6（无人值守自动确认，**未经人工**；依据 `REQ-0023` D1–D4 与实测，见 `task-spaces/20261119-164437/design2.md` §6.2；130/`addressMinimum` 与 15 字目标是参数，不是契约）。回退：删除本增量与 helper、把「名字优先、邮箱 `@` 保底」还原为 `min(名字固有宽, 可用宽 × 0.45)` 与 `byTruncatingMiddle`；无数据/契约迁移。若评审否决 A 族（列宽重分配），按 `design2.md` §3 的 B/C/D 族重选，不复用本节数值。
- 实现进度（2026-11-19，`T-1119-01`）：`RecipientSuggestionLayout`（列宽分配 + 地址显式缩短）与 `SuggestionRowView.layout()` 接线已落生产源（`RecipientTextField.swift` 253 行、`RecipientTextField+AppKit.swift` 293 行，未新增文件/target/依赖）。生产源 `ComposeAutocompleteProbe` 覆盖 `T-SCN-0017-03` 的 11 个可执行 ID，147 CHECK / 0 FAIL；实测 100%×480/700/900、145%/175%/225%×480、无名字行、40 字名 130pt、`@` 两侧与 `fullAddress` 保留与设计预期一致（证据 `task-spaces/20261119-164437/evidence/compose-autocomplete-probe/`）。性能（N4，`bench.txt`）：18 字符地址首次约 0.68ms/行（与设计期 0.6ms 同量级），39/58 字符约 4.2/10.9ms；布局重复调用命中 `(地址, 宽, 字号)` 缓存约 10µs/次，热路径为**有界 O(L²) + 缓存**。实现未改 `SCN-0017`/`REQ-0023` 状态位。

## 设计增量：远程图片实际加载的运行载体 ATS 例外（REQ-0024 / SCN-0018，2026-11-19，P2 已人工确认）

- 来源：`REQ-0024`（`quality`，`accepted`）/ 新场景 `SCN-0018`（`mail/read/remote-image-load`，`designed`）。完整论证、方案族与设计期 L2 矩阵见 `task-spaces/20261119-213812/design.md` 与 `evidence/remote-image-probe/`。
- 现状归因（L2，生产 `MessageWebView` + `MessageBodyStyle` + 受控 http 源 + 三种 carrier 对照）：开关/CSP 链路正常（放行档 `img-src … http:`、阻断档 0 请求），缺口在传输层。带 bundle `Info.plist` 且无 ATS 例外的载体里，明文 http 图片**一次也不出网**（受控服务端 0 命中、`img.naturalWidth=0`）；同一二进制把 bundle plist 换成含 `NSAllowsArbitraryLoadsInWebContent=true` 后，请求到达、图片解码渲染（品红像素 4096）。`127.0.0.1`/`localhost` 被 ATS 豁免，不能用来判 ATS（无 ATS 载体下 `127.0.0.1` 放行、非本地主机名 0 命中）；裸可执行（`swift run` 形状）无 bundle plist、无 ATS 域策略，本来即可加载。
- 修改：
  - 新增受版本管理的 `Resources/Info.plist`（与现 `make-app.sh` heredoc 逐键一致），增加 `<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>`；**不含** `NSAllowsArbitraryLoads`、`NSExceptionDomains`。
  - `Scripts/make-app.sh` 的 heredoc 改为 `cp Resources/Info.plist "$APP/Contents/Info.plist"`；release 构建、图标、ad-hoc 签名、`build-info.txt`、`dist` 路径不变。
  - `MessageWebView`/`MessageBodyStyle`/`MessageBodyView`/`MailboxViewModel`/`ComposeEditor` **零改动**：`loadHTMLString(_, baseURL: nil)`、CSP 两档、禁 JS、白底、`lastRender` guard 原样。
- 安全面（已实测）：ATS 例外只放宽 **WKWebView 内容**（正文 + 撰写编辑器）；两处图片仍由同一 `allowRemoteContent` 放行档 CSP 门控（默认/关闭 0 请求）；URLSession（EAS/附件）明文 http 在加键后**仍被 ATS 拒绝**（`urlsession-matrix.txt`），应用网络路径无变化。全局 `NSAllowsArbitraryLoads` 会放行 URLSession，已否决。
- `swift run`：无 bundle `Info.plist` → 无 ATS 域策略，明文 http 图片本来即可加载；本次不为它加任何 shim，只把结论写进本规格与 `SCN-0018`。发布/开发统一用 `./Scripts/make-app.sh && open dist/uumail.app`。
- 尺寸/预算：`Sources/uumail` 行数零变化（无单文件 ≤300 风险）；新增资源文件约 35 行；不新增 target/依赖/第三方库；`Package.swift`、schema、`MailStore`、`CMP-PRES`/`CMP-DOMAIN`/`Scenes` 契约不动。
- 验证：`SCN-0018` 的 `T-SCN-0018-01`（L2 正例，探针 `.app` 的 plist = `Resources/Info.plist` 原样副本 + 非本地主机名 + 受控 http 源；含无 ATS 负控制、`data:` 正控制）、`T-SCN-0018-02`（L1 键断言 + L2 URLSession 仍受限）、`T-SCN-0018-03`（L1 脚本接线 + dist plist/build-info 一致；L2 裸可执行正例）。回归 `SCN-0013-01..04`、`SCN-0004`/`SCN-0010`/`SCN-0012`/`SCN-0015`/`SCN-0016`。A5 真实样本冒烟为发布前/人工项（脱敏计数，不记录 URL/主机/主题）。
- 定级与确认：**P2**（交付载体/安全策略单点、无模块/契约/schema/热路径变化）。放宽 ATS 属安全策略变更，按 `REQ-0024` D4 与 `auto-confirm` §3 已取得**人工确认**（人工确认：是否批准加 `NSAllowsArbitraryLoadsInWebContent=true`；决定 pass；意见「批准：仅加 `NSAllowsArbitraryLoadsInWebContent=true`（推荐）」；2026-11-19，`doc/history/decisions/2026-11-19-remote-image-ats.md`）。回退：删除 `NSAppTransportSecurity` 字典、`make-app.sh` 恢复内联 heredoc（或保留资源文件但去键）；无数据/契约迁移；回退后 `SCN-0018` 正例必然失败（这正是要暴露的载体缺口）。
- 实现进度：已实现（2026-11-19，`T-1119-04`）：新增 `Resources/Info.plist`（与历史 `make-app.sh` heredoc 逐键一致，另加 `NSAppTransportSecurity/NSAllowsArbitraryLoadsInWebContent=true`，不含 `NSAllowsArbitraryLoads`/`NSExceptionDomains`），`Scripts/make-app.sh` 改为 `cp "Resources/Info.plist"`；`plutil` 键断言、`grep` 脚本接线断言、`./Scripts/swiftw build` 与架构 4 门通过。按任务卡时序，实现 commit 后运行 `./Scripts/make-app.sh` 重建 `dist`，并断言 `cmp` 字节一致、`build-info` commit = HEAD（命令输出见 `task-spaces/20261119-213812/evidence/carrier/` 与 `dev.md`）。


## 设计增量：内联图片渲染串透传（REQ-0025 / SCN-0019，2026-11-20）

- 来源：`REQ-0025`（`feature`，`accepted`）/ 新场景 `SCN-0019`（`designed`）。完整论证见 `task-spaces/20261120-111818/design.md`。
- 修改：
  - `Sources/uumail/MessageBodyView.swift#MessageBodyView` 新增 `let inlineImageHTML: String?`；`.loaded` 分支（`natural` 与 `capped` 两处）用 `inlineImageHTML ?? html` 交给既有 `MessageWebView`。
  - `Sources/uumail/MailboxView.swift` 把 `viewModel.inlineImageHTML` 传入 `MessageBodyView`。
  - `MessageWebView` / `MessageBodyStyle` **零改动**：CSP 两档值、`sanitized`、禁 JS、`.nonPersistent()`、白底、`lastRender` guard、`loadHTMLString(_, baseURL: nil)` 全部原样；`data:` 本就在两档 `img-src` 中。
- 不变量：视图不解析 `cid:`、不取负载、不判断附件；只消费视图模型算好的渲染串。`MessageBodyView` 既有信封头/附件条/截断 banner/字号分支不变。
- 视觉：`lastRender` 由 `"\(allowRemoteContent)|\(html)"` 自然包含渲染串；图片任务到达时重载一次；不逐图增量重载。
- 尺寸：`MessageBodyView` 259、`MailboxView` 219（2026-11-20 实测；本增量 +3/+1 已落地）；均 ≤300。
- 测试：L2 探针编译生产 `MessageBodyView`/`MessageBodyStyle` + 生产改写函数，断言 `img.naturalWidth>0`、快照像素、0 请求；视图层不做 L1 单测。
- 定级/确认：**P2**（跨 `Presentation`→视图接线，无 public 契约/schema/依赖变更）。D3/D8 为默认确认（未经人工），见 `task-spaces/20261120-111818/design2.md` §8；所消费的 `MailboxViewModel.inlineImageHTML` 公开面已**人工确认 pass（A，2026-11-20）**，记录见 `doc/history/decisions/2026-11-20-inline-image-render-public-surface.md`。
- 实现进度（2026-11-20，`T-1120-04`）：`MessageBodyView` 新增 internal `inlineImageHTML` 入参，`.loaded` 的 `natural`/`capped` 两处改用 `inlineImageHTML ?? html`；`MailboxView` 透传 `viewModel.inlineImageHTML`；`MessageWebView`/`MessageBodyStyle`/CSP 两档/`baseURL`/`lastRender` 零改动。L2 证据 `task-spaces/20261120-111818/evidence/inline-image-view/`（负控制 raw `naturalWidth=0`；生产改写串 `naturalWidth=32`、`magenta_px=4096`、`requests_delta=0`；纯文字基线 images=0）PASS；全量 343 例绿、架构 4 门 PASS。

## 设计增量：附件取用交互——双击打开、右键另存为（REQ-0026 / SCN-0020，2026-11-20，P2 已人工确认）

- 来源：`REQ-0026`（`feature`，`accepted`）/ 新场景 `SCN-0020`（`mail/read/attachment-access`，`designed`）。完整论证、方案族、失败路径、验证计划与设计期探针见 `task-spaces/20261120-160446/design3.md`（第 3 轮，按方案评审 `review2` B1–B3 修订；第 2 轮见 `design2.md`）与 `evidence/attachment-interaction-probe/`、`evidence/attachment-save-probe/`。
- 现状归因：附件条是 `MessageBodyView` 内联的 SwiftUI `Button`，单击即 `onOpenAttachment` → VM 下载 → `NSWorkspace.open`；无双击、无右键菜单、无另存为、无失败提示。`scenario-drafts.md` 与需求卡已把交互缺口与既有下载原语分开。
- 修改：
  - **新增** `Sources/uumail/AttachmentStripView.swift#AttachmentStripView`（internal，≤300 行）：只做附件条呈现与交互。
    - 附件元数据渲染保持 `Label(displayName, systemImage: "paperclip")` + `.buttonStyle(.bordered)` + `.controlSize(.small)` + `scaledInheritedFont`；默认布局与字号档位不变。
    - `Button` 单击动作只写 `selectedAttachmentID`（可见描边 overlay，不改变尺寸）；双击用 `.simultaneousGesture(TapGesture(count: 2).onEnded { Task { await onOpen(attachment) } })`；`.focusable()` + `.focused($focusedID, equals: id)` + `.onKeyPress(.return)` 打开；Space 仍走 Button 选中。
    - `.contextMenu` 两项：「打开」→ `onOpen`；「另存为…」→ `onSave`。不加「在 Finder 中显示」、不加分享/服务扩展。
    - AX：`accessibilityLabel(displayName)`、`accessibilityHint("双击打开；右键可另存为")`、`accessibilityAction(named: "打开")`、`accessibilityAction(named: "另存为…")`。
    - 错误 banner：`errorText != nil` 时在附件条下方一行（警告图标 + 文案，橙色，`.caption`）；无错误时零布局变化；不进状态栏/同步状态。
    - 另存为进行中（`savingID == attachment.id`）：同一 banner 位显示「正在另存为…」+「取消」（`onCancelSave`）；
      取消只取消复制任务、清理临时文件，目标不变；`savingID` 与当前选中/附件列表不一致时不显示（防串台）。
    - 附件列表变化（切换邮件）时清空选中/焦点/`savingID` 显示状态。
  - `Sources/uumail/MessageBodyView.swift#attachmentStrip` 删除内联实现，改调 `AttachmentStripView(attachments:errorText:savingID:onOpen:onSave:onCancelSave:)`；新增 `attachmentErrorText: String?`、`savingAttachmentID: String?`、`onSaveAttachment`、`onCancelSave` 入参。`natural`/`capped` 两处分支都走同一附件条；正文 WebView/CSP/字号/白底/截断 banner 零改动。`MessageBodyView` 当前 259 行，预计 ≤270。
  - `Sources/uumail/MailboxView.swift`：只做接线——构造 `AttachmentActionModel`（`currentKey`/`download`
    闭包；`MailboxView` 标 `@MainActor`）、在列表选择绑定 setter 与 `.onChange(of: viewModel.selectedListKey)`
    两处调用 `attachmentActions.syncSelection()`、把 `attachmentErrorText`/`savingAttachmentID`/
    `onOpenAttachment`/`onSaveAttachment`/`onCancelSave` 传给 `MessageBodyView`。不再自己持有
    `AttachmentActionGate`/`saveErrorText`/`saving`/`saveTask`。当前 219 行，预计 ≤245。
  - **新增** `Sources/uumail/AttachmentExport.swift`（internal，≤300 行）：
    - `SavePanelPresenting`（`destination(for:) -> URL?`，nil=取消）与 `SystemSavePanel`（`NSSavePanel`，`runModal()`；`canCreateDirectories = true`）。
    - `AttachmentFileCopy.copy(from:to:)` 为 **`nonisolated static func ... async throws`**：源==目标 no-op；否则在目标目录建临时文件，**分块复制（1 MiB/块，逐块 `Task.checkCancellation()`）在后台任务执行**，成功后按目标是否存在选择 `replaceItemAt`（已存在）或 `moveItem`（不存在）原子落位；失败/取消清理临时文件并抛 `MailError.storage`/`CancellationError`；主线程不执行文件 I/O。
    - `AttachmentSaveFlow.run(source:displayName:shouldContinue:)` 为 `@MainActor async`：面板取消 → nil；复制成功 → nil；**源缺失（面板前/复制中）→ `missingSourceText`，不自动重下**；取消 → nil（不写错误）；复制失败 → `ErrorText` 文案。**第 3 轮删除 `reResolve` 参数**（B1-b：避免跨代际按当前选中重下、避免保存重试错误写 `attachmentErrorText`）。
    - `AttachmentActionGate.begin/end`：按 `Attachment.id`（= `fileReference`）去重，保证并发双击只打开一次、并发另存为只弹一个面板。
    - **`AttachmentActionModel`**（第 3 轮，internal）：APP 动作代际协调者。`epoch: UInt64` 在
      `selectedListKey` 真正变化时递增（`syncSelection()` 唯一写点，两处接线调用）；`open`/`save`
      捕获 `Origin(key, epoch)`，每个 `await` 回来、N3 重下前、弹面板/复制前、打开/写文案前比较；
      `saveErrorText`/`saving`/`saveTask`/`openGate`/`saveGate` 归它；`saving` 只在下载成功且 origin
      仍当前后设置（下载阶段无「取消」）；`visibleSavingID` 按 origin 兜底。`fileExists`/`openFile`/
      `download`/`panel`/`copy` 均可注入供 L2；**不读 `Presentation` internal `selectionGeneration`**。
    - 时序：面板在 `@MainActor`；复制 `await` 后台任务；完成后回主线程写状态。`NSSavePanel.runModal()` 的用户交互期仍占用主线程（用户主动模态，已接受），但复制期不再阻塞。
  - 不改 `Sources/Composition/*`、`Sources/Scenes/*`、`Sources/MailDomain/*`、`Sources/MailStore/*`、`Package.swift`、`Resources/Info.plist`；不新增 target/第三方依赖；不 import `Composition`。
- 不变量：
  - 视图不下载、不读写缓存/文件、不判 `MailError`；只调 VM/闭包并显示传入文案。
  - 单击不触发下载/打开；双击/Return 只触发一次打开；右键菜单不改变正文/缓存。
  - 打开走系统默认程序；另存为保留缓存；取消不改缓存/选择；失败不打开缺失文件。
  - 缓存目录/文件名/2 GB 最旧优先/单飞/先落盘后标记全部沿用 `SCN-0005`，本增量不改。
  - **迟到结果不串台（B3）**：下载由 VM 用 `selectionGeneration` + `selectedListKey` 丢弃迟到结果；
    打开/另存为由 APP `AttachmentActionModel` 用 `Origin(key, epoch)`（`epoch` 在选择真正变化时递增）
    丢弃迟到结果；`await` 回来、N3 重下前、弹面板/复制前、打开/写文案前都比较；A→B→A 也丢弃；
    APP 不读 `Presentation` internal `selectionGeneration`（分层上读不到）。
  - **取消（B3）**：取消入口只在面板/复制阶段（下载阶段不显示「取消」）；下载阶段任务被取消 →
    不弹面板、不复制、不写错误、不打开；已在飞的共享下载不中止（`FlightBoard` 不随调用方取消）。
  - **源缺失（B1-b）**：面板前/复制中源不存在 → 不自动重下，返回 `missingSourceText`
    「附件缓存已失效，请重试另存为」；保存重试错误不写 `attachmentErrorText`（下载文案归 VM）。
  - **复制不占主线程（B4）**：`AttachmentFileCopy.copy` 为 `nonisolated async`，文件 I/O 在后台、逐块检查取消；`AttachmentSaveFlow` 只 `await`，主线程只更新状态；失败/取消清理临时文件，目标不产生半文件。
- 尺寸/预算：`AttachmentStripView.swift` 新增约 120–160 行、`AttachmentExport.swift` 新增约 210–290 行（含异步分块复制/取消 + `AttachmentActionModel`）；`MessageBodyView` 259 → ≤270、`MailboxView` 219 → ≤245；`uumail` 总量约 +360–480 行；单文件均 ≤300。
- 验证：
  - L1：`PresentationTests/MailboxViewModelAttachmentTests`（下载成功/失败/文案/清空；**迟到失败/成功不写不清新状态** `T-SCN-0020-01f`；**下载阶段调用方取消不写错误** `T-SCN-0020-01g`）；`ScenesTests/ReadSceneTests`（缓存外部删除、并发单飞）；`FileAttachmentFilesTests` 既有 3 例回归。
  - L2：直接编译生产 `AttachmentStripView.swift` + `AttachmentExport.swift` + `MessageBodyView.swift`/`MessageWebView`/`MessageBodyStyle.swift` + 所需 `Presentation` 对象；断言单击/双击/Return、`NSView.menu(for:)` 菜单项与 `performActionForItem`、`AttachmentSaveFlow` 取消/成功/失败/源缺失不重下、`AttachmentFileCopy` 字节/覆盖/临时文件/目标不存在、gate 去重；**生产 `MessageBodyView` 的 `natural`/`capped` 两处接线**（`T-SCN-0020-06`）；**异步复制主线程隔离/取消**（`T-SCN-0020-08`）；**A1/A8 既有 L2 回归**（`T-SCN-0020-05/07`：`InlineImageVerifyProbe`、CSP 两档/远程 gate、白底、字号）；**APP 动作代际/取消/`saveErrorText`**（`T-SCN-0020-10a..10e`）。`T-SCN-0020-05` 的 `swiftc` 文件列表必须含 `AttachmentStripView.swift`，先编译（exit 0）再运行，原始输出 `l2-inline-image-build.txt`/`l2-inline-image-regression.txt`。证据入 `task-spaces/<run>/evidence/attachment-access-verify/`，逐例原始输出 + `commands.md`。
  - 不上 L3/L4；真实右键/Control-单击、真实 `NSSavePanel`、VoiceOver、选中态/banner 像素为发布前手工冒烟残余。
- 定级与确认：**P2**（跨 `CMP-APP`/`CMP-PRES`；无 schema/`MailDomain`/`AttachmentFiles`/`Scenes`/`Composition`/target/依赖变更）。唯一新增公开面 `MailboxViewModel.attachmentErrorText` 已**人工确认 A（2026-11-20）**，记录 `doc/history/decisions/2026-11-20-attachment-error-surface.md`；`AttachmentActionModel`/`AttachmentExport` 为 `uumail` internal，`selectionGeneration` 为 `Presentation` internal 且 APP 不引用，均不新增 public。D1–D18 为**默认确认（未经人工）**，见 `task-spaces/20261120-160446/design3.md` §8（第 3 轮新增 D16–D18）。回退：删除 `AttachmentStripView`/`AttachmentExport`/`AttachmentActionModel` 与接线，恢复 `MessageBodyView` 内联 Button 与单击打开；无数据/契约迁移。
- 实现进度：未实现（设计落卡 2026-11-20；第 2 轮按评审 B1–B4 修订异步复制/取消与验证计划；**第 3 轮按 `review2` B1–B3 修订 APP 动作代际、N3/源缺失 guard、取消收窄、`T-05` 编译文件**）。task-split 按本增量拆任务；实现 commit 只含 `Sources/uumail/*`、`Sources/Presentation/*` 与 L1/L2 证据所需改动，不翻场景状态。
- 实现进度（2026-11-20，`T-1120-07`）：`AttachmentExport.swift`（279 行）落地 `SavePanelPresenting`/`SystemSavePanel`、`AttachmentFileCopy`（`nonisolated async` + `Task.detached` 1 MiB 分块 + 取消传播 + 临时文件原子移动/替换）、`AttachmentSaveFlow`（去 `reResolve`；`missingSourceText`；`shouldContinue`）、`AttachmentActionGate`、`AttachmentActionModel`（`Origin(key,epoch)`/`syncSelection` 唯一递增/N1 首次下载前 guard/N3 重下 guard/`visibleSavingID`）；L2 生产源探针 `attachment-export-probe` 21 项全 PASS（`02e/02f/08a/08b/10a–10e` + 源缺失不重下），证据 `task-spaces/20261120-160446/evidence/attachment-access-verify/l2-export.txt`；`swiftw build` 与架构 4 门 PASS。
- 实现进度（2026-11-20，`T-1120-08`）：新增 `AttachmentStripView.swift`（114 行）：`Label`+`bordered`/`small`/`scaledInheritedFont` 原样式保留；单击只写 `selectedAttachmentID`（overlay 描边，不改尺寸），双击 `simultaneousGesture(TapGesture(count:2))`、`.focusable`+`.focused`+`.onKeyPress(.return)`，`.contextMenu` 恰两项「打开」「另存为…」；AX label/hint/两个自定义动作；`savingID` 匹配时「正在另存为…」+「取消」，否则 `errorText` 橙色 banner，二者都无时零布局变化；附件列表变化清本地选中/焦点。L2 生产源宿主探针 `attachment-strip-probe` 6 项全 PASS（`02a/02b/02c/02d/04b`），证据 `task-spaces/20261120-160446/evidence/attachment-access-verify/l2-strip.txt`；`swiftw build` 与架构 4 门 PASS。
- 实现进度（2026-11-20，`T-1120-09`）：`MessageBodyView` 删除内联附件条，`natural`/`capped` 两处改调 `AttachmentStripView`，新增 `attachmentErrorText`/`savingAttachmentID`/`onSaveAttachment`/`onCancelSave` 四个参数（254 行）；`MailboxView` 标 `@MainActor`、`@State AttachmentActionModel`、`init` 注入 `currentKey`/`download`、列表绑定 setter + `.onChange(of: selectedListKey)` 两处 `syncSelection()`、传 `saveErrorText ?? attachmentErrorText` 与 `visibleSavingID`、删除内联 `NSWorkspace.open`（236 行）。L2 宿主探针 `attachment-wiring-probe` 15 项全 PASS（`06a` 100/120/145% 单击 0/双击 1/菜单两项/高度与旧内联条一致、banner 条件渲染；`06b` 175/225% 附件条可点、WebView 339pt ≥200）；`T-05` 回归探针编译含 `AttachmentStripView.swift`、17 用例全 PASS（`l2-inline-image-build.txt`/`l2-inline-image-regression.txt`）；全量 360 例/58 suites 绿、架构 4 门 PASS。

## 设计增量：正文宽表格适配（REQ-0027 / SCN-0021，2026-11-23，P3）

- 来源：`REQ-0027`（`accepted`）/ `SCN-0021`（`mail/read/html-table-layout`）；证据与方案见 `doc/history/works/2026-11-23-table-adapt/`。
- 现状：`MessageBodyStyle.baseCSS` 只有 `table { max-width: 100% }`；816px / 8 列固定宽度的表压不下去，145/175/225% 字号下文档 `scrollWidth` 832px，右侧列被阅读区裁掉。
- 变更：`baseCSS` 增加

  ```css
  table[width], table[style*="width" i] {
      display: block;
      max-width: 100%;
      overflow-x: auto;
  }
  ```

  只命中带显式宽度的表；无宽度表保持 `display:table`。块宽被 `max-width` 压到阅读区，列宽由 WebKit 重排；内容仍压不下去时表格内部横向滚动。`MessageWebView`、CSP 两档、`baseURL`、禁 JS、白底、字号 `pageZoom`、`lastRender` guard 全部零改动。
- 不做：HTML 扫描/包裹、JS、`!important`、撰写页 `ComposeDocument`（另立）；允许显式宽度 ≤ 视口的表保持原宽。
- 验证：L2 `TableLayoutProbe`（编译生产 `MessageBodyStyle.swift`）逐例断言 120% 下 816px 表保持 816、`scrollWidth == 978`；145/175/225% 下 `scrollWidth == 810/671/522`；无宽度 300px 表不被拉伸；900px 表 + 600px 图在 668px 下 `scrollWidth == 668`。证据 `doc/history/works/2026-11-23-table-adapt/evidence/`。
- 残余：带 `align`/浮动的显式宽度表可能改变环绕版式；无显式宽度且内容超宽的畸形表仍可能溢出。发布前真实样本冒烟。
- 实现进度（2026-11-23，`T-1123-04`）：规则已加入 `MessageBodyStyle.baseCSS`（50 行）；L2 `TableLayoutProbe` 6/6 PASS（120/145/175/225、窄表、图片表），真实样本 120% 979/978、145/175/225% 810/671/522、`overflowCount=0`；全量 384 tests/59 suites、架构 4/4、`make-app.sh` 通过。证据 `doc/history/works/2026-11-23-table-adapt/evidence/`。

## 设计增量：日历页与会议卡（REQ-0029 / SCN-0024、REQ-0030 / SCN-0023，2026-11-24，已实现）

- 来源：`REQ-0029`/`SCN-0024`、`REQ-0030`/`SCN-0023`；`CMP-PRES` 同批增量提供 `CalendarViewModel`、`MeetingCardPresentation` 与网格投影；`CMP-SCN-CALENDAR` 提供 `ics` 文本。
- **导航**（`MailboxView.swift`，+约 70 行，≤300）：
  - 侧栏顶部新增「日历」行（`Label("日历", systemImage: "calendar")`）+ `Divider` + 现有文件夹 `List`；点「日历」置 `@State private var calendarSelected = true` 并清空邮件列表选中；点任一文件夹置回 `false`。
  - `body` 顶层二分支：`calendarSelected == true` → `NavigationSplitView { sidebar } detail: { CalendarView(model: calendarModel) }`（两栏，日历占满右区）；`false` → 现有三栏邮件布局（原样保留，不改列表/正文/工具栏/搜索）。
  - 日历→邮件跳转：`CalendarView` 交出 `(folderID, serverID)`，`MailboxView` 置 `calendarSelected = false` 后调 `viewModel.select(folderID:)`（该调用会重载列表）再按 `serverID` 选中；目标邮件不在当前 200 封页面时只切到文件夹并给状态栏提示「该邀请不在当前列表页」，不伪造选中、不新增 VM 方法、不在场景间互调。
- **新文件** `Sources/uumail/CalendarView.swift`（internal，≤300 行）：
  - 工具栏：`Picker`（月/周，`.segmented`）+「上一周期 / 今天 / 下一周期」三个按钮（`chevron.left`/`calendar`/`chevron.right`），全部只调 `CalendarViewModel` 方法。
  - 月视图：固定 6 行 × 7 列 `LazyVGrid`；列头「一…日」；每格显示日号（非当月灰、今天高亮）+ 最多 3 个事件 chip + 「+N」；chip 点击选中事件，日号点击切到周视图并把 `anchor` 置为该日。
  - 周视图：左侧时间槽（整点标签）+ 7 列；事件块按 `startMinute/endMinute` 比例定位，重叠按 `lane` 并排；顶栏一行放全天事件。
  - 事件详情：选中后用 `.popover` 展示主题/时间/地点/组织者/重复说明/来源邮件，按钮「打开邮件」「在日历中打开」。
  - 空态与错误：无事件 → `EmptyState`（「本期没有收到会议邀请」+ 说明只覆盖升级后同步窗口）；`errorText` → 顶部 banner；`isTruncated` → 顶部「仅显示前 500 条」提示。
- **新文件** `Sources/uumail/MeetingCardView.swift`（internal，≤120 行）：卡片只读 `MeetingCardPresentation`，三个字段行 + 「在日历中打开」按钮；按钮动作由 `MessageBodyView` 注入的闭包提供；卡片无网络、无文件访问。
- **`MessageBodyView` 变更**（+约 20 行，仍 ≤300）：新增 `meetingCard: MeetingCardPresentation?` 与 `onOpenInCalendar: () -> Void`；渲染位置在 `MessageHeaderView` 与正文 `switch` 之间、且位于 `switch` 之外，保证 `.loading/.loaded/.failed` 都显示卡片。
- **新文件** `Sources/uumail/CalendarExport.swift`（internal，≤120 行）：`CalendarFileWriting`（写临时目录）+ `CalendarOpening`（`open(URL) -> Bool`，生产实现 `NSWorkspace.shared.open`）+ `CalendarExport` 协调（写文件 → 打开 → 失败清理、成功延迟清理）。协议只为 L2 探针注入替身，不进入 public 面。**不引入 EventKit、不申请日历权限**：`.ics` 交给系统默认日历应用导入，本进程不读日历数据。
- 尺寸：`uumail` 现约 2729 行 + 约 530 行 → 约 3259 行；单文件 `CalendarView` ≤300、`MailboxView` ≤300、`MessageBodyView` ≤300；不新增 target/依赖。
- 测试（L2 探针，沿用 `NSHostingController` + `NSTextField.stringValue`/`NSToolbar` seam）：
  - 月视图：6×7 网格文本、日格 chip 文本与「+N」；
  - 周视图：事件块 frame 与 09:30 行对齐（几何断言，容差 ±2pt）；
  - 卡片：邀请邮件出现卡片文本，非邀请无卡片节点；
  - 导出：点击调 `CalendarOpening` 替身 1 次且 URL 存在，删除后临时文件被清理。
  - 若某个 seam 不可行（R41），由 `SCN-0024`/`SCN-0023` 声明 L3 并写理由，不用 L1 投影冒充。

## 实现（2026-11-24，T-1124-11/12）

- `Sources/uumail/CalendarView.swift`（月网格/周时间轴/事件详情/导出）、`MeetingCardView.swift`、
  `CalendarExport.swift`（临时 `.ics` + `NSWorkspace`，opener 可注入）；`MessageBodyView` 在信封头与正文之间插入卡片；
  `MailboxView` 侧栏「日历」入口与二分支布局；`UumailApp` 传入 `calendarModel`。
- 证据：437 tests / 71 suites、架构 4/4、`make-app.sh` 成功；月/周像素与 `NSWorkspace` 导入为发布前人工冒烟项（R59）。

## 修复：日历跳回邮件的定位与侧栏选中（2026-11-24，REQ-0029/SCN-0024）

- 现象与根因见 `history/pitfalls.md` P1：侧栏用「Button + 第二个 List」两套状态，分栏重建时 `onChange` 把日历状态改回邮件；
  跳转只做 `select(folderID:)`+`select(messageID:)`，同文件夹早退、搜索模式下找不到、且列表不滚动。
- 修复：侧栏改为单一 `List(selection:)`（`calendarTag` 哨兵 + folder id，`sidebarSelection` 一个 Binding 驱动两种内容）；
  跳转改用 `MailboxViewModel.reveal(folderID:serverID:)`（清搜索 → 切文件夹 → 重载 → 选中，找不到返回 false）；
  `MailboxView` 给消息列表加 `ScrollViewReader`，选中变化滚动到可视区；状态栏提示未加载的邀请。
- 证据：`MailboxRevealTests` 3 例 + 全量 440 tests / 72 suites 绿、架构 4/4、`make-app.sh` 成功。

## 修复：邮件工具栏 tooltip（2026-11-24）

- 现象与根因见 `history/pitfalls.md` P2：SwiftUI 的 `.help` 不会桥接到 `NSToolbarItem.toolTip`，且 4 个按钮原本没有 `.help`。
- 修复：`ToolbarTooltipInstaller`（零尺寸 `NSViewRepresentable`，挂在邮件列 `.background`）在窗口 toolbar 出现后按
  `item.label` 补 `toolTip`，已有值不覆盖；`MailboxToolbar` 的 7 个按钮补齐 `.help` 文案。
- 证据：离屏探针 7/7 条目 `toolTip` 非空（`task-spaces/20261124-toolbar-tooltip/evidence/tooltip-probe.txt`）；
  全量 440 tests / 72 suites、架构 4/4、`make-app.sh` 成功。

## 设计增量：浮动阅读窗宿主与双击/键盘入口（REQ-0031 / REQ-0032，2026-11-24，P2）

**载体结论（探针先行，R63 关闭）**：浮窗用 **AppKit `NSWindow` + `NSHostingController`**，不用 SwiftUI `Window` 场景。

- 探针证据 `task-spaces/20261124-152611/probe/`：
  - `window-carrier.txt`：SwiftUI `Window(id:)` 确实是单例（两次 open 同一 window 编号）、`.defaultSize` 生效、
    可在开窗后 `setFrame`；但**运行时算出的初始尺寸无法在显示前生效**——
    `content-sized.txt` 请求 480×680 实测 660×622、`content-sized-ressize.txt`（`.windowResizability(.contentSize)`）实测 900×622。
    若走 SwiftUI 载体只能在开窗后 `setFrame`，会先闪一个错误尺寸，违反「默认尺寸 = 阅读区宽 × 主窗口 85%」的可感知承诺。
  - `appkit-window.txt`：AppKit 载体在 `orderFront` 前 `NSWindow(contentRect:)` 定尺寸，内容 480×707 精确生效；
    复用同一 `windowNumber`、二次打开只改内容尺寸、`readerWindows` 计数 1。
- 新文件 `Sources/uumail/ReaderWindowController.swift`（≈140 行，internal）：
  - 持有唯一 `NSWindow`（`styleMask: [.titled, .closable, .resizable, .miniaturizable]`、`isReleasedWhenClosed = false`、
    `isRestorable = false`、`setFrameAutosaveName("reader")`），内容由 `NSHostingController` 承载 `ReaderWindowView`。
  - `show(ref:using router:model:)`：无窗 → 用 `router.readerSize(for:)` 在显示前建窗，位置贴主窗口右上、向内偏移，
    `makeKeyAndOrderFront`；有窗 → 更新 router ref 与 model，`setContentSize`（仅当用户未手动调整过；已调整则沿用），置前。
  - 撰写态 `router.blockedNotice` → 视图展示提示行，不替换内容。
  - `windowShouldClose`：阅读态直接关；撰写态交给 `ComposeView` 既有的「放弃这封邮件？」确认，取消则 `return false`。
- 新文件 `Sources/uumail/ReaderWindowView.swift`（≈120 行，internal）：信封头 + 静态提示 +（只读）会议卡 + 正文 + 工具栏；
  阅读态 `MessageBodyView(allowRemoteContent: true)`，工具栏「回复 / 全部回复 / 转发」；撰写态整块换成 `ComposeView`
  （`preferredWidth` = 内容宽、`preferredHeight` = 内容高），关闭后回阅读态。
- 入口（`MailboxView`）：
  - 行上 `.onTapGesture(count: 2)` 打开浮窗（单击仍由 `List(selection:)` 选中；双击时先选中再打开，属于既有选择行为）；
  - `onKeyPress(.return)` 与 `onKeyPress(.space)`：`messageListFocused` 且有选中 → 打开浮窗（与双击同一路径）；
  - 打开前把主窗口几何写入 `ReaderRouter`：阅读区宽沿用现有 `readingPaneSize.width`，窗口高取 `NSApp.keyWindow?.frame.height`。
- 日历（`CalendarView` + 新文件 `CalendarSelection.swift` ≈90 行）：
  - 删除 360×240 详情 sheet 与 `SelectedOccurrence`；新增 `selectedOccurrence`（同一时刻一个）；
  - 月块/周块包一层 AppKit 点击捕获 `ClickCatcherView`（`clickCount == 1` → 选中，`== 2` → 打开；探针
    `probe/click-catcher.txt`：1→仅选中、1,2→选中+打开、2→仅打开），Esc 清选中；
  - 浮窗工具栏为「转发」「在日历中打开」；`在日历中打开` 复用 `CalendarExport.present`（`.ics` 文本由 `CMP-SCN-CALENDAR#ics(for:)` 提供）；
  - `CalendarView` 从 325 行降到 ≈280（详情段移出、点击捕获与选中态进新文件），恢复单文件 ≤300。
- 远程图片（决策 D6）：仅 `ReaderWindowView` 阅读态传 `allowRemoteContent: true`；静态提示文案
  「远程图片来自发件人服务器，已自动显示」；主窗口 `MailboxView` 与撰写编辑器**不传 true**。
- 目录与预算：`Sources/uumail` 约 2,130 → 约 2,450 行；`ReaderWindowController`/`ReaderWindowView`/`CalendarSelection`
  各 ≤180。`MailboxView.swift` 实测 **305 行已超 ≤300**（`plan/risks.md` R71）：本批新增的双击/Enter/空格入口、浮窗工具栏接线
  **必须落在新文件 `MailboxView+Reader.swift`**（SwiftUI 视图扩展），使主文件回到 ≤300；`CalendarView` 从 325 降到 ≈280
  （详情段删除、点击捕获与选中态进 `CalendarSelection.swift`）。比例与拆分见 `T-1124-20` 出口，超预算即停，不调上限。
- 装配：`ReaderCoordinator`（`@MainActor` 类，持有 `ReaderRouter` + `ReaderWindowController`）在 `UumailApp` 创建，
  经 environment 下传；**`AppComposition` 不改**（仍 188/200 行），因此本批无 `CMP-ROOT` 任务。
- 验证：
  - L2 窗口探针（`T-SCN-0025-01`）：开窗内容尺寸 = `readerSize`、复用同窗、`frameAutosaveName` 生效（重启读取已保存 frame）；
  - L2 日历探针（`T-SCN-0024-05/06`）：单击只选中、双击/Enter/空格打开、无 sheet；
  - 远程图片：渲染文本含 `img`（CSP `img-src` 放行）且提示存在；主窗口同封仍无远程资源请求（同一套 `MessageBodyView`，传参不同）。

## 实现（2026-11-24，T-1124-20）

- 新文件：`ReaderCoordinator.swift`（118 行，AppKit `NSWindow` + `NSHostingView`，`setFrameAutosaveName("uumail.reader")`）、
  `ReaderWindowView.swift`（146 行，阅读态/撰写态切换、工具栏按路由风格、远程图片静态提示）、
  `CalendarSelection.swift`（44 行，`ClickCatcherView` + representable）、`CalendarBlocks.swift`（115 行，月块/周块/横幅）、
  `MessageRowView.swift`（35 行）。
- 改动：`MailboxView` 行双击 + Enter/空格入口（`MailboxView+Reader.swift`，292 行）；`CalendarView` 去详情、选中高亮、
  双击/Enter/空格打开（293 行）；`UumailApp` 不再需要第二 Scene。
- **架构门禁约束落地**：`uumail` 不得 import `Scenes`/`Observation`，因此读窗口用进程内单例
  `ReaderCoordinator.shared`，入口传 `folderID`/`serverID` 字符串，`MessageRef` 只在 `Presentation` 内部出现。
- 证据（L2）：`evidence/calendar-click/calendar-click.txt`（生产 `CalendarSelection` 的 `hitTest` 命中与 clickCount 映射）；
  载体机制证据 `probe/appkit-window.txt`。真实点击/拖动/缩放/多屏与撰写关闭确认框登记为发布前人工项。
- 后续（2026-11-24，`T-1124-23`…`T-1124-25`）：列表列宽、行双击、浮窗默认居中与周视图小时虚线 4 处修复完成；
  461 tests / 77 suites、架构 4/4；L2 证据 `task-spaces/20261124-233500-feedback5/probe/`；`make-app.sh` 成功（release）。

## 设计增量：列表默认列宽与双击入口修复（REQ-0034 / REQ-0031 修复，2026-11-24，P3）

- 来源：用户反馈（2026-11-24，W-M3-18）「列表太窄」「双击没反应，只有 Enter 能打开」；`REQ-0034` 收列宽，
  双击入口按 `REQ-0031` 的修复处理。本增量只动 `CMP-APP`，不改 `CMP-PRES`、场景卡与需求口径。
- 列宽：消息列表列 `.navigationSplitViewColumnWidth(min: 320, ideal: 480)`（原 `280/380`）；侧栏仍 `180/220`（未改）。
  L2 探针实测（`task-spaces/20261124-233500-feedback5/probe/column-width.txt`）：
  - 窗口 1440 宽：侧栏 220 / 列表 480 / 正文 731（W-M3-19 去掉侧栏后为 480 / 952，见下文两栏增量）；
  - 1000：220 / 480 / 291；900：220 / 480 / 191；760：220 / 480 / 51（低于窗口下限 900，仅探针）。
  - 列表优先保 480，窗口变窄时正文列先让位；不再回到 280 的窄列。
- 双击根因：SwiftUI `.onTapGesture(count: 2)` 挂在 `List(selection:)` 的行上在 macOS 不触发（列表消费点击；
  用户实测只有 Enter 能打开）。改为在行上 overlay 一层 AppKit 点击捕获，复用 `CalendarSelection.swift` 的
  `ClickCatcherView`。
- 新文件 `Sources/uumail/MessageRowClick.swift`（21 行，internal）：
  - 只有 `onSelect`/`onOpen` 两个闭包，body 为
    `ClickCatcher(singleClickDelay: 0, onSingleClick: onSelect, onDoubleClick: onOpen)`；
    不读 `Message`、不建窗口、不复刻打开逻辑。
  - `MailboxView` 在 `MessageRowView` 上 `.overlay { MessageRowClick(onSelect:onOpen:) }`；单击立即写
    `messageSelection.wrappedValue = message.listKey` 并 `messageListFocused = true`，双击调 `openReader(message)`
    （`MailboxView+Reader.swift`，30 行）。
- `ClickCatcherView` 增加实例级 `singleClickDelay`（默认 `ClickCatcherView.singleClickDelay = 0.28`，保持日历行为）；
  `ClickCatcher` 的 `makeNSView`/`updateNSView` 都透传。延迟 >0 时单击挂 `DispatchWorkItem`、双击取消；
  列表传 0：单击同步执行，双击回调只负责打开。
- 入口路径：
  - 单击：只选中并聚焦列表，不打开浮窗；
  - 双击：系统事件 `1→2` 时先选中、随即打开；只有 `2` 时直接打开（探针覆盖）；
  - Enter / 空格：列表聚焦且有选中 → `openSelectedInReader()`，与双击共用 `openReader` →
    `ReaderCoordinator.shared.show(...)`；无选中或焦点不在列表时返回 `.ignored`；
  - 三条路径都不新增命令、不改变主窗口选中语义。
- 行预算：`MailboxView.swift` **299 行**（≤300）；`MessageRowClick.swift` 21；`MailboxView+Reader.swift` 30；
  本修复只新增 `MessageRowClick.swift`（周视图的 `CalendarHourGrid.swift` 见下一节）；不改 schema，
  不新增 target/依赖/公开面。
- 证据：`probe/column-width.txt`（1440/1000/900/760 三列实测）、`probe/message-row-click.txt`
  （catchers=3；行单击只选中；`1,2` 选中+打开；纯 `2` 打开；`window.sendEvent` 的 `hitTest` 命中）；
  探针源 `MailboxColumnWidthProbe.swift`/`MessageRowClickProbe.swift`。

## 设计增量：浮窗默认居中与周视图小时虚线（REQ-0035 / REQ-0036，2026-11-24，P3）

- 来源：用户反馈浮窗每次出现在主窗口右上、像偏在一侧；周视图每小时一块灰色实心带，读不出小时网格。
  `REQ-0035` 收居中，`REQ-0036` 收小时虚线；定位纯函数在 `CMP-PRES`（见其同日增量），本组件只负责 AppKit
  窗口放置与绘制。
- 浮窗默认居中（`ReaderCoordinator`）：
  - 原实现固定 `setFrameTopLeftPoint` 贴主窗口右上；改为调
    `ReaderRouter.centeredOrigin(in: mailbox.frame, size: window.frame.size, visible: screen.visibleFrame)`，
    以主窗口中心为浮窗中心，再夹进屏幕可用区。
  - autosave 名 `uumail.reader.centered`（原 `uumail.reader`）：旧名字默认保存的是右上角 frame，继续用会把
    「默认居中」抵消；换名后旧 frame 不再被恢复。
  - 新增 `UserDefaults` 键 `uumail.reader.userMoved`：`windowDidMove` 且
    `NSApp.currentEvent?.type == .leftMouseDragged`、非程序化放置（`isPlacing`）时置 true；未拖动过 → 每次启动
    重新居中（保留已恢复的尺寸）；已拖动过 → `setFrameUsingName` 恢复位置与尺寸，不再居中。
  - 默认尺寸仍由 `ReaderRouter.readerSize(for:)` 决定；本增量不改 480/460 下限、85% 高与屏幕高 cap。
- 周视图小时虚线（`CalendarHourGrid` + `CalendarView`）：
  - 新文件 `Sources/uumail/CalendarHourGrid.swift`（23 行，internal）：一个 `Path` 画 `startHour...endHour`
    共 17 条横线（8…24），`hourHeight = 48`，最后一条落在 `totalHeight - 0.5`；
    `stroke(Color.gray.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))`。
  - `CalendarView` 周视图用 `CalendarHourGrid` 替掉每小时一块的 `Rectangle().fill(secondary.opacity(0.08))`
    实心带；时间槽标签、事件块定位、lane、全天条均不变。
  - **实现坑**：`Color.secondary` 作为 `Path.stroke` 的颜色在 SwiftUI 里不渲染（实测无可见线）；改为
    `.gray.opacity(0.45)`。语义色需求若以后要跟随主题，必须重新实测，不能直接换回 `.secondary`。
- 范围/预算：不新增 target/依赖/公开面，不改 schema；`ReaderCoordinator` 163 行、`CalendarView` 293 行、
  `CalendarHourGrid` 23 行，均 ≤300。
- 证据：`task-spaces/20261124-233500-feedback5/probe/hour-grid.png`（1024×1824 预览，17 条虚线）；
  探针源 `HourGridPreview.swift`。真实拖动/缩放/多屏行为仍属发布前人工冒烟项。

## 设计增量：顶部三段切换与去掉文件夹栏（REQ-0037 / REQ-0038，2026-11-24，P2，已实现）

- 来源：`REQ-0037`（顶部三段切换、去掉文件夹侧栏）/ `REQ-0038`（发件箱），场景 `SCN-0028` / `SCN-0029`。`CMP-PRES` 同批提供 `inboxFolderID`/`sentFolderID`/`selectSent`/`refreshSent`，`CMP-SYNC` 提供 `syncSentOnce`。不改 schema/target/依赖/EAS 协议，不改 `MessageBodyView`/`MessageWebView`/`MessageBodyStyle`/`CalendarView`/`UumailApp`。
- 顶部切换（根视图，始终可见）：
  - `MailboxView.body` 为 `Group`：`section == .calendar` 时整块渲染日历，否则渲染邮件两栏；`private enum MailboxSection { case inbox, sent, calendar }`，默认 `.inbox`。
  - 根 `.toolbar` 的 `ToolbarItem(placement: .navigation)` 放 `Picker("邮箱", selection: $section)`：`.pickerStyle(.segmented)`、`.labelsHidden()`、`.frame(width: 260)`，三段「收件箱 / 发件箱 / 日历」。位置是窗口 leading（交通灯之后），挂在根 `Group` 上而非某个分栏，所以邮件页与日历页都保留；另加 `.toolbar(removing: .sidebarToggle)` 去掉侧栏开关。
  - 邮件页两栏 `NavigationSplitView`：第一列 = 消息列表（`VStack`：列表 + `Divider` + 状态栏；`.navigationSplitViewColumnWidth(min: 320, ideal: 480)`、`.searchable(placement: .toolbar)`、工具栏 `MailboxToolbar`），详情 = 阅读区（信封头 + 会议卡 + 正文 + 附件条）。不再渲染 `viewModel.folders`（`reloadFolders` 保留，用于解析收件箱/发件箱的 serverID）；其他文件夹不提供入口、也不同步。
  - 日历页 `CalendarView(model:)` 独占内容区（不嵌 split），顶部切换仍在。
- 切换动作（`onChange(of: section)`）：
  - `.inbox` → `select(folderID: viewModel.inboxFolderID)`；
  - `.sent` → `Task { await viewModel.selectSent() }`，**任务完成后若 `section` 已不是 `.sent` 则 `select(folderID: inboxFolderID)`**（防 Sent 同步迟到把导航抢回发件箱）；
  - `.calendar` → 无动作（`CalendarView` 自己加载）。
- 刷新分派：`MailboxToolbar.Actions.refresh` 按 section 分派 `viewModel.refresh()` / `viewModel.refreshSent()`；其余动作、顺序与禁用条件不变（仍 7 项）。
- 空态与标题：列表为空时 `EmptyState`，发件箱段显示「没有发件邮件」、收件箱段沿用「没有邮件」；`navigationTitle` 为「发件箱」/「收件箱」。
- **否决 `HSplitView`**：探针（`probe/HSplitProbe.swift`，列表 `.frame(minWidth: 320, idealWidth: 480, maxWidth: 760)`）在 1440 窗口把列表拉到 **760**，不遵守 `idealWidth`；改用两栏 `NavigationSplitView`，同一宽度语义下列表稳定 480、阅读区先让位。
- 尺寸：`MailboxView` **293 行**（≤300，余 7）；`Sources/uumail` 共 3813 行；不新增文件/target/依赖。
- L2 证据（`task-spaces/20261125-000000-sent-nav/probe/`，重建命令见同目录 `run.sh`）：
  - `toolbar-nav.png`：顶部三段 Picker、无文件夹栏；
  - `two-column.txt`：1440 窗口 list 480 / reading 952；900 窗口 list 480 / reading 412；
  - `HSplitProbe.swift`：否决 `HSplitView` 的依据。
- 人工项（发布前）：真实点击顶部切换、列表/阅读分隔条拖拽、深色主题整窗视觉；真实发一封测试信后确认服务器 Sent Items 出现副本并能在「发件箱」拉到（外发需用户确认）。
- 定级：**P2**（跨 `CMP-APP`/`CMP-PRES`/`CMP-SYNC`；无 schema/协议/target/依赖变更；APP 层无新增 public 契约）。

## 设计增量：设置页邮箱地址输入（REQ-0039，2026-11-25，P2，已实现）

- 来源：`REQ-0039` / `SCN-0030`。表单在「账号（不带域）」之后新增一行「邮箱地址」，让用户填写与实际邮箱域一致的 `From` 地址；留空时沿用 `账号@服务器地址`。
- `AccountSetupView` 的账号 Section 字段顺序：显示名 → 服务器地址 → 账号（不带域）→ 邮箱地址 → 密码 → 域。
- `TextField("邮箱地址", text: $viewModel.email, prompt: Text("name@company.com；留空则用 账号@服务器地址"))`：
  - 不设 `SecureField`、不做格式校验、不禁用连接按钮；空值与非法值的取舍交给服务器和场景。
  - 文案同时给出示例与留空回退，避免用户把 Exchange 主机地址误填成邮箱地址。
- 视图只绑定 `AccountSetupViewModel.email`，不读配置、不比较已存地址、不直接调 `updateAccountAddress`；提交仍走既有 `onConnect` → `connect()`。
- 尺寸：`AccountSetupView.swift` **71 行**；不新增文件/target/依赖，不改 schema 或其他表单字段。本增量未新增 APP 层测试；连接与迁移行为由 `AccountSetupSceneTests` 覆盖。
