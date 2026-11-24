---
layer: design
module: mail
status: verified
updated: 2026-11-24
flow: mail/read
scenario: SCN-0025
---

# SCN-0025 双击浮动阅读窗与就地回复

**结果**：用户在邮件列表里双击一封邮件（或选中后按 Enter / 空格），主窗口之上出现一个可移动的阅读浮窗，默认宽度等于阅读区、高度等于主窗口的 85%，里面是这封信封头、只读会议卡与正文，远程图片直接显示并有一行静态提示；浮窗工具栏「回复 / 全部回复 / 转发」把内容区就地切成撰写；打开即把该封标为已读。同一时刻只有一个浮窗，撰写中双击另一封不替换内容。

## 入口

- `CMP-APP#MailboxView`（行上的双击 / Enter / 空格入口、浮窗场景宿主、工具栏、静态提示）
- `CMP-APP#MessageRowClick`（列表行 AppKit 点击捕获：单击立即选中、双击打开；替代不触发的 SwiftUI 行手势）
- `CMP-APP#ReaderWindowController`（AppKit 宿主窗口：创建、复用、置前、尺寸与位置记忆）
- `CMP-PRES#ReaderViewModel`（按引用读取、信封头 / 会议卡 / 正文占位与补拉、即读、三种回复种子）
- `CMP-PRES#ReaderRouter`（单例路由：当前 ref、替换 / 撰写态拒绝 / 置前、主窗口几何）
- `CMP-SCN-READ#message(_:)`（按引用取单封）
- `CMP-APP#MessageBodyView` / `#MessageHeaderView` / `#MeetingCardView`（复用既有视图）

## 运行序

流程 `F-READ-11`：

1. 列表行由 AppKit ClickCatcher（`MessageRowClick`）接管鼠标：单击立即选中该行，双击打开；选中行按 Enter / 空格同样打开（不再使用 SwiftUI `.onTapGesture(count:2)`——该手势在 `List(selection:)` 行上不触发，是 2026-11-24 实测到的根因）。视图把该行的 `MessageRef`（folder + serverID）交给 `ReaderRouter`；打开动作本身不改变 `selectedListKey`（双击的第一下已由 ClickCatcher 选中该行）。
2. `ReaderRouter.open(ref:)`：
   - 浮窗不存在 → 从主窗口读取「阅读区宽度」与「窗口高度」，按 `宽 = max(480, 阅读区宽)`、`高 = max(460, min(主窗口高 × 0.85, 屏幕可用高))` 算出内容尺寸；位置按 `ReaderRouter.centeredOrigin(in: 主窗口 frame, size: 内容尺寸, visible: 屏幕可用区)` 取主窗口中心并夹在可见区内（用户从未拖动过位置时），交 `ReaderWindowController` 在**显示之前**建窗并 `orderFront`；
   - 已存在 → 写入新 ref，`setContentSize` 到同一口径（用户手动调整过则沿用其尺寸与位置；拖动后的位置以 `uumail.reader.centered` 跨启动保存），`makeKeyAndOrderFront`；
   - 路由处于撰写态 → 不改 ref、只置前，并置 `composeBlocked = true` 由视图提示「正在撰写中，请先取消或发送」。
3. `ReaderViewModel.load(ref)`：`ReadScene.message(ref)` 命中 → 生成信封头 / 会议卡；未命中 → `state = .missing`（窗内中文「找不到这封邮件」）。
4. 正文：`bodyIfCached(ref)` 命中 → 直接渲染；未命中 → 占位 + `ReadScene.open(ref)` 流式补拉，成功替换、失败给占位与重试（与 `SCN-0004` 同一条路径）。
5. 浮窗阅读态 `allowsRemoteContent = true`（仅本视图实例），并在信封头下方渲染静态提示「远程图片来自发件人服务器，已自动显示」。
6. 打开时置读：`ReadScene.markReadLocally(ref)` → 成功则不提示；失败 → `markReadErrorText` 中文提示（不阻断阅读）。本地 0→1 时 `ReadScene.writeBackMarkRead(ref)` 后台回写，失败静默。
7. 工具栏「回复 / 全部回复 / 转发」→ 用**本窗这一封**的消息与 `quotableHTML` 构造 `ComposeViewModel`（与主窗口同三个 seed 入口），`ReaderRouter` 进入撰写态，内容区换成 `ComposeView`（`preferredWidth` = 浮窗内容宽，编辑器仍按默认阻止远程资源）。
8. 取消 / 发送 / 存草稿 → 回阅读态（发送后显示与主窗口一致的状态文案）。
9. 关闭浮窗：阅读态直接关闭；撰写态先走「放弃这封邮件？」确认，取消则保留，确认则关闭且不入队。

