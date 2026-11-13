---
layer: design
module: composition
status: active
updated: 2026-11-14
component: CMP-ROOT
---

# CMP-ROOT Composition 组件规格

## 模块卡

- 状态：`active`
- 单元：模块（组合根 + 平台适配器，不含业务规则）
- 层 / 类型：根；装配、注入、路由与生命周期（D9）
- 业务价值：把「谁依赖谁、谁先启动」集中到一处，让业务判断留在场景；没有它，各入口各自装配，DEBUG 分支与轮询散落。
- 负责 X：读配置（Keychain / DEBUG 环境 / CLI 环境）、构造依赖、注入端口、按入口状态路由（配置页/邮箱/CLI 命令）、持有并启停长生命周期任务（自动刷新、`OutboxPump`、bootstrap）；平台适配器实现（Keychain、通知、附件文件、时钟、路径）。
- 不负责 Y：任何业务判断与流程编排——不判账号状态、不判 outbox/同步结果、不映射业务错误、不重试、不格式化、不读写业务数据。
- 内部逻辑：
  - `AppComposition`：有账号行 → 直接装配邮箱；无账号行但有配置 → `start()` 触发一次 `AccountSetupScene.connect` 引导，成功进邮箱、失败停在配置页显示场景错误文案；`connect()` 是配置页入口动作。
  - `OutboxPump`：启动补投 + 30s 周期 + 入队信号；只调 `Outbox.flushAll`，不检查投递结果（重试/退避在 `Outbox`）。
  - `CommandLineComposition`：环境配置 + `--db`；空库经 setup 场景引导（内存凭据，不写登录 Keychain）；诊断命令另建 `EASClient`（D8 例外）。
  - `GatewayFactory` / `PlatformGateway`：唯一 EAS 构造点；测试可注入 fake gateway。
- 拥有的数据：无持久数据；只持有进程级任务句柄与已构造对象。
- 变化轴：部署形态（App/CLI）、平台实现替换。
- 公开契约：
  - `AppComposition.make(environment:) -> AppComposition?`、`.init(store:credentials:configuration:)`、测试注入 init、`route`、`mailbox`、`accountSetup`、`start/stop/connect`
  - `CommandLineComposition.configuration(environment:insecure:)`、`.easConfiguration(_:)`、`.make(databasePath:configuration:gatewayFactory:)`
  - `GatewayFactory`、`OutboxPump`（内部）
- 入口：`Sources/Composition/AppComposition.swift#AppComposition`、`CommandLineComposition.swift#CommandLineComposition`、`OutboxPump.swift#OutboxPump`、`GatewayFactory.swift#GatewayFactory`
- 依赖：其余 8 个库 target（`MailDomain`、`MailStore`、`SyncEngine`、`Outbox`、`EASClient`、`EASAdapter`、`Scenes`、`Presentation`）。组合根豁免扇出。
- 冷热：启动一次；运行期只做路由，不进热路径。
- 尺寸预算：`AppComposition` ≤200 行（当前 **180**）；`CommandLineComposition` 127；`OutboxPump` 66；平台适配器各自 ≤120 行。
- 单独运行：`./Scripts/swiftw test --filter CompositionTests`
- 删除测试：删掉后各入口各自装配、环境分支散落 → 真边界。

## 契约卡：组合根 v1

- 签名（摘要见上）；`AppComposition` 是 `@MainActor @Observable`，`route` 只有 `.accountSetup` / `.mailbox`。
- 前置：`make` 需要可打开的数据库；无配置时停在配置页且不发起网络。
- 后置：`start()` 幂等（重复调用不新增泵/刷新循环）；`stop()` 幂等且不改变 `route`；`connect()` 成功后 `route = .mailbox` 并启动任务。
- 不变量：只构造/注入/路由；不调用业务契约；不对 `MailError`/`SyncState`/`OutboundState` 做 `switch`；不重试、不 sleep、不拼 MIME；DEBUG 环境凭据只留在进程内，不写登录 Keychain。
- 错误模式：装配失败（数据库打不开）返回 `nil`；引导失败停在配置页显示 `AccountSetupViewModel.errorText`；CLI 配置缺失抛 `CommandLineConfigurationError.missing(key)`。
- 幂等 / 顺序 / 并发：`start/stop` 幂等；`bootstrapTask` 只试一次；`OutboxPump.start/stop` 可重启。
- 超时 / 取消：`stop()` 取消 bootstrap、自动刷新与泵。
- 一致性：邮箱装配使用同一 `MailStore` 与配置；CLI 与 App 默认不同库（CLI 默认 `.build/`），避免双进程写同一库。
- 兼容性：为可测性保留注入 init 与 `gatewayFactory`，生产 omits；`PlatformGateway` 是唯一 EAS 构造点。
- 契约测试：`CompositionTests`（装配冒烟、bootstrap、路由、泵启停、DEBUG 凭据、附件缓存、CLI 引导）。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| App 路由（有账号行 / 无行 / 无配置） | ✅ `AppComposition` | 「an account row plus configuration routes to the mailbox without touching the gateway」等 5 例 |
| 无账号行 bootstrap（成功/失败） | ✅ | 「a fresh database with a stored configuration connects through the setup scene ...」「a failed bootstrap stays on the setup page ...」 |
| 投递泵（启动补投/信号/启停） | ✅ `OutboxPump` | `OutboxPumpTests` 3 例 |
| CLI 装配与空库引导 | ✅ `CommandLineComposition` | `CommandLineCompositionTests` |
| 平台适配器 | ✅ `Platform/*.swift` | `FileAttachmentFilesTests`、`ConfigurationSourceTests` |
| 唯一 EAS 构造点 | ✅ `GatewayFactory.swift` | 装配测试注入 fake gateway |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 只装配/路由 | 架构门 3/4：`AppComposition` 行数与业务 switch；装配测试断言不触碰 gateway |
| 引导 | fake gateway + 内存库：成功建号/存凭据/进邮箱；失败无账号行、无凭据 |
| 生命周期 | start/stop 幂等；泵投递一次；入队信号立即投递 |
| 平台适配器 | `FileAttachmentFilesTests`（原子写、2 GB 淘汰）；`ConfigurationSourceTests`（DEBUG 凭据不落 Keychain） |
| 残留 | **真机 bootstrap 与真实投递未跑**；门 2 按文件名判定、门 4 依赖命名（见下） |

## 依赖约束

- 允许 import 全部库 target 与平台框架（Security、UserNotifications、CryptoKit、Observation）。
- 禁止：`MailStore` 业务查询/写入（路径初始化与存在性检查除外）、`MailGateway`/`Outbox`/`SyncEngine` 的业务方法、业务错误文案、retry/sleep 循环、按业务状态分支。
- **门禁已知局限**：`Scripts/check-architecture.sh` 门 3 只数 `AppComposition.swift` 行数；门 4 的业务 case 标签 + `switch` 主语匹配依赖命名。新增组合根文件时需同步扩展脚本，不能只看 4 门全过。
