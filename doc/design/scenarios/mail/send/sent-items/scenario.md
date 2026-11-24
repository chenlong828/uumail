---
layer: design
module: mail
status: verified
updated: 2026-11-24
flow: mail/send
scenario: SCN-0029
---

# SCN-0029 发件箱显示服务器 Sent Items

**结果**：用户点顶部「发件箱」时，列表先显示本地已缓存的已发送邮件，随后按服务器 Sent Items（folder type 5）同步最近 30 天，服务器副本进入列表；发送成功的信由 `SendMail` 的 `SaveInSentItems` 落到服务器，用户下次打开「发件箱」时被同步拉回；账号没有 Sent 文件夹时显示「没有发件邮件」空态；同步失败保留缓存并给中文错误，收件箱的 key 与列表不受影响。

## 入口

- `CMP-SYNC#syncSentOnce`（只同步 Sent Items 的入口；无 Sent 文件夹返回 nil）
- `CMP-PRES#selectSent` / `#refreshSent`（选中发件箱、缓存优先、刷新与失败文案）
- `CMP-EAS#send` 的 `SaveInSentItems`（发送时由服务器保存副本，本次不改）

## 运行序

流程 `F-SEND-02`：

1. 点「发件箱」→ `MailboxView` 调 `viewModel.selectSent()`；若缓存中已有 type 5 的文件夹，先选中并显示本地列表，不等待网络。
2. `selectSent()` → `refreshSent()`：`sync.phase = .syncing`；`SyncScene.refreshSent()` 只调 `SyncEngine.syncSentOnce()`，不发「新邮件」通知。
3. `syncSentOnce()`：`provisionIfNeeded` → 全量刷新文件夹 → 找 `isSentItems`（type 5）；无 → `state = .idle`、返回 nil、不写任何批次；有 → `state = .syncingMessages(folder: sentID)`，走与收件箱相同的 `syncFolder`（FIFO 门、30 天窗口 `FilterType=5`、reset 与 key 同事务），但只针对该 collection。
4. 批次落库后 `SyncScene` 返回 `RefreshOutcome`；`MailboxViewModel.apply` 重读 folders 与当前列表；若 Sent 文件夹是这次刷新才出现，补选；列表出现服务器副本，状态回 idle。
5. 发信路径：撰写发送 → `Outbox` 冷投递 → `EASClient.send` 的 `SendMail` 带 `SaveInSentItems`，服务器保存副本；不在发送成功后立即同步，用户下次打开「发件箱」时由第 3 步拉回。
6. 工具栏刷新在当前 section 为发件箱时走 `refreshSent()`；收件箱与自动刷新仍走 `refresh()`/`syncOnce()`，两条路径互不移动对方 key。

失败路径：

- 账号没有 Sent 文件夹 → `syncSentOnce` 返回 nil，发件箱显示「没有发件邮件」空态，不显示错误文案。
- Sent 同步失败 → `RefreshOutcome.error` 映射为中文错误，保留发件箱已缓存列表；不把收件箱判为失败，也不推进收件箱 key。
- 发件箱同步进行中用户快速切回收件箱 → 视图在异步完成后按当前 section 留在收件箱，迟到的 Sent 选择不抢回导航。
- 发送成功但 Sent 副本尚未同步 → 发件箱暂不显示该封；下次打开「发件箱」或手动刷新时才出现，不伪造本地插入。

## 不可变引用

- `SCN-0003`：收件箱的 30 天同步窗口、`sync_key` 事务、失败不推进 key 与通知规则不变；`syncSentOnce` 不触碰收件箱 key/窗口。
- `SCN-0028`：顶部三段切换、默认收件箱、无侧栏与两栏布局；本场景只承接「发件箱」这一段的选中与同步。
- `SCN-0025`：双击/Enter/空格打开浮窗、阅读与就地撰写不变；发件箱列表行复用同一阅读入口。
- 不做本地 Sent 镜像；不改 `SendMail`/EAS 请求、schema、target、依赖与 outbox 状态机。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0029-01` | 正 | `syncSentOnce` → 只同步 type 5：added 2、Sent key 401；收件箱 key 仍 101、收件箱窗口未移动（L1 `SyncEngineTests`「syncSentOnce syncs only Sent Items and leaves the inbox key alone」） |
| `T-SCN-0029-02` | 正 | `selectSent()` → 选中 folder 18、列表出现已发送副本（主题「已发送」）、`sentFolderID == 18`、phase idle（L1 `MailboxViewModelTests`「selectSent syncs Sent Items and shows the sent copy」） |
| `T-SCN-0029-03` | 正 | `SendMail` 文档含 `SaveInSentItems`；HTTP 200 + 0 字节 body 仍判成功（既有 `EASClientTests`「SendMail succeeds on 200 with a zero-byte body」；EAS 未改） |
| `T-SCN-0029-04` | 反 | 无 Sent 文件夹 → 返回 nil、无批次、无错误；Sent 同步失败 → 发件箱保留缓存列表 + 中文错误，收件箱列表与 key 不受影响（L1 `SyncEngineTests.noSentItems` + `MailboxViewModel.apply` 的失败映射，与既有 `failureKeepsCache` 同路径；Sent 未单独立失败用例，失败隔离以独立入口与独立 key 保证） |

## 状态

`verified`（2026-11-24 实现并验证）。

- 实现：`SyncEngine.syncFolder`（原 `syncInbox` 泛化）+ 新 `syncSentOnce()`；`SyncScene.refreshSent()`；`MailboxViewModel.sentFolderID`/`selectSent()`/`refreshSent()`；`SendMail` 的 `SaveInSentItems` 未改。
- 证据（L1）：`Tests/SyncEngineTests/SyncEngineTests.swift` 2 例（sentItems 只同步 Sent 且 inbox key 不变；noSentItems 返回 nil）；`Tests/PresentationTests/MailboxViewModelTests.swift` 1 例（selectSent → folder 18、列表出现已发送副本、phase idle）；`Tests/EASClientTests/EASClientTests.swift` 既有 `SaveInSentItems` 断言。
- 全量 464 tests / 77 suites、架构 4/4、`make-app.sh` 成功（release，2026-11-24 23:57 CST）。
- 未覆盖（发布前人工项）：**真实发一封信 → 服务器 Sent Items 出现副本 → App「发件箱」拉到**（未执行，不写成已通过）；真实点击发件箱与切换中的竞态；`refreshSent` 不发新邮件通知本轮无独立断言（组件规格已登记为残余）；发送成功不触发即时同步、无本地 Sent 镜像均为本卡已确认口径，不是缺陷。
