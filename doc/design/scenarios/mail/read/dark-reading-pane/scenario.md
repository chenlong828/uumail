---
layer: design
module: mail
scope: project:uumail
status: designed
updated: 2026-11-16
flow: mail/read
scenario: SCN-0010
---

# SCN-0010 深色主题下的邮件阅读

## 结果

用户在深色主题下（系统深色 + 跟随系统，或菜单强制深色）打开一封邮件，正文内容区是**不透明白色画布**：未声明背景的纯文本/HTML 邮件以白底深字正常显示；邮件作者显式声明的背景色、文字色、表格与图片布局保留。作者的 `prefers-color-scheme: dark` 媒体变体在正文画布按浅色求值、不生效；不使用暗色阅读主题、不做邮件反色。附件条、远程图片开关、截断提示等正文之外的 chrome 仍随应用主题。切换主题、切换邮件、复用 WebView 或重开窗口后正文仍白，且不重新加载正文、不重新拉取。

## 入口

- `CMP-APP#MessageBodyStyle.sanitized`（`baseCSS` 白底兜底 + CSP 注入；`Sources/uumail/MessageBodyStyle.swift`，由 `MessageBodyView.swift` 抽出）
- `CMP-APP#MessageWebView.makeNSView` / `#updateNSView`（`WKWebView` 创建/复用：沿用现有 KVC 把 `drawsBackground` 设为 `true`、`underPageBackgroundColor = .white`、`appearance = .aqua`；`updateNSView` 复确认外观，不触发重载）
- `CMP-APP#MessageBodyView`（`.loaded` 分支；`Sources/uumail/MessageBodyView.swift`）
- `CMP-APP#UumailApp`（`preferredColorScheme` 提供深色前置条件；不在阅读组件里写主题规则）
- `CMP-PRES#BodyPresentation.loaded(html:truncated:)`（正文数据；本景不改契约）
- `CMP-APP#MessageBodyView` 的附件条 / 远程图片开关 / 截断 banner（正文之外，仍随主题）

## 运行序

流程 `F-READ-04`：

1. 应用处于深色主题（系统深色 + 跟随系统，或 `SCN-0011` 强制深色）。用户选中邮件，`MailboxViewModel` 缓存优先得到 `BodyPresentation.loaded(html, truncated)`；本景不触网。
2. `MessageBodyView` 渲染 `.loaded` → 创建或复用 `MessageWebView`。画布固定为不透明浅色：沿用现有 KVC `setValue(true, forKey: "drawsBackground")`、`underPageBackgroundColor = .white`、`appearance = .aqua`；`updateNSView` 在 SwiftUI 更新后复确认 `appearance`，但 `lastRender` 未变时**不**调用 `loadHTMLString`。
3. `MessageBodyStyle.sanitized` 先注入 CSP，再注入 `baseCSS`：`html, body { background-color: #ffffff; color-scheme: light; }` 与默认深色文字（沿用 `#1d1d1f`）；作者样式在其后，显式 `background-color`/`color`/表格/图片布局不被覆盖。
4. 正文画布的 `prefers-color-scheme` 固定为 light（`appearance = .aqua` + `color-scheme: light`）：作者 dark-mode 媒体变体不生效；作者显式静态背景/文字色仍保留。
5. 用户切换主题（`SCN-0011`）：应用 chrome 立即变化；正文不重新 `loadHTMLString`、不重新拉正文、不改变滚动位置/选中，画布仍白。
6. 用户切换到另一封邮件：新正文走同一规则；复用 WebView 时外观与兜底样式仍生效，不出现「上一封白、下一封透明」。
7. 附件条、远程图片开关、截断提示、加载/失败占位在画布之外，跟随应用主题，不强制白。远程图片开关只改变 CSP 的 `img-src`，不改白底、禁 JS 与作者样式。

失败路径：

- 正文获取失败 → `.failed` / 摘要回退按应用主题显示，不出现白色空块；重试入口可用。
- HTML 无 `<head>`、标签不闭合或为空 → 仍包裹出带白底与 CSP 的文档；空正文显示白色画布而非透明。
- 作者显式深色背景/白字 → 保留作者样式，不做反色；白底只在其透明区域下方兜底。
- 主题切换发生在正文加载中 → 只影响 chrome；正文完成后仍按白底规则显示，不重复加载。
- WebView 复用后外观状态过期 → `makeNSView` 设置常量、`updateNSView` 复确认；不得依赖创建时的一次性设置。
- 远程图片被 CSP 阻止 → 白底与文字仍正常，不退回透明画布。

## 不可变引用

