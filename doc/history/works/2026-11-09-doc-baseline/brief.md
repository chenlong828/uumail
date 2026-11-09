---
layer: history
module: global
status: frozen
updated: 2026-11-09
---

# W-2026-11-09-doc-baseline 工序简报

> 已归档。文档整理是旁路工序，不建需求卡；本文件是过程记忆，现行文档见 `README.md` 的阅读顺序。

## 需求

把散落的架构草案整理成符合 doc-layout-spec 的文档树：五态分离、frontmatter 齐全、导航不靠登记表；并把 `~/working/公网邮箱访问` 里已验证的 Exchange/EAS 接入事实，按「设计真相 + 组件手册」落位，而不是当成需求或坑档案。

## 背景

整理前仓库只有一份 `design/architecture.md`（P1 草案），其中 EAS 接入部分是按规范写的假设；而探针已在真实公司网关跑通，实测结论与草案有冲突（自动发现不可用、DeviceId 不能自造、字符串编码与 MIME 承载方式不同）。不校正就会把错误前提冻结进契约。

## 验收标准

- 五态目录各就各位：`requirements/`、`plan/`、`design/`、`works/`、`history/`；不建空文件。
- 每份文档带 frontmatter，`layer` 与路径一致；README 只写阅读顺序与入口。
- 架构草案按实测校正：接入章节、DeviceProfile、错误映射、M0 状态。
- 探索结论落在组件范围内（`CMP-EAS/spec.md` + `playbook.md`），不写进坑档案。
- 文档不含账号、密码、设备 ID、主机名等运行时值。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| T-DOC-01 | design | 全局 | done | architecture.md、doc-layout-spec、arch-design-spec |
| T-DOC-02 | design | CMP-EAS | done | 探针实测记录、EAS 客户端对照、架构草案 §7 |
| T-DOC-03 | design | 全局 | done | req-scenario-spec、现有能力表 |
| T-DOC-04 | verify | 全局 | done | frontmatter 校验、链接校验、敏感值扫描 |

## 边界

- 只整理与落位，不新增实现，不改探针代码。
- 探针目录的 `.env`、`output/`、`logs/` 不复制；文档只保留形状描述与引导路径。
