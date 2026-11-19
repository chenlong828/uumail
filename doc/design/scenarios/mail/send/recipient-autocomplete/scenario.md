---
layer: design
module: mail
scope: project:uumail
status: designed
updated: 2026-11-19
flow: mail/send
scenario: SCN-0017
---

# SCN-0017 撰写页收件人输入联想补全

**结果**：用户在撰写页（新建/回复/全部回复/转发）的收件人或抄送输入框输入少量字符，输入框下方出现候选提示框；每行显示「人名 + 邮箱」，没有可用名字时只显示邮箱；显示名优先取足宽度（约 15 个汉字的姓名/组织名一眼可见，邮箱保留可辨的下限），约 15 个汉字的组织/姓名在 100%/145%/175% 的常用宽度与最窄 sheet 下完整可见，225%×480 按本卡授权降级且邮箱仍保留 `@` 两侧字符。候选来自本机已同步邮件的信封，在首次聚焦时一次性聚合，随每次输入在内存中刷新，不触网；用户用鼠标或键盘选中后，当前尾片段补全为纯邮箱地址，其他已填地址、抄送、主题、正文与编辑器状态保持不变。无候选时静默不显示；手动输入、粘贴、多收件人、发送/存草稿等既有撰写能力不退化。

## 入口

- `CMP-APP/RecipientTextField.swift#RecipientTextField`（新增 internal：`NSTextField` 的 `NSViewRepresentable`，负责焦点/光标末尾/键盘命令/IME 组合态；`Sources/uumail/RecipientTextField.swift`）
- `CMP-APP/RecipientTextField.swift#RecipientSuggestionList`（新增 internal：候选行视图与无障碍标签；同上文件）
- `CMP-APP/RecipientForm.swift#ComposeRecipientForm`（新增 internal：收件人/抄送 Form + 候选浮层的生产子视图；从 `ComposeView.swift` 拆出，`@ViewBuilder` 承接主题行；L2 探针可直接宿主它）
- `CMP-APP/ComposeView.swift#ComposeView`（接线；候选浮层由 `ComposeRecipientForm` 的 `.overlay` 承接并按字段锚点定位；`ComposeView` 给它在 VStack 中 `.zIndex(10)`；不改 sheet 宽高、格式栏、编辑器、取消确认）
- `CMP-PRES/ComposeViewModel.swift#ComposeViewModel`（新增：`RecipientField`、候选状态、焦点/文本/光标/键盘/选中方法）
- `CMP-SCN-COMPOSE/ComposeScene.swift#ComposeScene.recipientDirectory(account:)`（新增：一次聚合本地信封，失败降级为空目录）
- `CMP-DOMAIN/Contacts.swift#ContactAddress`、`#ContactEnvelope`、`#ContactDirectory`、`#RecipientText`（新增：保留显示名的解析、匹配/排序、尾片段替换的纯值类型）
- `CMP-STORE/MailStore.swift#MailStore.folders`、`#MailStore.messages(account:folder:limit:)`（既有只读契约，本景不改；不新增 store 方法/schema）
- `CMP-OUT/MimeBuilder.swift#MimeBuilder`（既有发送头组装；本景只验证纯地址不被改写）
- 不涉及 GAL/`Search`/`Find`、macOS 通讯录、`Sent` 镜像、附件/正文解析；不新增网络请求、target、第三方依赖或 `Package.swift` 改动。

## 运行序

流程 `F-COMPOSE-03`：

1. 用户打开撰写 sheet（新建/回复/全部回复/转发）。打开本身不读联系人目录；`to`/`cc` 仍是可手填的纯文本字段。
2. 用户首次聚焦收件人或抄送字段：`ComposeViewModel.recipientFocusChanged(in:)` 置当前字段并**只在此刻（或首次文本变化）加载一次**目录：
   - `ComposeScene.recipientDirectory(account:)` 读当前账号地址（读取失败则不排除自己，不抛错）；读 `MailStore.folders(account:)`；
   - 跳过 Drafts(3)/Deleted Items(4)/Sent Items(5)/Outbox(6) 等非「已收邮件」文件夹；对其余文件夹**按 `folders` 返回顺序（Inbox 优先）**逐个读 `MailStore.messages(account:folder:limit:500)`（每个文件夹最多最近 500 封，信封字段只有 `sender`/`recipients`/`cc`/`receivedRaw`）；累计到 **5,000 封**即停止，避免大邮箱在首次聚焦时把主线程拖住；
   - 把每封映射为 `ContactEnvelope`，`ContactDirectory(envelopes:excluding:[当前账号地址])` 一次完成解析、去重、名字回退与排序；
   - 任一 store 读取失败 → 返回空目录并静默降级，撰写页照常打开、发送/存草稿不受影响；不触网、不逐键查库、不建表。
