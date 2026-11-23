---
layer: design
module: mail
scope: project:uumail
status: verified
updated: 2026-11-17
flow: mail/send
scenario: SCN-0016
---

# SCN-0016 回复撰写页的 HTML 正文、格式栏与关闭

**结果**：用户在阅读页点「回复」「全部回复」「转发」或「新建」，撰写 sheet 打开 HTML 编辑器：原邮件 HTML 全宽出现在光标下方（无 `blockquote`、无左边距），上方格式栏可加粗/斜体/下划线/删除线/字号/对齐/列表/清除格式；发送后 HTML 客户端看到排版、纯文本客户端看到同一内容的纯文本。sheet 顶部有 `xmark`、底部有「取消」：无改动直接关闭，有改动二次确认，取消不写 outbox；sheet 宽度等于当前阅读窗格宽度。

## 入口

- `CMP-SCN-COMPOSE#replySeed`、`#replyAllSeed`、`#forwardSeed`（`quotedHeader` 参数 + `HTMLText.quotedEmail`；`Sources/Scenes/ComposeScene.swift`）
- `CMP-SCN-COMPOSE#send`、`#saveDraft`
- `CMP-STORE#enqueueOutbox`、`#outboxItem`、`#saveDraft`（`body_html` 列；v10）
- `CMP-OUT#MimeBuilder.build`（`multipart/alternative`；`Sources/Outbox/MimeBuilder.swift`）
- `CMP-PRES#ComposeViewModel`（`bodyHTML`、`editorDidLoad`、`setEditorHTML`、`hasEdits`；`Sources/Presentation/ComposeViewModel.swift`）
- `CMP-PRES#ComposeDocument`（编辑文档注入/回收；`Sources/Presentation/ComposeDocument.swift`）
- `CMP-PRES#DisplayFormat.quoteHeader`、`#longDate`
- `CMP-APP#ComposeView`、`#ComposeEditor`、`#ComposeFormatBar`、`#ComposeEditorHandle`
- `CMP-APP#MailboxView`（`GeometryReader` 量 detail、sheet 尺寸）

## 运行序

流程 `F-COMPOSE-02`：

1. 用户点回复/全部回复/转发/新建 → `MailboxViewModel.composeReply()` 等取 `quotableHTML`（仅阅读区已加载的正文，不触网），构造 `ComposeViewModel`。`DisplayFormat.quoteHeader` 把 `sender` + `receivedRaw` 格式化成 `2026年11月9日 20:11，X <…> 写道：`（无日期/无发件人时回退），传给 `ComposeScene.replySeed`。
2. `ComposeScene` 生成 `Draft`：
   - `bodyHTML` = `HTMLText.quotedEmail(header:originalHTML:)`：完整 HTML 文档；`<div id="uumail-reply-start"><br></div>` + 全宽引文容器（`margin-top/padding-top/border-top`，无 `margin-left`/`blockquote`）+ 12px 灰字抬头 + 清洗后的原邮件正文；
   - `body` = `HTMLText.plainText(from: bodyHTML)`，纯文本兜底与 HTML 同源。
3. 撰写 sheet 打开：`MailboxView` 用 detail 列的 `GeometryReader` 尺寸作为 `preferredWidth/preferredHeight`；`ComposeView` 宽 = `max(paneWidth, 480)`、高 = `460…820`；`ComposeEditor` 把 `bodyHTML` 交给 `ComposeDocument.editorDocument`：加 CSP（`default-src 'none'`、无 `script-src`；`img-src data:` 或 `data: https: http:`）、编辑器样式（id `uumail-editor-style`）、`<body contenteditable="true" spellcheck="true">`，并 `loadHTMLString`。
4. 加载完成：编辑器把光标放到 `uumail-reply-start`、滚到顶部；`capture` 读 `documentElement.outerHTML`，`ComposeDocument.emailHTML(fromEditorDocument:)` 去掉 CSP meta、编辑器样式和 `contenteditable`/`spellcheck`，回写 `ComposeViewModel.editorDidLoad`，作为取消基线。
5. 格式栏按钮 → `ComposeEditorHandle.perform` 先让 WebView 成为 first responder，再 `evaluateJavaScript`：`execCommand`（加粗/斜体/下划线/删除线/列表/对齐/清除）或 Range API 包 `<span style="font-size:Npx">`。页面自己的 `<script>` 被清洗 + CSP 双重阻断；`Cmd-B/I/U` 仍由 WebKit 原生支持。
6. 发送/存草稿：先 `capture`，`setEditorHTML`；`ComposeViewModel.draft` 用 `HTMLText.plainText` 从 HTML 重新生成 `body`（无 HTML 时保留手工 `body`，兼容 CLI/测试），`Draft.bodyHTML` 写入 outbox 的 `body_html`。
7. `Outbox` 投递：`MimeBuilder` 有 HTML → `Content-Type: multipart/alternative`，`text/plain` + `text/html` 两段各自 base64；无 HTML → 原单段 `text/plain`。`ClientId = outboxID`、只入队、投递状态机不变。
8. 取消/`xmark`：先 `capture`；`hasEdits` 比较收件人/抄送/主题/body/当前 HTML 与基线。无改动 → 直接 `onClose`；有改动 → `confirmationDialog("放弃这封邮件？")`：「放弃」只关 sheet，不写 outbox；「继续编辑」保持。
9. 宽度：`Geo` 量到 detail 列宽后 sheet 以该宽度居中；阅读窗格 resize 时 `.onChange` 更新下一次打开的宽度；窗口最小尺寸与阅读区布局不变。

