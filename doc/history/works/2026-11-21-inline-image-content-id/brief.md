---
layer: history
module: mail
status: frozen
updated: 2026-11-23
---

# 2026-11-21 内联图片 ContentId 持久化（W-M3-14）

> 已归档（2026-11-23）。现行真相见 `design/components/CMP-EAS|CMP-DOMAIN|CMP-STORE|CMP-SCN-READ/spec.md`
> 的 2026-11-21 设计增量与 `history/decisions/2026-11-21-inline-image-content-id.md`。

**现象**：阅读页正文内联图片不显示；附件条双击能预览同一张图。

**根因**：正文 `cid:` 是不透明 `_Foxmail.1@<uuid>`；网关 `Sync` 的 `Attachments` 返回 `ContentId`（与 cid 逐字一致）
与 `IsInline=1`，但客户端只解析 `DisplayName`/`FileReference`/`EstimatedDataSize`，`Attachment` 与 `attachments` 表
都没有 content-id，`InlineImageHTML.matches` 只能按文件名匹配 → 0 match → 保留 `cid:` → CSP 拦截。

**决定（用户 2026-11-21 确认）**：走 C1；接受 schema v11 + `Attachment.contentID`；旧邮件重开/重同步后生效；
内联附件继续列在附件条；需求重开并改设计。P1。

**范围**：`EASClient` 解析 `ContentId`、`Attachment.contentID`、`attachments` v11、`InlineImageHTML.matches` 优先匹配。
**非目标**：`IsInline` 不解析/不落库；不改附件条交互；不做旧数据回填（v11 游标回绕让首轮重拉窗口）。

**验收**：`T-SCN-0019-05`（不透明 cid 按 ContentId 命中）；原有 3 正 1 反不回归；全量 `368 tests / 58 suites`、架构 4/4。

**任务表**：见 `plan/roadmap.md` §W-M3-14（`T-1121-02`…`T-1121-06`）。

**证据**：`evidence/README.md`（cid 形态、ContentId 对应关系与代码事实；原始正文/Sync 响应已删除）。
