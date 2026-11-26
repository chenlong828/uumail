---
layer: design
module: mail
status: verified
updated: 2026-11-26
flow: mail/receive
scenario: SCN-0028
---

# SCN-0028 顶部三段邮箱切换

**结果**：用户启动应用后没有左侧文件夹栏，顶部在交通灯之后固定显示「收件箱 / 发件箱 / 日历」三段切换，默认收件箱；邮件页是列表 + 阅读两栏，列表默认 480pt、不窄于 320pt；日历页占满内容区，顶部切换仍在；草稿、已删除、垃圾邮件等其他文件夹没有入口。

## 入口

- `CMP-APP#MailboxView`（根视图顶部三段切换、无侧栏、邮件两栏、日历整宽、工具栏刷新分派）
- `CMP-PRES#inboxFolderID` / `#sentFolderID`（收件箱 type 2 与发件箱 type 5 的文件夹身份）

## 运行序

流程 `F-RECEIVE-05`：

1. 启动 → `MailboxView` 的 section 默认收件箱；根视图 toolbar 的 `.navigation` 位渲染「收件箱 / 发件箱 / 日历」`Picker(.segmented)`，并移除侧栏开关；内容区走邮件两栏 `NavigationSplitView`，第一列列表用 `min 320 / ideal 480`，第二列为阅读区。
2. 选「收件箱」→ 用 `inboxFolderID` 选中收件箱并重载列表；列表仍按最近 30 天读取，搜索、选中、双击/浮窗与阅读路径不变。
3. 选「发件箱」→ `Task { await viewModel.selectSent() }`；异步完成后视图检查当前 section，若用户已切走则选回收件箱，迟到的发件箱选择不抢回导航（发件箱选择与同步细节见 `SCN-0029`）。
4. 选「日历」→ `CalendarView` 占满内容区，顶部三段切换仍在；切回收件箱或发件箱 → 恢复两栏邮件页，section 与顶部切换保持一致。
5. 工具栏刷新 → 当前 section 为发件箱时走发件箱刷新，否则走既有收件箱/全局刷新；搜索仍只作用于邮件列表，状态栏同步态与错误文案沿用既有。
6. 其他文件夹不渲染、不可达；`reloadFolders` 只用于解析收件箱与发件箱的 serverID，不扩大同步范围。

失败路径：

- 账号没有 Sent 文件夹 → 发件箱显示「没有发件邮件」空态，不出现错误文案（`T-SCN-0028-04`）。
- 发件箱同步失败 → 保留已缓存的列表并显示中文错误，不把收件箱判为失败；错误可重试。
- 发件箱同步进行中用户快速切回收件箱 → 异步完成后按当前 section 回到收件箱，不把选中抢回发件箱。
- 窗口缩到应用最小宽 900 → 列表仍 480、阅读区 412；不出现列表低于 320 或被压成 0/负宽。

## 不可变引用

