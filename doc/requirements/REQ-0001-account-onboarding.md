---
layer: requirements
module: mail
status: accepted
updated: 2026-11-09
---

# REQ-0001 账号接入与设备身份

- **ID**：REQ-0001
- **类型**：feature
- **场景叙述**：用户在新 Mac 上打开设置，填入服务器地址、账号、密码与已在公司网关登记的设备 ID；客户端完成策略握手并落库，账号进入可同步状态。
- **价值**：不做的后果是客户端根本连不上服务器——外网只发布 EAS，且网关按设备登记放行，没有这条链路，其余所有功能都没有数据来源。
- **非目标**：不做自动发现（外网 `Autodiscover` 404）；不做 OAuth；不做多账号；不做设备 ID 的自动登记或申请。
- **约束**：凭据只存 Keychain；设备 ID 不入代码库；连接只走 TLS 的 443。
- **影响场景**：SCN-0001（`design/scenarios/mail/access/account-onboarding/`）。
- **澄清记录**：2026-11-09 整理文档时确认「手填优先、自动发现不可用」为既定事实（来源：探针实测）。
- **状态**：accepted（2026-11-09 范围确认，见 `history/decisions/2026-11-09-scope-baseline.md`）
- **确认记录**：2026-11-09 首版范围确认，本卡转 `accepted`。
- **验收归属**：SCN-0001 转 `verified` 即视为交付。
