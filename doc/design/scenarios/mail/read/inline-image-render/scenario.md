---
layer: design
module: mail
status: verified
updated: 2026-11-21
flow: mail/read
scenario: SCN-0019
---

# SCN-0019 正文内联图片（`cid:`）渲染

**结果**：用户打开一封正文以 `cid:` 引用内联图片的 HTML 邮件时，**打开就能在正文里看到图片**，
不需要先点附件条里的 `image001.png`，也不需要先开「加载远程图片」。只取当前正文实际引用的内联
附件；远程 `http(s)` 图片仍按开关阻止。引用缺失/取负载失败/坏数据时：**有文字时正文文字必显示、
可滚动**，不崩、不无限重试；**纯图片邮件在图片外部失败时正文仍空白，是已接受降级**（与现状相同），
不把「所有图片必可见」写成契约。原始正文、CSP 两档值、`baseURL`、禁 JS、附件条点击下载全部不变。

## 入口

- `CMP-SCN-READ#InlineImageHTML`（新增 internal 纯函数：`src` 提取/规范化/唯一匹配/字节嗅探/仅 `src` 值改写）
- `CMP-SCN-READ#renderInlineImages(for:html:)`（新增；复用既有 `#downloadAttachment` 与 `AttachmentFiles` 缓存/单飞）
- `CMP-PRES#MailboxViewModel.inlineImageHTML`（新增只读状态）与 `MailboxViewModel+Body` 的图片任务
- `CMP-APP#MessageBodyView`（新增 `inlineImageHTML` 入参，只换显示串）/ `#MessageWebView`（既有，**不改**：CSP、禁 JS、`loadHTMLString(_, baseURL: nil)`、`lastRender` 原样）
- 既有入口：`CMP-SCN-READ#open`/`#bodyIfCached`/`#downloadAttachment`、`CMP-STORE#attachments`/`#markAttachmentCached`、`CMP-PRES#MailboxViewModel.openSelected`
- 不涉及：`MailGateway`/`MailWriteGateway`、`MessageBodyStyle`（CSP/sanitized）、远程开关状态机、附件条与 `NSWorkspace` 打开
- 2026-11-21 增量：`EASClient#sync` 的附件元数据（`ContentId`）、`MailDomain#Attachment.contentID`、`MailStore#attachments` v11 持久化进入本场景的匹配输入

## 运行序

流程 `F-READ-08`：

1. 既有同步已落信封与附件元数据（`displayName`/`fileReference`/`size`）；打开邮件取正文（缓存优先，否则补拉落库），与 `SCN-0004` 相同。
2. `MailboxViewModel` 得到 `.loaded(rawHTML)`；`inlineImageHTML` 为空，正文先按原样显示（有文字则文字可见）。
3. 正文含 `cid:` 时启动图片任务；`InlineImageHTML.sources` 只提取 `src` 属性的 `cid:` 值（去重）。无引用 → 不触网、不启动。
4. 对每个引用，`InlineImageHTML.matches` 在当前邮件附件里匹配：**先按 `Attachment.contentID`（同步信封的 `ContentId`）与 `cid` 规范化后全串相等**；无命中时回退到 `displayName`、`cid` 的 `@` 前 local part，或（`displayName` 带已知图片扩展名时）去扩展名的 `displayName` 与之规范化后相等。命中的候选集合按 `fileReference` 去重后须唯一；0 个/多个 → 跳过。
5. 每个唯一匹配的附件经 `ReadScene.downloadAttachment` 取负载：`AttachmentFiles.cachedURL` 命中直接读；未命中按 `fileReference` 单飞 `fetchAttachment` → 原子落盘 → `markAttachmentCached`。同一附件被多次引用只取一次；单张失败/超时/超限/取消 → 跳过该张。
6. 字节按图片魔数嗅探（PNG/JPEG/GIF/WebP/BMP/TIFF/HEIC）生成 `data:` URL；`InlineImageHTML.replacingSources` 只替换对应 `src` 值，`ReadScene.renderInlineImages` 返回改写后的 HTML（无可用替换时返回 `nil`）；PRES 赋给 `inlineImageHTML`。任务完成时当前选中/正文仍是发起时那封才落状态，否则丢弃。
7. `MessageBodyView` 用 `inlineImageHTML ?? rawHTML` 交给既有 `MessageWebView` → `MessageBodyStyle.sanitized`（CSP 不变）→ `loadHTMLString`。`data:` 在两档 CSP 的 `img-src` 里都已允许；远程 `http(s)` 仍由开关决定。`inlineImageHTML` 到达时 `lastRender` 变化，重载一次。
8. 失败：无匹配/取不到/坏字节 → 该 `cid:` 保留原样（被 CSP 阻止；不要求可见，破图占位由 `T-SCN-0019-04` 的文字基线排除），正文文字与其余图片照常；不弹错、不循环重试；切换邮件/清空 → 取消任务并丢弃迟到结果（已开始的单飞下载可能完成，结果丢弃）。原始 `body` 与回复引用保持 raw HTML（不含 data URL）。

失败路径：

