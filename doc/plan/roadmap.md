---
layer: plan
module: global
scope: project:uumail
status: current
updated: 2026-11-16
---

# 路线图

只记里程碑、工序与依赖。需求状态看 `requirements/`，设计真相看 `design/`。
首版范围已于 2026-11-09 确认：REQ-0001…0007 `accepted`（`history/decisions/2026-11-09-scope-baseline.md`）。2026-11-14 追加并交付：REQ-0012「全部回复的收件人与抄送预填」`delivered`（W-M2-03，任务表见本文 §W-M2-03 任务表）。2026-11-14 追加需求分析并纳入 W-M3-03：REQ-0013「列表停留自动已读」与 REQ-0014「列表键盘删除」已于 2026-11-15 交付（`SCN-0008`/`SCN-0009` `verified`、两需求 `delivered`）；设计已完成（P1 已确认并归档），任务拆分复核完成（2026-11-14），任务表见本文 §W-M3-03 任务表。2026-11-16 追加 W-M3-04 并完成交付：REQ-0015「深色阅读白底」与 REQ-0016「菜单主题切换」`delivered`；Q5/Q6/P2 已于 2026-11-16 确认（`history/decisions/2026-11-16-theme-appearance.md`），`SCN-0010`/`SCN-0011` 已由 `designed` 转 `verified`，`T-1116-01`…`T-1116-06` 已完成；任务表见 §W-M3-04。
工序目录名沿用历史 `works/YYYY-MM-DD-<短名>/`；2026-11-14 起过程记录放工作区 `task-spaces/<run>/`，**任务表作为项目排期的一部分落在本文件**，不再只存在于某次运行的 brief 里。

## 里程碑

| 里程碑 | 目标 | 出口判据 | 状态 |
|---|---|---|---|
| M0 协议探针 | 证明外网 EAS 通道可用，锁定线格式、设备身份与命令覆盖 | 命令行跑通 `OPTIONS → Provision → FolderSync → Sync → ItemOperations → SendMail`，实测状态码与能力矩阵成文 | 已完成（`history/works/2026-11-09-eas-probe/`） |
| M1 只读客户端 | 账号接入、文件夹树、列表、正文、附件、离线缓存 | 五个只读场景（SCN-0001…0005）全部 `verified` | 进行中：账号、文件夹树、列表、正文已通；附件 02–04 未实现；场景卡待转 `verified` |
| M2 发送与草稿 | Outbox、SendMail、回复/转发、草稿、Sent 镜像、全部回复 | send-message 场景 `verified`；离线发送可在联网后只发一次 | 进行中：Outbox 入队/冷投递/重试已实现；Sent 镜像与撰写附件未做；全部回复 `SCN-0007` `verified`（2026-11-14，T-1114-09，含真机 UI 冒烟），REQ-0012 `delivered`；其余场景卡待 `verified` |
| M3 体验 | Ping、通知、本地搜索、错误恢复与空态 | 新邮件端到端 ≤ 60s 可见（Ping 或轮询）；搜索、通知场景 `verified`；W-M3-03 的 `SCN-0008`/`SCN-0009` `verified` | 进行中：Ping 不支持 → 5 分钟轮询；搜索与通知已落地，场景卡待 `verified`；W-M3-03 已交付（2026-11-15，T-1114-19/20 验证）：`SCN-0008`/`SCN-0009` `verified`、REQ-0013/REQ-0014 `delivered`；P1 frozen 记录与 R16 真机证据已归档 |
| M4 加固 | 策略、限流、安全、性能 | 限流退避、缓存上限、安全审计、5k 性能基线已落 | 已完成（`history/works/2026-11-09-m4-hardening/`） |

## 工序

