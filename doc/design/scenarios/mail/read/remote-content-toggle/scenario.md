---
layer: design
module: mail
scope: project:uumail
status: designed
updated: 2026-11-16
flow: mail/read
scenario: SCN-0013
---

# SCN-0013 远程图片开关并入工具栏

## 结果

用户打开一封正文已加载的邮件时，阅读区不再有独立一行的「加载远程图片」控件；该入口位于窗口顶部主工具栏，与新建、回复、全部回复、转发、刷新并列。入口默认关闭；打开后仅当前这封邮件临时放行远程图片，关闭或切换邮件后恢复默认阻止。禁 JS、`default-src 'none'`、白底与作者样式不变；开关状态不写偏好、不跨会话保留，也不新增第二处入口或第二条工具条。

## 入口

- `CMP-APP#MailboxToolbar`（新增 internal `ToolbarContent`：主工具栏「加载远程图片」按钮，图标 `photo`/`photo.fill`，`accessibilityValue` 为「已开启/已关闭」；`!canAllowRemoteContent` 时禁用）
- `CMP-APP#MailboxView`（把 `viewModel` 的放行状态/可用条件与 setter 接进 `MailboxToolbar`；把 `viewModel.allowsRemoteContent` 传给阅读区；不读 HTML、不拼 CSP）
- `CMP-APP#MessageBodyView`（移除正文 `.loaded` 分支里的 `Toggle("加载远程图片")` 行与 `@State allowRemoteContent`；只接收 `allowRemoteContent: Bool` 并转交 WebView；不再拥有放行状态）
- `CMP-APP#MessageWebView`（`allowRemoteContent: Bool` 入参、`lastRender` guard 与 CSP 重载语义不变）
- `CMP-APP#MessageBodyStyle.contentSecurityPolicy(allowRemoteContent:)`（既有纯函数；本场景不改两档策略内容）
- `CMP-PRES#MailboxViewModel.allowsRemoteContent`、`#canAllowRemoteContent`、`#setAllowsRemoteContent(_:)`（新增 public 状态/派生/受守卫的 setter；P2 待确认）
- `CMP-DOMAIN#Message`（只读；不新增字段，不读 HTML）
- 不涉及 `CMP-STORE`/`CMP-SYNC`/`CMP-SCN-READ`/`CMP-EAS*` 的新调用；开关不触网、不写库、不写偏好。

## 运行序

流程 `F-READ-06`：

1. 用户选中一封邮件，正文为 `.loaded`；窗口主工具栏渲染「加载远程图片」入口，默认关闭；阅读区内没有同名/同功能第二入口，也没有该控件独占的一行。正文侧收到的是 `viewModel.allowsRemoteContent`（初始 `false`）。
2. 无选中、正文 `.none`/`.loading`、或 `.failed` → 入口禁用；不得因入口触发正文补拉、同步或图片请求。
3. 用户点击入口 → `MailboxViewModel.setAllowsRemoteContent(true)` 先检查 `canAllowRemoteContent`（当前选中身份与正文所属邮件一致，且正文 `.loaded`）→ 置 `allowsRemoteContent = true` → `MessageBodyView` 以 `true` 调 `MessageWebView` → 当前 HTML 以放行档 CSP 重载（`img-src data: https: http:`）；禁 JS、`default-src 'none'`、白底与作者样式不变；不写偏好、不写库、不发额外命令。
4. 用户再次点击 → `setAllowsRemoteContent(false)`（关闭总是允许）→ 恢复阻挡档 CSP（`img-src data:`），当前正文重载；其它邮件不受影响。
5. 切换选中邮件 A→B → `selectedListKey` 变化时在同一状态更新内把 `allowsRemoteContent` 重置为 `false`；B 默认阻止远程图片。返回 A 仍为关闭（临时放行不保留）。旧邮件正文尚未被新正文替换的短暂窗口内，`canAllowRemoteContent` 也必须为 false，setter 为 no-op，A 的放行不得泄漏到 B。
6. 同一封邮件正文补拉完成/重渲染、或普通列表重载但选中身份未变 → 保持当前入口状态（仍属同一封）；主题切换、窗口重排 → 不重载正文、不改变入口状态；重开窗口/应用 → 默认关闭。
7. 入口变化只改放行状态与当前正文重渲染，不改正文 HTML/sanitizer、附件条、截断 banner、信封头、列表或侧栏。

