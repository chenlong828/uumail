# uumail 文档

> **文档根 = `doc/`**。本文及树内文档里的 `requirements/…`、`design/…`、`plan/…`、`history/…` 路径都相对本目录；在仓库根使用时要加 `doc/` 前缀。代码在仓库根的 `Sources/`、`Tests/`。

macOS 原生邮件客户端，只走 Exchange ActiveSync（以「一台已登记的 iPhone」身份接入公司 Exchange）。首版范围已确认；2026-11-14 完成场景收口与分层重构（9 个库 target + 2 个可执行 target），功能里程碑 M1/M2/M3 仍在进行。

## 阅读顺序

1. [architecture.md](design/architecture.md) — 现行分层、target、九条核心契约、冷热路径、组合根规则、D1–D10 决策与实施阶段。先读这一篇。
2. [CMP-EAS 规格](design/components/CMP-EAS/spec.md) 与 [接入 playbook](design/components/CMP-EAS/playbook.md) — 服务器接入的契约、实测线格式与排障顺序；这是本项目最确定的一层。
3. 组件规格（`design/components/`）：`CMP-DOMAIN`（值类型/端口）、`CMP-STORE`（数据）、`CMP-SYNC`、`CMP-OUT`、`CMP-EASADAPTER`、`CMP-SCN-{ACCOUNT,SYNC,READ,COMPOSE}`、`CMP-PRES`、`CMP-ROOT`、`CMP-CLI`、`CMP-APP`。
4. [design/scenarios/](design/scenarios/) — 业务功能树 `mail/{access,receive,read,send}/<场景>`，运行序、入口与测试证据。
5. [roadmap.md](plan/roadmap.md)、[risks.md](plan/risks.md)、[open-questions.md](plan/open-questions.md) — 里程碑、风险、待拍板项。
6. [requirements/](requirements/) — 每个用户可感知动作一张卡（REQ-0001…0012）。
7. [history/](history/) — 已归档的[范围与关键决策](history/decisions/2026-11-09-scope-baseline.md)、[附件缓存上限](history/decisions/2026-11-09-attachment-cache-cap.md)、[正文契约 D10](history/decisions/2026-11-13-fetched-body-contract.md)、[EAS 探针](history/works/2026-11-09-eas-probe/result.md)、[M1 账号接入](history/works/2026-11-09-m1-account-access/result.md)、[M4 加固](history/works/2026-11-09-m4-hardening/result.md)、[场景重构收口](history/works/2026-11-10-scene-refactor/result.md)。只作记忆，不作设计依据。

## 入口

- **现在能回答什么**：能不能用 EAS 收信发信？能，见 playbook 的能力矩阵。现在是什么结构？9 个库 target + 2 个可执行，四条业务流各一个场景类，发信入队后由 `Outbox` 冷投递。测试与门禁？`./Scripts/swiftw test` 169 tests / 37 suites 全绿，`bash Scripts/check-architecture.sh` 4 门全过。首版做什么？单账号、最小策略握手、本机联系人、不做 OAuth（2026-11-09 确认）。
- **还不能回答什么**：真机 `uumailctl diagnose/sync/send` 与 App live bootstrap 未在收口会话验证；7 张场景卡仍是 `designed`（逐项原因见各卡）；附件 25MB/续传/名称回退、已读回写、Sent 镜像、outbox UI 角标、全部回复的收件人/抄送预填（REQ-0012，SCN-0007 已 `designed`）未实现；`PendingOps` 时机、本地保留策略（Q1）、App/CLI 双跑租约（Q3）、单账号替换（Q4）未定。MoveItems 未验证。
- **下一步**：先做真机冒烟（诊断、同步、发送、App 启动一次真实 bootstrap），再补 outbox 待发/失败角标；之后按 `plan/roadmap.md` 把 M1/M2/M3 场景卡逐项转 `verified`，全部回复预填按 W-M2-03 推进（`SCN-0007` 已 `designed`；`T-1114-02`、`T-1114-03`、`T-1114-04` 已完成，其余 change 待 P1 确认）。结构变更走工作区 `task-spaces/<run>/` 工序与决策记录。

## 目录约定

| 目录 | 状态 | 只回答 |
|---|---|---|
| `requirements/` | 需求 | 为什么做 |
| `plan/` | 调度 | 接下来做什么 |
| `design/` | 现行真相 | 系统现在是什么 |
| `works/` | 执行 | 历史工序归档位置；2026-11-14 起新工序的任务表与过程记录放工作区 `task-spaces/<run>/`，`works/` 只保留历史 |
| `history/` | 记忆 | 怎么走到这里的（冻结只读） |

凭据与设备 ID 不入库：运行时值放 `.env` 或 Keychain，文档只描述形状。