3. 目录归一（`ContactDirectory`）：按顶层 `;`/`,` 拆分信封（引号内、`<>` 内不拆）；有 `<>` 取地址、`<>` 前为显示名；无 `<>` 且含 `@` 的整段视为地址、名字为空；只接受**恰好一个 `@`、local/domain 非空、无空白且不含 `;`/`,`/`<`/`>`/引号**的 SMTP 地址，跳过裸显示名/通讯组名/Exchange DN/未闭合或空 `<>`/`Team <a@x;b@y>` 这类畸形段；按小写地址去重；排除当前账号自己的地址；同地址多个名字取「最近一次非空名字」（按 `receivedRaw` 降序近似最近，同值按聚合顺序稳定），相邻输入不随机跳变；RFC 2047 编码词不解码，按「无可用名字」处理（地址仍可被选中）。
4. 每次字段文本变化或光标位置变化：
   - 取最后一个顶层 `;`/`,` 之后的尾片段并 trim；片段为空 → 隐藏候选；
   - 光标/选区不在片段末尾（在中间编辑）→ 隐藏候选，不做插入；
   - 用 `ContactDirectory.suggestions(for:excluding:limit:8)` 在小写片段上匹配：地址前缀 → 显示名前缀 → 地址子串 → 显示名子串；大小写不敏感；同一候选只出现一次；排除收件人与抄送字段中已完整出现的地址（只解析尾片段之前的完整地址，避免排除正在输入的片段本身）；按匹配度、最近出现、地址小写稳定排序；最多 8 条；
   - 有命中 → 在**当前聚焦字段正下方**显示候选浮层；无命中 → 隐藏；全部在内存中完成，不查库、不等待。
