---
layer: design
module: mail
scope: project:uumail
status: designed
updated: 2026-11-19
flow: mail/read
scenario: SCN-0018
---

# SCN-0018 远程图片放行后的实际加载

**结果**：用户打开一封含远程图片的 HTML 邮件、在主工具栏点「加载远程图片」开启放行后，当前这封邮件正文里被 CSP 允许的**远程图片真正被请求并显示**（受控明文 http 源：请求到达且图片解码成功、非破图），不再只是切换了一个看不见的 CSP 档位。默认、关闭、切换邮件后仍不发起任何图片请求；放行仍只作用于当前邮件、会话内临时有效；禁 JS、`default-src 'none'`、白底与作者样式、正文 HTML/sanitizer、开关位置与状态机都不变。用户实际运行的 release app bundle 携带使明文 http 图片可在 WebView 内容里加载的传输层配置，而应用网络路径（EAS/URLSession）不被放宽；`swift run`（无 bundle `Info.plist`）的载体行为有明确结论。

## 入口

- `CMP-APP#MessageWebView` / `#MessageBodyStyle`（既有，本景**不改**；`loadHTMLString(_, baseURL: nil)`、放行/阻止两档 CSP、禁 JS、`lastRender` guard 原样保留）
- `CMP-APP#MessageBodyView`（既有，本景不改；只把 `allowRemoteContent` 转交 WebView）
- `CMP-PRES#MailboxViewModel.allowsRemoteContent` / `#canAllowRemoteContent` / `#setAllowsRemoteContent(_:)`（既有，本景不改；`SCN-0013` 已认领其状态机）
- 交付载体（本景新增/改）：
  - `Resources/Info.plist`（新增，受版本管理；含 `NSAppTransportSecurity/NSAllowsArbitraryLoadsInWebContent = true`，不含 `NSAllowsArbitraryLoads`/`NSExceptionDomains`）
  - `Scripts/make-app.sh`（改为 `cp Resources/Info.plist "$APP/Contents/Info.plist"`；release 构建、图标、ad-hoc 签名、`build-info.txt` 不变）
- `CMP-APP#ComposeEditor` + `CMP-PRES#ComposeDocument.editorDocument(emailHTML:allowRemoteContent:)`（既有，本景不改；ATS 例外对其同样生效，但其图片仍由同一放行档 CSP 门控）
- 不涉及：`MailDomain`/`MailStore`/`Scenes`/`CMP-PRES` 契约、schema、偏好、协议；不新增 target/依赖/第三方库；不改开关入口/位置/可用条件。

## 运行序

流程 `F-READ-07`（复用 `SCN-0013` 的 `F-READ-06` 入口与状态机，只补第 3–5 步的网络/载体结果）：

1. 用户选中一封正文 `.loaded` 的 HTML 邮件；工具栏「加载远程图片」默认关；正文以阻止档 CSP（`img-src data:`）渲染。**此时服务端 0 次图片请求**（图片主机不可达或服务端从未被访问都一样）。
2. 用户点击入口 → `setAllowsRemoteContent(true)`（受 `canAllowRemoteContent` 守卫，同 `SCN-0013`）→ `MessageBodyView` 以 `true` 调 `MessageWebView` → `MessageBodyStyle.sanitized` 注入放行档 CSP（`img-src data: https: http:`）→ `loadHTMLString` 重载。
3. **传输层**：WebKit 按 CSP 允许的 scheme 发起图片请求；明文 `http` 子资源只有在承运进程具备 ATS WebView 内容例外时才真正出网。release app bundle 的 `Info.plist` 必须带 `NSAllowsArbitraryLoadsInWebContent = true`：
   - 受控 http 源：服务端命中 ≥1，图片解码成功（`img.naturalWidth/naturalHeight > 0`，非破图/非空白），快照出现图片像素；
   - 用户样本（发布前/人工冒烟）：可见图片显示；1×1 `display:none` 跟踪像素可与可见图一起被请求，不要求可见。
4. 用户再次点击关闭 → 恢复阻止档 CSP 并重载；**关闭后不再新增图片请求**（服务端命中不增长）。其它邮件不受影响。
5. 切换选中邮件 A→B：`allowsRemoteContent` 在同一状态更新内复位为 `false`；B 以阻止档渲染、**服务端 0 次请求**；返回 A 仍为关；重开窗口/应用默认关；旧正文未替换时 setter no-op、0 请求。
6. 运行载体：`swift run` 的可执行无 bundle `Info.plist`，无 ATS 域策略，明文 http 图片本来即可加载（设计期 L2 矩阵已证）；release `./Scripts/make-app.sh` 的 `dist/uumail.app` 必须安装 `Resources/Info.plist` 原样副本。两种运行方式都要有明确结论，不能只修好一种。
7. 入口变化仍只改放行状态与当前正文重渲染；不改正文 HTML/sanitizer、附件条、截断 banner、信封头、列表或侧栏；不写偏好/不写库/不发额外命令。

