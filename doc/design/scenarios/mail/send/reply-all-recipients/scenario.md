---
layer: design
module: mail
scope: project:uumail
status: verified
updated: 2026-11-14
flow: mail/send
scenario: SCN-0007
---

# SCN-0007 全部回复的收件人与抄送预填

**结果**：用户在阅读页选中一封多人邮件点「全部回复」，撰写页的收件人已带入原发件人与原收件人、抄送已带入原抄送人；地址去重并排除当前账号自己。用户可直接编辑并发送，种子构建全程不触网。

## 入口

- `CMP-SCN-COMPOSE#replyAllSeed`（`Sources/Scenes/ComposeScene.swift`；T-1114-06）
- `CMP-DOMAIN#AddressList`（`Sources/MailDomain/AddressList.swift`；T-1114-03）
- `CMP-STORE#messages`、`#searchLocal`（读原邮件 To/Cc）、`#account`（当前账号地址）、`#applySyncBatch`（v9 回填写 cc）；T-1114-05
- `CMP-EAS#sync`、`CMP-EASADAPTER#fetchMessages`（Cc 采集链路；T-1114-02、T-1114-04）
- `CMP-PRES#MailboxViewModel.composeReplyAll`、`#ComposeViewModel.init(replyingAllTo:...)`（T-1114-07）
- `CMP-APP#MailboxView` 工具栏「全部回复」（T-1114-08）

## 运行序

流程 `F-REPLYALL-01`：

1. 用户在阅读页选中邮件，点「全部回复」；`MailboxViewModel.composeReplyAll()` 取 `selectedMessage` 与 `account`，只读本地 `messages`/`searchLocal` 结果，不发网络请求。
2. `ComposeScene.replyAllSeed(to:bodyHTML:account:)`：
   - 经 `MailStore.account(account)` 读当前账号地址；读取失败/缺失时不做排除，继续打开撰写页；
   - `to` = 原发件人 + 原 `recipients`：`AddressList` 拆分纯地址，按小写地址去重并保序，去掉与账号地址相同者；
   - `cc` = 原 `cc`：同样拆分/去重/排除自己，再减去已在 `to` 的地址；
   - 主题与引用沿用 `replySeed`（`Re:` 不重复、`(无主题)` 回退、`--- 原邮件 ---`）；`Draft.cc` 为空时写 `nil`。
3. `ComposeViewModel(mode: .replyAll, to: draft.to, cc: draft.cc ?? "", ...)`；撰写页两个字段可编辑，`canSend` 仍只要求 `to` 非空。
4. 用户点发送 → `ComposeScene.send` 只入队，走 `SCN-0006` 的 `Outbox`/`MimeBuilder`；`Draft.cc` 写成 `Cc:` 头，本场景不改投递规则。

失败路径：

- 原邮件缺 `From`/`To`/`Cc`：只填可解析项，不编造；`to` 为空时 `canSend == false`，用户可手填后发送。
- 地址畸形、只有显示名、裸通讯组名：跳过该段，不阻塞其余地址，不因单个坏地址崩溃；`<>` 内的非 SMTP/DN 形态原样保留。
- 引号内逗号、尖括号内分隔符：不拆；`"Doe, John" <j@x>` 取 `j@x`。
- 原邮件只包含自己：排除后 `to`/`cc` 为空，不把自己填回去。
- 账号地址读取失败：不排除任何地址，继续打开撰写页，不崩溃。
- 历史邮件 `cc` 为空：不伪造；v9 会把消息集合 sync key 置 `"0"`，升级后下一次同步重拉最近窗口（≤5×25 封）补 `cc`；更早邮件保持为空，仍可用 To。
- 网关 Sync 信封不返回 `Cc`：本场景不通过；停在 T-1114-02 的验证并按 REQ-0012 重议，不改需求为「只填 To」。

## 不可变引用

