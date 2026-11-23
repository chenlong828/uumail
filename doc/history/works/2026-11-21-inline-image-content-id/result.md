---
layer: history
module: mail
status: frozen
updated: 2026-11-23
---

# 2026-11-21 内联图片 ContentId 持久化 — 收口

## 结论

`ContentId` 从同步信封解析并持久化（`attachments` v11），`InlineImageHTML.matches` 以它为首选、名字规则回退；
该样本邮件的两个不透明 `cid:` 现在能分别映射到对应附件。旧邮件靠 v11 迁移把消息游标置 `"0"`，升级后首轮
按窗口重拉 ≤125 封补齐 `content_id`；`IsInline` 暂不落库。

## 验收

| 项 | 结果 |
|---|---|
| `T-SCN-0019-05`（正） | `InlineImageHTMLTests` 3 例 + `ReadSceneInlineImageTests.opaqueCIDUsesContentID` 通过 |
| 既有 3 正 1 反 | 名字匹配/歧义/嗅探/改写用例全部保持通过 |
| 协议解析 | `EASClientTests` 附件解析断言 `contentID == "report@corp.test"` |
| 存储 | `MailStoreTests` round-trip + 省略 `ContentId` 不清旧值；`MigrationTests` v11 旧行为 nil、游标归零（folders 保留）、重同步可填 |
| 全量 | `368 tests / 58 suites` 绿；架构 4 门 PASS |

## 结论落点

| 结论 | 落点 |
|---|---|
| 决策与人工确认 | `history/decisions/2026-11-21-inline-image-content-id.md` |
| 解析/映射/持久化/匹配 | `design/components/CMP-EAS`、`CMP-DOMAIN`、`CMP-STORE`、`CMP-SCN-READ` 规格 §设计增量（2026-11-21） |
| 场景 | `SCN-0019`（转回 `verified`，新增 `T-SCN-0019-05`）；`REQ-0025` 重开后重新交付 |
| 排期 | `plan/roadmap.md` §W-M3-14 |
| 架构限制 | `design/architecture.md` §10 第 11 条改为「已持久化」 |

## 未决

- 应用内肉眼验收需重启 `dist/uumail.app` 后人工点开该邮件。
- `IsInline` 未解析：内联附件仍出现在附件条（用户已确认保留）。
- 超出 125 封窗口的更早邮件要等全量重建才会补 `content_id`；不做主动回填。
