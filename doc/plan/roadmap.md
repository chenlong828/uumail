---
layer: plan
module: global
scope: project:uumail
status: current
updated: 2026-11-17
---

# 路线图

只记里程碑、工序与依赖。需求状态看 `requirements/`，设计真相看 `design/`。
首版范围已于 2026-11-09 确认：REQ-0001…0007 `accepted`（`history/decisions/2026-11-09-scope-baseline.md`）。2026-11-14 追加并交付：REQ-0012「全部回复的收件人与抄送预填」`delivered`（W-M2-03，任务表见本文 §W-M2-03 任务表）。2026-11-14 追加需求分析并纳入 W-M3-03：REQ-0013「列表停留自动已读」与 REQ-0014「列表键盘删除」已于 2026-11-15 交付（`SCN-0008`/`SCN-0009` `verified`、两需求 `delivered`）；设计已完成（P1 已确认并归档），任务拆分复核完成（2026-11-14），任务表见本文 §W-M3-03 任务表。2026-11-16 追加 W-M3-04 并完成交付：REQ-0015「深色阅读白底」与 REQ-0016「菜单主题切换」`delivered`；Q5/Q6/P2 已于 2026-11-16 确认（`history/decisions/2026-11-16-theme-appearance.md`），`SCN-0010`/`SCN-0011` 已由 `designed` 转 `verified`，`T-1116-01`…`T-1116-06` 已完成；任务表见 §W-M3-04。2026-11-16 追加 W-M3-05 并完成交付：REQ-0017「阅读页信封头」`delivered`、`SCN-0012` `verified`；P2（D1–D8）已于 2026-11-16 确认（`history/decisions/2026-11-16-reading-pane-headers.md`），`T-1116-07`…`T-1116-10` 已完成；任务表见 §W-M3-05。2026-11-16 另立 W-M3-06（远程图片开关并入工具栏、手动标记已读、自动已读 10→3 秒）：`REQ-0018`/`REQ-0019` `accepted`、`REQ-0013` 重开 `accepted`，`SCN-0013`/`SCN-0014`/`SCN-0008` 均 `designed`；P2（D1–D8）已于 2026-11-16 确认（`history/decisions/2026-11-16-remote-toolbar-mark-read.md`），`T-1116-11`…`T-1116-16` 于 2026-11-17 全部完成；`SCN-0008`/`SCN-0013`/`SCN-0014` 已转 `verified`、`REQ-0013`/`REQ-0018`/`REQ-0019` 已转 `delivered`（`task-spaces/20261117-064420/review.md` §7）；任务表见 §W-M3-06。2026-11-17 的 W-M3-07（界面与阅读字体大小可调）已完成交付：`REQ-0020` `delivered`、`SCN-0015` `verified`；实现提交 `2c2b1a2` + 评审回退修复 `d958da9`，`T-SCN-0015-01..04`（3 正 1 反）L1 6/6、L2 342/0、全量 275 tests / 50 suites、架构 4/4（`task-spaces/20261117-095147/review.md` §8/§12）；任务号 `T-1117-01` 为无人值守默认决策（未经人工），task-split 未产出独立任务表。
工序目录名沿用历史 `works/YYYY-MM-DD-<短名>/`；2026-11-14 起过程记录放工作区 `task-spaces/<run>/`，**任务表作为项目排期的一部分落在本文件**，不再只存在于某次运行的 brief 里。

## 里程碑

