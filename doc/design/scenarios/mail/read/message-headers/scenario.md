---
layer: design
module: mail
scope: project:uumail
status: designed
updated: 2026-11-16
flow: mail/read
scenario: SCN-0012
---

# SCN-0012 阅读页信封头

## 结果

用户在邮件列表选中一封邮件，右侧阅读区在正文上方显示这封邮件的信封头：主题作为标题行，其下是发件人、收件人（To）、抄送（有则显示）与时间（服务器 `DateReceived`，格式沿用 `DisplayFormat.messageDate`）。头部只读本地已同步字段，选中变化时立即换成新邮件；正文尚未开始、加载中、加载完成或加载失败时头部都在，且只属于当前选中邮件。没有选中邮件时头部不出现，只显示「选择一封邮件」占位；空字段隐藏对应行，不出现空标签；主题缺失显示「(无主题)」。头部随应用主题（深色下不强制白），头部文本可选中复制（不提供地址菜单、复制按钮或按发件人搜索）。

## 入口

- `CMP-PRES#MailboxViewModel.selectedMessage`（当前选中邮件的唯一来源；复合 `listKey` 身份，含搜索跨文件夹）
- `CMP-PRES#MailboxViewModel.headerPresentation`（新增；只由 `selectedMessage` 派生，无自己的状态、不触网）
- `CMP-PRES#MessageHeaderPresentation`（新增；`subject` + 有序 `rows`，空字段在映射时丢弃；形状见 `design/components/CMP-PRES/spec.md` 设计增量）
- `CMP-PRES#DisplayFormat.messageDate`（复用既有时间格式与回退，不新增收件人/抄送格式化 API）
- `CMP-APP#MailboxView`（把 `viewModel.headerPresentation` 传给阅读区；不读 `Message` 字段）
- `CMP-APP#MessageBodyView`（新增 `header:` 入参；头部渲染在正文状态之外，四种正文态共用）
- `CMP-APP#MessageHeaderView`（新增视图文件；只渲染展示值，不拼地址、不判空）
- `CMP-DOMAIN#Message`（`subject`/`sender`/`recipients`/`cc`/`receivedRaw` 只读；不改字段）
- 不涉及 `CMP-STORE`、`CMP-SCN-READ`、`CMP-SYNC`、`CMP-EAS*` 的新调用；头部不触网、不写库、不写偏好。

## 运行序

流程 `F-READ-05`：

1. 用户在列表点击/键盘选中一封邮件（或自动选中首封、搜索命中）→ `MailboxViewModel` 以复合 `listKey`（folder + serverID）解析 `selectedMessage`；本步骤纯本地，不触网。
2. `headerPresentation` 在读取时由 `selectedMessage` 派生（纯映射，无缓存）：主题取 `subject`，空白/缺失 →「(无主题)」；行按「发件人 → 收件人 → 抄送（非空才出现）→ 时间」排列；时间取 `receivedRaw` 经 `DisplayFormat.messageDate`；空字段整行丢弃。映射规则与行上限以 `CMP-PRES`/`CMP-APP` 设计增量与契约为准，本卡不复制契约。
3. `MailboxView` 只把 `viewModel.headerPresentation` 传给 `MessageBodyView`；`MessageBodyView` 在正文区域上方渲染头部与分隔线，头部在正文状态机之外，因此 `.loading`/`.loaded`/`.failed` 都保留头部。
4. 正文状态 `.none` 有两种含义，由头部是否存在区分：`header != nil`（刚选中、正文任务尚未开始）按「正在获取正文」显示并保留头部；`header == nil`（无选中）只显示「选择一封邮件」占位。
5. 选中变化 → 同一次状态更新内头部换为新邮件；随后按 `SCN-0004` 取消上一封正文 task、重置并加载正文。旧邮件的发件人/收件人/抄送/主题/时间不得残留。
6. 搜索模式/跨文件夹 → 头部跟随 `selectedMessage` 的复合身份；同一 `serverID` 出现在不同文件夹时，头部属于真正选中的那一行。
7. 空字段（`sender`/`recipients`/`cc`/`receivedRaw` 为 nil 或空白）隐藏对应行；主题缺失用「(无主题)」；时间无法解析沿用 `DisplayFormat.messageDate` 的既有回退，不崩溃。
8. 无选中（清空选择、删除后无下一封、列表为空、切换文件夹）→ 头部消失，只显示占位；不保留上一封的头部。
9. 外观：头部随应用主题（标签用 `secondary`，不写强制色）；不写主题偏好；不影响正文画布的白色兜底、禁 JS 与 CSP（`SCN-0010`）。

