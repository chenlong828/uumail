---
layer: design
module: app
scope: project:uumail
status: verified
updated: 2026-11-17
flow: settings/appearance
scenario: SCN-0015
---

# SCN-0015 界面与阅读字体大小可调

## 结果

用户从 macOS 菜单栏的系统 View 菜单（中文系统显示为「显示」）下的「字体大小」子菜单选择 100%、120%、145%、175%、225% 中一档，当前项带勾选。应用窗口内自绘文字（侧栏、列表、状态栏、阅读区头部、附件条/banner、空态、配置页、撰写 sheet，以及数据库打不开时的根级错误页）与阅读区正文（作者 HTML 渲染内容）在本次操作内按该档位放大/缩小；不重开窗口、不重建承载用户状态的视图、不重新加载/补拉正文、不触网、不重置选中/滚动/搜索/草稿。选择写入本地偏好，退出重开仍生效；首次运行/偏好缺失/损坏/未知时回 100%。100% 与改动前渲染一致；175%/225% 下文字不重叠、无非预期裁剪、操作入口均可达；阅读区仍白底、禁 JS 与远程资源策略不变。

## 入口

- `CMP-APP#UumailApp`（`@State fontSize`、首帧读偏好、根环境注入；100% 只装 `\.fontSizePreference`、不装 `\.font`；根级数据库错误页改走 `EmptyState`；`Sources/uumail/UumailApp.swift`）
- `CMP-APP#FontSizeCommands`（系统 View 菜单的「字体大小」五项 Picker，与 `ThemeCommands` 的「主题」相邻；`Sources/uumail/FontSizeCommands.swift`）
- `CMP-PRES#FontSizePreference` / `#FontSizePreferenceStore`（`load()`/`save(_:)`、默认与回退；public `init()` 用 `.standard`，测试经 internal `init(defaults:)` 注入独立 suite；`Sources/Presentation/FontSizePreference.swift`）
- `CMP-APP#FontSizeStyle`（环境值 `\.fontSizePreference`、`View.scaledFont(_:)`（原 `.font(style)` 点）、`View.scaledInheritedFont(_:)`（原默认字体点，100% 不加修饰）、`FontSizePreference.font(for:)`；`Sources/uumail/FontSizeStyle.swift`）
- `CMP-APP#EmptyState`（100% 保留 `ContentUnavailableView`，>100% 自绘缩放空态；覆盖列表空态/同步中、阅读区选择/加载/失败态、`UumailApp` 根级数据库错误页；`Sources/uumail/EmptyState.swift`）
- `CMP-APP#MailboxView`、`#MessageHeaderView`、`#MessageBodyView`、`#ComposeView`、`#AccountSetupView`（字号消费者；不写偏好逻辑）
- `CMP-APP#MessageBodyStyle`（正文 `baseCSS`；100% 保持 13px/1.55，字号不改 CSS）
- `CMP-APP#MessageWebView`（正文渲染；`pageZoom` 在 `lastRender` guard 外应用；`lastRender` 仍只含 `allowRemoteContent|html`）
- `CMP-APP#MailboxToolbar`（系统工具栏；不新增字号控件，7 个动作与顺序不变）
- `CMP-APP#ThemeCommands`（相邻菜单；本景不改其三项与行为）

## 运行序

流程 `F-APP-02`：