| 里程碑 | 目标 | 出口判据 | 状态 |
|---|---|---|---|
| M0 协议探针 | 证明外网 EAS 通道可用，锁定线格式、设备身份与命令覆盖 | 命令行跑通 `OPTIONS → Provision → FolderSync → Sync → ItemOperations → SendMail`，实测状态码与能力矩阵成文 | 已完成（`history/works/2026-11-09-eas-probe/`） |
| M1 只读客户端 | 账号接入、文件夹树、列表、正文、附件、离线缓存 | 五个只读场景（SCN-0001…0005）全部 `verified` | 进行中：账号、文件夹树、列表、正文已通；附件 02–04 未实现；场景卡待转 `verified` |
| M2 发送与草稿 | Outbox、SendMail、回复/转发、草稿、Sent 镜像、全部回复 | send-message 场景 `verified`；离线发送可在联网后只发一次 | 进行中：Outbox 入队/冷投递/重试已实现；Sent 镜像与撰写附件未做；全部回复 `SCN-0007` `verified`（2026-11-14，T-1114-09，含真机 UI 冒烟），REQ-0012 `delivered`；其余场景卡待 `verified` |
| M3 体验 | Ping、通知、本地搜索、错误恢复与空态 | 新邮件端到端 ≤ 60s 可见（Ping 或轮询）；搜索、通知场景 `verified`；W-M3-03 的 `SCN-0008`/`SCN-0009` `verified` | 进行中：Ping 不支持 → 5 分钟轮询；搜索与通知已落地，场景卡待 `verified`；W-M3-03 已交付（2026-11-15，T-1114-19/20 验证）：`SCN-0008`/`SCN-0009` `verified`、REQ-0013/REQ-0014 `delivered`；P1 frozen 记录与 R16 真机证据已归档；W-M3-05（阅读页信封头）已完成（2026-11-16）：`SCN-0012` `verified`、REQ-0017 `delivered`，`T-1116-07`…`T-1116-10` 完成；W-M3-06（远程开关/手动置读/3 秒）已完成（2026-11-17）：`SCN-0008`/`SCN-0013`/`SCN-0014` `verified`、`REQ-0013`/`REQ-0018`/`REQ-0019` `delivered`，`T-1116-11`…`T-1116-16` 完成；W-M3-07（界面/阅读字号）已完成（2026-11-17）：`SCN-0015` `verified`、`REQ-0020` `delivered`，`T-1117-01`（默认号，未经人工）完成 |
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
| W-M3-05 阅读页信封头 | M3 | W-M3-04；REQ-0017 `delivered`；SCN-0012 `verified`；P2（D1–D8）已确认（`history/decisions/2026-11-16-reading-pane-headers.md`） | CMP-PRES、CMP-APP | 已完成（2026-11-16）：`T-1116-07`（P2 确认门）已落盘，`T-1116-08`→`T-1116-09` 实现完成，`T-1116-10` 验证通过；出口达成：`SCN-0012` `verified`、`REQ-0017` `delivered`、`T-1116-07`…`T-1116-10` 完成；任务表见本文 §W-M3-05 任务表 |
| W-M3-06 远程开关归位、手动置读与 3 秒自动已读 | M3 | W-M3-05；REQ-0013/REQ-0018/REQ-0019 `delivered`；SCN-0008/SCN-0013/SCN-0014 `verified`；P2（D1–D8）已确认（`history/decisions/2026-11-16-remote-toolbar-mark-read.md`） | CMP-PRES、CMP-APP | 已完成（2026-11-17）：确认门 `T-1116-11` 于 2026-11-16 落盘，`T-1116-12`/`T-1116-13` 实现完成，`T-1116-14`…`T-1116-16` 逐例验证通过（12/12 例子）；全量 269 tests / 49 suites、架构 4 门、三份 L2 探针 32/5/16 通过；`SCN-0008`/`SCN-0013`/`SCN-0014` 转 `verified`、`REQ-0013`/`REQ-0018`/`REQ-0019` 转 `delivered`；任务表见本文 §W-M3-06 |
| W-M3-07 界面与阅读字体大小可调 | M3 | 代码基线 `4ae0108`；REQ-0020 `delivered`；SCN-0015 `verified`；设计 `task-spaces/20261117-071134/design.md`（第 2 轮） | CMP-PRES、CMP-APP | 已完成（2026-11-17）：实现 `2c2b1a2` + 评审回退修复 `d958da9`（`ComposeView` 100% 恒等、`EmptyState` 语义基值）；`T-SCN-0015-01..04`（3 正 1 反）L1 6/6、L2 342/0（`fontsize-web` 38 PASS，含 R40 图片/表格 8 条）、全量 275 tests / 50 suites、架构 4/4；`SCN-0015` 转 `verified`、`REQ-0020` 转 `delivered`（`task-spaces/20261117-095147/review.md` §8/§12）；`T-1117-01` 为无人值守默认任务号（未经人工），task-split 未产出独立任务表 |
| W-M3-08 HTML 回复撰写 | M3 | W-M3-07；REQ-0021 `delivered`；SCN-0016 `verified`；P2（D1–D8）已登记（`history/decisions/2026-11-17-html-compose.md`） | CMP-DOMAIN、CMP-STORE、CMP-OUT、CMP-SCN-COMPOSE、CMP-PRES、CMP-APP | 已完成（2026-11-17）：`T-1117-20`…`T-1117-27`；`Draft/OutboxItem.bodyHTML`、outbox v10 `body_html`、`multipart/alternative`、全宽 HTML 引文、`ComposeDocument`、WKWebView 编辑器/格式栏/取消确认/sheet 等宽落地；`SCN-0016` 转 `verified`、`REQ-0021` 转 `delivered`；全量 292 tests / 51 suites、架构 4 门；真实 App UI 冒烟 sheet 1441pt = detail 1440pt；任务表见本文 §W-M3-08 任务表 |
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

## W-M3-05 任务表（阅读页信封头）

来源：`REQ-0017`（`delivered`）、`SCN-0012`（`verified`）、`REQ-0004` 的 2026-11-16 归属澄清、`design/components/CMP-PRES/spec.md` 与 `CMP-APP/spec.md` §设计增量：阅读页信封头、设计评审 `task-spaces/20261116-212545/review.md`（pass，N1–N7）、拆分记录 `task-spaces/20261116-212545/split.md`。