失败路径：

- **载体缺 ATS 键**（旧 `dist`、手改脚本、MDM/系统策略剥离）→ 放行档仍然 0 次请求、图片空白（复现用户症状）。由 `T-SCN-0018-03` 的配置断言 + `T-SCN-0018-01` 的正例在验证期抓出；**不得**以「CSP 字符串正确/开关为 true」判过。
- 图片主机 403/404/超时/DNS 失败 → 正文照常显示与滚动，破图/空位可见，不弹错、不崩溃、不回退入口状态、不自动重试（同 `SCN-0013` 失败路径）。
- 防盗链/主机下线/内容删除（外部不可控）→ 破图；**不算本卡回归**；用户样本必须由发布前冒烟确认可见。
- 无选中 / 正文 `.loading` / `.failed` / 旧正文未替换 → 入口禁用或 setter no-op，状态不变、0 请求（回归 `SCN-0013-04`）。
- 真实用户样本只用于冒烟；自动化夹具用假 HTML + 受控 http 源，不把真实主题/URL/主机/账号写入测试或 evidence。

## 不可变引用

- `SCN-0013` 已验证的全部承诺：工具栏位置与顺序、开关状态机、单封会话内临时放行、切换/重开复位、CSP 两档精确值、禁 JS、`default-src 'none'`、白底与作者样式、`lastRender` guard 与主题不重载、正文 HTML/sanitizer 不被无谓改写。
- `SCN-0004` 的「默认阻止 + `<script>` 不执行」完整欠账仍归 `SCN-0004`（`T-SCN-0004-03`）；本卡的「阻止档零请求」只覆盖开关路径，不代替它。
- `SCN-0016` 撰写编辑器与 `SCN-0015` 字号、`SCN-0010` 白底、`SCN-0012` 信封头：只回归，不新增断言。
- 安全：`NSAllowsArbitraryLoadsInWebContent` 是**唯一**放宽项；不得出现 `NSAllowsArbitraryLoads`、`NSExceptionDomains`；不放宽 URLSession/EAS 网络路径；不伪造 Referer/Cookie；不做代理、缓存、离线保存、URL 改写、`cid:` 解析、懒加载、图片查看器。
- 契约：不改 `MailDomain`/`MailStore`/`Scenes`/`CMP-PRES` 公开契约；不改 schema/协议/数据所有权；不新增 target/依赖；单文件 ≤300 行（本景 `Sources/uumail` 零行数变化）。
- 载体契约：release `dist/uumail.app/Contents/Info.plist` 必须与 `Resources/Info.plist` 字节一致，且 `dist/build-info.txt` 的 commit 与构建时 HEAD 一致。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID |
|---|---|---|---|---|
| `T-SCN-0018-01` | 正 | **L2** | 生产 `MessageWebView`/`MessageBodyStyle` 编进探针，宿主离屏 `NSWindow`；探针 `.app` 的 `Contents/Info.plist` = `Resources/Info.plist` **原样副本**（探针二进制在 bundle 内命名为 `uumail` 以满足 `CFBundleExecutable`）；假 HTML 的唯一 `<img>` 指向本进程内受控 HTTP 服务器（只绑 `127.0.0.1`），URL 主机用**解析到该服务器的非本地主机名**（`127.0.0.1.nip.io` 一类）。断言：阻止档 0 命中、`naturalWidth=0`；放行档 ≥1 命中、`naturalWidth/naturalHeight>0`、快照品红像素 >0；关闭后命中不增长。**负控制**：同探针在**无 ATS 键**的 bundle 里放行档必须 0 命中（若命中说明主机名/载体设置错，测试失败）；**正控制**：`data:` 图在阻挡档也渲染（证明 CSP/像素通道正常）。 | `RemoteImageProbe.actualLoadWithShippedPlist` |
| `T-SCN-0018-02` | 反 | **L1 + L2** | L1：`Resources/Info.plist` 含 `NSAppTransportSecurity/NSAllowsArbitraryLoadsInWebContent=true`，且不含 `NSAllowsArbitraryLoads`、`NSExceptionDomains`（`plutil -p` 解析后的键断言，不做文本 grep）。L2：同一 carrier 用 `URLSession` 请求同一明文 http 地址仍被 ATS 拒绝（`App Transport Security policy requires … secure connection`），证明 EAS/应用网络路径未放宽；放行档关闭时 0 命中（隐私不回归）。 | `ProbePlist.atsScopeIsWebContentOnly` + `RemoteImageProbe.urlSessionRemainsATSRestricted` |
| `T-SCN-0018-03` | 正 | **L1 + L2** | L1：`Scripts/make-app.sh` 从 `Resources/Info.plist` 装机（不再内联 ATS heredoc）；里程碑构建后 `dist/uumail.app/Contents/Info.plist` 与 `Resources/Info.plist` 用 `cmp` 断言字节一致、`dist/build-info.txt` 的 commit 与 HEAD 一致。L2：裸可执行（`swift run` 形状，无 bundle plist）正例通过，说明两种运行方式都有明确结论、不需要为 `swift run` 加例外。 | `CarrierProbe.scriptInstallsShippedPlist` + `RemoteImageProbe.bareExecutableLoadsPlainHTTP` |