1. 启动 → `FontSizePreferenceStore.load()` 读 `UserDefaults["appearance.fontSize"]`（`100`/`120`/`145`/`175`/`225`）。缺失、损坏或未知值 → 100；`UumailApp.init` 先读偏好再构造 composition，首窗口渲染前即应用，避免先 100% 后跳变。100% 只装 `\.fontSizePreference`，不装根 `\.font`（实测根 `.font(.body)` 会把默认两行文本从 32.0pt 压到 31.5pt，破坏恒等）。
2. 用户打开系统 View 菜单（中文「显示」）→「字体大小」子菜单与「主题」相邻，五项齐全；当前生效项带勾选。勾选在父菜单打开时刷新（R26）。
3. 用户选择一项 → binding 写入 `@State fontSize`；若与当前值不同，`FontSizePreferenceStore.save` 写一次偏好；根环境 `.fontSizePreference` 与 `.font` 变化使当前窗口与已打开邮件立即应用，无需重启。若选择当前项 → 不写偏好、不改状态、不闪烁。
4. 界面文字按档位缩放：默认文本/`TextField`/`Form` 在 >100% 吃根 `\.font`，100% 不装；原来源有显式 `.font(.caption/.headline/.body)` 的点走 `scaledFont`，原来源继承默认字体的点（阅读头部标签/值、列表主题、附件 label、TextEditor）走 `scaledInheritedFont`；按钮 100% 用原字符串标题、>100% 用显式缩放 label；空态 >100% 走 `EmptyState`（title 按实测 26pt 基缩放，不是 `.title2` 的 17pt 基）；根级数据库错误页同走 `EmptyState`。字体家族不变、文字矢量清晰；100% 为恒等档；布局按新字号重排，既有 `lineLimit` 可继续省略但操作入口不得消失。
5. 阅读正文按档位缩放：`MessageWebView.makeNSView` 首帧设 `pageZoom`，`updateNSView` 在 `lastRender` guard 外设置 `webView.pageZoom = scale`；默认 13px 文本与作者显式 `px` 字号文本、表格/图片都按真实渲染比例缩放；作者显式背景/颜色/字体家族、表格/图片相对布局保留；白底、CSP、禁 JS 不变；默认不重载文档、不触网。
6. 字号与主题独立：切字号不改 `preferredColorScheme`/白底；切主题不改 `pageZoom`/字号；两者都不重载正文、不重置选中/滚动/草稿。
7. 退出重开 → 读取同一偏好并应用到首帧；菜单勾选与实际生效值一致。
8. 175%/225% 下（默认窗口 900×560 与放大窗口）→ 文字不与相邻文本/控件重叠；头部 + 附件条 + banner 的元数据区整体 cap 220pt 并内部滚动；480pt 保守可用高下正文 WebView 视口实测 259pt（≥200 下限，达 260 目标）；120%/145% 不 cap（242.5/205pt，145 仍 ≥200）；列表行高由字体撑开、可滚动；状态栏文案尾部截断但「N 封」保可见；工具栏 7 个既有动作仍可达（实测全部可见，溢出时由系统 overflow menu 承接）；控件可点击、禁用态正确。
9. 快速连续切换档位 → 最终状态与最后一次选择一致；不重复写偏好、不闪烁、不重载正文；`pageZoom` 只改渲染属性。

失败路径：

- 偏好缺失/损坏/未知 → `load()` 回 100，不崩溃；菜单勾选与实际生效值一致。合法整数（如 int `175`）经 `UserDefaults` 字符串桥接按同档接受；`"purple"`、空串、`"175.5"`、`"250"`、int `999` 等回 100。
- 偏好写入失败 → 不回滚当前会话字号、不弹错；下次启动读旧值或默认值（`UserDefaults.set` 无同步失败信号）。
- 字号变化发生在正文加载中/已加载/失败态 → 界面 chrome 立即变化；已加载正文只改 `pageZoom`，不重新拉取；`.loading`/`.failed` 不因字号触发补拉或网络。
- 无窗口/窗口关闭时通过菜单切换 → 状态记录并应用到下次窗口，不崩溃。
- 175%/225% + 超长主题/多收件人/长地址 → 元数据区（头部+附件条+banner）超过 220pt 时内部滚动，正文视口 259pt（480 高），操作入口不被挤出；120%/145% 不 cap，145% 视口 205pt 仍在下限之上。
- 数据库打不开（`AppComposition.make()` 返回 nil）→ 根级错误页走 `EmptyState`；100% 与原 `ContentUnavailableView` 逐点相等，>100% 标题/描述缩放、不重叠；菜单仍可切换字号，不重试数据库、不写业务库。
- 225% + 工具栏 → 7 个动作仍可达；不得静默消失或变成不可点击。
- 225% + 深色主题 → 正文仍白底，字号缩放不改变白底/作者样式；状态栏/列表文字不与控件重叠。
- 字号变化与主题切换同时发生 → 两个偏好各自幂等，不互相覆盖，不重载正文。
- 强制调用字号 setter（防御性）→ 不写业务库、不发网络、不改变正文内容。

## 不可变引用