**门已关闭（2026-11-16）**：D1–D8 已按 `design.md` §9.2 的建议答案确认，确认记录见 `history/decisions/2026-11-16-reading-pane-headers.md`（`frozen`）。`T-1116-07` 完成后 `T-1116-08`→`T-1116-09` 可开工，再由 `T-1116-10` 复跑验证；本表不代签，也不把确认写成评审通过。**已完成（2026-11-16）**：`T-1116-07`…`T-1116-10` 全部完成，`SCN-0012` 已转 `verified`、`REQ-0017` 已转 `delivered`（`task-spaces/20261116-212545/review.md` §9.7，收尾按清单翻转）。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1116-07` | `design`（确认门） | SCN-0012（0 组件） | `SCN-0012` §入口/§测试/§状态；`CMP-PRES`/`CMP-APP` §设计增量：阅读页信封头；`design.md` §9.2 D1–D8 | —（人工确认先行） | 已完成（2026-11-16） | `doc/history/decisions/2026-11-16-reading-pane-headers.md` 以 `frozen` 落盘，逐项覆盖 D1–D8 与结论，写明谁/何时/确认哪几项/影响；若 D1/D4 有收窄或改动，同批由设计节点同步 `CMP-PRES`/`CMP-APP` 增量与 `SCN-0012` 断言后再放行；`MessageHeaderPresentation`/`headerPresentation` 补进 `CMP-PRES` 模块卡公开契约摘要；`git -C uumail status` 只见文档，无 `Sources/`/`Tests/`/`Package.swift`；**人工门，不计 L1–L4** |
| `T-1116-08` | `change` | `CMP-PRES` | `CMP-PRES/spec.md` §设计增量：阅读页信封头（`MessageHeaderPresentation`/`Row`、`MailboxViewModel.headerPresentation`、映射规则、L1 测试计划） | T-1116-07 | 已完成（2026-11-16） | `MessageHeaderPresentationTests` 覆盖完整/稀疏/空白/畸形日期/行序/行上限全绿；`MailboxViewModelTests` 增补切换/无选中/`select(folderID:)`/跨文件夹同 `serverID`，并断言读取 `headerPresentation` 不新增网关/场景调用；`./Scripts/swiftw test --filter PresentationTests` + `bash Scripts/check-architecture.sh` 4 门；公开面与规格一致（或按 D1 确认收窄）；`MessageHeaderPresentation.swift` 约 70 行、`MailboxViewModel` ≤400；`CMP-PRES` 增量只追加实现进度行；证据入 `task-spaces/<run>/evidence/`；`L1（单元测试）` |
| `T-1116-09` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：阅读页信封头（`MessageHeaderView`、`MessageBodyView(header:)`、`MailboxView` 接线、R27、L2）；`SCN-0012` §测试载体 | T-1116-08 | 已完成（2026-11-16） | `HeaderProbe`（L2）覆盖 `T-SCN-0012-01..04` 全 `PASS`：头部在正文状态机外、`.none` 两义、空字段隐藏、切换无残留、`.failed` 保留头部、清空后只剩占位；`.loaded` 段链生产 `MessageBodyView`/`MessageBodyStyle` + WebKit；R27 行数/≤170pt/正文 ≥150pt（320pt 面板）与头部在正文上方的坐标改成 `expect`，补长 Cc 夹具；探针编译生产路径而非 `seam-src/`；`./Scripts/swiftw build` + `./Scripts/swiftw test` + 架构 4 门；证据入 `task-spaces/<run>/evidence/header-probe/`；单文件预算：`MessageBodyView`/`MailboxView` ≤300、`MessageHeaderView` 约 45；`L2（无头探针）`（T-03 的 L1 段由 T-1116-08 覆盖） |
| `T-1116-10` | `verify` | SCN-0012（0 组件） | `SCN-0012` §测试/§状态/§与相邻场景的边界；`SCN-0004`/`SCN-0010` §测试（回归） | T-1116-09 | 已完成（2026-11-16） | 按 `SCN-0012` 逐例复跑 `T-SCN-0012-01..04`（3 正 1 反，L1+L2）全绿，含 `.loaded` 与 R27 断言；`SCN-0004` 的 02/04 与既有组件用例、`SCN-0010` 的 01..04 回归不退化（`SCN-0004` 的 01 性能/03 CSP 自动化属既有欠账，不纳入本批，也不得因本批新增失败）；`./Scripts/swiftw test` + `bash Scripts/check-architecture.sh` 4 门；证据入 `task-spaces/<run>/evidence/`；只建议翻转，不自行改状态；`L1（单元测试）+ L2（无头探针）` |

任务边界（每个任务卡的可执行边界）：

| 任务 | 允许改的范围 | 明确不做 |
|---|---|---|
| `T-1116-07` | `doc/history/decisions/` 新确认记录；确认结论要求时由设计节点同步两份组件增量与 `SCN-0012` 断言；`CMP-PRES` 模块卡公开契约摘要补索引 | 不写实现/测试；不代签；不自行选默认值当确认；不改 `REQ-0017` 范围 |
| `T-1116-08` | `Sources/Presentation/MessageHeaderPresentation.swift`（新增）、`Sources/Presentation/MailboxViewModel.swift`、`Tests/PresentationTests/MessageHeaderPresentationTests.swift`（新增）、`Tests/PresentationTests/MailboxViewModelTests.swift`（增补）、`Tests/PresentationTests/Support.swift`（仅在夹具需要时）、`CMP-PRES` 增量实现进度行（只追加）、`task-spaces/<run>/` | 不改 `MailDomain`/`MailStore`/schema/协议/`DisplayFormat` API；不改场景卡/需求卡/决策记录/roadmap 门状态；不做 L2 探针；不碰 `CMP-APP` 文件 |
| `T-1116-09` | `Sources/uumail/MessageHeaderView.swift`（新增）、`Sources/uumail/MessageBodyView.swift`、`Sources/uumail/MailboxView.swift`、`CMP-APP` 增量实现进度行（只追加）、`task-spaces/<run>/`（含 `dev.md` 与 `evidence/header-probe/`） | 不改 `MessageWebView` 的白底/CSP/禁 JS 语义、`MessageBodyStyle` 行为、`UumailApp`/主题菜单、列表/工具栏/搜索/附件条/远程开关/截断 banner；不改 `Package.swift`/新增 target/依赖；不改场景卡/需求卡/决策记录/roadmap 门状态；不做 L3 截图/OCR 或 L4 AX |
| `T-1116-10` | `Tests/`（仅在测试缺口时补测试）、`task-spaces/<run>/evidence/`、本节点报告 | 不改产品代码；不新增探针 target；不改设计产物/需求/场景/门状态；不自行翻转 `verified`/`delivered`/任务完成 |

共同约束：每个 change 一个实现 commit，message 带 `T-` 与 `SCN-`；规格实现进度行随实现 commit 只追加，若需改契约/形状/测试断言，回设计，不在任务里自行扩。越权清单按 `af-flow-rule` §4：改设计产物、自授权人工门、发布动作、出口外探针，发现即停手并在 `dev.md` 记「超出任务范围」。

并行关系：**本批无可并行任务**。`T-1116-07`→`T-1116-08`→`T-1116-09`→`T-1116-10` 为单链：07 是人工门，未关闭前 change 不得启动；08 新增的 `MessageHeaderPresentation`/`headerPresentation` 是 09 的直接输入（共享公共契约必须串行）；09→10 是实现→验证，验证不跳步。组件级 WIP=1 自然满足：同一时刻只有一个 `CMP-PRES` 或 `CMP-APP` 任务在飞。

**条件与回退**：P2 否决 D1/D2/D3/D5/D6/D7/D8 任一 → 回设计重评，`T-1116-07` 重新出结论，`T-1116-08`…`T-1116-10` 不复用本表边界硬做。D1 收窄 `Row` 公开面时，08 出口加「无多余 public API」核对，探针改用可构造夹具的替代，不重拆。D4 改行上限/R27 预算时，先由设计节点改 `SCN-0012` 断言与两份增量，再开工并重估 09 装载。若 08 发现必须改 `MailDomain.Message`/`DisplayFormat` 公共 API，或 09 发现 `MessageHeaderPresentation` 形状不足，停下回设计，不在任务里扩。若 `.loaded` 的生产视图在无头探针不可观察，先按 `SCN-0012` §测试载体换 seam；仍不可行则由场景卡声明 L3 并回设计改卡，**不得**静默降级或用 L1 冒充。

本批统一验证命令：`./Scripts/swiftw test`、`bash Scripts/check-architecture.sh`；单任务过滤用 `./Scripts/swiftw test --filter PresentationTests`；`HeaderProbe` 的编译/复跑按 `SCN-0012` §测试载体执行，证据入 `task-spaces/<run>/evidence/`。

**回归口径**：`SCN-0004` 只回归 `T-SCN-0004-02`/`04` 与既有组件用例；`T-SCN-0004-01`（1 万封 <1s P95）与 `03`（CSP 自动化断言）是既有欠账（`SCN-0004` §状态），本批不补、不算本批失败，也不得因本批新增失败。`SCN-0010` 已 `verified`，按 `T-SCN-0010-01..04` 回归。`SCN-0008`/`SCN-0009`/`SCN-0005` 不在本批场景回归清单；若实现意外触及，再按对应卡补回归并记录。

### 装载清单（2026-11-16 W-M3-05 拆分）

| 任务 | 必读 | 预计装载 | 备注 |
|---|---|---|---|
| `T-1116-07` | `SCN-0012`；`CMP-PRES`/`CMP-APP` §设计增量；`design.md` §9.2；`review.md` §3/§5；`history/decisions/` 格式参考 | ~500 行 | 人工确认；不代签 |
| `T-1116-08` | `CMP-PRES` §设计增量；`Sources/Presentation/MessageHeaderPresentation.swift`（新）；`MailboxViewModel.swift`；`ErrorText.swift`；`PresentationTypes.swift`；`Tests/PresentationTests/MailboxViewModelTests.swift`、`Support.swift` | ~1,000 行 | 只加 public 类型/派生属性与 L1；不碰 `.loaded` |
| `T-1116-09` | `CMP-APP` §设计增量；`MessageBodyView.swift`、`MailboxView.swift`、`MessageBodyStyle.swift`；`MessageWebView`（在 `MessageBodyView.swift` 内，只读）；`SCN-0012` §测试载体；设计探针 `HeaderProbe`/`probe-commands.txt` 基座 | ~1,500 行 | `.loaded` 链 WebKit；换生产路径 |
| `T-1116-10` | `SCN-0012` §测试/§状态/§边界；`SCN-0004`/`SCN-0010` §测试；探针与测试输出 | ~1,700 行 | 3 正 1 反，复跑 + 回归；只建议翻转 |

装载纪律：单任务 ≤2,000 行；若实现时发现必须跨第二个组件/契约或装载超限，先停下按批次纪律重拆，不静默扩大。所有任务另读 `doc/design/architecture.md` §2/§3 的相关段落（约 100 行）并核对依赖方向未变。

## W-M3-06 任务表（远程开关归位、手动置读与 3 秒自动已读）

来源：`REQ-0018`/`REQ-0019`（`delivered`）、`REQ-0013`（`delivered`，重开后转回）、`SCN-0013`/`SCN-0014`（`verified`）、`SCN-0008`（按 3 秒修订后 `verified`）、`design/components/CMP-PRES`/`CMP-APP`/`CMP-SCN-READ` §2026-11-16 设计增量、设计 `task-spaces/20261116-223645/design.md`（第 2 轮）与评审 `task-spaces/20261116-223645/review.md`（pass，N1–N9）、拆分记录 `task-spaces/20261116-223645/split.md`；完成记录 `task-spaces/20261117-064420/review.md`（pass）与 `test.md`。

**门已确认（2026-11-16，发起人本次运行指令）**：`MailboxViewModel` 新增 6 个 public 成员与 `MailboxToolbar` 形态属 P2，发起人已按 `design.md` §8.2 的 D1–D8 唯一建议答案逐项确认（无收窄、无改选），确认记录见 `history/decisions/2026-11-16-remote-toolbar-mark-read.md`（`frozen`，含 N6：`MailboxToolbar` 为 `CMP-APP` 内部文件、非新组件；记录由 run `20261117-060443` 按发起人指令代录）。`T-1116-11` 已确认，`T-1116-12`/`T-1116-13` 实现已提交，`T-1116-14`…`T-1116-16` 逐例验证通过；**已完成（2026-11-17）**：`SCN-0008`/`SCN-0013`/`SCN-0014` 转 `verified`、`REQ-0013`/`REQ-0018`/`REQ-0019` 转 `delivered`、`T-1116-11`…`T-1116-16` 完成（`task-spaces/20261117-064420/review.md` §7，收尾按清单翻转）；本表不把确认写成评审通过。评审 N1–N9 的处理：N2 即本门；N3 回退口径见本节「条件与回退」；N4 探针换生产源、N5 正文侧探针并入 `T-1116-13`；N6 在确认记录中明确 `MailboxToolbar` 是 `CMP-APP` 内部文件、非新组件（若人改判新增组件，按 P1 停手回设计）；N7 的选中入口约束写进 12 的 L1；N1/N8/N9 是历史措辞、reason 脱敏与像素/AX 限制，不改变本批任务边界，也不另立任务。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1116-11` | `design`（确认门） | SCN-0013 / SCN-0014 / SCN-0008（0 组件） | `design.md` §8.2 D1–D8；`CMP-PRES`/`CMP-APP` 增量「P2 已确认」段；`SCN-0013`/`SCN-0014`/`SCN-0008` §状态 | —（人工确认先行） | 已完成（2026-11-17；确认门 2026-11-16，任务发起人；记录 `history/decisions/2026-11-16-remote-toolbar-mark-read.md`，run `20261117-060443` 代录） | `doc/history/decisions/2026-11-16-remote-toolbar-mark-read.md` 以 `frozen` 落盘，逐项覆盖 D1–D8，写明谁/何时/确认哪几项/影响范围，并明确 `MailboxToolbar` 为 `CMP-APP` 内部文件、非新组件（N6）；若任一项收窄或改选，先由设计节点同步 `CMP-PRES`/`CMP-APP` 增量与 `SCN-0013`/`SCN-0014`/`SCN-0008` 断言后再放行；`git -C uumail status` 只见文档，无 `Sources/`/`Tests/`/`Package.swift`；**人工门，不计 L1–L4** |
| `T-1116-12` | `change` | `CMP-PRES` | `CMP-PRES/spec.md` §设计增量：远程图片放行与手动置读（`:306-342`）；`CMP-SCN-READ/spec.md` §设计增量：手动置读复用（`:120-126`）；`SCN-0013`/`SCN-0014` §测试 L1 行；`SCN-0008` §测试（`.seconds(3)` 断言） | T-1116-11 | 已完成（2026-11-17） | `MailboxViewModel` 落地 6 个 public 成员与 internal `performMarkRead -> MailError?`/`normalizeMarkReadError`/`localMarkRead`；`selectedListKey` 身份变化重置放行与错误；`MailboxDwell` 去掉 `ReadScene`/`onMarked`、改 3 秒仅计时 + `onElapsed` 并在 init 接线。`./Scripts/swiftw test --filter PresentationTests` 绿，至少含 `remoteContentResetsOnSelectionChange`、`remoteContentCannotLeakToStaleBody`、`manualMarkReadPersistsBeforeWriteBack`、`manualMarkReadIsIdempotentAndSelectionScoped`、`manualMarkReadRacesDwellOnce`、`manualMarkReadWriteBackFailureKeepsLocal`、`manualMarkReadLocalFailureReportsChinese`、`manualMarkReadNonMailErrorReportsChinese`、`normalizeMarkReadErrorWrapsNonMailError`、`dwellAsksForThreeSecondsAndMarks`，既有 dwell 取消/后台/重载用例按 3 秒更新且不回归；`bash Scripts/check-architecture.sh` 4 门；`MailboxViewModel` ≤400 行、`MailboxDwell` ≤70 行；`CMP-PRES` 增量只追加实现进度行；证据入 `task-spaces/<run>/evidence/t1116-12-presentation.txt`；`L1（单元测试）` |
| `T-1116-13` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：工具栏归位、远程图片放行与手动置读（`:129-175`）；`SCN-0013` §测试载体（`RemoteContentToolbarProbe`/`RemoteContentBodyProbe`）；`SCN-0014` §测试载体（`ManualMarkReadProbe`） | T-1116-12 | 已完成（2026-11-17） | 新 `Sources/uumail/MailboxToolbar.swift`（7 个图标控件、固定顺序、`State`/`Actions`、禁用条件）；`MailboxView` 换工具栏、状态栏在 `deleteErrorText` 后显示 `markReadErrorText`、阅读区传 `allowRemoteContent`；`MessageBodyView` 删 `@State` 与正文开关行、加只读 `Bool`；`MessageWebView` 的 CSP/禁 JS/白底/`lastRender` 不变。`./Scripts/swiftw build` + `./Scripts/swiftw test` + 架构 4 门；单文件预算：`MailboxView` ≤300、`MessageBodyView` ≤300、`MailboxToolbar` ≤300。L2 探针编译**生产** `Sources/uumail/MailboxToolbar.swift`（非 `seam-src/`）：`RemoteContentToolbarProbe.toggleLivesInWindowToolbar`（900×560 + 搜索框，7 项全在 `visibleItems`、「加载远程图片」恰好一个）、`...selectionResetsToBlocked`、`...unavailableStatesDoNotFire`；`ManualMarkReadProbe.toolbarButtonInvokesMarkRead`、`...buttonDisabledWhenNoUnread`；`RemoteContentBodyProbe.bodyHasNoRemoteToggleRow`、`...toggleReloadsWithMatchingCSP`（生产 `MessageBodyView`/`MessageWebView`/`MessageBodyStyle`，假 HTML，不加载真实远程资源）；另跑 `RemoteContentProbe.cspHasTwoExactTiers`（L1 两档 CSP 精确值）。全部 PASS/0 FAIL，覆盖 `T-SCN-0013-01..04` 的入口/重载/重置/禁用部分与 `T-SCN-0014-01/02` 的入口部分；探针源码与原始输出入 `task-spaces/<run>/evidence/`；`CMP-APP` 增量只追加实现进度行；`L1（CSP 值）+ L2（无头探针）` |
| `T-1116-14` | `verify` | SCN-0008（0 组件） | `SCN-0008` §测试/§状态/§与相邻场景的边界；`CMP-PRES` 增量：计时器重构（`:331-334`）；`CMP-SCN-READ` 增量：手动置读复用（`:120-126`） | T-1116-13 | 已完成（2026-11-17） | 按 `SCN-0008` 逐例复跑 `T-SCN-0008-01..04`（3 正 1 反）全绿，含「传给 sleep 的时长为 `.seconds(3)`」断言与 2 秒切走/后台负例；`SCN-0003`/`SCN-0004` 回归不退化（`SCN-0004` 的 `T-SCN-0004-01/03` 属既有欠账，不纳入本批，也不得因本批新增失败）；`./Scripts/swiftw test` + `bash Scripts/check-architecture.sh` 4 门；证据入 `task-spaces/<run>/evidence/t1116-14-scn-0008.txt`；只建议翻转，不自行改状态；`L1（单元测试）` |
| `T-1116-15` | `verify` | SCN-0013（0 组件） | `SCN-0013` §测试/§状态/§与相邻场景的边界；`CMP-APP` 增量：工具栏归位（`:132-173`）；`CMP-PRES` 增量：远程放行（`:320-324`） | T-1116-14 | 已完成（2026-11-17） | 按 `SCN-0013` 逐例复跑 `T-SCN-0013-01..04`（3 正 1 反，L1+L2）全绿：工具栏 7 项可见/无溢出、正文无独立开关行、默认关、开/关重载、切邮件重置与陈旧正文 no-op、不可用禁用；`SCN-0004` 的 02/04 与既有组件用例、`SCN-0010` 的 `01..04` 回归不退化；`./Scripts/swiftw test` + 架构 4 门；证据入 `task-spaces/<run>/evidence/t1116-15-scn-0013.txt`；只建议翻转，不自行改状态；`L1（单元测试）+ L2（无头探针）` |
| `T-1116-16` | `verify` | SCN-0014（0 组件） | `SCN-0014` §测试/§状态/§与相邻场景的边界；`CMP-PRES` 增量：手动置读（`:325-330`）；`CMP-APP` 增量：工具栏/状态栏（`:160-167`） | T-1116-15 | 已完成（2026-11-17） | 按 `SCN-0014` 逐例复跑 `T-SCN-0014-01..04`（3 正 1 反，L1+L2）全绿：本地先行/恰好一次回写、已读与无选中禁用、并发幂等、回写失败静默；本地写失败覆盖 `MailError` 与非 `MailError`（`MailStoreError.database`/`NSError`），断言「本地存储失败：…」中文前缀、保持未读、零回写；`SCN-0008`/`SCN-0004` 回归不退化；`./Scripts/swiftw test` + 架构 4 门；证据入 `task-spaces/<run>/evidence/t1116-16-scn-0014.txt`；只建议翻转，不自行改状态；`L1（单元测试）+ L2（无头探针）` |

