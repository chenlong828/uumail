---
layer: design
module: app
status: active
updated: 2026-11-16
component: CMP-APP
---

# CMP-APP AppShell 组件规格

## 模块卡

- 状态：`active`（视图只绑定视图模型；`UumailApp` 只做装配与窗口宿主）
- 单元：组件
- 层 / 类型：L3；UI 外壳
- 业务价值：让用户能看见并操作邮箱；没有它，同步能力只存在于命令行。
- 负责 X：窗口与导航、文件夹选择、邮件列表渲染、正文 WebView、撰写/配置表单、空态与失败态展示；T-1114-10 设计新增列表焦点 Delete/Backspace、前台状态转发（实测后改用 `NSApplication` 通知）、状态栏删除错误（2026-11-14 已实现，T-1114-18）。
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
- 尺寸预算：单文件 ≤300 行；当前 `uumail` 共 608 行（2026-11-16 实现后实测；旧记 493/528 为过期数字）。
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
  - 范围只限正文画布；附件条、远程图片开关、截断提示、侧栏/列表/工具栏仍随主题（Q6 A，2026-11-16 确认）。
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
  - `case .none where header == nil` 先判占位，其余 `.none` 与 `.loading` 合并；`.failed`/`.loaded` 分支内容不变（附件条、远程图片开关、截断 banner、`MessageWebView` 均在头部之下）。
- `MailboxView`：`MessageBodyView(header: viewModel.headerPresentation, bodyPresentation: viewModel.body, …)`；不再新增字段读取、不判空、不拼文案。
- 不改：`MessageWebView` 的 KVC 白底/`.aqua` 外观/CSP/禁 JS（`SCN-0010`）、附件条与下载、远程图片开关、截断 banner、工具栏、列表、搜索、主题菜单、`UumailApp`。
- R27 上限：主题 ≤2 行，发件人/时间各 ≤1 行，收件人/抄送各 ≤2 行；头部文本块 ≤170pt；默认窗口下限 900×560 下正文区域仍 ≥300pt 且 WebView 自身可滚动。设计探针实测长值夹具（200 字主题 + 12 收件人，无 Cc）文本块 107pt、320pt 面板下方余 204pt；含 Cc 最坏约 130pt。
- 预算：`MessageBodyView` 146 → 约 165、`MailboxView` 210 → 211、新文件约 45；单文件 ≤300、`Sources/uumail` 约 608 → 约 655。
- 验证：L2 `HeaderProbe`（离屏 `NSHostingView`；设计阶段已证 `.none`/`.loading`/`.failed` 三种正文态下的头部渲染与占位）。`T-SCN-0012-03` 的 `.loaded` 一段需实现节点把探针面板换成生产 `MessageBodyView`/`MessageBodyStyle` 并链 WebKit（`SCN-0010` 的 `AppearanceProbe` 已有离屏 WKWebView 先例）；头部在 switch 之外，`.loaded` 复用同一渲染路径，但不因此免测。探针编译命令与限制见 `task-spaces/20261116-212545/evidence/header-probe/`。`SCN-0004`/`SCN-0010` 回归覆盖正文白底与 CSP。
- 不做：可折叠/展开头部、每封布局切换、头像/发件人卡片、地址点击菜单、Bcc/Reply-To、真实 `Sent`。
