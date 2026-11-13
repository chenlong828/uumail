---
layer: plan
module: global
status: draft
updated: 2026-11-13
---

# 开放问题

跨工序、要人拍板的问题。一条一个问题：为什么现在要问、选项与代价、未拍板时的默认走向。
已决项一律移出本表，结论在 `history/decisions/`；本文件只留仍然悬空的问题。

## 已决（2026-11-09）

Provision 深度、多账号、DeviceId 来源、失败件上限、抓包入库、HTML 远程资源、联系人边界、OAuth/Graph — 八项已确认，见 `history/decisions/2026-11-09-scope-baseline.md`。需求状态同批落定：REQ-0001…0007 `accepted`，其余 `draft`。

附件缓存上限与淘汰策略（原 Q2）：按 A 方案落地，总容量 2 GB（`2_000_000_000` 字节）、按修改时间最旧优先淘汰；见 `history/decisions/2026-11-09-attachment-cache-cap.md`。

## Q1 本地保留策略：正文与邮件怎么裁剪

**为什么现在要问**：M1 同步大量邮件后本地库会持续膨胀（`plan/risks.md` R6），裁剪策略直接影响「搜索能不能命中旧信」和「离线能读多久」，也会改 `CMP-STORE` 的清理契约。

**选项**
- A 按时间窗口：正文保留最近 12 个月，列表信封全量保留（推荐）。代价：一年前的正文需要按需回拉，且回拉可能失败。
- B 按大小预算：库超过阈值后按最旧优先裁剪。代价：用户无法预测哪封信还能读。
- C 不裁剪：等出现性能问题再说。代价：库膨胀不可逆，M4 之前就可能卡顿。

**默认**：A，具体窗口在 M1 用真实邮箱规模校准后写进 `CMP-STORE/spec.md`。**落点**：`design/components/CMP-STORE/spec.md`。

