---
layer: history
module: global
status: frozen
updated: 2026-11-14
---

# W-SCN-REFACTOR 场景收口与分层重构

> 已归档（2026-11-14）。本文件是过程记忆，不是现行设计依据；现行真相见 `design/architecture.md` 与 `design/components/*/spec.md`，收口验收见同目录 `result.md`。

## 需求

把 UI 层与逻辑层按**场景**收口：每条业务流的上层组合只住在一个类里；UI 只绑定薄视图模型；逻辑与 EAS 客户端之间由 L1 端口隔离。目标结构见同目录 `architecture-spec.md`（P1 评审稿）。

## 背景

现状四个病灶（证据见 `architecture-spec.md` §1）：

1. 顶层组合分裂：阅读流程横跨视图、`MailboxModel`、`MailService`、`MailStore` 四处，没有一个类能完整描述它。
2. `MailService` 一人兼组合根、账号 bootstrap、发送、正文补拉、附件缓存、搜索、outbox 状态机。
3. EAS 只被隔离了 1/4：同步走端口，正文/附件/发送三处直连 `EASClient`。
4. UI 承担编排：回复/转发在视图构造模型、`service` 穿视图、轮询写在 App 的 `.task`；CLI 另写一套编排并留死代码。

## 范围

**做**

- 新增 `MailDomain`、`EASAdapter`、`Outbox`、`Scenes`、`Presentation`、`Composition` 六个 target；`AppServices` 退役。
- `MailGateway` 从 3 个操作扩到 7 个；EAS 错误只在一处映射。
- 拆 `MailService` 为 4 个场景类；`MailboxModel`/`ComposeModel` 改薄；CLI 改调场景。
- 发信改为“入队即返回 + 冷投递”，含跨进程租约防双投。
- 值类型归位到 `MailDomain`（过渡期 `typealias` 保编译）。

**不做**

- 不新增业务功能：标记已读、移动、删除仍留到 `PendingOps` 工序。
- 不改数据库 schema（outbox 复用现有列，`state` 值新增 `sending` 为数据语义变更，无迁移）。
- 不做多账号、不做 Sent 镜像、不改协议线格式。

## 验收标准

| # | 标准 | 判定 |
|---|---|---|
| A1 | `./Scripts/swiftw test` 全绿；新增 `ScenesTests`、`PresentationTests` | CI |
| A2 | `Scenes`/`Presentation` 不 import `EASClient`/`EASAdapter`；仅 `Composition` 允许 | 架构脚本 |
| A3 | 每条业务流只有一个顶层编排类（见规格 §2 责任收口表） | 评审 |
| A4 | 视图零业务调用：只 `vm.xxx()` 与绑定状态，无 `service` 参数、无模型构造 | grep + 评审 |
| A5 | CLI `diagnose/sync/send/seed` 真机等价；`send` 走 Outbox 并可等待投递结果 | 真机 |
| A6 | 离线发送：入队即返回，恢复网络只投递一次；App 与 CLI 同库并发不双投 | 契约测试 |
| A7 | 阅读/列表热路径不触网；P95 不劣化 | 手测 + 现有基线 |
| A8 | 文档同步：`design/architecture.md`、`CMP-*`、场景卡 `_index` | 收口检查 |
| A9 | 组合根只装配/注入/路由：无业务分支、无业务调用、无重试；`AppComposition` ≤200 行 | 架构脚本 + 评审 |

## 已确认决策（2026-11-10）

| ID | 决策 | 结论 |
|---|---|---|
| D1 | 场景粒度 | 4 个场景类；搜索并入 `ReadScene`，通知并入 `SyncScene` |
| D2 | 发信时序 | `send` 只入队；`Outbox` 冷投递；UI 显示“已加入发件箱/待发/失败” |
| D3 | `SyncEngine` 层次 | 从 L2 降为 L1b 能力；场景可直接依赖 |
| D4 | Target 粒度 | 9 个库 target；`MailDomain`/`Scenes`/`Composition` 三条边界不可省 |
| D9 | 组合根边界 | 只装配、注入、路由与生命周期；业务判断一律不进组合根（防止长成上帝类） |

改动定级：**P1**（模块切分、分层依赖、核心契约、热路径发送语义）。设计未冻结前不写实现代码。

## 任务表

