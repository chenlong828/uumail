---
layer: history
module: eas
status: frozen
updated: 2026-11-23
---

# 2026-11-21 附件下载修复 — 收口

## 结论

网关没有"不支持"，是客户端读错了响应节点。改为 `Response/Fetch/Properties/Data`（直挂 `Data` 兼容），
附件请求单独 600s 资源预算；真机小附件 0.27s 取回 52,189 B 有效 xlsx，28.7MB 附件 181.55s 取回
28,720,799 B（旧 120s 预算下会超时）。25MB 上限按用户决定暂缓。

## 验收

| 项 | 结果 |
|---|---|
| `T-SCN-0005-01`（正） | 真机：52,189 B xlsx（12 个 zip 成员全通过）；`EASClientTests` 嵌套/直挂/`Fetch/Status=6`/600s 预算 4 例 |
| `T-SCN-0005-02`（正） | 暂缓（用户 2026-11-21 决定），不新增断言，欠账保留在场景卡 |
| `T-SCN-0005-03`（正） | 暂缓：网关 `Options/Range` 回 `Status=2`，不可实现 |
| `T-SCN-0005-04`（反） | 暂缓：无 `AttachmentName` 回退 |
| 全量 | `362 tests / 58 suites` 全绿；架构 4 门 PASS |
| 真机大附件 | 28.7MB → 181.55s / 28,720,799 B |

## 结论落点

| 结论 | 落点 |
|---|---|
| payload 路径与 `Fetch/Status` 语义、600s 预算 | `design/components/CMP-EAS/spec.md` §设计增量（2026-11-21）、`playbook.md` §5.5 |
| 运行序与欠账 | `design/scenarios/mail/read/attachment-download/scenario.md` |
| 排期记录 | `plan/roadmap.md` M3 段 |
| 代码 | `Sources/EASClient/EASClient.swift`、`Sources/EASClient/URLSessionTransport.swift`、`Tests/EASClientTests/EASClientTests.swift` |
| 提交 | `abbc4ef`（修复）+ `34ff554`（重发 dist） |

## 未决

- 应用内「双击打开/另存为」的真机点击验证未做。
- `Fetch/Status=6` 现已带状态码上抛，但 `EASAdapter` 仍归 `.unsupported`，UI 文案仍是「网关返回了暂不支持的结果」；细化文案另立任务。
- 25MB 上限、断点续传、`AttachmentName` 回退仍是 `SCN-0005` 的公开欠账。
