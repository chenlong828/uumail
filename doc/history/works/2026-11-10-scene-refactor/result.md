---
layer: history
module: global
status: frozen
updated: 2026-11-14
---

# W-SCN-REFACTOR 收口结果

> 已归档（2026-11-14）。验收结果保留为过程记忆；现行真相见 `design/architecture.md` 与 `design/components/*/spec.md`。

对象：`brief.md` 的 A1–A9 验收标准、T-1110-01…10 任务表、`architecture-spec.md`（P1 冻结稿，2026-11-13 通过）与 `review.md`（第二轮评审与四档裁决）。本文件是收口记录；冻结后的现行真相已并入 `design/architecture.md` 与 `design/components/*/spec.md`。

## 验收结果

| # | 标准 | 结论 | 证据 |
|---|---|---|---|
| A1 | `./Scripts/swiftw test` 全绿；新增 `ScenesTests`、`PresentationTests` | 通过 | 最终验证 **159 tests / 37 suites** 全绿；新增 `ScenesTests`、`PresentationTests`、`CompositionTests`、`MailDomainTests`、`EASAdapterTests`（`ee31905`） |
| A2 | `Scenes`/`Presentation` 不 import `EASClient`/`EASAdapter`；仅 `Composition` 允许 | 通过 | `bash Scripts/check-architecture.sh` 4 门全过；import 白名单：`Scenes` 允许 `MailDomain/MailStore/SyncEngine/Outbox`，`Presentation` 允许 `MailDomain/Scenes`，`Composition`/`uumailctl` 才放行 EAS（`ee31905`） |
| A3 | 每条业务流只有一个顶层编排类 | 通过 | 4 个场景类各管一条流：`AccountSetupScene`/`SyncScene`/`ReadScene`/`ComposeScene`（`1f0c0b3`）；组合只出现在 `Sources/Composition/`；场景职责表见 `design/architecture.md` §2 |
| A4 | 视图零业务调用：只 `vm.xxx()` 与绑定状态，无 `service` 参数、无模型构造 | 通过 | 视图只 import `Presentation`（`UumailApp` 另 import `Composition`）；`grep -rn 'service\|MailStore\|SyncEngine\|Outbox\|Scenes' Sources/uumail/*.swift` 无命中；架构门限定只有 `UumailApp.swift` 可 import `Composition`（`636bd48`、`ee31905`） |
| A5 | CLI `diagnose/sync/send/seed` 真机等价；`send` 走 Outbox 并可等待投递结果 | **未验证** | CLI 已改调 `CommandLineComposition` + 场景（`0e9a8bc`）：`sync→SyncScene.refresh`、`send→ComposeScene.send + Outbox.flushAll`、`folders/store/body→ReadScene`、`seed→KeychainCredentialStore`；**本会话未对真实网关跑 `diagnose/sync/send`**，真机等价未证 |
| A6 | 离线发送：入队即返回，恢复网络只投递一次；App 与 CLI 同库并发不双投 | 部分通过（契约级） | 契约测试：`OutboxTests`「enqueue only writes a queued local row and returns immediately」「offline enqueue recovers later and delivers exactly once」「an expired sending lease can be reclaimed; a live lease cannot」；`MailStoreTests` 领取/租约/退避用例；**未做两个真实进程同库并发实测** |
| A7 | 阅读/列表热路径不触网；P95 不劣化 | 部分通过 | 热路径零网络有测试：`ScenesTests`「a cached body is yielded without touching the gateway」「folders and search read the local store only」；P95 未在重构后复测（仅有 5k 性能基线 `PerformanceTests`），不宣称不劣化 |
| A8 | 文档同步：`design/architecture.md`、`CMP-*`、场景卡 `_index` | 通过 | 本次 T-1110-10：`design/architecture.md` 重写、9 个新组件规格 + 5 个既有规格更新、6 张场景卡入口/证据刷新；`design/scenarios/_index.md` 是生成物（`generated: true`），本仓库尚无生成器，本次没有手写它 |
| A9 | 组合根只装配/注入/路由：无业务分支、无业务调用、无重试；`AppComposition` ≤200 行 | 通过 | `AppComposition.swift` **180 行**；4 项架构门全过（含门 3 行数、门 4 业务 switch）；`CompositionTests` 8 例装配冒烟（`ee31905`）；`OutboxPump`（启动补投/30s/入队信号）与 `CommandLineComposition` 已从视图/CLI 收走 |