| 工序 | 里程碑 | 依赖 | 主要组件 | 出口 |
|---|---|---|---|---|
| W-DOC-01 文档基线 | — | M0 结论 | 全仓 | 已完成：五态文档树成立，架构草案按实测校正（`history/works/2026-11-09-doc-baseline/`） |
| W-M1-01 账号接入与设备身份 | M1 | W-DOC-01；REQ-0001 已 accepted | CMP-EAS、CMP-STORE | 已完成（`history/works/2026-11-09-m1-account-access/`）：协议、落库、UI 外壳；SCN-0001 待 `verified` |
| W-M1-02 文件夹树同步 | M1 | W-M1-01 | CMP-SYNC、CMP-STORE | 已实现；SCN-0002 待 `verified` |
| W-M1-03 收件箱增量同步 | M1 | W-M1-02 | CMP-SYNC、CMP-STORE、CMP-EAS | 已实现（随 W-M1-01 追加任务）：分页与原子提交已通；SCN-0003 待 `verified` |
| W-M1-04 正文渲染与附件下载 | M1 | W-M1-03 | CMP-STORE、CMP-EAS、AttachmentCache | 已实现；SCN-0004、SCN-0005 待 `verified`（附件真机未验） |
| W-M2-01 Outbox 与发信 | M2 | W-M1-04 | CMP-OUT、CMP-EAS | 已完成（无过程记录，见下）：协议、队列、撰写界面；真机自测信投递成功 |
| W-M2-02 回复/转发与草稿 | M2 | W-M2-01 | CMP-OUT、CMP-STORE | 已实现（无过程记录，见下）；回复/转发复用 `SCN-0006`，草稿无场景卡 |
| W-M2-03 全部回复与抄送预填 | M2 | W-M2-02；REQ-0012 `delivered` | CMP-EAS、CMP-DOMAIN、CMP-EASADAPTER、CMP-STORE、CMP-SCN-COMPOSE、CMP-PRES、CMP-APP | 已完成（2026-11-14）：`T-1114-02`…`T-1114-08` 落地 Cc 采集、领域/存储、`replyAllSeed`、视图模型与工具栏；`T-1114-09` 验证 3 正 1 反全绿，`SCN-0007` 转 `verified`、REQ-0012 转 `delivered`；全量 182 tests / 38 suites、架构 4 门过；真机 UI 冒烟已完成（本地录制网关，未向真实邮箱投递）。任务表见本文 §W-M2-03 任务表 |
| W-M3-01 Ping 与通知 | M3 | W-M2-01 | CMP-SYNC、通知策略 | Ping 实测不支持 → 轮询；通知已落地（无过程记录，无独立场景卡） |
| W-M3-02 本地搜索 | M3 | W-M1-03 | CMP-STORE | 已实现（无过程记录，无独立场景卡）；FTS 不扫正文列 |
| W-M3-03 列表已读与键盘删除 | M3 | W-M1-04；REQ-0013/0014 已 delivered | CMP-PRES、CMP-APP、CMP-SCN-READ、CMP-SYNC、CMP-STORE、CMP-DOMAIN、CMP-EAS、CMP-EASADAPTER、CMP-ROOT | 已完成（2026-11-15）：设计完成（2026-11-14，T-1114-10 第 2 轮）；实现完成（2026-11-14，T-1114-11…18/21）：写端口、EAS 写命令、适配器、存储提交、FIFO 门、场景编排、计时/删除/视图接线落地；`T-1114-19`/`T-1114-20` 验证 8/8 例子全绿，`SCN-0008`/`SCN-0009` 转 `verified`、REQ-0013/REQ-0014 转 `delivered`；全量 239 tests / 44 suites×2、架构 4 门过；P1 frozen 记录与 R16 真机证据已归档，写响应 `MoreAvailable`/前台信号按实测修订；任务表见本文 §W-M3-03 任务表 |
| W-M3-04 菜单主题与深色阅读白底 | M3 | W-M3-03；REQ-0015/0016 `delivered`；Q5/Q6/P2 已确认 | CMP-APP、CMP-PRES | 已完成（2026-11-16）：Q5 A + Q6 A + P2 确认（`history/decisions/2026-11-16-theme-appearance.md`）；`SCN-0010`/`SCN-0011` 落卡 `designed` 后转 `verified`；`ThemePreferenceStoreTests` 5 例、`AppearanceProbe`/`ThemeProbe`、全量 244 tests / 45 suites 与架构 4 门通过；REQ-0015/REQ-0016 已转 `delivered`；任务表见本文 §W-M3-04 任务表 |
| W-SCN-REFACTOR 场景收口与分层重构 | M1/M2/M3 结构前置 | W-DOC-01、M4 结论 | 全仓 | 已完成（`history/works/2026-11-10-scene-refactor/`）：4 场景、9 库 + 2 可执行、159 测试、4 架构门 |

### W-SCN-REFACTOR 场景收口与分层重构（2026-11-14 完成）

结构收口已完成并归档（`history/works/2026-11-10-scene-refactor/`）。当前组件/target 状态：

- 9 个库 target（`MailDomain`、`MailStore`、`SyncEngine`、`Outbox`、`EASClient`、`EASAdapter`、`Scenes`、`Presentation`、`Composition`）+ 2 个可执行 target（`uumail`、`uumailctl`）；`AppServices` 退役。
- 4 个场景类收口每条业务流：`AccountSetupScene`、`SyncScene`、`ReadScene`、`ComposeScene`；视图只绑定薄视图模型。
- 发信改为「入队即返回 + `Outbox` 冷投递」；outbox schema v8（租约 + 退避 + 显式状态）。
- 最终验证：159 tests / 37 suites 全绿；`Scripts/check-architecture.sh` 4 门全过；`AppComposition` 180 行。

结构收口**不等于功能里程碑完成**：M1/M2/M3 的出口仍看场景卡 `verified`。当前仍缺：真机冒烟（`uumailctl diagnose/sync/send`、App live bootstrap）、附件 25MB/续传/名称回退、已读回写/键盘删除（已设计，待实现）、Sent 镜像、outbox UI 角标、`PendingOps`。

## 过程记录缺口（2026-11-13 登记）

