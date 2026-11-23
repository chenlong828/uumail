---
layer: plan
module: global
scope: project:uumail
status: current
updated: 2026-11-21
---

# 路线图

只记里程碑、工序与依赖。需求状态看 `requirements/`，设计真相看 `design/`。
首版范围已于 2026-11-09 确认：REQ-0001…0007 `accepted`（`history/decisions/2026-11-09-scope-baseline.md`）。2026-11-14 追加并交付：REQ-0012「全部回复的收件人与抄送预填」`delivered`（W-M2-03，任务表见本文 §W-M2-03 任务表）。2026-11-14 追加需求分析并纳入 W-M3-03：REQ-0013「列表停留自动已读」与 REQ-0014「列表键盘删除」已于 2026-11-15 交付（`SCN-0008`/`SCN-0009` `verified`、两需求 `delivered`）；设计已完成（P1 已确认并归档），任务拆分复核完成（2026-11-14），任务表见本文 §W-M3-03 任务表。2026-11-16 追加 W-M3-04 并完成交付：REQ-0015「深色阅读白底」与 REQ-0016「菜单主题切换」`delivered`；Q5/Q6/P2 已于 2026-11-16 确认（`history/decisions/2026-11-16-theme-appearance.md`），`SCN-0010`/`SCN-0011` 已由 `designed` 转 `verified`，`T-1116-01`…`T-1116-06` 已完成；任务表见 §W-M3-04。2026-11-16 追加 W-M3-05 并完成交付：REQ-0017「阅读页信封头」`delivered`、`SCN-0012` `verified`；P2（D1–D8）已于 2026-11-16 确认（`history/decisions/2026-11-16-reading-pane-headers.md`），`T-1116-07`…`T-1116-10` 已完成；任务表见 §W-M3-05。2026-11-16 另立 W-M3-06（远程图片开关并入工具栏、手动标记已读、自动已读 10→3 秒）：`REQ-0018`/`REQ-0019` `accepted`、`REQ-0013` 重开 `accepted`，`SCN-0013`/`SCN-0014`/`SCN-0008` 均 `designed`；P2（D1–D8）已于 2026-11-16 确认（`history/decisions/2026-11-16-remote-toolbar-mark-read.md`），`T-1116-11`…`T-1116-16` 于 2026-11-17 全部完成；`SCN-0008`/`SCN-0013`/`SCN-0014` 已转 `verified`、`REQ-0013`/`REQ-0018`/`REQ-0019` 已转 `delivered`（`task-spaces/20261117-064420/review.md` §7）；任务表见 §W-M3-06。2026-11-17 的 W-M3-07（界面与阅读字体大小可调）已完成交付：`REQ-0020` `delivered`、`SCN-0015` `verified`；实现提交 `2c2b1a2` + 评审回退修复 `d958da9`，`T-SCN-0015-01..04`（3 正 1 反）L1 6/6、L2 342/0、全量 275 tests / 50 suites、架构 4/4（`task-spaces/20261117-095147/review.md` §8/§12）；任务号 `T-1117-01` 为无人值守默认决策（未经人工），task-split 未产出独立任务表。2026-11-18 的 W-M3-09（撰写页收件人输入联想补全）已完成交付：`REQ-0022` `delivered`、`SCN-0017` `verified`；实现提交 `0682d4c` + 测试 `d0deaee`/`5133f5c`，`T-SCN-0017-01..04`（3 正 1 反）L1（全量 327 tests / 54 suites）、L2 56/0、架构 4/4（`task-spaces/20261118-190035/review.md` §F）；任务号 `T-1118-02` 为无人值守默认决策（未经人工），task-split 未产出独立任务表。2026-11-19 另立 W-M3-10（收件人候选行显示名宽度）：`REQ-0023` `accepted`、`SCN-0017` 已转回 `designed`，第 2 轮设计评审 **pass**（`task-spaces/20261119-164437/review2.md`，B1–B3 关闭、N1–N5 非阻塞），P3 默认确认（未经人工，`design2.md` §6.2）；任务表 `T-1119-01`…`T-1119-03` 已建（拆分记录 `task-spaces/20261119-164437/split.md`，排期提交追踪号 `T-1119-00`，不代表任务表编号）；2026-11-19 实现 `13c23fd` + 措辞 `e6a183f`，实现鉴定第 4 轮 **pass**（`task-spaces/20261119-164437/review4.md` §7）：`SCN-0017` 转 `verified`、`REQ-0023` 转 `delivered`、`T-1119-01`…`T-1119-03` 完成，W-M3-10 完成。2026-11-19 另立 W-M3-11（远程图片放行后的实际加载：运行载体 ATS 例外）：`REQ-0024` `accepted`、`SCN-0018` `designed`，设计评审 **pass**（`task-spaces/20261119-213812/review.md`，B1–B5 非阻塞），ATS 例外已**人工确认**（pass，仅加 `NSAllowsArbitraryLoadsInWebContent=true`；`doc/history/decisions/2026-11-19-remote-image-ats.md`）；任务表 `T-1119-04`/`T-1119-05` 已建（拆分记录 `task-spaces/20261119-213812/split.md`）；2026-11-19 实现 `1b86282`，实现鉴定第 4 轮 **pass**（`task-spaces/20261119-213812/review4.md` §8）：`SCN-0018` 转 `verified`、`REQ-0024` 转 `delivered`、`T-1119-04`/`T-1119-05` 完成，W-M3-11 完成；A5 真实样本冒烟仍为发布前/人工项。2026-11-20 另立 W-M3-12（HTML 正文内联图片 `cid:` 渲染）：`REQ-0025` `accepted`、`SCN-0019` `designed`，设计第 2 轮评审 **pass**（`task-spaces/20261120-111818/review2.md`，B1/B2 关闭、N1–N6 处置通过），两个 P2 additive public 面已**人工确认 pass（A）**（`doc/history/decisions/2026-11-20-inline-image-render-public-surface.md`）；任务表 `T-1120-01`…`T-1120-05` 已建（拆分记录 `task-spaces/20261120-111818/split.md`）；已完成（2026-11-20）：实现 `e848b4b`/`a61fb1b`/`c41a9db`/`72f7da1`/`97fcbec`，`T-SCN-0019-01..04`（3 正 1 反）L1+L2 全 PASS，`SCN-0019` 转 `verified`、`REQ-0025` 转 `delivered`、`T-1120-01`…`T-1120-05` 完成，W-M3-12 完成（`task-spaces/20261120-111818/review5.md` §7）；A5 真实样本冒烟仍为发布前/人工项。2026-11-20 另立并完成 W-M3-13（附件取用交互：双击打开/右键另存为）：`REQ-0026` 转 `delivered`、`SCN-0020` 转 `verified`，`T-1120-06`…`T-1120-11` 完成；实现 `220cb21`/`eeadf19`/`d932a5e`/`1d19514`/`5a4cdee`/`92c9bfc`/`3eb3e9b`，`T-SCN-0020-01..10`（3 正 1 反 + 回归/接线/质量）L1 `360/58`、L2 `83 PASS`、架构 4/4（`task-spaces/20261120-160446/test.md`/`test2.md`/`review7.md` §8）。真实右键/Control-单击、`NSSavePanel`、VoiceOver、像素级视觉验收、元素级联动与 A5 真样本冒烟仍为发布前/人工项。2026-11-21 W-M3-14（内联图片 ContentId 持久化，P1）已完成：`attachments` v11 + `Attachment.contentID` + `EASClient` 解析 `ContentId` + `InlineImageHTML.matches` 优先匹配，`T-1121-02`…`T-1121-06` 完成、`SCN-0019` 转回 `verified`、`REQ-0025` 重新交付（任务表见 §W-M3-14）。同日修复附件下载（`T-1121-01`）：`CMP-EAS.fetchAttachment` 改读 `Response/Fetch/Properties/Data`（真机取证，此前所有附件都抛 `malformedResponse`），附件请求资源预算 120s→600s（28.7MB 实测 181.55s），25MB 上限按用户决定暂缓；证据 `history/works/2026-11-21-attachment-fetch/`。2026-11-21 另增开发环境凭据文件（`T-1121-07`）：启动优先读 `~/.uumail.env`、菜单「开发 → 保存凭据到 ~/.uumail.env」显式导出（0600、明文），避免 ad-hoc 重签名后每次启动都弹钥匙串授权；决策 `history/decisions/2026-11-21-dev-dotenv-credentials.md`。
工序目录名沿用历史 `works/YYYY-MM-DD-<短名>/`；2026-11-14 起过程记录放工作区 `task-spaces/<run>/`，**任务表作为项目排期的一部分落在本文件**，不再只存在于某次运行的 brief 里。

## 里程碑

| 里程碑 | 目标 | 出口判据 | 状态 |
|---|---|---|---|
| M0 协议探针 | 证明外网 EAS 通道可用，锁定线格式、设备身份与命令覆盖 | 命令行跑通 `OPTIONS → Provision → FolderSync → Sync → ItemOperations → SendMail`，实测状态码与能力矩阵成文 | 已完成（`history/works/2026-11-09-eas-probe/`） |
| M1 只读客户端 | 账号接入、文件夹树、列表、正文、附件、离线缓存 | 五个只读场景（SCN-0001…0005）全部 `verified` | 进行中：账号、文件夹树、列表、正文已通；附件 02–04 未实现；场景卡待转 `verified` |
| M2 发送与草稿 | Outbox、SendMail、回复/转发、草稿、Sent 镜像、全部回复 | send-message 场景 `verified`；离线发送可在联网后只发一次 | 进行中：Outbox 入队/冷投递/重试已实现；Sent 镜像与撰写附件未做；全部回复 `SCN-0007` `verified`（2026-11-14，T-1114-09，含真机 UI 冒烟），REQ-0012 `delivered`；其余场景卡待 `verified` |
| M3 体验 | Ping、通知、本地搜索、错误恢复与空态 | 新邮件端到端 ≤ 60s 可见（Ping 或轮询）；搜索、通知场景 `verified`；W-M3-03 的 `SCN-0008`/`SCN-0009` `verified` | 进行中：Ping 不支持 → 5 分钟轮询；搜索与通知已落地，场景卡待 `verified`；W-M3-03 已交付（2026-11-15，T-1114-19/20 验证）：`SCN-0008`/`SCN-0009` `verified`、REQ-0013/REQ-0014 `delivered`；P1 frozen 记录与 R16 真机证据已归档；W-M3-05（阅读页信封头）已完成（2026-11-16）：`SCN-0012` `verified`、REQ-0017 `delivered`，`T-1116-07`…`T-1116-10` 完成；W-M3-06（远程开关/手动置读/3 秒）已完成（2026-11-17）：`SCN-0008`/`SCN-0013`/`SCN-0014` `verified`、`REQ-0013`/`REQ-0018`/`REQ-0019` `delivered`，`T-1116-11`…`T-1116-16` 完成；W-M3-07（界面/阅读字号）已完成（2026-11-17）：`SCN-0015` `verified`、`REQ-0020` `delivered`，`T-1117-01`（默认号，未经人工）完成；W-M3-09（撰写页收件人联想）已完成（2026-11-18）：`SCN-0017` `verified`、`REQ-0022` `delivered`，`T-1118-02`（默认号，未经人工）完成；W-M3-10（候选行显示名宽度）已完成（2026-11-19）：`SCN-0017` `verified`、`REQ-0023` `delivered`，`T-1119-01`…`T-1119-03` 完成（`task-spaces/20261119-164437/review4.md` §7）；W-M3-11（远程图片实际加载）已完成（2026-11-19）：`SCN-0018` `verified`、`REQ-0024` `delivered`，`T-1119-04`/`T-1119-05` 完成（`task-spaces/20261119-213812/review4.md` §8）；A5 发布前人工冒烟仍待办；W-M3-12（内联图片 `cid:` 渲染）已完成（2026-11-20）：`SCN-0019` `verified`、`REQ-0025` `delivered`，`T-1120-01`…`T-1120-05` 完成（`task-spaces/20261120-111818/review5.md` §7）；A5 发布前人工冒烟仍待办（任务表见 §W-M3-12）；W-M3-13（附件取用交互）已完成（2026-11-20）：`SCN-0020` `verified`、`REQ-0026` `delivered`，`T-1120-06`…`T-1120-11` 完成（`task-spaces/20261120-160446/review7.md` §8）；真实右键/`NSSavePanel`/VoiceOver/像素/元素级联动与 A5 冒烟仍待人工（任务表见 §W-M3-13） |
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
| W-M3-09 收件人输入联想补全 | M3 | W-M3-08；REQ-0022 `delivered`；SCN-0017 `verified`；P1 默认确认（未经人工，`history/decisions/2026-11-18-recipient-autocomplete.md`） | CMP-DOMAIN、CMP-SCN-COMPOSE、CMP-PRES、CMP-APP | 已完成（2026-11-18）：设计完成（2026-11-18）后实现 `0682d4c` + 测试 `d0deaee`/`5133f5c`；`T-SCN-0017-01..04`（3 正 1 反）T-01/02/04 L1、T-03 L2 `56 PASS / 0 FAIL`；全量 `327 tests / 54 suites`、依赖场景定向 `91 tests / 11 suites`、架构 4/4；`SCN-0017` 转 `verified`、`REQ-0022` 转 `delivered`（`task-spaces/20261118-190035/review.md` §F）；`T-1118-02` 为无人值守默认任务号（未经人工），task-split 未产出独立任务表 |
| W-M3-10 收件人候选行显示名宽度 | M3 | W-M3-09；REQ-0023 `delivered`；SCN-0017 `verified`；设计 `task-spaces/20261119-164437/design2.md`（第 2 轮，评审 pass）；P3 默认确认（未经人工，`design2.md` §6.2） | CMP-APP | 已完成（2026-11-19）：实现 `13c23fd` + 措辞 `e6a183f`；生产源 L2 主探针 147/0（20/21 次；干净重跑与记录逐字节一致，1/21 次仅 N9 环境断言）+ 补充 16/16、全量 327/54、依赖回归 72/7、架构 4/4；`SCN-0017` 转 `verified`、`REQ-0023` 转 `delivered`（`task-spaces/20261119-164437/review4.md` §7）。任务表见本文 §W-M3-10 任务表 |
| W-M3-11 远程图片实际加载（运行载体 ATS 例外） | M3 | W-M3-06；REQ-0024 `delivered`；SCN-0018 `verified`；设计 `task-spaces/20261119-213812/design.md`（评审 pass）；ATS 例外人工确认（2026-11-19 pass，`history/decisions/2026-11-19-remote-image-ats.md`） | CMP-APP（运行载体：`Resources/Info.plist` + `Scripts/make-app.sh`） | 已完成（2026-11-19）：实现 `1b86282`（`Resources/Info.plist` + `Scripts/make-app.sh` 单一来源）；`T-1119-04`/`T-1119-05` 完成；`T-SCN-0018-01..03` L1+L2 全 PASS（动态开→关、无 ATS 负控制、`data:` 正控制、URLSession 仍受限），独立复跑与快照哈希一致；全量 327/54、架构 4/4（`test.md`/`test2.md`/`review4.md`）；`SCN-0018` 转 `verified`、`REQ-0024` 转 `delivered`；A5 发布前人工冒烟仍待办。任务表见本文 §W-M3-11 任务表 |
| W-M3-12 HTML 正文内联图片（`cid:`）渲染 | M3 | W-M1-04；REQ-0025 `delivered`；SCN-0019 `verified`；设计 `task-spaces/20261120-111818/design2.md`（第 2 轮，`review2.md` **pass**）；两个 P2 additive public 面人工确认 A（2026-11-20，`history/decisions/2026-11-20-inline-image-render-public-surface.md`） | CMP-SCN-READ、CMP-PRES、CMP-APP | 已完成（2026-11-20）：实现 `e848b4b`/`a61fb1b`/`c41a9db`/`72f7da1`/`97fcbec`；`T-SCN-0019-01..04`（3 正 1 反）L1+L2 全 PASS，全量 347/57、架构 4/4、六场景回归不退化；`SCN-0019`→`verified`、`REQ-0025`→`delivered`（`task-spaces/20261120-111818/review5.md` §7）。任务表见本文 §W-M3-12 |
| W-M3-13 附件取用交互（双击打开、右键另存为） | M3 | W-M1-04；REQ-0026 `delivered`；SCN-0020 `verified`；设计 `task-spaces/20261120-160446/design3.md`（第 3 轮，`review3.md` **pass**）；G1 public 面人工确认 A（2026-11-20，`history/decisions/2026-11-20-attachment-error-surface.md`） | CMP-PRES、CMP-APP | 已完成（2026-11-20）：实现 `220cb21`…`3eb3e9b`（7 commit）；`T-SCN-0020-01..10`（3 正 1 反）L1 `360/58`、L2 `83 PASS`、架构 4/4；`SCN-0020`→`verified`、`REQ-0026`→`delivered`（`task-spaces/20261120-160446/review7.md` §8）；`Scenes`/`Composition`/`MailDomain`/`MailStore`/`Package.swift` 零改动；真实右键/`NSSavePanel`/VoiceOver/像素/元素级联动与 A5 冒烟仍为发布前/人工项。任务表见本文 §W-M3-13 |
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

