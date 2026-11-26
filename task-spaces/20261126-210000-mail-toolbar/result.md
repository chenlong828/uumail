---
layer: works
module: mail
scope: project:uumail
status: closed
updated: 2026-11-26
---

# W-M3-22 结果：主窗口顶栏分组

## 交付

- `ae8b9d0` `fix(toolbar): window-level mail actions pinned to the trailing edge (REQ-0042)`
  - `MailboxView.swift`（298 行）：七个动作从 `mailListColumn` 的 `.toolbar` 迁到根视图 `.toolbar`，`mailboxToolbar` 为 `@ToolbarContentBuilder` 计算属性；`ToolbarTooltipInstaller` 改挂根视图背景。
  - `ToolbarTooltips.swift`（92 行）：`installTooltips(in:)` + `pinActionGroupToTrailingEdge(in:)`（插 `.flexibleSpace`、删搜索前多余 `.flexibleSpace`、幂等）。
- `8904366` `test(store): make the 30-day window fixture time-relative`——修正 `PerformanceTests` 的固定 10 月日期（2026-11-26 后落入 30 天窗口外，属时间炸弹，与功能无关但阻塞全量验收）。

## 验收

- `./Scripts/swiftw test`：**466 tests / 77 suites** 全绿；`bash Scripts/check-architecture.sh`：**4/4 PASS**。
- L2（`probe/`，生产 `MailboxToolbar` + `ToolbarTooltips`）：
  - `final-1512.png` / `final-layout.txt`：1512pt 下三段在左、标题居中、七个动作在 x≈898..1169 紧贴搜索框，七项全可见，tooltip 逐项非空。
  - `final-900.png`：900pt 下限时 5 个动作可见 + 「»」溢出（系统行为，溢出项可达）。
  - `stability.txt`：0.3s 翻转 `hasSelection` 连续 6s，`items=13`、`flex=2`、首动作 x=898 稳定，无重复插入。
- 裁决摘要：blocker 0 / decision 0（口径已人工确认） / hold 1（真实悬停、点击动作与浅色主题像素待发布前人工）。

## 结论落点

| 结论 | 落点 |
|---|---|
| 顶栏分组与贴右口径 | `doc/design/scenarios/mail/receive/mailbox-sections/scenario.md`（`REQ-0042` 增量，`T-SCN-0028-05`） |
| 组件实现与量测 | `doc/design/components/CMP-APP/spec.md`（`REQ-0042` 增量） |
| 需求 | `doc/requirements/REQ-0042-mail-toolbar-groups.md` |
| 排期与任务表 | `doc/plan/roadmap.md` §W-M3-22 |
| 导航摘要 | `doc/README.md` |

## 未覆盖 / 未决

- 真实窗口悬停看 tooltip、点击七个动作、浅色主题像素验收：发布前人工项。
- macOS 14/15 的 flexible space 贴右效果未验证（本机 macOS 26.6）。
- 图标常驻文字标签未做；如需另立增量。
- 依赖 label 的 `actionLabels`/`tooltips` 映射：新增动作必须同步，否则不参与贴右/无 tooltip。