失败路径：

- 正文补拉失败（离线/503/鉴权失败）→ 头部仍显示当前邮件的信封，正文按 `SCN-0004` 显示摘要回退或重试态；头部不消失、不显示上一封。
- 长主题/多收件人/超长地址 → 行数上限内换行或截断（主题 ≤2 行，发件人/时间各 ≤1 行，收件人/抄送各 ≤2 行）；头部文本块 ≤170pt，正文区域在默认窗口（≥900×560）下仍 ≥300pt 可用高度且可滚动，不出现布局崩溃或正文被完全挤出。
- 字段为 `nil`/空白/畸形日期 → 隐藏或按既有回退显示，不出现 `nil`、空标签或崩溃。
- 切换选中时正文 task 被取消 → 头部只跟随选中，不因取消被清空或回退到上一封。
- 头部渲染不得触网、写库、写偏好或记录真实地址/主题到日志。
- 深色主题切换 → 头部随主题；正文白底不回归（`SCN-0010`）。

## 不可变引用

- `MailDomain.Message` 的公共字段与语义不变；`MailStore` schema、查询列与迁移不变；`MailGateway`/`Scenes` 不新增方法。
- 阅读热路径不触网（`SCN-0004`）；选中身份用复合 `listKey`（R23），不退回只按 `serverID`。
- `SCN-0004` 的正文打开、缓存优先、补拉、截断、CSP；`SCN-0010` 的正文白底；`SCN-0008`/`SCN-0009` 的已读/删除；`SCN-0005` 的附件条 —— 均不因本场景改变语义。
- 头部不是新的持久化数据：不新增表/列，不写 Keychain/网络，不缓存第二份信封。
- `REQ-0016` 的主题偏好与菜单不改；头部只消费应用当前外观。
- 头部不显示 Bcc/Reply-To/Message-ID/会话/重要性/附件数量；不解析通讯组、不查 GAL/联系人。
- 头部文本可选中复制属于系统文本选择，不是「点击地址复制/按发件人搜索」交互；不新增按钮、菜单或简介卡片。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID |
|---|---|---|---|---|
| `T-SCN-0012-01` | 正 | L2 | **两条夹具**。(a) 完整信封（主题「季度评审」、发件人 `"赵六" <zhao@example.com>`、收件人 `"李四" <li@example.com>`、抄送 `"王五" <wang@example.com>`、`receivedRaw` 合法 ISO-8601，正文 `.loading`）→ 头部字段按序等于「主题、发件人、其值、收件人、其值、抄送、其值、时间、`messageDate` 值」，且头部字段都落在正文区域上方（`.loading` 下头部仍在）。(b) 长值完整信封（200 字主题、12 个收件人、无 Cc）→ 行数只由字段存在性决定（本夹具为「主题 + 发件人/收件人/时间」），主题 ≤2 行、收件人 ≤2 行，头部文本块 ≤170pt，下方正文区仍 ≥150pt（320pt 探针面板；默认窗口下 ≥300pt）。 | `HeaderProbe.completeHeaderRowsWhileLoading`、`HeaderProbe.longHeaderStaysBounded` |
| `T-SCN-0012-02` | 正 | L2 | 稀疏信封（无 Cc、`subject` 为 nil、发件人为裸地址、收件人存在、`receivedRaw` 畸形、`cc` 为空白）→ 头部不出现「抄送」字段；主题为「(无主题)」；发件人/收件人保留；时间按 `DisplayFormat.messageDate` 回退；不出现空标签、空行或 `nil`。 | `HeaderProbe.sparseHeaderHidesEmptyRows` |
| `T-SCN-0012-03` | 正 | L2 + L1 | 选中 A 后切到 B，B 的正文处于 `.loading` 再到 `.loaded` → 切换后头部立即为 B；任何时刻都不出现 A 的主题/发件人/抄送；B 正文完成后头部不变；不新增网络请求（L1：`headerPresentation` 是纯派生，`openSelected` 未新增调用）。`.loaded` 夹具用最小 HTML，不含真实邮件内容。 | `HeaderProbe.switchUpdatesHeaderWithoutStaleRows`；L1 `MailboxViewModelTests.headerPresentationFollowsSelection`（含跨文件夹同 `serverID`） |
| `T-SCN-0012-04` | 反 | L2 | 选中 B 后正文补拉返回 503（`.failed`）→ 头部仍是 B 的信封，正文显示重试/摘要态；随后清空选中（或切到空列表）→ 头部字段全部消失，只剩「选择一封邮件」占位。 | `HeaderProbe.failedBodyKeepsHeaderThenClearingDropsIt` |