共同约束：每个 change 一个实现 commit，message 带 `T-` 与 `SCN-`；L2 探针文件名/组合由实现按 `commands.md` 落定（出口以用例 ID 与生产源断言为准，不得删/放宽断言）；规格实现进度行随实现 commit 只追加，若需改契约/形状/测试断言，回设计，不在任务里自行扩。越权清单按 `af-flow-rule` §4：改设计产物、自授权人工门、发布动作、出口外探针，发现即停手并在 `dev.md` 记「超出任务范围」。

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

共同约束：每个 change 一个实现 commit，message 带 `T-` 与 `SCN-`；L2 探针文件名/组合由实现按 `commands.md` 落定（出口以用例 ID 与生产源断言为准，不得删/放宽断言）；规格实现进度行随实现 commit 只追加，若需改契约/形状/测试断言，回设计，不在任务里自行扩。越权清单按 `af-flow-rule` §4：改设计产物、自授权人工门、发布动作、出口外探针，发现即停手并在 `dev.md` 记「超出任务范围」。

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

## W-M3-09 设计状态（收件人输入联想补全，2026-11-18）

来源：`REQ-0022`（`delivered`）、`SCN-0017`（`verified`）、`history/decisions/2026-11-18-recipient-autocomplete.md`（D1–D10，P1 默认确认，未经人工）、`history/decisions/2026-11-18-recipient-autocomplete-design-addendum.md`（A1–A6 复核增补，默认确认，未经人工）、`design/components/{CMP-DOMAIN,CMP-STORE,CMP-SCN-COMPOSE,CMP-PRES,CMP-APP}/spec.md` §2026-11-18 增量。

设计结论：**会话内聚合**，首次聚焦经 `ComposeScene.recipientDirectory(account:)` 读一次本地已收信封（每文件夹 500、总计 5,000 封上限），`ComposeViewModel` 缓存；不建 `contacts` 表、不改 `MailStore`/schema（store 既有 1008/1000 超出登记 R45，本批新增 0 行）；`MailDomain` 新增 `ContactAddress`/`ContactEnvelope`/`ContactDirectory`/`RecipientText`；`ComposeViewModel` 新增候选/焦点/键盘/选中 public 面；`uumail` 新增 `RecipientTextField`/`RecipientSuggestionList` 与独立 `RecipientForm.swift` 的 `ComposeRecipientForm`，候选浮层用 `.overlay` 不参与布局，不改变 sheet 宽高。

方案设计复核（2026-11-18，run `20261118-082503`）：把原 `ZStack` 浮层改为 `.overlay` + `.zIndex(10)`（设计探针证 ZStack 会把 200pt 浮层计入布局并下推内容）；`ComposeRecipientForm` 从 `ComposeView.swift` 拆到 `RecipientForm.swift` 以便 L2 探针只编译控件文件；`RecipientTextField` 按实测 SwiftUI `TextField` 拟合（无边框、`textBackgroundColor`、13pt、4pt inset、24pt 行高）并随字号档缩放；读取加 5,000 总计上限；click-after-focus-loss 与 IME Esc 写入 L2 断言。细节见 `task-spaces/20261118-082503/design.md`、`CMP-APP`/`CMP-SCN-COMPOSE`/`CMP-PRES` 增量与 R47–R49。

**待 `task-split`**：按组件与场景拆任务（`CMP-DOMAIN` → `CMP-SCN-COMPOSE` → `CMP-PRES` → `CMP-APP` → `verify`），一个 task 一件事，不改本设计边界；任务号、依赖、装载清单、出口由该节点补入本节。本设计不预分配任务号，也不代替 `task-split` 决策。设计提交使用 `T-1118-01` 作为**默认设计任务号（未经人工）**，只用于 commit 可追溯，不代表任务表编号。

**实现与验证（2026-11-18，run `20261118-190035`）**：实现 `0682d4c`（10 个 `Sources/` 文件）+ 测试 `d0deaee`/`5133f5c`（6 个 `Tests/` 文件，生产源未变）；`T-SCN-0017-01..04`（3 正 1 反）通过（T-01/02/04 L1；T-03 L2 `56 PASS / 0 FAIL`）；全量 `327 tests / 54 suites`、依赖场景定向 `91 tests / 11 suites`、架构 4/4；`SCN-0017` 转 `verified`、`REQ-0022` 转 `delivered`（`task-spaces/20261118-190035/review.md` §F）。**`task-split` 欠账保留**：`T-1118-02` 为无人值守默认任务号（未经人工），未建独立任务表；本节不补任务表，也不把 `T-1118-02` 写成有序任务卡。

## W-M3-10 任务表（收件人候选行显示名宽度）

来源：`REQ-0023`（`delivered`）、`SCN-0017`（`verified`；2026-11-19 因显示宽度增量从 `verified` 转回 `designed`，完成重验后转回 `verified`）、`task-spaces/20261119-164437/design2.md`（第 2 轮设计）、`task-spaces/20261119-164437/review2.md`（**pass**；B1–B3 关闭、N1–N5 非阻塞建议）、`doc/design/components/CMP-APP/spec.md` §设计增量：候选行显示名的可读宽度（`:243-253`）、`doc/design/architecture.md` §1 收件人输入联想行（`:38`）、拆分记录 `task-spaces/20261119-164437/split.md`。

**设计边界（不改）**：A 族「行内列宽重分配 + 地址显式缩短」；`horizontalInset=8`、`gap=6`、`preferredAddressFloor=130`、`representativeNameCharacters=15`；`addressMinimum = ceil(width(地址首字符 + "…@" + 域名首字符))`；有名字 `name=min(intrinsic, available−6−addressFloor)`、`address=available−6−name`；无名字 `address=available`；完整地址保留在 `fullAddress`，`.help`/无障碍/选中仍用完整地址。P3，默认确认 D1–D6（未经人工，`design2.md` §6.2）。本表只拆任务，不改设计决定、不改 `REQ-0023` 口径。

**探针源码缺口（装载前必读）**：2026-11-18 验证轮的 `ComposeAutocompleteProbe` 源码在已归档的 `task-spaces/20261118-190035/`，当前工作区不可读、仓库内无副本。`T-1119-01` 必须以本轮 `task-spaces/20261119-164437/evidence/name-width-probe/round2/NameWidthProbe2.swift`（311 行，已覆盖显示宽度）为基座重建 `ComposeAutocompleteProbe`，按 `SCN-0017` `T-SCN-0017-03` 的 11 个可执行 ID 复建断言，**不得只跑显示宽度子集**。若 4 项交互断言（`candidateRowsAndFallback`/`fieldBaselineAndNoLayoutShift`/`clickAfterFocusLoss`/`imeEscKeepsComposition`）在预算内无法复建，停下按批次纪律重拆或回设计改 T-03 的测试载体，**不得**静默删断言或以 L1 冒充 L2。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1119-01` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：候选行显示名的可读宽度（`:243-253`）；`design2.md` §4.1–§4.3/§5/§7.1；`SCN-0017` 第 5 步（`:44`）与 `T-SCN-0017-03`（`:89`） | —（与 `T-1119-02` 可并行） | 已完成（2026-11-19） | 按 `design2.md` §4.2/§4.3 在 `Sources/uumail/RecipientTextField.swift` 增加 internal `RecipientSuggestionLayout`（列宽 + 地址缩短纯函数），并让 `RecipientTextField+AppKit.swift#SuggestionRowView.layout()` 只用其返回的 `name`/`address`；`nameLabel`/`addressLabel` 改 internal；`configure` 保存 `fullAddress`，`addressLabel.stringValue` 写缩短串，完整地址仍供 `.help`/无障碍/选中；缩短结果按 `(地址, 宽, 字号)` 缓存。出口：`./Scripts/swiftw build` + `./Scripts/swiftw test` + `bash Scripts/check-architecture.sh` 4 门绿；以**生产源**（`Sources/uumail/RecipientTextField.swift` + `RecipientTextField+AppKit.swift` + `RecipientForm.swift`，不用 `patched/` 副本）重建 `ComposeAutocompleteProbe`，全 `PASS/0 FAIL` 并覆盖 `T-SCN-0017-03` 的 11 个可执行 ID（交互 4 项 + 显示宽度 7 项）；逐项含 100%×480/700/900、40 字名 130pt、145%×480（名字 ≥280.5、邮箱 ≥104）、175%×480（名字 ≥325 完整、不降级）、225%×480（行宽 392、行高 54、名字 ≥290、邮箱 ≥72）、无名字按 `row.nameLabel`/`row.addressLabel` 身份、`addressLabel.intrinsicContentSize.width <= frame.width + 0.5`、`fullAddress`/`.help` 保留；`columnWidthsEdgeClamp` **直接调** `RecipientSuggestionLayout.widths` 覆盖无名字、超窄（`available < addressMinimum + gap`）、100% 的 130 保底、175% 取满、225% 的 `addressMinimum` 边界；探针源码/命令/原始输出入 `evidence/compose-autocomplete-probe/`；补 bench 输出（N4）后，CMP-APP 增量保留并引用 0.6ms 或改为「有界 O(L²)+缓存」；文件预算 `RecipientTextField.swift` ≤300、`RecipientTextField+AppKit.swift` ≤300，不新增文件/target/依赖，`Package.swift` 不动；diff 仅允许范围内的文件；commit 带 `T-1119-01` 与 `SCN-0017`；不改状态位。`L2（无头探针）+ L1（构建/既有单测）` |
| `T-1119-02` | `change` | `SCN-0017`（0 组件） | `SCN-0017` 第 5 步（`:44`）与 `T-SCN-0017-03`（`:89`）；`design2.md` §4.4/§7.1；`review2.md` §7 N1/N3/N5 | —（与 `T-1119-01` 可并行，文件不重叠） | 已完成（2026-11-19） | 只做已定稿设计的措辞对齐（引用 `design2.md` §4.4/§7.1 与 `review2.md` §7，不新增/改选设计决定）：第 5 步「行宽 = 浮层宽 = `max(字段宽, 200)`」改为「行宽 = 行 bounds 宽；225% 滚动条占 17pt 时为 392；100%×480 可用宽 393、225% 为 376」；`T-SCN-0017-03` 的 225% 名字「约 10.4 字」改为「约 10.7 字（实测 298）」；145%/175% 的「480/700/900 都完整」收窄为「480 实测，700/900 由公式/实现回归覆盖」。不改任何阈值（280.5/325/290/130/104/58/72）、证据层级、T-03 断言集合与卡状态；`git diff` 只含这两处；commit 带 `T-1119-02` 与 `SCN-0017`；`SCN-0017` 仍 `designed`。`文档核对（不计 L1–L4；非行为/渲染断言，出口是可 diff 的锚点一致性与数值对照）` |
| `T-1119-03` | `verify` | `SCN-0017`（0 组件） | `SCN-0017` §测试（`:83-90`）/§状态（`:110-116`）/§与相邻场景的边界（`:100-108`）；`CMP-APP` 增量（`:243-253`）；`architecture.md` §1 收件人输入联想（`:38`） | `T-1119-01`、`T-1119-02` | 已完成（2026-11-19） | 在实现与文档冻结后独立复验，不复用 `T-1119-01` 的产物：干净 `./Scripts/swiftw build` 后用生产源重编 `ComposeAutocompleteProbe`，按 `T-SCN-0017-03` **逐可执行 ID**（11 项）记录 PASS/FAIL，不只报总数；覆盖 100%/145%/175%/225%×480、100%×700/900、无名字身份、`@` 两侧与二次截断、`fullAddress`/`.help`；`T-SCN-0017-01/02/04` L1 全绿；`./Scripts/swiftw test` 全量（基线 `327 tests / 54 suites`，不得新增失败）与 `bash Scripts/check-architecture.sh` 4 门；`SCN-0006`/`SCN-0007`/`SCN-0015`/`SCN-0016` 回归不退化；证据入 `evidence/compose-autocomplete-probe/verify/`；只建议翻转 `SCN-0017`→`verified`、`REQ-0023`→`delivered`、`T-1119-01..03` 完成，不自行改状态位；不改产品代码/探针断言/设计文档；失败就记录并退回 `T-1119-01`，不得降级或跳过。`L1（单元测试）+ L2（无头探针）` |

