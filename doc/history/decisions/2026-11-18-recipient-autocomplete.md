---
layer: history
module: mail
status: frozen
updated: 2026-11-18
---

# 撰写页收件人输入联想补全：P1 默认确认（D1–D10）与设计边界（2026-11-18）

## 背景

`REQ-0022`（撰写页收件人输入联想补全）在 2026-11-18 完成需求分析（`accepted`），场景草案见 `task-spaces/20261118-080109/scenario-drafts.md`。本次设计把草案落为正式场景 `SCN-0017`（`designed`），并把改动收敛到：

- `MailDomain`：新增 `ContactAddress`/`ContactEnvelope`/`ContactDirectory`/`RecipientText` 四个 public 值类型（解析、匹配、排序、尾片段替换；无 I/O）；
- `Scenes`：`ComposeScene.recipientDirectory(account:)` 一次聚合本地已收信封；
- `Presentation`：`ComposeViewModel` 新增候选状态与焦点/文本/光标/键盘/选中方法；
- `uumail`：新增 internal `RecipientTextField`/`RecipientSuggestionList`/`ComposeRecipientForm`，`ComposeView` 接线。

不改 `MailStore`：不建 `contacts` 表、不加 v11 迁移、不新增 store 查询；只复用既有 `folders(account:)` 与 `messages(account:folder:limit:)` 读契约。`MailStore` 当前实测 **1008 行 / 1000 行硬上限**（`task-spaces/20261118-082503/evidence/design-baseline.log`；`MailStore.swift` 763 + `Migrations.swift` 167 + `SyncStoreConformance.swift` 40 + `Values.swift` 38），本批新增 0 行；既有 8 行超出登记为 `plan/risks.md` R45，不在本批扩预算，也不靠本批“顺手”修。

按 `arch-design-spec`，本批为 **P1**：`MailDomain` 是平台级扇入（6+）的稳定契约，新增 public 值类型会进入 `Scenes`/`Presentation` 的公共面；`ComposeScene`/`ComposeViewModel` 新增 public 成员；新增一套输入控件与候选层。未触模块切分/合并、核心 schema、数据所有权或热路径失败语义，但按“判不准往上取”取 P1，交评审判断。

## 确认来源与范围

- **无人值守**：本系列任务无 `confirm` 节点、无人在环，发起人未中途逐项回答。
- 依据 `auto-confirm`，以下 D1–D10 为**默认确认（未经人工）**：按 `REQ-0022` 澄清记录、`scenario-drafts.md` 的推荐项与默认值自动确认并继续。
- **本记录不是发起人签字，也不得写成「已确认（人）」或「发起人确认」**；评审可独立否决。若评审判 P1 的划分不成立、或否决任一子项，按其结论回设计，不复用本记录的结论。
- 确认对象：P1 定级、数据源、存储形态、目录语义、触发与上限、UI/键盘/IME、插入规则、公开契约、证据层级、隐私与范围。
- 影响范围：`REQ-0022` / `SCN-0017` / `CMP-DOMAIN` / `CMP-SCN-COMPOSE` / `CMP-PRES` / `CMP-APP`；`CMP-STORE` 明确不改。

## 决定

