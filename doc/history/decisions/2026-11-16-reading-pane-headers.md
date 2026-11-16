---
layer: history
module: mail
status: frozen
updated: 2026-11-16
---

# 阅读页信封头：P2 确认（D1–D8）与实现边界（2026-11-16）

## 背景

`REQ-0017`（阅读页展示信封头信息）在 2026-11-16 完成需求分析，`SCN-0012` 已落为 `designed`。设计把改动收敛到 `CMP-PRES`（`MessageHeaderPresentation` / `MailboxViewModel.headerPresentation`，纯映射与派生）与 `CMP-APP`（`MessageHeaderView`、`MessageBodyView(header:)`、`MailboxView` 接线），不新增组件/target/依赖，不改 `MailDomain`/`MailStore`/`Scenes` 契约。

按 `arch-design-spec`，本批新增 public 类型与 public 派生属性、跨 `Presentation`/`uumail` 两个 target，定为 **P2**。`design.md` §9.2 列出 D1–D8 待人工确认；`roadmap.md` §W-M3-05 将其排为任务链首的人工门 `T-1116-07`，门未关闭前不得改 `Sources/`。2026-11-16 的实现准出评审因此判 fail：确认记录缺失，开发节点停在门前。

## 确认来源与范围

- 本记录由 W-M3-05 实现批次（run `20261116-212545`）在代码评审回退重跑时归档。
- 确认来自任务发起人在本次 agent-flow 回退重跑中给出的执行指令：先回 confirm 阶段关闭 `T-1116-07`（按 `design.md` §9.2 确认 D1–D8，并落 `history/decisions/2026-11-16-reading-pane-headers.md`），再重跑开发 `T-1116-08`→`T-1116-09`。
- 发起人**未逐项改写** D1–D8；按 `design.md` §9.2 的**唯一建议答案**确认，无收窄、无改选。原始确认没有独立 IM/邮件原文；**本记录是唯一书面落点**，不把编排指令伪造成第三方签字。
- 确认人：任务发起人（工作区所有者）；确认时间：2026-11-16（本次回退重跑指令）；确认项：D1–D8；影响范围：`REQ-0017` / `SCN-0012` / `CMP-PRES` / `CMP-APP` 的 P2 实现与 L1/L2 验证，以及本批任务 `T-1116-07`…`T-1116-10`。

## 决定

| # | 确认项 | 结论 |
|---|---|---|
| D1 | 公开类型名与形状 | `MessageHeaderPresentation` + 嵌套 `Row`；字段为 `subject` + `rows`；`init(message:)` public（L2 探针需要）。`Row` 保留 `label`/`value`/`lineLimit` 与 public `init(label:value:lineLimit:)`，`Row.id = label`；**不**按评审 N4 收窄公开面，保持设计形状，避免探针与规格漂移。 |
| D2 | 派生属性 | `MailboxViewModel.headerPresentation` 为 public 计算属性，无存储、无缓存；`nil` **当且仅当** `selectedMessage == nil`。 |
| D3 | 字段顺序与标签 | 主题（无标签）→ 发件人 → 收件人 → 抄送 → 时间；标签右对齐、固定宽 44pt；行序与标签按 `CMP-PRES` 设计增量固定。 |
| D4 | 行上限与 R27 预算 | 主题 2 / 发件人 1 / 收件人 2 / 抄送 2 / 时间 1；头部文本块 ≤170pt；默认窗口（≥900×560）正文 ≥300pt；L2 探针 320pt 面板下方正文区 ≥150pt。 |
| D5 | 收件人展示 | 信封原文（保留显示名），不引 `AddressList`、不新增收件人/抄送 `DisplayFormat` API；`To` 用 `recipients`，`Cc` 用 `cc`。 |
| D6 | `.none` 收口 | `header != nil` 时 `.none` 按「正在获取正文」显示并保留头部；占位「选择一封邮件」仅在 `header == nil`（无选中）时出现。 |
| D7 | 文本可选范围 | `.textSelection(.enabled)` 只加在头部块与无选中占位；不加在详情根、不碰 `WebView` 子树。 |
| D8 | L2 载体 | 独立 `HeaderProbe` + 两段最小模块（`MailDomain`、`Presentation` 只编本景用到的生产文件），不新增 target；断言先要求字段存在再比对值；`.loaded` 段链生产 `MessageBodyView`/`MessageBodyStyle` + WebKit。 |

## 影响

- `CMP-PRES` 新增一个 public 值类型与一个 public 只读派生属性；`CMP-APP` 新增一个 internal 视图并给 `MessageBodyView` 增加 internal `header:` 入参，均属 additive、兼容性变更。
- 不新增依赖/target/schema，不改 `MailDomain.Message`、`MailStore`、`MailGateway`/`Scenes`，不改列表/工具栏/搜索/附件条/同步/发送；阅读热路径仍零网络，头部是纯本地派生。
- 实现与验证按 `roadmap.md` §W-M3-05：`T-1116-08`（`CMP-PRES`，L1）→ `T-1116-09`（`CMP-APP`，L2）→ `T-1116-10`（`SCN-0012` 复跑 + 回归）。**开发/评审不翻转 `SCN-0012` 的 `verified` 与 `REQ-0017` 的 `delivered`**，只由收尾在评审通过后执行。
- 回滚 = 回退实现与测试；无 schema/数据迁移，无持久化头部数据。

## 未采纳 / 明确不做

- 不按 N4 把 `Row.init` 收成 internal；D1 需要独立 L2 探针能构造夹具，且本批不改设计形状。
- 不显示 Bcc/Reply-To/Message-ID/会话/重要性/附件数；不解析通讯组、不查 GAL、不做头像/发件人卡片。
- 不做折叠/展开、点击地址复制、按发件人搜索、回复/转发菜单；不引入真实 `Sent` 时间。
- 不做 L3 截图/OCR、L4 AX/VoiceOver；`SCN-0012` 最低 L2，语音朗读仍未验证。

## 落点

- 需求/场景：`doc/requirements/REQ-0017-reading-pane-headers.md`、`doc/design/scenarios/mail/read/message-headers/scenario.md`（`SCN-0012`）。
- 规格：`doc/design/components/CMP-PRES/spec.md`、`doc/design/components/CMP-APP/spec.md`（设计增量由「待确认」改为「已确认」，实现后追加进度行）。
- 排期：`doc/plan/roadmap.md` §W-M3-05（`T-1116-07` 确认记录落盘后放行 08/09）。
- 实现：`Sources/Presentation/MessageHeaderPresentation.swift`、`Sources/Presentation/MailboxViewModel.swift`、`Sources/uumail/MessageHeaderView.swift`、`Sources/uumail/MessageBodyView.swift`、`Sources/uumail/MailboxView.swift`。
- 测试/证据：`Tests/PresentationTests/MessageHeaderPresentationTests.swift`、`Tests/PresentationTests/MailboxViewModelTests.swift`；L2 证据入 `task-spaces/20261116-212545/evidence/header-probe/`。
