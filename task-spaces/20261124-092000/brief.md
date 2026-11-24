# W-M3-16 日历视图与会议卡 — 工序 brief

- 工序：`W-M3-16`（M3；设计已确认，实现待启动）
- 当前任务：`T-1124-01`（落盘）与 `T-1124-02`（P1 确认门）已完成；实现从 `T-1124-03` 开始
- 任务表：`doc/plan/roadmap.md` §W-M3-16（唯一现行任务表，本 brief 不复制）

## 需求与背景

2026-11-24 探索「收到的会议邀请」时实证：

- 样本「【会议预告】AI时代的软件工程迭代和岗位变迁」在 EAS 上是 `IPM.Schedule.Meeting.Request` + 完整 `MeetingRequest`（09:30–12:00、C4519、王权英、`Bias=-480`），但客户端只当普通 HTML 邮件显示；
- `ItemOperations` 要 MIME（`BodyPreference Type=4`）也只回 HTML，`text/calendar` 原文不可得；全库 `.ics` 附件为 0；
- 「钉钉日程」每周邀请同形状（`MeetingMessageType=1`），说明按时间聚合是日常需求；
- 复制库实测 `PRAGMA journal_mode = delete`，与文档「WAL + FTS5」不一致。

## 范围（2026-11-24 逐项确认）

- 需求：`REQ-0029`（日历月/周视图）、`REQ-0030`（会议卡 + `.ics` 导出），均 `accepted`。
- 场景：`SCN-0024`（`calendar/browse/calendar-grid`）、`SCN-0023`（`mail/read/meeting-card`），均 `designed`。
- 组件：新 `CMP-SCN-CALENDAR`、`CMP-OUTBOX-STORE`（均 `planned`）；`CMP-EAS`/`CMP-DOMAIN`/`CMP-EASADAPTER`/`CMP-STORE`/`CMP-OUT`/`CMP-PRES`/`CMP-APP`/`CMP-ROOT` 各一条增量。
- 不做：不同步日历集合、不接受/拒绝、不调 `MeetingResponse`、不建/改/删日程、无冲突/提醒/日视图/年视图、不引入 EventKit、不处理附件 `.ics`、**不回填历史邀请**。

## 已确认决策（详见 `doc/history/decisions/2026-11-24-calendar-view-scope.md`）

| 决策 | 结论 |
|---|---|
| 数据源 / 动作 / 重复 | 只展示收到的邀请；只读 + 「在日历中打开」；完整展开重复 |
| 结构 | 新场景组件（住 `Scenes`）；`MailDomain` 承载会议类型；独立 `meetings` 表按 `UID`；public 视图模型；新领域 `calendar` |
| 存储预算 | **先拆 outbox** 到 `CMP-OUTBOX-STORE`（同一 SQLite + 同一队列），`MailStore` 回 1000 内；账号/文件夹另立 `W-REFACTOR-02` |
| 运行环境 | SQLite 启用 **WAL**（`Configuration.journalMode = .wal`，单队列） |
| 时区 | 固定偏移 + 事件详情标注（DST 精确另立 Q5） |
| 回填 | **不回填**；升级后日历为空、旧邀请无会议卡（已二次确认） |
| 排序 | 同一 `UID` 按 `DtStamp` 只升不降 |
| 例外 | `InstanceType=3` 合并进系列 |
| 验收 | L2 探针先证 seam；失败则场景声明 L3 并留证据 |
| 网关缺字段 | 退化为普通邮件 + 空态提示，不猜正文时间 |

## 验收标准（实现期）

- `T-SCN-0024-01..04` 与 `T-SCN-0023-01..04`（各 3 正 1 反）PASS；
- 全量 `./Scripts/swiftw test`、`bash Scripts/check-architecture.sh` 4 门、`./Scripts/make-app.sh`；
- 回归 `SCN-0003`/`SCN-0004`/`SCN-0012` 不退化；两场景 `verified`、两需求 `delivered`；
- 预算：`MailStore` ≤1000、`OutboxStore` ≤400、`CalendarScene` ≤260、`CalendarView` ≤300。

## 风险

R56（DST 偏移）、R57（旧邀请覆盖）、R58（不回填导致空日历）、R59（L2 seam）、R60（网关缺字段）、R61（WAL 副文件/备份）；见 `doc/plan/risks.md`。