- `REQ-0015`/`SCN-0010`：正文画布始终白底；作者显式背景/颜色/字体家族保留；作者 dark-media 变体不生效；字号缩放不得改变阅读画布与 CSP；`pageZoom` 只缩放渲染，不改 CSS。
- `REQ-0017`/`SCN-0012`：头部行序/行数/字段语义不变；100% 下 R27 的数值预算不变（第 2 轮编译未改生产源实测最坏夹具 159.5pt；第 1 轮的 158.5pt 是 fixture/补丁副本拟合值，已更正）；>100% 头部可增长，175%/225% 与附件条/banner 一起 cap 220pt 保证正文视口，正文仍可滚动。
- `REQ-0018`/`REQ-0019`/`SCN-0013`/`SCN-0014`：工具栏 7 个动作、远程开关/手动置读行为不变；100% 下 900×560 无溢出；225% 下入口仍可达（系统工具栏不随字号缩放，实测 7 项全部可见）。
- `REQ-0016`/`SCN-0011`：主题菜单三项、即时切换、持久化、勾选不变；字号菜单相邻但不合并、不互相写偏好。
- `REQ-0004`/`SCN-0004`：正文打开/缓存/补拉/截断/CSP/禁 JS 不变；字号是 UI 偏好，不触发网络、不写业务库。
- 不改 `MailDomain`/`MailStore`/`Scenes`/`MailGateway` 契约、schema、协议；不新增依赖/target；不改 `Package.swift`。
- macOS 14 最低版本；只用 SwiftUI/AppKit/WebKit 标准能力；不引第三方。`WKWebView.pageZoom` 为 macOS 11+ 标准 API，本设计已实测。
- 系统菜单栏/窗口标题栏/系统对话框/文件面板/tooltip 由系统控制，不在本景；工具栏/搜索框为系统 chrome，不缩放但操作可达；设计覆盖清单见 `CMP-APP` 增量与 `task-spaces/20261117-071134/design.md` §6.2。数据库根级错误页是应用自绘文字，不是系统故障页，纳入本景。
- 100% 是恒等档：界面字体修饰、正文 `baseCSS` 13px/1.55、100% 生产头部 159.5pt、完整 body 视口 273pt（480 高）/353pt（560 高）与布局边距与改动前一致；100% 不装根 `\.font`、不包 cap；不得用 `scaleEffect` 位图放大。
- 「不重建视图树」按「不重建承载用户状态的视图（列表、正文 WebView、草稿编辑器、窗口）」执行；`EmptyState` 的 100% `ContentUnavailableView` 与 >100% 自绘分支只切换无状态占位子树，不重置选中/滚动/搜索/草稿（显式例外，见 design.md §5.2）。
- 不新增工具栏常驻字号控件；菜单是唯一入口。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID（拟） |
|---|---|---|---|---|
| `T-SCN-0015-01` | 正 | L1 + L2 | 首次启动无偏好 → 100%；「字体大小」菜单与「主题」相邻，五项文案 100%/120%/145%/175%/225% 齐全，100% 勾选；不新增工具栏字号控件；100% 下界面字体（caption 10pt/body 13pt/headline 13pt bold）、正文 `baseCSS` 13px/1.55、100% 生产头部 159.5pt、完整 body 视口 273pt（480 高）/353pt（560 高）与改动前一致（无额外缩放/行距；不装根 `.font`、不包 cap）；根级错误页 100% 与 `ContentUnavailableView` 逐点相等。 | `FontSizePreferenceStoreTests.defaultsTo100WhenUnset`（L1）+ `FontSizeProbe.menuShowsFiveLevelsAndChecks100`（L2，先打开父 View 菜单）+ `FontSizeProbe.percent100MatchesBaseline`（L2） |
| `T-SCN-0015-02` | 正 | L1 + L2 | 依次选 120/145/175/225 → 界面样本（侧栏/列表/工具栏标签（系统不缩放）/阅读头部/状态栏/配置页/撰写/空态/按钮/根级错误页）与阅读正文（默认样式 + 作者显式 `px` + 表格/图片夹具）按档位单调放大，实际比例与标称偏差 ≤8%（界面 1.200/1.450/1.750/2.250；空态 title 26→31.2/37.7/45.5/58.5、root 描述 13→15.6/18.85/22.75/29.25）；菜单勾选更新；当前窗口与已打开邮件立即变化；不重建承载用户状态的视图、不重载/补拉正文、不触网；切换邮件后新正文仍按档位渲染且只加载一次；选中/滚动/搜索/草稿不丢；字体家族不变；空态 100%→120% 只切换无状态占位子树，不重置用户状态。系统 chrome 不缩放项按覆盖清单显式登记，不静默漏。 | `FontSizePreferenceStoreTests.roundTripsEachLevel`（L1）+ `FontSizeProbe.fiveLevelsScaleInterfaceAndBody`（L2，生产 `scaledFont`/`MessageBodyStyle`/`pageZoom`）+ `FontSizeProbe.scaleChangeDoesNotReloadBodyOrResetState`（L2） |
| `T-SCN-0015-03` | 正 | L1 + L2 | 设 175% → 退出重开，首帧即 175%、菜单勾选 175%；设 225% → 切主题浅/深/跟随系统，字号与 `pageZoom` 不变、正文仍白、不重载；切字号 → 主题不变；重复选当前档不写偏好、不闪烁。 | `FontSizePreferenceStoreTests.persistsAndRestoresAcrossInstances`（L1）+ `FontSizeProbe.relaunchAndThemeIndependence`（L2） |
| `T-SCN-0015-04` | 反 | L1 + L2 | 偏好缺失/损坏/未知 → 100、不崩溃；写失败不回滚/不弹错；175%/225% 在 900×560 与放大窗口下文字不重叠、无非预期裁剪、工具栏 7 个动作可达（可见或溢出）、元数据区 cap 220 后正文视口 ≥200（480 高实测 259，目标 260）、145%/120% 不 cap 仍 ≥200（205/242.5）、列表/头部/状态栏不压正文、正文可滚动、控件可点击；根级错误页 225% 标题/描述缩放且不重叠；100% 与既有场景无回归（SCN-0010/0011/0012/0013/0014）。 | `FontSizePreferenceStoreTests.invalidValueFallsBackTo100`（L1）+ `FontSizeProbe.extremeScaleKeepsLayoutUsableAndControlsReachable`（L2）+ `FontSizeProbe.percent100AndExistingScenariosDoNotRegress`（L2） |

