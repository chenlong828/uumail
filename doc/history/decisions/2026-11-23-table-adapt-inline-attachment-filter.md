---
layer: history
module: mail
status: frozen
updated: 2026-11-23
---

# 正文宽表压缩适配与附件条内联图过滤（2026-11-23）

## 背景

用户反馈打开 `资管研发AIGC双周报_20261122 及 研发管理双周报` 时排版乱，并追问 HTML 表格撑宽页面。实证（WKWebView 探针 + 本机 `mail.sqlite`，2026-11-23）：

- 正文 349,563 字节，2 个表；指标表 `width="816"` / `width:612.0pt`，8 列固定列宽合计 816px，`table { max-width:100% }` 压不下去。
- 阅读区 1174pt；字号 120% 时 CSS 视口 978px，表格 816px 恰好放下；145/175/225% 视口 810/671/522px，表格仍 816px，文档 `scrollWidth` 832px，越界元素 56/124/225 个。
- 附件 57 个，其中 55 个是正文 `cid:` 引用的内联图，真实文件仅 xlsx + wmz；`AttachmentStripView` 用不可滚动 `HStack`，57 个 `Label` 压缩成一排回形针并裁掉。

## 决策

- **D1 表格采用压缩适配（人工确认，2026-11-23）**：只对显式宽度的表加 `display:block; max-width:100%; overflow-x:auto`。列宽按窗宽重排、图片随格缩放；压不下去时表格内部滚动。页面宽度始终等于阅读区。被否决：保版式 + HTML 外层包裹滚动（改动大、要滚动提示）；`table-layout:fixed`（均分列、不可读）；整页横向滚动（用户明确不要）。
- **D2 不改 CSP/不启用 JS/不改 `baseURL`**：纯 CSS，保持 T5 安全面。
- **D3 只改阅读区（默认确认，未经人工）**：撰写页引言用独立的 `ComposeDocument` CSS，同类问题另立，不在本批扩散。
- **D4 附件条隐藏正文内联图（人工确认，2026-11-23）**：`MailboxViewModel.attachments` 从「全量」收窄为「附件条展示集」；`ReadScene.attachments(for:)` 与内联渲染仍用全量。过滤复用 `InlineImageHTML.matches`；歧义/未命中保留，宁可多显示、不误删。
- **D5 新增 additive public 纯函数**：`Scenes.InlineImageReferences.attachmentIDs(inHTML:attachments:) -> Set<String>`。不新增类型依赖、不 import 新框架；`MailboxViewModel` 签名不变。

## 取代关系

本决策 **D4** 取代 `REQ-0025` 2026-11-21 人工确认的「③ 内联附件继续列在附件条」。取代理由：55 个内联图把附件条变成回形针墙，附件条不再承担「保存内联图」的职责；用户 2026-11-23 明确选择隐藏。若后续要恢复「保存内联图」入口，另立需求。

## 影响

- `REQ-0027`（`SCN-0021`）、`REQ-0028`（`SCN-0022`）。
- 代码：`Sources/uumail/MessageBodyStyle.swift`、`Sources/Scenes/InlineImageHTML.swift`、`Sources/Presentation/MailboxViewModel+Body.swift`；`AttachmentStripView`/`MessageBodyView`/`MailboxView` 零改动。
- 不改 schema、依赖、target、`Package.swift`、CSP、`baseURL`、禁 JS、白底、字号、远程开关。

## 风险与残余

- `display:block` 对带 `align`/浮动的显式宽度表可能改变环绕版式；本批样本的浮动表无 `width`，发布前真实样本冒烟。
- 无显式宽度但内容超宽（`nowrap` 长文本）的表仍可能溢出；图片已由 `img{max-width:100%}` 兜底。
- 内联图被隐藏后，用户不能再从附件条另存内联图；渲染失败时也没有兜底入口。属用户已确认的代价，登记待办（不在本批）。
- 过滤在 main actor 同步执行；本样本 349KB/55 cid 毫秒级；更大正文若实测有卡顿，再移到渲染任务并接受一次闪动。
- 撰写页引言表格未适配（D3）。

## 确认记录

- 2026-11-23 用户选择：修复范围 =「表格 + 附件条隐藏内联图」；表格策略 =「压缩适配」。人工确认 D1、D4；D2/D3/D5 为随之确定的设计约束（D5 为 additive public，已在此记录）。