## 结论落点

| 结论 | 落点 |
|---|---|
| 分层：L3 视图 + `Presentation`、L2 场景、L1b `SyncEngine`/`Outbox`、L1 `MailDomain`、L1a `MailStore`、L0 `EASClient`/`EASAdapter` | `design/architecture.md` §2；`Package.swift` |
| 9 个库 target + 2 个可执行 target；`AppServices` 退役 | `design/architecture.md` §2；`fc26985` |
| `MailGateway` v2（7 个操作）+ `FetchedBody{text,isHTML,isTruncated}`（D10） | `design/components/CMP-DOMAIN/spec.md`；`history/decisions/2026-11-13-fetched-body-contract.md`；`27502e0` |
| `SyncStore` 同步、`MailStore` 直接遵循、`StoreAdapter` 删除 | `design/components/CMP-STORE/spec.md`、`CMP-SYNC/spec.md`；`519bf28` |
| `Outbox` actor：入队即返回、120s 租约、退避、`ClientId` 幂等；schema v8 | `design/components/CMP-OUT/spec.md`、`CMP-STORE/spec.md`；`6244c56` |
| 4 个场景类与各自入口符号 | `design/components/CMP-SCN-{ACCOUNT,SYNC,READ,COMPOSE}/spec.md`；`1f0c0b3` |
| 薄视图模型、单一错误文案表、视图去服务 | `design/components/CMP-PRES/spec.md`、`CMP-APP/spec.md`；`636bd48` |
| 组合根 D9（只装配/注入/路由，≤200 行）与 CLI 收口 | `design/components/CMP-ROOT/spec.md`、`CMP-CLI/spec.md`；`fc26985`、`0e9a8bc` |
| 场景运行序与测试证据 | `design/scenarios/mail/**/scenario.md` |
| 里程碑状态与遗留 | `plan/roadmap.md`、`plan/open-questions.md`、`plan/risks.md` |

## 裁决摘要

`architecture-spec.md` 走查（W1–W10）与四档裁决在冻结时已定；实现完成后复核如下：

| 档位 | 项 | 结论 |
|---|---|---|
| Blocker | — | **0**。最终验证全绿、4 项架构门全过，无数据丢失/契约自相矛盾的证据 |
| Decision now | 1 项：D10 `fetchBody` 返回 `FetchedBody{text,isHTML,isTruncated}` | 已定并落地（`27502e0`）；决策记录 `history/decisions/2026-11-13-fetched-body-contract.md`，场景与组件规格已按此写 |
| Hold | ① 真机冒烟（`uumailctl diagnose/sync/send`、App 启动一次真实 bootstrap）；② UI 待发/失败 outbox 角标 | 不阻塞文档冻结；见「未决/遗留」1–2，已登记 `plan/risks.md` R13 与 `plan/open-questions.md` |

评审过程记录：W1–W10 与「通过」结论见 `review.md`（随本目录归档）；实现期契约未改，唯一新增决策为 D10。

## 提交与验证