失败路径：

- 正文加载失败（`.failed`）→ 入口禁用；重试成功后才可用，默认仍为关闭；失败状态不因入口产生第二次网络请求。
- 远程图片放行后图片请求失败（网络/证书/404）→ 正文照常显示与滚动，破图/空位可见，不弹错、不崩溃、不回退入口状态。
- 快速连续切换 A→B→C → 入口状态始终跟随当前选中；不得对已切走的邮件保持放行，也不得把旧状态带到新邮件。
- 旧正文未替换（选中 B 但仍显示 A 的 `.loaded` HTML）时强制调用 setter → `canAllowRemoteContent` 为 false，状态不变、不重载、不发请求。
- 主题切换/深色模式 → 工具栏入口随应用主题；正文白底与 CSP 不回归（`SCN-0010`/`SCN-0004`）。
- 无选中时强制调用放行入口 → 不改变任何邮件的 CSP、不发远程请求（防御性断言，视图不可达也应成立）。

## 不可变引用

- T5/D6：WKWebView 禁 JS；CSP `default-src 'none'`；远程资源默认阻止、单封临时放行；不做全局白名单、不做自动加载、不做内容检测。
- `MessageWebView` 的不透明白底、`NSAppearance(.aqua)`、`lastRender` guard 与主题不重载语义不变（`SCN-0010`）。
- 正文打开/缓存优先/补拉/截断/附件条/信封头语义不变（`SCN-0004`/`SCN-0012`）。
- 开关不是持久化偏好：不新增表/列、不写 `UserDefaults`/Keychain/网络；不新增 schema/协议/依赖/target。
- 工具栏其它动作（新建/回复/全部回复/转发/刷新）行为与可用条件不变；不新增第二条工具条或第二处远程入口。
- 正文 HTML/sanitizer 的内容不变；开关只影响 CSP 的远程资源一档。
- 工具栏拥挤由 `CMP-APP` 的紧凑图标按钮与默认窗口断言约束（R32）；入口在 900×560 下不得被折叠/溢出。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID |
|---|---|---|---|---|
| `T-SCN-0013-01` | 正 | L2 | 生产 `MailboxToolbar` + `NavigationSplitView` + 搜索框，离屏 `NSHostingController` 宿主，窗口 900×560：`NSToolbar` 中同时存在「新建/回复/全部回复/转发/加载远程图片/标记为已读/刷新」，全部在 `visibleItems`（未溢出）；「加载远程图片」恰好一个。正文宿主用生产 `MessageBodyView` 的 `.loaded` 形态（假 HTML）：正文子树没有同名 `Toggle`/独立一行控件（递归检查 `NSTextField`/`NSButton` 标题与 `NSToolbar` 外的控件，均无该标签）。 | `RemoteContentToolbarProbe.toggleLivesInWindowToolbar` + `RemoteContentBodyProbe.bodyHasNoRemoteToggleRow` |
| `T-SCN-0013-02` | 正 | L1 + L2 | 入口默认关（L1 `allowsRemoteContent == false`）；点击入口一次 → setter 收到 `true`、状态为开、正文以放行档重载；再点一次 → 收到 `false`、恢复阻挡档。L1 断言 `MessageBodyStyle.contentSecurityPolicy` 两档精确值；L2 用生产 `MessageWebView` 载入假 HTML，读回 CSP `meta` 的 `content` 与状态一致，并确认只重载当前正文：正文 body 的 HTML、附件条与头部不变（CSP `meta` 按两档变化是预期，不是正文内容变化）。 | `RemoteContentProbe.cspHasTwoExactTiers`（L1）+ `RemoteContentBodyProbe.toggleReloadsWithMatchingCSP`（L2） |
| `T-SCN-0013-03` | 正 | L1 + L2 | A 邮件开启放行 → 切到 B → B 入口为关、正文用阻挡档；返回 A 仍为关；重开宿主/重建状态后默认关；A 的放行不写偏好、不泄漏到 B。L1 另断言：选中 B 但正文仍为 A 的 `.loaded` 时 `canAllowRemoteContent == false`，强制 `setAllowsRemoteContent(true)` 为 no-op。L2 用重建的 `MailboxToolbar` 状态断言入口为关。 | `MailboxViewModelTests.remoteContentResetsOnSelectionChange` + `...remoteContentCannotLeakToStaleBody`（L1）；`RemoteContentToolbarProbe.selectionResetsToBlocked`（L2） |
| `T-SCN-0013-04` | 反 | L1 + L2 | 无选中 / 正文 `.loading` / `.failed` → 入口禁用；点击不改变状态、不重载、不发请求（L2 合成点击 + L1 强制调用）；正文失败不因入口崩溃；重试成功后入口恢复默认关且可用。 | `RemoteContentToolbarProbe.unavailableStatesDoNotFire`（L2）+ `MailboxViewModelTests.forcedRemoteAllowIsNoOpWhenUnavailable`（L1） |

