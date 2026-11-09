# uumail 文档

> **文档根 = `doc/`**。本文及树内文档里的 `requirements/…`、`design/…`、`plan/…`、`history/…` 路径都相对本目录；在仓库根使用时要加 `doc/` 前缀。代码在仓库根的 `Sources/`、`Tests/`。

macOS 原生邮件客户端，只走 Exchange ActiveSync（以「一台已登记的 iPhone」身份接入公司 Exchange）。首版范围已确认，进入 M1 开发；代码在仓库根，文档在本目录。

## 阅读顺序

1. [architecture.md](design/architecture.md) — 系统边界、分层组件、四张核心契约、冷热路径。P1 设计，关键决策已确认。
2. [CMP-EAS 规格](design/components/CMP-EAS/spec.md) 与 [接入 playbook](design/components/CMP-EAS/playbook.md) — 服务器接入的契约、实测线格式与排障顺序；这是本项目最确定的一层。
3. [roadmap.md](plan/roadmap.md)、[risks.md](plan/risks.md)、[open-questions.md](plan/open-questions.md) — 里程碑、风险、待拍板项。
4. [requirements/](requirements/) — 每个用户可感知动作一张卡（REQ-0001…0011）。
5. [design/scenarios/](design/scenarios/) — 业务功能树 `mail/{access,receive,read,send}/<场景>`。
6. [history/](history/) — 已归档的[范围与关键决策](history/decisions/2026-11-09-scope-baseline.md)、[EAS 探针](history/works/2026-11-09-eas-probe/result.md)、[文档基线](history/works/2026-11-09-doc-baseline/result.md)。只作记忆，不作设计依据。

## 入口

- **现在能回答什么**：能不能用 EAS 收信发信？能，见 playbook 的能力矩阵。首版做什么？单账号、最小策略握手、本机联系人、不做 OAuth（2026-11-09 确认）。
- **还不能回答什么**：Ping、MoveItems 未验证；本地保留策略与附件缓存上限未定（`plan/open-questions.md`）。
- **下一步**：W-M1-03 收件箱增量同步（`Sync` 命令 + 消息表 + SyncEngine）。W-M1-01 的协议与落库已完成，UI 与账号状态机待补。

## 目录约定

| 目录 | 状态 | 只回答 |
|---|---|---|
| `requirements/` | 需求 | 为什么做 |
| `plan/` | 调度 | 接下来做什么 |
| `design/` | 现行真相 | 系统现在是什么 |
| `works/` | 执行 | 正在做什么（当前为空，首个工序立项时创建） |
| `history/` | 记忆 | 怎么走到这里的（冻结只读） |

凭据与设备 ID 不入库：运行时值放 `.env` 或 Keychain，文档只描述形状。
