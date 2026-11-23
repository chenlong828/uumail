---
layer: works
module: eas
status: frozen
updated: 2026-11-23
---

> 已归档（2026-11-23）。现行真相见 `design/components/CMP-EAS/spec.md` §设计增量（2026-11-17）。

# 2026-11-17 同步状态误判为设备未登记（T-1117-02 / T-1117-03）

**现象**：应用正常收发，状态栏常驻「设备未登记：请在网关登记并激活该设备 ID 后重试」，重启不消失。

**根因**：网关把「请求被吞 / SyncKey 不可用」和「设备未放行」都答成 `200` + 0 字节。`EASClient.ensureSuccess` 在解码前一律判 `deviceNotRegistered`，而该错误被 `SyncScene` 当成永久错误：自动刷新流结束、不重置同步状态，坏掉的 `sync_state.sync_key` 留在 SQLite 里，所以重启也复现。

**落点**：`T-1117-02` 收窄 Sync 的判定（`syncKeyInvalid`，走重建）并停用「设备未登记即停自动刷新」；`T-1117-03` 成功同步清掉状态栏旧文案。

**验收**：`EASClientTests` 35 例、`SyncSceneTests` 5 例、`PresentationTests` 90 例；全量 281 tests / 50 suites；架构 4 门。真机：把副本库的 `sync_key` 改回旧值后跑启动链路 → 自动重建（列表 200 → 125）且 `phase=idle`，不再出现「设备未登记」。证据见 `evidence/`。
