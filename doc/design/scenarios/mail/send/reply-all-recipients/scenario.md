---
layer: design
module: mail
scope: project:uumail
status: designed
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

| ID | 类型 | 方案 | 可执行 ID（拟） |
|---|---|---|---|
| `T-SCN-0007-01` | 正 | 原邮件 `From="张三" <z@corp.test>`、`To="a@corp.test; b@corp.test"`、`Cc="c@corp.test; z@corp.test"`；账号 `me@corp.test`。全部回复 → `To == "z@corp.test; a@corp.test; b@corp.test"`，`Cc == "c@corp.test"`（`z@` 已在 To，从 Cc 去掉），主题 `Re:`，正文含引用。 | `ScenesTests/ComposeSceneTests.replyAllFillsSenderAndOriginalRecipients` |
| `T-SCN-0007-02` | 正 | 同一封邮件全部回复并发送 → outbox 行 `to/cc` 与种子一致；MIME 带 `Cc:` 且地址与 outbox 行一致；投递只一次。 | `PresentationTests/ComposeViewModelTests.replyAllSendCarriesCcIntoOutbox` + 既有 `OutboxTests/OutboxDeliveryTests.deliversOnce`（以 `c@d.e` 断言 `Cc:` 进 MIME） |
| `T-SCN-0007-03` | 正 | 构造 pre-v9 库：已同步消息无 `cc`，有正文与附件缓存；v9 迁移后消息集合 `sync_key == "0"`、`folders` key 不变、`cc == nil` 可读；按既有 key 0 bootstrap 路径重拉（`SyncEngineTests.bootstrap` 已覆盖两请求语义）；store 层用 `applySyncBatch` 写入同一消息 + Cc → 本地 `Message.cc` 可读，正文/附件仍在；全部回复带出 Cc。 | `MailStoreTests/MigrationTests.preV9MessageGetsCcAfterBackfill` + 既有 `SyncEngineTests/SyncEngineTests.bootstrap` + `ScenesTests/ComposeSceneTests.replyAllUsesBackfilledCc` |
| `T-SCN-0007-04` | 反 | 头缺失/畸形：无 `From`、`To` 为空、`Cc` 只有自己、重复地址、引号内逗号、裸通讯组名/只有显示名。断言：不崩溃、不编造、不重复、不含自己；`To` 为空时 `canSend == false`；手填后可发送。 | `ScenesTests/ComposeSceneTests.replyAllSkipsMalformedAndSelf` + `PresentationTests/ComposeViewModelTests.replyAllEmptyToCannotSend` |

支撑测试（不属于 3+1 断言，但组件出口要求）：

- `MailDomainTests.AddressList`：拆分/引号/尖括号/去重/排除自己/空输入的表驱动用例（T-1114-03）。
- `EASClientTests`：Sync fixture 同时输出 `To`/`Cc` 并断言 `EASMessage.cc`（T-1114-02，先证网关返回）。
- `EASAdapterTests`：`fetchMessages` 的 Cc 映射（T-1114-04）。
- `MailStoreTests`：`applySyncBatch` 的 To/Cc `COALESCE`，partial `Change` 不清空已有值（T-1114-05）。
- `SyncEngineTests/SyncEngineTests.bootstrap`：既有 key 0 两请求路径，证明迁移置 `"0"` 后下一次同步会重拉（不新增测试）。
- `MailboxViewModelTests`：`composeReplyAll` 的选中邮件接线（T-1114-07）。

## 状态

`designed`（2026-11-14，T-1114-01）。入口、运行序、不可变引用、3 正 1 反测试方案已齐；四元素无 `missing`。测试尚未执行，`verified` 留待 T-1114-09。

实现：部分开始（2026-11-14）。`T-1114-02`（Sync 信封 `Cc` 采集）、`T-1114-03`（`CMP-DOMAIN#Message.cc`、`#AddressList`）、`T-1114-04`（`CMP-EASADAPTER` 的 `Cc` 映射）、`T-1114-05`（`CMP-STORE` schema v9 `cc` 读写与回填）与 `T-1114-06`（`CMP-SCN-COMPOSE#replyAllSeed` 合并 To/Cc、去重、排除自己、Cc 减 To）已落地；`T-1114-07..08` 未开始，其余 change 仍待 P1 实现门确认。设计拍板与候选见 `task-spaces/20261114-103223/design.md`。`Cc` 网关可达性已由 `T-1114-02` 证明；`SCN-0007` 保持 `designed`，3 正 1 反与 `verified` 留待 `T-1114-09`。