5. 候选行展示：`显示名 + 邮箱`；显示名为空/nil/不可用 → 只显示邮箱。行内列宽按**名字优先、邮箱至少 `@` 两侧可见**分配：行宽 = 浮层宽 = `max(字段宽, 200)`；可用宽 = 行宽 − 16；邮箱保底 = `max(addressMinimum, min(130, 可用宽 − 6 − 15 × 名字字号))`，其中 `addressMinimum` 是该地址「首字符 + `…@` + 域名首字符」的渲染宽（约 100% 36pt、145% 50pt、175% 58pt、225% 72pt；100% 的 130pt 是优先值，不是契约），名字列取 `min(名字固有宽, 可用宽 − 6 − 保底)`，邮箱列取剩余；无显示名时邮箱占满可用宽。名字尾部省略；邮箱在放不下时用**保留 `@` 的显式中间缩短**（`本地前缀…@域名前缀`，如 `hr-…@corp.t` / `h…@c`），完整地址保留在 `.help` 与无障碍标签。100%/145%/175% 下 15 字组织名在 480/700/900 宽下都完整，175%×480 不再降级；40 字名仍单行稳定截断且 100% 下邮箱 130pt；只有 225%×最窄 sheet 降级为名字约 10.7 字、邮箱 `@` 保底，不出现 1–2 字级名字截断（130/`addressMinimum` 与 15 字都是列宽分配参数/代表样例，不写成契约；依据与 L2 实测见 `task-spaces/20261119-164437/design2.md` §4 与 `evidence/name-width-probe/round2/`）。浮层用 `.overlay` 挂在表单上、按当前字段锚点定位，**不参与布局**（设计探针已证 ZStack 会撑高、`.overlay` 不会；`task-spaces/20261118-082503/evidence/design-probe/overlay-probe.txt`），因此不改变 sheet 宽高与表单行布局、不把编辑器挤走；`ComposeView` 给表单 `.zIndex(10)`，浮层绘制在格式栏/编辑器之上；高度取 `min(内容, 240×scaleFactor, 字段下方可用高度)`，超出滚动；跟随五档字号与浅色/深色主题，悬停可读；每行带无障碍标签。
6. 键盘/鼠标：默认不高亮；`↓` 高亮第一条，`↑/↓` 在 0…n-1 间移动（到边界停住）；只有用户主动方向键高亮后，`Return`/`Tab` 才选中；`Esc` 收起；直接点击行也可选中；鼠标悬停只做视觉提示，不改变 `Return` 的提交目标。中文输入法组合期间 `Return` 只确认输入法候选词，不得选中联系人；组合期间不自动高亮。组合期间 `Esc` 只收起候选、不取消输入法组合（有候选时消费该命令，无候选时交还输入法）。
7. 选中：把当前尾片段替换为**纯邮箱地址**并补 `; `（保留片段前已有分隔符与其前文本，不重排、不改其他地址）；候选浮层关闭；光标移到补全后地址的末尾，焦点留在原字段，可继续输入下一个收件人；`hasEdits` 变为 `true`。点击候选行时若字段先失焦，视图把清空延后到下一 runloop，确保点击仍按原字段完成选中，再把焦点还给字段。
8. 继续输入/切换收件人与抄送：两个字段各自独立取片段、各自出候选；切字段/失焦/关闭 sheet 立即收起浮层；同一地址不因两栏都输入而重复插入。
9. 发送/存草稿：走既有 `ComposeViewModel.draft` → `ComposeScene.send`/`saveDraft` → `Outbox`/`MimeBuilder`；`to`/`cc` 是纯地址，`To:`/`Cc:` 不出现未编码的显示名；不触网、不改 MIME、RFC 2047、`Outbox` 状态机与投递语义。
10. 同步更新：新同步邮件在下一次打开撰写页（或下一次首次聚焦）时可见；不要求当前已打开的候选列表实时增量刷新。字号/主题在浮层打开期间变化 → 浮层按新字号/主题重排，不重载正文、不重置输入、不丢焦点。

失败路径：

- 本地无任何已收邮件/目录为空 → 不显示候选；手动输入、粘贴、发送/存草稿全部照常，不报错。
- 目录读取失败（存储错误）→ 空候选、静默降级；撰写页仍可打开与发送；不把存储错误显示成收件人错误。
- 信封畸形：未闭合 `<>`、空 `<>`、引号内逗号、裸通讯组名、Exchange DN、RFC 2047 名字 → 跳过坏段或按「无可用名字」稳定归一，不崩溃、不把非 SMTP 段当候选；其余联系人不受影响。
- 显示名缺失/空白/与地址相同/编码词 → 该行只显示邮箱，不显示空名字占位/`nil`/`<>`/编码乱码。
- 同地址多个名字 → 最近一次非空名字胜；最近时间相同按聚合顺序与地址稳定排序，相邻输入不随机跳变。
- 地址已在收件人或抄送中 / 等于当前账号 → 不进入候选；选中已有地址不产生重复。
- 片段为空、只有空白、无命中 → 不显示候选框。
- 光标在中间/有选区 → 不显示候选或只显示但不插入；任何情况下不得改乱已有地址文本。
- 快速连续输入（`z`→`zh`→`zha`）→ 只显示与最新文本一致的候选，不出现旧结果闪现/错插（同步重算，无异步竞态）。
- 中文输入法组合中按 `Return` → 不选中联系人；`Esc` 收起候选但不取消输入法组合。
- 候选框打开时字段失焦、切换字段、sheet 关闭 → 候选框关闭；不残留悬浮层、不阻塞关闭确认。
- 联系人数很大/预载慢 → 撰写页先可用；候选可暂不出现；不得因联想阻塞发送/取消；每文件夹 500 封、总计 5,000 封上限与失败降级按上述执行。
- 超出每文件夹 500 封或总计 5,000 封的旧邮件联系人不进入目录；这是为首次聚焦性能付出的已接受降级（R46），不报错、不影响手动输入与发送。
- 目录只用本地已收邮件信封；不做持久联系人表、不做迁移，因此旧邮件被清理后名字可能丢失——这是本设计已接受的降级，不写成与派生表同等的持久性承诺。

