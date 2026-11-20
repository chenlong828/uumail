---
layer: history
module: mail
status: frozen
updated: 2026-11-20
---

# 内联图片（`cid:`）渲染：P2 默认确认（D1–D9）与设计边界（2026-11-20）

## 背景

`REQ-0025`（HTML 正文内联图片 `cid:` 显示，`feature`，`accepted`）在 2026-11-20 完成需求分析；场景草案见 `task-spaces/20261120-111818/scenario-drafts.md`。设计期先用只读聚合证据证实了 Q1：与用户截图同形的缓存正文 1297 字符，仅两个 `<img src="cid:image00N.png@<hex>.<hex>">`、无可见文字，附件名恰为 `image001.png`/`image002.png`（与截图附件条一致）；不是正文未下载，而是 `cid:` 未解析/内联负载未回填/CSP 不含 `cid:`。随后用 L2 探针证实方向：现有 CSP 的 `img-src data:` 能渲染改写后的 `data:` 图，原位 `cid:` 不渲染，远程 `http` 在阻止档仍 0 请求。

本次设计把草案落为正式场景 `SCN-0019`（`mail/read/inline-image-render`，`designed`），并把改动收敛到：

- `Scenes`：新增 internal `InlineImageHTML`（`cid:` 来源提取、规范化、附件唯一匹配、字节嗅探、只改写 `src` 值）与 `ReadScene.renderInlineImages(for:html:)`（复用既有 `downloadAttachment`/`AttachmentFiles` 缓存/单飞，返回渲染串）；
- `Presentation`：`MailboxViewModel.inlineImageHTML`（当前正文渲染投影）+ 可取消图片任务，不解析 HTML、不读文件；
- `uumail`：`MessageBodyView` 新增 `inlineImageHTML` 入参并优先用它渲染，`MailboxView` 透传。

**不**改 `attachments` schema、不加 `ContentId`/`IsInline` 列、不改 `MailDomain`/`Attachment`/`EASAttachment`/`MailGateway`、不改 `EASClient` 命令、不改 `MessageBodyStyle` CSP、不改 `loadHTMLString` 的 `baseURL`、不注册 `WKURLSchemeHandler`、不改远程开关与附件条。

## 确认来源与范围

- **无人值守**：本系列任务无 `confirm` 节点、无人在环，发起人未中途逐项回答。
- 依据 `auto-confirm`，以下 D1–D9 为**默认确认（未经人工）**：按 `REQ-0025` 澄清记录、设计证据与推荐项自动确认并继续。
- **本记录不是发起人签字，也不得写成「已确认（人）」或「发起人确认」**；评审可独立否决。若评审判 P1 的划分不成立、或否决任一子项，按其结论回设计，不复用本记录。
- 未触发 `auto-confirm` §3：不改 schema/`MailDomain` 公开契约/数据所有权/热路径依赖，不新增依赖/权限/付费，不做不可逆迁移。若评审把 `ReadScene` 新增公开方法视为核心契约（P1），则改按 P1 补人工确认，本记录不冻结该部分。
- 影响范围：`REQ-0025` / `SCN-0019` / `CMP-SCN-READ` / `CMP-PRES` / `CMP-APP` / `architecture.md`；`CMP-EAS`、`CMP-EASADAPTER`、`CMP-DOMAIN`、`CMP-STORE` 明确不改。

## 决定