> 证据层级：L1 单元测试 / L2 无头探针 / L3 截图 OCR / L4 GUI 自动化（AX）。本卡最高 L2，不做截图与 AX。设计期证据分两类：**未修改生产源**（100% 头部/完整 body 基线、菜单、pageZoom、工具栏）与**生产源 + 设计 diff 副本**（225% 头部/175–225% body，副本见 `evidence/font-size-probe/round2/patched/`）。`EmptyState` 是新增文件，设计期用原型 `round2/patched/EmptyState.swift`，**实现期换生产 `EmptyState` 复跑**。225% 的生产源复跑是**实现期 L2**，不再写成“设计期已证生产”；详见 `design.md` §9 与 `round2/README.md`。
>
> `FontSizeProbe` 的 L2 覆盖：菜单（真实 SwiftUI App，父菜单打开后读 `NSMenuItem.state`，R26）；界面文本（`NSHostingView` + `.textSelection` 的 `NSTextField.font`）；生产 `MessageHeaderView` 100% 基线（未改生产源，159.5pt/44pt 列）与设计 diff 副本 225%（312.5pt、44×2.25=99pt、值列起点 115、不重叠）；**完整 body**（header + 2 附件 + banner + divider + 真实 `WKWebView`）在 320×480/560 的实测视口；空态/按钮/根错误页（设计原型 `EmptyState` 100%/120%/225% 字体与按钮 fitting；实现期换生产 `EmptyState` 复跑）；工具栏（生产 `MailboxToolbar` + `NSToolbar.items`/`visibleItems`，R32/R36/R37）。
>
> 非 `textSelection` 文本不在 AppKit 层暴露 `NSTextField`：用「生产同一 `scaledFont`/根环境 + 探针宿主逐样式测量 + 源码覆盖审计（每个 `.font(` 调用点要么缩放、要么在系统 chrome 清单内）」组合；不把 L1 映射冒充 L2。若实现期 seam 失效，由本卡声明 L3 并写理由，不能静默 skip 或降级。
>
> 数值口径：`159.5pt`/`273pt`/`259pt` 等是本机 macOS 26 设计期基线；实现/验证在目标最低 macOS 14 上按“改动前 vs 改动后”对比，断言 100% 相等与 175/225% 视口 ≥200，不把这些数字当跨系统常量。
>
> 测试替身：偏好逻辑用 `PresentationTests`（`@testable import Presentation`，经 internal `init(defaults:)` 注入独立 `UserDefaults` suite）；界面/菜单/正文/工具栏用独立 `FontSizeProbe`（编译生产源，离屏 `NSHostingController`/`NSWindow` + 生产 `WKWebView`，L2）。不新增 `uumail` 测试 target；不要求真实 app 截图或 AX。证据入 `task-spaces/<run>/evidence/font-size-probe/`。