以下工序已在代码与设计真相里落地，但**没有 `works/` 目录、`brief.md`、`result.md` 与评审记录**；只能按提交追溯，不补造事后记录：

| 工序 | 可追溯的提交（2026-11-09） | 结论落点 |
|---|---|---|
| W-M2-01 Outbox 与发信 | `89b7c7c` 22:56 SendMail / outbox / MIME；`5be7b46` 23:12 CLI `send`；`9be8aca` 23:19 真机投递记录 | `CMP-OUT/spec.md`、`CMP-EAS/spec.md`、`history/works/2026-11-09-m4-hardening/result.md` 发信段 |
| W-M2-02 回复/转发与草稿 | `3cb055a` 23:00 `ComposeModel` / `ComposeView`，5 个模型单测 | `CMP-APP/spec.md`、`CMP-OUT/spec.md` |
| W-M3-01 Ping 与通知 | `b3a6f62` 23:05 通知；`0913217` 23:11 Ping 探测与轮询 | playbook §5.2、`CMP-SYNC` / `CMP-APP` 规格 |
| W-M3-02 本地搜索 | `b3a6f62` 23:05 FTS5 trigram、CJK 子串、跨文件夹 | `CMP-STORE/spec.md`（`searchLocal` 行） |

这四条当时的任务号只留在 commit message（`T-1109-17`、`T-1109-18`、`T-M4-01..05`、`T-M2-verify`）里，没有 brief 任务表与验收记录，补记也无从核对验收标准；故只登记缺口，不补造 result。下一次同类改动按批次纪律从 `brief.md` 起建目录。

## W-M2-03 任务表（全部回复与抄送预填）

来源：`REQ-0012`（`delivered`）、`SCN-0007`（`verified`）、`design/components/CMP-*` 设计增量。设计冻结于 2026-11-14，实现须先过 P1 人工确认门。

| 任务 | 类型 | 组件 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|
| `T-1114-01` | `design` | SCN-0007（0 组件） | — | 已完成（2026-11-14） | 场景卡四元素齐、3 正 1 反可执行、转 `designed` |
| `T-1114-02` | `change` | `CMP-EAS` | T-1114-01 | 已完成（2026-11-14） | Sync 信封 `Cc` 解析 + fixture 测试；真机样本已证网关返回，未触发停止分支 |
| `T-1114-03` | `change` | `CMP-DOMAIN` | T-1114-01 | 已完成（2026-11-14） | `Message.cc` 可选字段 + `AddressList` 归一化 + 5 例值类型测试；`MailDomainTests` 8 例绿 |
| `T-1114-04` | `change` | `CMP-EASADAPTER` | T-1114-02、T-1114-03 | 已完成（2026-11-14） | `EASMessage.cc → Message.cc` 映射 + 2 例 Cc 测试（Add/Change、缺失/空白）；`EASAdapterTests` 6 例绿 |
| `T-1114-05` | `change` | `CMP-STORE` | T-1114-03 | 已完成（2026-11-14） | schema v9 `cc` 列、读写与 COALESCE、消息游标回填、pre-v9 迁移测试；173 测试全绿 |
| `T-1114-06` | `change` | `CMP-SCN-COMPOSE` | T-1114-01、T-1114-03 | 已完成（2026-11-14） | `replyAllSeed` + 地址解析/去重/排除自己 + 3 例组件测试；176 测试全绿 |
| `T-1114-07` | `change` | `CMP-PRES` | T-1114-06 | 已完成（2026-11-14） | `Mode.replyAll`、`composeReplyAll`、视图模型测试；`PresentationTests` 28 例、全量 181 测试全绿 |
| `T-1114-08` | `change` | `CMP-APP` | T-1114-07 | 已完成（2026-11-14） | 工具栏「全部回复」按钮，视图不拼地址；编译 + VM 接线，真机冒烟留 T-1114-09 |
| `T-1114-09` | `verify` | SCN-0007 / REQ-0012 | 全部 | 已完成（2026-11-14，第 2 轮） | 3 正 1 反全绿（`replyAllUsesBackfilledCc` 改为自带 pre-v9 fixture，真实走 v9 迁移 → `applySyncBatch(changed:)` → `replyAllSeed`）、`SCN-0006` 回归无退化、架构 4 门过；全量 182 tests / 38 suites；`SCN-0007` → `verified`、REQ-0012 → `delivered`；真机 UI 冒烟已完成（带 Cc 多人邮件全部回复 → To/Cc → 发送 → outbox/MIME，自己邮件不含自己；本地录制网关，未向真实邮箱投递） |

并行关系：`T-1114-02` 与 `T-1114-03` 可并行；之后 `T-1114-04`、`T-1114-05`、`T-1114-06` 分属三个组件可并行。

## W-M3-03 任务表（列表已读与键盘删除）

