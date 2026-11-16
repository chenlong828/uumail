---
layer: design
module: mail
scope: project:uumail
status: verified
updated: 2026-11-17
flow: mail/read
scenario: SCN-0014
---

# SCN-0014 手动标记邮件为已读

## 结果

用户在邮件列表选中一封未读邮件，点击窗口主工具栏的「标记为已读」；该邮件立即在本机转为已读：列表小蓝点消失、主题字重回到常规，不等待网络；已读状态持久化，并在后台回写服务器一次。已读邮件或无选中时入口不可用，不产生网络写；服务器回写失败不回滚本地已读、不弹错误；本地写失败时邮件保持未读，并在状态栏给出用户可感知的中文提示。手动置读与自动计时并发时只有一次真实 0→1 与一次网络写。

## 入口

- `CMP-APP#MailboxToolbar`（新增 internal `ToolbarContent`：主工具栏「标记为已读」按钮，图标 `envelope.open`；`!canMarkSelectedRead` 时禁用）
- `CMP-APP#MailboxView`（把 `viewModel` 的可用条件与 `markSelectedRead()` 接进工具栏；状态栏在删除错误之后显示 `viewModel.markReadErrorText`；不判业务、不拼中文）
- `CMP-PRES#MailboxViewModel.markSelectedRead()`、`#canMarkSelectedRead`、`#markReadErrorText`（新增 public 方法/派生/错误状态；P2 待确认）
- `CMP-PRES#MailboxViewModel.performMarkRead(_:)`（internal；本地置读 + 列表重载 + 仅 0→1 启动回写的唯一入口，供手动与 `MailboxDwell` 共用；它调 internal `localMarkRead` 闭包，默认 `read.markReadLocally`，测试可注入抛错；本地失败在返回前归一为 `MailError`，非 `MailError` → `.storage(reason: String(describing:))`）
- `CMP-PRES#MailboxDwell`（改为仅计时：3 秒；`onElapsed` 回调到 `performMarkRead`；不再直接持有 `ReadScene`；本批同时完成 10→3 秒）
- `CMP-SCN-READ#markReadLocally`、`#writeBackMarkRead`（既有两阶段；复用，不新增方法）
- `CMP-DOMAIN#MailWriteGateway.markRead`、`SyncStore.markRead/commitMarkRead`（既有；不改）
- `CMP-SYNC#markRead`（既有串行门；不改）
- `CMP-STORE#markRead`、`#commitMarkRead`（既有本地置读/提交；不改）
- `CMP-PRES#ErrorText`（本地写失败的中文映射；既有，只接收 `performMarkRead` 归一后的 `MailError`，不新增用户可见文案体系）
- 不新增 `CMP-STORE`/`CMP-SYNC`/`CMP-EAS*` 方法，不改 schema/协议。

## 运行序

流程 `F-READ-07`：

1. 用户选中一封未读邮件 → `canMarkSelectedRead` 为 true（当前选中且 `isRead == false`），工具栏「标记为已读」可用；选中已读邮件/无选中/选中行被临时隐藏 → 禁用。正文 `.loading`/`.failed` 不影响置读入口（置读不依赖正文）。
2. 点击 → `MailboxViewModel.markSelectedRead()` 先清空 `markReadErrorText`，再对当前选中未读邮件调一次 `performMarkRead(ref)`；后者只调一次 internal `localMarkRead(ref)`（生产默认闭包为 `read.markReadLocally(ref)`）。存储把 `is_read` 置 1（记录是否真实 0→1），返回。
3. 本地成功 → `markReadErrorText` 保持 nil；立即重载当前列表（蓝点消失、字重常规），不等网络；`refreshDwell()` 使已读邮件的自动计时取消。
4. 仅当返回 true（真实 0→1）→ 后台 `Task { await read.writeBackMarkRead(ref) }`；经 `SyncEngine` 串行门写 `Change/Read=1`，成功后 key 推进。返回 false（已被同步置读/已读/已删/被隐藏）→ 仍重载一次纠正陈旧列表，不启动回写。
5. 回写失败（offline/503/鉴权/设备未登记/策略拒绝）→ 本地已读保持，不弹错、不回滚、不重试；下一次同步按服务器事实更新其它邮件。
6. 手动置读与自动计时同时命中同一封 → `@MainActor` 串行：先完成本地写的一方产生唯一一次 0→1 与一次网络写；后一方 `markReadLocally` 返回 false，不再回写；列表刷新后自动计时取消；不得出现第二封被误置读。
7. 本地写失败 → 不把列表显示成已读、不启动回写；`performMarkRead` 在返回前把错误归一为 `MailError`（非 `MailError` 一律 `.storage(reason: String(describing: error))`），`markSelectedRead` 只把该 `MailError` 交 `ErrorText` 写 `markReadErrorText`——`storage` 分支固定为「本地存储失败：…」，保证中文片段；状态栏在删除错误之后显示该提示；列表保持未读，入口仍可用，可重试。
8. 选中变化/删除/搜索切换 → `canMarkSelectedRead` 跟随新的选中；`selectedListKey` 变化时清空 `markReadErrorText`，不把上一封的错误带到新选中。

