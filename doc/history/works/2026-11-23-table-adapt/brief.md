---
layer: history
module: global
status: frozen
updated: 2026-11-23
run: 20261123-table-adapt
---

# W-M3-15 brief：正文宽表适配与附件条内联图过滤

## 目标

1. **REQ-0027**：HTML 正文里带显式宽度的表格（Outlook/Word 常见 `width="816"` / `width:612pt`）不再把整个文档撑宽；超出阅读区时按窗宽重排列宽，压不下去时只在表格内部横向滚动。页面宽度始终等于阅读区。
2. **REQ-0028**：附件条只列正文没有通过 `cid:` 引用的附件；这封周报的 57 个附件里 55 个是正文内联图，过滤后只剩 2 个真实文件。该条**取代** 2026-11-21 人工确认的「内联附件继续列在附件条」（`REQ-0025` 澄清③）。

## 用户样本与证据（2026-11-23）

- 样本：`资管研发AIGC双周报_20261122 及 研发管理双周报`（本机 `mail.sqlite`，正文 349,563 字节）。
- 正文：2 个 `<table>`；指标表 `width="816"`、`style="width:612.0pt"`、8 列固定列宽；64 张 `<img>`，38 张声明宽度 ≥900px（最大 1177px）；55 个唯一 `cid:` 图片。
- 附件：57 个，其中 55 个被正文 `cid:` 引用，真实文件仅 `研发管理双周报-资管研发部-1120更新.xlsx` 与 `image002.wmz`。
- 阅读区：窗口 1512pt，三栏 338 + 1174；字号偏好 120%。
- 当前 CSS 只有 `table { max-width: 100% }`。实测（WKWebView，同一 `baseCSS` + `data:` 内联图）：

| 字号 | CSS 视口 | 文档 scrollWidth | 越界元素 |
|---|---|---|---|
| 120% | 978 | 979 | 0 |
| 145% | 810 | 832 | 56 |
| 175% | 671 | 832 | 124 |
| 225% | 522 | 832 | 225 |

- 根因：表格 used width 不会低于 min-content width（8 列固定列宽合计 612pt = 816px）；`max-width` 被列宽下限压过，文档出现横向溢出，WebView 在阅读区右缘裁掉。
- 附件条：`AttachmentStripView` 用不可滚动 `HStack`；57 个 `Label` 被压缩到只剩回形针，整行超出阅读区被裁。
- 截图右侧工具栏/收件人也被裁，说明截图本身裁过；正文右侧截断有一部分来自截图，但表格溢出与附件条拥挤是独立实测问题。

## 验收标准

- `T-SCN-0021-01..04`（3 正 1 反）：120/145/175/225% 下 `document.scrollWidth == 视口宽度`；宽表所有列可通过压缩或表内滚动到达；窄表/无宽度表不受影响；反例（表格无显式宽度但内容超宽）不崩、不改变页面宽度策略。
- `T-SCN-0022-01..04`（3 正 1 反）：正文 `cid:` 命中的附件不进附件条；真实文件保留；歧义/未命中保留（不误删）；正文无 `cid:` 时附件条不变。
- 回归：`SCN-0004`/`SCN-0019`/`SCN-0020` 现有用例全绿；`./Scripts/swiftw test` 全量；架构 4 门；`make-app.sh` 构建成功。
- 不改 CSP、禁 JS、远程图片开关、schema、依赖、target。

## 任务表

| 任务 | 类型 | 组件 | 状态 | 出口 |
|---|---|---|---|---|
| `T-1123-01` | `design` | —（0 组件） | 已完成（2026-11-23） | REQ/SCN/决策/规格增量/任务表落盘 |
| `T-1123-02` | `change` | `CMP-SCN-READ` | 已完成（2026-11-23） | `InlineImageReferences.attachmentIDs(inHTML:attachments:)` + `InlineImageHTMLTests` 用例 |
| `T-1123-03` | `change` | `CMP-PRES` | 已完成（2026-11-23） | 正文 HTML 到达后过滤 `attachments`；`MailboxViewModelInlineImageTests` 三例 |
| `T-1123-04` | `change` | `CMP-APP` | 已完成（2026-11-23） | `MessageBodyStyle.baseCSS` 宽表规则；探针证据 |
| `T-1123-05` | `verify` | `SCN-0021`/`SCN-0022` | 已完成（2026-11-23） | 逐例 L1 + L2 布局探针；全量回归；状态翻转 |

## 装载清单

`MessageBodyStyle.swift`、`InlineImageHTML.swift`、`MailboxViewModel+Body.swift`、`MailboxViewModel.swift`、`AttachmentStripView.swift`、`MessageBodyView.swift`、`Tests/ScenesTests/InlineImageHTMLTests.swift`、`Tests/PresentationTests/MailboxViewModelInlineImageTests.swift`、`Tests/PresentationTests/Support.swift`、`doc/design/components/CMP-{APP,PRES,SCN-READ}/spec.md`、`doc/design/scenarios/mail/read/{inline-image-render,message-read}/scenario.md`。
