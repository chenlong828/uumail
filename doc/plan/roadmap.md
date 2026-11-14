---
layer: plan
module: global
scope: project:uumail
status: current
updated: 2026-11-14
---

# 路线图

只记里程碑、工序与依赖。需求状态看 `requirements/`，设计真相看 `design/`。
首版范围已于 2026-11-09 确认：REQ-0001…0007 `accepted`（`history/decisions/2026-11-09-scope-baseline.md`）。2026-11-14 追加：REQ-0012「全部回复的收件人与抄送预填」`accepted`（W-M2-03，任务表见本文 §W-M2-03 任务表）。
工序目录名沿用历史 `works/YYYY-MM-DD-<短名>/`；2026-11-14 起过程记录放工作区 `task-spaces/<run>/`，**任务表作为项目排期的一部分落在本文件**，不再只存在于某次运行的 brief 里。

## 里程碑

| 里程碑 | 目标 | 出口判据 | 状态 |
|---|---|---|---|
| M0 协议探针 | 证明外网 EAS 通道可用，锁定线格式、设备身份与命令覆盖 | 命令行跑通 `OPTIONS → Provision → FolderSync → Sync → ItemOperations → SendMail`，实测状态码与能力矩阵成文 | 已完成（`history/works/2026-11-09-eas-probe/`） |
| M1 只读客户端 | 账号接入、文件夹树、列表、正文、附件、离线缓存 | 五个只读场景（SCN-0001…0005）全部 `verified` | 进行中：账号、文件夹树、列表、正文已通；附件 02–04 未实现；场景卡待转 `verified` |
| M2 发送与草稿 | Outbox、SendMail、回复/转发、草稿、Sent 镜像、全部回复 | send-message 场景 `verified`；离线发送可在联网后只发一次 | 进行中：Outbox 入队/冷投递/重试已实现；Sent 镜像与撰写附件未做；全部回复设计完成（`SCN-0007` `designed`），实现待启动；场景卡待 `verified` |
| M3 体验 | Ping、通知、本地搜索、错误恢复与空态 | 新邮件端到端 ≤ 60s 可见（Ping 或轮询）；搜索、通知场景 `verified` | 进行中：Ping 不支持 → 5 分钟轮询；搜索与通知已落地，场景卡待 `verified` |
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
| W-M2-03 全部回复与抄送预填 | M2 | W-M2-02；REQ-0012 `accepted` | CMP-EAS、CMP-DOMAIN、CMP-EASADAPTER、CMP-STORE、CMP-SCN-COMPOSE、CMP-PRES、CMP-APP | 设计完成：`SCN-0007` `designed`（2026-11-14）；`T-1114-02` 已证网关返回 `Cc` 并落地解析；其余 change 待 P1 确认后启动；任务表见本文 §W-M2-03 任务表 |
| W-M3-01 Ping 与通知 | M3 | W-M2-01 | CMP-SYNC、通知策略 | Ping 实测不支持 → 轮询；通知已落地（无过程记录，无独立场景卡） |
| W-M3-02 本地搜索 | M3 | W-M1-03 | CMP-STORE | 已实现（无过程记录，无独立场景卡）；FTS 不扫正文列 |
| W-SCN-REFACTOR 场景收口与分层重构 | M1/M2/M3 结构前置 | W-DOC-01、M4 结论 | 全仓 | 已完成（`history/works/2026-11-10-scene-refactor/`）：4 场景、9 库 + 2 可执行、159 测试、4 架构门 |

### W-SCN-REFACTOR 场景收口与分层重构（2026-11-14 完成）

结构收口已完成并归档（`history/works/2026-11-10-scene-refactor/`）。当前组件/target 状态：

- 9 个库 target（`MailDomain`、`MailStore`、`SyncEngine`、`Outbox`、`EASClient`、`EASAdapter`、`Scenes`、`Presentation`、`Composition`）+ 2 个可执行 target（`uumail`、`uumailctl`）；`AppServices` 退役。
- 4 个场景类收口每条业务流：`AccountSetupScene`、`SyncScene`、`ReadScene`、`ComposeScene`；视图只绑定薄视图模型。
- 发信改为「入队即返回 + `Outbox` 冷投递」；outbox schema v8（租约 + 退避 + 显式状态）。
- 最终验证：159 tests / 37 suites 全绿；`Scripts/check-architecture.sh` 4 门全过；`AppComposition` 180 行。

结构收口**不等于功能里程碑完成**：M1/M2/M3 的出口仍看场景卡 `verified`。当前仍缺：真机冒烟（`uumailctl diagnose/sync/send`、App live bootstrap）、附件 25MB/续传/名称回退、已读回写、Sent 镜像、outbox UI 角标、`PendingOps`。

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

来源：`REQ-0012`（`accepted`）、`SCN-0007`（`designed`）、`design/components/CMP-*` 设计增量。设计冻结于 2026-11-14，实现须先过 P1 人工确认门。

| 任务 | 类型 | 组件 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|
| `T-1114-01` | `design` | SCN-0007（0 组件） | — | 已完成（2026-11-14） | 场景卡四元素齐、3 正 1 反可执行、转 `designed` |
| `T-1114-02` | `change` | `CMP-EAS` | T-1114-01 | 已完成（2026-11-14） | Sync 信封 `Cc` 解析 + fixture 测试；真机样本已证网关返回，未触发停止分支 |
| `T-1114-03` | `change` | `CMP-DOMAIN` | T-1114-01 | 待启动 | `Message.cc` 可选字段 + 值类型测试 |
| `T-1114-04` | `change` | `CMP-EASADAPTER` | T-1114-02、T-1114-03 | 待启动 | `EASMessage.cc → Message.cc` 映射 + 测试 |
| `T-1114-05` | `change` | `CMP-STORE` | T-1114-03 | 待启动 | schema v9 `cc` 列、读写、历史回填、迁移测试 |
| `T-1114-06` | `change` | `CMP-SCN-COMPOSE` | T-1114-01、T-1114-03 | 待启动 | `replyAllSeed` + 地址解析/去重/排除自己 + 组件测试 |
| `T-1114-07` | `change` | `CMP-PRES` | T-1114-06 | 待启动 | `Mode.replyAll`、`composeReplyAll`、视图模型测试 |
| `T-1114-08` | `change` | `CMP-APP` | T-1114-07 | 待启动 | 工具栏「全部回复」按钮，视图不拼地址 |
| `T-1114-09` | `verify` | SCN-0007 / REQ-0012 | 全部 | 待启动 | 3+1 绿、`SCN-0006` 回归、架构门过、`verified`/`delivered` |

并行关系：`T-1114-02` 与 `T-1114-03` 可并行；之后 `T-1114-04`、`T-1114-05`、`T-1114-06` 分属三个组件可并行。

## 批次纪律

- 每个工序一次立一个 `works/` 目录，任务表写在 `brief.md`；一个任务一个对话。
- 组件级 WIP=1：同一时刻只有一个在飞任务改同一组件。
- M1 未通过前不启动 M2；M2 与 M3 可并行但共享 CMP-SYNC，需错峰。
