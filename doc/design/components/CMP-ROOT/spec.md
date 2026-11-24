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
- 负责 X：读配置（Keychain / `~/.uumail.env` / DEBUG 环境 / CLI 环境）、构造依赖、注入端口、按入口状态路由（配置页/邮箱/CLI 命令）、持有并启停长生命周期任务（自动刷新、`OutboxPump`、bootstrap）；平台适配器实现（Keychain、通知、附件文件、时钟、路径）。
- 不负责 Y：任何业务判断与流程编排——不判账号状态、不判 outbox/同步结果、不映射业务错误、不重试、不格式化、不读写业务数据。
- 内部逻辑：
  - `AppComposition`：有账号行 → 直接装配邮箱；无账号行但有配置 → `start()` 触发一次 `AccountSetupScene.connect` 引导，成功进邮箱、失败停在配置页显示场景错误文案；`connect()` 是配置页入口动作。
  - `OutboxPump`：启动补投 + 30s 周期 + 入队信号；只调 `Outbox.flushAll`，不检查投递结果（重试/退避在 `Outbox`）。
  - `CommandLineComposition`：环境配置 + `--db`；空库经 setup 场景引导（内存凭据，不写登录 Keychain）；诊断命令另建 `EASClient`（D8 例外）。
  - `GatewayFactory` / `PlatformGateway`：唯一 EAS 构造点；测试可注入 fake gateway。
  - `DotEnvCredentialStore`（2026-11-21）：开发者凭据文件 `~/.uumail.env` 的读写；启动时优先于此文件，
    读不到才回落 Keychain；`connect()` 成功后把新配置留在内存，菜单在首次配置后即可导出；只有
    「开发 → 保存凭据到 ~/.uumail.env」菜单动作会写（`0600`，明文），
    决策见 `history/decisions/2026-11-21-dev-dotenv-credentials.md`。
- 拥有的数据：无持久数据；只持有进程级任务句柄与已构造对象。
- 变化轴：部署形态（App/CLI）、平台实现替换。
- 公开契约：
  - `AppComposition.make(environment:) -> AppComposition?`、`.init(store:credentials:configuration:)`、测试注入 init、`route`、`mailbox`、`accountSetup`、`start/stop/connect`
  - `CommandLineComposition.configuration(environment:insecure:)`、`.easConfiguration(_:)`、`.make(databasePath:configuration:gatewayFactory:)`
  - `GatewayFactory`、`GatewayEndpoints`（`read`/`write` 均非可选；T-1114-10 设计，2026-11-14 已实现）、`OutboxPump`（内部）
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

## 设计增量：写端口与同一引擎装配（T-1114-10，2026-11-14 设计；T-1114-21/15/16 已实现）

- `GatewayFactory` 从返回单个读端口改为返回端点 bundle，生产仍是同一个 `EASAdapter`：

  ```swift
  public struct GatewayEndpoints: Sendable {
      public var read: any MailGateway
      public var write: any MailWriteGateway   // 非可选
  }
  public typealias GatewayFactory = @Sendable (ServerConfiguration) -> GatewayEndpoints
  ```

