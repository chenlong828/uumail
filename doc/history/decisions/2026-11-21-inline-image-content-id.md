---
layer: history
module: mail
status: frozen
updated: 2026-11-21
---

# 内联图片持久化 ContentId（2026-11-21）

## 背景

`REQ-0025`/`SCN-0019` 第一版（2026-11-20）只按 `cid:` 的 local part 与附件 `displayName`
（含去扩展名）唯一匹配，明确接受「不透明 `cid:`（不含文件名）的邮件图片仍不显示」的降级；
当时记录的依据是「无证据表明该网关返回 `ContentId`」，并把 schema v11 + `Attachment.contentID`
列为触发条件。

2026-11-21 真实样本（`会议纪要-测试委员双周例会20261119`，Foxmail 发出）证伪了这条依据：

- 正文两处 `<img src="cid:_Foxmail.1@<uuid>">`，与附件名毫无关系；
- 生产 `EASClient.sync` 的 `Attachments` 节点实测返回
  `<ContentId>_Foxmail.1@<uuid></ContentId>` 与 `<IsInline>1</IsInline>`，`ContentId` 与正文 `cid:` 逐字一致；
- 客户端只解析 `DisplayName`/`FileReference`/`EstimatedDataSize`，`ContentId` 被丢弃，
  `MailDomain.Attachment` 与 `attachments` 表（v4）也没有该字段，于是匹配必然为 0，正文保留
  `cid:` 并被 CSP 拦截。

## 决定

按 C1 落地：**持久化 `ContentId`，匹配以它为先**。

- `EASAttachment` 增加 `contentID`，`EASClient.parseMessage` 读 `ContentId`（`IsInline` 暂不解析、不落库）。
- `MailDomain.Attachment` 增加 `contentID: String?`（公开契约的兼容扩展，带默认值）。
- `attachments` 表 v11 增加 `content_id TEXT`；同步 upsert 写入，读取带回；
  旧行保持 NULL。
- `InlineImageHTML.matches` 先按 `contentID` 精确匹配（规范化后含 `@` 全串），命中则只在该集合里取；
  未命中时才回退到既有 `displayName`/local part/去扩展名规则；歧义（≥2）仍跳过。
- 内联附件继续显示在附件条（用户 2026-11-21 决定）；不改 `SCN-0005` 的下载/打开语义。
- 旧邮件：v11 之前入库的附件没有 `content_id`，要等重新同步（Sync 窗口）后才有值；
  用户 2026-11-21 接受「新邮件立即生效、旧邮件重开/重同步后生效」。

## 影响

- 公开契约变化：`Attachment` 新增字段（兼容，默认 `nil`）。
- schema 变化：`attachments` 增加一列（additive migration v11）。
- 同步路径：`ContentId` 随附件元数据入库；无额外请求。
- 渲染路径：命中 `ContentId` 的内联图片不再依赖文件名；原有按名匹配的邮件行为不变。

## 未采纳

| 方案 | 理由 |
|---|---|
| 读时取 MIME（`BodyPreference Type=4`）解析 `Content-ID` | 多一次大请求；网关是否支持 MIME 正文未验证；慢且易失败 |
| 按 `IsInline` + 正文顺序猜测 | 附件顺序与 `<img>` 顺序无协议保证，错图风险 |
| 只按 `ContentLocation` 匹配 | 本样本没有该字段 |
| 只在内存里映射、不落库 | 渲染在读路径，附件元数据只在 Sync 时出现；不持久化就必然丢失 |

## 人工确认记录

2026-11-21 用户逐条确认：

1. 接受 C1（schema v11 + `Attachment.contentID`）；
2. 接受「新邮件立即生效、旧邮件重开/重同步后生效」；
3. 内联附件继续列在附件条；
4. 修改设计，内联图片需要支持持久化。

定级 **P1**（核心 schema + 公开契约）；确认发生在编码前。
