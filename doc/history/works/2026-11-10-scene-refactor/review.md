---
layer: history
module: global
status: frozen
updated: 2026-11-14
---

# W-SCN-REFACTOR 评审记录（第二轮）

> 已归档（2026-11-14）。本文件是评审过程记忆；裁决与落点见同目录 `result.md` 的「裁决摘要」与 `design/architecture.md` §8.1。

对象：`architecture-spec.md`（P1 评审稿）。方法：场景走查（arch-design-spec 第 8 步），结论四档正交于定级。

## 逐条走查

| # | 走查 | 结论 | 证据/落点 |
|---|---|---|---|
| W1 | 阅读已缓存邮件 | 通过 | 场景契约 §4.9；`bodyIfCached` 零网络 |
| W2 | 阅读未缓存邮件 | 通过 | `open` 事件序列；先 `applyBody` 后 yield |
| W3 | 设备未登记接入 | 通过 | §4.7 顺序固定 + `discardAccount` |
| W4 | 同步中途进程被杀 | 通过 | 批次回滚 + outbox 租约（schema v2） |
| W5 | 扩展：标记已读 | Decision now | 扩展点声明；`PendingOps` 立开放问题 |
| W6 | 峰值叠加冷路径 | Verified sound / Hold | WAL 读不扫正文；5k 基线待 M4 |
| W7 | App 与 CLI 双跑 | Decision now | CLI `--db` 默认 `.build/`；进程租约列 M4 |
| W8 | 网关新增错误码 | 通过 | 只改 `EASAdapter.map` |
| W9 | 删除测试 | 通过 | 五个边界均为真边界（§9） |
| W10 | 组合根腐化（启动显示上次同步失败） | 通过（规则化） | 文案与失败判断归 `SyncScene`/VM；`Composition` 只构造与启动（§7 路由三分） |

## 四档裁决

| 档位 | 项 | 动作 |
|---|---|---|
| Blocker | 无 | — |
| Decision now | W5 已读扩展点；W7 CLI 默认库；outbox `sending` 租约入库；W10 组合根边界 | 已写入 §4.6/§4.4/§7、brief 任务表与开放问题 |
| Verified sound | W1–W4、W6、W8、W9 | 不改；禁止顺手优化 |
| Hold | `PendingOps` 时机；进程级账号租约；性能基线；Sent 镜像；账号替换 | 转 `plan/open-questions.md`，不进本次 diff |

## 评审发现的设计修正

1. 原方案“入队同时写本地已发送占位”超出本次范围（属新增功能），改为只写 outbox 行；Sent 镜像进开放问题。
2. 原方案 outbox 只在内存加锁，跨进程无效；改为 schema v2 的 `sending_since` 租约列。
3. 原方案让 `SyncEngine` 经 `StoreAdapter` 访问数据；改为 `MailStore` 直接遵循 `SyncStore`，删除透传适配器（D6）。
4. `uumailctl` 诊断命令直连 `EASClient` 显式登记为例外，避免为 `ping` 扩大 `MailGateway`（D8）。
5. 新增 D9：组合根只装配/注入/路由，不承接业务逻辑；路由三分写入 §7，配套“腐化信号”与 CI 门禁。

## 人工确认（2026-11-13）

- 整体结论：**通过**。
- D1–D9：逐条确认，无修改。
- 无附加条件；规格冻结，进入 T-1110-01。
