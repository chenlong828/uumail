---
layer: history
module: global
status: frozen
updated: 2026-11-13
---

# 附件缓存上限与淘汰策略（2026-11-09）

## 背景

`plan/open-questions.md` Q2：附件缓存没有上限会吃满磁盘，上限过低会让用户反复下载同一附件。M4 加固落地时按默认方案 A 拍板，2026-11-13 补记成文。

## 决定

- **总上限 2 GB**（`2_000_000_000` 字节，十进制），按文件大小累计。
- **超限时按修改时间最旧优先删除**，删到不超过上限为止；未超限不动。
- 触发点：每次附件写入缓存后（`MailService` 的下载路径调用 `AttachmentCache.prune`）。
- 缓存目录在 Application Support，与邮件库一样明文落盘。

## 代价 / 影响

- 大附件多时需要重下；用户会遇到「昨天能打开、今天要重下」，只在打开失败时提示重新下载。
- 规则单一、可解释，不做按文件夹或时间的组合策略。
- 缓存与本地库一样依赖 FileVault，属已知接受项（`plan/risks.md` R12）。

## 未采纳

| 方案 | 理由 |
|---|---|
| B 按文件夹/时间策略清理 | 规则难解释，行为不可预测 |
| C 不设上限，只提示清理 | 磁盘风险转移给用户 |

## 落点

`design/components/CMP-APP/spec.md`（实现进度）、`design/architecture.md` §1 决策句与 §7 附件；代码 `Sources/AppServices/AttachmentCache.swift`。
