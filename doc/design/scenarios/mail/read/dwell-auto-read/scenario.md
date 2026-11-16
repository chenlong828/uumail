---
layer: design
module: mail
scope: project:uumail
status: designed
updated: 2026-11-16
flow: mail/read
scenario: SCN-0008
---

# SCN-0008 列表停留自动已读

**结果**：用户在邮件列表选中一封未读邮件并保持选中，应用在前台连续 3 秒后，该邮件在本机转为已读：列表蓝点消失、主题字重回到常规；状态持久化，不等待网络。服务器回写在后台尽力完成，使其他客户端可见；回写失败不回滚本地已读、不弹错误。3 秒内切换选中、切换文件夹/搜索、删除该邮件或应用失活会取消计时；回到前台且该邮件仍选中时重新计满 3 秒。原文「打开一个邮件超过 3 秒」按既有语义收敛为「选中即打开阅读区，从选中且满足条件时开始计时」，不等待正文加载完成。

## 入口

- `CMP-PRES#MailboxViewModel`（`MailboxDwell` 3 秒计时、前台状态、选中变化/重载取消；`visibleMessages` 驱动蓝点；T-1114-17）
- `CMP-PRES#MailboxDwell`（仅计时：3 秒、可注入 sleep、不读系统时间、不直接读写存储；到点通过 `onElapsed` 回调 `MailboxViewModel.performMarkRead`）
- `CMP-PRES#MailboxViewModel.performMarkRead`（本地先行 + 列表重载 + 仅 0→1 启动回写；2026-11-16 设计从 `MailboxDwell` 移入视图模型，供自动/手动共用）
- `CMP-SCN-READ#markReadLocally`、`#writeBackMarkRead`（本地置读与服务器回写两阶段；T-1114-16；契约不变）
- `CMP-SYNC#markRead`（与 `syncOnce` 共享集合 key 的显式串行门；T-1114-15）
- `CMP-STORE#markRead`、`#commitMarkRead`（本地置读；写成功后 delta + read + key 同事务；T-1114-14）
- `CMP-DOMAIN#MailWriteGateway.markRead`（T-1114-11）、`#SyncStore.markRead`/`#commitMarkRead`（T-1114-14）
- `CMP-EASADAPTER#markRead`、`CMP-EAS#sync(change: .read)`（`Change` + `ApplicationData/Read=1`；T-1114-13/T-1114-12）
- `CMP-APP#MailboxView`（前台/失活状态转发：`NSApplication.didBecomeActive`/`willResignActive` 通知，不写业务；T-1114-18）

## 运行序

流程 `F-READ-02`：

1. 列表选中变化（鼠标、键盘、自动选中首封）→ `MailboxDwell.update` 取消上一封计时；新选中项 `isRead == false`、`isApplicationActive` 且**不在搜索模式** → 启动 3 秒计时；否则不计时。
2. 计时期间发生选中变化、文件夹切换、进入/停留在搜索、删除、应用失活 → 取消计时；回到前台且仍选中同一未读邮件（且不在搜索模式）→ `update` 看到从不可计到可计的变化，重新计满 3 秒，不累计。
3. 普通同步重载列表 → `MailboxDwell.update` 收到同一 target 且仍合格时**不重启**计时；若该邮件已被同步置读/删除/移走，取消。
4. 计时到点 → `MailboxDwell` 再次确认仍可计 → 通过 `onElapsed` 调 `MailboxViewModel.performMarkRead(ref)`；后者调 internal `localMarkRead`（默认 `ReadScene.markReadLocally`）。`MailStore.markRead` 在本地事务中置 `is_read = 1`，返回是否发生 0→1 转换。
5. 本地成功 → `performMarkRead` 重新读本地列表（蓝点立即消失、字重常规）并 `refreshDwell()`；仅当 `localMarkRead` 返回 true（0→1）时后台启动 `ReadScene.writeBackMarkRead(ref)`。返回 false（已被同步置读/已删）时也重载一次以纠正陈旧列表，但不回写。本地写失败时 `performMarkRead` 把任意错误归一为 `MailError` 后返回，自动计时路径忽略它（不重载、不回写、不弹错）。
6. `SyncEngine.markRead` 在 FIFO 门内再钉一次本地已读 → 读当前集合 `SyncKey` → `Sync` 携带 `Change/Read=1` → 服务器返回 delta + 新 `SyncKey` → `MailStore.commitMarkRead` 把「响应 delta + `is_read=1` + 新 key」同事务提交。
7. 服务器回写失败：本地已读保持，不弹错、不重试、不推进 key；返回 `.failed(MailError)` 仅供诊断/测试，PRES 不展示。下一次普通同步仍按服务器事实更新其它邮件。
8. 已读邮件再次被选中、重复计时、重复回写：不产生第二次网络写；`markReadLocally` 返回 false 时不启动回写。

