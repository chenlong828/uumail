---
layer: works
module: global
status: active
updated: 2026-11-10
---

# W-SCN-REFACTOR 场景收口与分层重构

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
| T-1110-01 | change | CMP-DOMAIN | pending | 新建 `MailDomain`：值类型、端口、`MailError`、`ServerConfiguration`；`typealias` 过渡 | `Sources/MailDomain/**`、`Package.swift` |
| T-1110-02 | change | CMP-EASADAPTER | pending | `EASAdapter` 实现 `MailGateway` v2；`MailService` 内部改走端口 | `Sources/EASAdapter/**`、`MailService.swift` |
| T-1110-03 | change | CMP-UC-* | pending | 新建 `Scenes`：AccountSetup / Sync / Read / Compose | `Sources/Scenes/**` |
| T-1110-04 | change | CMP-PRES | pending | 薄视图模型；视图去 `service`、去编排 | `Sources/Presentation/**`、`Sources/uumail/**` |
| T-1110-05 | change | CMP-CLI | pending | `uumailctl` 改调场景；删重复账号逻辑 | `Sources/uumailctl/**` |
| T-1110-06 | change | CMP-OUT | pending | `Outbox` 冷投递、租约、退避；`MailStore` 新增 claim/mark 契约 | `Sources/Outbox/**`、`MailStore.swift` |
| T-1110-07 | change | CMP-ATT | pending | `AttachmentFiles` 端口与实现；附件流程移入 `ReadScene` | `Sources/Composition/**` |
| T-1110-08 | change | CMP-ROOT | pending | `Composition` 组合根；App 启动与轮询迁移；DEBUG 环境入口 | `Sources/Composition/**`、`UumailApp.swift` |
| T-1110-09 | test | 全仓 | pending | `ScenesTests`/`PresentationTests`/架构 import 脚本 | `Tests/**`、`Scripts/**` |
| T-1110-10 | docs | 全仓 | pending | 冻结进 `design/architecture.md` 与各 `spec.md`；场景卡状态更新 | `doc/design/**` |

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
- 第二轮：`architecture-spec.md` 完整规格与走查，**待最终确认**。确认后冻结并进入 T-1110-01。
