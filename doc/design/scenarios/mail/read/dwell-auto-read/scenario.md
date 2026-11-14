---
layer: design
module: mail
scope: project:uumail
status: designed
updated: 2026-11-14
flow: mail/read
scenario: SCN-0008
---

# SCN-0008 列表停留自动已读

**结果**：用户在邮件列表选中一封未读邮件并保持选中，应用在前台连续 10 秒后，该邮件在本机转为已读：列表蓝点消失、主题字重回到常规；状态持久化，不等待网络。服务器回写在后台尽力完成，使其他客户端可见；回写失败不回滚本地已读、不弹错误。10 秒内切换选中、切换文件夹/搜索、删除该邮件或应用失活会取消计时；回到前台且该邮件仍选中时重新计满 10 秒。

## 入口

- `CMP-PRES#MailboxViewModel`（`MailboxDwell` 10 秒计时、前台状态、选中变化/重载取消；`visibleMessages` 驱动蓝点；T-1114-17）
- `CMP-PRES#MailboxDwell`（可注入 sleep；不读系统时间；不把计时放进场景）
- `CMP-SCN-READ#markReadLocally`、`#writeBackMarkRead`（本地置读与服务器回写两阶段；T-1114-16）
- `CMP-SYNC#markRead`（与 `syncOnce` 共享集合 key 的显式串行门；T-1114-15）
- `CMP-STORE#markRead`、`#commitMarkRead`（本地置读；写成功后 delta + read + key 同事务；T-1114-14）
- `CMP-DOMAIN#MailWriteGateway.markRead`（T-1114-11）、`#SyncStore.markRead`/`#commitMarkRead`（T-1114-14）
- `CMP-EASADAPTER#markRead`、`CMP-EAS#sync(change: .read)`（`Change` + `ApplicationData/Read=1`；T-1114-13/T-1114-12）
- `CMP-APP#MailboxView`（`scenePhase` 前后台转发；不写业务；T-1114-18）

## 运行序

流程 `F-READ-02`：

1. 列表选中变化（鼠标、键盘、自动选中首封）→ `MailboxDwell.update` 取消上一封计时；新选中项 `isRead == false`、`isApplicationActive` 且**不在搜索模式** → 启动 10 秒计时；否则不计时。
2. 计时期间发生选中变化、文件夹切换、进入/停留在搜索、删除、应用失活 → 取消计时；回到前台且仍选中同一未读邮件（且不在搜索模式）→ `update` 看到从不可计到可计的变化，重新计满 10 秒，不累计。
3. 普通同步重载列表 → `MailboxDwell.update` 收到同一 target 且仍合格时**不重启**计时；若该邮件已被同步置读/删除/移走，取消。
4. 计时到点 → `MailboxDwell` 再次确认仍可计 → 调 `ReadScene.markReadLocally(ref)`；`MailStore.markRead` 在本地事务中置 `is_read = 1`，返回是否发生 0→1 转换。
5. 本地成功 → `MailboxDwell.onMarked` → `MailboxViewModel` 重新读本地列表（蓝点立即消失、字重常规）；仅当 `markReadLocally` 返回 true（0→1）时后台启动 `ReadScene.writeBackMarkRead(ref)`。返回 false（已被同步置读/已删）时也重载一次以纠正陈旧列表，但不回写。
6. `SyncEngine.markRead` 在 FIFO 门内再钉一次本地已读 → 读当前集合 `SyncKey` → `Sync` 携带 `Change/Read=1` → 服务器返回 delta + 新 `SyncKey` → `MailStore.commitMarkRead` 把「响应 delta + `is_read=1` + 新 key」同事务提交。
7. 服务器回写失败：本地已读保持，不弹错、不重试、不推进 key；返回 `.failed(MailError)` 仅供诊断/测试，PRES 不展示。下一次普通同步仍按服务器事实更新其它邮件。
8. 已读邮件再次被选中、重复计时、重复回写：不产生第二次网络写；`markReadLocally` 返回 false 时不启动回写。

失败路径：

- 本地写失败 → `markReadLocally` 抛错；`MailboxDwell` 不重载、不回写；列表仍显示未读；无 UI 错误（罕见，按存储错误记录）。
- 服务器回写失败（`offline`/`throttled`/`authFailed`/`deviceNotRegistered`/`policyBlocked`/`unsupported`）→ 本地已读保持，无 UI 错误；本次回写不直接暂停自动刷新；下一次 `SyncScene` 刷新若仍失败，按既有规则暂停。
- 回写时 `SyncKey` 失步（`Status=3/4`）→ 只算回写失败；下一次刷新按既有规则重建，不用已读回写触发重建。
- 计时到点前邮件被删/被移走/列表重载导致选中消失 → 取消，不报错。
- 应用在计时期间失活 → 取消；回前台重新计满，不累计。
- 回写响应 `moreAvailable == true` → 视为协议异常，`SyncEngine` 抛 `unsupported`；不提交 delta/key；本地已读保持；T-1114-12 样本再决定是否 drain。