| # | 项 | 结论 |
|---|---|---|
| D1 | 数据源 | 只读本地已同步邮件的信封 `sender`/`recipients`/`cc`；跳过 Drafts(3)/Deleted Items(4)/Sent Items(5)/Outbox(6) 文件夹；不接 GAL/`Search`/`Find`、不接 macOS 通讯录、不读 Sent 镜像、不新增网络。依据 `REQ-0022` 非目标、`REQ-0012` 的已收邮件语义与架构 T12。 |
| D2 | 存储形态 | **会话内聚合**：首次聚焦时经 `ComposeScene.recipientDirectory(account:)` 读一次，`ComposeViewModel` 缓存到本次撰写页关闭；不建 `contacts` 表、不做 v11 迁移、不改 `applySyncBatch`、不调 `MailStore` 预算。理由：需求只要求「打开撰写页可用、不逐键查库」，当前真实库 125 封/647 地址，一次聚合足够；持久派生表要 schema+回填+upsert+迁移测试，并把已超 8 行的 store 预算再推高，收益（旧邮件删后名字仍在）不是本卡要求。回退：若后续产品要求持久联系人，另立需求，加 v11 `contacts` 与 store 契约；本决策不阻断。 |
| D3 | 目录语义 | 有 `<>` 取地址、`<>` 前为显示名；无 `<>` 且含 `@` 的整段视为地址、名字为空；只接受含 `@` 且无空白的 SMTP 地址；跳过裸显示名/通讯组名/Exchange DN/未闭合或空 `<>`；小写地址去重；排除当前账号自己的地址；同地址多个名字取最近一次非空名字（`receivedRaw` 降序近似最近，同值按聚合顺序稳定）；RFC 2047 编码词不解码，按「无可用名字」只显示地址。不展开通讯组、不查目录、不做拼音/首字母/模糊音。 |
| D4 | 触发与上限 | 空片段不显示；输入 1–2 字符即可出候选；每次文本变化在内存中重算，无额外点击/快捷键；每文件夹最多读最近 500 封信封，候选上限 8 条（`limit` 夹取到 1…8，0/负数返回空）；新同步邮件下一次打开撰写页可见，不做当前候选列表的实时增量刷新。 |
| D5 | UI 形态 | `ComposeRecipientForm` 内用自定义 `RecipientTextField`（`NSTextField` 的 `NSViewRepresentable`）承接焦点/光标/键盘/IME；候选用 `RecipientSuggestionList` 浮在当前聚焦字段正下方（按字段 frame 的 `PreferenceKey` 定位，Form 外的 ZStack），**不改变 sheet 宽高与表单行高**；默认不高亮；`↓` 第一条、`↑/↓` 边界停住、`Return`/`Tab` 只在有高亮时选中、`Esc` 收起；鼠标悬停只做视觉提示，不改变 `Return` 的提交目标；点击直接选中；失焦/切字段/关 sheet 收起；候选行带无障碍标签；跟随五档字号与浅/深色语义色。不采用 popover（焦点/离屏探针不稳定）与内联撑高布局（改变表单基线）。 |
| D6 | 插入规则 | 只替换当前字段最后一个顶层 `;`/`,` 之后的尾片段为**纯邮箱地址**并补 `; `；保留片段前已有分隔符与其前文本；不改其他已填地址/`Cc`/主题/正文/编辑器；光标在中间/有选区不出候选也不插入；同一地址不重复插入；选中后 `hasEdits == true`；`Draft.to`/`Draft.cc` 只含纯地址，`To:`/`Cc:` 不出现未编码显示名。 |
| D7 | 公开契约 | `MailDomain` 新增 `ContactAddress`/`ContactEnvelope`/`ContactDirectory`/`RecipientText`（public，纯值类型，只依赖 Foundation）；`ComposeScene.recipientDirectory(account:)` public（同步、非 throwing，失败返回空目录）；`ComposeViewModel` 新增 `RecipientField` 与候选/焦点/文本/光标/键盘/选中 public 成员；`uumail` 的控件与候选层保持 internal。不新增 target/依赖，不改 `Package.swift`；`Presentation` 仍不 `import MailStore`。 |
| D8 | 证据层级 | `T-SCN-0017-01`/`02`/`04` 最低 L1；`T-SCN-0017-03` 最低 **L2**：独立 `ComposeAutocompleteProbe` 在离屏 `NSHostingView`/`NSWindow` 渲染生产控件，读文本节点/控件状态与 frame，覆盖可见候选、人名+邮箱、无名字回退、选中、IME、深色/225%。不要求 L3/L4；不使用 L1 映射冒充可见性。若 L2 seam 失效，由场景卡改声明 L3 并写理由，不静默降级。 |
| D9 | 隐私 | 联系人/地址只在本地使用，不联网、不导出、不写日志、不进 evidence；L2 探针只用 `*.corp.test`/`example.test` 假数据；候选行只显示本次需要的姓名/地址。 |
| D10 | 范围 | 四种撰写模式（新建/回复/全部回复/转发）与 `To`/`Cc` 两字段都生效；不做拼音/首字母/模糊音、联系人管理页/分组/收藏/黑名单、token/芯片化、把显示名写进 MIME、Sent 镜像、GAL/通讯录、自动选中/自动发送、多账号切换、按邮件/文件夹筛选来源；不改 `AddressList` 公开行为、回复种子、MIME、`Outbox`、发送通道与投递语义。 |

## 范围变更

