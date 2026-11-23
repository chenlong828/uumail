---
layer: history
module: mail
status: frozen
updated: 2026-11-23
---

# W-M3-08 回复撰写 HTML 富文本（P2 设计）

日期：2026-11-17。需求：REQ-0021；场景：SCN-0016。发起人已确认三项口径：

- 发信格式：`multipart/alternative`（text/plain + text/html），纯文本客户端仍可读。
- 取消：有改动时二次确认，无改动直接关闭。
- 范围：回复/全部回复/转发/新邮件统一使用 HTML 编辑器与格式栏。

## 现状

- `ComposeView`：纯文本 `TextEditor`，无格式栏、无取消入口、sheet 固定 `minWidth 640`。
- `ComposeScene.replySeed`：正文为 `"\n\n--- 原邮件 ---\n" + 纯文本`；`MimeBuilder` 只发 `text/plain`。
- `Draft`/outbox 只有 `body TEXT`；`Outbox` 投递时重建 `Draft`。
- 阅读区 `MessageWebView` 已有“白底 + CSP + 禁 JS”的 HTML 渲染，但不可编辑。

## 目标结构

| 层 | 单元 | 改动 | 数据/契约 |
|---|---|---|---|
| L1 | `MailDomain.Draft` | 加 `bodyHTML: String?`（默认 nil，兼容扩展） | HTML 正文是发信内容；`body` 是纯文本兜底 |
| L1 | `MailDomain.OutboxItem` | 加 `bodyHTML: String?` | 投递重建 Draft 时保留 HTML |
| L1a | `MailStore` | v10 `outbox ADD COLUMN body_html TEXT`；enqueue/select/map 带该列 | 既有行读出 nil，回退纯文本 |
| L1b | `Outbox/MimeBuilder` | 有 HTML → `multipart/alternative`；无 → 原单段 text/plain | 边界随机；两段 base64 |
| L2 | `Scenes/HTMLText` | 纯文本提取、引号/转发 HTML 文档、编辑文档注入与回收、脚本/iframe/事件属性清洗 | 生成的内容即发信内容，不含编辑器 CSP/样式 |
| L2 | `ComposeScene` | 引用种子改为 HTML：日期/发件人抬头 + 原邮件 HTML，**无缩进/无 blockquote**；纯文本 `body` 同步生成 | `quotedHeader` 由 Presentation 传入 |
| L3 | `Presentation/ComposeViewModel` | `bodyHTML`、`editorDidLoad/setEditorHTML`、`hasEdits`、Draft 写入 HTML | 编辑内容权威在视图模型；发送仍只入队 |
| L3 | `Presentation/ComposeDocument` | 编辑文档（CSP/样式/contenteditable）与回收（去 CSP/编辑器样式/contenteditable） | 不把编辑器 chrome 发出去 |
| L3 | `Presentation/DisplayFormat` | 引用抬头日期格式 `yyyy年M月d日 HH:mm` | — |
| L3 | `uumail/ComposeEditor` | WKWebView contenteditable + 格式命令；`pageZoom` 跟字号 | 页面脚本被 CSP 阻断，命令由 app evaluateJavaScript 注入 |
| L3 | `uumail/ComposeFormatBar` | 粗/斜/下划线/删除线、字号、对齐、列表、清除格式 | 只发 `execCommand`/Range 操作 |
| L3 | `uumail/ComposeView` | 格式栏、取消（有改动确认）、xmark、宽度跟随阅读窗格 | 取消不写库、不投递 |
| L3 | `uumail/MailboxView` | 用 GeometryReader 量 detail 窗格，sheet 宽高跟随 | 只读几何，不改阅读区 |

## 关键决策

1. **HTML 是发信真源，纯文本是投影**：`Draft.bodyHTML` 由编辑器内容决定；`Draft.body` 在发送时由 `HTMLText.plainText` 从 HTML 重新生成（测试里直接设 `body`、无 HTML 时仍走原路径）。
2. **不缩进**：引文容器只有 `margin-top/padding-top/border-top`，没有 `margin-left`、没有 `<blockquote>`；抬头是 12px 灰字，原邮件正文全宽。
3. **CSP 禁页面脚本**：编辑文档注入 `default-src 'none'; img-src …; style-src 'unsafe-inline'`，没有 `script-src`，所以发件人 `<script>` 不会运行；工具栏命令由 `evaluateJavaScript` 注入，不依赖页面脚本；原邮件 HTML 仍做标签/属性清洗（第二道防线）。远程图片沿用阅读区「加载远程图片」的会话开关。
4. **捕获式同步**：不在每次输入时回写 SwiftUI（避免光标跳动/重载）；发送、存草稿、取消前调用 `capture()` 取 `documentElement.outerHTML`，在 Presentation 层去掉编辑器 chrome 后写回 `bodyHTML`。
5. **取消基线**：编辑器 `didFinish` 后把“清洗后的 html”记为基线；`hasEdits` 比较 收件人/抄送/主题 + 当前 html 与基线。首次打开未改动 → 直接关闭；改过 → 二次确认。发送/存草稿成功后的关闭不经确认。
6. **宽度**：`MailboxView` 用 `GeometryReader` 量 detail 列，sheet 宽 = 该列宽（下限 420，避免极端窄），高 = 该列高（460…820）。不改窗口最小尺寸，不新增窗口。
7. **兼容**：`Draft.bodyHTML`、`OutboxItem.bodyHTML` 均为可选默认 nil；旧 outbox 行读出 nil，继续发纯文本；旧测试的纯文本路径保留。

## 失败路径

- 原邮件无正文/非 HTML：种子仍生成抬头 + 空引文；纯文本为空，HTML 有抬头。
- 原 HTML 含 script/iframe/on* / javascript:：种子清洗后丢弃；CSP 再挡一层。
- 编辑器未加载完成就点发送/取消：`capture()` 返回 nil，退回 `viewModel.bodyHTML`；不丢已输入（未加载时也无输入）。
- 发送失败/存草稿失败：sheet 不关，状态行显示原因；`hasEdits` 仍为真。
- 阅读窗格宽度量不到（GeometryReader 未布局）：用默认 720；sheet 不崩溃。
- 取消确认中点「继续编辑」：不关闭、不清空。
- 纯文本收件人：收到 text/plain 段；HTML 客户端看到 HTML 段。

## 测试计划

- L1 `ScenesTests`：引用种子含抬头/原 HTML、无 `blockquote`/`margin-left`；纯文本含原文；清洗掉 script/iframe/onerror/javascript:；空正文仍生成可读抬头（正/反）。
- L1 `PresentationTests`：`ComposeDocument.editorDocument` 注入 CSP/contenteditable/样式，`emailHTML(fromEditorDocument:)` 去掉 chrome 且保留正文；`hasEdits` 基线（未改动 false、改字段/HTML true）；发送把 bodyHTML 写进 outbox。
- L1 `OutboxTests`：有 HTML → multipart/alternative，含两个 part 与 base64 payload；无 HTML → 单段 text/plain（不回归）。
- L1 `MailStoreTests`：v10 后新行 body_html 可读写；旧行/无 HTML 为 nil。
- L2 冒烟（若图形会话可用）：真实 ComposeEditor 加载引文、执行加粗、capture 回读；sheet 宽度 = 阅读窗格宽度。不可用则登记限制，不用 L1 冒充。