任务边界（每个任务卡的可执行边界）：

| 任务 | 允许改的范围 | 明确不做 |
|---|---|---|
| `T-1116-11` | `doc/history/decisions/` 新确认记录（只写确认事实与影响，不写实现） | 不写实现/测试；不代签；不把建议答案写成确认；不改需求范围；不直接改规格/场景断言（收窄时另由设计节点同步） |
| `T-1116-12` | `Sources/Presentation/MailboxViewModel.swift`、`MailboxDwell.swift`（必要时 `MailboxViewModel+*.swift` 扩展文件）、`Tests/PresentationTests/MailboxViewModelTests.swift`、`Tests/PresentationTests/Support.swift`（仅夹具需要时）、`CMP-PRES` 增量实现进度行（只追加）、`task-spaces/<run>/` | 不改 `CMP-APP`/`uumail` 文件；不改 `MailDomain`/`MailStore`/`Scenes`/`MailGateway`/schema/协议；不改场景卡/需求卡/决策记录/roadmap 门状态；不做 L2 探针；不新增 target/依赖 |
| `T-1116-13` | `Sources/uumail/MailboxToolbar.swift`（新增）、`MailboxView.swift`、`MessageBodyView.swift`、`CMP-APP` 增量实现进度行（只追加）、`task-spaces/<run>/`（含 `dev.md`、探针源码与 `evidence/`） | 不改 `MessageWebView` 的 CSP/禁 JS/白底/`lastRender`，不改 `MessageBodyStyle` 行为；不改 `UumailApp`/主题菜单/列表/侧栏/搜索/附件条/头部/截断 banner；不改 `Package.swift`/新增 target/依赖；不改场景卡/需求卡/决策记录/roadmap 门状态；不做 L3 截图/OCR 或 L4 AX；不新增第二条工具条/第二处入口 |
| `T-1116-14` | `Tests/`（仅在测试缺口时补测试）、`task-spaces/<run>/evidence/`、本节点报告 | 不改产品代码；不新增探针；不改设计产物/需求/场景/门状态；不自行翻转 `verified`/`delivered`/任务完成 |
| `T-1116-15` | `Tests/`（仅在测试缺口时补测试）、`task-spaces/<run>/evidence/`、本节点报告 | 不改产品代码；不改/不新增探针源码；不改设计产物/需求/场景/门状态；不自行翻转状态；L2 失败不得静默 skip 或用 L1 冒充 |
| `T-1116-16` | `Tests/`（仅在测试缺口时补测试）、`task-spaces/<run>/evidence/`、本节点报告 | 不改产品代码；不改/不新增探针源码；不改设计产物/需求/场景/门状态；不自行翻转状态；不得只注入 `MailError` 冒充本地失败覆盖 |