| # | 项 | 结论 |
|---|---|---|
| D1 | 场景归属 | 新建 `SCN-0019`（`mail/read/inline-image-render`），不重开已验证的 `SCN-0018`/`SCN-0013`，不塞进 `SCN-0005`/`SCN-0004`。`SCN-0018` 仍只认领远程 `http(s)` 放行/ATS；`SCN-0013` 仍只认领开关状态机与 CSP 两档值。 |
| D2 | 匹配族 | 选 **C2：`displayName` / `cid:` local part 唯一匹配**（`Scenes/InlineImageHTML` internal 纯函数）；不持久化 `ContentId`。规范化 = 去空白/去 `cid:`/去 `<>`/百分号解码/小写；候选为 `displayName`、`cid` local part，或（`displayName` 带已知图片扩展名时）去扩展名后的 `displayName`；0 或 ≥2 个候选都不猜。理由：样本 `cid:` local part 精确等于附件名；无证据表明该网关返回 `ContentId`；持久化需 schema v11 + `Attachment` 公开字段 + `EASClient` 解析，并把 `MailStore` 已超的预算再推高（R45）。回退/触发：出现不透明 `cid:` 真实样本时另立需求走 C1，不静默加列。 |
| D3 | 载体族 | 选 **V1：渲染前把 `cid:` 的 `src` 值替换为 `data:` URL**。现有两档 CSP 已允许 `img-src data:`；零 CSP 变更、零 `baseURL` 变更、无新 scheme、无 JS。否决 V2（`WKURLSchemeHandler`：需 CSP 加 scheme + WebView 配置 + 异步供数/生命周期）、V3（临时文件/`file://`：放大本地文件暴露面与清理成本）、V4（取正文时改写并持久化：正文库膨胀 4/3、附件字节双份、旧缓存仍要渲染期兜底）。 |
| D4 | 取负载时机 | 打开正文、`.loaded` 后**异步、非阻塞**启动；缓存命中不触网；缓存未命中才走 `fetchAttachment`；**只取当前正文实际引用的附件**，未引用附件不预取。`open` 的流不等待图片；正文文字先显示。 |
| D5 | 附件条 | 保持现状：内联附件仍列在附件条，点击下载/打开入口与 `NSWorkspace` 行为不变；不做按 `IsInline` 隐藏（无该列，避免扩大范围）。复用 `downloadAttachment` 的单飞与 2GB 缓存，不改 `SCN-0005` 契约。 |
| D6 | 失败口径 | 无匹配/歧义/取负载失败/坏字节/超 20MB guard → **跳过该图**，保留原 `cid:`（被 CSP 阻止，不出现破图）；正文文字与其余图片照常；不弹错、不重试循环；切换邮件取消并丢弃迟到结果。纯图片邮件且外部失败仍空白是已接受降级，不把「所有图片必可见」写成契约。 |
| D7 | 渲染投影边界 | `body`/`quotableHTML`/`message_bodies` **始终是原始 HTML**；`data:` URL 只存在于 `MailboxViewModel.inlineImageHTML` 这次渲染投影，不持久化、不进回复引用、不进草稿/外发。`InlineImageHTML` 只做字节魔数嗅探（PNG/JPEG/GIF/WebP/BMP/TIFF/HEIC）+ base64；PRES 不解析 HTML、不读文件。 |
| D8 | 安全与不变式 | 不改 CSP 两档精确值、禁 JS、`.nonPersistent()`、白底、作者样式、`lastRender` guard、`loadHTMLString(_, baseURL:nil)`；只处理 `<img>`/`src` 的 `cid:`，不解析 CSS `background-image`/VML（样本无此形态，后续另立）；远程 `http(s)` 仍由 `RemoteContent` 开关控制，内联 `data:` 不受开关影响；不伪造 Referer/Cookie；不因 `cid:` 向第三方发请求。 |
| D9 | 定级/证据 | **P2**（跨 `Scenes`/`Presentation`/`uumail` 三层、additive 场景方法/视图模型状态 + internal 纯函数；无 schema/`MailDomain` 契约/数据所有权/热路径依赖变更）。验证：L1 映射/改写/失败分支 + L2 生产 `MessageWebView` 实际渲染；真实样本只做发布前/人工冒烟（脱敏，不记录主题/发件人/URL/字节）。不上 L3/L4。 |

## 范围变更

- 新增 `Scenes/InlineImageHTML.swift`（internal 纯函数，约 120 行）与 `Scenes/ReadScene+InlineImages.swift`（public 方法，约 50 行）；`Scenes` 由 1006 → 约 1176，**既有 800 行预算已超**，登记不静默调预算。
- `Presentation`：`MailboxViewModel` +约 8、`MailboxViewModel+Body` +约 30（不新增文件；单文件仍 ≤400）。
- `uumail/MessageBodyView.swift` +约 3、`MailboxView.swift` +约 1（单文件仍 ≤300）。
- **不新增** schema/迁移/store 方法/EAS 命令/依赖/target/`Package.swift` 改动/网络新路径/第三方库。
- 回退方式：删除新增纯函数/场景方法/VM 状态/视图入参接线；无数据迁移；`body`、附件条、远程开关、CSP 均不受影响。

## 代价 / 影响

- 打开含内联图的邮件时，首次需为被引用的附件取负载；图片在正文文字之后出现（不是阻塞式打开）。复用附件缓存后，重开同一邮件不再触网。
- data URL 让当前渲染串约为图片字节的 1.33 倍；只在当前邮件内存中存在，切换即释放；不缓存跨邮件。单图 >20MB 跳过（guard，非验收契约）。
- 不透明 `ContentId`（不含文件名的 `cid:`）的邮件图片仍不显示；这是本轮明确接受的降级，后续按 D2 触发条件另立需求。
- `Scenes` 800 行预算已超，本设计再增约 170 行；登记为既有欠账，建议后续把 `HTMLText`/`InlineImageHTML` 类纯工具拆到独立组件（另立任务，避免与本次混做）。

## 证据

- 样本事实与 L2 方向证据：`task-spaces/20261120-111818/evidence/inline-image-current-state-design.md`、`evidence/inline-image-probe/`（`probe-run.txt`、`commands.md`）。
- 设计全文：`task-spaces/20261120-111818/design.md`（§3 方案族、§4 组件级、§5 验证计划、§6 风险）。
- 正式场景：`doc/design/scenarios/mail/read/inline-image-render/scenario.md`（`SCN-0019`，`designed`）。
