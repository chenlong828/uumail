---
layer: requirements
module: mail
scope: project:uumail
status: delivered
updated: 2026-11-26
---

# REQ-0042 主窗口顶栏：三段切换在左、邮件动作在右

- **ID**：REQ-0042
- **类型**：`quality`
- **场景叙述**：主窗口顶栏左侧是「收件箱 / 发件箱 / 日历」三段切换；右侧依次是新建、回复、全部回复、转发、加载远程图片、标记为已读、刷新七个动作，紧贴右侧的搜索框。窗口在 1000pt 以上宽度时七个动作全部可见、不折叠进「»」溢出菜单；每个图标悬停显示中文说明（tooltip）。窗口缩到最小宽 900pt 时才允许局部折叠，折叠的动作仍可从溢出菜单触发。
- **价值**：不做的后果——动作工具栏挂在列表列上，被 `NavigationSplitView` 归入 leading 组：位置挤在三段切换与标题之间，空间尚可（1512pt）时「加载远程图片」「标记为已读」「刷新」就已折进溢出菜单，用户要点两次才能取用；图标也没有悬停提示，只能靠猜。动作回到右侧后，顶部形成「左边切换 / 右边操作」的稳定分工，与 macOS 邮件一致。
- **非目标**：
  - 不改动作集合、动作语义、禁用规则（`hasSelection`/`canAllowRemoteContent`/`canMarkSelectedRead`/`isSyncing`）与刷新按 section 分派。
  - 不改三段切换的语义、默认 section、发件箱迟到保护与日历页行为。
  - 不改搜索框本身（`.searchable` 的绑定、⌘F、空态与结果过滤）。
  - 不改浮窗阅读窗自己的工具栏（`ReaderWindowView`）。
  - 图标不改成常驻文字标签（保持 icon-only + tooltip）；发送类窗口（撰写 sheet）不在本需求内。
  - 不改 schema、不新增 target/依赖。
- **约束**：
  - 动作组由窗口级 toolbar（`MailboxView` 根视图 `.toolbar`）声明，不再挂在 `mailListColumn` 上；排列为 `.primaryAction`。
  - 动作组必须贴住右侧搜索框：`ToolbarTooltipInstaller` 在工具栏出现后插入一个 `.flexibleSpace` 到动作组之前，并移除系统放在搜索框之前的多余 `.flexibleSpace`；重复安装不得重复插入（状态变化下稳定）。
  - tooltip 由同一个安装器按 label 映射写入 `NSToolbarItem.toolTip`（SwiftUI `.help` 不会桥接到 toolbar item）；新增/改名动作必须同时更新映射与 `actionLabels`。
  - 900pt 最小宽允许系统溢出；不为此缩小三段切换或隐藏动作。
- **影响场景**：
  - `SCN-0028`（`mail/receive/mailbox-sections`）：新增 `T-SCN-0028-05`（顶栏分组、不折叠、tooltip），场景做增量重验。
  - 回归（不新增断言）：`SCN-0025`（浮窗打开/浮窗内撰写不受影响）、`SCN-0024`（日历页仍占满内容区、顶部切换在）、`SCN-0006`（发送仍只入队）。
- **澄清记录**：
  - 2026-11-26 **人工确认**（截图：1512pt 主窗口）：三段切换放左上、回复等动作放右上；「空间很充足但最右侧图标还折叠了」按缺陷处理；「这批图标没有指示标签」按悬停提示（tooltip）处理。
- **状态**：`delivered`（2026-11-26 实现并验证：动作组迁到窗口级 toolbar 并由安装器贴右；466 tests / 77 suites、架构 4/4；L2 探针 1512/900 截图；`make-app.sh` 成功）。
- **验收归属**：`SCN-0028` 的 `T-SCN-0028-05` 通过 + 上述约束逐条无违反 + 回归场景不退化；需求不另立测试。
