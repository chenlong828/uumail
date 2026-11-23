---
layer: history
module: mail
status: frozen
updated: 2026-11-23
---

# W-M3-08 结果：HTML 回复撰写（REQ-0021 / SCN-0016）

日期：2026-11-17。状态：实现与验证完成；`SCN-0016` `verified`、`REQ-0021` `delivered`。

## 交付

| 任务 | 组件 | 落点 |
|---|---|---|
| `T-1117-20` | 0 | REQ-0021、SCN-0016、六份组件增量、决策记录 `history/decisions/2026-11-17-html-compose.md` |
| `T-1117-21` | CMP-DOMAIN | `Draft.bodyHTML`、`OutboxItem.bodyHTML`（可选默认 nil） |
| `T-1117-22` | CMP-STORE | v10 `outbox.body_html`；enqueue/select/map/claim RETURNING |
| `T-1117-23` | CMP-OUT | `MimeBuilder` `multipart/alternative`；空白 HTML 回单段 |
| `T-1117-24` | CMP-SCN-COMPOSE | `quotedHeader`、`HTMLText.quotedEmail/plainText/sanitizedForCompose/splitDocument`、全宽无缩进 |
| `T-1117-25` | CMP-PRES | `ComposeViewModel.bodyHTML/editorDidLoad/setEditorHTML/hasEdits`、`ComposeDocument`、`DisplayFormat.quoteHeader` |
| `T-1117-26` | CMP-APP | `ComposeView` 重写、`ComposeEditor`、`ComposeFormatBar`、取消确认、`GeometryReader` sheet 等宽 |
| `T-1117-27` | SCN-0016 | L1 3 正 1 反、全量测试、架构门、L2 UI 冒烟、WebKit 探针 |

## 验证

- `./Scripts/swiftw test`：**292 tests / 51 suites**，exit 0。
- `bash Scripts/check-architecture.sh`：4/4 PASS。
- `./Scripts/make-app.sh`：release 构建并发布 `dist/uumail.app`。
- L2 UI 冒烟（真实 App，真实账号/邮件）：sheet `1441×820` @ `(240,113)`；主窗口 `1920×987` @ `(0,30)`；detail 列 `1440` → 等宽（1pt 取整）；「回复」标题/`xmark`/格式栏/「取消」/引文抬头/全宽原邮件正文/顶部光标可见。见 `evidence/ui-smoke.md`。
- WebKit 探针（独立 app 包 + 生产 `ComposeDocument` 冒烟）：contenteditable、`execCommand('bold')`、outerHTML 回读、CSP 下内联脚本不执行。见 `evidence/webkit-smoke.txt`。
- 限制：`WebKitEditorSmokeTests` 单跑通过，但全量套件退出时 WebKit 清理偶发 SIGSEGV，未留在 CI 套件（源文件与结果在 `evidence/`）；未做自动化点击（`AXIsProcessTrusted() == false`），取消/发送按钮的点击行为由 `hasEdits` L1 与代码分支覆盖。

## 未决 / 后续

- 格式栏未做字体族/文字颜色/插入图片/表格/超链接（REQ-0021 非目标）；如需要另立需求。
- 编辑器打开时沿用阅读区「加载远程图片」的会话开关；切换开关不会重载已打开的撰写 sheet（下次打开生效）。
- `REQ-0020` 字号仍按既有实现生效；撰写 sheet 新增控件的 100% 基线由 `composeButton` 分支保持。
- 并发会话：本批开始后，另一会话在同一工作区提交了 `1759492`（T-1117-02，SCN-0003）并留下 `MailboxDeletion`/`MailboxViewModel`/`MailboxViewModelTests` 的未提交改动；本批任务号改用 `T-1117-20…27` 避让，提交只包含本批文件，不触碰对方改动。

## 提交与收尾

- 实现提交：`8b9334e feat(mail): HTML reply compose with format bar, cancel and pane-width sheet (T-1117-20..27, SCN-0016, REQ-0021)`。
- 同工作区的并发会话在 12:31 先提交了 `d888705`（T-1117-03），其中包含本批的 `CMP-PRES` 设计增量（因共享 index 被一起带入）；本批提交未再重复该文件。这属于并发写入的已知边界，内容已落盘。
- 提交后复跑：`./Scripts/swiftw test` 292 tests / 51 suites 绿；架构 4 门 PASS；`./Scripts/make-app.sh` 重新发布 `dist/uumail.app`。
- 未纳入提交：`dist/build-info.txt`（构建产物，保持工作区现有修改）、`task-spaces/`（过程与证据，含真实邮件截图，不入库）。
