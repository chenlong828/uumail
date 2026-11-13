---
layer: design
module: cli
status: active
updated: 2026-11-14
component: CMP-CLI
---

# CMP-CLI uumailctl 组件规格

## 模块卡

- 状态：`active`
- 单元：组件（可执行入口）
- 层 / 类型：L3；交付入口（诊断 + 数据命令）
- 业务价值：真机排障与端到端验证的唯一命令行入口；让 CLI 与 App 共享同一组合根与场景，而不是各写一套编排。
- 负责 X：命令解析、配置来源（环境变量）、退出码、把数据命令转给 `CommandLineComposition` + 场景、诊断命令直连 `EASClient`。
- 不负责 Y：业务编排（调场景）、UI、持久化逻辑。
- 内部逻辑：
  - 数据命令经 `CommandLineComposition.make` 装配同一对象图；空库先经 `AccountSetupScene.connect` 引导。
  - `send` 入队后 `Outbox.flushAll` 并等待投递结果；失败保留行并打印 `(item kept for retry)`。
  - `--db` 默认值：`send` 为 `.build/outbox.sqlite`，`folders` 为 `.build/uumailctl.sqlite`；`sync`/`store`/`body --db` 必填；**不会默认打开 App 库**（避免双进程游标互顶）。
  - 诊断命令（`options/provision/ping/diagnose`、无 `--db` 的 `body`）直连 `EASClient`（D8 例外）。
- 拥有的数据：无；数据在 `MailStore`。
- 变化轴：命令集与参数；诊断探针可随协议变化独立调整。
- 公开契约：命令行参数与退出码（`0` 成功，`2` 用法/缺参，`3` 业务/协议错误）。
- 入口：`Sources/uumailctl/UumailCtl.swift#UumailCtl`
- 依赖：`Composition`、`Scenes`、`MailDomain`、`EASClient`。扇出 4（含 D8 例外）。
- 冷热：冷。
- 删除测试：删掉后真机排障与端到端验证无入口。

## 契约卡：命令行 v1

| 命令 | 路径 | 关键参数 | 行为 |
|---|---|---|---|
| `options` | 直连 `EASClient` | — | 打印协议版本与命令数 |
| `provision` | 直连 `EASClient` | — | 两步握手，打印 PolicyKey 长度（不打印值） |
| `ping` | 直连 `EASClient` | `--heartbeat` | 打印 status/changes/elapsed |
| `diagnose` | 直连 `EASClient` | — | OPTIONS → Provision → FolderSync → 收件箱 |
| `body` | `--db` 时经 `ReadScene`，否则直连 | `--folder --server [--db]` | 打印 truncated/chars/前 1000 字符 |
| `folders` | `CommandLineComposition` + `ReadScene.folders` | `--db --json` | 本地文件夹树 + sync key |
| `sync` | `CommandLineComposition` + `SyncScene.refresh` | `--db`（必填） | 打印 report 与最近 10 封 |
| `send` | `CommandLineComposition` + `ComposeScene.send` + `Outbox.flushAll` | `--to --subject --body --db` | 入队并等待投递；失败退出 3 |
| `store` | 组合根引导快照 + `ReadScene.folders` | `--db`（必填） | 打印已落库文件夹 |
| `seed` | `KeychainCredentialStore.save` | — | 把环境账号写入登录 Keychain |

- 不变量：数据命令不得绕过场景；`send` 必须经 `Outbox` 而不是直连 SendMail；诊断命令不得为 `ping/options` 扩大 `MailGateway`。
- 错误模式：`EASError` → stderr `EAS error: ...`，退出 3；其它错误 → `error: ...`，退出 3；缺参/未知命令 → usage，退出 2。
- 幂等 / 顺序 / 并发：每次调用独立进程；同库并发由 outbox 行级租约与 `--db` 默认隔离约束（进程级账号租约未做，见 `plan/open-questions.md` Q3）。
- 超时 / 取消：由 `EASClient` / 场景决定；CLI 不额外重试。
- 兼容性：`seed` 只写 Keychain；空库数据命令会先引导（多一次 probe/provision/folderSync，输出格式不变）。
- 契约测试：`CompositionTests/CommandLineCompositionTests.swift`（空库引导后复用）；**无 CLI 端到端测试**。

## 实现进度（2026-11-14）

| 命令 | 代码 | 验证 |
|---|---|---|
| `options/provision/ping/diagnose` | ✅ 直连 | 协议探针，`EASClientTests` 覆盖底层 |
| `folders/sync/store/body --db` | ✅ 经组合根 + 场景 | 组件/契约测试；**本会话未真机跑** |
| `send` | ✅ 入队 + `flushAll` | `OutboxTests`；**本会话未真机跑** |
| `seed` | ✅ | 无单测（Keychain 需真实环境） |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 装配与引导 | `CommandLineCompositionTests`：空库经 setup 场景建号后复用 |
| 数据命令路由 | 代码评审 + 场景契约测试；缺 CLI 命令级测试 |
| 退出码 | 手工检查；无自动化断言 |
| 发布前 | `uumailctl diagnose/sync/send` 真机冒烟（**未做**） |

## 依赖约束

- 数据命令只经 `Composition` + `Scenes`；诊断命令可 import `EASClient`（显式例外，门 1 放行）。
- 不 import `MailStore`/`Presentation`/`Outbox`；不写业务 SQL、不拼 MIME。
