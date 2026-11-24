---
layer: history
module: global
status: frozen
updated: 2026-11-24
---

# 坑档案

现象、存续条件、对策落点。只在 `history/` 冻结；允许更新「存续状态」。

## P1 日历 → 邮件跳转不定位，侧栏「日历」点不动（2026-11-24，已修复）

- **现象**：在日历里点「打开邮件」，回到邮件页后没有选中/滚动到那封邀请；随后再点侧栏「日历」没有反应，像是卡在邮件页。
- **存续条件**：
  1. 侧栏的「日历」是 `List` 上方的一个 `Button`，而文件夹是另一个 `List`；两者用两个状态源（`showingCalendar` + `List(selection:)`），
     再靠 `onChange(of: folderSelection)` 把 `showingCalendar` 置回 `false`。分栏重建时 List 会重新解析 selection，触发 `onChange`，
     把刚设为 `true` 的 `showingCalendar` 立刻改回 `false`。
  2. 跳转只调 `select(folderID:)` + `select(messageID:)`：前者在「同一文件夹」时早退，后者只在已加载的 200 封里找；
     搜索模式下 `messages` 还是搜索结果，找不到就静默返回；即使选中，`List` 不会滚动到该行。
- **对策**：
  - 侧栏改为**单一 `List(selection:)`**：日历行与文件夹行共用一个 selection（`__calendar__` 哨兵 + folder id），
    删除 `Button` 与 `onChange` 之间的双状态同步（`MailboxView.sidebarSelection`）。
  - 新增 `MailboxViewModel.reveal(folderID:serverID:)`：退出搜索、切文件夹、重载页面、再选中；找不到返回 `false`，
    由状态栏提示「该邀请不在当前列表页」。
  - 消息列表加 `ScrollViewReader`，选中变化时 `scrollTo(anchor: .center)`。
- **回归**：`Tests/PresentationTests/MailboxViewModelTests.swift` 的 `MailboxRevealTests` 3 例（跨文件夹、清搜索、未找到）。
- **落点**：`Sources/uumail/MailboxView.swift`、`Sources/Presentation/MailboxViewModel.swift`、`design/components/CMP-APP/spec.md` 增量。
