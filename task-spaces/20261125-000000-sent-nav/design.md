---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-24
---

# W-M3-19 设计：顶部邮箱切换与发件箱

## 1. 现状

- `MailboxView` 用三栏 `NavigationSplitView`：侧栏 = 服务器全部文件夹（type 1–19），中栏 = 消息列表，详情 = 阅读区；
  日历通过侧栏第一行切换。用户不使用草稿/已删除/RSS 等文件夹，列表过长。
- `SendMail` 已经带 `<SaveInSentItems/>`（`EASClient.send`，测试 `SendMail succeeds on 200 with a zero-byte body` 断言），
  但 `SyncEngine.syncOnce` 只同步 `isInbox`；服务器已有 Sent Items 文件夹（本地 folder type 5 / serverID 18），
  所以 App 从未把它拉下来，发件箱为空。
- `MailboxViewModel.reloadCurrentList` 已经能读任意 folder，因此只剩「同步 Sent」和「选择 Sent」两件事。

## 2. 定级与组件

- **P2**：跨 `CMP-APP` / `CMP-PRES` / `CMP-SYNC` 三个组件，新增同步入口与 UI 结构；不改 schema、target、依赖、EAS 协议；
  `Folder.isSentItems` 是 additive public 值语义。
- 组件落点：
  - `CMP-DOMAIN`：`Folder.isSentItems`（type 5）。
  - `CMP-SYNC`：`syncFolder` 泛化（由 `syncInbox` 改名）；新增 `syncSentOnce()`（不改变 `syncOnce()` 语义）。
  - `CMP-PRES`：`sentFolderID`/`inboxFolderID`、`selectSent()`、`refreshSent()`；复用既有 `apply`/`select(folderID:)`。
  - `CMP-APP`：顶部 `Picker`、去掉 sidebar、两栏 `NavigationSplitView`、工具栏刷新按 section 分派、空态文案。

## 3. 修改方案

### 3.1 顶部切换（REQ-0037）

- `MailboxView` 不再渲染文件夹列表；`MailboxSection`（private enum）= `inbox` / `sent` / `calendar`，默认 `.inbox`。
- 顶部 `Picker(.segmented)` 放在窗口 toolbar 的 `.navigation` 位（leading，交通灯之后）；`ToolbarItem` 在根视图上，
  日历/邮件两种内容都保留。
- 邮件页：两栏 `NavigationSplitView`（第一列 = 消息列表，`.navigationSplitViewColumnWidth(min: 320, ideal: 480)`；
  详情 = 阅读区）。`HSplitView` 实测不遵守 `idealWidth`（1440 窗口列表被拉到 760），**否决**；见 `probe/HSplitProbe.swift`。
- 日历页：`CalendarView` 独占内容区；顶部切换仍在。
- 切换动作：收件箱 → `select(folderID: inboxFolderID)`；发件箱 → `Task { await selectSent() }`（异步，带“切走后不抢占”的守卫）；
  日历 → 无动作（`CalendarView.task` 自己加载）。
- 工具栏刷新按钮按 section 分派 `viewModel.refresh()` / `refreshSent()`；搜索仍只作用于列表。

### 3.2 发件箱与 Sent 同步（REQ-0038）

- `SyncEngine.syncFolder(_:folderCount:)`：原 `syncInbox` 仅改名/改参数，语义不变；`runSync` 仍只同步收件箱。
- 新增 `syncSentOnce() async throws -> SyncReport?`：
  - `provisionIfNeeded` → `refreshFolders` → 取 `isSentItems`；
  - 无 Sent 文件夹 → `nil`，不改 state；
  - 有 → `state = .syncingMessages(folder: sentID)`，走同一 `syncFolder`（FIFO 门、窗口、reset、key 事务不变）；
  - 失败 → `recordFailure(error)` 并抛出，与 `syncOnce` 共用失败分类。
  - `syncOnce()` 的 inbox key 不受影响；Sent 的 key 独立存 `sync_state`。
- `SyncScene.refreshSent() async -> RefreshOutcome`：只调 `syncSentOnce`；不发“新邮件”通知（自己的发件不是来信），
  错误映射到 `MailError` 后返回。
- `MailboxViewModel.refreshSent()`：`sync.phase = .syncing` → `apply(outcome)` → 若 Sent 文件夹在刷新后才出现则补选。
- `selectSent()`：先选本地 Sent（立即显示缓存），再刷新；若刷新后 Sent 才出现，再补选。视图侧在异步完成后检查
  `section`，用户已切走则回收件箱，避免迟到的选择抢回导航。
- 发送后：服务器由 `SaveInSentItems` 保存副本；用户打开「发件箱」时 `selectSent` 触发同步，副本出现。
  不做本地 Sent 镜像（用户选择“显示服务器 Sent Items”）；不做发送成功的即时同步（Outbox 冷投递与 UI 解耦）。

### 3.3 其他文件夹

- 全部隐藏：不再渲染 `viewModel.folders`；`reloadFolders` 保留，用于解析 inbox/sent 的 serverID。
- 不同步、不提供入口；`plan/open-questions.md` 的“其他文件夹为空”按“隐藏 + 只补 Sent”收口。

## 4. 场景走查

- 正常：启动 → 收件箱列表 + 阅读；点发件箱 → 本地 Sent 缓存先显示 → 同步 → 服务器副本进入列表；点日历 → 整宽日历。
- 失败：Sent 同步失败 → 发件箱保留旧列表 + 中文错误；收件箱不受影响；无 Sent 文件夹 → `syncSentOnce` 返回 nil，
  不显示错误，列表空。
- 并发：用户点发件箱后立刻切回收件箱 → Sent 任务完成时检查 section，恢复收件箱，不抢占。
- 回归：收件箱刷新、30 天列表、双击/Enter/空格浮窗、日历、回复/转发/发送、远程图片、附件不变。

## 5. 测试

- L1：
  - `SyncEngineTests` 新增 `syncSentOnce` 2 例（只同步 Sent、不动 inbox key；无 Sent 返回 nil）；
  - `MailboxViewModelTests` 新增 `selectSent` 1 例（选中/刷新/列表出现已发送副本）；全量 464 tests / 77 suites。
- L2：
  - `probe/toolbar-nav.png`：顶部 Picker 位于 leading，三段「收件箱/发件箱/日历」，无文件夹栏；
  - `probe/two-column.txt`：1440 list 480 / reading 952；900 list 480 / reading 412。
  - `probe/HSplitProbe.swift`：HSplitView 不遵守 idealWidth，否决依据。
- 架构 4 门、`make-app.sh`。
- 未覆盖（发布前人工）：真实发信后服务器 Sent Items 副本、真实点击顶部切换/分隔条、深色主题视觉。

## 6. 决策

- 顶部用 toolbar `.navigation` 的 segmented Picker，不额外加一行 header：视觉最轻，日历/邮件共享。
- 不用 `HSplitView`（不遵守 idealWidth）；用两栏 `NavigationSplitView`，列表 480 的既有口径不变。
- Sent 同步用独立入口 `syncSentOnce`，不并进 `syncOnce`：避免 Sent 失败把收件箱刷新判失败，也不改 `SyncReport.syncKey` 的既有含义。
- 无本地 Sent 镜像：服务器已有 `SaveInSentItems`，本地镜像会引入第二真相与重复风险；先按用户选择验证服务器路径。