失败路径：

- 原邮件正文未加载（`quotableHTML == nil`）：种子仍有合法 HTML 文档和抬头（或 `原邮件`），编辑器可写；不触网补拉。
- 原 HTML 含 `script`/`iframe`/`on*`/`javascript:`：`HTMLText.sanitizedForCompose` 先移除；CSP 再挡页面脚本（WebKit 探针：内联 `<script>` 不执行，`execCommand` 正常）。
- 编辑器未 `didFinish` 就点发送/取消：`capture` 返回 nil，保留当前 `bodyHTML`，不丢表单字段；随后动作按既有 `hasEdits`/`canSend` 判断。
- 发送/存草稿失败：sheet 不关，状态行显示中文；`hasEdits` 仍真，用户可继续编辑或取消。
- 纯文本收件人：收到 `text/plain` 段；HTML 客户端收到 `text/html` 段；两段内容同源。
- 旧 outbox 行（v10 前）：`body_html = NULL`，投递仍走单段 `text/plain`，不回归。
- 阅读窗格宽度尚未布局：用默认 720×560；sheet 不崩溃。
- 远程图片：默认 `img-src data:` 被 CSP 挡；用户先在阅读区打开「加载远程图片」再回复时，编辑器按会话开关放行 `https:/http:`。撰写打开不额外加载新请求（除正文/图片渲染）。

## 不可变引用

- `REQ-0007`/`SCN-0012`：主题前缀、`In-Reply-To`/`References` 规则、单回复 `To=发件人`、转发 `To` 为空；本景只改正文引用形态，不改收件人/会话头。
- `REQ-0012`/`SCN-0007`：全部回复的 To/Cc 合并、去重、排除当前账号；`replyAllSeed` 只把 `bodyHTML` 复制过去，地址逻辑不动。
- `SCN-0006`/`REQ-0006`：`send` 只入队、无网络等待；`Outbox` 租约/退避/幂等/永久失败语义、`Cc:` 头、`ClientId = outboxID` 均不变。MIME 只加一个兼容的 `multipart/alternative` 分支。
- `SCN-0004`/`SCN-0010`：阅读区仍白底、CSP、禁 JS、`lastRender` 键不变；本景不碰 `MessageWebView`。
- `SCN-0015`/`REQ-0020`：五档字号对撰写 sheet 字段/按钮/格式栏/编辑器 `pageZoom` 生效；100% 保既有基线；不改偏好 key、菜单、主题。
- `MailDomain` 兼容：`Draft.bodyHTML` 与 `OutboxItem.bodyHTML` 都是可选、默认 nil，旧调用/旧行/CLI 不变；`MailStore` 只做 additive v10。
- 不新增第三方依赖/target；不改 `Package.swift`；不把编辑器 CSP/样式/`contenteditable` 发出去；不把 `<script>`/事件属性发给收件人。
- 不改 `AddressList`、EAS 协议、`SyncEngine`、`ReadScene`、通知、附件、搜索、删除、已读语义。

## 测试

