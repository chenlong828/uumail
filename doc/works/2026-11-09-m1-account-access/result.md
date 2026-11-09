---
layer: works
module: eas
status: active
updated: 2026-11-09
---

# W-2026-11-09-m1-account-access 结果

## 验收结果

| 验收项 | 结论 | 证据 |
|---|---|---|
| `swift build` / `swift test` 通过 | ✅ | 22 个测试全绿（3 个 suite） |
| WBXML 与参考实现字节级一致 | ✅ | FolderSync / Provision / Sync 三组 golden 字节完全相等；opaque 回环通过 |
| 错误映射逐行有测试 | ✅ | 401 / 444 / 449 / 503 / 空 200 / 502 快慢分流 / FolderSync 非 1 状态 |
| FolderSync 解析 + 事务落库 | ✅ | 21 个真实文件夹落库；幂等、软删、复活、回滚各有测试 |
| 真实网关只读跑通 | ✅ | `[1] OPTIONS ok: 2.0…16.1`、`[2] Provision ok`、`[3] FolderSync ok: 21 folders`、`[4] inbox: id=13` |
| 凭据不入库 | ✅ | 环境变量注入；`.env` 在 `.gitignore`；文档与测试无真实值 |
| 收件箱 UI | ✅ | SwiftUI 外壳：配置页、文件夹侧栏、邮件列表；窗口截图验证 |
| 收件箱同步端到端 | ✅ | 真机：5 轮 × 25 封 = 125 封入 SQLite，含主题/发件人/时间/已读 |
| `Sync` 分页语义 | ✅ | 实测 `MoreAvailable` 不可靠，改为按「本轮新增 < 窗口」停止；进 playbook §3 |

## 结论落点

| 结论 | 落点 |
|---|---|
| WBXML 线格式按实测实现（NUL 字符串、opaque、code page） | `Sources/EASClient/WBXML.swift`、`doc/design/components/CMP-EAS/playbook.md` §4 |
| 错误映射与 502 快慢分流 | `Sources/EASClient/EASClient.swift`、`CMP-EAS/spec.md` 错误映射表 |
| 设备身份、策略握手、文件夹落库 | `Sources/MailStore/MailStore.swift`、`CMP-STORE/spec.md` |
| 构建环境的三处本机约束（缓存路径、嵌套 sandbox） | `Scripts/swiftw`、`README.md` |
| 真实网关能力：21 个文件夹、收件箱 `ServerId=13`、协议版本列表 | 本文件与 `playbook.md` §1 |

## 裁决摘要

blocker 0 / decision 1（502 快慢分流：慢 502 归 protocolRejected，快 502 归 transient，已加测试）/ hold 1（PolicyKey 持久化留到 App 外壳接 Keychain）。

## 未决 / 遗留

- `SCN-0001` 仍不能转 `verified`：场景要求 UI 层错误文案与账号状态，本工序只到组件与 CLI。
- `Sync`、正文/附件、发送尚未实现；下一个工序从收件箱同步开始。
- TLS 验证默认开启；公司证书若为内部 CA 需要 `--insecure`，尚未在真实环境验证该分支。