| ID | 类型 | 组件 | 状态 | 内容 | 装载 |
|---|---|---|---|---|---|
| T-1110-01 | change | CMP-DOMAIN | done | 新建 `MailDomain`：值类型、端口、`MailError`、`ServerConfiguration`；`typealias` 过渡 | `Sources/MailDomain/**`、`Package.swift` |
| T-1110-02 | change | CMP-EASADAPTER | done | `EASAdapter` 实现 `MailGateway` v2；`MailService` 内部改走端口 | `Sources/EASAdapter/**`、`MailService.swift` |
| T-1110-03 | change | CMP-UC-* | done | 新建 `Scenes`：AccountSetup / Sync / Read / Compose | `Sources/Scenes/**` |
| T-1110-04 | change | CMP-PRES | done | 薄视图模型；视图去 `service`、去编排 | `Sources/Presentation/**`、`Sources/uumail/**` |
| T-1110-05 | change | CMP-CLI | done | `uumailctl` 改调场景；删重复账号逻辑 | `Sources/uumailctl/**` |
| T-1110-06 | change | CMP-OUT | done | `Outbox` 冷投递、租约、退避；`MailStore` 新增 claim/mark 契约 | `Sources/Outbox/**`、`MailStore.swift` |
| T-1110-07 | change | CMP-ATT | done | `AttachmentFiles` 端口与实现；附件流程移入 `ReadScene` | `Sources/Composition/**` |
| T-1110-08 | change | CMP-ROOT | done | `Composition` 组合根；App 启动与轮询迁移；DEBUG 环境入口 | `Sources/Composition/**`、`UumailApp.swift` |
| T-1110-09 | test | 全仓 | done | `ScenesTests`/`PresentationTests`/架构 import 脚本 | `Tests/**`、`Scripts/**` |
| T-1110-10 | docs | 全仓 | done | 冻结进 `design/architecture.md` 与各 `spec.md`；场景卡状态更新 | `doc/design/**` |

## 风险

| 风险 | 缓解 |
|---|---|
| 场景边界切错，`ReadScene` 长成新上帝类 | 删除测试与一句话测试在评审中执行（规格 §10） |
| 发信改入队后用户误以为没发出 | `Compose` 显示“已加入发件箱”，列表/状态栏可见待发数（需 UI 小改） |
| CLI 与 App 同库并发双投 | `sending` + 租约（120s）+ `ClientId` 幂等键 |
| 值类型迁移打爆测试 | `typealias` 过渡，分两个 commit |
| 场景类依赖 `MailStore` 具体类型，后续难测 | 场景只经 `MailStore` 公开契约；测试用内存库或真实 SQLite 临时文件 |
| 组合根逐步承接业务判断，长成第二个 `MailService` | §7 禁入清单 + `AppComposition` ≤200 行 + 架构脚本 + 只做装配冒烟测试 |

## 开放问题

1. 首配后再次修改服务器/账号（单账号替换）的行为未定义，重构保持现状（覆盖 Keychain、复用账号行），另立工序。
2. `PendingOps`（已读/移动/删除）的落地时机：M3 前，本次只预留端口与表位。
3. `SyncEngine` 的 `start/stop/stateStream` 未实现；本次维持 `syncOnce/currentState`，轮询由 `SyncScene` 负责。

## 评审状态

- 第一轮（2026-11-10）：边界与四个决策已确认。
- 第二轮（2026-11-13）：`architecture-spec.md` 完整规格与走查**通过**；D1–D9 逐条确认，无附加条件。规格冻结，进入 T-1110-01。
- 收口（2026-11-14）：T-1110-01…10 全部完成；验收与裁决见同目录 `result.md`，现行真相已并入 `design/architecture.md` 与 `design/components/*/spec.md`。

## 执行记录

