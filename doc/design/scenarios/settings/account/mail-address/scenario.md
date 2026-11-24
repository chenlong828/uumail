---
layer: design
module: settings
status: verified
updated: 2026-11-25
flow: settings/account
scenario: SCN-0030
---

# SCN-0030 账号邮箱地址配置与迁移

**结果**：配置页多一个「邮箱地址」字段；显式填写时，App 把它作为发信 `From`、写入本机账号行，并在已有账号重连/启动时把旧的 `账号@服务器地址` 迁移成显式地址；字段留空时沿用 `账号@服务器地址`，且不会覆盖用户之前手动改过的地址。旧 Keychain/DotEnv 没有该字段时仍能解码。

## 入口

- `CMP-APP#AccountSetupView`（「邮箱地址」输入框）
- `CMP-PRES#AccountSetupViewModel.email`（表单字段、`input` 透传）
- `CMP-SCN-ACCOUNT#AccountSetupScene.connect`（地址解析、已有账号迁移、`ConnectedAccount.address`）
- `CMP-ROOT#AppComposition.attachMailbox` / `#CommandLineComposition.make`（启动时按配置显式地址迁移账号行）
- `CMP-STORE#MailStore.updateAccountAddress`（单行更新 `accounts.address`）
- `CMP-DOMAIN#ServerConfiguration.email` / `#resolvedEmail`（additive；旧配置回退）

## 运行序

流程 `F-ACCOUNT-03`：

1. 配置页加载：`AccountSetupViewModel.email` 取配置里的 `email`（旧 Keychain 为 `""`）。
2. 用户填 `user@company.com` → `AccountInput.email` 带入；`AccountSetupScene.configuration(from:)` 保留该值，`resolvedEmail` 返回显式地址。
3. 新账号：`accounts.address` 写入显式地址；`credentials.save(configuration)` 保存同一配置（Keychain 或 `~/.uumail.env` 的 `EAS_EMAIL`）。
4. 已有账号：显式地址与旧地址不同 → `updateAccountAddress` 迁移；返回 `ConnectedAccount.address` 为显式地址。字段留空 → 不更新，返回已存地址。
5. 启动：`AppComposition.attachMailbox`（及 CLI `CommandLineComposition.make`）在配置 `email` 非空且与账号行不同时迁移；`Outbox` 发信从账号行读 `From`。
6. 真实发信：服务器 Sent Items 保存副本，`发件箱` 按 `SCN-0029` 同步拉回。

失败路径：

- 字段留空且账号行已有自定义地址 → 保持原地址，不重置为 `account@host`。
- 显式地址错误/服务器拒绝（如 502）→ 发送失败按既有中文错误呈现，不静默；Sent 无副本。
- 旧配置无 `email` → 解码为 `""`，`resolvedEmail` 回退；不阻塞启动/发信。
- Keychain/DotEnv 写入失败 → 沿用既有凭据保存失败路径，不改账号行迁移的原子性（迁移在保存前）。

## 不可变引用

- `SCN-0001`：账号接入顺序（probe → provision → 账号/文件夹 → credentials last）；本卡只在其中补地址解析与迁移。
- `SCN-0002`：文件夹树与 `applyFolderSnapshot`；本卡不改。
- `SCN-0029`：发件箱 Sent Items 同步；本卡保证 `From` 正确，使服务器保存副本。
- 不改 `SendMail`/EAS、schema、target、依赖；`Outbox` 仍读 `accounts.address`，不新增发信参数。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0030-01` | 正 | 新账号 + `email = "jdoe@corp.test"` → `accounts.address == "jdoe@corp.test"`、`ConnectedAccount.address` 一致、凭据保存的 `configuration.email` 一致（L1 `AccountSetupSceneTests`） |
| `T-SCN-0030-02` | 正 | 旧 payload 无 `email` → 解码 `email == ""`、`resolvedEmail == "u@mail.example.com"`；重复 `connect` 且 `email` 留空 → 保留已存自定义地址 `old@corp.test`（L1 `legacyConfigurationDecoding` + `repeat connect`） |
| `T-SCN-0030-03` | 正 | 已有账号 + 显式 `email` → `accounts.address` 迁移为新地址、`ConnectedAccount.address` 为新地址；启动路径同规则（L1 `AccountSetupSceneTests.explicitEmail`） |
| `T-SCN-0030-04` | 反 | 留空 + 自定义旧地址 → 不得被重置为 `account@host`；显式错误地址发信被网关拒绝 → 中文错误可见、无 Sent 副本（L1 留空保护 + 真实发信 502 记录） |

## 状态

`verified`（2026-11-25 实现并验证）。

- 实现：`ServerConfiguration.email`/`resolvedEmail`（旧解码回退）、`AccountInput.email`、`AccountSetupViewModel.email`/表单字段、`AccountSetupScene` 地址解析与迁移、`MailStore.updateAccountAddress`、`AppComposition`/`CommandLineComposition` 启动迁移、DotEnv/CLI `EAS_EMAIL`、`uumailctl sync-sent`。
- 证据（L1）：`Tests/MailDomainTests` 的 legacy decode 断言、`Tests/ScenesTests/AccountSetupSceneTests` 的 `explicitEmail` 与 repeat-connect 用例；全量 465 tests / 77 suites、架构 4/4。
- 证据（真实）：先用 `账号@host` 发信被网关 502；用 `EAS_EMAIL` 后发送成功，`uumailctl sync-sent` 从服务器 Sent Items 拉到 12 封（含测试信）。
- 未覆盖（发布前人工项）：真实 App 设置页输入、Keychain 旧条目迁移的整窗 UI、地址错误的中文提示端到端。
