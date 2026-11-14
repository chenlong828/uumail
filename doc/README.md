# uumail 文档

> **文档根 = `doc/`**。本文及树内文档里的 `requirements/…`、`design/…`、`plan/…`、`history/…` 路径都相对本目录；在仓库根使用时要加 `doc/` 前缀。代码在仓库根的 `Sources/`、`Tests/`。

macOS 原生邮件客户端，只走 Exchange ActiveSync（以「一台已登记的 iPhone」身份接入公司 Exchange）。首版范围已确认；2026-11-14 完成场景收口与分层重构（9 个库 target + 2 个可执行 target），功能里程碑 M1/M2/M3 仍在进行。同日追加 `REQ-0013`（列表停留自动已读）与 `REQ-0014`（列表键盘删除），均 `accepted`，纳入 W-M3-03；实现已完成（T-1114-11…18/21，2026-11-14），`SCN-0008`/`SCN-0009` 仍 `designed`，待 T-1114-19/20 验证；写路径 P1 frozen 记录与 R16 真机样本仍缺。

## 阅读顺序

1. [architecture.md](design/architecture.md) — 现行分层、target、九条核心契约、冷热路径、组合根规则、D1–D10 决策与实施阶段。先读这一篇。
2. [CMP-EAS 规格](design/components/CMP-EAS/spec.md) 与 [接入 playbook](design/components/CMP-EAS/playbook.md) — 服务器接入的契约、实测线格式与排障顺序；这是本项目最确定的一层。
3. 组件规格（`design/components/`）：`CMP-DOMAIN`（值类型/端口）、`CMP-STORE`（数据）、`CMP-SYNC`、`CMP-OUT`、`CMP-EASADAPTER`、`CMP-SCN-{ACCOUNT,SYNC,READ,COMPOSE}`、`CMP-PRES`、`CMP-ROOT`、`CMP-CLI`、`CMP-APP`。
4. [design/scenarios/](design/scenarios/) — 业务功能树 `mail/{access,receive,read,send}/<场景>`，运行序、入口与测试证据。
5. [roadmap.md](plan/roadmap.md)、[risks.md](plan/risks.md)、[open-questions.md](plan/open-questions.md) — 里程碑、风险、待拍板项。
6. [requirements/](requirements/) — 每个用户可感知动作一张卡（REQ-0001…0014）。
7. [history/](history/) — 已归档的[范围与关键决策](history/decisions/2026-11-09-scope-baseline.md)、[附件缓存上限](history/decisions/2026-11-09-attachment-cache-cap.md)、[正文契约 D10](history/decisions/2026-11-13-fetched-body-contract.md)、[EAS 探针](history/works/2026-11-09-eas-probe/result.md)、[M1 账号接入](history/works/2026-11-09-m1-account-access/result.md)、[M4 加固](history/works/2026-11-09-m4-hardening/result.md)、[场景重构收口](history/works/2026-11-10-scene-refactor/result.md)。只作记忆，不作设计依据。

## 入口

- **现在能回答什么**：能不能用 EAS 收信发信？能，见 playbook 的能力矩阵。现在是什么结构？9 个库 target + 2 个可执行，四条业务流各一个场景类，发信入队后由 `Outbox` 冷投递。测试与门禁？`./Scripts/swiftw test` 239 tests / 44 suites 全绿，`bash Scripts/check-architecture.sh` 4 门全过。首版做什么？单账号、最小策略握手、本机联系人、不做 OAuth（2026-11-09 确认）。
- **还不能回答什么**：真机 `uumailctl diagnose/sync/send` 与 App live bootstrap 未在收口会话验证；9 张场景卡中 8 张仍是 `designed`，`SCN-0007` 已 `verified`（全部回复 3 正 1 反组件级全绿，真机 UI 冒烟已完成）；附件 25MB/续传/名称回退、Sent 镜像、outbox UI 角标未实现；`SCN-0008`/`SCN-0009` 已 `designed`（2026-11-14，T-1114-10 第 2 轮），实现与 R16 真机证据已完成（T-1114-11…18/21，239 tests / 44 suites），待 T-1114-19/20 验证；P1 frozen 记录已归档；全部回复的 Cc 采集、本地读写、种子构建、视图模型与工具栏已由 `T-1114-02..09` 落地并验收；`PendingOps` 时机、本地保留策略（Q1）、App/CLI 双跑租约（Q3）、单账号替换（Q4）未定。MoveItems 未验证。
- **下一步**：先做真机冒烟（诊断、同步、发送、App 启动一次真实 bootstrap），再补 outbox 待发/失败角标；之后按 `plan/roadmap.md` 把 M1/M2/M3 剩余场景卡逐项转 `verified`。W-M2-03（全部回复）已完成：`SCN-0007` `verified`（含真机 UI 冒烟）、REQ-0012 `delivered`。W-M3-03（列表已读与键盘删除）已实现并补齐 R16 真机、焦点/前台探针与 P1 frozen 记录（2026-11-14，T-1114-11…18/21）：`SCN-0008`/`SCN-0009` 仍 `designed`，按 `plan/roadmap.md` §W-M3-03 跑 T-1114-19/20 验证后再建议翻转。结构变更走工作区 `task-spaces/<run>/` 工序与决策记录。

## 目录约定

| 目录 | 状态 | 只回答 |
|---|---|---|
| `requirements/` | 需求 | 为什么做 |
| `plan/` | 调度 | 接下来做什么 |
| `design/` | 现行真相 | 系统现在是什么 |
| `works/` | 执行 | 历史工序归档位置；2026-11-14 起新工序的任务表与过程记录放工作区 `task-spaces/<run>/`，`works/` 只保留历史 |
| `history/` | 记忆 | 怎么走到这里的（冻结只读） |

凭据与设备 ID 不入库：运行时值放 `.env` 或 Keychain，文档只描述形状。
