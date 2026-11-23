---
layer: history
module: global
status: frozen
updated: 2026-11-23
run: 20261123-table-adapt
---

# W-M3-15 设计简报（P2）

## 1. 改动级别

- **REQ-0027（表格适配）**：`CMP-APP` 内部 CSS 规则，不改公共契约、schema、依赖、热路径 → **P3**。
- **REQ-0028（附件条过滤）**：新增 `Scenes` additive public 纯函数，`Presentation` 增加过滤逻辑，跨两个组件、改公共面 → **P2**。人工确认：2026-11-23 用户在方案选择中确认「附件条隐藏内联图」；这是本批唯一的人工门。
- 不新增组件/target/依赖；不改 `MailDomain`/`MailStore`/`EAS`/`Composition`/`Package.swift`。

## 2. 组件与契约

| 组件 | 改动 | 契约 |
|---|---|---|
| `CMP-APP` | `MessageBodyStyle.baseCSS` 增宽表规则 | 无 public；`sanitized` 签名不变 |
| `CMP-SCN-READ` | 新增 `public enum InlineImageReferences`（同文件 `InlineImageHTML.swift`），复用 internal `InlineImageHTML.matches` | additive：`attachmentIDs(inHTML:attachments:) -> Set<String>`，纯函数、无 I/O、无新依赖 |
| `CMP-PRES` | `MailboxViewModel+Body` 在正文 HTML 确定时过滤 `attachments`（`removeAll` 命中项）；`attachments` 语义改为「附件条要展示的附件」 | 无签名变化；`attachments` 仍是 `public internal(set)` |

数据流：`ReadScene.attachments`（全量，附件下载与内联渲染仍用它）→ `MailboxViewModel.attachments`（展示投影，已过滤）→ `AttachmentStripView`。内联渲染仍由 `ReadScene.renderInlineImages` 自己取全量附件，不依赖 VM 投影。

## 3. 方案选择

### 3.1 表格：压缩适配（用户已确认）

```css
table[width], table[style*="width" i] {
    display: block;
    max-width: 100%;
    overflow-x: auto;
}
```

- 只命中带显式宽度的表；无宽度表保持 `display:table`，不改变原有版式。
- `display:block` 让表的宽度可被 `max-width` 压到阅读区；列宽由 WebKit 按内容重新分配；压不下去时 `overflow-x:auto` 在表格内部滚动。
- 不改 HTML、不启用 JS、不改 CSP；`baseURL` 与 `lastRender` 逻辑不变。
- 实测：816px 表在 668px 视口压到 636px，8 列全可见；120% 下 816px 表保持 816px（无变化）；120/145/175/225% 全部 `scrollWidth == 视口`。

被否决：
- 保版式 + 外层 `div` 滚动：保留列宽，但需 HTML 扫描/包裹和滚动提示，改动更大；用户已选压缩。
- `table-layout:fixed`：均分列、忽略内容，长文本/图片列不可读。
- 允许整页横向滚动：用户明确不要页面被撑宽。

### 3.2 附件条：按 `cid:` 引用过滤（用户已确认）

- `InlineImageReferences.attachmentIDs` 直接复用 `InlineImageHTML.matches` 的唯一匹配规则（先 `contentID`，再名字回退）；歧义/未命中不隐藏，避免误删真实附件。
- `MailboxViewModel+Body.startInlineImageRender` 在拿到 HTML 后同步过滤；缓存正文路径与补拉成功路径共用该入口。预览 HTML（纯文本）没有 `cid:`，不过滤；补拉完成后过滤。
- 过滤在 main actor 上同步执行；本样本 349KB/55 cid 的匹配为毫秒级，可接受。
- **取代** 2026-11-21 人工确认的「内联附件继续列在附件条」（`REQ-0025` 澄清③）。理由：55 个内联图把附件条变成回形针墙，附件条不再承担「保存内联图」的职责；需要保存内联图的诉求另行评估，不在本批。

## 4. 运行序

1. 打开邮件 → `attachments` 取全量 → 附件条先按全量显示（正文未到时的短暂态；缓存正文路径几乎不闪）。
2. 正文 HTML 到达（缓存或补拉）→ `startInlineImageRender` 先算 `inlineIDs` → 从 `attachments` 移除命中项 → 附件条只剩真实附件；随后启动内联图渲染。
3. 表格：`MessageBodyStyle.sanitized` 注入 `baseCSS`（含宽表规则）→ WKWebView 加载 → 宽表压缩/表内滚动；页面不横向溢出。

失败路径：
- `InlineImageReferences` 匹配不到 → 附件保留（宁可多显示，不误删）。
- 内联图渲染失败 → 正文文字照常、图片不显示；对应附件已从附件条移除（用户选择隐藏；记入残余风险）。
- 表格无显式宽度但内容超宽 → 本规则不命中，可能仍溢出（图片已被 `img{max-width:100%}` 压住；仅 `nowrap` 文本等极端情况），记为残余。

## 5. 测试计划

| 用例 | 层级 | 断言 |
|---|---|---|
| `T-SCN-0021-01` | L2 探针 | 120% 下 816px 表文档宽度 = 视口，表格宽度不变（816） |
| `T-SCN-0021-02` | L2 探针 | 145/175/225% 下文档宽度 = 视口；宽表可压缩或表内滚动，所有列可到达 |
| `T-SCN-0021-03` | L2 探针 | 无宽度窄表（300px）保持原宽，不被拉伸 |
| `T-SCN-0021-04` | 反 | 无显式宽度但含 600px 图片的表格：页面不撑宽（由既有 `img` 规则兜底），不崩 |
| `T-SCN-0022-01` | L1 | 正文引用一个 `cid:` → 该附件不进 `viewModel.attachments`，真实 PDF 保留 |
| `T-SCN-0022-02` | L1 | 不透明 `contentID`（`_Foxmail.1@...`）命中 → 隐藏 |
| `T-SCN-0022-03` | L1 | 正文无 `cid:` / 纯文本预览 → 全部附件保留 |
| `T-SCN-0022-04` | 反 | 歧义（两个附件同名）或未命中 → 不隐藏，不误删 |

L2 布局探针编译生产 `MessageBodyStyle.swift`，用 WKWebView 量 `document.documentElement.clientWidth` / `scrollWidth` 与表格 rect，源码与原始输出入 `evidence/`。

## 6. 风险

- `display:block` 对带 `align`/浮动的显式宽度表可能改变环绕版式；本样本的浮动表无 `width`，不受影响。发布前用真实样本再冒烟。
- 隐藏内联附件后，用户不能再从附件条保存内联图；本批明确接受，记入 `plan/open-questions.md` 候选（不在本批实现）。
- 过滤发生在 main actor；若未来正文极大，需移到内联渲染任务内并接受一次闪动；本批不预付。
- 组合框（撰写页引言）使用自己的 `ComposeDocument` CSS，本批不改；同类宽表在撰写预览仍可能溢出，记待办。