## 与相邻场景的边界

- `SCN-0011` 主题：两套偏好、两个相邻菜单；本景只回归主题三项/即时/持久化/勾选，不认领主题断言。
- `SCN-0010` 白底：只回归「字号变化后正文仍白、作者样式保留、不重载」；pageZoom 不改变 CSP/画布。
- `SCN-0012` 信封头：只回归 100% 下 R27 预算与行序/行数；放大档位的「头部可增长但 cap 220、不压正文」由本景负例承担，不改 `SCN-0012` 的数值断言。
- `SCN-0013`/`SCN-0014` 工具栏：只回归 100% 下 7 项可见/无溢出与行为；225% 下「7 个动作可达」由本景负例承担，不改两卡的行为断言。
- `SCN-0001`/`SCN-0006`：字号变化后配置页/撰写 sheet 外观与输入不丢，回归；不新增断言。
- `SCN-0004` 阅读：只回归打开/缓存/补拉/CSP 不被字号触发；不新增断言。

## 设计要点（落卡依据）

- 界面：`FontSizePreference.font(for:)` 在 100% 返回原语义字体；其余档用 `NSFont.preferredFont(forTextStyle:)` 的 descriptor 缩放 point size，保持家族/字重。100% 只注入 `\.fontSizePreference`、不注入 `\.font`；原来源有显式 `.font` 的点用 `scaledFont`，原来源继承默认字体的点用 `scaledInheritedFont`（100% 不加修饰）。L2 实测 100% 与改动前 point size/family/traits 全等、生产头部 159.5pt；225% body 29.25pt、比例 2.250。
- 正文：`pageZoom` 在 `lastRender` guard 外；不把字号纳入 `lastRender` 键（纳入会重载）。实测 1.0→2.25 导航增量 0、作者 px 与默认文本同比、滚动保持、白底/CSP 不变。
- 空态/按钮/根错误页：`ContentUnavailableView` 与字符串标题 `Button` 不响应环境字体（实测尺寸比 1.00）；`EmptyState` 在 100% 保留原组件（逐点相等）、>100% 自绘（title 26×scale、description 13/10×scale）；按钮 100% 字符串标题、>100% 显式缩放 label；`UumailApp` 根级数据库错误页同走 `EmptyState`。
- 175%/225%：头部 + 附件条 + banner 的元数据区 cap 220pt（100% 生产头部 159.5pt、120/145% 不 cap）；标签宽 `44×scale`；480 高正文视口实测 259pt（A 变体只 cap 头部为 147.5pt，已否决）；状态栏计数 `.layoutPriority(1)`；工具栏不缩放、7 动作实测可见。

## 状态

`verified`（2026-11-17，T-1117-01 验证，收尾按 `review.md` §8 清单翻转；`T-1117-01` 为无人值守默认任务号、未经人工）。原 `designed`（2026-11-17，设计节点落卡；同日第 2 轮按评审 fail 修订）。四元素齐：入口、运行序、不可变引用、测试均 `present`；`T-SCN-0015-01..04` 为 3 正 1 反可执行 ID；最低 `L1 + L2`，不要求 L3/L4。第 2 轮修订：生产头部 159.5pt（更正 158.5）、175/225% 元数据 cap、完整 body 视口实测、`EmptyState`/按钮/根错误页样本、100% 不装根字体、空态子树例外。

`verified` 判据：`T-SCN-0015-01..04` 全 pass（3 正 1 反）；L1 6/6、L2 342/0（`fontsize-web` 38 PASS，含 R40 图片/表格 8 条）、全量 `275 tests / 50 suites`、架构 4/4；`SCN-0010`/`SCN-0011`/`SCN-0012`/`SCN-0013`/`SCN-0014` 回归无退化；无未登记 skip。证据：`task-spaces/20261117-095147/test.md` §2–§6、`review.md` §8/§12 与 `evidence/`。