- `PlatformGateway.make` 返回 `GatewayEndpoints(read: adapter, write: adapter)`；`EASAdapter` 同时遵循 `MailGateway` 与 `MailWriteGateway`；生产 `read`/`write` 由同一 `let adapter` 构造（`EASAdapter` 是 struct，无对象身份，该不变量由实现检查/代码评审守）。
- 任务顺序（B1/B2）：**T-1114-21 先**把 `GatewayFactory`/`PlatformGateway` 改为返回 `GatewayEndpoints`，此时 `SyncEngine`/`ReadScene` 签名未改，组合根仍只用 `endpoints.read`；**T-1114-15** 把 `endpoints.write` 传给 `SyncEngine`；**T-1114-16** 把同一个 `engine` 传给 `ReadScene`。T-1114-15/16 各含 `CMP-ROOT` 仅装配例外，WIP 由该 change 独占；T-1114-21 不再做“最后补 `endpoints.write`”。
- `AppComposition.attachMailbox` / `CommandLineComposition.make` 只做机械注入：
  1. `let endpoints = gatewayFactory(configuration)`；
  2. `let engine = SyncEngine(gateway: endpoints.read, store: store, account: account, writeGateway: endpoints.write)`（T-1114-15 起）；
  3. **同一个 `engine`** 传给 `SyncScene(engine:)` 与 `ReadScene(..., writeEngine: engine)`（T-1114-16 起）；
  4. `Outbox`/`ReadScene.gateway`/`AccountSetupScene` 用 `endpoints.read`；`AppComposition.makeSetupScene` 里既有的 `gatewayFactory(...)` 直接当 `any MailGateway` 的调用点，T-1114-21 必须一并改为 `.read`，否则类型不匹配。
- 不变量：一个账号只构造一个 `SyncEngine`；组合根不得为 `ReadScene` 另建引擎（否则两把串行门各自为政，R19）；不判 `MailError`、不决定是否触发写、不重试。
- 测试：`CompositionTests` 的 `makeGatewayFactory` 返回 `GatewayEndpoints(read: fake, write: UnsupportedWriteGateway())`，其中 `UnsupportedWriteGateway` 定义在 `Tests/CompositionTests/Support.swift`（其他测试 target 各自定义同形替身，或另立 test-only support，不进入 production target）；新增一条装配测试断言生产 `PlatformGateway.make` 的 `write` 是 `EASAdapter`（生产唯一实现；类型上非可选，不存在 `nil` 分支），并断言装配后的场景图可接受该端口。**若该断言需要具体类型，T-1114-21 同批给 `CompositionTests` 增加 `EASAdapter` 测试依赖（当前 `Package.swift` 未列），或改用不引入生产类型的断言；不得为断言把 `EASAdapter` 暴露进 `Composition`。** 写行为在 `SyncEngineTests`/`ScenesTests` 证，不在组合根证。
- 兼容性：`GatewayFactory` 是 Composition 内部注入面，改类型只影响组合根与装配测试；`MailGateway` 读契约不变。`AppComposition` 行数预算 ≤200 不变（预计 +3～5）。

**实现（2026-11-14）**：`GatewayEndpoints{read,write}` 与 `GatewayFactory` 端点化；`PlatformGateway.make` 返回同一个 `EASAdapter` 的 read/write；`AppComposition`/`CommandLineComposition` 把 `endpoints.write` 传给 `SyncEngine`，把同一个 `engine` 传给 `ReadScene`。`CompositionTests` 17 例绿，含 `write is EASAdapter` 断言；`AppComposition` 182 行（上限 200）。

## 设计增量：日历场景与视图模型装配（REQ-0029 / REQ-0030，2026-11-24，未实现）

- 来源：`CMP-SCN-CALENDAR`（新场景）与 `CMP-PRES#CalendarViewModel`；只做构造与注入，不做业务判断（D9）。
- `AppComposition`（184 → 约 194 行，仍 ≤200）：
  - 构造 `CalendarScene(store: store, account: account)`；
  - 构造 `CalendarViewModel(calendar: calendarScene)`，与 `MailboxViewModel` 并列暴露给 `UumailApp`；
  - 不判断「有没有会议」「该显示月还是周」，不读 `meetings` 表。
- `UumailApp`：把 `CalendarViewModel` 传给 `MailboxView`（新增参数）；根视图仍只在配置页/邮箱之间路由。
- `CommandLineComposition`：本批不新增 CLI 命令；如后续要诊断，另立 `CMP-CLI` 增量（`meetings` 探针），不混进本批。
- 尺寸与门禁：`AppComposition` ≤200 行（门 3）；`Composition` 业务 switch 门（门 4）不新增 `switch`；不新增 target/依赖。
