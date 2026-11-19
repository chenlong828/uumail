---
layer: design
module: app
status: active
updated: 2026-11-19
component: CMP-APP
---

# CMP-APP AppShell 组件规格

## 模块卡

- 状态：`active`（视图只绑定视图模型；`UumailApp` 只做装配与窗口宿主）
- 单元：组件
- 层 / 类型：L3；UI 外壳
- 业务价值：让用户能看见并操作邮箱；没有它，同步能力只存在于命令行。
- 负责 X：窗口与导航、窗口主工具栏（`MailboxToolbar`）、文件夹选择、邮件列表渲染、正文 WebView、撰写/配置表单、空态与失败态展示；T-1114-10 设计新增列表焦点 Delete/Backspace、前台状态转发（实测后改用 `NSApplication` 通知）、状态栏删除错误（2026-11-14 已实现，T-1114-18）；2026-11-18 设计新增撰写页收件人/抄送字段控件与候选浮层（`RecipientTextField`/`RecipientSuggestionList`/`RecipientForm.swift` 的 `ComposeRecipientForm`）。
- 不负责 Y：业务编排、状态机、格式化规则、服务装配、网络与持久化。
- 内部逻辑：
  - `UumailApp` 构造 `AppComposition`，按 `route` 显示 `MailboxView` 或 `AccountSetupView`；生命周期交给组合根。
  - 每个视图只接收一个视图模型（`@Bindable`），动作一律 `viewModel.xxx()`；响应式刷新只看 VM 状态。
  - 正文渲染：`MessageWebView`（WKWebView、禁 JS、CSP 阻止远程资源）；附件条点击调 VM。
- 拥有的数据：无；账号凭据归 `CredentialStore`，邮件数据归 `MailStore`。
- 变化轴：窗口形态（单窗口 → 多窗口/菜单栏）、列表与阅读布局、字号档位（2026-11-17 新增五档 UI 偏好）。
- 公开契约：无对外契约；只依赖 `Presentation`（`UumailApp` 另依赖 `Composition`）。
- 入口：`Sources/uumail/UumailApp.swift#UumailApp`、`MailboxView.swift#MailboxView`、`MailboxToolbar.swift#MailboxToolbar`（2026-11-16 设计新增）、`MessageBodyView.swift#MessageBodyView`、`ComposeView.swift#ComposeView`、`RecipientForm.swift#ComposeRecipientForm`（2026-11-18 设计新增，internal；方案设计复核从 `ComposeView.swift` 拆出，供 L2 探针单独编译）、`RecipientTextField.swift#RecipientTextField`/`#RecipientSuggestionList`（2026-11-18 设计新增，internal）、`AccountSetupView.swift#AccountSetupView`、`FontSizeStyle.swift#EnvironmentValues.fontSizePreference`/`#View.scaledFont(_:)`/`#View.scaledInheritedFont(_:)`/`#FontSizePreference.font(for:)`、`FontSizeCommands.swift#FontSizeCommands`、`EmptyState.swift#EmptyState`（2026-11-17 设计新增，internal；第 2 轮修正入口符号）
- 依赖：`Presentation`、`Composition`（仅 `UumailApp.swift`）、SwiftUI/AppKit/WebKit。扇出 2。
- 冷热：热（读本地库）；收件人候选只读 VM 内存状态，不触网、不查库。
- 尺寸预算：单文件 ≤300 行；当前 `uumail` 共 **1490 行**（2026-11-18 实测：`MailboxView` 218、`MessageBodyView` 256、`UumailApp` 69、`MessageHeaderView` 34、`ComposeView` 172、`ComposeEditor` 173、`ComposeFormatBar` 75、`AccountSetupView` 66、`MailboxToolbar` 75、`MessageBodyStyle` 41、`ThemeCommands` 45、`FontSizeStyle` 106、`FontSizeCommands` 33、`EmptyState` 127）；2026-11-18 收件人联想设计预计 +280–340（`RecipientTextField.swift` 约 200、`RecipientForm.swift` 约 80、`ComposeView` 约 180）→ 约 1770，单文件仍 ≤300，不新增 target/依赖。
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
- 测试：`PresentationTests/ComposeDocumentTests` + `ComposeViewModelTests`（L1）；L2 真实 App 冒烟：sheet `1441×820`、detail `1440×987`（等宽）、「取消」/格式栏/抬头/全宽正文可见（`task-spaces/20261117-1140-html-reply/evidence/ui-smoke.md`）；WebKit 探针：contenteditable/`execCommand`/outerHTML/CSP（`evidence/webkit-smoke.txt`）。
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
