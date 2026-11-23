---
layer: history
module: global
status: frozen
updated: 2026-11-23
run: 20261123-table-adapt
---

# W-M3-15 收口

## 结论

| 结果 | 结论 |
|---|---|
| REQ-0027 / SCN-0021 宽表适配 | 已交付。`MessageBodyStyle.baseCSS` 对显式宽度表加 `display:block; max-width:100%; overflow-x:auto`；120% 下 816px 表保持 816、页面 978；145/175/225% 下压到 778/639/490，页面 810/671/522；真实样本 `overflowCount=0`。 |
| REQ-0028 / SCN-0022 附件条静默内联图 | 已交付。`InlineImageReferences.attachmentIDs` + `MailboxViewModel.startInlineImageRender` 过滤；本样本 57 个附件过滤后剩 2 个真实文件；歧义/无 cid 不误删。 |

## 验收证据

- L2 `TableLayoutProbe`（生产 `MessageBodyStyle.swift` + WKWebView）：`RESULT 6/6 passed`，原始输出 `evidence/table-layout.txt`。
- 真实样本（本机缓存正文 + 55 张内联图，只记录数字）：`evidence/real-sample-table.txt`，120% 979/978、145% 810/810、175% 671/671、225% 522/522，`overflowCount=0`。
- L1 `InlineImageHTMLTests` 18 例、`MailboxViewModelInlineImageTests` 8 例；全量 `384 tests / 59 suites`，架构 4/4（`check-architecture.sh`）。
- `./Scripts/make-app.sh` 成功，`dist/build-info.txt` = `0ce2e2e` / 2026-11-23 15:56:21 CST。
- 并行全量第一次运行时 `MailboxViewModel delete` suite 报 1 个 issue（未保留断言文本）；随后并行全量、串行全量（`--no-parallel`）均 384/384 通过；判定为既有计时类 flake，与本次改动无关，记入 hold。

## 任务状态

`T-1123-01`…`T-1123-05` 全部完成；`SCN-0021`/`SCN-0022` → `verified`；`REQ-0027`/`REQ-0028` → `delivered`。

## 残余

- 内联图渲染失败时对应附件已从附件条移除，用户没有另存入口；用户 2026-11-23 已确认的代价，另立需求评估。
- 无显式宽度且 `nowrap` 长文本超宽的表仍可能溢出。
- 撰写页 `ComposeDocument` 引言表格未适配（D3）。
- 正文首次补拉期间（缓存未命中）附件条会短暂显示全量，正文到达后过滤；无 schema 变更无法提前判定内联。
- `TableLayoutProbe` 的 1px 舍入（979/978）按容差断言，不追求逐像素相等。