- 单回复种子 `To =` 原发件人、`Cc =` 空；转发种子收件人为空：本次不改（`CMP-SCN-COMPOSE#replySeed`、`#forwardSeed`）。
- `SCN-0006` 的发送入队、`Outbox` 状态机、`ClientId` 幂等与 MIME 规则：本次不改。
- `Draft.cc → Cc:` 头的既有行为（`Outbox/MimeBuilder`）：只验证，不改。
- `MailGateway` / `SyncStore` 协议签名：本次不改；`Message` 只加可选 `cc`。
- EAS 线格式与 `Cc` token：以 `CMP-EAS/playbook.md` 与 fixture 为准，不在场景层拼 WBXML。

## 测试

| ID | 类型 | 方案 | 可执行 ID（已验证） |
|---|---|---|---|
| `T-SCN-0007-01` | 正 | 原邮件 `From="张三" <z@corp.test>`、`To="a@corp.test; b@corp.test"`、`Cc="c@corp.test; z@corp.test"`；账号 `me@corp.test`。全部回复 → `To == "z@corp.test; a@corp.test; b@corp.test"`，`Cc == "c@corp.test"`（`z@` 已在 To，从 Cc 去掉），主题 `Re:`，正文含引用。 | `ScenesTests/ComposeSceneTests.replyAllFillsSenderAndOriginalRecipients` |
| `T-SCN-0007-02` | 正 | 同一封邮件全部回复并发送 → outbox 行 `to/cc` 与种子一致；MIME 带 `Cc:` 且地址与 outbox 行一致；投递只一次。 | `PresentationTests/ComposeViewModelTests.replyAllSendCarriesCcIntoOutbox` + 既有 `OutboxTests/OutboxDeliveryTests.deliversOnce`（以 `c@d.e` 断言 `Cc:` 进 MIME） |
| `T-SCN-0007-03` | 正 | 构造 pre-v9 库：已同步消息无 `cc`，有正文与附件缓存；v9 迁移后消息集合 `sync_key == "0"`、`folders` key 不变、`cc == nil` 可读；按既有 key 0 bootstrap 路径重拉（`SyncEngineTests.bootstrap` 已覆盖两请求语义）；store 层用 `applySyncBatch(changed:)` 把同一消息 + Cc 写回 → 本地 `Message.cc` 可读，正文/附件仍在；同一 store 上 `replyAllSeed` 带出 Cc。 | `MailStoreTests/MigrationTests.v9MessageCcMigration` + 既有 `SyncEngineTests/SyncEngineTests.bootstrap` + `ScenesTests/ComposeSceneTests.replyAllUsesBackfilledCc`（该用例自带 pre-v9 fixture，真实走 v9 迁移 → `applySyncBatch(changed:)` → `replyAllSeed`） |
| `T-SCN-0007-04` | 反 | 头缺失/畸形：无 `From`、`To` 为空、`Cc` 只有自己、重复地址、引号内逗号、裸通讯组名/只有显示名。断言：不崩溃、不编造、不重复、不含自己；`To` 为空时 `canSend == false`；手填后可发送。 | `ScenesTests/ComposeSceneTests.replyAllSkipsMalformedAndSelf` + `PresentationTests/ComposeViewModelTests.replyAllEmptyToCannotSend` |

支撑测试（不属于 3+1 断言，但组件出口要求）：

- `MailDomainTests.AddressList`：拆分/引号/尖括号/去重/排除自己/空输入的表驱动用例（T-1114-03）。
- `EASClientTests`：Sync fixture 同时输出 `To`/`Cc` 并断言 `EASMessage.cc`（T-1114-02，先证网关返回）。
- `EASAdapterTests`：`fetchMessages` 的 Cc 映射（T-1114-04）。
- `MailStoreTests`：`applySyncBatch` 的 To/Cc `COALESCE`，partial `Change` 不清空已有值（T-1114-05）。
- `SyncEngineTests/SyncEngineTests.bootstrap`：既有 key 0 两请求路径，证明迁移置 `"0"` 后下一次同步会重拉（不新增测试）。
- `MailboxViewModelTests`：`composeReplyAll` 的选中邮件接线（T-1114-07）。

