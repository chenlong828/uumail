---
layer: design
module: mail
scope: project:uumail
status: designed
updated: 2026-11-14
flow: mail/read
scenario: SCN-0009
---

# SCN-0009 列表键盘删除

**结果**：焦点在邮件列表时，用户按 Delete 或 Backspace，当前选中邮件立即从当前列表（含搜索结果）消失；服务器确认删除成功后本地软删、下次同步不复活，选中推进到相邻邮件。删除失败时行与选中恢复、正文可重开、状态栏显示中文错误，邮件不丢，可重试。服务器已无该邮件视为成功。

## 入口

- `CMP-APP#MailboxView`（列表焦点下的 `.onDeleteCommand`/等价 Delete/Backspace 绑定、前台/失活 `NSApplication` 通知转发；视图不判业务；T-1114-18）
- `CMP-PRES#MailboxViewModel.deleteSelected`、`MailboxDeletion`（临时隐藏集、单飞、选中推进/恢复、错误展示；T-1114-17）
- `CMP-SCN-READ#deleteMessage`（删除编排；不本地预删；T-1114-16）
- `CMP-SYNC#deleteMessage`（与 `syncOnce` 共享 key 的显式串行门；T-1114-15）
- `CMP-STORE#commitDelete`（服务器成功后 delta + 软删 + key 同事务；复用 `deleted_at`；T-1114-14）
- `CMP-DOMAIN#MailWriteGateway.delete`（T-1114-11）、`#SyncStore.commitDelete`（T-1114-14）
- `CMP-EASADAPTER#delete`、`CMP-EAS#sync(change: .delete)`（`Delete` + `ServerId`；T-1114-13/T-1114-12）

## 运行序

流程 `F-READ-03`：

1. 焦点在邮件列表且存在选中项；按 Delete/Backspace。焦点在搜索框、正文、撰写 sheet、配置页时按键不进入本流程。
2. `MailboxViewModel.deleteSelected`：`MailboxDeletion.begin(ref)` 把 `MessageRef` 放入隐藏集并立即重绘（行消失），置 `isDeleting = true`；取消该邮件的已读计时。
3. 选中推进：取删除项在 `visibleMessages` 中的位置，选下一封；末条选上一封；列表为空时清空正文与选中，显示空态。正文按本地缓存打开下一封。
4. 调 `ReadScene.deleteMessage(ref)` → `SyncEngine.deleteMessage`：FIFO 门内读当前集合 `SyncKey` → `Sync` 携带 `Delete/ServerId` → 服务器返回 delta + 新 `SyncKey`。
5. 成功：`MailStore.commitDelete` 把「响应 delta + `deleted_at=now` + 新 key」同事务提交；VM 按当前列表模式重载（搜索模式按当前搜索词重查，不切回文件夹列表），删除行不再出现；保留推进后的选中；隐藏集清除。后续增量同步不复活。
6. 失败：`MailboxDeletion.commit` 移除隐藏、写中文 `errorText`；VM 重载并恢复删除前的选中与正文；状态栏显示错误，不弹模态；本地行未软删，可重试。
7. 服务器已无该邮件（删除幂等）→ 视为成功，本地软删（逐条 not-found 语义以 T-1114-12 样本为准；无明确状态时不把通用失败当成功）。
8. 同一时刻只允许一个删除在飞；在飞期间再次按键返回 `.ignored`，不重复发网络；等待期间同步返回该邮件时隐藏集优先，不让它闪回。

失败路径：

- 离线/超时/`503`/`authFailed`/`deviceNotRegistered`/`policyBlocked` → 恢复 + 中文错误，不排队、不重试。
- `SyncKey` 失步（`Status=3/4`）→ 恢复 + 错误；下一次刷新按既有规则重建，不以删除失败触发全量重建。
- 本地软删提交失败而服务器已成功 → `commitDelete` 回滚，`SyncEngine` 抛 `storage`；VM 恢复行并提示错误；下一次同步的 `removedServerIDs` 负责收敛，不丢邮件。
- 删除等待期间同步返回该邮件 → 隐藏集优先，不闪回；失败恢复后按服务器事实显示。
- 列表在等待期间切换文件夹/搜索 → 隐藏集只作用于 `MessageRef`（folder + serverID）；完成回调不跨文件夹强行恢复/推进，不覆盖用户新选择。
- 删除失败后用户已改选 → 不强行恢复旧选中，只恢复行与错误提示；正文保持用户当前选择。

## 不可变引用