证据层级：最低 **L2**；本卡不上 L3/L4（模型不支持读图；`af-flow-rule` §1）。A5 真实样本冒烟是发布前/人工项，登记在 `SCN-0018` 的状态段与 `test.md`，不替代上述自动断言。

测试载体与纪律：

- **探针源**：`task-spaces/20261119-213812/evidence/remote-image-probe/RemoteImageProbe.swift`（设计期 L2，生产源 + 已构建库对象链接）+ `commands.md` 的复跑命令。探针不提交为生产代码。
- **配置单源**：探针 bundle 的 `Info.plist` 必须来自交付的 `Resources/Info.plist` 原样副本；若将来把 plist 改回脚本内联，`T-SCN-0018-03` 需改为「先跑 `make-app.sh` 再从 `dist` 取 plist」，代价是验证需 release 构建。
- **禁止 `127.0.0.1`/`localhost` 单独作 ATS 结论**：IP 字面量与本地网络被 ATS 豁免（设计期对照：同一无 ATS bundle 下 `127.0.0.1` 放行、非本地主机名 0 命中），只用它们会假绿。离线无法解析非本地主机名时，登记跳过（替身＝`T-SCN-0018-02` 静态键断言 + `data:` 正控制），不得静默降级。
- **人工冒烟（A5）**：用用户样本邮件（只读本地库、脱敏）在**生产 `MessageWebView` + 交付 plist** 的探针里读取 `document.images` 的完成数/自然宽计数（不记录 URL/主机/主题），并做一次真实 app 可见性冒烟；任一失败记 `test.md`，不写「应该可见」。

## 状态

`designed`（2026-11-19，设计落卡；`REQ-0024` `accepted`）。四元素：入口 `present`（含交付载体）、运行序 `present`（含失败路径）、不可变引用 `present`、测试 `present`（2 正 1 反，`T-SCN-0018-01..03`，最低 L2）。

依赖：`SCN-0013`（`verified`，本卡只读引用，不重开）；`SCN-0004`/`SCN-0010`/`SCN-0012`/`SCN-0015`/`SCN-0016` 只回归。定级 **P2**（交付载体/安全策略单点）；ATS 例外属安全策略变更，**必须人工确认**后才能实现（`REQ-0024` D4；问题与依据见 `task-spaces/20261119-213812/design.md` §12）。本卡不代签确认记录。

## 与相邻场景的边界

- `SCN-0013` 远程开关并入工具栏：认领入口位置、开关状态机、CSP 两档值、单封放行与切换复位；本卡只认领「开启后图片**实际被请求并渲染**」与「交付载体配置生效」，不重复其 CSP/状态断言。
- `SCN-0004` 邮件阅读：`T-SCN-0004-03`（默认阻止 + `<script>` 不执行）仍归该卡；本卡的前置零请求只是开关路径的起点，不代替那条欠账。
- `SCN-0016` HTML 撰写：只回归；撰写编辑器的 WebView 也受同一 ATS 例外影响，但其图片由同一 `allowRemoteContent` 放行档 CSP 门控，不新增语义。
- `SCN-0010` 深色阅读白底 / `SCN-0012` 信封头 / `SCN-0015` 字号：只回归，不改其断言。
- `SCN-0008`/`SCN-0009`/`SCN-0014`：已读与删除规则不受本卡影响。
