---
layer: history
module: mail
status: frozen
updated: 2026-11-16
---

# 远程图片开关归位、手动置读与 3 秒自动已读：P2 确认（D1–D8）与实现边界（2026-11-16）

## 背景

`REQ-0018`（远程图片开关并入工具栏）、`REQ-0019`（手动标记已读）与 `REQ-0013`（连续停留 10→3 秒重开）在 2026-11-16 完成需求分析与设计。改动收敛到 `CMP-PRES`（`MailboxViewModel` 会话内放行状态、手动置读与共用写路径、`MailboxDwell` 纯计时）与 `CMP-APP`（`MailboxToolbar`、`MailboxView`/`MessageBodyView` 接线），不新增组件/target/依赖，不改 `MailDomain`/`MailStore`/`Scenes` 契约、schema 或协议。

按 `arch-design-spec`，`MailboxViewModel` 新增 6 个 public 成员（additive）、跨 `Presentation`/`uumail` 两个 target，并新增 internal 工具栏文件，定为 **P2**。`task-spaces/20261116-223645/design.md` §8.2 列出 D1–D8 待人工确认；`roadmap.md` §W-M3-06 将其排为任务链首的人工门 `T-1116-11`，门未关闭前不得改 `Sources/`。2026-11-16 的实现准出评审因此判 fail：确认记录缺失，开发节点停在门前。

## 确认来源与范围

- 本记录由 W-M3-06 实现批次（run `20261116-223645`）在代码评审回退重跑时归档。
- 确认来自任务发起人在本次 agent-flow 回退重跑中给出的执行指令：先回 confirm 阶段关闭 `T-1116-11`（按 `design.md` §8.2 确认 D1–D8，并落 `history/decisions/2026-11-16-remote-toolbar-mark-read.md`），再重跑开发 `T-1116-12`→`T-1116-13` 并补齐 `SCN-0008`/`SCN-0013`/`SCN-0014` 的 L1/L2 证据。
- 发起人**未逐项改写** D1–D8；按 `design.md` §8.2 的**唯一建议答案**确认，无收窄、无改选。原始确认没有独立 IM/邮件原文；**本记录是唯一书面落点**，不把编排指令伪造成第三方签字。
- 确认人：任务发起人（工作区所有者）；确认时间：2026-11-16（本次回退重跑指令）；确认项：D1–D8；影响范围：`REQ-0018` / `REQ-0019` / `REQ-0013` / `SCN-0013` / `SCN-0014` / `SCN-0008` 的 P2 实现与 L1/L2 验证，以及本批任务 `T-1116-11`…`T-1116-16`。

## 决定

| # | 确认项 | 结论 |
|---|---|---|
| D1 | 远程放行状态归属与重置 | `MailboxViewModel.allowsRemoteContent`（默认 `false`、不持久化）+ `selectedListKey.didSet` 在选中身份变化时重置；`canAllowRemoteContent` 要求当前选中身份匹配正文所属 `openedBody`/`openingRef` 且 `body` 为 `.loaded`；setter `true` 受守卫、`false` 总是允许。 |
| D2 | 手动置读 API 与错误面 | `canMarkSelectedRead`/`markSelectedRead()`/`markReadErrorText`；同步完成本地写，仅 0→1 时后台 `writeBackMarkRead`；本地失败在 `performMarkRead` 归一为 `MailError`（非 `MailError` → `.storage(reason: String(describing:))`），再经 `ErrorText` 写状态栏，保证中文；回写失败静默；internal `localMarkRead` 闭包仅测试注入，不进 public 面；`T-SCN-0014-04` 覆盖 `MailStoreError.database`/`NSError` 等非 `MailError`。 |
| D3 | `MailboxDwell` 仅计时重构 | 去掉 `ReadScene` 依赖与 `onMarked`，只保留 `sleep`/`update`/`cancel` 与 `onElapsed`；`onElapsed` → `performMarkRead`；3 秒私有常量；测试记录并断言 `.seconds(3)`。 |
| D4 | 工具栏形态与顺序 | 抽出 internal `MailboxToolbar`；7 个紧凑图标按钮；顺序固定：新建 → 回复 → 全部回复 → 转发 → 加载远程图片 → 标记为已读 → 刷新；仍是唯一窗口工具栏，不新增第二工具条。 |
| D5 | 远程入口控件 | 带状态 `Button`（`photo`/`photo.fill` + `accessibilityValue`「已开启/已关闭」），不用 Toggle、不用菜单/隐藏入口。 |
| D6 | 不可用行为 | 禁用而非隐藏：无选中/正文未加载/失败/已读均禁用，布局稳定；远程入口在正文 `.loading`/`.failed` 时不可用。 |
| D7 | L2 载体 | 独立 `RemoteContentToolbarProbe`/`ManualMarkReadProbe` + 生产 `MailboxToolbar`，离屏 `NSHostingController`，读 `NSToolbar.items`/`visibleItems` 并用 `window.sendEvent` 合成点击；不新增 target、不启动 app bundle、不依赖 AX。 |
| D8 | 正文侧 L2 | `RemoteContentBodyProbe` 编译生产 `MessageBodyView`/`MessageWebView`/`MessageBodyStyle`（假 HTML），断言正文无独立开关行 + Bool→CSP 重载；不加载真实远程资源，不把源码删除当 L2。 |

