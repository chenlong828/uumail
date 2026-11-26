---
layer: works
module: mail
scope: project:uumail
status: active
updated: 2026-11-26
---

# W-M3-22 设计：顶栏动作组贴右

## 归因（探针实测）

把同一组 `MailboxToolbar` 分别挂在列表列、根视图、容器、兄弟视图，`NSToolbarItem.view` 帧一致：动作都在 x≈591..862（1512pt 窗口），搜索框在右缘，中间空一大片。结论：macOS 26 的 `NavigationSplitView` 把 primaryAction 项排进 leading 组（紧随三段切换与侧栏开关），点选/尺寸变化时先触发溢出；不是挂载视图选错。

## 方案

- 动作组上提到 `MailboxView` 根 `.toolbar`（与三段 Picker 同一处）；列表列不再声明 toolbar。
- `ToolbarTooltipInstaller` 在工具栏出现后：
  1. 在动作组前插入一个 `.flexibleSpace`（若前一项不是 flexible space，幂等）；
  2. 删除 Search 项与最后一个动作之间的 `.flexibleSpace`（只删这一段，避免误删刚插入的那个）；
  3. 按 label 映射补 `NSToolbarItem.toolTip`（SwiftUI `.help` 不桥接，2026-11-26 复测仍为 nil）。
- 实测：动作组 x 898..1169，紧贴搜索框；0.3s 状态翻转 6s，items=13、flex=2、首动作 x 不变。
- 900pt（下限）：5 个动作可见 + 「»」溢出，属系统行为；不为此缩窄三段切换。

## 契约与风险

- 只动 `CMP-APP` 两个 internal 文件；无 public 契约/schema/依赖/target 变化。
- 依赖 `MailboxToolbar` 的 label；新增/改名动作必须同步 `actionLabels` 与 `tooltips` 映射。
- 搜索项识别用 identifier 含 `search` 或 label `Search`；找不到时只插不删（macOS 14/15 回退）。

## 定级

**P3**：组件内视图与工具栏安装逻辑，无契约/数据/热路径变化。