| ID | 类型 | 方案 | 可执行 ID（已验证） |
|---|---|---|---|
| `T-SCN-0016-01` | 正 | 回复种子：`quotedHeader` 带日期/发件人 → `bodyHTML` 是完整文档，含抬头、原 `<p>第一行<br>第二行</p>`，无 `<blockquote>`/`margin-left`；`body` 含抬头与 `第一行\n第二行`；转发用 `---------- 转发邮件 ----------`；全部回复保留 HTML 与 To/Cc。 | `ScenesTests/ComposeSceneTests.replySeedRules`、`.forwardSeedRules`、`.replyAllFillsSenderAndOriginalRecipients`；`PresentationTests/ComposeViewModelTests.replySeed` |
| `T-SCN-0016-02` | 正 | 发送：`ComposeViewModel.send()` 把 HTML 存进 outbox `body_html`，`body` 由 HTML 生成（`hello <b>world</b>` → `hello world`）；MIME 是 `multipart/alternative`，两段 `Content-Type` 与 base64 载荷齐全、boundary 闭合；旧 v10 前 outbox 行 `bodyHTML == nil` 仍可读。 | `PresentationTests/ComposeViewModelTests.sendCarriesHTML`；`OutboxTests/OutboxMimeTests.mimeMultipart`；`OutboxTests/OutboxDeliveryTests.deliversHTML`；`ScenesTests/ComposeSceneTests.replyAllUsesBackfilledCc`（旧行 nil） |
| `T-SCN-0016-03` | 正 | 编辑/取消/布局：编辑文档有 CSP/编辑器样式/`contenteditable`，`capture` 去除三者并保留正文与发件人样式；未改动的种子基线 `hasEdits == false`，改 HTML/地址后为 true，改回后 false；L2 UI 冒烟：真实 App sheet `1441×820`，主窗口 `1920×987`，detail 列 `1440`，引文抬头/全宽正文/「取消」可见；WebKit 探针：`contentEditable=true`、`execCommand('bold')` 返回 true、`outerHTML` 回读成功、CSP 下内联脚本不执行。 | `PresentationTests/ComposeDocumentTests.roundTrip`、`.emptyDraft`；`PresentationTests/ComposeViewModelTests.cancelBaseline`、`.replyNormalisedSeedIsNotDirty`；L2 UI 冒烟（2026-11-17，`history/works/2026-11-17-html-reply/evidence/ui-smoke.md`）；WebKit 探针（`evidence/webkit-smoke.txt`） |
| `T-SCN-0016-04` | 反 | 清洗与兜底：原 HTML 内联 `<script>`、`<iframe>`、`onclick`、`javascript:` → 种子 HTML 全部移除且保留 `safe`/`link` 文本；空/纯空白 HTML → MIME 退回单段 `text/plain`；新邮件不设 `body`/`bodyHTML` 时仍走原纯文本发送路径；远程图片默认 CSP 仅 `data:`，放行档为 `data: https: http:`。 | `ScenesTests/ComposeSceneTests.replySeedSanitisesOriginal`；`OutboxTests/OutboxMimeTests.blankHTMLFallsBack`；`PresentationTests/ComposeDocumentTests.remotePermission`；既有 `ComposeViewModelTests.sendEnqueues`/`sendFailureKeepsText` |

支撑测试：`ComposeSceneTests` 10 例（含原有地址规则）；`ComposeViewModelTests` 11 例；`OutboxMimeTests` 3 例；`OutboxDeliveryTests` 新增 `deliversHTML`；`MigrationTests`/pre-v9 fixture 覆盖 v10 后旧行 nil；`WebKitEditorSmokeTests` 曾在单跑中通过（见 `evidence/webkit-smoke.txt`），因测试进程退出时 WebKit 清理偶发 SIGSEGV，未留在 CI 套件内，只作为 L2 证据。

## 状态

`verified`（2026-11-17）。

验证证据（`./Scripts/swiftw test`，2026-11-17）：

| 测试 | 断言 | 结果 |
|---|---|---|
| `T-SCN-0016-01` | 抬头、原 HTML、无缩进、纯文本同源；转发/全部回复 | 通过 |
| `T-SCN-0016-02` | `body_html` 落库、MIME 双段与 base64、历史行 nil | 通过 |
| `T-SCN-0016-03` | 编辑文档往返、取消基线、L2 等宽与可见入口 | 通过 |
| `T-SCN-0016-04` | 清洗、空白 HTML 回退、远程图片两档、纯文本路径 | 通过 |

全量 **292 tests / 51 suites** 绿；`bash Scripts/check-architecture.sh` 4 门 PASS。L2 UI 冒烟（2026-11-17，真实 `dist/uumail.app`，真实账号/邮件，最小化记录）：sheet `1441×820` @ `(240,113)`，主窗口 `1920×987` @ `(0,30)`，detail 列 `1440`；可见「回复」标题、`xmark`、格式栏、底部「取消/存草稿/发送」、抬头与全宽原邮件正文、编辑器光标在顶部空行。截图与原始输出在 `history/works/2026-11-17-html-reply/evidence/`（不入库，避免真实邮件内容进仓库）。

实现沿革：`designed`（2026-11-17，T-1117-20）；数据/存储/MIME（T-1117-21…23）、场景/视图模型（T-1117-24…25）、编辑器/格式栏/取消/等宽（T-1117-26）、验证（T-1117-27）完成。

## 与相邻场景的边界

- 回复/全部回复的地址与主题归 `SCN-0007`/`REQ-0012`；本景只新增正文 HTML 与 `bodyHTML` 字段。
- 发送入队、投递、重试归 `SCN-0006`；本景只加 `multipart/alternative` 与 `body_html`，不改变投递状态机。
- 阅读区渲染/CSP/远程开关归 `SCN-0004`/`SCN-0013`；本景编辑器有独立的编辑页 CSP/样式，不修改 `MessageWebView`。
- 字号归 `SCN-0015`；本景只让新增控件跟随字号、编辑器 `pageZoom` 跟随，不改字号偏好与菜单。
