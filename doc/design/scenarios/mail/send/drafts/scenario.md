---
layer: design
module: mail
scope: project:uumail
status: verified
updated: 2026-11-27
flow: mail/send
scenario: SCN-0031
---

# SCN-0031 草稿箱与就地继续编辑

**结果**：顶部切换出现「收件箱 / 发件箱 / 草稿箱 / 日历」四段；切到草稿箱，左侧按更新时间倒序列出本机草稿（主题、收件人、时间），右侧空态提示选择草稿。单击一封草稿 → 右侧直接进入编辑态（标题「草稿」，收件人/抄送/主题/正文回填，顶部红色关闭、`存草稿`⌘S、蓝色发送）；`存草稿` 覆盖同一行并留在编辑器，`发送` 把该行转成待发并从草稿箱移除；切换 tab 或另一封草稿时自动保存未保存修改。草稿与服务器 Drafts 文件夹双向合并同步：本地新写/改动/删除/发出的草稿推到服务器，服务器变化合回本地；两边都改过的同一封草稿两份都保留，由人删除。

## 入口

- `CMP-APP#MailboxView`（section `.drafts`、`draftListColumn`、`draftDetail`、`leaveDraftEditor`/`openDraft`/`closeDraftEditor`）
- `CMP-APP#DraftListView`（草稿列表行、空态、时间格式）
- `CMP-APP#ComposeView`（`isEmbedded`、`存草稿`⌘S、`onDraftSaved`）
- `CMP-PRES#MailboxViewModel.drafts` / `#loadDrafts` / `#compose(draft:)`
- `CMP-PRES#ComposeViewModel`（`mode.draft`、`draftID`、`saveDraft()`、`send()`）
- `CMP-SCN-COMPOSE#drafts` / `#saveDraft(_:account:draftID:)` / `#send(_:account:draftID:)`
- `CMP-OUTBOX-STORE#drafts` / `#updateDraft` / `#sendDraft`

## 运行序

流程 `F-SEND-03`：

1. 顶部四段 Picker（`.navigation` 位）切到「草稿箱」→ `switchSection` 先看是否正在草稿编辑态：是则 `leaveDraftEditor()` 自动保存后清空；随后 `viewModel.loadDrafts()` 读 `outbox WHERE state = 'draft' ORDER BY updated_at DESC, id DESC`。
2. 左列 `DraftListView` 渲染草稿行：主题（空 → 「无主题」）、收件人（空 → 「未填写收件人」）、`MM-dd HH:mm` 更新时间；无草稿时显示「没有草稿」。
3. 单击一行（`List(selection:)` 绑定行 id）→ `onChange(selectedDraftID)` 找到 `DraftRecord` → `openDraft`：先 `leaveDraftEditor()`（上一封有改动则保存），再 `viewModel.compose(draft:)` 生成 `ComposeViewModel(mode: .draft, …, draftID: 行 id)`，右侧 `ComposeView(isEmbedded: true)` 就地显示。
4. 编辑中按 `存草稿`（或 ⌘S）→ `editor.capture()` → `saveDraft()` → `ComposeScene.saveDraft(draft, account, draftID:)` 走 `OutboxStore.updateDraft`（同一行、刷新 `updated_at`）→ `onDraftSaved()` 让左列 `loadDrafts()` 刷新；编辑器不关闭，状态行显示「草稿已保存」。
5. 编辑中点 `发送` → 收件人校验 → `send(draft, account, draftID:)` → `OutboxStore.sendDraft` 把同一行改为 `is_draft = 0, state = 'queued'` → `onEnqueued` 唤醒投递泵 → `onClose()` 清空编辑器与选中，`loadDrafts()` 后该行消失。
6. 切换到收件箱/发件箱/日历，或选中另一封草稿 → 先自动保存当前草稿（失败则保留编辑器与内容），再执行切换/打开。
7. 同步（REQ-0044）：进入草稿箱、`存草稿`、删除、发送后触发一轮草稿同步（单飞）。先拉 Drafts 文件夹（`Folder.type == 3`）按指纹合并，再推本地未绑定/改动/待删的草稿；失败只返回错误，本地继续可用。
8. 关闭编辑器（红色关闭/Esc）→ `capture` + `hasEdits`：无改动直接关；有改动 `confirmationDialog("存储草稿？")`：存草稿（成功后关闭）、放弃、继续编辑。

失败路径：

- 自动保存失败（存储错误）→ 保留 `draftCompose` 与编辑器内容，不切走丢弃；状态行显示中文原因。
- 手工存草稿失败 → 编辑器保留，`status == .failed`，可重试。
- 行已被其他窗口删除（`updateDraft`/`sendDraft` 返回 false）→ 保存回退为插入新草稿、发送回退为入队新行，不丢内容。
- 草稿收件人为空时发送 → `MailError.invalidInput`，编辑器保留并显示中文错误；草稿仍在列表。
- 无草稿 / 未选中草稿 → 「没有草稿」/「选择一封草稿」空态，不报错。
- 服务器不可用 → 草稿箱继续用本地列表，同步错误不阻塞编辑；下一轮进入/保存/删除再重试。
- 两边都改过同一封 → 原行采用服务器版本，本地版本复制成新草稿并在同一轮上传成服务器第二份；两行都可见，人删其一。
- 服务器草稿被删而本地改过 → 解绑保留本地行，下一轮重新上传；本地未改 → 本地行删除。
- 发送/删除已绑定草稿 → 同事务落 tombstone，离线时下一轮同步再删服务器副本。

## 不可变引用