- `SCN-0025`：列表行单击、双击/Enter/空格打开浮窗、单例路由与就地撰写；本场景只替换外层导航，不改行手势与打开路径。
- `SCN-0024`：日历月/周视图、会议块定位、双击/键盘打开与「在日历中打开」；日历页只是从侧栏换到顶部入口。
- `SCN-0027`：列表 `min 320 / ideal 480` 的宽度口径沿用；两栏宽度由本场景的 `T-SCN-0028-02` 承接，SCN-0027 已按两栏重验。
- `SCN-0003`：收件箱同步窗口、`sync_key` 与通知规则不变；发件箱同步使用独立入口与独立 key，不改收件箱。
- 列表 30 天窗口、搜索、工具栏按钮集合与既有动作、窗口最小尺寸（900×560）不变。
- 顶栏分组（2026-11-26 起）：三段切换在左、七个邮件动作在右并按 `REQ-0042` 贴住搜索框；动作集合/禁用规则/刷新分派不变。
- 不改 schema、不新增 target 与依赖。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0028-01` | 正 | 启动后 → 顶部 leading（交通灯之后）出现「收件箱 / 发件箱 / 日历」三段，默认收件箱；左侧无文件夹栏，内容区为列表 + 阅读两栏（L2 `task-spaces/20261125-000000-sent-nav/probe/toolbar-nav.png`，探针源 `ToolbarProbe.swift`：Picker 在 `.navigation` 位、`toolbar(removing: .sidebarToggle)`） |
| `T-SCN-0028-02` | 正 | 1440 与 900 窗口 → 列表均 480，阅读区分别 952 / 412；列表未低于 320、无 0/负宽（L2 `task-spaces/20261125-000000-sent-nav/probe/two-column.txt`，探针源 `TwoColumnProbe.swift`，与生产 `min 320 / ideal 480` 一致） |
| `T-SCN-0028-03` | 正 | 切「发件箱」→ 选中 type 5 的 folder 18、列表出现已发送副本、phase idle；切「日历」→ 日历占满内容区且顶部三段仍在；切回收件箱/发件箱后两栏恢复（L1 `MailboxViewModelTests` 的 `selectSent` 例 + L2 `ToolbarProbe` 的根视图 toolbar 机制；真实 App 点击切到日历与发件箱列为发布前人工项） |
| `T-SCN-0028-04` | 反 | 无 Sent 文件夹 → `syncSentOnce` 返回 nil、发件箱空态「没有发件邮件」且不报错；发件箱同步中快速切回收件箱 → 视图按当前 section 留在收件箱，不把选中抢回发件箱（L1 `SyncEngineTests.noSentItems` + 视图 section 守卫走查；真实快速点击的竞态列为发布前人工项） |
| `T-SCN-0028-05` | 正 | 顶栏分组：1512pt 窗口下依次为「三段切换（左）→ 标题 → 七个动作（右，紧贴搜索框）」，七个动作全部可见、无「»」溢出；每个动作悬停有中文 tooltip；900pt 最小宽允许溢出但动作仍可达；状态变化（选中变化导致禁用态切换）后分组与 tooltip 保持。 | L2 探针 `task-spaces/20261126-210000-mail-toolbar/probe/`：`final-1512.png`/`final-900.png`/`final-layout.txt`（帧坐标 898..1169 紧贴搜索、tooltip 文本逐项列出）、`stability.txt`（0.3s 状态翻转 6s，items/flex/首动作 x 稳定） |

## 状态

`verified`（2026-11-24 实现并验证；2026-11-26 `REQ-0042` 增量重验：动作组迁到窗口级 toolbar 并贴右、tooltip 安装器补全，`T-SCN-0028-05` 通过；真实窗口点击/悬停仍为发布前人工项）。

- 实现：`MailboxView` 去掉侧栏，根视图 toolbar 的 `.navigation` 位放三段 `Picker(.segmented)`，默认收件箱；邮件页改两栏 `NavigationSplitView`，列表 `min 320 / ideal 480`、阅读区取剩余；日历页占满内容区，顶部切换保留；工具栏刷新按 section 分派；`MailboxView` 293 行（≤300）。
- 证据（L2）：`task-spaces/20261125-000000-sent-nav/probe/toolbar-nav.png`——顶部 Picker 在 leading、交通灯之后，三段可见，无文件夹栏；`task-spaces/20261125-000000-sent-nav/probe/two-column.txt`——1440 list=480 reading=952，900 list=480 reading=412；`HSplitView` 在 1440 把 list 拉到 760、不遵守 `idealWidth`，因此否决（`task-spaces/20261125-000000-sent-nav/probe/HSplitProbe.swift`）。
- 证据（L1）：`Tests/PresentationTests/MailboxViewModelTests.swift` 的 `selectSent` 例（folder 18、列表出现已发送副本、phase idle）；全量 465 tests / 77 suites、架构 4/4、`make-app.sh` 成功（release，2026-11-24 23:57 CST）。
- 未覆盖（发布前人工项）：真实点击顶部三段切换、真实列表/阅读分隔条拖拽、深色主题整窗视觉；真实快速切换的竞态未做无头探针。