共同约束：每个 change 一个实现 commit，message 带 `T-` 与 `SCN-`；规格实现进度行随实现 commit 只追加，若需改契约/形状/测试断言，回设计，不在任务里自行扩。越权清单按 `af-flow-rule` §4：改设计产物、自授权人工门、发布动作、出口外探针，发现即停手并在 `dev.md` 记「超出任务范围」。

并行关系：**本批无可并行任务**，`T-1116-11`→`T-1116-12`→`T-1116-13`→`T-1116-14`→`T-1116-15`→`T-1116-16` 为单链。理由：11 是人工门，未关闭前不得实现；13 直接消费 12 新增的 6 个 public 成员与 `performMarkRead` 归一化契约（共享公共契约必须串行）；14–16 的验证要在实现冻结后跑全量测试与回归，不在 `CMP-APP` 改动尚未落地时把部分树当验收；组件级 WIP=1 自然满足：同一时刻只有一个 `CMP-PRES` 或 `CMP-APP` 任务在飞。

**条件与回退**：P2 否决 D1–D8 任一项 → 回设计重评，`T-1116-11` 重新出结论，`T-1116-12`…`T-1116-16` 不复用本表边界硬做。确认收窄 D1/D2/D3/D5/D6/D7/D8 → 设计先同步规格与场景断言，再按收窄后的出口执行，任务号不变。D4 改工具栏顺序/形态 → 先由设计节点改 `SCN-0013`/`SCN-0014` 断言与 `CMP-APP` 增量，再开工并重估 `T-1116-13` 装载。若 12 发现必须改 `MailDomain`/`MailStore`/`Scenes`/`MailGateway` 契约或 schema，或 13 发现必须动 `MessageBodyStyle` 的 CSP/禁 JS/白底、新增 target/依赖 → 停下回设计，不在任务里扩；本批范围按 P2 处理，出现 P1 变更即停。若 L2 工具栏探针在生产源码上驱动不了，按 R37 先断言条目存在、settle 后点击；仍不可行时改为直接触发 `Actions` 闭包并在证据里登记限制，**不得**静默降级或用 L1 冒充 L2；若正文侧探针观察不到「无独立开关行」，回设计换 seam，不能拿源码删除冒充 L2。N7：12 的 L1 要覆盖所有选中入口经 `selectedListKey`，不以 `selection.messageID` 兼容 fallback 当远程重置路径。回退 = 回退本批 commit，纯 additive、无 schema/数据残留（N3）；若 `T-1116-13` 后需回退，先回退 13 再回退 12，保持 public 面与调用方一致；回退/重跑轮次不翻转状态位。