失败路径：

- 本地存储错误 → 保持未读、无回写、有可感知中文提示；错误可能是 `MailError`，也可能是 `MailStoreError`/GRDB `DatabaseError`/`NSError`（`markReadLocally` 原样抛出），一律由 `performMarkRead` 归一后再映射；重复点击仍按未读处理，不产生网络写。
- 回写失败 → 本地已读保持、无 UI 错误；下一次同步不因此暂停自动刷新（按既有规则）。
- 回写时 `SyncKey` 失步（`Status=3/4`）→ 只算回写失败；下一次刷新按既有规则重建，不用手动置读触发重建。
- 选中行在点击前已被删除/隐藏 → 入口已禁用或动作 no-op；不崩溃、不发网络。
- 写响应携带整页 delta/`MoreAvailable` → 按既有写路径同事务提交，剩余页由下一轮同步消费；不回滚本地已读。
- 已读邮件重复点击/重复调用 → 幂等，无第二次网络写；`canMarkSelectedRead` 为 false 时强制调用也不写本地、不发网络。
- 自动计时在手动置读后仍试图回写 → 第二次 `markReadLocally` 返回 false，不再回写；不会出现第二封被置读。

## 不可变引用

- 复用 `ReadScene.markReadLocally`/`writeBackMarkRead` 与 `SyncEngine.markRead`；不新增 `MailWriteGateway`/`SyncStore`/`MailStore` 方法，不改 schema/协议。
- `markReadLocally` 的 `throws` 面不变（可能抛 `MailStoreError`/GRDB 错误，不强制归类）；用户可见中文由 `performMarkRead` 归一后交给 `ErrorText`，`ReadScene` 不 import PRES、不拼文案。
- 自动已读计时/取消规则归 `SCN-0008`（本批 10→3 秒修订）；本场景不改变计时、前台、搜索模式等条件。
- 回写失败语义与 `SCN-0008` 一致：本地已读不回滚、不弹错、不重试、不推进 key。
- 列表身份用复合 `listKey`（folder + serverID，R23）；只作用当前选中一封。
- 不做离线补写队列/`pending_op`/`readDirty`（`plan/open-questions.md` Q2 口径不变）。
- 不做「标记为未读」、全部已读、按文件夹已读、右键菜单、快捷键、批量多选、已读回执、置读后自动跳下一封。
- 不改删除、同步、发送、搜索、主题、通知；不新增第二套已读语义入口。
- 无新增 DB/Keychain/网络写入；测试用假邮件/假网关，不写真实邮箱或凭据。
- 入口只在窗口主工具栏；不新增第二条工具条或第二个已读入口。

## 测试

| ID | 类型 | 层级 | 方案 | 可执行 ID |
|---|---|---|---|---|
| `T-SCN-0014-01` | 正 | L1 + L2 | 选中未读、应用前台，点击工具栏「标记为已读」→ 本地 `isRead == true` 持久化、VM 列表值为已读（蓝点/字重由 `messages` 的 `isRead` 派生，L1 断言该派生；L2 只断言工具栏点击触发动作，不单独做像素断言）；服务器写命令恰好一次且携带当前 key、key 推进；不等待网络。返回 false 的竞态不产生回写。 | `MailboxViewModelTests.manualMarkReadPersistsBeforeWriteBack`（L1）+ `ManualMarkReadProbe.toolbarButtonInvokesMarkRead`（L2） |
| `T-SCN-0014-02` | 正 | L1 + L2 | 选中已读/无选中 → 入口禁用；强制调用不写库、不发网络；重复标记同一封幂等，不产生第二次网络写；切 A→B 后只影响 B；选中行被隐藏时 no-op。 | `MailboxViewModelTests.manualMarkReadIsIdempotentAndSelectionScoped`（L1）+ `ManualMarkReadProbe.buttonDisabledWhenNoUnread`（L2） |
| `T-SCN-0014-03` | 正 | L1 | 手动置读与自动计时/普通同步并发 → 只有一次真实 0→1 与一次网络写；列表只目标行变已读；自动计时在刷新后取消，无第二封被误置读；`SyncEngine` 串行门不被写响应分页拖成两次写。 | `MailboxViewModelTests.manualMarkReadRacesDwellOnce` + `SyncEngineTests.markReadIsSerializedWithSyncOnce`（既有） |
| `T-SCN-0014-04` | 反 | L1 | 回写失败（offline/503）→ 本地仍已读、`markReadErrorText == nil`、不回滚；本地写失败 → 保持未读、`markReadErrorText` 含中文、不启动回写、列表不显示已读；已读邮件选中不发网络。本地失败经 internal `localMarkRead` 闭包（`@testable import Presentation`）注入，**至少两条**：① `MailError.storage(reason:)`；② 非 `MailError`（`MailStoreError.database("磁盘写入失败")` 与/或 `NSError`）。非 `MailError` 走 `performMarkRead` 的同一归一分支，断言 `markReadErrorText` 等于 `ErrorText.text(for: .storage(reason: String(describing: injected)))` 或至少以「本地存储失败」开头并含注入的中文原因；不得只注入 `MailError` 造成假绿。状态栏绑定由代码审查确认（与 `SCN-0009` 删除错误同一 L1 口径），本卡不上 L2 状态栏像素断言。 | `MailboxViewModelTests.manualMarkReadWriteBackFailureKeepsLocal` + `...manualMarkReadLocalFailureReportsChinese`（MailError）+ `...manualMarkReadNonMailErrorReportsChinese`（`MailStoreError.database`/`NSError`）+ `...normalizeMarkReadErrorWrapsNonMailError`（L1） |