失败路径：

- 本地写失败 → `markReadLocally` 抛错（可能是 `MailError`/`MailStoreError`/GRDB `DatabaseError`）；`performMarkRead` 归一为 `MailError` 后返回，自动计时路径不重载、不回写；列表仍显示未读；无 UI 错误（罕见，按存储错误记录；手动入口才展示中文）。
- 服务器回写失败（`offline`/`throttled`/`authFailed`/`deviceNotRegistered`/`policyBlocked`/`unsupported`）→ 本地已读保持，无 UI 错误；本次回写不直接暂停自动刷新；下一次 `SyncScene` 刷新若仍失败，按既有规则暂停。
- 回写时 `SyncKey` 失步（`Status=3/4`）→ 只算回写失败；下一次刷新按既有规则重建，不用已读回写触发重建。
- 计时到点前邮件被删/被移走/列表重载导致选中消失 → 取消，不报错。
- 应用在计时期间失活 → 取消；回前台重新计满，不累计。
- 回写响应携带整页 delta 与 `MoreAvailable`（R16 真机样本）：这是正常分页信号，`SyncEngine` 把 delta + 本地已读 + 新 key 同事务提交，剩余页由下一轮增量同步消费；不视为协议异常、不回滚本地已读。

## 不可变引用

- `ReadScene` 的本地读方法（`folders/messages/search/attachments/bodyIfCached/open`）仍零网络；本场景新增的 `markReadLocally` 只写本地，只有 `writeBackMarkRead` 触网且只经 `SyncEngine`。
- 同一账号同一集合同时只有一个 Sync 在飞（读或写）；写结果与 `SyncKey` 同事务提交。
- 列表排序（`received_raw DESC, server_id DESC`）、软删过滤（`deleted_at IS NULL`）与 `Message.isRead` 语义不变。
- 正文/附件缓存、通知条件、搜索 FTS 行为不变。
- 不新增 `Message` 公共字段；不新增 `readDirty`/`pending` 状态；不建 `pending_op` 表。
- 计时固定 3 秒，不做配置；只对当前选中一封计时，不对所有可见未读行计时；搜索模式不计时。
- 计时器仍是声明式 `update`：相同 target 且合格不重启；计时器不直接访问 `ReadScene`/`MailStore`，写路径只在 `MailboxViewModel.performMarkRead`（2026-11-16 设计）。

## 测试