- `SCN-0016`：sheet 撰写（新建/回复/转发）的 HTML 编辑器、闭合确认、等宽口径不变；本场景只新增 `isEmbedded` 分支与 `存草稿` 按钮。
- `SCN-0028`：顶部切换仍由 `.navigation` 位 Picker 提供；新增第四段不改变 leading 位置与日历页行为。
- `SCN-0006`：发送只入队、`ClientId = outboxID`、Outbox 租约/退避/幂等不变；草稿转队只是同一行的状态更新。
- `SCN-0017`：草稿编辑器复用 `ComposeRecipientForm`，收件人联想、候选浮层与 ≤480/225% 的布局基线不变。
- 草稿只读本机 `outbox` 表，不同步服务器 Drafts 文件夹；不改 schema、不新增 target/依赖。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0031-01` | 正 | 保存后出现在草稿箱、按更新时间倒序、同账号隔离：`OutboxDraftTests.draftRoundTrip`（两条草稿、`state='draft'`、不在 pending、更新同行、`cc` 空读回 nil）；`DraftListTests.draftsArePerAccount`（另一账号读不到） |
| `T-SCN-0031-02` | 正 | 就地继续编辑并保存同行：`DraftListTests.reopenedDraftSavesInPlace`（`mode == .draft`、`draftID` 对齐、再次保存后仍 1 条且内容更新、不入队）；`ComposeSceneDraftTests.saveDraftUpdatesOpenedDraft` |
| `T-SCN-0031-03` | 正 | 发送消费草稿：`DraftListTests.sendingOpenedDraft`（发送后草稿清空、pending 恰为原行 id）；`OutboxDraftTests.sendDraftQueuesSameRow`（state→queued、`is_draft=0`、正文更新）；`ComposeSceneDraftTests.sendOpenedDraft`（不触网）；L2 截图 `task-spaces/20261127-114500-drafts-tab/probe/embedded-compose.png`（就地编辑器：红点/草稿标题/存草稿/发送/回填表单） |
| `T-SCN-0031-04` | 反 | 行被删除与空收件人：`OutboxDraftTests.missingDraftIsNotCreated`（missing id 不插行、不报 success）；`ComposeSceneDraftTests.missingDraftFallsBack`（发送回退为新的 queued 行）；`ComposeViewModelTests.sendFailureKeepsText`（空收件人发送失败保留编辑器）；L2 截图 `draft-list.png`（列表行与「选择一封草稿」空态） |

| `T-SCN-0031-05` | 正 | 双向合并：服务器草稿拉取后绑定 `server_id`；本地新草稿上传后绑定；两边都改用原行收服务器版、本地改动复制成新草稿并上传（`conflicts == 1`、两行都在）；删除/发送已绑定草稿落 tombstone，下一轮 `Sync Delete` 后清空。 | `DraftSyncTests.downloadsServerDrafts`/`.uploadsLocalDraft`/`.conflictKeepsBoth`/`.deleteTombstoneIsFlushed`/`.sendingBoundDraftDeletesServerDraft`；`DraftBindingTests.bindingsAndTombstones`；`EASDraftWriteTests.createDraft/updateDraft/deleteDraft`（WBXML Add/Change/Delete 与 ServerId 解析） |
支撑测试：`OutboxDraftTests` 3 例、`ComposeSceneDraftTests` 3 例、`DraftListTests` 3 例、`DraftSyncTests` 5 例、`DraftBindingTests` 1 例、`EASDraftWriteTests` 3 例；全量 484 tests / 83 suites。

## 状态

`verified`（2026-11-27 实现并验证；同日 `REQ-0044` 增量：草稿与服务器 Drafts 双向合并同步，`T-SCN-0031-05` 通过，真机草稿写入/删除为发布前人工项）。

- 实现：`DraftRecord`（MailDomain）、`OutboxStore.drafts/updateDraft/sendDraft`、`ComposeScene.drafts/saveDraft(draftID:)/send(draftID:)`、`ComposeViewModel.mode.draft/draftID`、`MailboxViewModel.drafts/loadDrafts/compose(draft:)`、`MailboxSection.drafts`、`DraftListView`、`MailboxView+Drafts`、`ComposeView.isEmbedded/存草稿⌘S`。
- 证据（L2）：`task-spaces/20261127-114500-drafts-tab/probe/draft-list.png`（三行草稿：主题/收件人/时间 + 右侧「选择一封草稿」空态）、`embedded-compose.png`（就地编辑器：草稿标题、存草稿、发送、回填收件人/主题/正文）。
- 增量证据（REQ-0044，L1）：`DraftSyncTests` 5 例（下载绑定、上传绑定、冲突两份、删除 tombstone、发送 tombstone）、`DraftBindingTests`、`EASDraftWriteTests`（Sync Add/Change/Delete 的 WBXML 与 ServerId）；EAS 协议与真实网关的草稿写入/删除未在真机验证。
- 未覆盖（发布前人工项）：真实点击 tab/草稿行/存草稿/发送的整窗流程，⌘S 焦点行为，浅色/深色像素，VoiceOver；真实 Exchange 上的草稿 Add/Change/Delete 与多设备冲突合并。

## 与相邻场景的边界

- 新建/回复/转发的 sheet 撰写归 `SCN-0016`；本场景只新增草稿箱与就地编辑分支。
- 发送入队、投递、重试归 `SCN-0006`；本场景只把草稿行改成 queued。
- 顶部切换与发件箱归 `SCN-0028`/`SCN-0029`；本场景只加第四段与草稿列表。
- 服务器 Drafts 同步不在本场景，另立需求。
