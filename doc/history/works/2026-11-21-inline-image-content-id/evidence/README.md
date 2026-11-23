# 内联图片不显示：排查结论（2026-11-21）

> 归档说明（2026-11-23）：原始正文 HTML、附件文件名/字节、真实地址与 Sync 原始响应含真实邮件数据，均已删除；
> 本文件只保留可复核的形态与结论。

- 正文有两处 `<img src="cid:_Foxmail.1@<uuid>">`：cid 是**不透明 ContentId**，与附件文件名无关。
- 生产 `EASClient.sync` 的附件元数据实测包含 `<ContentId>`（与正文 cid 逐字一致）与 `<IsInline>1`；
  首版客户端只解析 `DisplayName`/`FileReference`/`EstimatedDataSize`，这两个字段被丢弃。
- 缓存目录里两张图已下载（约 37 KB GIF 与 893 KB JPEG），说明取字节/落盘正常；失败只发生在
  `cid → 附件` 的映射上。
- 代码事实：`attachments` 表（v4）无 content-id 列；`InlineImageHTML.matches` 只按
  `displayName`/local part/去扩展名 stem 匹配 → 0 个候选 → `renderInlineImages` 返回 nil →
  正文保留 `cid:` → `img-src` CSP 不含 `cid:` → 空白。
- 这是 2026-11-20 决策 D2 明确接受的降级（「不透明 `cid:` 的图片仍不显示」），触发条件在本次样本上发生。
- 修复与决策：见同目录 `brief.md`/`result.md` 与 `history/decisions/2026-11-21-inline-image-content-id.md`。
