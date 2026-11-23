---
layer: design
module: mail
status: designed
updated: 2026-11-23
flow: mail/read
scenario: SCN-0022
---

# SCN-0022 附件条只列正文未引用的附件

**结果**：用户打开正文以 `cid:` 引用内联图的 HTML 邮件，附件条**只显示正文没有引用的附件**；内联图仍在正文中渲染，真实附件（xlsx、wmz 等）保留并可打开/另存。匹配不到或歧义时不隐藏，宁可多显示、不误删。附件数据、schema、`ReadScene.attachments`/`downloadAttachment` 的全量语义、内联图渲染链路不变。

## 入口

- `CMP-SCN-READ#InlineImageReferences.attachmentIDs(inHTML:attachments:)`（新增 additive public 纯函数，复用 internal `InlineImageHTML.matches`）
- `CMP-PRES#MailboxViewModel` 的 `MailboxViewModel+Body.startInlineImageRender`（既有入口，新增过滤）
- `CMP-APP#AttachmentStripView`（既有，零改动；只收到过滤后的 `attachments`）
- 不涉及：`EASClient`、`MailStore`、`MailDomain`、`Package.swift`、附件 schema、`ReadScene.renderInlineImages`

## 运行序

流程 `F-READ-10`：

1. 打开邮件，`MailboxViewModel` 从 `ReadScene.attachments(for:)` 取全量附件，先赋给 `attachments`（正文未到时的短暂态）。
2. 正文 HTML 到达（缓存命中或补拉成功）→ `startInlineImageRender(html)`：
   a. `InlineImageReferences.attachmentIDs(inHTML:attachments:)` 按 `InlineImageHTML.matches` 的唯一匹配规则（先 `contentID`，再 `displayName`/去扩展名回退）算出 `Set<fileReference>`；
   b. 从 `attachments` 移除命中项；歧义/未命中保留；
   c. 再启动既有内联图渲染（仍由 `ReadScene` 自己取全量附件，不受投影影响）。
3. 附件条按过滤后的 `attachments` 渲染；为空时整块不显示（既有行为）。
4. 正文无 `cid:`（纯文本/预览）→ 匹配为空 → 附件条不变。

失败路径：
- 匹配歧义（0 或 >1 候选）→ 不隐藏，附件条保留；不误删真实文件。
- 内联图渲染失败/坏字节 → 正文文字照常；对应附件已被隐藏（用户选择「隐藏内联图」的已接受代价），不弹错、不回滚。
- 切换邮件 → `attachments` 重新从 store 取全量再过滤，不残留上一封的投影。
- `startInlineImageRender` 被重复调用（同一封重载）→ 投影已在全量基础上过滤过一次；重复过滤幂等，不会误删。

## 不可变引用

- `SCN-0019`：`InlineImageHTML.sources/matches/dataURL/replacingSources`、`ReadScene.renderInlineImages`、`inlineImageHTML` 换串重载；本卡只复用 `matches`，不改匹配规则/渲染链路。
- `SCN-0020`/`SCN-0005`：附件条单击选中/双击打开/右键另存为、`downloadAttachment` 缓存/单飞、2GB 上限；本卡不改入口与语义。
- `REQ-0025` 2026-11-21 澄清③「内联附件继续列在附件条」**被本卡取代**；决策记录 `history/decisions/2026-11-23-table-adapt-inline-attachment-filter.md`。
- `MailboxViewModel.attachments` 的公开签名不变（仍是 `public internal(set) var attachments: [Attachment]`）；语义收窄为「附件条展示集」。
- 不新增依赖/target/schema；不改 `Package.swift`；单文件预算不变。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID |
|---|---|---|---|---|
| `T-SCN-0022-01` | 正 | L1 | 正文 `<img src="cid:logo@test">` + 附件 `logo.png`（按名字回退命中）+ 真实 `报表.pdf`：打开后 `viewModel.attachments == [报表.pdf]`。 | `MailboxViewModelInlineImageTests.hidesReferencedInlineAttachment` |
| `T-SCN-0022-02` | 正 | L1 | 不透明 `contentID` 命中（`_Foxmail.1@...`）+ 一个真实附件：隐藏命中项，真实附件保留；同时断言 `inlineImageHTML` 仍生成 `data:`。 | `MailboxViewModelInlineImageTests.hidesInlineAttachmentByContentID` |
| `T-SCN-0022-03` | 正 | L1 | 正文无 `cid:` / 只有纯文本预览：全部附件保留（2 个都在），不误过滤。 | `MailboxViewModelInlineImageTests.keepsAttachmentsWithoutCID` |
| `T-SCN-0022-04` | 反 | L1 | 两个附件同名（歧义）或 `cid:` 无对应附件：不隐藏、不误删；`attachments` 保持原样，正文仍显示。 | `InlineImageHTMLTests.attachmentIDsSkipsAmbiguous`、`MailboxViewModelInlineImageTests.ambiguousInlineReferenceKeepsAttachments` |

证据层级：最低 **L1**（纯函数 + 视图模型状态）。不上 L2/L3/L4；真实样本只做发布前/人工冒烟。

## 状态

`designed`（2026-11-23 设计；`T-1123-02`/`T-1123-03` 实现、`T-1123-05` 验证后转 `verified`）。定级 **P2**（跨组件 + additive public 纯函数）；人工确认 2026-11-23：隐藏正文内联图（用户方案选择）。

## 与相邻场景的边界

- `SCN-0019`：内联图渲染归它；本卡只消费其匹配规则，不重复认领图片可见性。
- `SCN-0020`：附件取用交互归它；本卡只改变附件条的数据来源（投影），不改交互。
- `SCN-0005`：附件下载/缓存归它；本卡不改下载入口与缓存算法。
- `SCN-0004`：正文渲染/补拉归它；本卡不重复认领正文可用性。
