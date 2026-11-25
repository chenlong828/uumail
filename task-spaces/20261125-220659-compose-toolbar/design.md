---
layer: works
module: mail
scope: project:uumail
status: active
updated: 2026-11-25
---

# W-M3-21 设计：撰写页顶栏（发送置顶、关闭存草稿）

## 现状

`Sources/uumail/ComposeView.swift`（174 行）是挂在阅读窗格上的 sheet：头部「标题 + 右上 `xmark`」，底部「取消 / 状态 / 存草稿 / 发送」。用户要求按 macOS「邮件」的撰写窗口语言重排：操作都在顶部，发送在右上，且只需要一个大的蓝色发送按钮；关闭时询问是否存草稿，关闭按钮默认是取消（不丢内容）。

## 设计

- 顶栏（一行）：左侧自绘红色关闭圆点（13pt，`xmark`，白色），中间标题（新邮件/回复/全部回复/转发，居中），右侧唯一动作「发送」（`borderedProminent` + `controlSize(.large)` + `.defaultAction`）。底部操作条与旧 `xmark` 删除。
- 状态行：`statusText` 非空时在顶栏下方单独一行（caption + 图标 + 语义色），编辑态零高度；发送失败不挤压标题/按钮。
- 关闭：红色关闭点点击或 Esc（该按钮承载 `.keyboardShortcut(.cancelAction)`，与旧「取消」按钮同一机制）→ 先 `capture` HTML；`hasEdits == false` 直接 `onClose`；有改动弹 `confirmationDialog("存储草稿？")`：`存草稿`（`saveDraft()` 成功才关，失败留在 sheet）、`放弃`（destructive，直接关）、`继续编辑`（`role: .cancel`，默认 Esc）。
- 发送：`capture` → `viewModel.send()`（只入队）→ 成功 `onClose`；`canSend`/`isSending` 禁用条件不变。
- 字号/宽度：sheet 宽 = `max(阅读窗格, 480)`、高 `460…820` 不变；标题 `.scaledFont(.headline)`；按钮沿用「100% 字符串标题、>100% 显式缩放 label」；标题在顶栏内居中，按钮固定，225%×480 实测不重叠。
- 不改：`ComposeViewModel`/`ComposeScene`/`Outbox`/schema/依赖/target、收件人表单与候选浮层、格式栏、编辑器、取消确认的数据语义、快捷键语义（Enter 发送、Esc 关闭）。

## 组件与契约

- 只改 `CMP-APP` 的 `ComposeView.swift`；无 public 契约、schema、依赖、target 变化；`CMP-PRES` 的 `statusText`/`canSend`/`hasEdits`/`saveDraft`/`send` 全部复用，零改动。
- 基数为 1:1（一个 sheet 一个 `ComposeViewModel`）；关闭/发送/存草稿仍是三个独立动作，互不合并。

## 走查

1. 正常：填写收件人 → 点「发送」或 Return → capture → 入队 → 关 sheet。
2. 关闭（有改动）：点红点/Esc → capture → 弹窗；「存草稿」成功关闭、失败留在 sheet 且状态行显示原因；「放弃」直接关；「继续编辑」保留。
3. 关闭（无改动）：直接关，不弹窗。
4. 窄宽/225%：顶栏标题居中在两枚控件之间；状态行单独一行，不把按钮挤出窗口；发送 disabled 时仍是灰色。
5. 编辑器未就绪：capture 返回 nil → 用当前 `bodyHTML`，不丢字段、不崩溃。

## 定级与风险

- **P3**：单文件 UI 布局/交互，无公共契约、schema、数据所有权、依赖或热路径变化。
- 风险：红色关闭点是自绘控件（sheet 无系统红绿灯），靠 `.help("关闭（Esc）")` + 无障碍标签说明语义；若后续要真红绿灯，需把撰写从 sheet 改为独立 `NSWindow`，另立增量。
- 未做：Cmd+S 存草稿、发送失败横幅、图标化发送（椭圆蓝按钮）。

## 验证

- L1：全量测试（`./Scripts/swiftw test`）不退化；`ComposeViewModelTests` 的 `canSend`/`hasEdits`/`send`/`saveDraft` 覆盖数据语义。
- L2：`probe/ComposeToolbarProbe.swift` 编译生产 `ComposeView.swift` 及依赖，托管在 `NSWindow`，`screencapture -l` 取证：900×760、480×760、225%×480×760；断言顶栏控件位置/无底栏/无第二个关闭入口/标题居中不重叠。