**完成（2026-11-19，收口）**：`T-1119-01`/`T-1119-02` 分别由 `13c23fd`/`e6a183f` 落地，`T-1119-03` 由 `test.md` 与 `review4.md` 的独立复跑覆盖；`T-SCN-0017-01..04` 逐例有结果，验证证据见 `task-spaces/20261119-164437/test.md` §10、`review4.md` §2–§3、`evidence/verify/`、`evidence/verify-accept/`。收尾按 `review4.md` §7 翻转 `SCN-0017`→`verified`、`REQ-0023`→`delivered`、三任务与 W-M3-10 完成；N2/N5/N6/N8/N9/N10/N11 仍为非阻塞残余。

任务边界（每个任务卡的可执行边界）：

| 任务 | 允许改的范围 | 明确不做 |
|---|---|---|
| `T-1119-01` | `Sources/uumail/RecipientTextField.swift`、`Sources/uumail/RecipientTextField+AppKit.swift`、`CMP-APP` 增量实现进度行（只追加；N4 的 0.6ms 措辞按结果修正，不改规则/数值/验收）、`task-spaces/<run>/`（含 `dev.md` 与 `evidence/compose-autocomplete-probe/`） | 不改 `RecipientForm.swift`/`panelSize`、`ComposeView.swift`、`SuggestionRowView.sizeThatFits`、`.help`/无障碍/选中语义、行高/浮层宽高/sheet 宽高；不改 `Presentation`/`Scenes`/`MailDomain`/`MailStore`/`Outbox`/`SyncEngine`/schema；不改 `Package.swift`、不新增 target/依赖/文件；不新增 `Tests/` L1（设计 D5）；不改 `SCN-0017`/`REQ-0023`/`architecture.md`/`roadmap` 的状态或断言；不做 L3 截图/OCR 或 L4 AX |
| `T-1119-02` | `doc/design/scenarios/mail/send/recipient-autocomplete/scenario.md`（仅第 5 步 `:44` 与 `T-SCN-0017-03` `:89` 的措辞）、`task-spaces/<run>/` | 不改任何阈值/断言门槛/证据层级/卡状态；不改 `CMP-APP`/`architecture.md`/需求卡/决策记录/roadmap；不改 `design2.md`/`review.md`（上一轮过程记录）；不改源码/测试/探针；若措辞对齐需要改设计决定，停手回设计 |
| `T-1119-03` | `Tests/`（仅在发现测试缺口时补测试，独立测试 commit）、`task-spaces/<run>/evidence/compose-autocomplete-probe/verify/`、本节点报告 | 不改产品代码；不改/不新增探针断言；不改设计产物/需求/场景/门状态；不自行翻转 `verified`/`delivered`/任务完成；L2 失败不得静默 skip、降级或用 L1 冒充 |

共同约束：每个 change 一个实现 commit，message 带 `T-` 与 `SCN-`；L2 探针文件名/组合由实现按 `commands.md` 落定（出口以用例 ID 与生产源断言为准，不得删/放宽断言）；规格实现进度行随实现 commit 只追加，若需改契约/形状/测试断言，回设计，不在任务里自行扩。越权清单按 `af-flow-rule` §4：改设计产物（`T-1119-02` 仅限已定稿措辞）、自授权人工门、发布动作、出口外探针，发现即停手并在 `dev.md` 记「超出任务范围」。

并行关系：`T-1119-01`（`CMP-APP` 两个源文件）与 `T-1119-02`（`SCN-0017` 两处措辞）无共享文件/契约，可并行；`T-1119-03` 依赖两者冻结后独立复验，不跳步。组件级 WIP=1 自然满足：同批只有 `T-1119-01` 一个 `CMP-APP` 任务在飞；`T-1119-02` 不触碰组件代码，不构成第二个 `CMP-APP` 任务。`T-1119-03` 不并行改 `CMP-APP`。

**条件与回退**：若 `T-1119-01` 发现必须改 `RecipientForm.swift`/`panelSize`/`sizeThatFits`/浮层宽高或 sheet 宽高 → 停下回设计（B/C 族问题），不在任务里扩；若必须把 helper 公开或下沉到 `Presentation` 才能做 L1 → 停下回设计（D5 契约代价），不静默改层级；若 175%×480 生产源实测名字 <325 → 按 B2 回归处理，退回设计，不放宽阈值；若 225% 降级超过 `REQ-0023` 授权（名字 <290 或邮箱 <72）→ 退回设计；若 4 项交互 L2 断言无法复建 → 停下重拆或回设计改 T-03 载体，不得删断言；若 `T-1119-02` 的措辞对齐需要改阈值/降级规则 → 停下回设计，不在文档任务里改。回退 = 按提交反向回退；本批纯 additive（helper/显示串），无 schema/数据迁移，回退后候选回退到 `min(固有宽, 可用宽×0.45)` 与 `byTruncatingMiddle`；回退/重跑轮次不翻转状态位。

本批统一验证命令：`./Scripts/swiftw build`、`./Scripts/swiftw test`、`bash Scripts/check-architecture.sh`；单任务过滤用 `./Scripts/swiftw test --filter PresentationTests`；`ComposeAutocompleteProbe` 的编译/复跑按 `task-spaces/20261119-164437/evidence/name-width-probe/round2/commands2.txt` 的对象与模块缓存方式执行，但源码必须换成生产 `Sources/uumail/RecipientTextField.swift` + `RecipientTextField+AppKit.swift` + `RecipientForm.swift`，不得用 `patched/` 设计副本；证据入 `task-spaces/<run>/evidence/compose-autocomplete-probe/`。

拆分复核（2026-11-19）：每个任务在「规格锚点」列指到组件规格/场景卡的具体行；依赖无环（`T-1119-01` 与 `T-1119-02` 并行 → `T-1119-03`）；出口含可执行 ID/命令/证据位置与最低证据层级；已落本表。拆分过程、默认确认与风险见 `task-spaces/20261119-164437/split.md`。

### 装载清单（2026-11-19 W-M3-10 拆分）

| 任务 | 必读 | 预计装载 | 备注 |
|---|---|---|---|
| `T-1119-01` | `CMP-APP` §设计增量 `:243-253`；`design2.md` §4.1–§4.3/§5/§7.1；`SCN-0017` `:44`/`:89`；`RecipientTextField.swift`（165 行）、`RecipientTextField+AppKit.swift`（265 行）、`RecipientForm.swift`（只读，222 行）；`NameWidthProbe2.swift`（311 行）+ `commands2.txt` | ~1,600 行 | 探针源码需重建；不得只跑显示宽度；先补 `columnWidthsEdgeClamp` 直接边界与 bench |
| `T-1119-02` | `SCN-0017` `:44`/`:89`；`design2.md` §4.4/§7.1；`review2.md` §7 N1/N3/N5 | ~300 行 | 只改两处措辞；阈值/层级/状态不动 |
| `T-1119-03` | `SCN-0017` §测试/§状态/§与相邻场景的边界；`architecture.md` §1；`CMP-APP` 增量；`T-SCN-0017-01..04` 既有测试；探针输出 | ~1,400 行 | 独立重编生产源；11 项逐例；全量 + 架构 4 门 + 四场景回归 |

装载纪律：单任务 ≤2,000 行；若 `T-1119-01` 因探针重建超限，先停下按批次纪律重拆（不得删 T-03 断言），或回设计改测试载体；所有 change 另读 `doc/design/architecture.md` §2/§3 的相关段落（约 100 行）并核对依赖方向未变。

## W-M3-11 任务表（远程图片放行后的实际加载：ATS 运行载体）

来源：`REQ-0024`（`delivered`）、`SCN-0018`（`verified`）、`task-spaces/20261119-213812/design.md`（第 1 轮）、`task-spaces/20261119-213812/review.md`（**pass**；B1–B5 非阻塞建议）、`doc/design/components/CMP-APP/spec.md` §设计增量：远程图片实际加载的运行载体 ATS 例外（`:256-269`）、`doc/design/scenarios/mail/read/remote-image-load/scenario.md`（`T-SCN-0018-01..03`）、决策记录 `doc/history/decisions/2026-11-19-remote-image-ats.md`（人工确认 pass）、拆分记录 `task-spaces/20261119-213812/split.md`。

**设计边界（不改）**：只在交付载体增加 `NSAppTransportSecurity/NSAllowsArbitraryLoadsInWebContent=true`，**不加** `NSAllowsArbitraryLoads`/`NSExceptionDomains`；plist 抽成 `Resources/Info.plist` 单一来源，`Scripts/make-app.sh` 只 `cp`；`MessageWebView`/`MessageBodyStyle`/`MessageBodyView`/`MailboxViewModel`/`ComposeEditor` 零改动；不改 CSP 两档/禁 JS/白底/`lastRender` guard，不改 schema/协议/公开契约/target/依赖；不伪造 Referer/Cookie，不做代理/URL 改写/缓存。ATS 例外已**人工确认**（2026-11-19，pass，意见「仅加 `NSAllowsArbitraryLoadsInWebContent=true`」），本批不再设确认门；定级 P2。

**验证载体前提（装载前必读）**：`SCN-0018` §测试的探针源在 `task-spaces/20261119-213812/evidence/remote-image-probe/`（`RemoteImageProbe.swift`，278 行，编译生产 `MessageWebView`/`MessageBodyStyle`；`commands.md` 有编译与 carrier 组装命令），探针**不提交为生产代码**，验证产物只入 `task-spaces/<run>/evidence/`。现有 `--allow` 是启动参数、没有运行时切换 seam（`review.md` §5 B3）：`T-SCN-0018-01` 的「开→关后命中不增长」必须补动态切换宿主（带 binding 的探针 host 或 `--allow-sequence`），**不得**用两次独立运行冒充。探针 `.app` 的 `Contents/Info.plist` 必须用 `Resources/Info.plist` **原样副本**、二进制在 bundle 内命名 `uumail`（满足 `CFBundleExecutable`）；图片 URL 用解析到受控服务器的**非本地主机名**（`127.0.0.1.nip.io` 一类），**禁止**只用 `127.0.0.1`/`localhost` 判 ATS（会被豁免，假绿）。