证据层级：L1 单元测试 / L2 无头探针 / L3 截图 OCR / L4 GUI 自动化（AX）。本卡最低 L2，不上 L3/L4。

测试载体（可读 seam 已由设计探针证明；`MessageBodyView` 的 `.loaded` 一段留实现节点补齐，见 `task-spaces/20261116-212545/evidence/header-probe/`）：

- **L2 `HeaderProbe`**：独立可执行文件，直接编译生产 `Sources/uumail/MessageHeaderView.swift`；`Presentation`/`MailDomain` 用同源生产文件按最小模块编译（`MessageHeaderPresentation.swift`、`ErrorText.swift`、`PresentationTypes.swift`、`Values.swift`、`Errors.swift`）。离屏 `NSHostingView` + 无边窗口宿主，读 SwiftUI 可选中 `Text` 背后的 `NSTextField.stringValue`，按 y 降序/x 升序还原行序；不截图、不 OCR、不需要辅助功能授权、不新增 target、不启动 app bundle。设计阶段探针用与 `MessageBodyView` 同结构的离屏面板验证状态分支；`T-SCN-0012-03` 的 `.loaded` 一段由实现节点把面板换成生产 `MessageBodyView`/`MessageBodyStyle` 并链 WebKit（`SCN-0010` 的 `AppearanceProbe` 已有离屏 WKWebView 先例）。断言必须**先要求字段存在**再比较值：若 SwiftUI 改掉可选文本的承载方式，探针应红，不得静默通过。
- **L1**：`PresentationTests` 覆盖 `MessageHeaderPresentation` 的映射（行序、隐藏行、`(无主题)`、日期回退、清空空白）与 `MailboxViewModel.headerPresentation` 的来源（选中/切换/跨文件夹同 `serverID`/无选中）。
- 探针证据按 `T-SCN-0012-01..04` 入 `task-spaces/<run>/evidence/`，只用假数据，不写真实邮箱/主题。
- 设计阶段探针只覆盖 `.loading`/`.failed`/`.none` 三种纯 SwiftUI 正文态；`.loaded` 的 WebView 白底与 CSP 回归属 `SCN-0004`/`SCN-0010`，本卡不重复断言。
- `.loading` 下附件条本来就不渲染，「正文/附件条不被头部改变」由 `SCN-0004`/`SCN-0005` 回归判定，不塞进 `T-SCN-0012-01` 的 L2 断言。
- 若某条 skip，必须有替身并登记，否则最多 `designed`，不能标 `verified`。

## 状态

`designed`（2026-11-16 设计落卡）。四元素：入口 `present`、运行序 `present`（含失败路径）、不可变引用 `present`、测试 `present`（3 正 1 反，`T-SCN-0012-01..04` 可执行，最低 L2）。

L2 探针 seam 已由设计探针验证（`task-spaces/20261116-212545/evidence/header-probe/header-probe-4.txt`，四条测试形态共 14 条断言全 pass）；L1 映射与 VM 用例见 `CMP-PRES` 设计增量的测试计划。公共契约增量属 P2，**人工确认后才合并实现**；未实现、未 `verified`。

`verified` 判据：`T-SCN-0012-01..04` 全 pass；`SCN-0004`/`SCN-0010` 回归不退化；无 skip 或 skip 有登记替身。

## 与相邻场景的边界

- `SCN-0004` 邮件阅读：正文打开/缓存/补拉/截断/CSP；本场景不重复认领。2026-11-16 已把 `SCN-0004` 结果句中的「信封」收窄为正文。
- `SCN-0010` 深色阅读白底：正文画布；头部随应用主题，不强制白，也不改白底机制。
- `SCN-0008`/`SCN-0009`：已读/删除；头部不因列表置读或删除隐藏而改变规则（删除后无选中时头部清空）。
- `SCN-0005` 附件下载：附件条在正文区域；头部不显示附件数量、不改变附件条。