来源：`REQ-0013`/`REQ-0014`（2026-11-14 为 `accepted`，2026-11-15 已转 `delivered`）、`SCN-0008`/`SCN-0009`（2026-11-14 为 `designed`，2026-11-15 已转 `verified`）、`design/components/CMP-*` 设计增量。设计提案于 2026-11-14 完成第 2 轮修订（按评审 B1–B4）。实现节点于 2026-11-14 完成 T-1114-11…18/21 并提交；同日回退重跑补齐 **P1 frozen 记录**（`doc/history/decisions/2026-11-14-mail-write-path.md`）与 **R16 真机证据**（写命令被接受、返回新 key、删除进入「已删除邮件」、not-found 成功），并按实测修订写响应 `MoreAvailable` 语义与前台信号来源。

任务拆分复核（2026-11-14）：每个任务在「规格锚点」列指到组件规格的具体段落；依赖无环；出口含测试名/命令/证据位置。T-1114-11 与 T-1114-14 的边界按「一次提交可编译」调整：`MailWriteGateway` 留在 T-1114-11；`SyncStore` 三方法与唯一生产遵循 `MailStore` 同批进 T-1114-14，避免协议加方法后 `MailStore`/测试替身编译失败的中间态。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1114-10` | `design` | SCN-0008 / SCN-0009 + 写路径（0 组件） | `SCN-0008`/`SCN-0009` §入口/§运行序/§测试；`CMP-*` 设计增量 | 需求分析 brief | 已完成（2026-11-14，第 2 轮） | 两张场景卡四元素齐、3 正 1 反可执行、转 `designed`；写端口非可选/串行写/预算拆分拍板；`architecture.md` §3.1/§5 与组件规格增量；P1 提案已确认（`doc/history/decisions/2026-11-14-mail-write-path.md`） |
| `T-1114-11` | `change` | `CMP-DOMAIN` | `CMP-DOMAIN/spec.md` §设计增量：邮箱写路径（`MailWriteGateway`） | T-1114-10 + P1 确认 | 已完成（2026-11-14；2026-11-15 T-1114-19/20 验证通过） | `Ports.swift` 新增 `MailWriteGateway`（2 方法，非可选）；`MailDomainTests` 内加编译期遵循 mock（不进生产 target）；**不动 `SyncStore`**，不产生不可编译中间态；`./Scripts/swiftw test --filter MailDomainTests` 绿 |
| `T-1114-12` | `change` | `CMP-EAS` | `CMP-EAS/spec.md` §设计增量：Sync 写命令 | T-1114-11 | 已完成（2026-11-14；R16 真机已取证） | `sync(change:)` 支持 `.read`（`Change/ApplicationData/Read=1`）与 `.delete`（`Delete/ServerId`）；`EASClientTests` 32 例绿（golden 请求体/新 key/`Status=3/4`/写 401→`deviceNotRegistered`/Collection 内与顶层 `MoreAvailable`）；**R16 真机已证**：两命令均 `Collection/Status=1` + 新 key，读回 `Read=1`，删除进入「已删除邮件」，重复删除为成功 no-op；证据 `task-spaces/20261114-232232/evidence/r16-real-gateway.txt` |
| `T-1114-13` | `change` | `CMP-EASADAPTER` | `CMP-EASADAPTER/spec.md` §设计增量：写端口映射 | T-1114-11、T-1114-12 | 已完成（2026-11-14；2026-11-15 T-1114-19/20 验证通过） | `EASAdapter` 同时遵循读/写端口；`markRead`/`delete` 全量透传 `MessageDelta`、复用 `EASAdapter.map`；`EASAdapterTests` 补 delta 透传与写 401/3/4/offline；不在适配层判业务；`./Scripts/swiftw test --filter EASAdapterTests` 绿 |
| `T-1114-14` | `change` | `CMP-STORE + CMP-DOMAIN` | `CMP-STORE/spec.md` §设计增量：本地置读与写成功提交；`CMP-DOMAIN/spec.md` §设计增量：邮箱写路径（`SyncStore`） | T-1114-11 | 已完成（2026-11-14；2026-11-15 T-1114-19/20 验证通过） | 同批增 `SyncStore.markRead/commitMarkRead/commitDelete` 与 `MailStore` 实现/转发器，更新测试替身；`MailStoreTests` 覆盖只改目标行、已读幂等、delta+本地效果+key 同事务、回滚不推进 key、重复软删幂等、partial echo 不清空目标信封；全量 `./Scripts/swiftw test` 绿；不新增 schema；`MailStore` 组件 ≤1000 行，超限先停下报预算 |
| `T-1114-21` | `change` | `CMP-ROOT` | `CMP-ROOT/spec.md` §设计增量：写端口与同一引擎装配 | T-1114-13 | 已完成（2026-11-14；2026-11-15 T-1114-19/20 验证通过） | `GatewayEndpoints{read,write}` 与 `GatewayFactory` 端点化，`write` 非可选；`PlatformGateway.make` 返回同一 `EASAdapter` 的 read/write；`CompositionTests` 测试工厂显式注入 `UnsupportedWriteGateway`，断言生产 `write` 是 `EASAdapter`（需具体类型时同批补测试依赖）；`./Scripts/swiftw test --filter CompositionTests` + 架构门绿；组合根不判业务 |
| `T-1114-15` | `change` | `CMP-SYNC + CMP-ROOT（仅装配）` | `CMP-SYNC/spec.md` §设计增量：串行写路径；`CMP-ROOT/spec.md` §设计增量 | T-1114-11、T-1114-13、T-1114-14、T-1114-21 | 已完成（2026-11-14；2026-11-15 T-1114-19/20 验证通过） | `SyncEngine.init` 非可选 `writeGateway` + 显式 FIFO 门 + `markRead`/`deleteMessage`；`SyncEngineTests` 17 例覆盖写与 `syncOnce` 串行、key 恰好推进一次、失败不推进/不落本地、`Status=3/4` 的 reset+rebuild 与排队写互斥（fetch 顺序 `5→0→200`、写用重建后的 key）、写响应整页 delta/`MoreAvailable` 照常提交、取消不发网络；两处生产组合根传 `endpoints.write`；`./Scripts/swiftw test --filter SyncEngineTests` + 架构门绿 |
| `T-1114-16` | `change` | `CMP-SCN-READ + CMP-ROOT（仅装配）` | `CMP-SCN-READ/spec.md` §设计增量：自动已读与键盘删除；`CMP-ROOT/spec.md` §设计增量 | T-1114-15 | 已完成（2026-11-14；2026-11-15 T-1114-19/20 验证通过） | `ReadScene` 非可选 `writeEngine: SyncEngine` + `markReadLocally`/`writeBackMarkRead`/`deleteMessage`；`ScenesTests` 覆盖本地先行、回写失败不回滚、删除只在服务器成功后落本地、取消传播；同批更新测试构造点，并把两处生产组合根传同一个 `engine`；`./Scripts/swiftw test --filter ScenesTests` + 架构门绿 |
| `T-1114-17` | `change` | `CMP-PRES` | `CMP-PRES/spec.md` §设计增量：停留计时与键盘删除 | T-1114-16 | 已完成（2026-11-14；2026-11-15 T-1114-19/20 验证通过） | `MailboxDwell`/`MailboxDeletion` 与 VM 接线；主 VM **298 行**（目标 ≤380）；`PresentationTests` 52 例，新增覆盖切文件夹/搜索/删除取消计时、搜索模式进入与停留不计时、回前台不足 10 秒不置读、失活不发网络、写响应 `Read=0` 不回翻本地已读、删除非末条正文切换、失败恢复正文后重试、not-found 成功、隐藏行不可选中/打开；O5/R23 保持；`./Scripts/swiftw test --filter PresentationTests` 绿 |
| `T-1114-18` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：列表焦点删除与前台状态 | T-1114-17 | 已完成（2026-11-14；焦点五上下文与真实窗口前台探针已跑；2026-11-15 T-1114-19/20 验证通过） | 列表焦点 Delete/Backspace（`.onDeleteCommand` 优先、`.onKeyPress(.delete)` 备选）+ 前台状态转发 + 状态栏 `deleteErrorText`；焦点探针覆盖列表命中、搜索框/正文/撰写页/配置页不命中（`evidence/ui-delete-probe-focus.txt`）；真实 SwiftUI `WindowGroup` 探针证明 `scenePhase` 不随应用失活变化，前台信号改用 `NSApplication.willResignActive/didBecomeActive` 通知（`evidence/scene-phase-probe.txt`）；身份接线按 R23 结论；`./Scripts/swiftw test --filter PresentationTests` + 架构门绿 |
| `T-1114-19` | `verify` | SCN-0008（0 组件） | `SCN-0008` §测试/§状态 | T-1114-18 | 已完成（2026-11-15） | `T-SCN-0008-01..04`（3 正 1 反）全绿；`SCN-0003`/`SCN-0004` 回归；全量 `./Scripts/swiftw test` + 架构 4 门；证据入 `task-spaces/20261114-232232/evidence/`；结果见 `task-spaces/20261114-232232/test.md` |
| `T-1114-20` | `verify` | SCN-0009（0 组件） | `SCN-0009` §测试/§状态 | T-1114-19 | 已完成（2026-11-15） | `T-SCN-0009-01..04`（3 正 1 反）全绿；`SCN-0004`/`SCN-0003`/`SCN-0008` 回归；全量 `./Scripts/swiftw test` + 架构 4 门；状态翻转项已交收尾节点；证据入 `task-spaces/20261114-232232/evidence/`；结果见 `task-spaces/20261114-232232/test.md` |

并行：`T-1114-11` 完成后，`T-1114-12`（`CMP-EAS`）与 `T-1114-14`（`CMP-STORE` + `CMP-DOMAIN` 契约）分属不同组件/契约，可并行；`T-1114-21` 在 `T-1114-13` 后可启动，可与 `T-1114-14` 并行（不同组件），但必须早于 `T-1114-15`。`T-1114-11`/`T-1114-14` 都触碰 `CMP-DOMAIN`，按组件 WIP=1 串行；`T-1114-21`/`T-1114-15`/`T-1114-16` 都含 `CMP-ROOT`，串行且不并行第二个 `CMP-ROOT` 任务。`T-1114-16` 之后 `T-1114-17`、`T-1114-18` 串行；`T-1114-19`、`T-1114-20` 串行，验证不跳步。

**跨组件仅装配例外**：`T-1114-15`/`T-1114-16` 的组件列分别为 `CMP-SYNC + CMP-ROOT（仅装配）`、`CMP-SCN-READ + CMP-ROOT（仅装配）`。原因：写端口/写引擎非可选后，新增构造参数会让两处生产组合根编译失败；拆成独立 `CMP-ROOT` 任务无法形成可编译的单组件提交，保留旧构造/默认值又会重新制造静默退化。WIP 处置：同一时刻不并行第二个 `CMP-ROOT` 任务，`CMP-ROOT` 的 WIP 由该 change 独占；组合根只构造/注入/路由，不判业务。

`T-1114-14` 的 `CMP-STORE + CMP-DOMAIN` 不是装配例外，而是「公共契约与其唯一生产遵循同批」：`SyncStore` 加方法必须同批改 `MailStore`，否则无法编译；它只做一次验证（`MailStoreTests` + 全量编译），不拆成两个组件提交。

change 共同出口：`./Scripts/swiftw test` 全量绿（或过滤对应 target 绿且不破坏其他 target 编译）+ `bash Scripts/check-architecture.sh` 4 门过 + `SCN-0008`/`SCN-0009` 不回归 + 更新对应 `doc/design/components/<CMP>/spec.md` 的契约与实现进度 + 同步 `doc/design/architecture.md` §3/§5（数据所有权/写路径）与 §10；未更新规格不算完成。P1 已确认并归档为 `doc/history/decisions/2026-11-14-mail-write-path.md`，change 按该记录的边界执行。

本批统一验证命令：`./Scripts/swiftw test`、`bash Scripts/check-architecture.sh`；单任务过滤用 `./Scripts/swiftw test --filter <Target>`；verify 任务另跑 `T-SCN-0008-01..04`/`T-SCN-0009-01..04` 与 `SCN-0003`/`SCN-0004` 回归。

### 装载清单（2026-11-14 拆分复核）

| 任务 | 必读 | 预计装载 | 备注 |
|---|---|---|---|
| `T-1114-11` | `CMP-DOMAIN/spec.md` §设计增量；`Sources/MailDomain/Ports.swift`；`Tests/MailDomainTests` | ~300 行 | 只加端口 |
| `T-1114-12` | `CMP-EAS/spec.md` §设计增量；`EASClient.swift`、`WBXML.swift`；`EASClientTests`；playbook §3/§5 | ~1,600 行 | R16 探针证据 |
| `T-1114-13` | `CMP-EASADAPTER/spec.md` §设计增量；`EASAdapter.swift`；`CMP-DOMAIN` 写端口；`EASAdapterTests` | ~450 行 | 不判业务 |
| `T-1114-14` | `CMP-STORE/spec.md` §设计增量；`MailStore.swift`、`Migrations.swift`、`SyncStoreConformance.swift`；`CMP-DOMAIN` §设计增量；`MailStoreTests`；`Tests/SyncEngineTests` 与 `Tests/ScenesTests/ScenesSupport.swift` 的两个 `SyncStore` 替身 | ~1,900 行 | 本批最大；`MailStore` 超 1000 行先停 |
| `T-1114-21` | `CMP-ROOT/spec.md` §设计增量；`GatewayFactory.swift`、两处组合根；`CompositionTests` | ~600 行 | 只装配 |
| `T-1114-15` | `CMP-SYNC/spec.md` §设计增量；`SyncEngine.swift`；`SyncEngineTests`；`CMP-ROOT` 增量；测试替身 | ~1,100 行 | 门与 key |
| `T-1114-16` | `CMP-SCN-READ/spec.md` §设计增量；`ReadScene.swift`；`ScenesTests` 支持与用例；组合根 | ~1,050 行 | 同一 engine |
| `T-1114-17` | `CMP-PRES/spec.md` §设计增量；`MailboxViewModel.swift`、`PresentationTypes.swift`；`PresentationTests` 支持与用例 | ~1,100 行 | 主 VM 预算 |
| `T-1114-18` | `CMP-APP/spec.md` §设计增量；`MailboxView.swift`；`SCN-0009` §测试；`PresentationTests` | ~700 行 | UI 探针 |
| `T-1114-19`/`T-1114-20` | `SCN-0008`/`SCN-0009` §测试/§状态；`SCN-0003`/`SCN-0004` 回归；相关测试 | 各 ~1,500–1,700 行 | 证据入 `evidence/` |

装载纪律：本批按单任务 ≤2,000 行装载控制；单任务不跨第二个组件/契约，若实现时发现必须跨或装载超限，先停下按批次纪律重拆，不静默扩大。本批最大为 `T-1114-14`（约 1,900 行），已接近上限，仍限 `CMP-STORE`/`CMP-DOMAIN` 一个契约链。所有 change 另读 `doc/design/architecture.md` §3/§5/§10 的相关段落（约 150 行），并在出口同步。

P1 确认记录已归档为 `uumail/doc/history/decisions/2026-11-14-mail-write-path.md`（`frozen`，2026-11-14；确认来源与范围见文首）。记录包含：写端口全链路非可选与测试替身、T-1114-15/16 的 `CMP-ROOT` 仅装配例外与 WIP 处置、场景扇出 1–2→1–3（含窄 `SyncWriting` 替代方案 F）、**T-1114-11/14 的「契约与唯一生产遵循同批」边界**，以及 R16 真机带来的写响应 `MoreAvailable`/not-found/前台信号三项修订。R16 探针证据在 `task-spaces/20261114-232232/evidence/`，不写入本表。

## W-M3-04 任务表（菜单主题与深色阅读白底）

来源：`REQ-0015`/`REQ-0016`（`delivered`）、`SCN-0010`/`SCN-0011`（2026-11-16 落卡 `designed` 后转 `verified`）、`design/components/CMP-APP/spec.md` 与 `CMP-PRES/spec.md` §设计增量、确认记录 `history/decisions/2026-11-16-theme-appearance.md`。

**门已关闭，实现与验证已完成**：Q5（文档树与菜单入口）按 A、Q6（白底范围）按 A、P2（本批设计与 public 类型）确认，均记录在 `history/decisions/2026-11-16-theme-appearance.md`。`T-1116-01` 已完成；`T-1116-02`…`T-1116-04` 按组件顺序落地，`T-1116-05`→`T-1116-06` 串行验证。若发起人后续否决任一 P2 子项或改选 B，按本节「条件与回退」重开设计，本表任务号不复用。拆分过程与判据见 `task-spaces/20261116-154416/split.md`。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1116-01` | `design` | SCN-0010 / SCN-0011（0 组件） | `REQ-0015`/`REQ-0016`；`scenario-proposal.md` §frontmatter/§入口/§运行序/§测试；`CMP-APP`/`CMP-PRES` §设计增量 | 人工确认 Q5/Q6/P2 | 已完成（2026-11-16） | 确认来源记入 `history/decisions/2026-11-16-theme-appearance.md` 与两份组件规格（`open-questions.md` 移除 Q5/Q6）；两卡落在确认后的路径并转 `designed`；两卡测试表 3 正 1 反与 `T-SCN-0010-01..04`/`T-SCN-0011-01..04` 一致；`CMP-APP`/`CMP-PRES` 增量从「待确认/未实现」改为确认记录；`git -C uumail status` 仅文档，无代码/测试/Package 改动 |
| `T-1116-02` | `change` | `CMP-PRES` | `CMP-PRES/spec.md` §设计增量：主题偏好 | T-1116-01 | 已完成（2026-11-16） | `ThemePreferenceStoreTests` 的 `defaultsToSystemWhenUnset`/`roundTripsEachPreference`/`invalidValueFallsBackToSystem`/`persistsAndRestoresAcrossInstances`/`repeatedSaveKeepsSingleValue` 全绿；`./Scripts/swiftw test --filter PresentationTests` 绿；公开面不含 `UserDefaults`/`defaultsKey`；`CMP-PRES` 增量改为已实现 |
| `T-1116-03` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：菜单主题与深色阅读白底（阅读白底段） | T-1116-01 | 已完成（2026-11-16） | `AppearanceProbe`（L2）覆盖 `T-SCN-0010-01/03/04`：白色画布采样、作者样式保留/dark-media 抑制、畸形 HTML 仍得白底与 CSP；`./Scripts/swiftw build` 过；`MessageBodyStyle.swift` 承接 `baseCSS`/CSP/`sanitized`，`MessageBodyView` 不再持有；原始输出入 `task-spaces/<run>/evidence/`；`CMP-APP` 增量更新 |
| `T-1116-04` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：菜单主题与深色阅读白底（菜单主题段） | T-1116-02、T-1116-03 | 已完成（2026-11-16） | `ThemeProbe`（L2）覆盖 `T-SCN-0011-01..04`：默认/损坏回退、三项即时切换、重开持久化、勾选在打开父菜单后刷新、切换不重建窗口/不重载正文，并覆盖 `T-SCN-0010-02` 的切主题不重载部分；`./Scripts/swiftw build` 与 `./Scripts/swiftw test` 绿；R25 写失败按设计限制只做代码审查与「不抛/不回滚」断言，不伪造注入；证据入 `evidence/` |
| `T-1116-05` | `verify` | SCN-0011（0 组件） | `SCN-0011` §测试/§状态 | T-1116-04 | 已完成（2026-11-16） | 按 `SCN-0011` 测试表逐例验证 `T-SCN-0011-01..04`（L1 + L2）全绿；`SCN-0010`/`SCN-0001`/`SCN-0006` 回归；`./Scripts/swiftw test` + `bash Scripts/check-architecture.sh` 4 门；证据入 `evidence/`，**不做截图/AX**；只建议翻转，不自行改状态。允许改范围：`Tests/`（仅补测试）+ `task-spaces/<run>/`；不改产品代码、不新增探针 |
| `T-1116-06` | `verify` | SCN-0010（0 组件） | `SCN-0010` §测试/§状态 | T-1116-05 | 已完成（2026-11-16） | 按 `SCN-0010` 测试表逐例验证 `T-SCN-0010-01..04`（L1 + L2）全绿；`SCN-0004` 回归；`./Scripts/swiftw test` + 架构 4 门；证据入 `evidence/`，**不做截图/AX**；只建议翻转，不自行改状态。允许改范围：`Tests/`（仅补测试）+ `task-spaces/<run>/`；不改产品代码、不新增探针 |