- `cid:` 无对应附件 / 同名多附件（歧义）→ 不取、不替换；正文文字可读。
- `fetchAttachment` 404/超时/`FileReference` 失效 → 跳过该图；不把整封升级为失败；重开同一邮件走附件缓存，失败则再尝试一次（无循环重试）。
- 坏 base64/非图片字节 → 嗅探失败，不替换；不产生非法 `data:` URL。
- 单图超过实现 guard（20MB）→ 跳过；不阻塞其它图。
- 切换 A→B：A 的图片任务取消，迟到结果不得写到 B；B 以 raw HTML 先显示。
- 纯图片邮件且外部失败 → 正文仍空白是已接受降级（与现状相同）；不把「所有图片必可见」写成契约。

## 不可变引用

- `SCN-0013`/`SCN-0018` 已验证的全部承诺：远程开关位置/状态机/单封会话内/切换与重开复位；两档 CSP 精确值（`img-src data:` 与 `img-src data: https: http:`）；禁 JS、`default-src 'none'`、白底与作者样式；`lastRender` guard；ATS 载体配置。本卡不放宽 `http(s)` 默认阻止，不改 CSP 字符串。
- `SCN-0005`：附件条存在与点击下载/打开、`AttachmentFiles` 2GB 最旧优先、同一 `fileReference` 单飞、`markAttachmentCached` 语义；本卡只复用读取，不改入口与 25MB/续传/名称回退欠账。
- `SCN-0004`：正文基本渲染、正文补拉与 `<script>` 不执行仍归该卡；本卡的「失败正文可读」只覆盖内联图片失败。
- `SCN-0015`：`WKWebView.pageZoom` 与 175/225% 元数据区 cap 不变。
- `SCN-0010`：阅读窗格白底、作者样式不重写。
- 数据/契约（2026-11-21 修订，原「不改 schema/不持久化 ContentId」作废）：`attachments` schema v11 增加 `content_id`；
  `Attachment`/`EASAttachment` 增加 `contentID`（兼容扩展，默认 `nil`）；`MailStore` 是唯一写入口，读取带回。
  `IsInline` 仍不解析、不落库。`inlineImageHTML` 仍是视图状态；原始 `message_bodies` 与 `MailboxViewModel.body` 保持 raw HTML。
  决策见 `history/decisions/2026-11-21-inline-image-content-id.md`。
- 隐私：只取当前正文实际引用的内联附件；不预取未引用附件；不因 `cid:` 向第三方发请求；不伪造 Referer/Cookie。
- 预算：`MailStore`/`EASClient`/`EASAdapter` 0 行；`Scenes`/`Presentation`/`uumail` 按设计增量，单文件 ≤300/400 行；不新增 target/依赖/第三方库。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID |
|---|---|---|---|---|
| `T-SCN-0019-01` | 正 | **L1 + L2** | L1：受控 HTML（可见文字 + `<img src="cid:logo@test">`）+ 假附件 `logo.png`（假 PNG，非空白像素；覆盖去扩展名匹配），`InlineImageHTML` 提取/规范化/唯一匹配，`ReadScene.renderInlineImages` 只取被引用附件，`InlineImageHTML.dataURL` 生成 `data:image/png;base64,...`，返回串含 data URL 且正文其余字节不变。L2：把生产 `InlineImageHTML` 的改写结果交给生产 `MessageWebView`（离屏 `NSWindow`），断言 `img.naturalWidth/naturalHeight>0`、快照非白/品红像素 >0、`requests=0`；不需要点附件条、不需要开远程开关。 | `InlineImageHTMLTests.sourcesFindCIDSourcesOnly`、`InlineImageHTMLTests.normalizationHandlesCasePercentAndBrackets`、`InlineImageHTMLTests.matchesDisplayNameAndLocalPart`、`InlineImageHTMLTests.matchesStemWhenCIDOmitsExtension`、`ReadSceneInlineImageTests.fetchesOnlyReferencedAttachments`、`InlineImageProbe.productionRewriteRenders` |
| `T-SCN-0019-02` | 正 | **L1 + L2** | 同页再含一张 `http://` 远程图：开关默认关 → 内联 `cid:` 图可见、远程 0 请求；打开「加载远程图片」→ 内联图仍可见、不新增内联负载请求/第三方请求。远程图开启后的实际加载归 `SCN-0018`，本卡只回归。 | `MailboxViewModelInlineImageTests.remoteGateDoesNotAffectInlineImages`、`InlineImageProbe.remoteStillBlocked` |
| `T-SCN-0019-03` | 正 | **L1 + L2** | 打开 A（含内联图）→ 切到 B → 返回 A；或关闭重开同一邮件：A 的图片仍可见；同一附件只下载一次（fake gateway 调用计数 / `AttachmentFiles` 缓存）；切换期间无第三方请求。远程开关复位归 `SCN-0013`。 | `ReadSceneInlineImageTests.reusesCachedFileAndSingleFlight`、`MailboxViewModelInlineImageTests.switchingMessageDropsStaleInlineImages`、`InlineImageProbe.reopenRenders` |
| `T-SCN-0019-05` | 正 | **L1** | 不透明 `cid:`（`_Foxmail.1@<uuid>` 形态）不在附件名里：带 `contentID` 的附件按 `ContentId` 命中，正文替换为 `data:`；`ContentId` 缺失时不出图（回到名字规则）；两个附件同 `ContentId` 仍按歧义跳过。 | `InlineImageHTMLTests.matchesOpaqueCIDByContentID`、`InlineImageHTMLTests.contentIDTakesPrecedenceOverNames`、`InlineImageHTMLTests.duplicateContentIDIsIgnored`、`ReadSceneInlineImageTests.opaqueCIDUsesContentID` |
| `T-SCN-0019-04` | 反 | **L1 + L2** | 四类失败：①引用无对应附件；②取负载失败/超时；③坏 base64/非图片字节；④同名多附件（歧义）。断言：**有文字时**正文文字必显示、可滚动；纯图片邮件的外部失败仍空白属**已接受降级**（不判 fail、不要求所有图可见）；不崩、不无限重试；远程图仍按开关阻止；下一封不受影响。L2 同页需有纯文字基线，用于区分「文字照常渲染」与「被阻止的破图占位」。 | `ReadSceneInlineImageTests.failedPayloadIsSkipped`、`ReadSceneInlineImageTests.oversizedAttachmentIsSkipped`、`InlineImageHTMLTests.ambiguousReferenceIsIgnored`、`MailboxViewModelInlineImageTests.emptyOrFailedPayloadsLeaveRawHTML`、`InlineImageProbe.failedImageKeepsText` |

