---
layer: history
module: global
status: frozen
updated: 2026-11-13
---

# fetchBody 契约：保留正文类型与截断标记（2026-11-13）

## 背景

W-SCN-REFACTOR 规格 §4.1 把 `MailGateway.fetchBody` 定为返回 `String`。T-1110-02 把 `MailService` 切到端口时暴露两个被 `String` 抹掉的语义：

1. **`isHTML`**：网关可能回 `Type=1` 纯文本（playbook §5.1），直接当 HTML 渲染会丢换行，这是 2026-11-10 修过的缺陷类。
2. **`isTruncated`**：`SCN-0004` 的失败路径承诺「网关仍截断 → 给提示、不静默丢内容」，`CMP-EAS` 不变量也要求读 `Truncated`。

按原契约落地等于删掉这两条承诺；用户确认采用值类型（2026-11-13 问答）。

## 决定

- `MailDomain.FetchedBody { text, isHTML, isTruncated }`。
- `MailGateway.fetchBody` 返回 `FetchedBody`；`EASAdapter` 原样透传 `EASClient.FetchedBody` 的三个字段。
- `isHTML → HTML` 的转换归场景层（`ReadScene`），不压进 L0 适配器。
- `BodyEvent.loaded(FetchedBody)`；Presentation 用 `isTruncated` 渲染「正文过长」提示。

## 代价 / 影响

- 冻结契约变更一次，记为本规格 D10；T-1110-02 已按此实现，行为与 v0.1 一致。
- 场景与视图模型各多带一个字段；纯文本转换仍是场景层职责。

## 未采纳

| 方案 | 理由 |
|---|---|
| `fetchBody -> String` | 丢 `Type` 与 `Truncated`；需同时改 SCN-0004 与 CMP-EAS 不变量，且静默丢内容 |
| `FetchedBody { html, isTruncated }`，转换放适配器 | L0 承担 HTML 排版与纯文本换行规则，越过场景边界 |

## 落点

`Sources/MailDomain/Values.swift`、`Sources/EASAdapter/EASAdapter.swift`、`Sources/AppServices/MailService.swift`；规格 §4.1 / §4.9 / §4.11（D10）。