并行关系：`T-1116-02`（`CMP-PRES`）与 `T-1116-03`（`CMP-APP` 阅读白底）在 `T-1116-01` 后可并行；`T-1116-04` 同时依赖二者，且与 `T-1116-03` 同组件，按组件 WIP=1 串行；`T-1116-05`→`T-1116-06` 串行验证，不跳步，也不并行第二个 `CMP-APP` 任务。

**条件与回退**：Q5 选 B 时，`T-1116-01` 改 `SCN-0011` 的 `flow`/路径，且须先按评审 U4 补 `ThemeCommands` 应用菜单落点的设计，再改 `T-1116-04` 的锚点；不能只改文档就开工。Q6 选 B 时，先改 `REQ-0015`/`SCN-0010` 范围，把附件条/远程开关/截断提示纳入 `T-1116-03`，并重估该任务装载；仍只改 `CMP-APP`。P2 否决白底机制/应用机制/偏好归属/菜单入口/测试载体任一子项时，回设计重评，`T-1116-01` 重新出卡，不复用本表任务号。

本批统一验证命令：`./Scripts/swiftw test`、`bash Scripts/check-architecture.sh`；单任务过滤用 `./Scripts/swiftw test --filter <Target>`；`AppearanceProbe`/`ThemeProbe` 的命令与原始输出按 `T-1116-01` 写实的测试表执行，证据入 `task-spaces/<run>/evidence/`。

