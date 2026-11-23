---
layer: history
module: global
status: frozen
updated: 2026-11-23
run: 20261123-table-adapt
---

# W-M3-15 评审（P2/P3）

## 裁决

**通过**（P2 部分由用户 2026-11-23 人工确认；P3 部分自动测试 + L2 探针通过）。

## Blocker

无。

## Decision now（已定并落文档/测试）

- **表格压缩而非保版式滚动**：用户 2026-11-23 选择「压缩适配」。落点 `REQ-0027`、`SCN-0021`、`CMP-APP` 增量、决策记录 D1；L2 探针 `TableLayoutProbe` 固定。
- **附件条隐藏正文内联图**：用户 2026-11-23 选择。落点 `REQ-0028`、`SCN-0022`、`CMP-{PRES,SCN-READ}` 增量、决策记录 D4；取代 `REQ-0025` 2026-11-21 澄清③，已在决策记录写明。
- **additive public `InlineImageReferences`**：`CMP-SCN-READ` 增量与决策记录 D5；无签名破坏、无新依赖；L1 用例固定匹配语义（contentID 优先、名字回退、歧义跳过）。

## Verified sound（查过并确认）

- 120% 下生产 CSS 不改变现有 816px 表宽度（978/816），只影响超宽/大字号场景；真实样本 `overflowCount=0`。
- 无宽度 300px 表保持 300，不被 `display:block` 拉伸。
- 900px 表 + 600px 图在 668px 下文档不溢出，图片宽度 ≤ 单元格。
- `ReadScene.attachments(for:)`/`renderInlineImages`/`downloadAttachment` 未改；内联图仍由场景取全量，附件条过滤只是 PRES 投影。
- 无 schema/依赖/target/`Package.swift`/CSP/`baseURL`/禁 JS/白底/字号改动。

## Hold

- 内联图失败时无附件条另存入入口（已接受代价，另立需求）。
- 撰写页引言表格未适配（另立）。
- 无显式宽度 + `nowrap` 超宽表的残余（不阻塞）。
- 并行全量首跑 `MailboxViewModel delete` 计时 flake（未复现；串行全量通过），记入既有测试稳定性待办。
- 正文首次补拉期间附件条短暂显示全量（无 schema 无法提前判定内联；已接受）。

## 证据

`evidence/table-layout-probe/main.swift`、`evidence/table-layout.txt`、`evidence/real-sample-table.txt`；`result.md`。