## 状态

`verified`（2026-11-14，T-1114-09）。

验证证据（`./Scripts/swiftw test`，2026-11-14）：

| 测试 | 断言 | 结果 |
|---|---|---|
| `T-SCN-0007-01` `ScenesTests/ComposeSceneTests.replyAllFillsSenderAndOriginalRecipients` | `To` = 原发件人 + 原收件人、保序；`Cc` 去重且减去已在 `To` 者；主题/引用不变 | 通过 |
| `T-SCN-0007-02` `PresentationTests/ComposeViewModelTests.replyAllSendCarriesCcIntoOutbox` + `OutboxTests/OutboxDeliveryTests.deliversOnce` | outbox 行 `to/cc` 与种子一致；MIME 带 `Cc:`；`ClientId` 幂等、只投递一次 | 通过 |
| `T-SCN-0007-03` `MailStoreTests/MigrationTests.v9MessageCcMigration` + `SyncEngineTests.bootstrap` + `ScenesTests/ComposeSceneTests.replyAllUsesBackfilledCc` | pre-v9 库 `cc == nil`、正文/附件保留、消息 `sync_key` 置 `"0"`、folders key 不变；同一用例内 pre-v9 → v9 迁移 → `applySyncBatch(changed:)` 把 Cc 写回同一消息 → `replyAllSeed` 带出该 Cc | 通过 |
| `T-SCN-0007-04` `ScenesTests/ComposeSceneTests.replyAllSkipsMalformedAndSelf` + `PresentationTests/ComposeViewModelTests.replyAllEmptyToCannotSend` | 畸形/重复/自己/无 `From`/空 `To` 不崩溃、不编造；空 `To` 时 `canSend == false`，手填后可发送 | 通过 |

支撑测试：`ComposeSceneTests` 10 例（含「账号地址读取失败不排除任何地址」）、`ComposeViewModelTests` 8 例、`MailboxViewModelTests` 16 例（5 suites）、`MigrationTests` 2 例、`EASClientTests` 27 例（6 suites）、`EASAdapterTests` 6 例、`MailDomainTests` 10 例、`Outbox` 相关 30 例（4 suites）、`OutboxPumpTests` 3 例；全量 **182 tests / 38 suites** 绿，架构门 4/4 PASS。`SCN-0006` 回归：发送入队、离线恢复、泵投递、单次投递与 MIME `Cc:` 用例均未退化；`SCN-0006` 自身仍为 `designed`，其未验项不变。

实现沿革：`designed`（2026-11-14，T-1114-01）；`T-1114-02`（Sync 信封 `Cc` 采集）、`T-1114-03`（`Message.cc`、`AddressList`）、`T-1114-04`（适配层映射）、`T-1114-05`（schema v9 回填）、`T-1114-06`（`replyAllSeed`）、`T-1114-07`（视图模型）、`T-1114-08`（工具栏）已落地。

真机 UI 冒烟（2026-11-14，T-1114-09 第 2 轮）：在 macOS 26.6.2 的图形会话里启动真实 `uumail` app bundle（DEBUG），使用应用数据库的副本，并插入一封本地构造的「带 Cc 多人邮件」——`From` 为当前账号自己、`To` 为 `a@corp.test; b@corp.test`、`Cc` 为 `c@corp.test; 自己`。通过应用自身 AX 树选中该邮件并点击「全部回复」：撰写页 `To = a@corp.test; b@corp.test`、`Cc = c@corp.test`，自己未出现在任一栏；点击「发送」后 Outbox 行 `to/cc` 与种子一致，`MimeBuilder` 生成的 MIME 含 `To:`/`Cc:` 且无自己。为避免向真实同事投递，冒烟使用仅本地的录制网关：MIME 落盘后返回 `offline`，Outbox 行保留为 `failed_retryable`，未向真实邮箱发信。被测的工具栏点击、`ComposeScene.replyAllSeed`、`Outbox`、`MimeBuilder` 均为真实代码。
