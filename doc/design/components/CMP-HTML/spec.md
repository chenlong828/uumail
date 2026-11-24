---
layer: design
module: global
scope: project:uumail
status: active
updated: 2026-11-24
component: CMP-HTML
---

# CMP-HTML 文本 ↔ HTML 纯工具

- **单元 / 层**：组件 / L1 工具（无状态、无 I/O）
- **业务价值**：为阅读与撰写提供同一套「纯文本 → 可读 HTML」「引用原文」「清理可编辑文档」「`cid:` 内联图替换」规则。
  没有它，两处会各写一套转义/清理规则，正文与引用就会走样或带进脚本。
- **负责 / 不负责**：
  - 负责：HTML 转义与 `pre-wrap` 换行、纯文本转 HTML、引用原文拼装、撰写文档清理与空文档、`cid:` 源收集与 `data:` 替换规则、
    「正文已内联引用的附件集合」判定。
  - 不负责：附件下载/缓存（`CMP-SCN-READ`/`AttachmentFiles`）、CSP/渲染（`CMP-APP`）、正文持久化（`CMP-STORE`）。
- **数据所有权**：无。纯函数，无持久化、无缓存。
- **公开契约**：
  - `HTMLText`：`escape` / `fromPlainText` / `plainText(from:)` / `quotedEmail` / `sanitizedForCompose` / `emptyEmailDocument`。
  - `InlineImageHTML`：`sources(inHTML:)` / `normalizedCID(_:)` / `matches(inHTML:attachments:)` / `dataURL(for:)` /
    `replacingSources(inHTML:with:)`；`Match` 公开 `source` 与 `attachment`。
  - `InlineImageReferences.attachmentIDs(inHTML:attachments:)`：正文已内联引用的附件集合（附件条过滤用）。
- **依赖**：`Foundation`、`MailDomain`（只用 `Attachment` 值类型）。不依赖任何其它组件。
- **尺寸预算**：≤420 行；当前 **391**（`HTMLText` 221 + `InlineImageHTML` 170，2026-11-24 `wc -l`）；
  单文件 ≤250。
- **单独运行**：`./Scripts/swiftw test --filter HTMLSupportTests`；构建 `./Scripts/swiftw build`。
- **验证计划**：
  - `HTMLSupportTests/InlineImageHTMLTests`：`cid:` 大小写/`CID:` 前缀、引号与未加引号属性、注释/其它属性不误扫、
    唯一匹配替换、`data:` URL 与 MIME。
  - 既有阅读/撰写断言经 `ScenesTests`/`PresentationTests` 回归（转义、引用、编辑文档）。
- **删除测试**：删掉后阅读与撰写的转义/引用/内联图规则要在两个上层组件各写一份，且很快分叉 → 真边界。
- **来源**：`history/decisions/2026-11-24-risk-review-decisions.md` D1（`Scenes` 超 1200 且已有两个 HTML 纯工具，拆到纯工具组件）；
  原文件在 `Sources/Scenes/{HTMLText,InlineImageHTML}.swift`，2026-11-24 迁至新 target `HTMLSupport`。