证据层级：L1 单元测试 / L2 无头探针 / L3 截图 OCR / L4 GUI 自动化（AX）。本卡最低 L2，不上 L3/L4。

测试载体：

- **L2 `RemoteContentToolbarProbe`**：独立可执行文件，直接编译生产 `Sources/uumail/MailboxToolbar.swift`；用 `NSHostingController` + 离屏 `NSWindow`（900×560）承载 `NavigationSplitView` + `.searchable`，通过 `window.toolbar?.items` 读 `label`/`isVisible`，通过 `window.sendEvent` 合成点击驱动入口。设计探针已证该 seam：`task-spaces/20261116-223645/evidence/toolbar-probe/`（33 条断言 PASS，含禁用不触发）。探针必须**先断言条目存在且可见再点击**；状态变化后让 run loop 转一帧再点击禁用控件，避免读到旧渲染。不新增 target、不启动 app bundle、不截图/OCR、不依赖辅助功能授权。
- **L2 `RemoteContentBodyProbe`**：编译生产 `MessageBodyView.swift`/`MessageWebView`/`MessageBodyStyle.swift` 与最小 `Presentation`/`MailDomain` 文件（同 `HeaderProbe` recipe），宿主 `.loaded` 假 HTML；检查正文子树没有独立开关行，并在 Bool 变化后读回 CSP `meta`。不加载真实远程资源；假 URL 不进入证据。
- **L1**：`PresentationTests` 覆盖 `allowsRemoteContent` 默认/受守卫 setter/选中重置/陈旧正文 no-op；`MessageBodyStyle` 两档 CSP 精确值可由独立最小编译断言。
- 证据入 `task-spaces/<run>/evidence/`，使用假 HTML/假 URL；不写真实邮箱、主题或凭据。
- 本场景**不**重复认领 `SCN-0004` 的「远程图片实际不发请求」欠账（`T-SCN-0004-03`）；本场景只断言 CSP 两档值、放行状态传递、工具栏位置与重载，真实网络请求的自动化仍属既有欠账。
- 若某条 skip，必须有替身并登记，否则最多 `designed`，不能标 `verified`。

## 状态

`designed`（2026-11-16 设计落卡）。四元素：入口 `present`、运行序 `present`（含失败路径）、不可变引用 `present`、测试 `present`（3 正 1 反，`T-SCN-0013-01..04` 可执行，最低 L2）。

本卡依赖 `CMP-PRES` 新增 public 状态/派生/方法，属 P2 契约增量；确认清单见 `task-spaces/20261116-223645/design.md` §8.2 与 `CMP-PRES` 设计增量。**本卡不代签确认记录**；P2 确认后才进入实现。

`verified` 判据：`T-SCN-0013-01..04` 全 pass；`SCN-0004`/`SCN-0010` 回归不退化；无 skip（或有替身并登记）；工具栏在默认窗口下限 900×560 可见/可操作。设计阶段 L2 toolbar seam 已证，不等同于本卡验收。

## 与相邻场景的边界

- `SCN-0004` 邮件阅读：正文打开、缓存、补拉、截断、CSP/禁 JS；本场景只认领开关位置、当前邮件放行状态与重载，不重复认领正文渲染/网络阻断。
- `SCN-0010` 深色阅读白底：正文画布白底；远程开关从正文行移到主工具栏后仍随应用主题，工具栏项不强制白，也不改变白底机制。
- `SCN-0012` 阅读页信封头：头部在正文上方；移除开关行不得移除/遮挡头部；头部与开关互不影响。
- `SCN-0008`/`SCN-0014`：自动/手动已读；开关不改变已读规则。
- `SCN-0009` 键盘删除：删除隐藏/失败恢复不改；开关不处理删除。
- `SCN-0005` 附件下载：附件条位置与行为不变；开关不显示附件数量。