| 任务 | 日期 | 结论 |
|---|---|---|
| T-1110-01 | 2026-11-13 | `MailDomain` 目标落地（`Values/Errors/Configuration/Ports`，仅依赖 Foundation）；`MailStore`、`SyncEngine` 的值类型改为 `typealias`，`SyncStore` 改为同步、网关端口实现 7 个操作；新增 `MailDomainTests` 3 例；83 个测试全绿 |
| T-1110-07 | 2026-11-13 | `FileAttachmentFiles`（Composition 目标）：确定性文件名、原子写、2 GB 最旧优先淘汰；`AttachmentRef` 增加 `displayName`；3 个单测。附件流程接入 `ReadScene` 随 T-1110-03 |
| T-1110-02 | 2026-11-13 | 新建 `EASAdapter` 目标（`EASAdapter` 类型 + 唯一错误映射）；`MailService` 的正文/发信/附件改走端口，`isHTML`/`isTruncated` 由 `FetchedBody` 保留（D10）；新增 `EASAdapterTests` 4 例；87 个测试全绿 |
| T-1110-06 | 2026-11-13 | 新建 `Outbox` 目标：入队只落本地行、`UPDATE … RETURNING` 单句领取、120s 租约、30s→2m→10m→30m 后翻倍封顶 24h、失败分类与手动重试、`ClientId = outboxID`；`MimeBuilder` 迁入 Outbox，From/Message-ID 取 `MailStore.account`（返回新增 `host`）；`MailStore` 迁移 `v8_outbox_v2`（`sending_since`/`next_attempt_at`、`failed`→`failed_retryable`）与 `claim/mark/release/cancel/outboxItem`、`discardAccount`/`markAccountReady`、`outboxNotClaimable`/`accountNotEmpty`；`MailService.send` 改为入队后一次投递；新增 `OutboxTests`，`MailStoreTests` 随契约更新（状态值改名、需先 claim）；120 个测试全绿。解释：`releaseOutbox` 兼作手动重试（spec 未单列 retry 写契约）；sending 中取消用进程内标记、投递返回后经 queued→canceled 落终态；账号行缺失视为永久失败 |
| T-1110-03 | 2026-11-14 | 新建 `Scenes`（依赖 MailDomain/MailStore/SyncEngine/Outbox）：`AccountSetupScene`（probe/provision → 建号或复用 → 文件夹快照 → ready → 凭据最后；失败只回滚本次新建账号）、`SyncScene`（单飞、授权请求一次、added>0 才通知、auth/device/policy 暂停自动刷新）、`ReadScene`（本地读零网络、缓存优先、按 `MessageRef` 单飞补拉且先落库再 yield、附件经 `AttachmentFiles`）、`ComposeScene`（Re:/Fwd: 与引用规则照搬 `ComposeModel`、入队即返回、空收件人拒绝）；`HTMLText` 迁入 Scenes，`MailService`/`MailboxModel` 改 import；新增 `ScenesTests` 22 例，142 个测试全绿。偏差/解释：`Outbox` 是 actor，故 `send`/`pending`/`retry`/`cancel` 必须是 async；回滚不删复用的既有无消息账号；`AccountInput` 无协议字段，凭据按 `ServerConfiguration` 默认值补；顺带修正 `SyncEngineTests` 的 `fetchBody` 返回类型（T-1110-02 遗留，旧构建缓存掩盖了编译错误） |
| T-1110-04 | 2026-11-14 | 新建 `Presentation`（依赖 Scenes/MailDomain）：`MailboxViewModel`（文件夹/列表/正文/附件/同步/选择/搜索；正文缓存优先、预览 + 补拉、失败重试；自动刷新消费 `SyncScene` 流并映射 `SyncPresentation`）、`ComposeViewModel`（回复/转发种子经 `ComposeScene`；`send` 入队即返回“已加入发件箱”；`saveDraft`）、`AccountSetupViewModel`（validate/connect、`ErrorText`、`isBusy`）、`ErrorText` 单一 `MailError → 中文` 映射、`DisplayFormat`（发件人与日期，视图内两处格式化上提）；新增最小 `AppComposition`（store/EASAdapter/Outbox/SyncEngine/Scenes 装配、`KeychainCredentialStore`/`SystemNotifier`/`SystemMailClock`/`AppPaths`、DEBUG 环境与 DB 覆盖解析从视图迁入、账号接入路径、启停自动刷新）与 `MailStore: SyncStore` 直接遵循（规格 §11 `SyncStoreConformance`）；`UumailApp` 只做装配与窗口宿主，`MailboxView`/`MessageBodyView`/`ComposeView`/`AccountSetupView` 只绑定 VM；`AppServices` 的 `MailService`/`MailboxModel`/`ComposeModel` 保留未动。新增 `PresentationTests` 23 例，165 个测试全绿。偏差/风险：`send` 只入队，冷投递泵未在本任务落地（留 T-1110-08）；有 Keychain 凭据但本地无账号行时（如空库 `seed`）路由到预填配置页、需点一次“连接”，与旧版启动即建号的便利路径不同；`BodyPresentation` 保持规格的 `loaded(html,truncated)`/`failed(text)`，预览中与预览回退用并列的 `BodyNotice` 承载；`AppComposition` 为 195 行（门槛 ≤200） |
| T-1110-08 | 2026-11-14 | `Composition` 收口：`AppComposition` 161 行 + `OutboxPump`（启动补投、每 30s、入队信号、可停可重启）；启动 bootstrap 改为“有账号行走邮箱 / 无账号行但有凭据跑一次 `AccountSetupScene.connect` / 失败留在配置页显示文案”；新增 `CommandLineComposition`（env 配置、`--db` 装配、无账号行经 setup 场景引导、内存凭据、静默通知）与 `ConfigurationSource`（配置来源与类型转换从组合根抽出）；`ComposeViewModel`/`MailboxViewModel` 增加 `onEnqueued` 钩子，`UumailApp` 终止时停止任务；删除 `AppServices` target/8 个文件、`MailServiceProtocol`/`MailSendService` 与 `Tests/AppServicesTests`（20 例，行为由 PresentationTests/OutboxTests/ScenesTests 覆盖，未发现需移植的缺口）；新增 `OutboxPumpTests` 3 例、`ConfigurationSourceTests` 2 例；150 个测试全绿。偏差/风险：DEBUG 环境源改用进程内凭据存储（`EphemeralCredentialStore`），引导不会把环境凭据写进 login Keychain；为在删除 `AppServices` 后保持可编译，T-1110-05 的 CLI 场景化提前落到 `send/sync/body --db`（`folders/store` 与删死代码仍留 T-1110-05）；CLI 在空库上先经 setup 场景引导（多一次 probe/provision/folderSync，且凭据只进进程内，不写 Keychain），离线空库 `send` 会停在引导失败而非入队重试 |
| T-1110-05 | 2026-11-14 | `uumailctl` 数据命令全部收口到 `CommandLineComposition` + 场景：`sync`→`SyncScene.refresh`（`--db` 必填）、`send`→`ComposeScene.send` 后 `Outbox.flushAll`（`--to/--subject/--body` 不变，`--db` 默认 `.build/outbox.sqlite`，投递失败仍打印“(item kept for retry)”）、`folders`→`ReadScene.folders`（`--json` 保留，`--db` 默认 `.build/uumailctl.sqlite`，sync key 读本地 `sync_state`）、`store`→组合根引导快照后经 `ReadScene.folders` 打印、`body --db`→`ReadScene.open`、`seed`→`KeychainCredentialStore`；`options/provision/ping/diagnose` 与无 `--db` 的 `body` 保持直连 `EASClient`（§3 例外）；删除 CLI 的 `existingOrNewAccount` 等死代码，`uumailctl` 依赖收敛为 Composition/EASClient/MailDomain/Scenes；150 个测试全绿。行为差异：`folders` 空库上先经 setup 场景引导（多一次 probe/provision/folderSync，输出格式不变）；`store` 在已有账号的库上不重复拉快照（引导即快照，刷新由 `sync` 负责）；`body --db` 命中缓存时不再重复拉取 |
| T-1110-09 | 2026-11-14 | `CompositionTests` 增加装配冒烟 8 例（AppComposition 5、CommandLineComposition 1、ConfigurationSource 2）：有账号行 → 邮箱；无行 + 配置 → 配置页；空库 + 已存配置经 `start()` bootstrap 成功 → 建账号/存凭据/进邮箱，失败 → 停在配置页并显示 `ErrorText`、无账号行且不写凭据；泵 start/stop 幂等且一条入队只投一次；DEBUG 环境凭据留在进程内不写登录 Keychain。为可测性加最小依赖注入：新建 `Sources/Composition/GatewayFactory.swift`（`GatewayFactory` + 唯一 EAS 构造点 `PlatformGateway`），`AppComposition` 增加 gateway/notifier 注入 init（旧便利 init 保留），`CommandLineComposition.make` 增加可选 gatewayFactory，DEBUG 凭据选择抽为 `ConfigurationSource.setupCredentials`；无业务逻辑。新建 `Scripts/check-architecture.sh`（可执行，bash+grep，4 道门：per-target import 白名单含 Views/Scenes/Presentation/MailStore、场景互调、`AppComposition` ≤200 行、Composition 业务 switch），已用注入违例逐门验证会失败并退出非零。`MailStoreTests/MigrationTests` 用 GRDB 造 pre-v8 fixture（v5 outbox + `failed` 行 + accounts，登记 v1–v7 已应用，只重建迁移与断言所需两表）：打开后 `failed` → `failed_retryable`、旧字段可读且可重新 claim。`AppComposition` 180 行；159 个测试全绿；架构脚本 4 门全过。局限：场景互调门按“一文件一场景类”文件名判定；switch 门用业务 case 标签 + `switch error/state/...` 主语匹配，`case .idle/.failed` 这类通用标签依赖主语命名；迁移 fixture 只重建 accounts/outbox 两表（其余表登记为已应用）。 |
| T-1110-10 | 2026-11-14 | 收口落文档：`design/architecture.md` 重写为现行真相（分层/target/契约/D1–D10/阶段/残留）；新建 9 个组件规格（`CMP-DOMAIN`、`CMP-EASADAPTER`、`CMP-SCN-{ACCOUNT,SYNC,READ,COMPOSE}`、`CMP-PRES`、`CMP-ROOT`、`CMP-CLI`），更新 5 个既有规格（`CMP-STORE/SYNC/OUT/EAS/APP`）；6 张场景卡刷新入口与测试证据，全部保持 `designed`（逐项原因见 `result.md`）；`plan/roadmap.md` 增结构收口记录，`risks.md` 增 R13（outbox 无 UI 角标），`open-questions.md` 增 Q2–Q4；`doc/README.md` 阅读顺序与入口更新；本目录归档到 `history/works/`。验证：159 tests / 37 suites、4 项架构门、`AppComposition` 180 行 |