失败路径：

- `ReadScene.message(ref)` 返回 nil（邮件已被删除或从未入库）→ 窗内「找不到这封邮件」+ 「关闭」，工具栏禁用；不空白、不崩。
- 正文补拉失败 → 占位 + 「点击重试」，与 `SCN-0004` 同文案；重试复用同一 `open(ref)`。
- 标已读本地失败 → 状态区中文提示，阅读继续；服务器回写失败 → 静默（沿用 `SCN-0013`），不重试。
- 撰写种子失败（无发件人地址）→ 与主窗口同一中文提示，不进入撰写态。
- 主窗口尺寸不可得（首启、窗口尚未布局）→ 退回 1280×720 口径计算，不阻塞打开。

## 不可变引用

- `SCN-0004`：正文缓存优先、补拉、截断提示与 CSP；浮窗复用同一条读取路径，不新增网络入口。
- `SCN-0012`：信封头字段、行序与 `.none` 语义；浮窗直接复用 `MessageHeaderPresentation`。
- `SCN-0023`：会议卡展示值；浮窗内只读（不渲染卡片上的按钮）。
- `SCN-0013`：主窗口远程图片**仍默认阻止**、会话内重置；浮窗的默认放行是显式例外，不写回该状态。
- `SCN-0016` / `SCN-0021`：撰写视图、格式栏、取消确认与等宽；浮窗复用同一视图，不改造写路径。
- `SCN-0006` / `SCN-0007`：回复 / 全部回复的收件人种子；浮窗只换消息来源，种子规则不变。
- 不新增 target、不改 schema；唯一新增读面是 `CMP-SCN-READ#message(_:)`（additive）。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0025-01` | 正 | 双击 / Enter / 空格三种入口各打开一次 → 浮窗出现且信封头主题、正文 HTML、会议卡（邀请样本）与列表该行一致；主窗口选中项不变；内容尺寸 = `max(480, 阅读区宽) × max(460, min(主窗口高×0.85, 屏高))`；用户 `setContentSize` 后再次打开沿用新尺寸（L2 窗口探针 + L1 尺寸计算） |
| `T-SCN-0025-02` | 正 | 工具栏「回复」→ 撰写态：收件人 = 原发件人、主题以「回复：」开头、引文含当前正文；取消 → 回阅读态且 outbox 无新行；「全部回复」抄送与「转发」收件人与主窗口同名动作一致（L1 种子 + L2 视图状态） |
| `T-SCN-0025-03` | 正 | 打开浮窗 → 该封本地 `isRead = true`、主窗口列表刷新为已读、回写被调用 1 次；浮窗阅读态 `allowsRemoteContent = true` 且静态提示存在；主窗口同一封的阅读区 `allowsRemoteContent` 仍为 false（L1 状态机 + L2 渲染文本/CSP） |
| `T-SCN-0025-04` | 反 | 撰写态双击另一封 → `ReaderRouter.currentRef` 不变 + 提示文案出现；撰写态关闭 → 「放弃这封邮件？」：取消 → 仍在撰写态且 outbox 无行；确认 → 窗关闭且不入队；全程主窗口可切换选中。另：ref 已删除 → 窗内「找不到这封邮件」且工具栏禁用（L1 + L2） |
| `T-SCN-0025-05` | 正 | 默认居中：L1 `ReaderRouter.centeredOrigin` 三组断言——主窗 (100,100,1200,800)、浮窗 600×400 → origin (400,300)；主窗贴屏幕边 → 夹到可见区 (300,500)；屏幕可用区偏移 (200,200,800,600) → (400,300) 不越界。L2 窗口 frame：首次打开时浮窗中心与主窗中心重合、四周在 `visibleFrame` 内（`ReaderCoordinator` 真实窗口；本批未做无头探针，发布前人工核对） |
| `T-SCN-0025-06` | 正 | 列表双击入口：行 0 `clickCount=1` 只选中 a、不打开；行 1 `clickCount=1,2` 选中 b + 打开 b；行 2 纯 `clickCount=2` 只打开 c；`window.sendEvent` 真实 hitTest 命中并选中。证据 `task-spaces/20261124-233500-feedback5/probe/message-row-click.txt`（`catchers=3`），探针源同目录 `MessageRowClickProbe.swift`，证据生成命令 `PROBE_OUT=$PWD/message-row-click.txt ./message-row-click-probe` |

## 状态

`verified`（2026-11-24 实现并验证）。

- 实现：`T-1124-17`…`T-1124-21`。`CMP-STORE#message(account:folder:serverID:)`（新文件 `MailStore+Lookup.swift`）与
  `CMP-SCN-READ#message(_:)`；`CMP-PRES` 的 `ReaderViewModel` / `ReaderRouter`；`CMP-APP` 的 `ReaderCoordinator`
  （AppKit `NSWindow` + `NSHostingView`；autosave 名原为 `uumail.reader`，2026-11-24 起改为 `uumail.reader.centered`，见下）与 `ReaderWindowView`。