证据层级：最低 **L1**（映射/改写/失败分支）+ **L2**（生产 `MessageWebView` 实际渲染）。不上 L3/L4；
真实用户样本只做发布前/人工冒烟（脱敏，只记通过/失败），不作为自动化夹具、不替代逐例断言。

测试载体：

- L1：`ScenesTests/InlineImageHTMLTests`、`ScenesTests/ReadSceneInlineImageTests`、`PresentationTests/MailboxViewModelInlineImageTests`；fake gateway/files 断言调用集与缓存命中；不向真实邮箱/网络发请求。
- L2：扩展 `task-spaces/20261120-111818/evidence/inline-image-probe/`，保留 `raw-cid-blocked` 与 `remote-blocked` 负控制；断言像素与 `naturalWidth`，不依赖截图判读。
- 真实样本：用本机缓存正文 + 附件只读跑一次，读 `document.images` 的完成数/自然宽计数；不记录主题/发件人/URL/字节；失败记 `test.md`，不写「应该可见」。

## 状态

`verified`（2026-11-21 增补 `ContentId` 持久化并通过新用例；2026-11-20 首版实现并验证：`T-SCN-0019-01..04`
L1+L2 全 PASS，第 5 轮实现鉴定 **pass**，见 `task-spaces/20261120-111818/review5.md` §7；四元素齐，
`T-SCN-0019-01..05` 有可执行 ID/层级）。`REQ-0025` 于 2026-11-20 首次 `delivered`，2026-11-21 重开后按增量
重新交付。首版定级 **P2**；2026-11-21 的 `ContentId` 持久化按 **P1**（核心 schema + 公开契约）处理，已人工确认
（C1、旧邮件重同步生效、内联附件保留），见 `history/decisions/2026-11-21-inline-image-content-id.md`；
该增量改 `attachments` v11 与 `Attachment` 公开字段。匹配族/载体族选择见
`task-spaces/20261120-111818/design.md` §3。公开面 `ReadScene.renderInlineImages(for:html:)` 与
`MailboxViewModel.inlineImageHTML` 为 additive public，已**人工确认 pass（选项 A，2026-11-20）**，记录见
`doc/history/decisions/2026-11-20-inline-image-render-public-surface.md`；D1–D8 仍为默认确认（未经人工），
见 `task-spaces/20261120-111818/design2.md` §8。失败口径按「有文字时正文文字必显示、可滚动；纯图片邮件外部失败
仍空白是已接受降级」统一（B2，2026-11-20）。样本事实与 L2 方向证据见
`task-spaces/20261120-111818/evidence/inline-image-current-state-design.md`；2026-11-21 的样本证据见
`task-spaces/20261121-0705-inline-images/evidence/`。

## 与相邻场景的边界

- `SCN-0018`：远程 `http(s)` 图片放行/ATS 载体归它；本卡只认领 `cid:` 内联图片，不改其「不做 `cid:` 解析」的历史断言，也不重复其放行后加载结果。
- `SCN-0013`：开关位置/状态机/CSP 两档值/单封会话内复位归它；本卡只验证内联图不受开关影响且不破坏开关。
- `SCN-0005`：附件条点击下载/打开、缓存布局/2GB 淘汰、25MB/续传/名称回退归它；本卡只要求复用 `downloadAttachment` 时不改变其行为。
- `SCN-0004`：正文基本渲染、补拉、默认阻止与脚本不执行的完整欠账归它；本卡不替它转 `verified`。
- `SCN-0010`/`SCN-0015`：只回归白底与字号，不新增断言。
