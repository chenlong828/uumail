# W-M3-17 设计走查（T-1124-16，2026-11-24）

## 1. 输入

- 需求：`REQ-0031`（浮窗 + 就地回复）、`REQ-0032`（日历去详情、双击打开）、`REQ-0033`（列表 30 天窗口），均 `accepted`。
- 口径冻结：`doc/history/decisions/2026-11-24-floating-reader-window.md` D1–D13。
- 场景分析：`task-spaces/20261124-152611/scenario-analysis.md` §5（三张场景草案）。

## 2. 探针（R63 / R68 的证据）

| 探针 | 结论 | 证据 |
|---|---|---|
| SwiftUI `Window(id:)` 载体 | 单例成立（两次 open 同窗号）、`.defaultSize` 生效、可在开窗后 `setFrame`；但**运行时算出的初始尺寸无法在显示前生效**（请求 480×680 → 实测 660×622 / 900×622） | `probe/window-carrier.txt`、`probe/content-sized.txt`、`probe/content-sized-ressize.txt` |
| AppKit `NSWindow` + `NSHostingController` | `orderFront` 前定尺寸：内容 480×707 精确；复用同窗号；二次打开只改内容尺寸，reader 窗口数 1 | `probe/appkit-window.txt` |
| 日历单击/双击判定 | AppKit 点击捕获按 `clickCount` 映射：1→仅选中、1,2→选中+打开、2→仅打开；在 `NSHostingView` 内可被命中并驱动 | `probe/click-catcher.txt` |

**定案**：浮窗载体 = AppKit `NSWindow`（CMP-APP）；日历块 = AppKit 点击捕获（CMP-APP `CalendarSelection.swift`）；
列表行双击用 SwiftUI `.onTapGesture(count: 2)`（List 选择不受影响），Enter/空格走 `.onKeyPress`。

## 3. 组件与契约

| 组件 | 增量 | 公开面 |
|---|---|---|
| `CMP-STORE` | `message(account:folder:serverID:)`、`messages(account:folder:since:)`（`julianday` 窗口、不封顶） | additive |
| `CMP-SCN-READ` | `message(_:)`、`messages(folderID:since:)` 透传 | additive |
| `CMP-PRES` | 新 `ReaderViewModel` / `ReaderRouter` / `ReaderGeometry`；`MailboxViewModel.makeReaderModel()`；列表改 30 天窗口 | P2 additive |
| `CMP-APP` | `ReaderWindowController`、`ReaderWindowView`、`CalendarSelection`；列表双击/Enter/空格；日历去详情、选中与工具栏；浮窗默认放行远程图片 + 提示 | 视图层 |
| `CMP-ROOT` | **不改**（188/200 行）；coordinator 在 `UumailApp` | — |

依赖方向不变：APP → PRES → SCN-READ → STORE；新增文件不引入第三方依赖、不改 schema、不改 `Package.swift`。

## 4. 关键取舍

1. **不用 SwiftUI Window**：默认尺寸是需求的核心可感知承诺，SwiftUI 载体只能先开窗再改尺寸；AppKit 载体可在显示前定型。
2. **窗口记忆用 `setFrameAutosaveName`**：跨启动记住尺寸与位置，首次无保存值时才按「阅读区宽 × 85%」计算（`appkit-window.txt` 同时证明 `isRestorable=false` 不会和恢复机制打架）。
3. **日历不用 SwiftUI 手势**：`Button` 会吞单击，`.onTapGesture(count:1)+count:2` 会双触发；AppKit 点击捕获按 `clickCount` 判定，探针可验证。
4. **列表双击不改选择模型**：单击仍由 `List(selection:)` 负责，双击只是额外打开；键盘 Enter/空格复用同一条打开路径。
5. **即读不新增写路径**：复用 `markReadLocally` + `writeBackMarkRead`，失败语义与 `SCN-0013` 完全一致。
6. **远程放行只在浮窗实例**：`ReaderWindowView` 传 `allowRemoteContent: true`；主窗口与撰写编辑器不传，避免状态扩散（R66 的可逆边界）。

## 5. 风险处置

- R62（扩读契约被绕过）：P1 已确认；按 `CMP-STORE` → `CMP-SCN-READ` 顺序落两个 change 任务，不在视图层用大 limit 兜底。
- R63（第二窗口行为未验证）：探针已证；载体定 AppKit，关闭入口式处置。
- R64（双草稿）：路由撰写态拒绝替换 + 关闭确认；`T-SCN-0025-04` 反例覆盖。
- R65（旧邀请空窗）：`message(_:)` 到「找不到这封邀请邮件」；正文补拉失败给占位 + 重试。
- R66（远程图片隐私）：仅浮窗放行 + 静态提示 + 不扩 ATS 例外；逆转条件见决策记录 D6。
- R67（列表 30 天变慢）：`julianday` 窗口 + 不封顶；5k 阈值 1s，`SCN-0026` 的 `T-...-03` 钉住；超限回设计。
- R68（日历手势冲突）：点击捕获探针已证；仍保留「探针不过则只保留 Enter」的回退。
- R69（双击即已读）：已接受；`isRead` 只升不降，撤销需另立需求。

## 6. 遗留

- 真实拖动/缩放、多显示器位置、窗口恢复、VoiceOver 顺序：发布前人工冒烟项。
- 预算欠账（并发审计 R70/R71/R72 同日已登记）：`MailboxViewModel` 416/400、`MailboxView` 305/300、`Scenes` 1294/1200。
  本批处置：`MailboxViewModel` 不增长（factory 进 `+Compose`）、双击入口进新文件 `MailboxView+Reader.swift`、`CalendarView` 减到 ≈280；
  其余欠账不夹带拆分，按 R70/R71/R72 另立任务。
- 列表行双击用 SwiftUI 手势，未做注入式 L2 探针（无法无头合成 SwiftUI 事件）；实现期以真实点击冒烟 + `T-SCN-0025-01` 的窗口部分补偿，若失败改用 AppKit 点击捕获（同日历方案）。
