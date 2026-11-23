---
layer: history
module: eas
status: frozen
updated: 2026-11-23
---

# 2026-11-17 同步状态误判 — 收口

## 结论

网关把「请求被吞 / SyncKey 不可用」与「设备未放行」都答成 `200` + 0 字节；`EASClient` 原先一律判
`deviceNotRegistered`，被 `SyncScene` 当永久错误，坏掉的 `sync_key` 留在库里，重启也复现。收窄判定后：
`Sync` 的空响应/缺 `Collection/Status` 走 `syncKeyInvalid` → `resetCollection` 重建，`FolderSync`/`ItemOperations`
的空响应仍算设备未登记；成功同步清掉状态栏旧文案。

## 验收

- `EASClientTests` 35 例、`SyncSceneTests` 5 例、`PresentationTests` 90 例；全量 281 tests / 50 suites；架构 4 门。
- 真机：副本库写回旧 `sync_key` 后跑启动链路 → 自动重建（列表 200 → 125）且 `phase=idle`，不再出现「设备未登记」。

## 落点

| 结论 | 落点 |
|---|---|
| 判定收窄与重建路径 | `design/components/CMP-EAS/spec.md` §设计增量（2026-11-17）、`CMP-SYNC` 重建语义 |
| 真机证据 | `evidence/real-gateway-2026-11-17.txt` |
| 提交 | 见 `plan/roadmap.md` 2026-11-17 条目 |