## 不可变引用

- `REQ-0006`/`SCN-0006`：发送只入队、`Outbox` 状态机/租约/幂等、`Cc:` 头、`ClientId = outboxID` 不变；本景只验证选中后的纯地址能走既有发送链路。
- `REQ-0007`/`SCN-0007`、`REQ-0012`：单回复/转发/全部回复的收件人种子、主题前缀、去重/排除自己/Cc 减 To 规则不变；联想只能追加或替换用户正在输入的尾片段，不得改写种子。
- `REQ-0021`/`SCN-0016`：撰写 sheet 的 HTML 编辑器、格式栏、取消确认、等宽布局、`hasEdits` 基线不变；地址字段仍是可手填的纯文本输入。
- `REQ-0020`/`SCN-0015`：五档字号对既有界面/正文的断言不变；候选浮层跟随缩放，100% 不引入既有表单高度漂移。
- `REQ-0023`/本次显示宽度增量（2026-11-19，第 2 轮修订）：只改候选行内列宽分配与邮箱显示串（名字优先、邮箱 `@` 两侧可见的最小保底；100% 优先 130pt），**145%/175%×480 的 15 字名完整、仅 225%×480 授权降级**；不改候选数据/匹配/排序/上限/插入/交互，不改行高、浮层宽与 sheet 宽高；15 字是用户示例、不作硬上限；超长名稳定尾部截断并以 `.help` 兜底，完整地址保留在 `.help`/无障碍；完整论证与设计期 L2 实测见 `task-spaces/20261119-164437/design2.md`。
- `REQ-0015`/`REQ-0016`/`SCN-0010`/`SCN-0011`：阅读区白底、主题三项与即时/持久化不变；候选浮层只消费主题，不改主题偏好。
- `MailDomain.AddressList` 的现有拆分/取址/去重公开行为不变（回复种子仍用它）；保留显示名的新解析是**增量**，共享的内部拆分器只做实现归位，`AddressList` 输出由既有测试钉住。
- `MailDomain`/`MailStore`/`Scenes`/`MailGateway` 既有契约、EAS 协议、`SyncEngine`、`ReadScene`、通知、附件、搜索、已读/删除语义：本景不改；不新增 store 方法、不建 `contacts` 表、schema 仍 v10。
- `Presentation` 不 `import MailStore`，目录经 `Scenes` 暴露（架构门 1）；不新增 target/第三方依赖；不改 `Package.swift`。
- 新 public 值类型与场景/表现契约按 P1：设计按 `auto-confirm` 记**默认确认（未经人工）**，见 `history/decisions/2026-11-18-recipient-autocomplete.md`，交评审判断；不得静默扩成持久联系人组件或调 store 预算。
- 联系人是本地 PII：不联网、不导出、不写日志、不进 evidence；候选行只显示本次需要的姓名/地址；L2 探针只用 `*.corp.test`/`example.test` 假数据。
- 架构 T12「联系人只做本机通讯录 + 收件人历史」允许本能力；GAL/`Search`/`Find` 仍不可用。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID（拟） |
|---|---|---|---|---|
| `T-SCN-0017-01` | 正 | L1（单元测试） | 目录构建/解析/匹配：fixture 含 `"张三" <zhang.san@corp.test>`、`"李四" <li.si@corp.test>; wang@corp.test`、`"Alice" <alice@corp.test>`、无名字 `noname@corp.test`、旧信里同地址的旧名字、当前账号自己、裸通讯组名/Exchange DN/未闭合 `<>`/RFC 2047 名；场景层用 `MailStore.inMemory()` + `applySyncBatch` 造 Inbox 与 Sent/Drafts/Deleted/Outbox 文件夹。断言：只从 `sender`/`recipients`/`cc` 建目录；名字保留、无名字为 nil、编码名按无名字；同地址最近非空名字胜；小写去重；排除自己/非 SMTP/非邮件文件夹；空片段无候选；`zh`/`li`/`corp`/`san@` 命中符合预期；多命中按「地址前缀→名字前缀→地址子串→名字子串→最近→地址」稳定排序，重复查询顺序一致；排除已填地址与片段本身；`limit` 夹取 0…8；每文件夹 500、总计 5,000 的截断生效；目录只在首次聚焦加载一次（加载后新增邮件不改变本次候选）。 | `MailDomainTests/ContactDirectoryTests.buildsNameAndFallback`、`.mostRecentNonEmptyNameWins`、`.dedupesCaseInsensitively`、`.matchesAddressAndNameStably`、`.skipsBareGroupsDNsAndMalformedSegments`、`.limitAndFilledAddressExclusion`、`.blankFragmentAndClampedLimit`；`MailDomainTests/RecipientTextTests.tailFragmentAndReplacement`；`ScenesTests/ComposeSceneTests.recipientDirectoryAggregatesLocally`、`.recipientDirectorySkipsNonMailFoldersAndOwnAddress`、`.recipientDirectoryCapsFolderAndTotal`、`.recipientDirectoryDegradesToEmpty`；`PresentationTests/ComposeViewModelTests.directoryLoadsOncePerCompose` |
| `T-SCN-0017-02` | 正 | L1（单元测试） | 输入刷新与插入：初始 `to = "li.si@corp.test; "`；输入 `zh`/`zha` → 候选含 `zhang.san@corp.test`（带名字）并随输入收窄；`zzz` → 空、浮层隐藏；选中 → `to = "li.si@corp.test; zhang.san@corp.test; "`，其余地址/主题/正文/`cc` 不变，`hasEdits == true`；`cc` 独立出候选并插入；重复地址不重复插入；发送/存草稿的 `Draft.to`/`Cc` 是纯地址，`MimeBuilder` 的 `To:` 无未编码中文名；选中过程不新增目录加载/网络调用。 | `PresentationTests/ComposeViewModelTests.suggestionsRefreshWithFragment`、`.selectionReplacesTailOnly`、`.ccIsIndependent`、`.selectionWritesPureAddressIntoDraft`、`.noPerKeystrokeDirectoryLoad`；`OutboxTests/OutboxMimeTests.autocompleteAddressHeaderIsAscii` |
| `T-SCN-0017-03` | 正 | L2（无头探针） | 可见候选与交互：独立 `ComposeAutocompleteProbe` 编译生产 `RecipientTextField.swift` + `RecipientTextField+AppKit.swift` + `RecipientForm.swift`（链接已构建 `Presentation`/`Scenes`/`MailDomain`/`MailStore`/`Outbox`），用 `MailStore.inMemory()` 和 `*.corp.test` 假联系人，在离屏 `NSHostingView`/`NSWindow` 里渲染（不依赖 GUI 会话）。断言：100% 字段高 24pt、表单项位置与替换前一致；候选浮层出现在当前聚焦字段正下方、不把后续表单/格式栏/编辑器下推、不改变 sheet 宽高；行内同时读到人名与邮箱；无名字行只读到邮箱、无空名字/`nil`/`<>`；点击（含字段先失焦的顺序）或方向键高亮后 `Return` 选中 → 字段补全为纯地址、浮层消失、其他字段不变；`Cc` 同样；中文输入法组合态（`setMarkedText`）下 `Return` 不选中、`Esc` 只收候选不取消组合；深色主题与 225% 字号下候选行仍可见、不裁剪、不撑破 sheet、跟随语义色与字号档位。**显示宽度（REQ-0023）**：夹具 `集团人力资源部招聘与雇主品牌组`（15 字，100% 固有宽 193.5pt）、`欧阳建国市场部华东区`（10 字）、`李四`（2 字）、`ThisNameIsFortyCharsLong_ABCDEFGHIJKLMN`（40 字）、无名字 `noname@corp.test`；sheet 宽 480/700/900、100% 下断言 15/10 字名字标签 `frame.width >= intrinsicContentSize.width`（尾部无省略）、短名帧宽 == 固有宽、邮箱帧宽 > 0 且 15 字名行**显示串含 `@` 且两侧各至少 1 字符**、`显示串宽 ≤ 帧宽 + 0.5`；40 字名在 100%×480 名字帧宽 == 可用宽 − 6 − 130（±0.5）、邮箱帧宽 == 130（±0.5）、行高 24±0.5、`.help` 完整；145%×480 的 15 字名名字帧宽 ≥ 固有宽 280.5（±0.5，看全）、邮箱帧宽 ≥ 104、显示串含 `@` 两侧且放得下（实测 `hr-…@corp.t`/106.5）；**175%×480 的 15 字名名字帧宽 ≥ 固有宽 325（±0.5，完整，不降级）**、邮箱帧宽 ≥ 58、显示串含 `@` 两侧且放得下（实测 `h…@c`/62）；225%×480 行高 54±0.5、名字帧宽 ≥ 290（约 10.4 字，实测 298）且 < 固有宽、邮箱帧宽 ≥ 72、显示串含 `@` 两侧且放得下（实测 `h…@c`/72）、不裁剪不撑破；无名字行按 `row.nameLabel`/`row.addressLabel` 身份取，`nameLabel.isHidden == true`、`nameLabel.frame.width == 0`、邮箱帧宽 == 可用宽（393）、显示串 == 完整地址；探针直接调 `RecipientSuggestionLayout.widths` 覆盖无名字/超窄行夹取、100% 的 `addressFloor=130`、175% 名字取满与 225% 的 `addressMinimum` 边界。 | `ComposeAutocompleteProbe/candidateRowsAndFallback`、`.fieldBaselineAndNoLayoutShift`、`.clickAfterFocusLoss`、`.imeEscKeepsComposition`、`.nameWidthsAtMinAndDefaultSheet`、`.longNameKeepsAddressFloor`、`.nameWidthsAt175Percent`、`.nameWidthsAt225Percent`、`.addressKeepsAtVisibleAtZoom`、`.noNameRowUsesLabelIdentity`、`.columnWidthsEdgeClamp`（探针源码与命令入 `task-spaces/<run>/evidence/compose-autocomplete-probe/`；输出 `.txt` + `.png`，`read_image` 可选）；L1 支撑 `PresentationTests/ComposeViewModelTests.suggestionStateIsNamePlusAddress` |
| `T-SCN-0017-04` | 反 | L1（单元测试） | 负例与边界：无本地数据/无命中/纯空白片段 → 无候选、不报错、手动地址仍可发送；畸形信封（引号内逗号、未闭合/空 `<>`、裸组名、DN、RFC 2047 名）→ 跳过或稳定归一、不崩溃、不产生非 SMTP 候选；光标在中间/有选区 → 不插入、不改乱文本；当前账号/已填地址 → 排除、不重复；默认无高亮时 `Return` 不提交；`Esc` 收起；快速输入只保留最新结果；切换字段/失焦清空候选。 | `MailDomainTests/ContactDirectoryTests.malformedAndNonSMTP`；`PresentationTests/ComposeViewModelTests.middleCaretHidesSuggestions`、`.noDefaultHighlightSoReturnDoesNotCommit`、`.escapeDismissesSuggestions`、`.duplicateNotSuggested`、`.rapidTypingUsesLatestFragment`、`.emptyFragmentHasNoSuggestions`、`.blurClearsSuggestions`；既有 `ComposeViewModelTests.sendEnqueues`（手动输入回归） |