- 新增 public `MailDomain` 值类型 4 个、`ComposeScene` public 方法 1 个、`ComposeViewModel` public 成员若干；新增 `uumail` internal 文件 `RecipientTextField.swift`（含 `RecipientTextField`/`RecipientSuggestionList`），`ComposeView` 抽出 internal `ComposeRecipientForm`。
- 新增 `AddressList` 内部拆分器归位（`EnvelopeParser`，internal），`AddressList` 公开输出不变；这是实现层归位，不是新组件/新契约。
- **不新增** schema、迁移、store 方法、store 预算、依赖、target、`Package.swift` 改动、网络请求、MIME 形状。
- 回退方式：删除新增值类型/场景方法/VM 成员/控件文件与 `ComposeView` 接线；无 schema/数据迁移；`MailStore` 与发送链路不受影响。

## 代价 / 影响

- 每次打开撰写页并首次聚焦时，按文件夹读一次信封（真实库 125 封；每文件夹上限 500 封）；不做逐键查库。大邮箱下可能多几十毫秒，失败静默降级为空目录。
- 会话内聚合不持久：旧邮件被清理、或某文件夹未同步时，对应联系人/名字可能不可见；这是本卡接受的降级（`REQ-0022` 只要求利用已有缓存）。
- 自定义 `NSTextField` 需要与既有 SwiftUI `TextField` 在 100% 档保持同一外观/行高；若外观有明显漂移，L2 探针会红，届时回设计改控件形态，不在实现里静默改布局。
- `MailStore` 既有 1008/1000 的 8 行超出与本批无关，但会阻塞下一次 store 改动；登记 R45，本批不扩预算。
- 候选浮层覆盖在表单下方内容上（不撑高 sheet）；极端窄窗口/225% 下列表可能覆盖主题行，仍不遮挡当前聚焦字段，且可滚动/可收起。

## 未采纳 / 明确不做

| 方案 | 理由 |
|---|---|
| v11 `contacts` 派生表 + 回填 + `applySyncBatch` upsert | 需求不要求持久；schema/迁移/upsert 测试成本高；`MailStore` 已超预算 8 行；要做得先拆分或走 P1 预算调整，收益不匹配 |
| 从 Sent 镜像/outbox/草稿/通讯录取联系人 | `REQ-0022` 非目标；Sent 镜像未做；GAL 不可用；通讯录要权限与新依赖 |
| 拼音/首字母/模糊音 | 另一个能力；真实库中文名是文本，拼音索引需额外数据与规则；要则另立需求 |
| 联系人管理页/分组/收藏/黑名单/权重学习 | 超出「输入联想」一个动作，属另一张需求卡 |
| token/芯片化收件人字段 | 重构撰写表单，触碰 `SCN-0016` 的等宽/布局基线；与联想正交 |
| 把显示名写进 `To:`/`Cc:` | `MimeBuilder` 只对 Subject 做 RFC 2047；中文名进头有乱码/被拒风险；MVP 只插纯地址 |
| 自动高亮第一条 / `Return` 直接提交 | 会干扰中文输入法候选词；`REQ-0022` 明确默认不高亮、主动方向键后才允许 Return |
| popover / 内联撑高候选层 | popover 焦点与离屏探针不稳定；内联撑高改变表单基线；选浮层 + frame 锚点 |
| L3 截图 / L4 AX | L2 已能观察同一视觉结果且更稳定；不要求更高层级 |
| 当前撰写页实时增量刷新新同步联系人 | `REQ-0022` 只要求下一次打开可用；实时刷新要订阅同步流，扩大范围 |

## 落点

- 需求：`doc/requirements/REQ-0022-recipient-autocomplete.md`（`accepted`；本次只更新影响场景/状态行，不改范围）。
- 场景：`doc/design/scenarios/mail/send/recipient-autocomplete/scenario.md`（`SCN-0017`，`designed`）。
- 规格：`doc/design/components/CMP-DOMAIN/spec.md`、`CMP-STORE/spec.md`（不改声明）、`CMP-SCN-COMPOSE/spec.md`、`CMP-PRES/spec.md`、`CMP-APP/spec.md` 的设计增量；`doc/design/architecture.md` §1/§3.6/§5/§10。
- 排期：`doc/plan/roadmap.md` §W-M3-09（设计完成，任务表待 `task-split`）。
- 测试/证据：实现期 `MailDomainTests/ContactDirectoryTests`、`PresentationTests/ComposeViewModelTests`、`ScenesTests/ComposeSceneTests`、`OutboxTests/OutboxMimeTests` 与 `ComposeAutocompleteProbe`；L2 证据入 `task-spaces/<run>/evidence/compose-autocomplete-probe/`。
- 本设计不写产品代码、不跑实现测试、不翻转 `verified`/`delivered`、不发布。