- 列表排序（`received_raw DESC, server_id DESC`）、软删过滤（`deleted_at IS NULL`）、搜索 FTS 与正文/附件缓存语义不变。
- 删除只软删 `messages`，不物理删 `messages`/`message_bodies`/`attachments`；附件保留策略不变。
- 服务器侧按 EAS 客户端删除语义（移到「已删除邮件」）；不显式带 `DeletesAsMoves`。R16 真机样本（2026-11-14）已确认：删除后收件箱不再返回该 `ServerId`，同一封出现在 `Type=4`「已删除邮件」中（新 `ServerId`），不是永久删除。
- 同一账号同一集合同时只有一个 `Sync` 在飞；写结果与 `SyncKey` 同事务；失败不推进 key、不半删。
- `MailGateway` 读签名、`Outbox`、发送、通知、同步窗口与「列表查询不扫正文」不变。
- 不做多选；`List(selection:)` 仍是单选中；不做撤销、永久删除、确认框、离线队列。
- `ReadScene` 的既有本地读方法仍零网络；`deleteMessage` 是新增的显式写方法，只经 `SyncEngine`。

## 测试

| ID | 类型 | 方案 | 可执行 ID（拟） |
|---|---|---|---|
| `T-SCN-0009-01` | 正 | 选中一封按 Delete → 行立即消失、正文切到下一封；服务器删除命令恰好一次且带当前 key；成功后 `messages` 软删、`loadCached` 不再出现；key 推进。 | `PresentationTests/MailboxViewModelTests.deleteSelectedHidesRowAndAdvancesSelection` + `ScenesTests/ReadSceneTests.deleteSoftDeletesOnlyAfterGatewaySuccess` + `SyncEngineTests/SyncEngineTests.deleteAdvancesKeyOnce` |
| `T-SCN-0009-02` | 正 | 删唯一一封 → 列表空态、正文 `.none`、不崩溃；搜索结果中删除 → 搜索列表与文件夹列表都不再返回该行，选中推进正确。 | `PresentationTests/MailboxViewModelTests.deleteLastMessageClearsSelectionAndBody` + `...deleteFromSearchResultsRemovesFromFolderList` |
| `T-SCN-0009-03` | 正 | 服务器回「已不存在」→ 视为成功并本地软删；连按两次只发一次网络；删除成功后下一轮增量同步不复活该邮件。 | `PresentationTests/MailboxViewModelTests.deleteTwiceSendsOneNetworkWrite`（连按去重在 VM）+ `SyncEngineTests/SyncEngineTests.deleteIsIdempotentAndAdvancesKeyOnce`（服务器 not-found 幂等 + key 只推进一次）+ `ScenesTests/ReadSceneTests.deleteDoesNotResurrectOnNextSync` |
| `T-SCN-0009-04` | 反 | 服务器删除失败（offline/503）→ 行恢复原位置、选中恢复、状态栏中文错误、`MailStore` 行未软删；重试成功后删除。无选中时按键不删除、不发网络；焦点在搜索框时按键不删除、不发网络。 | `PresentationTests/MailboxViewModelTests.deleteFailureRestoresRowAndShowsError` + `...deleteWithoutSelectionDoesNothing` + 焦点/按键 UI 探针证据（T-1114-18） |

支撑测试（不属于 3+1 断言，但组件出口要求）：

- `MailStoreTests`：`commitDelete` 软删 + key 同事务、回滚不推进 key、重复软删幂等、正文/附件表不动。
- `EASClientTests`：`Delete/ServerId` golden 请求、新 key、`Status=3/4`、写 401 → `deviceNotRegistered`、删除 not-found 样本（R16 已取证：重复删除同一 `ServerId` 返回 `Collection/Status=1` + 新 key，无逐条状态，视为成功 no-op；见 `task-spaces/20261114-232232/evidence/r16-real-gateway.txt`）。
- `EASAdapterTests`：`MailWriteGateway.delete` 的 delta/错误映射。
- `SyncEngineTests`：写命令与 `syncOnce` 的门串行（删除等待一次 Sync，不被分页拖住）；同一 key 不被两个写推进。
- `MailboxViewModelTests`：等待期间同步返回被删邮件不闪回；切换文件夹/搜索不跨列表恢复；连按只发一次。
- `CompositionTests`：`GatewayEndpoints.write` 非可选且生产 `write` 为 `EASAdapter`（T-1114-21）；同一 `SyncEngine` 注入 `SyncScene` 与 `ReadScene` 的装配检查（T-1114-15/16）。

## 状态

`designed`（2026-11-14，T-1114-10）。四元素齐；3 正 1 反均给出可执行 ID。**已实现**（2026-11-14，T-1114-11…18/21）：`MailWriteGateway.delete`、`SyncEngine.deleteMessage`、`ReadScene.deleteMessage`、`MailboxDeletion`、列表 Delete/Backspace 绑定均已落地；全量 239 tests / 44 suites 绿。**未标 `verified`**：验证节点 T-1114-20 尚未运行/未评审。

实现前门均已关闭：P1 frozen 记录 `doc/history/decisions/2026-11-14-mail-write-path.md` 已归档；R16 真机已证 `Delete/ServerId` 被接受、返回新 key 并把邮件移入「已删除邮件」（2026-11-14）；焦点/按键探针覆盖列表、搜索框、正文、撰写页、配置页（证据见 `task-spaces/20261114-232232/evidence/ui-delete-probe-focus.txt`）。验证归属：`T-SCN-0009-01..04` 全绿并转 `verified` 前，`REQ-0014` 不得 `delivered`。
