---
layer: requirements
module: mail
scope: project:uumail
status: delivered
updated: 2026-11-25
---

# REQ-0039 账号邮箱地址可配置

- **ID**：REQ-0039
- **类型**：`feature`
- **场景叙述**：用户在配置页填写「邮箱地址」（例如 `user@company.com`），App 把它作为发信的 `From` 地址、写入本机账号行；旧配置没有该字段时仍按 `账号@服务器地址` 回退。已有账号在重新连接或下次启动读到显式地址时，自动把账号行里的旧地址改过来；用户之前手动改过的地址在字段留空时不会被覆盖。这样 Exchange 主机为 `mail.company.com`、邮箱域为 `company.com` 的账号才能发出服务器接受的邮件，Sent 镜像也才有副本。
- **价值**：不做的后果——`AccountSetupScene` 固定用 `account@host` 生成 `From`，本机实际配置得到 `user@mail.company.com`，网关对错误发件人返回 502，所有发信（含 Sent 镜像）都失败。真实发信验证时已复现：改用真实邮箱地址后同一封测试信发送成功。
- **非目标**：
  - 不做邮箱地址的格式校验/归属校验（交给服务器）；不做多账号、别名、发件人切换。
  - 不改 EAS 协议、`SendMail`、schema、target、依赖；不新增 OAuth。
  - 不改 Outbox 状态机/重试策略；不做本地 Sent 镜像。
- **约束**：
  - `ServerConfiguration.email` 为 additive 字段；旧 Keychain/DotEnv 缺少时解码为 `""`，`resolvedEmail` 回退 `account@host`。
  - 设置页「邮箱地址」留空 = 沿用 `账号@服务器地址`；显式填写才覆盖账号行地址。
  - 迁移只发生在 `AccountSetupScene.connect`（显式邮箱）与 `AppComposition`/`CommandLineComposition` 启动（配置显式邮箱）；留空时**不得**把用户自定义的旧地址重置为 `account@host`。
  - 只改 `accounts.address`（数据迁移），不改表结构；`MailStore.updateAccountAddress` 单行更新。
  - 失败可见：地址错误时服务器返回的错误仍按既有中文文案呈现，不吞错。
- **影响场景**：
  - **新建 `SCN-0030`（`settings/account/mail-address`）**：认领显式邮箱写入、旧配置回退、显式邮箱迁移已有账号与留空保护（3 正 1 反）。
  - 回归（不新增断言）：`SCN-0001`（账号接入）、`SCN-0002`（文件夹树）、`SCN-0029`（发件箱 Sent 同步）。
- **澄清记录**：
  - 2026-11-25 **人工确认**：正式修发件地址，增加邮箱地址配置并迁移已存账号（`EAS_EMAIL` 已在开发 `.env` 中）。
  - 2026-11-25 默认（未经人工）：字段留空不覆盖自定义旧地址；不做格式校验；只改账号行地址，不改 schema。
- **状态**：`delivered`（2026-11-25 实现：`ServerConfiguration.email`/`resolvedEmail`、设置页字段、`.env`/CLI `EAS_EMAIL`、`accounts.address` 迁移、`MailStore.updateAccountAddress`、`uumailctl sync-sent`；`SCN-0030` verified；465 tests / 77 suites、架构 4/4；真实发信修正地址后成功）
- **验收归属**：`SCN-0030` 的 3 正 1 反通过 + 上述约束逐条无违反 + `SCN-0029` 不退化；需求不另立测试。