> 证据层级：L1 单元测试 / L2 无头探针 / L3 截图 OCR / L4 GUI 自动化（AX）。本卡对「候选可见、人名+邮箱、无名字回退、选中后浮层消失」要求最低 **L2**：生产视图在离屏 `NSHostingView`/`NSWindow` 中渲染，探针读渲染后的文本节点/控件状态与 frame；不要求 L3/L4。依据：R29 已证无头 SwiftUI 文本可由 `NSTextField` 承载并读到 `stringValue`；R36/R37 已证离屏窗口可读控件并可合成命令。若实现期该 seam 失效，由本卡改声明 L3 并写理由，**不得**静默降级成 L1 映射或跳过。
>
> 视觉证据纪律：只截/渲染假数据 fixture（`*.corp.test` / `example.test`），不把真实姓名、地址、主题、正文截入 evidence；截图/输出与说明放 `task-spaces/<run>/evidence/`，脱敏后引用。
>
> 测试替身：目录/匹配用 `MailDomainTests` 内存值；场景用 `MailStore.inMemory()` + 临时库；视图模型用 `PresentationTests`（真实 `ComposeScene` + 内存 `MailStore`，不新增协议替身）；视觉用 `ComposeAutocompleteProbe`，不新增 `uumail` 测试 target。
>
> REQ-0023 的显示宽度断言**全部并入 `T-SCN-0017-03`（L2）**；`T-SCN-0017-04` 不新增（其负例仍是候选数据/交互）。设计期数值来自「生产源 + 设计 diff 副本」实测（`task-spaces/20261119-164437/evidence/name-width-probe/round2/`，250 CHECK / 0 FAIL），实现期必须换生产 `Sources/uumail/RecipientTextField.swift` + `RecipientTextField+AppKit.swift` 复跑，不把补丁副本当生产证据；`addressLabel.stringValue` 是已缩短的显示串，完整地址另存在行上供 `.help`/无障碍。

