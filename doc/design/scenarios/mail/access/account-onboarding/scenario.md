---
layer: design
module: mail
status: designed
updated: 2026-11-13
flow: mail/access
scenario: SCN-0001
---

# SCN-0001 账号接入与设备身份

**结果**：用户在一台新 Mac 上填入服务器、账号与已登记的设备 ID，客户端完成策略握手并落下可同步的账号，进入收件箱。

## 入口

- `CMP-EAS#options`、`CMP-EAS#provision`（`design/components/CMP-EAS/spec.md`）
- `CMP-STORE#applyFolderSnapshot`（`design/components/CMP-STORE/spec.md`）
- 入口符号：`Sources/EASClient/EASClient.swift`（`options` / `provision` / `folderSync`）、`Sources/MailStore/MailStore.swift`（`applyFolderSnapshot`）、`Sources/uumail/AccountSetupView.swift`。

## 运行序

流程 `F-ACCESS-01`：

1. 用户在设置页填服务器地址、账号、密码、设备 ID（自动发现不可用，直接手填；见 playbook §1）。
2. `CMP-EAS#options` 打裸 URL，取协议版本与命令列表；失败即停止并提示网络或网关问题。
3. 若无 PolicyKey：`CMP-EAS#provision` 两步握手，正式 PolicyKey 存 Keychain。
4. `CMP-EAS#folderSync(0)` 取文件夹树。
5. `CMP-STORE#applyFolderSnapshot` 原子落库账号、文件夹树与同步状态。
6. 账号状态置 `ready`，跳转收件箱并触发一次 `SCN-0003`。

失败路径：

- `444` → 参数拼装错误，属缺陷，提示重新配置；
- `200` 空 body / 写命令 `401` → `deviceNotRegistered`，展示设备登记指引（playbook §6），**不进入重试循环**；
- 认证 `401` → `authFailed`，回到凭据输入，不自动重试；
- `449` → 进 Provision；仍失败则 `policyBlocked`，保留本地配置供用户重试；
- 落库失败 → 整批回滚，账号保持 `draft`，不得出现「账号已建但无文件夹」的半成品。

## 不可变引用

- `CMP-EAS#provision` 的两步握手与 `X-MS-PolicyKey` 常驻（playbook §2、§3）。
- `CMP-STORE#applyFolderSnapshot` 的事务语义与幂等键。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0001-01` | 正 | 手填正确配置 → 账号 `ready`、文件夹树非空、PolicyKey 入 Keychain |
| `T-SCN-0001-02` | 正 | 已有 PolicyKey 的账号重连 → 跳过 Provision 第一步，直接 FolderSync 成功 |
| `T-SCN-0001-03` | 正 | 网关返回 449 → 自动 Provision 后重试成功，账号状态不被污染 |
| `T-SCN-0001-04` | 反 | 设备未登记（200 空 body）→ 错误分类为 `deviceNotRegistered`，UI 出现登记指引，且 5 分钟内无自动重试 |

## 状态

`designed`（2026-11-13 核对）。运行序、引用、测试方案与入口齐；实现与验证如下。

实现：配置页、Keychain 存储、`uumailctl seed`、同步前 `provisionIfNeeded` 已落地；账号行由 `MailStore.createAccount` 写为 `draft`，**没有 `ready` 状态机**，这是本场景未完成的最后一跳。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0001-01` | 部分：真机配置页 + Keychain 免配置启动 + 自动同步（`CMP-APP/spec.md`）；账号状态仍为 `draft`，未断言 `ready` |
| `T-SCN-0001-02` | 未覆盖：`EASClientTests`「Provision runs both steps and keeps the final policy key」只测握手；无「已有 PolicyKey 跳过第一步」用例 |
| `T-SCN-0001-03` | 未满足：`449` 只在错误映射里断言为 `policyRequired` → `policyBlocked`（`Sources/AppServices/Adapters.swift`）；同步前总做 Provision，但没有「中途 449 自愈」用例 |
| `T-SCN-0001-04` | 部分：`EASClientTests` 覆盖 200 空 body，`SyncEngineTests`「a device rejection stops the run and keeps the failure in the state」覆盖停跑；UI 登记指引与「5 分钟内不重试」未断言 |

未转 `verified` 的原因：3 正 + 1 反没有可执行的场景测试；账号状态机缺失、`449` 自愈未验。
