---
layer: history
module: global
status: frozen
updated: 2026-11-09
---

# W-2026-11-09-doc-baseline 结果

## 验收结果

| 项 | 结论 | 证据 |
|---|---|---|
| 五态目录 | ✅ | `requirements/` 11 卡、`plan/` 3 份、`design/` 架构 + 4 组件 + 6 场景、`history/works/` 2 个归档工序；`works/` 留空（无在飞工序） |
| frontmatter | ✅ | 29 份 md 全部带 `layer/status/updated`，`layer` 与路径一致；组件带 `component`，场景带 `flow`/`scenario` |
| 导航 | ✅ | `README.md` 只有阅读顺序与入口，无逐文件状态表 |
| 实测校正 | ✅ | architecture §0/§1/§4/§7/§10/§12、CMP-EAS 规格、playbook 已按探针结论改写 |
| 探索结论落位 | ✅ | 结论进 `CMP-EAS/spec.md` 与 `playbook.md`；未建 `history/pitfalls.md`（按用户意见，探索属组件事实，不是坑） |
| 敏感值 | ✅ | 用探针 `.env` 的实际值扫描 29 份文档，命中 0 |

## 结论落点

| 结论 | 落点 |
|---|---|
| 服务器接入事实（拓扑、请求骨架、线格式、能力矩阵） | `design/components/CMP-EAS/playbook.md` |
| 错误映射、命令契约、验证计划 | `design/components/CMP-EAS/spec.md` |
| 架构层摘要与修正（Autodiscover 不可用、DeviceId 不可自造、Sync 最小体） | `design/architecture.md` §1、§4、§7 |
| 用户可感知需求 | `requirements/REQ-0001…0011` |
| 业务功能树与测试方案 | `design/scenarios/mail/{access,receive,read,send}/` |
| 里程碑、风险、待拍板 | `plan/roadmap.md`、`plan/risks.md`、`plan/open-questions.md` |
| 探针过程与根因 | `history/works/2026-11-09-eas-probe/` |

## 未做 / 遗留

- 场景卡全部 `draft`（测试 ID 无 harness 承载），等 M1 首个 design 任务转 `designed`。
- 需求卡全部 `draft`，待用户确认首版范围后转 `accepted`。
- `design/scenarios/_index.md` 未生成（无生成脚本），首个工序落地时补工具。
- `works/` 无在飞工序，首个工序立项时创建。
- Ping、MoveItems 未验证；抓包脱敏入仓在同日范围确认中已定为「脱敏后入库」。