本批统一验证命令：`./Scripts/swiftw test`、`bash Scripts/check-architecture.sh`；单任务过滤用 `./Scripts/swiftw test --filter PresentationTests`；`RemoteContentToolbarProbe`/`ManualMarkReadProbe`/`RemoteContentBodyProbe` 的编译与复跑按 `SCN-0013`/`SCN-0014` §测试载体执行（生产源、900×560、`NSToolbar.items` + `window.sendEvent`），证据入 `task-spaces/<run>/evidence/`。

拆分复核（2026-11-16）：每个任务在「规格锚点」列指到组件规格或场景卡的具体段落；依赖无环（11→12→13→14→15→16）；出口含测试 ID/命令/证据位置与最低证据层级；已落本表。拆分过程与判据见 `task-spaces/20261116-223645/split.md`。

### 装载清单（2026-11-16 W-M3-06 拆分）

| 任务 | 必读 | 预计装载 | 备注 |
|---|---|---|---|
| `T-1116-11` | `design.md` §8.2；`CMP-PRES`/`CMP-APP` 增量；三张场景卡 §状态；`review.md` §3/§5；`history/decisions/` 格式参考 | ~500 行 | 人工确认；不代签 |
| `T-1116-12` | `CMP-PRES` §设计增量；`CMP-SCN-READ` §设计增量；`Sources/Presentation/MailboxViewModel.swift`、`MailboxDwell.swift`、`ErrorText.swift`；`Tests/PresentationTests/MailboxViewModelTests.swift`、`Support.swift` | ~1,100 行 | 单文件预算；非 `MailError` L1；`.seconds(3)` spy |
| `T-1116-13` | `CMP-APP` §设计增量；`MailboxView.swift`、`MessageBodyView.swift`、`MessageBodyStyle.swift`、`MailboxToolbar.swift`（新）；`SCN-0013`/`SCN-0014` §测试载体；设计探针源码 `evidence/toolbar-probe/` | ~1,500 行 | 生产源复跑；正文侧探针不省 |
| `T-1116-14` | `SCN-0008` §测试/§状态/§与相邻场景的边界；`SCN-0003`/`SCN-0004` 回归；测试与探针输出 | ~1,600 行 | 3 正 1 反，含 `.seconds(3)` |
| `T-1116-15` | `SCN-0013` §测试/§状态/§与相邻场景的边界；`SCN-0004`/`SCN-0010` 回归；探针输出 | ~1,800 行 | L1+L2；只建议翻转 |
| `T-1116-16` | `SCN-0014` §测试/§状态/§与相邻场景的边界；`SCN-0008`/`SCN-0004` 回归；探针输出 | ~1,800 行 | L1+L2；非 `MailError` 必须覆盖 |