证据层级：L1 单元测试 / L2 无头探针 / L3 截图 OCR / L4 GUI 自动化（AX）。本卡最低 L1，按钮存在/可用另用 L2。

测试载体：

- **L2 `ManualMarkReadProbe`**：独立可执行文件，直接编译生产 `Sources/uumail/MailboxToolbar.swift`；离屏 `NSHostingController` + `NSWindow` 承载 `NavigationSplitView` + `.searchable`，读 `NSToolbar.items`/`visibleItems` 的 `label`，用 `window.sendEvent` 合成点击；先断言条目存在可见，再断言点击调用 `actions.markSelectedRead`、禁用时调用次数不变。设计探针已证 seam（`task-spaces/20261116-223645/evidence/toolbar-probe/`，33 条断言 PASS）。不新增 target、不启动 app bundle、不截图/OCR、不依赖辅助功能授权。
- **L1 `PresentationTests`**：`MailboxViewModelTests` 用假邮件/假 `MailWriteGateway`/内存 `MailStore` 覆盖本地先行、恰好一次回写、key 推进、竞态、幂等、回写失败静默、本地失败提示；本地失败同时覆盖 `MailError` 与非 `MailError`（`MailStoreError.database`/`NSError`，`MailStore` 已在测试 target 依赖内），断言归一后的中文前缀与「保持未读、零回写」。测试注入点在 `performMarkRead` 的 `do` 内，归一化在同一 `catch`，因此非 `MailError` 用例与生产 `read.markReadLocally` 抛 GRDB 错误走同一分支，不是假绿。`ReadSceneTests`/`SyncEngineTests` 既有两阶段与串行门用例不回归。
- 状态栏提示以 `markReadErrorText` 的可断言中文片段为准（与 `SCN-0009` 删除错误一致）；不把「不崩溃」当通过。
- 证据入 `task-spaces/<run>/evidence/`，使用假邮件/假网关；不写真实邮箱、主题或凭据。
- 若某条 skip，必须有替身并登记，否则最多 `designed`，不能标 `verified`。

## 状态

`verified`（2026-11-17，T-1116-16 验证，收尾按 `review.md` §7 清单翻转）。原 `designed`（2026-11-16 设计落卡；同日第 2 轮按方案评审 F1 补本地置读错误归一化契约与非 `MailError` L1，四元素与 3 正 1 反结构不变）。四元素：入口 `present`、运行序 `present`（含失败路径）、不可变引用 `present`、测试 `present`（3 正 1 反，`T-SCN-0014-01..04` 可执行，最低 L1 + L2）。

本卡依赖 `CMP-PRES` 新增 public 方法/派生/错误状态，属 P2 契约增量；确认清单见 `task-spaces/20261116-223645/design.md` §8.2 与 `CMP-PRES` 设计增量。**本卡不代签确认记录**；P2 已于 2026-11-16 确认（`history/decisions/2026-11-16-remote-toolbar-mark-read.md`），实现见 `T-1116-12`/`T-1116-13`。

`verified` 判据：`T-SCN-0014-01..04` 全 pass；`SCN-0008`（按 3 秒修订后）与 `SCN-0004` 回归不退化；无 skip（或有替身并登记）。本轮结果：4 条例子全 pass（L1 + L2，`evidence/t1116-16-scn-0014.txt`、`test.md` §2.3）；`SCN-0008`/`SCN-0004` 回归无退化；`T-SCN-0014-03` 的竞态注入保留项按非阻塞登记（`review.md` H1）。

## 与相邻场景的边界

- `SCN-0008` 列表停留自动已读：自动计时的触发/取消/3 秒归它；本场景只认领手动入口，二者共享本地/回写路径但断言不重复。
- `SCN-0009` 键盘删除：删除隐藏/失败恢复不改；本场景不处理删除。
- `SCN-0004` 邮件阅读：打开/正文状态不改；手动置读不改变正文。
- `SCN-0003` 收件箱同步：普通同步仍按服务器 `Read` 更新；本场景只回归「写回与同步串行、只一次网络写」。
- `SCN-0013` 远程图片开关：同在主工具栏；两个控件互不影响，工具栏拥挤风险见 `plan/risks.md` R32。
