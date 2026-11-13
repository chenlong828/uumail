---
layer: design
module: scenes
status: active
updated: 2026-11-14
component: CMP-SCN-ACCOUNT
---

# CMP-SCN-ACCOUNT AccountSetupScene 组件规格

## 模块卡

- 状态：`active`
- 单元：组件（场景）
- 层 / 类型：L2；接入流程编排
- 业务价值：把「填表 → 探测 → 策略握手 → 文件夹快照 → 落账号 → ready → 存凭据」收在一个类里；失败不留半成品。没有它，视图与 CLI 各拼一遍接入流程。
- 负责 X：`validate`（只探活不写库）、`connect`（完整接入）、失败回滚、`MailError` 分类透传、重复接入复用既有账号。
- 不负责 Y：表单校验样式、Keychain 细节、协议细节、账号替换策略。
- 内部逻辑：
  - `connect` 顺序固定：`probe` → `provisionIfNeeded` → `fetchFolders(syncKey:"0")` → 建号/复用 → `applyFolderSnapshot` → `folders` → `markAccountReady` → `credentials.save`；凭据最后写。
  - 失败回滚只删**本次新建**且无消息的账号（`discardAccount`）；复用既有账号时失败保留原账号与数据。
  - 同一安装只保留一个账号：已有账号行则复用。
- 拥有的数据：无；账号行由 `MailStore` 写，凭据由 `CredentialStore` 写。
- 变化轴：接入步骤顺序与校验项。
- 公开契约：`CMP-SCN-ACCOUNT#validate`、`#connect`。
- 入口：`Sources/Scenes/AccountSetupScene.swift#AccountSetupScene`、`#AccountInput`、`#ConnectedAccount`
- 依赖：`MailDomain`（`MailGateway`、`CredentialStore`、`MailError`）、`MailStore`。扇出 2。
- 冷热：冷（用户等待一次）。
- 尺寸预算：≤800 行；当前随 `Scenes` 共 666 行。
- 单独运行：`./Scripts/swiftw test --filter ScenesTests`
- 删除测试：删掉后视图或 CLI 各自拼接入流程，失败回滚不一致 → 复杂度集中，是真边界。

## 契约卡：AccountSetupScene v1

- 签名：

  ```swift
  public struct AccountInput: Sendable { host, account, password, domain, deviceID, displayName }
  public struct ConnectedAccount: Equatable, Sendable { accountID, address, displayName, folders }
  public struct AccountSetupScene: Sendable {
      public init(gateway: any MailGateway, store: MailStore, credentials: any CredentialStore)
      public func validate(_ input: AccountInput) async throws
      public func connect(_ input: AccountInput) async throws -> ConnectedAccount
  }
  ```

- 前置：`host/account/password/deviceID` 非空；空字段在**任何网络调用之前**抛 `invalidInput`。
- 后置：`connect` 成功时账号行存在、`state = ready`、文件夹快照已落库、凭据已保存；`validate` 成功时库与凭据都未被写。
- 不变量：任一步失败不留下「账号已建但无文件夹」或「凭据已写但账号未成」；凭据最后写。
- 错误模式：透传 `MailError`；`invalidInput(reason:)` 用于空字段（如 `"host is empty"`）；`storage` 用于回滚失败。设备未登记等永久错误由调用方（VM/组合根）呈现，场景不重试。
- 幂等 / 顺序 / 并发：重复 `connect` 复用既有账号；单次用户操作，不做并发保护（组合根串行）。
- 超时 / 取消：由 `MailGateway` 实现决定；场景不额外加超时。
- 一致性：`connect` 返回时本地库已提交，VM 可直接读文件夹。
- 兼容性：`AccountInput` 无协议字段，构造 `ServerConfiguration` 时按默认值补 `deviceType/protocolVersion`；`ConnectedAccount` 只暴露场景需要的四元组。
- 契约测试：`ScenesTests/AccountSetupSceneTests.swift` 6 例。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| `validate` 不写库 | ✅ | 「validate probes and provisions without writing the database or credentials」 |
| `connect` 顺序、ready、凭据最后 | ✅ | 「connect probes, provisions, snapshots folders, marks ready and saves credentials last」 |
| 空字段先拒绝 | ✅ | 「empty required fields are rejected before any network call」 |
| 失败回滚 | ✅ | 「a folder-sync failure discards the new account and saves no credentials」 |
| 复用既有账号 / 失败保留 | ✅ | 「a repeat connect reuses the existing account row」「a failure while reusing an account keeps that account and its data」 |

注意：`markAccountReady` 被调用，但 `MailStore` 没有读账号状态的公开契约，测试只能断言账号行与文件夹；`ready` 本身不可直接断言。

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 顺序/回滚 | `ScenesTests` 6 例；fake gateway 记录调用序列 |
| 分类错误 | 注入 `authFailed`/`offline`/`invalidInput`，断言不重试、不留账号 |
| 幂等 | 重复 connect 复用账号；既有账号失败不删数据 |
| 依赖 | 门 1：`Scenes` 不 import EAS；只经 `MailGateway` |

## 依赖约束

- 只经 `MailGateway` 端口访问网络；只经 `MailStore` 公开契约写库。
- 不 import `EASClient`/`EASAdapter`/`Composition`；不决定 UI 文案。