## 不可变引用

- `ReadScene` 的本地读方法（`folders/messages/search/attachments/bodyIfCached/open`）仍零网络；本场景新增的 `markReadLocally` 只写本地，只有 `writeBackMarkRead` 触网且只经 `SyncEngine`。
- 同一账号同一集合同时只有一个 Sync 在飞（读或写）；写结果与 `SyncKey` 同事务提交。
- 列表排序（`received_raw DESC, server_id DESC`）、软删过滤（`deleted_at IS NULL`）与 `Message.isRead` 语义不变。
- 正文/附件缓存、通知条件、搜索 FTS 行为不变。
- 不新增 `Message` 公共字段；不新增 `readDirty`/`pending` 状态；不建 `pending_op` 表。
- 计时固定 10 秒，不做配置；只对当前选中一封计时，不对所有可见未读行计时；搜索模式不计时。

## 测试

| ID | 类型 | 方案 | 可执行 ID（拟） |
|---|---|---|---|
| `T-SCN-0008-01` | 正 | 选中未读邮件、应用前台，注入时钟前进 10 秒 → 本地 `isRead == true`、VM 列表蓝点条件为假、`MailStore.markRead` 只改目标行、服务器写命令恰好一次且携带当前 key；key 推进。 | `PresentationTests/MailboxViewModelTests.dwellMarksSelectedUnreadAfterTenSeconds` + `ScenesTests/ReadSceneTests.markReadLocallyPersistsBeforeWriteBack` + `SyncEngineTests/SyncEngineTests.markReadWritesOnceAndAdvancesKey` |
| `T-SCN-0008-02` | 正 | 第 9 秒切换选中 → 第一封不置读；切到第二封未读并满 10 秒 → 只有第二封置读；切文件夹/搜索/删除同样取消；失活取消、回前台重新计满；普通同步重载不重置正在运行的计时。 | `PresentationTests/MailboxViewModelTests.dwellCancelsOnSelectionChangeAndRestarts` + `...dwellPausesInBackgroundAndRestarts` + `...dwellSurvivesSyncReload` |
| `T-SCN-0008-03` | 正 | 置读后重新 `loadCached`/重启视图模型 → 仍为已读；重复计时/重复回写不产生第二次网络写；服务器已读回包不改变本地；已读邮件选中不发网络。 | `PresentationTests/MailboxViewModelTests.dwellMarkIsPersistentAndIdempotent` + `SyncEngineTests/SyncEngineTests.markReadIsSerializedWithSyncOnce` |
| `T-SCN-0008-04` | 反 | 应用失活满 10 秒 → 不置读、不发网络；回前台不足 10 秒仍不置读；服务器回写失败（offline/503）→ 本地仍已读且无错误文案、不回滚；已读邮件选中不发网络。 | `PresentationTests/MailboxViewModelTests.dwellDoesNotRunInBackground` + `ScenesTests/ReadSceneTests.markReadKeepsLocalReadWhenWriteBackFails` |

支撑测试（不属于 3+1 断言，但组件出口要求）：

- `MailDomainTests`：`MailWriteGateway` 的契约面（编译期）与 `SyncStore` 新方法签名；`MailGateway` 只读 fake 不需要实现写端口；引擎测试用测试 target 的 `UnsupportedWriteGateway` 显式注入，不依赖 nil 默认；`SyncStore` 的两个测试替身需补三个新方法（可默认抛错）。生产 target 不提供 `UnsupportedWriteGateway`。
- `MailStoreTests`：`markRead` 只改目标行、已读幂等、`commitMarkRead` 事务回滚不推进 key、`is_read=1` 与 key 同事务。
- `EASClientTests`：`Change/Read=1` golden 请求、新 key、`Status=3/4`、写 401 → `deviceNotRegistered`；既有无 `Commands` 的读请求不回归。
- `EASAdapterTests`：`MailWriteGateway` 的错误映射与 delta 透传。
- `CompositionTests`：`GatewayEndpoints.write` 非可选（生产 `PlatformGateway.make` 的 write 是 `EASAdapter`）由 T-1114-21 证；同一 `SyncEngine` 注入 `SyncScene`/`ReadScene` 由 T-1114-15/16 的装配检查证。

## 状态

`designed`（2026-11-14，T-1114-10）。四元素齐；3 正 1 反均给出拟执行 ID。**未实现**：`MailWriteGateway`、`SyncEngine.markRead`、`ReadScene.markReadLocally/writeBackMarkRead`、`MailboxDwell` 均不存在于代码。

实现前门：P1 人工确认（非可选写端口/SyncStore/组合根，无 schema）与 R16（T-1114-12 先证网关接受 `Sync` 的 `Change/Read=1` 并返回新 key）。R16 被拒则停止并按 `REQ-0013` 重议，不静默退化为只改本地。验证归属：`T-SCN-0008-01..04` 全绿并转 `verified` 前，`REQ-0013` 不得 `delivered`。
