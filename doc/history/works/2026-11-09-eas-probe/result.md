---
layer: history
module: eas
status: frozen
updated: 2026-11-09
---

# W-2026-11-09-eas-probe 结果

## 验收结果

| 验收项 | 结论 | 证据 |
|---|---|---|
| `OPTIONS` 协议协商 | ✅ | 裸 URL 返回 `MS-ASProtocolVersions`（16.1 可用）与 `Set-Cookie` |
| `Provision` 两步握手 | ✅ | 临时 PolicyKey → 确认换正式 key；`DeviceInformation` 必须直挂 |
| `FolderSync` | ✅ | 全量文件夹树；收件箱 `Type=2` |
| `Sync` | ✅ | 30 封信封；`SyncKey=0` 首轮只回 key |
| 正文 | ✅ | `ItemOperations` 取到约 2 万字符 HTML |
| 附件 | ✅ | `FileReference` 直取 72KB 并落盘 |
| 发信 | ✅ | `200` + 0 字节 body，含附件 |
| 建/删文件夹 | ✅ | `FolderCreate`/`FolderDelete` 均 `Status=1` |
| GAL / `Search` / `Find` | ❌ | `Store Status=2`、`Find`=2、`ResolveRecipients`=5；非我方缺陷 |
| 联系人文件夹 | ⚠️ | 文件夹存在但 Sync 无条目，疑似为空 |
| `Ping` / `MoveItems` | ⚠️ | 未覆盖，留给 M1/M3 |

**总体**：读 + 发 + 附件全部可用，M0 出口达成。

## 根因记录（不是缺陷，是环境事实）

1. WBXML 内联字符串是 NUL 结尾，不是长度前缀；规范写法在网关处挂 20s 后 502。
2. `SendMail` 的 `Mime` 是 opaque 原始 RFC822 字节，base64 字符串会 502。
3. `Provision` 的 `DeviceInformation` 直挂 `Provision`；多包 `Settings` 得 `Status=2`。
4. `User` 查询参数不带域；带域 502。认证头才带域。
5. `OPTIONS` 必须裸 URL；带 `Cmd` 被吞成 200 空。
6. `Sync` 请求体多带顶层元素 → `Status=4`。
7. 未登记设备：读 `200` 空 body、写 `401`，没有明确错误。

## 结论落点

| 结论 | 落点 |
|---|---|
| 环境拓扑、请求骨架、线格式、能力矩阵 | `design/components/CMP-EAS/playbook.md` |
| 错误映射、命令契约、验证计划 | `design/components/CMP-EAS/spec.md` |
| 接入方案摘要、Autodiscover 不可用、DeviceId 不可自造 | `design/architecture.md` §7 与 §4 |
| 设备身份 / Provision / GAL / 抓包脱敏等待拍板项 | 已决，见 `history/decisions/2026-11-09-scope-baseline.md` |
| 风险（设备被清理、EAS 收紧、GAL 不可用） | `plan/risks.md` R1–R4 |
| 场景与需求 | `design/scenarios/mail/access/account-onboarding/`、`requirements/REQ-0001` |

## 遗留

- `Ping` 与 `MoveItems` 未验证，M3 前必须单独探测。
- 抓包样本含真实邮件内容，入仓前需脱敏（已定为脱敏后入库）。
- 设备 ID 的长期可用性依赖公司网关清单，需在使用前确认激活状态。
