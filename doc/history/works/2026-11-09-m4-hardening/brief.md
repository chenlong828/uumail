---
layer: history
module: global
status: frozen
updated: 2026-11-13
---

# W-2026-11-09-m4-hardening 工序简报

> 已归档（2026-11-13）。本文件是过程记忆，不是现行设计依据；结论已落到 `design/components/CMP-EAS/playbook.md` §5.2、`CMP-SYNC`、`CMP-APP` 规格与 `history/decisions/2026-11-09-attachment-cache-cap.md`。

## 需求

M3 收尾与 M4 加固：Ping 结论、限流退避、附件缓存上限、安全审计、性能基线。对应 `plan/roadmap.md` 的 M3/M4。

## 验收标准

- Ping 有明确结论并落到 playbook；
- `Retry-After` 触发一次等待后重试；
- 附件缓存超过上限按最旧优先淘汰；
- 安全审计覆盖凭据、TLS、HTML、文件路径、通知内容；
- 性能基线数字可复现（5k 封）。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| T-M4-01 | verify | CMP-EAS | done | Ping 实测（status=4） |
| T-M4-02 | change | CMP-SYNC | done | 限流退避 + 一次性重试 |
| T-M4-03 | change | CMP-APP | done | 附件缓存 LRU（2GB） |
| T-M4-04 | verify | CMP-STORE | done | 5k 封性能基线 |
| T-M4-05 | verify | 全局 | done | 安全审计 |