**N6**：`MailboxToolbar` 是 `CMP-APP` 的内部文件（internal `ToolbarContent`），**不是新组件**，不新增组件卡/target/依赖；因此不触发 P1 组件切分评审。

## 影响

- `CMP-PRES` 新增 6 个 public 成员（`allowsRemoteContent`、`canAllowRemoteContent`、`setAllowsRemoteContent(_:)`、`canMarkSelectedRead`、`markSelectedRead()`、`markReadErrorText`）与 internal `performMarkRead`/`normalizeMarkReadError`/`localMarkRead`；均为 additive，不改既有成员签名。
- `CMP-APP` 新增 internal `MailboxToolbar`，`MailboxView` 接入工具栏/状态栏/阅读区，`MessageBodyView` 删除 `@State` 与正文开关行并新增只读 `Bool`；`MessageWebView` 的 CSP/禁 JS/白底/`lastRender` 不变。
- `MailboxDwell` 改为 3 秒纯计时；自动/手动共用 `MailboxViewModel.performMarkRead`；不新增 `pending_op`/`readDirty`/离线队列。
- 不新增依赖/target/schema，不改 `MailDomain.Message`、`MailStore`、`MailGateway`/`Scenes`，不写偏好/Keychain/业务库；读路径仍零网络。
- 实现与验证按 `roadmap.md` §W-M3-06：`T-1116-12`（`CMP-PRES`，L1）→ `T-1116-13`（`CMP-APP`，L1 CSP + L2）→ `T-1116-14`/`T-1116-15`/`T-1116-16`（三张场景卡复跑）。**开发/评审不翻转 `SCN-0013`/`SCN-0014`/`SCN-0008` 的 `verified` 与 `REQ-0018`/`REQ-0019`/`REQ-0013` 的 `delivered`**，只由收尾在评审通过后执行。
- 回滚 = 回退实现与测试；纯 additive、无 schema/数据迁移、无持久化放行状态。

## 未采纳 / 明确不做

- 不保留正文内远程开关，不新增第二处入口或第二工具条。
- 不做全局放行/白名单/内容检测/自动加载/每封记忆；开关不写偏好、不跨会话保留。
- 不做「标记为未读」、全部已读、按文件夹已读、右键菜单、快捷键、批量多选、已读回执、离线补写队列。
- 不做 L3 截图/OCR、L4 AX/VoiceOver；本批最高 L2。远程图片实际不发请求仍归 `SCN-0004` 既有欠账 `T-SCN-0004-03`，本批不接管。

## 落点

- 需求/场景：`doc/requirements/REQ-0018-remote-content-toolbar.md`、`doc/requirements/REQ-0019-mark-read-manual.md`、`doc/requirements/REQ-0013-dwell-auto-read.md`；`doc/design/scenarios/mail/read/remote-content-toggle/scenario.md`（`SCN-0013`）、`.../mark-read-manual/scenario.md`（`SCN-0014`）、`.../dwell-auto-read/scenario.md`（`SCN-0008`）。
- 规格：`doc/design/components/CMP-PRES/spec.md`、`CMP-APP/spec.md` 的 2026-11-16 增量（P2 状态改为已确认，实现后追加进度行）、`CMP-SCN-READ/spec.md` 的手动置读复用说明。
- 排期：`doc/plan/roadmap.md` §W-M3-06（门行与 `T-1116-11` 状态）。
- 实现：`Sources/Presentation/MailboxViewModel.swift`、`MailboxDwell.swift`、`Sources/uumail/MailboxToolbar.swift`（新）、`MailboxView.swift`、`MessageBodyView.swift`。
- 测试/证据：`Tests/PresentationTests/MailboxViewModelTests.swift`；L1/L2 证据入 `task-spaces/20261116-223645/evidence/`。