| ID | 类型 | 方案 | 可执行 ID（拟） |
|---|---|---|---|
| `T-SCN-0008-01` | 正 | 选中未读邮件、应用前台；注入时钟收到 `.seconds(3)`，推进 3 秒 → 本地 `isRead == true`、VM 列表蓝点条件为假、`MailStore.markRead` 只改目标行、服务器写命令恰好一次且携带当前 key；key 推进。必须断言传给 sleep 的时长恰为 `.seconds(3)`，否则 10→3 或更短的回归不可见。 | `PresentationTests/MailboxViewModelTests.dwellAsksForThreeSecondsAndMarks` + `ScenesTests/ReadSceneTests.markReadLocallyPersistsBeforeWriteBack` + `SyncEngineTests/SyncEngineTests.markReadWritesOnceAndAdvancesKey` |
| `T-SCN-0008-02` | 正 | 第 2 秒切换选中 → 第一封不置读；切到第二封未读并满 3 秒 → 只有第二封置读；切文件夹/搜索/删除同样取消；失活取消、回前台重新计满；普通同步重载不重置正在运行的计时。 | `PresentationTests/MailboxViewModelTests.dwellCancelsOnSelectionChangeAndRestarts` + `...dwellPausesInBackgroundAndRestarts` + `...dwellSurvivesSyncReload` |
| `T-SCN-0008-03` | 正 | 置读后重新 `loadCached`/重启视图模型 → 仍为已读；重复计时/重复回写不产生第二次网络写；服务器已读回包不改变本地；已读邮件选中不发网络。 | `PresentationTests/MailboxViewModelTests.dwellMarkIsPersistentAndIdempotent` + `SyncEngineTests/SyncEngineTests.markReadIsSerializedWithSyncOnce` |
| `T-SCN-0008-04` | 反 | 应用失活满 3 秒 → 不置读、不发网络；回前台不足 3 秒仍不置读；服务器回写失败（offline/503）→ 本地仍已读且无错误文案、不回滚；已读邮件选中不发网络。 | `PresentationTests/MailboxViewModelTests.dwellDoesNotRunInBackground` + `...dwellForegroundRestartNeedsFullDwell` + `ScenesTests/ReadSceneTests.markReadKeepsLocalReadWhenWriteBackFails` |

支撑测试（不属于 3+1 断言，但组件出口要求）：

- `MailDomainTests`：`MailWriteGateway` 的契约面（编译期）与 `SyncStore` 新方法签名；`MailGateway` 只读 fake 不需要实现写端口；引擎测试用测试 target 的 `UnsupportedWriteGateway` 显式注入，不依赖 nil 默认；`SyncStore` 的两个测试替身需补三个新方法（可默认抛错）。生产 target 不提供 `UnsupportedWriteGateway`。
- `MailStoreTests`：`markRead` 只改目标行、已读幂等、`commitMarkRead` 事务回滚不推进 key、`is_read=1` 与 key 同事务。
- `EASClientTests`：`Change/Read=1` golden 请求、新 key、`Status=3/4`、写 401 → `deviceNotRegistered`；既有无 `Commands` 的读请求不回归。
- `EASAdapterTests`：`MailWriteGateway` 的错误映射与 delta 透传。
- `CompositionTests`：`GatewayEndpoints.write` 非可选（生产 `PlatformGateway.make` 的 write 是 `EASAdapter`）由 T-1114-21 证；同一 `SyncEngine` 注入 `SyncScene`/`ReadScene` 由 T-1114-15/16 的装配检查证。

## 状态

`designed`（2026-11-16 设计修订：连续停留 10 秒 → 3 秒，并补「注入时钟收到 `.seconds(3)`」断言；`MailboxDwell` 改为仅计时、写路径移入 `MailboxViewModel.performMarkRead`）。四元素齐；3 正 1 反均给出可执行 ID。此前 10 秒版本于 2026-11-15 `verified`（T-1114-19，239 tests / 44 suites；原始证据 `task-spaces/20261114-232232/test.md`）；该历史证据不追溯删除。修订后由实现/验证节点重新执行 3 秒断言，评审通过后由收尾节点把 `status` 转回 `verified`；本设计节点不代判。

`verified` 判据：`T-SCN-0008-01..04` 全 pass（含 `.seconds(3)` 时长断言）；`SCN-0003`/`SCN-0004` 回归不退化；无 skip 或 skip 有登记替身。

## 与相邻场景的边界

- `SCN-0014` 手动标记已读：手动入口归它；本场景只认领自动计时。二者共享 `MailboxViewModel.performMarkRead` 与 `ReadScene` 两阶段写路径，但断言不重复；并发幂等由 `SCN-0014-03` 覆盖。
- `SCN-0004` 邮件阅读：打开/正文状态不改；本场景只改停留时长与写路径归属，不新增正文断言。
- `SCN-0003` 收件箱同步：普通同步仍按服务器 `Read` 更新；本场景只回归「写回与同步串行」。
- `SCN-0009` 键盘删除：删除取消计时；删除行为不变。