装载纪律：单任务 ≤2,000 行；若实现时发现必须跨第二个组件/契约或装载超限，先停下按批次纪律重拆，不静默扩大。所有 change 另读 `doc/design/architecture.md` §2/§3 的相关段落（约 100 行）并核对依赖方向未变。


## W-M3-08 任务表（HTML 回复撰写）

来源：`REQ-0021`（`delivered`）、`SCN-0016`（`verified`）、`history/decisions/2026-11-17-html-compose.md`（D1–D8）、`design/components/{CMP-DOMAIN,CMP-STORE,CMP-OUT,CMP-SCN-COMPOSE,CMP-PRES,CMP-APP}/spec.md` §2026-11-17 增量。

**门已确认（2026-11-17，发起人对话）**：D1 `multipart/alternative`、D2 有改动二次确认、D3 回复/全部回复/转发/新邮件统一 HTML。D4–D8 为实现期默认，已登记在决策记录；P2 变更（public 可选字段、非核心表字段、跨模块 UI）按本记录放行。

| 任务 | 类型 | 组件 | 规格锚点 | 状态 | 出口 |
|---|---|---|---|---|---|
| `T-1117-20` | `design` | 0 | `REQ-0021`；`SCN-0016`；六份组件增量；决策记录 | 已完成 | 需求/场景/契约/决策落盘；P2 三项人工确认 + 五项默认登记 |
| `T-1117-21` | `change` | `CMP-DOMAIN` | `CMP-DOMAIN` §设计增量 | 已完成 | `Draft.bodyHTML`/`OutboxItem.bodyHTML` 可选默认 nil；既有构造/CLI 不回归；`./Scripts/swiftw test --filter ScenesTests` 绿 |
| `T-1117-22` | `change` | `CMP-STORE` | `CMP-STORE` §设计增量 | 已完成 | v10 `body_html`、enqueue/select/map、旧行 nil；pre-v9 fixture 可迁移；`--filter MigrationTests`/`OutboxTests` 绿 |
| `T-1117-23` | `change` | `CMP-OUT` | `CMP-OUT` §设计增量 | 已完成 | `multipart/alternative` 双段/base64/boundary；空白 HTML 回单段；`--filter OutboxTests` 绿 |
| `T-1117-24` | `change` | `CMP-SCN-COMPOSE` | `CMP-SCN-COMPOSE` §设计增量 | 已完成 | `quotedHeader`、`HTMLText.quotedEmail`/`plainText`/清洗；全宽无缩进；`--filter ScenesTests` 绿 |
| `T-1117-25` | `change` | `CMP-PRES` | `CMP-PRES` §设计增量 | 已完成 | `bodyHTML`/`editorDidLoad`/`setEditorHTML`/`hasEdits`、`ComposeDocument`、`quoteHeader`；`--filter PresentationTests` 绿 |
| `T-1117-26` | `change` | `CMP-APP` | `CMP-APP` §设计增量 | 已完成 | `ComposeView`/`ComposeEditor`/`ComposeFormatBar`、取消确认、`GeometryReader` 等宽；`./Scripts/swiftw build` 绿 |
| `T-1117-27` | `verify` | `SCN-0016` | `SCN-0016` §测试/§状态 | 已完成 | 3 正 1 反 L1 全绿；292 tests / 51 suites；架构 4 门；L2 UI 冒烟与 WebKit 探针登记；`SCN-0016` `verified`、`REQ-0021` `delivered` |

边界：`T-1117-21`…`26` 各自只改一个组件；`T-1117-27` 只补测试/证据，不改产品代码。回退 = 按提交反向回退；schema 为 additive，回退后旧行 `body_html` 列保留但代码不读，下一次正常迁移可继续；不删除用户邮件数据。

## 批次纪律

- 每个工序一次立一个 `works/` 目录；2026-11-14 起过程记录放工作区 `task-spaces/<run>/`，**任务表写在本文件对应工序节**，brief 只保留当次分析/范围，不维护第二份现行任务表；一个任务一个对话。
- 组件级 WIP=1：同一时刻只有一个在飞任务改同一组件。
- M1 未通过前不启动 M2；M2 与 M3 可并行但共享 CMP-SYNC，需错峰。
