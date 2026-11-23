---
layer: history
module: mail
status: frozen
updated: 2026-11-17
---

# 回复撰写 HTML 富文本：P2 确认（D1–D8）与实现边界（2026-11-17）

## 背景

`REQ-0021`（回复撰写支持 HTML 富文本与完整关闭）在 2026-11-17 完成需求分析。改动跨 `MailDomain`（`Draft.bodyHTML`）、`MailStore`（v10 `outbox.body_html`）、`Outbox/MimeBuilder`（`multipart/alternative`）、`Scenes`（`HTMLText` 清洗/引文、`ComposeScene` 种子）、`Presentation`（`ComposeViewModel`、`ComposeDocument`）与 `uumail`（WKWebView 编辑器、格式栏、取消、sheet 宽度）；新增 public 可选字段与 public 方法、非核心表字段、跨文件/跨模块，按 `arch-design-spec` 定为 **P2**。

## 确认来源与范围

- 发起人在 2026-11-17 对话中直接回答三项设计选择（D1–D3），并确认实现范围；没有独立的邮件/IM 原文，本记录是唯一书面落点。
- 确认人：任务发起人（工作区所有者）；确认时间：2026-11-17；影响范围：`REQ-0021` / `SCN-0016` / `CMP-DOMAIN` / `CMP-STORE` / `CMP-OUT` / `CMP-SCN-COMPOSE` / `CMP-PRES` / `CMP-APP`。
- D4–D8 为实现期默认（发起人未逐项改写），按最小风险选择落盘；如后续要求变更，按 P2 重新定级并回设计。

## 决定

| # | 项 | 结论 |
|---|---|---|
| D1 | 发信格式（发起人确认） | `multipart/alternative`：`text/plain` 兜底 + `text/html`；仅 HTML 为空时退回单段 `text/plain`。两段同源。 |
| D2 | 取消行为（发起人确认） | 有改动时二次确认「放弃 / 继续编辑」；无改动直接关闭；取消不写 outbox。 |
| D3 | 编辑器范围（发起人确认） | 回复/全部回复/转发/新邮件统一使用 HTML 编辑器与格式栏。 |
| D4 | 引文布局（实现期默认） | 全宽、无缩进：不使用 `<blockquote>`、`margin-left`、左边框；抬头为日期 + 原发件人 + `写道：`，转发为 `---------- 转发邮件 ----------`。 |
| D5 | 安全（实现期默认） | 原邮件 HTML 先清洗（script/iframe/object/embed/form/input/button/textarea/select/meta/link/base、`on*`、`javascript:`），编辑页 CSP `default-src 'none'`、无 `script-src`；格式命令由 app `evaluateJavaScript` 注入。 |
| D6 | sheet 尺寸（实现期默认） | 宽 = detail 列宽（下限 480pt），高 = detail 列高（460…820pt 夹取）；`GeometryReader` 量取，窗口最小尺寸与阅读区布局不变。 |
| D7 | 持久化/兼容（实现期默认） | `Draft.bodyHTML`/`OutboxItem.bodyHTML` 可选默认 nil；`MailStore` v10 additive `body_html`；旧行读出 nil 仍发纯文本；CLI 不受影响。 |
| D8 | 远程内容（实现期默认） | 编辑器沿用阅读区的「加载远程图片」会话开关：关 → `img-src data:`；开 → `data: https: http:`；不新增开关。 |

## 影响

- `Draft`/`OutboxItem` 增加可选字段，`ComposeScene` 的 `replySeed`/`replyAllSeed`/`forwardSeed` 增加可选 `quotedHeader` 参数，`ComposeViewModel` 增加 `bodyHTML`/`editorDidLoad`/`setEditorHTML`/`hasEdits`；均为兼容扩展。
- 新增 `Presentation.ComposeDocument` 与 `uumail` 的 `ComposeEditor`/`ComposeFormatBar`（`CMP-APP` 内部文件，不新增组件/target/依赖）。
- MIME 新增 `multipart/alternative` 分支；无 HTML 时行为与旧版逐字节一致（既有 MIME 测试不回归）。
- 验证：`SCN-0016` 的 3 正 1 反（L1）+ 真实 App UI 冒烟（L2，宽度/可见入口）+ WebKit 探针（contenteditable/execCommand/CSP）；全量 292 tests / 51 suites、架构 4 门。WebKit 冒烟测试因退出时偶发 SIGSEGV 未留在 CI 套件，证据在 `history/works/2026-11-17-html-reply/evidence/`。
