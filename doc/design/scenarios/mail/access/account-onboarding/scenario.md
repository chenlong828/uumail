---
layer: design
module: mail
status: designed
updated: 2026-11-14
flow: mail/access
scenario: SCN-0001
---

# SCN-0001 账号接入与设备身份

**结果**：用户在一台新 Mac 上填入服务器、账号与已登记的设备 ID，客户端完成策略握手并落下可同步的账号，进入收件箱。

## 入口

- `CMP-SCN-ACCOUNT#validate`、`#connect`（`design/components/CMP-SCN-ACCOUNT/spec.md`）
- `CMP-DOMAIN#MailGateway`（生产实现 `CMP-EASADAPTER`；`probe/provisionIfNeeded/fetchFolders`）
- `CMP-STORE#applyFolderSnapshot`、`#markAccountReady`、`#discardAccount`
- 视图/CLI：`Sources/uumail/AccountSetupView.swift` → `AccountSetupViewModel`；`CommandLineComposition.make` 在空库上引导一次 `AccountSetupScene.connect`。

## 运行序

流程 `F-ACCESS-01`：

1. 用户在设置页填服务器地址、账号、密码、设备 ID（自动发现不可用，直接手填；见 playbook §1）。
2. `MailGateway.probe()` 打裸 URL，取协议版本与命令列表；失败即停止并提示网络或网关问题。
3. `provisionIfNeeded()`：无 PolicyKey 时两步握手；已有则跳过。
4. `fetchFolders(syncKey: "0")` 取全量树。
5. 复用既有账号行，或 `createAccount` 新建。
6. `applyFolderSnapshot` 单事务落文件夹树与同步 key。
7. `markAccountReady`；`credentials.save` **最后**执行。
8. 返回 `ConnectedAccount`，视图/组合根进入邮箱并触发一次 `SCN-0003`。

失败路径：

- `444` → 参数拼装错误，属缺陷，提示重新配置；
- `200` 空 body / 写命令 `401` → `deviceNotRegistered`，展示设备登记指引（playbook §6），**不进入重试循环**；
- 认证 `401` → `authFailed`，回到凭据输入，不自动重试；
- `449` → 进 Provision；仍失败则 `policyBlocked`，保留本地配置供用户重试；
- 文件夹快照或后续步骤失败 → 只回滚**本次新建**的账号（`discardAccount`），不写凭据；复用既有账号时失败保留原账号与数据。

## 不可变引用

- `CMP-SCN-ACCOUNT` 的顺序固定、凭据最后写与回滚规则。
- `MailStore.applyFolderSnapshot` 的事务语义与幂等键。
- `EASClient` 的 Provision 两步握手与 `X-MS-PolicyKey`（playbook §2、§3）；PolicyKey **只在进程内**，不落 Keychain。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0001-01` | 正 | 手填正确配置 → 账号行、文件夹树非空、凭据最后写入（端口/Keychain） |
| `T-SCN-0001-02` | 正 | 已有 PolicyKey 的账号重连 → 跳过 Provision 第一步，直接 FolderSync 成功 |
| `T-SCN-0001-03` | 正 | 网关返回 449 → 自动 Provision 后重试成功，账号状态不被污染 |
| `T-SCN-0001-04` | 反 | 设备未登记（200 空 body）→ 错误分类为 `deviceNotRegistered`，UI 出现登记指引，且 5 分钟内无自动重试 |

## 状态

`designed`（2026-11-14 核对）。运行序、引用、测试方案与入口已按实现更新；实现与验证如下。

实现：`AccountSetupScene`（`1f0c0b3`）已收口接入流程；`CommandLineComposition` 在空库上引导（`fc26985`）；`MailStore` 有 `markAccountReady`/`discardAccount`。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0001-01` | 部分：`ScenesTests`「connect probes, provisions, snapshots folders, marks ready and saves credentials last」断言调用顺序、文件夹与凭据最后写入；`MailStore` 无读账号状态的契约，`ready` 本身不可断言；PolicyKey 不持久化，旧口径「入 Keychain」已更正 |
| `T-SCN-0001-02` | 未覆盖：`EASAdapter.provisionIfNeeded` 在 key 存在时跳过（实现），无「跳过第一步」的测试；`EASClientTests`「Provision runs both steps」只测握手 |
| `T-SCN-0001-03` | 未满足：无「中途 449 自愈」用例；协议侧只断言 449 → `policyBlocked` |
| `T-SCN-0001-04` | 部分：`EASClientTests` 覆盖 200 空 body 映射；`ScenesTests` 覆盖文件夹失败回滚；UI 登记指引与「5 分钟内不重试」未断言 |

未转 `verified` 的原因：4 项没有完整的场景级证据（`ready` 不可观察、PolicyKey 跳过未测、449 自愈未测、5 分钟不重试未测）。
