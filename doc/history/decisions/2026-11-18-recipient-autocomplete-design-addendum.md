---
layer: history
module: mail
status: frozen
updated: 2026-11-18
---

# 收件人联想方案设计复核增补（A1–A6，2026-11-18）

## 背景

`REQ-0022` / `SCN-0017` 的 P1 默认确认见 `2026-11-18-recipient-autocomplete.md`（D1–D10）。方案设计复核（run `task-spaces/20261118-082503`）在现状基线上做了两处布局/控件实测，发现原设计增量里有两处会在实现期直接违反「不改变表单基线」：

1. 候选浮层放在 `ZStack` 里会参与布局：200pt 浮层把后续内容下推 60pt（`task-spaces/20261118-082503/evidence/design-probe/overlay-probe.txt`）；`.overlay` 不参与布局，后续内容位置不变。
2. 现状 SwiftUI `TextField` 的 AppKit 载体是 `isBordered=false`、`drawsBackground=true`、`backgroundColor=.textBackgroundColor`、13pt、24pt 高、文本 4pt inset（`task-spaces/20261118-082503/evidence/design-probe/textfield-probe.txt`、`field-probe.txt`）；普通 `NSTextField` 只有 16pt 高、0pt inset，直接替换会改变 100% 表单基线。

因此本记录在不改 D1–D10 方向的前提下，落 A1–A6 的实现级细化。**不新增 P1 触发项**：不改模块切分、schema、数据所有权、依赖方向、热路径失败语义，也不新增 target/依赖。

## 增补

| # | 项 | 结论 |
|---|---|---|
| A1 | 浮层宿主 | D5 的「Form 外 ZStack」改为 **Form 的 `.overlay(alignment: .topLeading)`**；浮层不参与布局，按当前字段 anchor 的 `minX/maxY+4` 定位；`ComposeView` 给 `ComposeRecipientForm` 在 VStack 中 `.zIndex(10)`，避免被 Divider/格式栏/编辑器覆盖。高度取 `min(内容, 240×scaleFactor, 字段下方可用高度)`，超出滚动。 |
| A2 | 控件文件切分 | `ComposeRecipientForm` 从 `ComposeView.swift` 拆到 internal `Sources/uumail/RecipientForm.swift`；`RecipientTextField.swift` 只放 `RecipientTextField`/`RecipientSuggestionList`。目的是 L2 探针只编译这两个生产文件，不必拉整棵 `ComposeView` 依赖树；不新增 target。 |
| A3 | 字段外观/标签 | `RecipientTextField` 改为字段-only；标签由 `ComposeRecipientForm` 的 `LabeledContent("收件人"/"抄送")` 提供（实测字段起点与现状 `TextField` 同为 x=59）。字段按现状拟合：无边框、`textBackgroundColor` 背景、13pt、4pt 文本 inset、100% 24pt 高；随 `fontSizePreference` 缩放字体与行高。 |
| A4 | 读取上限 | D4 的「每文件夹 500 封」之外，加**总计 5,000 封**上限；按 `folders` 顺序（Inbox 优先）累计。超出部分的旧邮件联系人不出现，属已接受降级（R46），不报错、不影响发送。 |
| A5 | 点击/IME | 点击候选行时字段若先失焦，视图用 `suggestionClickInFlight` 守卫把清空延后到下一 runloop，点击仍按原字段 index 选中后再还焦点；中文输入法组合态 `Esc` 只收候选、不取消组合（有候选时消费命令，无候选交还输入法）。两条都进 `T-SCN-0017-03` 的 L2。 |
| A6 | 测试 seam | `ComposeScene` 加 internal 常量 `recipientDirectoryFolderLimit=500`/`recipientDirectoryTotalLimit=5_000`；`ComposeViewModel` 加 internal `directoryLoadCount`，供 `@testable` 测试断言上限与「只加载一次」。不进入 public 契约。 |

## 范围与确认

- 落点：`CMP-APP`/`CMP-SCN-COMPOSE`/`CMP-DOMAIN`/`CMP-PRES` 设计增量、`SCN-0017`、`architecture.md` §1/§3.7/§4/§10.2、`roadmap.md` §W-M3-09、`risks.md` R46–R49、`doc/README.md`。
- 不涉及：产品代码、测试代码、`Package.swift`、schema/迁移、`MailStore`、发送链路、状态位、任务表；`MailStore` 仍 1008/1000（R45）。
- **默认确认（未经人工）**：无人值守，按 `auto-confirm` 对 A1–A6 取推荐项并继续；本记录不是发起人签字，评审可独立否决。若评审否决 A1/A3/A4，回设计改浮层宿主/控件形态/上限，不复用本记录。
- 回退：纯文档增量；删除本记录与对应设计增量行即可，无数据/契约迁移。A1 若在实现期 hit-testing 仍失败，按 `SCN-0017` 改声明 L3 并写理由，不静默降级。

## 证据

- `task-spaces/20261118-082503/evidence/design-probe/overlay-probe.txt`：ZStack vs `.overlay` 对后续元素位置的影响（200pt 浮层，ZStack 下推 60pt；overlay 不变）。
- `task-spaces/20261118-082503/evidence/design-probe/textfield-probe.txt`：现状 Form `TextField` 的 `NSTextField` 属性（无边框、`textBackgroundColor`、13pt、24pt、4pt inset）。
- `task-spaces/20261118-082503/evidence/design-probe/field-probe.txt`：字段-only 自定义 `NSTextField` 与 `LabeledContent` 同 x=59，但高度 16pt、inset 0；据此定 A3 的 24pt/4pt 拟合要求。