## 与相邻场景的边界

- `SCN-0006` 发送：只回归「手动地址/粘贴 → 发送只入队 → MIME 纯地址」；选中补全后的发送走同一路径，不新增 `SCN-0006` 断言。
- `SCN-0007` 全部回复：只回归 To/Cc 预填与去重；联想不得在种子打开时自动追加/改写地址；不新增 `SCN-0007` 断言。
- `SCN-0016` HTML 撰写：只回归 To/Cc 字段、编辑器、取消、等宽；候选浮层是新增 UI 面，由本景认领，不写进 `SCN-0016`。
- `SCN-0015` 字号：只回归撰写页既有控件在 5 档下不退化；候选浮层缩放由本景的 `T-SCN-0017-03` 承担，不改 `SCN-0015` 的数值断言。
- `SCN-0011` 主题：候选浮层跟随浅/深色，不改主题菜单/持久化/勾选断言；不新增 `SCN-0011` 断言。
- `SCN-0004`/`SCN-0010` 阅读区：不碰正文、白底、CSP、禁 JS；无回归关系。
- `REQ-0012` 的联系人联想非目标已由 `REQ-0022` 边界澄清区分；本景不改 `SCN-0007` 的种子语义。

## 状态

`designed`（2026-11-19，REQ-0023 显示宽度增量落卡；第 2 轮按评审 B1–B3 修订运行序第 5 步与 `T-SCN-0017-03`：邮箱 `@` 两侧可见的最小保底 + 地址显式缩短、**175% 不降级**、仅 225%×480 授权降级；把卡从 `verified` 转回 `designed`，待实现后重新验证）。设计论证与 L2 实测见 `task-spaces/20261119-164437/design2.md`（P3 默认确认 D1–D6，未经人工）。