**回归载体限制**：`SCN-0013` 的 L2 探针（`RemoteContentToolbarProbe`/`RemoteContentBodyProbe`）源码在已归档的 `task-spaces/20261116-223645/`，当前工作区不可读、仓库内无副本。本批 `Sources/` 零改动，`SCN-0013` 回归以替身登记：`MailboxViewModelTests` 的 `remoteContent*` L1 + 实现 commit 零 `Sources/` diff + `T-SCN-0018` 阻断档 0 命中 L2 + 探针内 `MessageBodyStyle.contentSecurityPolicy` 两档字符串断言；`test.md` 写明「未重跑 `SCN-0013` L2」，**不得**写成跑过。若复核要求完整 L2 回归，停下按批次纪律另拆探针重建任务，不在 `T-1119-05` 静默扩。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1119-04` | `change` | `CMP-APP`（运行载体） | `CMP-APP/spec.md` §设计增量：远程图片实际加载的运行载体 ATS 例外（`:256-269`，修改段 `:260-263`、实现进度 `:269`）；`design.md` §5.1–§5.2/§8.3；`SCN-0018` 入口 `:20-22`、运行序第 6 步 `:37`、不可变引用 `:53-55` | — | 已完成（2026-11-19） | 新增 `Resources/Info.plist`：与 `Scripts/make-app.sh:15-33` 现 heredoc **逐键一致**（`CFBundleName`/`CFBundleDisplayName`/`CFBundleIdentifier=com.uumail.app`/`CFBundleIconFile=AppIcon`/`CFBundleExecutable=uumail`/`CFBundlePackageType`/`CFBundleShortVersionString=0.1.0`/`CFBundleVersion=1`/`LSMinimumSystemVersion=14.0`/`NSHighResolutionCapable`/`LSApplicationCategoryType`），另加 `NSAppTransportSecurity`→`NSAllowsArbitraryLoadsInWebContent=true`；**不含** `NSAllowsArbitraryLoads`/`NSExceptionDomains`；`plutil -lint` 通过。`Scripts/make-app.sh`：删除内联 heredoc，改为 `cp Resources/Info.plist "$APP/Contents/Info.plist"`；release 构建、图标、ad-hoc 签名、`build-info.txt`、`dist` 路径不变（`:7-13,35-42` 不动）。出口（`L1（静态断言：plutil/cmp/脚本接线）+ 构建/架构门`）：`plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoadsInWebContent raw -o - Resources/Info.plist` → `true`；`plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads` 与 `… .NSExceptionDomains` → 非 0 退出（键不存在）；`grep -c "NSAppTransportSecurity" Scripts/make-app.sh` = 0、`grep -Ec 'cp[[:space:]]+"?Resources/Info\.plist' Scripts/make-app.sh` = 1、`grep -c "<<'PLIST'" Scripts/make-app.sh` = 0（内联 heredoc 已删）；`./Scripts/swiftw build` 绿、`bash Scripts/check-architecture.sh` 4 门 PASS。**先**提交实现 commit（带 `T-1119-04` + `SCN-0018`）**再**运行 `./Scripts/make-app.sh` 重建 `dist`（`AGENTS.md` 里程碑构建，不是发布、不推版本号），断言 `cmp -s dist/uumail.app/Contents/Info.plist Resources/Info.plist` 通过、`dist/build-info.txt` 的 `commit:` = `git rev-parse --short HEAD`。`CMP-APP` 增量「实现进度」行改为已实现（只改该行，不改规则/数值/验收）。命令输出与断言入 `task-spaces/<run>/evidence/carrier/`。 |
| `T-1119-05` | `verify` | `SCN-0018`（0 组件） | `SCN-0018` §测试 `:57-72`/§状态 `:74-78`/§与相邻场景的边界 `:80-86`；`CMP-APP` 增量 `:256-269`；`design.md` §7.2/§8.1–§8.2；`review.md` §5（B3/B4） | `T-1119-04` | 已完成（2026-11-19） | 在载体冻结后独立复验，不复用 `T-1119-04` 输出：按 `T-SCN-0018-01`（L2）重建探针 `.app`（plist = `Resources/Info.plist` 原样副本、二进制名 `uumail`、非本地主机名 + 受控 http 源），断言阻挡档 0 命中/`naturalWidth=0`、放行档 ≥1 命中/`naturalWidth>0`/快照品红像素 >0、**开→关动态序列**关闭后命中不增长（B3：带 binding 宿主或 `--allow-sequence`，不得用两次独立运行冒充）、**负控制**（同一二进制放无 ATS 键 bundle，放行档必须 0 命中）、**正控制**（`data:` 在阻挡档渲染）。按 `T-SCN-0018-02`（L1+L2）：shipped plist 的 `plutil` 键断言（含缺键）+ 同一 carrier `URLSession` 明文 http 仍报 ATS 错误 + 关闭档 0 命中。按 `T-SCN-0018-03`（L1+L2）：`Scripts/make-app.sh` 从 `Resources/Info.plist` 装机且无内联 ATS heredoc、`cmp` dist plist 与 shipped plist 字节一致、`dist/build-info.txt` 的 commit = 构建时 HEAD（dist 重建时的 HEAD；`dist` 是重建产物，重建后的 `chore: republish dist at 1b86282` 不改变该口径）、裸可执行（`swift run` 形状）放行档 ≥1 命中且 `naturalWidth>0`。回归：`MailboxViewModelTests` 的 `remoteContent*` L1 + 探针内 CSP 两档字符串断言（`SCN-0013` 替身，见上「回归载体限制」）；`ComposeDocumentTests.remotePermission`（B4 替身，不做新 L2，理由与残余风险写 `test.md`）；`./Scripts/swiftw test` 全量（基线 `327 tests / 54 suites`，不得新增失败）；`bash Scripts/check-architecture.sh` 4 门；`SCN-0004`/`SCN-0010`/`SCN-0012`/`SCN-0015`/`SCN-0016` 按边界只回归不新增。逐可执行 ID 记录 PASS/FAIL，证据入 `task-spaces/<run>/evidence/carrier-verify/`；A5 真实样本冒烟不执行（发布前/人工项，读真实邮件库有工作区/隐私边界），在 `test.md` 登记为残余。只建议翻转 `SCN-0018`→`verified`、`REQ-0024`→`delivered`、`T-1119-04`/`T-1119-05` 完成，不自行改状态位；不改产品代码/探针断言/设计产物；失败不得静默 skip、降级或用 L1 冒充 L2。`L1（静态断言与单元测试）+ L2（无头探针）` |

任务边界（每个任务卡的可执行边界）：

| 任务 | 允许改的范围 | 明确不做 |
|---|---|---|
| `T-1119-04` | `Resources/Info.plist`（新增）、`Scripts/make-app.sh`、`CMP-APP` 增量「实现进度」行（只改该行）、`dist/`（重建产物，不入库）、`task-spaces/<run>/`（`dev.md` + `evidence/carrier/`） | 不改 `Sources/`、`Tests/`、`Package.swift`；不改 `SCN-0018`/`REQ-0024`/`architecture.md`/`risks.md`/`roadmap` 的状态或断言（B1 措辞不在本任务）；不加 `NSAllowsArbitraryLoads`/`NSExceptionDomains`；不做代理/URL 改写/缓存；不做探针与 L2（归 `T-1119-05`）；不推版本号、不对外发布；不翻转状态位；不做出口外探针 |
| `T-1119-05` | `task-spaces/<run>/`（`test.md` + `evidence/carrier-verify/`；探针源码只放 task-space，不入库） | 不改产品代码/`Resources/Info.plist`/`Scripts/make-app.sh`；不改探针断言以迁就失败；不改设计产物/需求/场景/门状态；不自行翻转 `verified`/`delivered`/任务完成；不读真实邮件库、不把真实主题/URL/主机/账号写进证据；不做 L3 截图/OCR 或 L4 AX；不重跑 `make-app.sh` 重建载体（验证固定 `T-1119-04` 产物）；不在验证期提交 `Tests/`（会使 `build-info` 与 HEAD 不一致）；失败不得静默 skip、降级或用 L1 冒充 L2 |

共同约束：每个 change 一个实现 commit，message 带 `T-` 与 `SCN-`；L2 探针文件名/组合由实现按 `commands.md` 落定（出口以用例 ID 与生产源断言为准，不得删/放宽断言）；`CMP-APP` 增量实现进度行随实现 commit 只改该行，若需改契约/形状/测试断言，回设计，不在任务里自行扩。越权清单按 `af-flow-rule` §4：改设计产物、自授权人工门、发布动作、出口外探针，发现即停手并在 `dev.md` 记「超出任务范围」。

并行关系：**本批无可并行任务**。`T-1119-04`→`T-1119-05` 为单链：载体未冻结前无法按「shipped plist 原样副本」验；verify 不跳步、不复用实现输出。组件级 WIP=1 自然满足：同批只有一个 `CMP-APP` 任务在飞。

**条件与回退**：若 `Resources/Info.plist` 除 ATS 外与现 heredoc 有键值差异 → 停下逐键核对 `CMP-APP` 增量，不改键值去凑构建；若 `make-app.sh` 出现「必须先生成 plist 才能构建」的需求（当前不存在）→ 停下回设计；若 `plutil -extract … raw` 输出非 `true`（如 `1`）→ 以 `plutil -p` 解析的布尔值为准，不用文本 grep 代替、不放宽断言；若负控制（无 ATS bundle）出现命中 → 主机名/载体设置错，判失败而非通过；若 shipped plist 下 `URLSession` 明文 http 成功 → 安全面超出批准范围（等同全局放宽），立即停手回设计/人工确认，不得判过；若 `dist/build-info.txt` 的 commit ≠ HEAD → 判「载体未更新」，退回 `T-1119-04` 重建；若非本地主机名不可解析（离线）→ 登记跳过主正例，`SCN-0018` 保持 `designed`，`T-1119-05` 记阻塞，不得退回 `127.0.0.1`。回退＝反向回退实现 commit（删 `Resources/Info.plist`、恢复 heredoc）→ 图片重新空白（正是要暴露的载体缺口）；无 schema/数据迁移、无用户数据删除。回退/重跑轮次不翻转状态位。

本批统一验证命令：`./Scripts/swiftw build`、`./Scripts/swiftw test`、`bash Scripts/check-architecture.sh`；载体重建 `./Scripts/make-app.sh`（仅 `T-1119-04` 里程碑）；静态断言用 `plutil -lint`/`plutil -extract … raw`/`cmp`/`grep -c`；探针编译与复跑按 `task-spaces/20261119-213812/evidence/remote-image-probe/commands.md` 改造（bundle plist 换 `Resources/Info.plist` 原样副本、二进制名 `uumail`、非本地主机名），证据入 `task-spaces/<run>/evidence/carrier/` 与 `…/carrier-verify/`。

拆分复核（2026-11-19）：每个任务在「规格锚点」列指到组件规格/场景卡的具体行；依赖无环（单链）；出口含命令/期望值/文件/证据位置与最低证据层级（`L1`/`L2` 自描述）；已落本表。B1（`REQ-0024:43,55` 措辞，属需求卡）与 B5（`evidence/README.md` 用例数 9→10，属设计期过程文档）不拆任务，登记收尾处理；B3 进 `T-1119-05` 必做出口；B4 按「`SCN-0016-04` CSP L1 + 同一 WebKit 门控」替身处理。拆分过程、默认确认（D1–D7，未经人工）、风险与边界见 `task-spaces/20261119-213812/split.md`。

### 装载清单（2026-11-19 W-M3-11 拆分）

| 任务 | 必读 | 预计装载 | 备注 |
|---|---|---|---|
| `T-1119-04` | `CMP-APP` 增量 `:256-269`；`design.md` §5.1/§5.2/§8.3；`Scripts/make-app.sh`（43 行）；`SCN-0018` 入口/运行序/不可变引用；`AGENTS.md` 发布段 | ~450 行 | 只改载体；plist 键值逐项对照 heredoc；先 commit 后 `make-app.sh`；`dist` 不入库 |
| `T-1119-05` | `SCN-0018` §测试/§状态/§边界；`design.md` §7–§8；`review.md` §5（B3/B4）；`evidence/remote-image-probe/RemoteImageProbe.swift`（278 行）+ `commands.md`；`Sources/uumail/MessageBodyView.swift`/`MessageBodyStyle.swift`（只读）；`MailboxViewModelTests`/`ComposeDocumentTests` 相关用例 | ~1,500 行 | 探针只入 task-space；动态开→关；负控制/正控制；`SCN-0013` L2 用替身并登记；A5 只登记 |

装载纪律：单任务 ≤2,000 行；若 `T-1119-05` 因动态 toggle 探针重建超限，先停下按批次纪律重拆（不得删断言），或回设计改测试载体；所有任务另读 `doc/design/architecture.md` §2/§3 的相关段落（约 100 行）并核对依赖方向未变。

## W-M3-12 任务表（HTML 正文内联图片 `cid:` 渲染）

来源：`REQ-0025`（`delivered`）、`SCN-0019`（`verified`）、`task-spaces/20261120-111818/design2.md`（第 2 轮设计）、`task-spaces/20261120-111818/review2.md`（**pass**；B1/B2 关闭、N1–N6 处置通过）、实现鉴定 `task-spaces/20261120-111818/review5.md`（**pass**；`T-SCN-0019-01..04` 与任务完成，§7）、`doc/design/components/CMP-SCN-READ/spec.md` §设计增量：内联图片渲染（`:129-170`）、`CMP-PRES/spec.md` §设计增量：内联图片渲染投影（`:454-471`）、`CMP-APP/spec.md` §设计增量：内联图片渲染串透传（`:272-283`）、公开面人工确认记录 `doc/history/decisions/2026-11-20-inline-image-render-public-surface.md`（人工确认 pass，选项 A）、拆分记录 `task-spaces/20261120-111818/split.md`。

**设计边界（不改）**：C2（`displayName`/local part 唯一匹配）+ V1（渲染前 `cid:`→`data:`）；只认领 `<img src>`，不处理 `srcset`/CSS 背景图/VML；`body`/`quotableHTML`/`message_bodies` 保持 raw HTML，data URL 只进当前渲染投影；不改 `attachments` schema、`MailDomain`/`MailGateway`/`Attachment` 公开契约、CSP 两档值、`baseURL`、禁 JS、远程开关、附件条；不新增 target/依赖；不把真实样本字段写进测试/证据。公开面仅两个 **additive public** 成员：`ReadScene.renderInlineImages(for:html:)` 与 `MailboxViewModel.inlineImageHTML`，已**人工确认 pass（A，2026-11-20）**；D1–D8 仍为默认确认（未经人工），本表不把公开面确认写成对整份设计的签字。定级 **P2**。

**行数预算与拆分触发**：本批 `Scenes` 新增 **≤170 行**（`wc -l Sources/Scenes/*.swift` 合计 ≤1176；`T-1120-01` 按设计估算约 120 行、`T-1120-02` 约 50 行，二者合计为硬上限）；`InlineImageHTML.swift`、`ReadScene+InlineImages.swift` 各 **≤300**；`MailboxViewModel.swift`、`MailboxViewModel+Body.swift` 各 **≤400**；`MessageBodyView.swift`、`MailboxView.swift` 各 **≤300**。再改 `Scenes` 使其 **>1200 行**，或出现**第二个 HTML 纯工具**时，另立 **P1** 任务把 `HTMLText`/`InlineImageHTML` 拆到纯工具组件；本批不静默调预算、不新增 target/依赖。**N6 像素 guard 不在本批**：`design2.md` §2 N6 列为可选实现项，本批 170 行预算优先纯函数+取负载；R11（像素/解压炸弹）由收尾按项目 `risks.md` 口径登记，`T-SCN-0019-04` 只保留超像素边界用例（有文字时正文可读），不把像素上限写成验收契约。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1120-01` | `change` | `CMP-SCN-READ` | `CMP-SCN-READ/spec.md` §设计增量：内联图片渲染（`:132-149`）；`design2.md` §2 N6/§4.3；`SCN-0019` 运行序 3–4/6（`:33-36`） | — | 已完成（2026-11-20） | 新增 `Sources/Scenes/InlineImageHTML.swift`（internal；只 import Foundation + `MailDomain`；`sources`/`normalizedCID`/`matches`/`dataURL`/`replacingSources`；**不** import ImageIO/WebKit/SwiftUI/GRDB；N6 像素 guard **不在本批**——`design2.md` §2 N6 为可选实现项，本批 170 行预算优先纯函数+取负载，R11 残余交后续 P2/收尾）。新增 `Tests/ScenesTests/InlineImageHTMLTests.swift`：`sourcesFindCIDSourcesOnly`、`normalizationHandlesCasePercentAndBrackets`、`matchesDisplayNameAndLocalPart`、`matchesStemWhenCIDOmitsExtension`、`ambiguousReferenceIsIgnored`、`replacingOnlyTouchesSourceValues`、`dataURLSniffsCommonImageFormats` 全绿。出口：`./Scripts/swiftw test --filter ScenesTests` 绿 + `bash Scripts/check-architecture.sh` 4 门；`git diff` 仅新源文件、新测试与 `CMP-SCN-READ` 实现进度行（只追加）；单文件 ≤300、本任务 `Scenes` 源码新增按设计估算 ≤120 行（若超出，与 `T-1120-02` 合计仍须 ≤170，否则停下重拆）；不改 `ReadScene.swift`/其它 target/`Package.swift`。`L1（单元测试）` |
| `T-1120-02` | `change` | `CMP-SCN-READ` | `CMP-SCN-READ/spec.md` §设计增量：内联图片渲染（`:150-168`）；`design2.md` §4.4/§4.8；`SCN-0019` 运行序 5–6（`:35-36`）、失败路径（`:40-47`） | `T-1120-01` | 已完成（2026-11-20） | 新增 `Sources/Scenes/ReadScene+InlineImages.swift`（public `renderInlineImages(for:html:)`；`attachments(for:)` → `InlineImageHTML.matches` → 按 `fileReference` 去重 → 顺序 `downloadAttachment` → `Data(contentsOf:)` → 20MB 字节 guard → `InlineImageHTML.dataURL` → `replacingSources`；单张失败/坏数据/超限/取消跳过；全部无替换返回 nil；不抛错、不重试循环；每个附件之间检查 `Task.isCancelled`；不改 `downloadAttachment`/`FlightBoard`/`AttachmentFiles` 语义）。新增 `Tests/ScenesTests/ReadSceneInlineImageTests.swift`：`fetchesOnlyReferencedAttachments`、`reusesCachedFileAndSingleFlight`、`failedPayloadIsSkipped`、`oversizedAttachmentIsSkipped`、`cancellationStopsBetweenAttachments` 全绿；断言只取被引用附件、同附件多次引用只取一次、缓存命中 0 次 gateway、坏图跳过不阻断其它图、取消后不再取下一个附件、返回串含 `data:image/png;base64` 且其余字节不变。出口：`./Scripts/swiftw test --filter ScenesTests` 绿 + 架构 4 门；`git diff` 仅新源文件、新测试、测试 fake 的必要字节落盘支持（仅 `Tests/`）与 `CMP-SCN-READ` 实现进度行；单文件 ≤300、本任务源码新增按设计估算 ≤50 行（与 `T-1120-01` 合计 `Scenes` ≤170、组件合计 ≤1176）；不改协议/schema/`Attachment`/其它组件。`L1（单元测试）` |
| `T-1120-03` | `change` | `CMP-PRES` | `CMP-PRES/spec.md` §设计增量：内联图片渲染投影（`:454-470`）；`design2.md` §4.5；`SCN-0019` 运行序 2/7/8（`:32-38`） | `T-1120-02` | 已完成（2026-11-20） | 新增 `public private(set) var inlineImageHTML: String?` 与 internal 可取消图片任务；`MailboxViewModel+Body` 在 `openSelected`/`.cached`/`.loaded` 设置 `body` 后启动 `startInlineImageRender(ref, html)`；stale guard 为 `selectedRef == ref && openedBody == ref` 且当前 `.loaded` 的 html 仍是发起时那份；切换/清空/重开取消任务并清空 `inlineImageHTML`；失败/空结果保持 nil，不改 `body`/`quotableHTML`，不弹错、不重试。新增 `Tests/PresentationTests/MailboxViewModelInlineImageTests.swift`：`inlineImagesSetRenderHTMLWithoutTouchingBody`、`switchingMessageDropsStaleInlineImages`、`emptyOrFailedPayloadsLeaveRawHTML`、`remoteGateDoesNotAffectInlineImages` 全绿；断言 `inlineImageHTML` 含 data URL 而 `body`/`quotableHTML` 不含、迟到结果不写到 B、空/失败保持 raw、远程开关开/关不影响内联。出口：`./Scripts/swiftw test --filter PresentationTests` 绿 + 架构 4 门；`git diff` 仅两个 VM 文件、新测试、`Tests/PresentationTests/Support.swift` 的夹具必要改动与 `CMP-PRES` 实现进度行；`MailboxViewModel`/`+Body` 各 ≤400；不新增第三个 public 成员、不改 `body`/`quotableHTML` 语义、不 import `MailStore`/`EASClient`/WebKit；公开面只读且 `inlineImageTask` 不进 public 契约；`private`/`private(set)` 与 `+Body.swift` 跨文件访问冲突用主文件 internal 访问器或 `internal(set)` 解决（不改公开面），在实现进度行注明。`L1（单元测试）` |
| `T-1120-04` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：内联图片渲染串透传（`:272-282`）；`design2.md` §4.9；`SCN-0019` 运行序 7（`:37`） | `T-1120-03` | 已完成（2026-11-20） | `Sources/uumail/MessageBodyView.swift` 新增 internal `let inlineImageHTML: String?`；`.loaded` 的 `natural` 与 `capped` 两处均用 `inlineImageHTML ?? html` 交给既有 `MessageWebView`；`Sources/uumail/MailboxView.swift` 透传 `viewModel.inlineImageHTML`。`MessageWebView` 段与 `MessageBodyStyle` **0 行改动**（CSP 两档值/`sanitized`/禁 JS/`.nonPersistent()`/白底/`lastRender`/`loadHTMLString(_, baseURL: nil)` 原样）。出口：`./Scripts/swiftw build` + `./Scripts/swiftw test` + 架构 4 门绿；`git diff` 仅两个视图文件与 `CMP-APP` 实现进度行；`MessageBodyView`/`MailboxView` 各 ≤300；L2 透传探针编译**生产** `MessageBodyView.swift`/`MessageBodyStyle.swift` + 既有 `evidence/inline-image-probe/InlineImageProbe.swift` 的改造版，`inlineImageHTML` 传入生产改写串时断言 `img.naturalWidth>0`、快照品红像素 >0、`requests=0`，原始 `cid:` 负控制仍 `naturalWidth=0`；证据入 `task-spaces/<run>/evidence/inline-image-view/`。`L2（无头探针）+ 构建/既有测试门` |
| `T-1120-05` | `verify` | `SCN-0019`（0 组件） | `SCN-0019` §测试（`:60-76`）/§状态（`:78-88`）/§与相邻场景的边界（`:90-96`）；`design2.md` §5（`:187-211`）/§6（`:213-227`）；`review2.md` §交下一节点（`:164-171`） | `T-1120-01`…`T-1120-04` | 已完成（2026-11-20） | 在实现冻结后**独立复验，不复用实现输出**：①按 `T-SCN-0019-01..04` 逐可执行 ID 跑 L1（`InlineImageHTMLTests`/`ReadSceneInlineImageTests`/`MailboxViewModelInlineImageTests` 全部用例）；②重建 L2 探针，改用**生产** `InlineImageHTML` 的 `matches`/`dataURL`/`replacingSources` + 生产 `MessageBodyView`/`MessageWebView`，覆盖：内联图 `naturalWidth>0`/品红像素 >0/0 请求、远程档开/关内联仍可见且远程 0 新增请求、A→B→A/关闭重开仍可见且同附件只取一次、四类失败（无附件/取负载失败/坏字节/歧义）+ **纯文字基线** + L2 超像素/畸形大图边界用例（像素 guard 本批未实现时，只断言有文字时正文可读并登记 R11 残余，不判 fail；20MB 字节 guard 由 L1 `oversizedAttachmentIsSkipped` 覆盖），断言「有文字时文字必显示、可滚动；纯图片外部失败仍空白为已接受降级，不判 fail」；保留 `raw-cid-blocked`/`remote-blocked` 负控制。③`./Scripts/swiftw test` 全量（记录本批新增后的总数，不得新增失败）+ `bash Scripts/check-architecture.sh` 4 门；④回归 `SCN-0013`/`SCN-0018`/`SCN-0005`/`SCN-0015`/`SCN-0010`/`SCN-0004` 按各自 §测试/§边界不退化；A5 真实样本冒烟**不执行**，只登记残余；不上 L3/L4。证据入 `task-spaces/<run>/evidence/inline-image-verify/`；只建议翻转 `SCN-0019`→`verified`、`REQ-0025`→`delivered`、`T-1120-01`…`T-1120-05` 完成，不自行改状态位；不改产品代码/设计产物/探针断言以迁就失败。`L1（单元测试）+ L2（无头探针）` |

任务边界（每个任务卡的可执行边界）：

| 任务 | 允许改的范围 | 明确不做 |
|---|---|---|
| `T-1120-01` | 新增 `Sources/Scenes/InlineImageHTML.swift`、`Tests/ScenesTests/InlineImageHTMLTests.swift`；`CMP-SCN-READ/spec.md` 实现进度行（只追加）；`task-spaces/<run>/`（`dev.md` + 证据） | 不改 `ReadScene.swift`/`ReadScene+InlineImages.swift`/其它 target/`Package.swift`；不改场景卡/需求卡/决策记录/roadmap 状态；不引入 ImageIO/第三方库；不做 L2/L3/L4；不翻转状态位 |
| `T-1120-02` | 新增 `Sources/Scenes/ReadScene+InlineImages.swift`、`Tests/ScenesTests/ReadSceneInlineImageTests.swift`；`Tests/ScenesTests/ScenesSupport.swift` 仅加测试 fake 的字节落盘/调用计数；`InlineImageHTML.swift` 仅修 `T-1120-01` 暴露的纯函数缺陷（不改匹配/载体规则）；`CMP-SCN-READ` 实现进度行（只追加）；`task-spaces/<run>/` | 不改 `downloadAttachment` 签名/语义、`FlightBoard`/`AttachmentFiles` 端口、schema/`Attachment`/`MailDomain`/`MailGateway`；不改场景卡/需求卡/决策记录/roadmap 状态；不做 L2/L3/L4；不翻转状态位 |
| `T-1120-03` | `Sources/Presentation/MailboxViewModel.swift`、`Sources/Presentation/MailboxViewModel+Body.swift`；新增 `Tests/PresentationTests/MailboxViewModelInlineImageTests.swift`；`Tests/PresentationTests/Support.swift` 仅加夹具的附件字节/调用计数；`CMP-PRES` 实现进度行（只追加）；`task-spaces/<run>/` | 不改 `Scenes`/`uumail`/`MailDomain`/`MailStore`/schema；不改 `body`/`quotableHTML` 语义；不新增第三个 public 成员；不改场景卡/需求卡/决策记录/roadmap 状态；不做 L2/L3/L4；不翻转状态位 |
| `T-1120-04` | `Sources/uumail/MessageBodyView.swift`、`Sources/uumail/MailboxView.swift`；`CMP-APP` 实现进度行（只追加）；`task-spaces/<run>/`（`dev.md` + `evidence/inline-image-view/` 探针源码/命令/原始输出） | 不改 `MessageWebView` 语义、`MessageBodyStyle`、CSP 两档值、`sanitized`、禁 JS、`baseURL`、`lastRender` guard、附件条、远程开关、信封头/截断 banner/字号分支；不改 `Package.swift`/新增 target/依赖；不改场景卡/需求卡/决策记录/roadmap 状态；不做 L3 截图/OCR 或 L4 AX；不翻转状态位 |
| `T-1120-05` | `task-spaces/<run>/`（`test.md` + `evidence/inline-image-verify/`；探针源码只放 task-space，不入库）；`Tests/` 仅在发现测试缺口时补测试并单独一次测试 commit | 不改产品代码/探针断言以迁就失败；不改设计产物/需求/场景/门状态；不自行翻转 `verified`/`delivered`/任务完成；不读真实邮件库、不把真实主题/发件人/URL/账号/正文写进证据；不做 L3 截图/OCR 或 L4 AX；不重跑 `make-app.sh`/发布动作 |

共同约束：每个 change 一个实现 commit，message 带 `T-` 与 `SCN-`；L2 探针文件名/组合由实现按 `commands.md` 落定（出口以用例 ID 与生产源断言为准，不得删/放宽断言）；规格实现进度行随实现 commit 只追加，不改规则/数值/验收；若需改契约/形状/测试断言，回设计，不在任务里自行扩。越权清单按 `af-flow-rule` §4：改设计产物、自授权人工门、发布动作、出口外探针，发现即停手并在 `dev.md` 记「超出任务范围」。

并行关系：**本批无可并行任务**。`T-1120-01`→`T-1120-02`（同一 `CMP-SCN-READ`，后者消费前者的 internal 契约）→`T-1120-03`（消费 `renderInlineImages` 公开方法）→`T-1120-04`（消费 `inlineImageHTML` 公开属性）→`T-1120-05`（独立复验，验证不跳步、不复用实现输出）。组件级 WIP=1 自然满足：同一时刻只有一个 `CMP-SCN-READ`/`CMP-PRES`/`CMP-APP` 任务在飞。

**条件与回退**：若 `T-1120-01`+`T-1120-02` 的源码新增合计 >170 行、或任一新增文件 >300 行 → 停下重拆/回设计，不静默超预算；本批不实现 N6 像素 guard，若实现期发现 20MB 字节 guard 不足或真实样本触发解压炸弹风险 → 另立 P2 任务或回设计，不静默引入 `ImageIO`/新依赖；若 `T-1120-02` 发现必须改 `downloadAttachment` 签名、`FlightBoard`/`AttachmentFiles` 端口或 schema → 停下回设计（契约变更，需按 `auto-confirm` §3 另行确认）；若 `T-1120-03` 发现需要第三个 public 成员、或必须改 `body`/`quotableHTML` 语义 → 停下回设计（公开面确认只覆盖两个成员）；若 `T-1120-04` 发现必须动 `MessageWebView`/CSP/`baseURL`/JS → 停下回设计（安全面/契约变更）；若 L2 探针无法编译生产 `InlineImageHTML`/`MessageBodyView` → 按既有探针方式直接编译源文件；仍不可行则回设计改测试载体或声明 L3，**不得**用 L1 冒充、不得删断言；若 `Scenes` 合计 >1176 或任一新增文件 >300 → 停下按批次纪律重拆（N6 延后项不进本批），不静默超预算。回退＝反向回退实现 commit；本批无 schema/数据迁移，回退后正文回到 raw HTML（内联图不显示，即现状）；`SCN-0019` 在验证通过前保持 `designed`，回退/重跑轮次不翻转状态位。

本批统一验证命令：`./Scripts/swiftw build`、`./Scripts/swiftw test`、`bash Scripts/check-architecture.sh`；单任务过滤用 `./Scripts/swiftw test --filter ScenesTests` / `--filter PresentationTests`；L2 探针按 `task-spaces/20261120-111818/evidence/inline-image-probe/commands.md` 改造，必须编译**生产** `Sources/Scenes/InlineImageHTML.swift` + `Sources/uumail/MessageBodyView.swift`/`MessageBodyStyle.swift`，保留 `raw-cid-blocked`/`remote-blocked` 负控制并加纯文字基线；证据入 `task-spaces/<run>/evidence/inline-image-view/` 与 `…/inline-image-verify/`。

拆分复核（2026-11-20）：每个任务在「规格锚点」列指到组件规格/场景卡的具体行；依赖无环（单链）；出口含可执行 ID/命令/期望值/文件/证据位置与最低证据层级（`L1`/`L2` 自描述）；已落本表。本批新增 5 个任务，不按文件/工时拆；`T-1120-01`/`T-1120-02` 同组件串行是共享 internal 契约的必要约束。本拆分 docs commit 用追踪号 `T-1120-00`（不代表任务表编号）。拆分过程、默认确认（D1–D8，未经人工）、边界与风险见 `task-spaces/20261120-111818/split.md`。

### 装载清单（2026-11-20 W-M3-12 拆分）

| 任务 | 必读 | 预计装载 | 备注 |
|---|---|---|---|
| `T-1120-01` | `CMP-SCN-READ` 增量 `:129-170`；`design2.md` §2 N1/N6、§4.3；`SCN-0019` 运行序 3–4/6；`HTMLText.swift`（221 行，风格/正则参考）；`ScenesSupport.swift`（约 300 行）；`Package.swift` | ~900 行 | 纯函数优先；本批不做像素 guard；不 import ImageIO |
| `T-1120-02` | `CMP-SCN-READ` 增量 `:150-168`；`design2.md` §4.4/§4.8；`SCN-0019` 运行序 5–6/失败路径；`ReadScene.swift`（232 行）；`ScenesSupport.swift`；`ReadSceneTests.swift`；`InlineImageHTML.swift`（`T-1120-01` 产物） | ~1,300 行 | 复用 `downloadAttachment`/缓存/单飞；测试 fake 需落盘字节 |
| `T-1120-03` | `CMP-PRES` 增量 `:454-471`；`design2.md` §4.5；`SCN-0019` 运行序 2/7/8；`MailboxViewModel.swift`（381 行）、`MailboxViewModel+Body.swift`（109 行）、`MailboxViewModel+Compose.swift`（51 行，`quotableHTML`）；`PresentationTests/Support.swift`；`MailboxViewModelTests.swift` | ~1,900 行 | 接近上限；只加一个 public 属性；stale guard 必测 |
| `T-1120-04` | `CMP-APP` 增量 `:272-283`；`design2.md` §4.9；`SCN-0019` 运行序 7；`MessageBodyView.swift`（256 行）、`MailboxView.swift`（218 行）、`MessageBodyStyle.swift`（41 行）；既有 `InlineImageProbe.swift` + `commands.md` | ~1,000 行 | 只换显示串；CSP/`MessageWebView` 零改动 |
| `T-1120-05` | `SCN-0019` §测试/§状态/§边界；`design2.md` §5/§6；`review2.md` §交下一节点；`evidence/inline-image-probe/`（探针/命令/原始输出）；三组新测试与全量回归清单 | ~1,800 行 | 独立重编生产源；逐 ID；纯文字基线；A5 只登记 |

装载纪律：单任务 ≤2,000 行；若 `T-1120-03`/`T-1120-05` 装载超限，先停下按批次纪律重拆，不静默扩大；所有任务另读 `doc/design/architecture.md` §2/§3/§4 的相关段落（约 120 行）并核对依赖方向未变。

## W-M3-13 任务表（附件取用交互：双击打开、右键另存为）

来源：`REQ-0026`（`delivered`）、`SCN-0020`（`verified`）、`task-spaces/20261120-160446/design3.md`（第 3 轮设计）、`task-spaces/20261120-160446/review3.md`（**pass**；B1–B3 关闭、N1–N4 非阻塞）、实现鉴定 `task-spaces/20261120-160446/review7.md`（**pass**；`T-SCN-0020-01..10` 与任务完成，§8）、`doc/design/components/CMP-APP/spec.md` §设计增量：附件取用交互（`:286-339`）、`CMP-PRES/spec.md` §设计增量：附件下载失败文案（`:476-505`）、公开面人工确认记录 `doc/history/decisions/2026-11-20-attachment-error-surface.md`（人工确认 A）、拆分记录 `task-spaces/20261120-160446/split.md`。

**设计边界（不改）**：F1（SwiftUI `Button` + 双击 + `.contextMenu` + Return）、S1（APP 层 `NSSavePanel` + 临时文件原子落位）、APP 动作代际 A1（`AttachmentActionModel.epoch`；APP **不读** `Presentation` internal `selectionGeneration`）、源缺失 R1（不自动重下，`missingSourceText` 可重试）、取消 C1（入口只在面板/复制阶段；下载阶段任务被取消不写/不弹/不复制，共享 `FlightBoard` 不中止）；不改 `Scenes`/`Composition`/`MailDomain`/`MailStore`/schema/`Package.swift`、缓存算法（2 GB/修改时间最旧优先）、`SCN-0005` 欠账（25MB/续传/名称回退）、内联图片链路（`SCN-0019` 只回归）。公开面仅 `MailboxViewModel.attachmentErrorText`（**人工确认 A**，只读，`download` 签名不变）；D16–D18 仍为默认确认（未经人工）。定级 **P2**。

**行数预算与拆分触发**：`AttachmentStripView.swift`/`AttachmentExport.swift` 各 **≤300**；`MessageBodyView` **≤270**、`MailboxView` **≤245**；`MailboxViewModel.swift` **≤400**、`MailboxViewModel+Attachments.swift` **≤80**；`uumail` 总量约 **+360–480**。任一新增文件 >300、PRES 主文件 >400、或 `AttachmentExport.swift` 无法在单任务内闭合 → 停下重拆/回设计，不静默超预算、不改架构门/删测试/放宽断言。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1120-06` | `change` | `CMP-PRES` | `CMP-PRES/spec.md` §设计增量：附件下载失败文案 `:476-505`（新增状态 `:480-492`、测试 `:493-503`）；`SCN-0020` 失败路径/迟到结果 `:52-69,84-91`；`design3.md` §4.2.1 `:192-226`/§6.1 `:566-580`；`REQ-0026:59` | —（可与 `T-1120-07`/`T-1120-10` 并行；`T-1120-09` 依赖它） | 已完成（2026-11-20） | 新增 `public internal(set) var attachmentErrorText: String?` 与 internal `@ObservationIgnored selectionGeneration`（`selectedListKey` **真正变化**时递增 `selectionGeneration` 并清空 `attachmentErrorText`；同 key reload 不递增；`clearSelection` 走同一 `didSet`）；`download` 迁到新 `Sources/Presentation/MailboxViewModel+Attachments.swift`（≤80 行；签名不变；入口/`await` 后 `Task.isCancelled`、`catch is CancellationError`、`generation+key` guard；成功清空、失败经 `ErrorText` 写文案、取消不写不清）；新增 `Tests/PresentationTests/MailboxViewModelAttachmentTests.swift` 覆盖 `T-SCN-0020-01a–01g`（`01f` 迟到失败/成功、A→B→A；`01g` 取消；`Support.swift` 仅按需补夹具，不改既有 fake 语义）；`./Scripts/swiftw test --filter PresentationTests` 绿 + `bash Scripts/check-architecture.sh` 4 门；`MailboxViewModel.swift` ≤400、`+Attachments.swift` ≤80；`git diff` 仅 PRES 两个源文件、新测试、`Support.swift` 夹具与 `CMP-PRES` 实现进度行（只追加）；不改 `Scenes`/`MailDomain`/schema/`Package.swift`、不改 `download` 签名、不新增其它 public。`L1（单元测试）` |
| `T-1120-07` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量 `:306-317`（`AttachmentExport` 面板/复制/保存流/gate/动作模型、复制/取消/源缺失、APP epoch）、不变量 `:319-332`；`SCN-0020` 运行序 3–6 `:36-72`、失败路径 `:75-97`；`design3.md` §4.2.2 `:228-350`/§4.2.3 `:352-396`/§6.2 `:582-609`/§6.3 `:611-698` | —（`CMP-APP` 链首；`T-1120-08`/`T-1120-09` 依赖它；与 `T-1120-06`/`T-1120-10` 不同组件可并行） | 已完成（2026-11-20） | 新增 `Sources/uumail/AttachmentExport.swift`（internal，≤300）：`SavePanelPresenting`+`SystemSavePanel`、`AttachmentFileCopy`（`nonisolated async` 1 MiB 分块/逐块 `Task.checkCancellation`/临时文件原子落位/取消与失败清理/源==目标 no-op/缺源 `MailError.storage`）、`AttachmentSaveFlow`（去 `reResolve`；源缺失 `missingSourceText`；`shouldContinue`；面板/复制取消 nil）、`AttachmentActionGate`（按 `Attachment.id` per-id 单飞）、`AttachmentActionModel`（`Origin(key,epoch)`、`syncSelection` 唯一递增点+清 `saveErrorText`+隐藏 stale saving、`open` N3 重下 guard、`runSave` 面板前/复制后 guard、`cancelSave` 只取消面板/复制阶段、`visibleSavingID`）；按 `review3.md` N1 在 `runSave` 首次 `download` 前补 `guard isCurrent(origin)`。L2 探针覆盖 `T-SCN-0020-02e/02f/08a/08b` 与 `10a–10e`（`10a–10e` 不得用 `T-SCN-0020-08a/08b` 或 `02e/02f` 代替），逐例 PASS；`./Scripts/swiftw build` + 架构 4 门；证据入 `task-spaces/<run>/evidence/attachment-access-verify/`（逐例原始输出 + `commands.md`，含 HEAD/编译命令/限制）；≤300 行；`git diff` 仅新源文件 + `CMP-APP` 实现进度行。**import 约束**：`uumail` 白名单不含 `Observation`，`@Observable` 用 `import SwiftUI`（typecheck 证据 `task-spaces/20261120-160446/evidence/split-checks/typecheck.txt`）；若确需显式 import 或需改 `check-architecture.sh` → 停下回设计/架构，不静默改门；不 import `Composition`/`Scenes`/`WebKit`；不改 `Scenes`/`Composition`/`MailDomain`/`Package.swift`；不新增 public。`L2（无头探针）+ 构建门` |
| `T-1120-08` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：附件条 `:291-299`；`SCN-0020` 入口/运行序 2/4 `:20-21,34-35,43-51`、单击/Space `:93`；`design3.md` §4.2.5 `:454-470`、§6.2 `:590-593,596`；`design2.md` §4.2.2（AX/选中态/菜单，沿用） | `T-1120-07`（同组件 WIP=1；无编译依赖） | 已完成（2026-11-20） | 新增 `Sources/uumail/AttachmentStripView.swift`（internal，≤300）：`Label`+`bordered`/`small`/`scaledInheritedFont` 原样式；单击只写 `selectedAttachmentID`（描边 overlay，不改尺寸）；双击 `simultaneousGesture(TapGesture(count: 2))` → `onOpen`；`.focusable`+`.focused`+`.onKeyPress(.return)` → `onOpen`（Space 仍选中）；`.contextMenu` 恰两项「打开」「另存为…」；AX label/hint/两个自定义动作；`errorText != nil` 时橙色 `.caption` banner（无错误零布局变化）；`savingID == id` 时同位置「正在另存为…」+「取消」；附件列表变化清空选中/焦点/saving 显示；不下载/不读写文件/不判 `MailError`。L2 探针覆盖 `T-SCN-0020-02a/02b/02c/02d/04b`（单击 0 open/0 save；双击 1 open、并发双击 gate 后仍 1；Return 1、Space 0；`NSView.menu(for:)` 恰两项、`performActionForItem(0/1)` → open/save 各 1；`errorText` 非空才 banner，结构断言不要求像素）全 PASS；`./Scripts/swiftw build` + 架构 4 门；证据入 `task-spaces/<run>/evidence/attachment-access-verify/`；≤300 行；`git diff` 仅新文件 + `CMP-APP` 实现进度行；不改 `MessageBodyView`/`MailboxView`（接线归 `T-1120-09`）/`MessageWebView`/`MessageBodyStyle`/CSP/字号/白底；不新增依赖/target。`L2（无头探针）+ 构建门` |
| `T-1120-09` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：`MessageBodyView`/`MailboxView` 接线 `:300-305`、不变量 `:319-332`；`SCN-0020` 运行序 4 `:43-51`、迟到/取消 `:61-69`、`T-SCN-0020-06` `:125`；`design3.md` §4.2.4 `:398-452`、§6.2 `:597-599`、§6.3 `:658-687`；`review3.md` N2–N4 `:206-208` | `T-1120-06`、`T-1120-07`、`T-1120-08` | 已完成（2026-11-20） | `MessageBodyView`：删内联 `attachmentStrip`，`natural`/`capped` 两处改 `AttachmentStripView`；新增 `attachmentErrorText: String?`、`savingAttachmentID: String?`、`onSaveAttachment: (Attachment) async -> Void`（N3 明确 async，匹配 `AttachmentStripView.onSave`）、`onCancelSave: () -> Void`；`MailboxView`：`@MainActor`、`@State attachmentActions: AttachmentActionModel`、`init` 注入 `currentKey`/`download`、绑定 setter 与 `.onChange(of: viewModel.selectedListKey)` **两处** `syncSelection()`、传 `attachmentActions.saveErrorText ?? viewModel.attachmentErrorText` 与 `visibleSavingID`、`onOpen/onSave/onCancel`，删除内联 `NSWorkspace.open`。L2 宿主探针覆盖 `T-SCN-0020-06a/06b`（natural 100/120/145%、capped 175/225%：附件条出现、单击 0 open/0 下载、双击 1 次 open、菜单恰两项、`errorText != nil` 才 banner、无错误时高度与改造前一致 ±1pt、三档/两分支不裁剪/不挤压正文）；`T-SCN-0020-05` 编译门：`swiftc` 列表含 `AttachmentStripView.swift`、先编译 exit 0 再运行、17 用例全 PASS 且非零（N4：`commands.md` 内联 `OBJS`/变量、限定 bash；不得用 `T-SCN-0020-06` 代替）；`./Scripts/swiftw build` + `./Scripts/swiftw test` + 架构 4 门；`MessageBodyView` ≤270、`MailboxView` ≤245；`git diff` 仅两个视图文件 + `CMP-APP` 实现进度行；证据入 task-space；不改 `MessageWebView`/`MessageBodyStyle`/CSP 两档/`baseURL`/禁 JS/远程开关/信封头/截断 banner/字号分支；**不新增窗口关闭/`onDisappear` 自动取消**（N2 措辞归设计/收尾）；`MailboxView` 的绑定/`.onChange` 元素级联动仍为手工冒烟（R16），不写成 L2 通过。`L2（无头探针）+ 构建/测试门` |
| `T-1120-10` | `change`（仅测试载体） | `CMP-SCN-READ + CMP-COMP` | `SCN-0020` `T-SCN-0020-03` `:122`；`design3.md` §6.1 `:577-579`；`CMP-SCN-READ` 不可变引用（`downloadAttachment`/`FlightBoard` 语义不变）；`CMP-COMP` `FileAttachmentFiles` 无增量 | —（可与 APP/PRES 链并行；须早于 `T-1120-11`） | 已完成（2026-11-20） | 仅测试：`Tests/CompositionTests/FileAttachmentFilesTests.swift` 增 `FileAttachmentFiles(directory:maxBytes:)` 小上限（如 64 KB，**不真写 2 GB**）下 `store` 触发 prune 的用例（最旧优先、未超限不删、字节保留）；`Tests/ScenesTests/ReadSceneTests.swift` 增 `T-SCN-0020-03b`（缓存命中丢失/外部删除后 `downloadAttachment` 重新 fetch 1 次、store 1 次、`markAttachmentCached` 1 次）与 `04a`（同一附件并发 `downloadAttachment`：`fetchAttachment` 1 次、两调用同 URL）；`ScenesSupport.swift` 仅按需补 fake 能力；`./Scripts/swiftw test --filter FileAttachmentFilesTests` 与 `--filter ReadSceneTests` 绿 + 架构 4 门；`git diff --name-only` 只含 `Tests/`；不改产品代码/`ReadScene` 语义/`AttachmentFiles` 契约/`Package.swift`、不改场景/需求/状态。`L1（单元测试）` |
| `T-1120-11` | `verify` | `SCN-0020`（0 组件） | `SCN-0020` §测试 `:116-159`/§状态 `:161-170`/§边界 `:172-186`；`REQ-0026:79`；`design3.md` §6 `:564-721`；`review3.md` §4/§6 `:201-225` | `T-1120-06`…`T-1120-10` | 已完成（2026-11-20） | 实现冻结后**独立复验，不复用实现输出**：①L1 逐例 `T-SCN-0020-01a–01g`、`03a`、`03b`、`04a` + 过滤回归（`SCN-0019`/`SCN-0013`/`SCN-0018`/`SCN-0004`/`SCN-0015`/`SCN-0010`，按 `design3.md:580`）+ `./Scripts/swiftw test` 全量（记录总数，不新增失败）+ 架构 4 门；②L2 逐例 `02a–02f`、`04b`、`05`、`06a/06b`、`07`、`08a/08b`、`09`、`10a–10e`：生产 `AttachmentStripView.swift`/`AttachmentExport.swift`/`MessageBodyView.swift`/`MessageWebView`/`MessageBodyStyle` + 所需 PRES 对象，逐例原始输出；`T-SCN-0020-05` 先编译（含 `AttachmentStripView.swift`，exit 0）再跑 17 用例（全 PASS、非零；bash、OBJS 内联）；`T-SCN-0020-10` 不得用 `T-SCN-0020-08a/08b` 或 `02e/02f` 代替；`T-SCN-0020-07` 既有探针可复跑则复跑，不可用则等价断言并登记，不得静默跳过；③`git diff` 核对实现 commit 范围、`Scenes`/`Composition`/`MailDomain`/`MailStore`/`Package.swift` 零改动、无新 public（仅 `attachmentErrorText`）、无状态位翻转；④只建议翻转 `SCN-0020`→`verified`、`REQ-0026`→`delivered`、`T-1120-06`…`T-1120-11` 完成，不自行翻转；A5 真样本、真实右键/`NSSavePanel`/VoiceOver/元素级联动只登记手工残余，不写成自动化通过；N2（`SCN-0020:67`「窗口关闭」措辞与 `Task{}` 机制不一致）仅登记、不改卡，交设计/收尾按 `review3.md` N2 处置。证据入 `task-spaces/<run>/evidence/attachment-access-verify/` + `test.md`；不上 L3/L4；不改产品代码/设计产物/探针断言以迁就失败；不重跑 `make-app.sh`/发布。`L1（单元测试）+ L2（无头探针）` |

任务边界（每个任务卡的可执行边界）：

| 任务 | 允许改的范围 | 明确不做 |
|---|---|---|
| `T-1120-06` | `Sources/Presentation/MailboxViewModel.swift`、新增 `Sources/Presentation/MailboxViewModel+Attachments.swift`、新增 `Tests/PresentationTests/MailboxViewModelAttachmentTests.swift`、`Tests/PresentationTests/Support.swift`（仅夹具）、`CMP-PRES` 实现进度行（只追加）、`task-spaces/<run>/` | 不改 `download` 签名/新增其它 public；不改 `Scenes`/`MailDomain`/schema/`Package.swift`；不改场景/需求/决策记录/roadmap 状态；不做 L2/L3/L4；不翻转状态位 |
| `T-1120-07` | 新增 `Sources/uumail/AttachmentExport.swift`、`CMP-APP` 实现进度行（只追加）、`task-spaces/<run>/`（探针/命令/原始输出） | 不改 `Scenes`/`Composition`/`MailDomain`/`MailStore`/`Package.swift`/`check-architecture.sh`；不改 `MessageBodyView`/`MailboxView`（归 `T-1120-09`）；不 import 字面量 `Observation`/`Composition`/`Scenes`/`WebKit`；不新增 public/依赖/target；不把源缺失改回自动重下或加回下载阶段取消；不做 L3/L4；不翻转状态位 |
| `T-1120-08` | 新增 `Sources/uumail/AttachmentStripView.swift`、`CMP-APP` 实现进度行（只追加）、`task-spaces/<run>/` | 不改 `MessageBodyView`/`MailboxView`/`MessageWebView`/`MessageBodyStyle`/CSP/字号/白底；不下载/不读写文件/不判 `MailError`；不加「在 Finder 中显示」/分享/服务扩展；不新增依赖/target；不做 L3/L4；不翻转状态位 |
| `T-1120-09` | `Sources/uumail/MessageBodyView.swift`、`Sources/uumail/MailboxView.swift`、`CMP-APP` 实现进度行（只追加）、`task-spaces/<run>/`（含 `T-SCN-0020-05/06` 探针与证据） | 不改 `MessageWebView`/`MessageBodyStyle`/CSP 两档/`baseURL`/禁 JS/远程开关/信封头/截断 banner/字号分支；不新增窗口关闭/`onDisappear` 自动取消（N2 归设计/收尾）；不改 `Scenes`/`Package.swift`；不新增 public；不做 L3/L4；不翻转状态位 |
| `T-1120-10` | `Tests/CompositionTests/FileAttachmentFilesTests.swift`、`Tests/ScenesTests/ReadSceneTests.swift`、`Tests/ScenesTests/ScenesSupport.swift`（仅 fake 能力）、`task-spaces/<run>/` | 不改产品代码/`ReadScene` 语义/`AttachmentFiles` 契约/`Package.swift`；不改场景/需求/决策记录/roadmap 状态；不做 L2/L3/L4；不翻转状态位 |
| `T-1120-11` | `task-spaces/<run>/`（`test.md` + `evidence/attachment-access-verify/`；探针源码只放 task-space）；`Tests/` 仅在测试缺口时补测试并单独一次测试 commit | 不改产品代码/设计产物/需求/场景/门状态；不自行翻转 `verified`/`delivered`/任务完成；不读真实邮件库、不写真实主题/发件人/URL/账号/正文；不做 L3/L4；不重跑 `make-app.sh`/发布动作 |

共同约束：每个 change 一个实现 commit，message 带 `T-` 与 `SCN-`；L2 探针文件名/组合由实现按 `commands.md` 落定（出口以用例 ID 与生产源断言为准，不得删/放宽断言）；规格实现进度行随实现 commit 只追加，不改规则/数值/验收；若需改契约/形状/测试断言，回设计，不在任务里自行扩。越权清单按 `af-flow-rule` §4：改设计产物、自授权人工门、发布动作、出口外探针，发现即停手并在 `dev.md` 记「超出任务范围」。

并行关系：`T-1120-06`（`CMP-PRES`）、`T-1120-07`（`CMP-APP` 链首）、`T-1120-10`（仅 `Tests/`）三者互不共享文件/契约，可并行；APP 链 `T-1120-07`→`T-1120-08`→`T-1120-09` 必须串行（组件级 WIP=1；`T-1120-08` 虽无编译依赖也不并行第二个 `CMP-APP` 任务）；`T-1120-09` 另依赖 `T-1120-06` 的 `attachmentErrorText`；`T-1120-11` 在全部之后，验证不跳步、不复用实现输出。

**条件与回退**：若 `T-1120-06` 发现必须改 `download` 签名或新增 G1 之外的 public → 停下回设计/按 `auto-confirm` §3 确认；若 `T-1120-07` 编译期确需显式 `import Observation` 或需改架构门白名单 → 停下回设计/架构（规则变更，需确认），不静默改 `check-architecture.sh`；若 `T-1120-07` 发现 `AttachmentActionModel` 必须读 `Presentation` internal `selectionGeneration`、或需 `Scenes` 暴露新取消接线 → 停下回设计（A1/C1 边界）；若 `T-1120-08`/`T-1120-09` 发现必须动 `MessageWebView`/CSP/`baseURL`/JS → 停下回设计（安全面/契约变更）；若 `T-1120-09` 需要第三个 `syncSelection` 接线点或视图状态归属改变 → 停下回设计（机制 A1 边界）；若 `T-1120-10` 为让 `03b/04a` 通过而必须改产品代码 → 停下按缺陷/设计处理（`Scenes` 零改动承诺）；若验证节点无法用生产源编译探针 → 按 `design3.md` §6.3 调整对象列表后重试，仍不可行回设计改测试载体或声明 L3，**不得**用 L1 冒充、不得删断言；N2（「窗口关闭」措辞）不在实现里补自动取消接线，由设计/收尾按 `review3.md` N2 处置。回退＝反向回退实现 commit；本批无 schema/数据迁移；`SCN-0020` 在验证通过前保持 `designed`，回退/重跑轮次不翻转状态位。

本批统一验证命令：`./Scripts/swiftw build`、`./Scripts/swiftw test`、`bash Scripts/check-architecture.sh`；单任务过滤用 `./Scripts/swiftw test --filter PresentationTests` / `--filter ScenesTests` / `--filter FileAttachmentFilesTests`；L2 探针按各任务 `commands.md` 编译**生产**源（`AttachmentStripView.swift`/`AttachmentExport.swift`/`MessageBodyView.swift`/`MessageWebView`/`MessageBodyStyle.swift`）并逐例 `tee` 原始输出，证据入 `task-spaces/<run>/evidence/attachment-access-verify/`。

拆分复核（2026-11-20）：每个任务在「规格锚点」列指到组件规格/场景卡的具体行；依赖无环（三起点 + APP 单链 + 汇聚）；出口含可执行 ID/命令/期望值/文件/证据位置与最低证据层级（`L1`/`L2` 自描述）；已落本表。本批新增 6 个任务（5 change + 1 verify），不按文件/工时拆；`T-1120-07`/`T-1120-08`/`T-1120-09` 同组件串行是 WIP=1 的必要约束。本拆分 docs commit 用追踪号 `T-1120-06..11` 与 `SCN-0020`（不代表新增任务）。拆分过程、S1–S6 默认确认（未经人工）、边界与风险见 `task-spaces/20261120-160446/split.md`。

### 装载清单（2026-11-20 W-M3-13 拆分）

| 任务 | 必读 | 预计装载 | 备注 |
|---|---|---|---|
| `T-1120-06` | `CMP-PRES` 增量 `:476-505`；`design3.md` §4.2.1/§6.1；`SCN-0020` 失败路径/迟到 `:52-69,84-91`；`MailboxViewModel.swift`（385 行）、`MailboxViewModel+Body.swift`（140 行）、`MailboxViewModel+Delete.swift`（62 行）；`Tests/PresentationTests/Support.swift`（308 行）、`MailboxViewModelTests.swift` 风格参考 | ~1,200 行 | 只加一个 public 只读成员；`download` 签名不变；01f/01g 需可控 continuation |
| `T-1120-07` | `CMP-APP` 增量 `:306-332`；`design3.md` §4.2.2/§4.2.3/§6.2/§6.3；`design2.md` §4.2.3（异步复制/取消语义）；`SCN-0020` 运行序 3–6/失败路径；`ErrorText.swift`（14 行）、`Attachment`/`AttachmentRef` 类型；既有 `evidence/attachment-save-probe/` 与 `InlineImageVerifyProbe` 的 `commands.md` 风格 | ~1,300 行 | 面板/复制/保存流/gate/动作模型一文件；≤300 行；import 白名单见任务卡；证据逐例 |
| `T-1120-08` | `CMP-APP` 增量 `:291-299`；`design3.md` §4.2.5/§6.2 `02a–02d/04b`；`design2.md` §4.2.2（AX/选中态/菜单）；`SCN-0020:20-36,93`；`MessageBodyView.swift`（259 行，样式参考）、`FontSizeStyle.swift`（106 行）、`MessageBodyStyle.swift`（41 行） | ~800 行 | 只呈现/转发；不碰宿主；banner 结构断言 |
| `T-1120-09` | `CMP-APP` 增量 `:300-305,319-332`；`design3.md` §4.2.4/§6.2/§6.3；`SCN-0020:43-51,61-69,125`；`MailboxView.swift`（219 行）、`MessageBodyView.swift`（259 行）、`test-spaces/20261120-111818/evidence/inline-image-verify/`（探针/命令） | ~1,500 行 | 两处 `syncSelection` + 4 参数；`T-05` 先编译后运行、17 用例非零 |
| `T-1120-10` | `SCN-0020:122`；`design3.md` §6.1 `03a/03b/04a`；`Tests/CompositionTests/FileAttachmentFilesTests.swift`（80 行）、`Tests/ScenesTests/ReadSceneTests.swift`（约 300 行）、`ScenesSupport.swift`（约 350 行）；`ReadScene.swift:173-231` 只读 | ~900 行 | 仅 `Tests/`；小上限 64 KB；并发单飞 |
| `T-1120-11` | `SCN-0020` §测试/§状态/§边界 `:116-186`；`REQ-0026:79`；`design3.md` §6 `:564-721`；`review3.md` §4/§6 `:201-225`；各任务探针源码/`commands.md`/原始输出；`SCN-0019`/`SCN-0013`/`SCN-0018`/`SCN-0004`/`SCN-0015`/`SCN-0010` 回归清单 | ~1,900 行 | 独立重编生产源；逐 ID；不复用实现输出；只建议翻转 |

装载纪律：单任务 ≤2,000 行；若 `T-1120-09`/`T-1120-11` 装载超限，先停下按批次纪律重拆，不静默扩大；所有任务另读 `doc/design/architecture.md` §2/§3/§4 的相关段落（约 120 行）并核对依赖方向未变。

## W-M3-14 任务表（内联图片 ContentId 持久化，2026-11-21）

来源：`REQ-0025` 重开（真实样本证伪「网关不返回 `ContentId`」的前提），决策 `history/decisions/2026-11-21-inline-image-content-id.md`
（**P1**：核心 schema + 公开契约；人工确认 2026-11-21：C1、旧邮件重同步生效、内联附件保留、需持久化）。

| ID | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1121-02` | change | `CMP-EAS` | `CMP-EAS/spec.md` §设计增量（2026-11-21，附件 ContentId） | — | 已完成（2026-11-21） | `EASAttachment.contentID` + `parseMessage` 读 `ContentId`；`EASClientTests` 解析断言 |
| `T-1121-03` | change | `CMP-DOMAIN` | `CMP-DOMAIN/spec.md` §设计增量（2026-11-21） | `T-1121-02` | 已完成（2026-11-21） | `Attachment.contentID`（默认 `nil`，兼容扩展）；`EASAdapter` 映射 |
| `T-1121-04` | change | `CMP-STORE` | `CMP-STORE/spec.md` §设计增量：附件 ContentId | `T-1121-03` | 已完成（2026-11-21） | v11 `attachments.content_id`；upsert 用 `COALESCE`；`attachments(...)` 读回；迁移/round-trip 测试 |
| `T-1121-05` | change | `CMP-SCN-READ` | `CMP-SCN-READ/spec.md` §设计增量 2026-11-21 增量 | `T-1121-03`、`T-1121-04` | 已完成（2026-11-21） | `InlineImageHTML.matches` 先按 `contentID`；名字规则回退；歧义跳过；`InlineImageHTMLTests` / `ReadSceneInlineImageTests` |
| `T-1121-06` | verify | `SCN-0019` | `SCN-0019` §测试/§状态 | `T-1121-02`…`T-1121-05` | 已完成（2026-11-21） | `T-SCN-0019-01..05` L1 全绿、`368 tests / 58 suites`、架构 4/4；`SCN-0019` 转回 `verified` |

装载纪律：本批四张 change 互相依赖（编译面），按顺序一次交付一个组件测试；不改协议命令、不新增 target/依赖。

## W-M3-15 任务表（正文宽表适配与附件条内联图过滤，2026-11-23）

来源：`REQ-0027`/`REQ-0028`（`accepted`）、`SCN-0021`（`mail/read/html-table-layout`）/`SCN-0022`（`mail/read/attachment-strip-inline-filter`，均 `designed`）、
设计 `task-spaces/20261123-table-adapt/design.md`、决策 `history/decisions/2026-11-23-table-adapt-inline-attachment-filter.md`
（人工确认 2026-11-23：表格压缩适配 + 附件条隐藏内联图；取代 `REQ-0025` 2026-11-21 澄清③）。

**设计边界（不改）**：表格只改 `MessageBodyStyle.baseCSS`（`table[width], table[style*="width" i] { display:block; max-width:100%; overflow-x:auto }`），
不启用 JS、不改 CSP/`baseURL`/禁 JS/白底/`pageZoom`/`lastRender`/撰写页；附件条只在 PRES 做展示投影，`ReadScene.attachments(for:)` 与
`renderInlineImages` 仍用全量，不改 schema/`MailDomain`/`MailStore`/EAS/`Composition`/`Package.swift`。定级：REQ-0027 **P3**、REQ-0028 **P2**
（additive public `InlineImageReferences.attachmentIDs`，人工确认见决策记录）。

| 任务 | 类型 | 组件 | 规格锚点 | 依赖 | 状态 | 出口 |
|---|---|---|---|---|---|---|
| `T-1123-01` | `design` | —（0 组件） | `REQ-0027`/`REQ-0028`、`SCN-0021`/`SCN-0022`、`CMP-{APP,PRES,SCN-READ}` 设计增量、决策记录 | — | 已完成（2026-11-23） | 两卡两场景落盘、设计简报与决策记录落盘、本任务表落盘 |
| `T-1123-02` | `change` | `CMP-SCN-READ` | `CMP-SCN-READ/spec.md` §设计增量：附件条内联图过滤；`SCN-0022` 运行序 2/入口 | `T-1123-01` | 已完成（2026-11-23） | `InlineImageReferences.attachmentIDs` additive public；`InlineImageHTMLTests` 新增 4 例；`swiftw test --filter ScenesTests` 绿；不新增依赖/target |
| `T-1123-03` | `change` | `CMP-PRES` | `CMP-PRES/spec.md` §设计增量：附件条内联图投影；`SCN-0022` 运行序 2–4 | `T-1123-02` | 待开始 | `startInlineImageRender` 过滤 `attachments`；`MailboxViewModelInlineImageTests` 新增 4 例；`swiftw test --filter PresentationTests` 绿；不改 `download`/`openSelected` 签名 |
| `T-1123-04` | `change` | `CMP-APP` | `CMP-APP/spec.md` §设计增量：正文宽表格适配；`SCN-0021` 运行序 2–5 | `T-1123-01` | 待开始 | `baseCSS` 宽表规则；`TableLayoutProbe` L2 四例 PASS；`swiftw build` + 架构 4 门；不改 CSP/JS/`baseURL` |
| `T-1123-05` | `verify` | `SCN-0021`/`SCN-0022` | 两张场景 §测试/§状态；`REQ-0027`/`REQ-0028` 验收归属 | `T-1123-02`…`T-1123-04` | 待开始 | `T-SCN-0021-01..04` L2 + `T-SCN-0022-01..04` L1 逐例 PASS；全量 `swiftw test`/架构 4 门；`make-app.sh` 成功；翻转两场景 `verified`、两需求 `delivered` |

**验证命令**：`./Scripts/swiftw test --filter ScenesTests`、`./Scripts/swiftw test --filter PresentationTests`、`./Scripts/swiftw test`、
`bash Scripts/check-architecture.sh`、`./Scripts/make-app.sh`；L2 `TableLayoutProbe` 编译生产 `MessageBodyStyle.swift`，原始输出入
`task-spaces/20261123-table-adapt/evidence/`。

**装载清单**：`MessageBodyStyle.swift`、`InlineImageHTML.swift`、`MailboxViewModel+Body.swift`、`MailboxViewModel.swift`、`AttachmentStripView.swift`、
`MessageBodyView.swift`、`Tests/ScenesTests/InlineImageHTMLTests.swift`、`Tests/PresentationTests/MailboxViewModelInlineImageTests.swift`、
`Tests/PresentationTests/Support.swift`、`doc/design/components/CMP-{APP,PRES,SCN-READ}/spec.md`、两张场景卡；单任务 ≤120k、不开新组件。

**并行/WIP**：`T-1123-02`（`CMP-SCN-READ`）→ `T-1123-03`（`CMP-PRES`）串行；`T-1123-04`（`CMP-APP`）可与二者并行（不同组件、无共享文件）；`T-1123-05` 在全部之后，验证不复用实现输出。
**条件与回退**：表格规则若需改 CSP/JS 或 HTML 包裹 → 停下回设计（用户已选压缩）；过滤若需改 `MailDomain`/schema/`ReadScene.attachments` 语义 → 停下回设计/确认；回退 = 反向回退实现 commit，无数据迁移。

## 批次纪律

- 每个工序一次立一个 `works/` 目录；2026-11-14 起过程记录放工作区 `task-spaces/<run>/`，**任务表写在本文件对应工序节**，brief 只保留当次分析/范围，不维护第二份现行任务表；一个任务一个对话。
- 组件级 WIP=1：同一时刻只有一个在飞任务改同一组件。
- M1 未通过前不启动 M2；M2 与 M3 可并行但共享 CMP-SYNC，需错峰。