### 装载清单（2026-11-16 拆分复核）

| 任务 | 必读 | 预计装载 | 备注 |
|---|---|---|---|
| `T-1116-01` | `scenario-proposal.md`；`brief.md` §6；`design.md` §6；`CMP-APP`/`CMP-PRES` §设计增量；`history/decisions/2026-11-16-theme-appearance.md` | ~900 行 | 确认已归档；落卡并转 `designed`；关闭 Q5/Q6 |
| `T-1116-02` | `CMP-PRES/spec.md` §设计增量；`Sources/Presentation`；`Tests/PresentationTests`；`Package.swift` | ~700 行 | 不碰 `.standard`；不新增依赖 |
| `T-1116-03` | `CMP-APP/spec.md` §阅读白底；`MessageBodyView.swift`；`SCN-0010` §测试；`AppearanceProbe` 基座 | ~800 行 | 不改 CSP 策略；不新增 target |
| `T-1116-04` | `CMP-APP/spec.md` §菜单主题；`UumailApp.swift`；`MessageBodyView.swift`；`SCN-0011` §测试；`ThemeProbe` 基座 | ~900 行 | 不新增 target；不重建窗口 |
| `T-1116-05` | `SCN-0011` §测试/§状态；`SCN-0010`/`SCN-0001`/`SCN-0006` 回归；探针输出 | ~1,600 行 | 证据入 `evidence/` |
| `T-1116-06` | `SCN-0010` §测试/§状态；`SCN-0004` 回归；探针输出 | ~1,600 行 | 证据入 `evidence/` |

装载纪律：单任务 ≤2,000 行；若实现时发现必须跨第二个组件/契约或装载超限，先停下按批次纪律重拆，不静默扩大。本批 change 的出口另要求更新对应 `doc/design/components/<CMP>/spec.md` 的实现进度；未更新规格不算完成。

## 批次纪律

- 每个工序一次立一个 `works/` 目录；2026-11-14 起过程记录放工作区 `task-spaces/<run>/`，**任务表写在本文件对应工序节**，brief 只保留当次分析/范围，不维护第二份现行任务表；一个任务一个对话。
- 组件级 WIP=1：同一时刻只有一个在飞任务改同一组件。
- M1 未通过前不启动 M2；M2 与 M3 可并行但共享 CMP-SYNC，需错峰。