| 项 | 值 |
|---|---|
| 任务 commit | `519bf28` MailDomain、`27502e0` EASAdapter + D10、`53f25a0` FileAttachmentFiles、`6244c56` Outbox + schema v8、`1f0c0b3` Scenes、`636bd48` Presentation + AppComposition、`fc26985` Composition/CLI 装配 + 删 `AppServices`、`0e9a8bc` CLI、`ee31905` 测试/门禁 |
| 测试 | `./Scripts/swiftw test` → **159 tests / 37 suites**，全绿 |
| 架构门 | `bash Scripts/check-architecture.sh` → **4 gates pass** |
| 组合根 | `Sources/Composition/AppComposition.swift` = **180 行** |
| target | 9 库（`MailDomain`、`MailStore`、`SyncEngine`、`Outbox`、`EASClient`、`EASAdapter`、`Scenes`、`Presentation`、`Composition`）+ 2 可执行（`uumail`、`uumailctl`） |

## 未决 / 遗留

1. **真机冒烟未跑**（A5、A7）：本会话未对真实网关执行 `uumailctl diagnose/sync/send`；CLI 路径只有装配测试与组件/契约测试。App 启动 bootstrap 由 `CompositionTests`（fake gateway + 内存库）覆盖，**没有 live run**。
2. **UI 无待发/失败 outbox 角标**：发送只入队后，界面只有撰写页状态文案「已加入发件箱」；列表/状态栏看不到 pending/failed 数。已登记 `plan/risks.md` R13。
3. **场景调用架构门按文件名判定**（`Scripts/check-architecture.sh`）：门 2 用「一文件一场景类」推断归属；新场景若拆文件会漏判。门 4 用业务 case 标签 + `switch` 主语匹配，通用标签依赖命名。限制写在 `design/components/CMP-ROOT/spec.md`。
4. **`PendingOps`（已读/移动/删除）未建表、未实现场景**：时机仍未定（`plan/open-questions.md` Q2）；本次只预留扩展点。
5. **App 与 CLI 同库双跑的进程级账号租约未做**：目前靠 outbox 行级租约防双投；同步游标互顶仍可能（`plan/open-questions.md` Q3）。
6. **单账号替换（改服务器/账号）未定义**：重构保持覆盖 Keychain、复用账号行（`plan/open-questions.md` Q4）。
7. **PolicyKey 只存在 `EASClient` 实例内，不持久化**：新进程首命令前重新 Provision；旧场景卡「PolicyKey 入 Keychain」已按代码更正。
8. **附件场景未完整**：25MB 上限判断、断点续传、`AttachmentName` 回退、真机下载/打开均未落地；`FileAttachmentFiles` 只有缓存预算与原子写的单测。
9. **阅读场景**：已读回写服务器、sanitizer 的自动化断言、1 万封 P95 未做；场景卡保持 `designed`。
10. **备份分支 `backup/pre-autosquash` 保留**，本次不删除。
11. **`SyncEngine.start/stop/stateStream` 未实现**：维持 `syncOnce/currentState`，节奏由 `SyncScene` 负责。
12. **失败件保留上限（24h / 100 条，T11）无清理实现**：outbox 行保留到成功、取消或手动重试，未按上限淘汰。

## 场景卡状态说明

6 张场景卡本次只刷新入口符号与测试证据，**全部保持 `designed`**，没有翻 `verified`：

| 场景 | 未转 verified 的实证原因 |
|---|---|
| SCN-0001 | T-01 有组件级断言（账号行、文件夹、凭据最后写入）；但 `ready` 状态无读契约可断言，`449` 中途自愈与「5 分钟内不重试」无用例 |
| SCN-0002 | 02「服务器新增子文件夹」、03「其下邮件不丢」、04 `stale` 标记仍无用例 |
| SCN-0003 | 02–04 有组件级断言，01 只断言窗口与 key；「UI 列表条数/可见」无场景级测试，`stateStream` 未实现 |
| SCN-0004 | 01 无 1 万封 P95 证据，03 无「脚本不执行/图片不发请求」的自动化断言，已读回写未落地 |
| SCN-0005 | 01 无真机下载与打开，02–04（25MB 上限、断点续传、`AttachmentName` 回退）未实现 |
| SCN-0006 | 02 有入队+恢复+泵的组件级证据；01（UI 点击后回列表、Sent 出现）、03（附件发送）、04（超时重试幂等）未验 |