- 证据（L1）：`Tests/PresentationTests/ReaderViewModelTests.swift`（路由尺寸纯函数与三态、缓存正文、即读写一次、
  缺失 ref、回复种子、预览不可引用、`allowsRemoteContent` 默认 true）。
- 证据（L2，机制级）：载体 `task-spaces/20261124-152611/probe/appkit-window.txt`（显示前定尺寸、复用同窗号）；
  点击判定 `task-spaces/20261124-152611/evidence/calendar-click/calendar-click.txt`（生产 `CalendarSelection` 被命中，
  1→选中、1,2→选中+打开）。真实窗口的拖动/缩放/多屏位置、撰写态关闭确认框、编辑器 CSP 未做无头探针，
  登记为发布前人工冒烟项（与 `R59` 同类），不写成已通过。
- 2026-11-24 增量（`REQ-0035` / 双击入口修复）：浮窗默认位置改为相对主窗口居中并夹在屏幕可用区，用户拖动后
  沿用保存位置（新 autosave `uumail.reader.centered`，不恢复旧右上角位置）；列表行改用 AppKit `MessageRowClick`
  ClickCatcher（单击选中、双击打开），替换在 `List(selection:)` 上不触发的 `.onTapGesture(count:2)`。
- 增量证据（L1）：`Tests/PresentationTests/ReaderViewModelTests.swift` 的 `centeredOrigin` 三组断言全过；
  （L2）`task-spaces/20261124-233500-feedback5/probe/message-row-click.txt`——`catchers=3`，行 0 单击只选中、
  行 1 的 `1,2` 选中+打开、行 2 纯双击只打开，`window.sendEvent` 真实 hitTest 命中。全量 461 tests / 77 suites、架构 4/4。
- 未覆盖（发布前人工项）：真实鼠标双击 / 拖动后重启沿用位置仍需发布前人工冒烟；`T-SCN-0025-05` 的 L2 窗口 frame 未做无头探针，不写成已通过。
- `T-SCN-0025-01` 的「真实窗口尺寸」由 L2 载体探针 + L1 尺寸函数共同支撑；`T-SCN-0025-04` 的确认框走人工项，
  `ReaderRouter` 的「撰写态拒绝替换」由 L1 覆盖。`T-SCN-0025-05` 的 L1 位置断言全过、L2 frame 留人工项；
  `T-SCN-0025-06` 由 `message-row-click` 探针覆盖。
