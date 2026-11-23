---
layer: design
module: mail
status: designed
updated: 2026-11-23
flow: mail/read
scenario: SCN-0021
---

# SCN-0021 HTML 正文宽表格适配阅读区

**结果**：用户打开一封正文含显式宽度表格的 HTML 邮件，在 120/145/175/225% 四档字号下，**页面宽度始终等于阅读区 CSS 视口宽度**；宽表按窗宽重排列宽并换行，压不下去时只在表格内部横向滚动；无显式宽度的窄表保持原宽。右侧列不再被阅读区边缘裁掉。CSP、禁 JS、远程开关、白底、字号 `pageZoom` 与 `lastRender` guard 全部不变。

## 入口

- `CMP-APP#MessageBodyStyle.baseCSS`（新增宽表规则；`sanitized` 与 CSP 两档值不变）
- `CMP-APP#MessageWebView`（既有，零改动：`pageZoom`、`loadHTMLString(_, baseURL: nil)`、`lastRender` guard）
- `CMP-APP#MessageBodyView`（既有，零改动：正文装配与状态切换）
- 不涉及：`MailboxViewModel`、`ReadScene`、`MailStore`、EAS、附件、撰写页

## 运行序

流程 `F-READ-09`：

1. 打开邮件，`MailboxViewModel` 给出 `.loaded(html)`；`MessageWebView` 以 `pageZoom = fontSize.scale` 加载。
2. `MessageBodyStyle.sanitized` 注入 `baseCSS`；对 `table[width]`、`table[style*="width" i]` 应用 `display:block; max-width:100%; overflow-x:auto`。
3. 表格显式宽度 ≤ 视口：按原宽度渲染（120% 下 816px 表保持 816px），不拉伸无宽度表。
4. 表格显式宽度 > 视口：块宽压到视口，列宽按内容重排、文字换行、图片随格缩放；内容仍压不下去时表格内部横向滚动，文档不溢出。
5. 字号变化：`pageZoom` 立即生效，上述规则随新的 CSS 视口重算，文档宽度仍 = 视口。

失败路径：
- 表格无显式宽度但内容超宽（如 `nowrap` 长文本）：本规则不命中，可能仍溢出；图片由既有 `img{max-width:100%}` 兜底。属残余，不崩、不改变页面宽度策略。
- 表格带 `align`/浮动且显式宽度：`display:block` 可能改变环绕版式；本批样本的浮动表无 `width`，不受影响；发布前真实样本冒烟。
- 作者 CSS 后续覆盖 `display`/`max-width`/`overflow`：视作发送方显式选择，本规则不强行 `!important`。

## 不可变引用

- `SCN-0004`：正文补拉、缓存优先、截断、CSP 阻止远程资源；本卡不改。
- `SCN-0019`：内联图 `cid:` 渲染、`renderInlineImages`、`inlineImageHTML` 换串重载；本卡不改。
- `SCN-0010`/`SCN-0015`：白底、作者样式保留、五档 `pageZoom`、175/225% 元数据区 cap 220pt；本卡不改。
- `MessageBodyStyle.sanitized` 的注入位置与 CSP 字符串；禁 JS；`baseURL = nil`；`drawsBackground`/`underPageBackgroundColor`/`appearance`；`lastRender` guard。
- 不新增依赖/target/schema；不改 `Package.swift`；单文件 ≤300 行。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID |
|---|---|---|---|---|
| `T-SCN-0021-01` | 正 | L2 | 120%：生产 `MessageBodyStyle.baseCSS` + 816px、8 列固定宽度表，视口 978px；断言 `document.scrollWidth == 978` 且表格宽度 = 816（不被无谓压缩）。 | `TableLayoutProbe.wideTableAtDefaultSize` |
| `T-SCN-0021-02` | 正 | L2 | 145/175/225%：视口 810/671/522px，同一 816px 表；断言 `scrollWidth == 视口`，表格右缘 ≤ 视口或表内 `scrollWidth > clientWidth`，所有 8 列表头文字可从 DOM 读取。 | `TableLayoutProbe.wideTableAtLargeSizes` |
| `T-SCN-0021-03` | 正 | L2 | 无宽度 300px 两列表：断言宽度保持 300（不被拉伸到视口），`scrollWidth == 视口`。 | `TableLayoutProbe.narrowTableKeepsWidth` |
| `T-SCN-0021-04` | 反 | L2 | 900px 表 + 600px 图片 + 文字列，视口 668px：断言不崩、`scrollWidth == 668`、图片宽度 ≤ 单元格宽度；同时记录「无显式宽度且 nowrap 超宽」的残余（不判 fail）。 | `TableLayoutProbe.imageTableFitsViewport` |

证据层级：最低 **L2**（WKWebView 实际布局）；不上 L3/L4。L2 探针编译生产 `MessageBodyStyle.swift`，夹具为合成 HTML（不含真实邮件字段），源码与原始输出入 `task-spaces/20261123-table-adapt/evidence/`。

## 状态

`designed`（2026-11-23 设计；`T-1123-04` 实现、`T-1123-05` 验证后转 `verified`）。定级 **P3**；`REQ-0027` 方案已人工确认（压缩适配，2026-11-23）。

## 与相邻场景的边界

- `SCN-0004`：正文基本渲染/补拉/CSP 归它；本卡只认领表格宽度适配，不重复认领正文可用性。
- `SCN-0019`：内联图渲染归它；本卡只要求表格适配不改变 `img` 规则与 `inlineImageHTML` 换串行为。
- `SCN-0015`：字号缩放归它；本卡只验证四档 `pageZoom` 下页面不横向溢出（新增断言）。
- `SCN-0020`：附件条取用归它；本卡不涉及附件。