- T5：WKWebView 禁 JS；CSP `default-src 'none'`，远程资源默认阻止、单封可临时放行；本景不改安全策略。
- D10：`FetchedBody{text,isHTML,isTruncated}` 语义不变；截断提示仍由 `BodyPresentation.loaded(truncated:)` 透传。
- 阅读读路径不触网：缓存命中与打开不因本景新增网络；补拉仍归 `SCN-0004`。
- `baseCSS` 是兜底不是主题：作者显式背景/文字色/表格/图片布局不得被覆盖；不得改写正文文本。
- 正文画布的 `prefers-color-scheme` 固定 light（作者暗色媒体变体不生效）；这是 `doc/history/decisions/2026-11-16-theme-appearance.md` 的明确取舍，产品若要保留暗色变体需先改 `REQ-0015`/本卡。
- 不新增/修改 `MailDomain`、`MailStore`、`Scenes` 契约；不新增 schema；不改附件与已读逻辑。
- `SCN-0004` 只做打开/缓存/补拉/截断回归，不新增本卡断言，不重复认领底色。
- `SCN-0011` 的主题选择只改应用 chrome；正文白底规则不随主题反向变化。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID |
|---|---|---|---|---|
| `T-SCN-0010-01` | 正 | L2 | 深色主题下打开无背景纯文本/HTML 邮件 → 画布采样为不透明白色（#FFFFFF），默认文字为深色；`baseCSS` 含白色兜底与 `color-scheme: light`；浅色主题下采样一致。 | `AppearanceProbe.lightFloorAndCSP`（直接编译生产 `MessageBodyStyle.swift`）+ `AppearanceProbe.readingPaneIsOpaqueWhiteInDarkMode`（`takeSnapshot` 中心/下部采样） |
| `T-SCN-0010-02` | 正 | L2 | 深色/浅色/跟随系统来回切换，并在切换后换一封邮件、重开窗口 → 阅读区始终白；切换不触发 `loadHTMLString`、不拉正文、不改滚动与选中；复用 WebView 无透明闪烁。 | `AppearanceProbe.readingPaneStaysWhiteAcrossThemeAndMessageSwitch`（记录 `WKNavigationDelegate` 计数与两次采样） |
| `T-SCN-0010-03` | 正 | L2 + L1 | 正文自带显式白/深/彩色背景、表格与图片 → 作者样式保留，白底只在透明区域兜底；作者 `prefers-color-scheme: dark` 变体不生效；开启远程图片后仍白底。附件条、远程图片开关与截断提示跟随应用主题——**用代码审查 + 现有视图测试判定（L1）**，不再做像素/截图断言。 | `AppearanceProbe.senderStylesPreservedAndDarkMediaSuppressed`（`#123456` 采样 + dark-media 采样；用 body 级背景或采样点落在作者着色元素内，实测 sRGB 约 `rgba(21,69,105,1.00)`，断言用容差 ±2/通道）；chrome 部分：代码审查确认 `AttachmentBar`/远程开关/截断提示不写死白色 + `MailboxViewModelTests` 现有用例（L1） |
| `T-SCN-0010-04` | 反 | L2 | 畸形/无 `<head>` 且含 `<script>` 与远程 `<img>` 的正文 → 仍得到白底与 CSP、脚本不执行、远程请求被阻止、不崩溃；加载失败态跟随主题而不是白色空块；作者深色背景不被强制反色。 | `AppearanceProbe.malformedHTMLStillGetsLightFloorAndCSP` + `AppearanceProbe.failedBodyUsesThemeNotWhite` |

> 证据层级：L1 单元测试 / L2 无头探针 / L3 截图 OCR / L4 GUI 自动化（AX）。本卡最高 L2，不做截图与 AX。
>
> 夹具精度（D2，2026-11-16）：`T-SCN-0010-03` 的作者背景采样必须用 body 级背景或把采样点落在作者着色元素内；`#123456` 的 `takeSnapshot` 实测约 `rgba(21,69,105,1.00)`（sRGB），断言用容差，不对源 hex 精确相等。页面中心落在未着色区域时采样为白色是 `baseCSS` 兜底生效，不是作者样式被覆盖。
>
> 测试替身：像素用独立 `AppearanceProbe`（直接编译生产 `MessageBodyStyle.swift`，不新增 `uumail` 测试 target）；探针源码、命令、原始采样值入 `task-spaces/<run>/evidence/`。无替身的断言不得标 `verified`。

## 状态

`designed`（2026-11-16，T-1116-01 落卡）。Q6 已按 A 确认（只正文画布）；P2 已确认。四元素齐；`T-SCN-0010-01..04` 为 3 正 1 反可执行 ID。实现与验证完成后由收尾节点转 `verified`；本轮实现节点只建议翻转，不自行改状态。

**已实现与验证（2026-11-16，T-1116-03/06）**：`MessageBodyStyle.swift` 已承接 `baseCSS`/CSP/`sanitized`，`MessageBodyView` 的 `WKWebView` 固定不透明浅色并在 `updateNSView` 复确认外观。`AppearanceProbe` 逐条通过 `T-SCN-0010-01`（深色下中心/下部 `rgba(255,255,255,1.00)`、CSP 默认 data-only）、`T-SCN-0010-02`（切主题导航增量 0、换邮件增量 1、复用后仍白）、`T-SCN-0010-03`（作者 body `#123456` 采样 `rgba(21,69,105,1.00)`、dark-media 采样白）、`T-SCN-0010-04`（畸形 HTML 仍得白底与 CSP、失败占位深色）。证据：`task-spaces/20261116-154416/evidence/AppearanceProbe.txt`、`full-test.txt`、`architecture.txt`。建议收尾翻转 `SCN-0010` 为 `verified`、`REQ-0015` 为 `delivered`。