历史：`verified`（2026-11-18，T-1118-02 验证，收尾按 `task-spaces/20261118-190035/review.md` §F 清单翻转；`T-1118-02` 为无人值守默认任务号、未经人工）。原 `designed`（2026-11-18，设计落卡）。四元素齐：入口、运行序、不可变引用、测试均 `present`；`T-SCN-0017-01..04` 为 3 正 1 反可执行 ID，T-01/T-02/T-04 最低 L1、T-03 最低 L2。2026-11-18 的 `verified` 判据只覆盖 REQ-0022 交付面，不覆盖 2026-11-19 新增的显示宽度断言；本卡需按 `T-SCN-0017-03` 的新断言重验。

历史 `verified` 判据：`T-SCN-0017-01`/`T-SCN-0017-02`/`T-SCN-0017-04` L1 通过；`T-SCN-0017-03` L2 `56 PASS / 0 FAIL`；全量 `327 tests / 54 suites`、依赖场景定向 `91 tests / 11 suites`、架构 4/4；`SCN-0006`/`SCN-0007`/`SCN-0015`/`SCN-0016` 回归无退化。证据：`task-spaces/20261118-190035/test.md` §2–§6、`review.md` §A–§G 与 `evidence/verify/`。

方案设计复核 A1–A6（2026-11-18）：候选浮层改 `.overlay` 不参与布局、`ComposeRecipientForm` 拆到 `RecipientForm.swift`、`RecipientTextField` 按现状 24pt/13pt/4pt inset 拟合、读取加 5,000 总计上限、click-after-focus-loss 与 IME Esc 进 L2；见 `history/decisions/2026-11-18-recipient-autocomplete-design-addendum.md`（默认确认，未经人工）。不改变三正一反与层级。
