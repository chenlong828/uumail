---
layer: design
module: app
scope: project:uumail
status: designed
updated: 2026-11-16
flow: settings/appearance
scenario: SCN-0011
---

# SCN-0011 菜单主题切换

## 结果

用户从 macOS 菜单栏的系统 View 菜单（中文系统显示为「显示」）下的「主题」子菜单选择「跟随系统」「浅色」或「深色」，应用外观在本次操作内立即切换（窗口标题栏、侧栏、列表、工具栏、配置页、撰写 sheet），当前项有勾选；选择写入本地偏好，退出重开仍生效，首次运行/偏好缺失/损坏/未知时跟随系统。切换只改应用 chrome，不重建窗口、不重置选中/滚动/正文/草稿、不重新加载正文、不触网；邮件正文区始终按 `SCN-0010` 的白底规则显示。

## 入口

- `CMP-APP#UumailApp`（`@main`；`@State theme`、`.preferredColorScheme(theme.colorScheme)`、`.commands`；`Sources/uumail/UumailApp.swift`）
- `CMP-APP#ThemeCommands`（系统 View 菜单的 `Picker("主题", selection:)` 子菜单；`Sources/uumail/ThemeCommands.swift`）
- `CMP-PRES#ThemePreferenceStore`（`load()`/`save(_:)`、默认与回退；public `init()` 用 `.standard`，测试经 internal `init(defaults:)` 注入独立 suite；`Sources/Presentation/ThemePreference.swift`）
- `CMP-APP#MailboxView`、`#AccountSetupView`、`#ComposeView`（主题消费者；不写偏好逻辑）
- `CMP-APP#MessageBodyView`（正文白底例外，规则归 `SCN-0010`）

## 运行序

流程 `F-APP-01`：

1. 启动 → `ThemePreferenceStore.load()` 读本地偏好（`system`/`light`/`dark`）。缺失、损坏或未知值 → `system`；`UumailApp` 以 `@State` 持有并在首窗口渲染时应用，避免先深后浅的闪烁。
2. 用户打开系统 View 菜单（中文「显示」）→「主题」子菜单显示三项；当前生效项带勾选（`system` 时勾「跟随系统」，即使系统当前是深色）。勾选在父菜单打开时刷新，读取未打开的 NSMenu 可能得到旧值（测试注意）。
3. 用户选择一项 → `Picker` 写入 `@State theme`；若与当前值不同，`ThemePreferenceStore.save` 写一次本地偏好；`preferredColorScheme` 立即把窗口与已呈现 sheet 切到目标外观，无需重启。
4. `system`：系统外观在运行中变化时应用跟随；`light`/`dark`：忽略系统外观变化，保持强制值；从强制值切回 `system` 时立即按当前系统外观显示。
5. 应用不重建窗口、不重载列表/正文、不重置选中/滚动/草稿、不触发同步或网络；阅读画布按 `SCN-0010` 始终白底。
6. 用户重复选择当前项 → `Picker` 的 binding guard 不写偏好、不改状态、不闪烁；选择不同项 → 立即生效并写一次偏好。
7. 退出重开 → 读取同一偏好并应用；若偏好存储不可读/写入失败，当前会话仍按用户选择显示（`@State` 是会话真源），下次启动回退到可读值/`system`；`save` 不抛错、不弹错。

失败路径：

- 偏好写入失败 → 不回滚当前会话外观、不弹错；下次启动读取旧值或默认值（`UserDefaults.set` 无同步失败信号，见 `doc/history/decisions/2026-11-16-theme-appearance.md`）。
- 偏好值损坏/未知 → `load()` 回退 `system`，不崩溃；菜单勾选与实际生效值一致。
- 在配置页/撰写 sheet 中切换主题 → 同样立即生效；表单输入、草稿、选中与滚动不丢。
- 系统外观在 `light`/`dark` 强制期间变化 → 应用不变；切回 `system` 后立即对齐当前系统。
- 主题切换时正文正在加载/已加载 → 正文不重载、不重新拉取；完成后仍白底。
- 无窗口/窗口关闭时通过菜单切换 → 状态记录并应用到下次窗口，不崩溃。

## 不可变引用

- `REQ-0015`/`SCN-0010`：正文内容区始终白底；主题选择不改变阅读画布。
- macOS 顶部菜单栏与系统对话框由系统控制，不在本景范围；主题只作用于应用窗口与控件，`uumailctl` 不变。
- 主题是 UI 偏好：不写业务库/Keychain/网络；不进入 `MailDomain`/`MailStore`/`Scenes` 契约；不改 schema、同步、发送、已读、附件。
- 单窗口现状；未来多窗口也必须应用同一主题（本景不引入按窗口配置）。
- macOS 14 最低版本；只用 SwiftUI/AppKit 标准能力，不引第三方。
- 默认 `system`；不新增设置窗口/偏好面板；菜单项是唯一入口。
- 当前项勾选与实际生效值一致；重复选择幂等。
- 菜单标题随系统本地化（View / 显示）；测试按系统 View 菜单或项标题「主题」定位，不硬编码「显示」。
- `SCN-0001`/`SCN-0004`/`SCN-0006` 只做外观回归，不新增本卡断言。

## 测试

| ID | 类型 | 方案 | 可执行 ID |
|---|---|---|---|
| `T-SCN-0011-01` | 正 | 首次启动无偏好 + 系统深色 → chrome 深色、勾「跟随系统」；系统浅色启动 → chrome 浅色；两种情况下正文都白底（引用 `SCN-0010`）。 | `ThemePreferenceStoreTests.defaultsToSystemWhenUnset` + `ThemeProbe.menuShowsFollowSystemChecked`（先打开父 View 菜单） |
| `T-SCN-0011-02` | 正 | 系统深色时选「浅色」→ 窗口/侧栏/列表/工具栏/配置页/撰写 sheet 立即变浅，正文仍白；退出重开仍浅。系统浅色时选「深色」→ 立即变深，正文仍白；退出重开仍深。 | `ThemePreferenceStoreTests.persistsAndRestoresAcrossInstances` + `ThemeProbe.selectingLightAndDarkAppliesImmediately`（window + sheet 的 `effectiveAppearance`） |
| `T-SCN-0011-03` | 正 | 「跟随系统」下模拟系统深→浅→深，应用实时跟随；选「深色」后系统变化，应用保持深；切回「跟随系统」立即对齐；重复选同一项不写偏好、不闪烁。 | `ThemeProbe.followSystemTracksSystemChanges`（`nil` + `NSApp.appearance` 模拟系统变化）+ `ThemeProbe.repeatedSelectionDoesNotChangeState`（计数与外观） |
| `T-SCN-0011-04` | 反 | 偏好缺失/损坏/未知 → 回退跟随系统、不崩溃；`save` 不抛错、当前会话值不被回滚；切换主题不重载正文、不重置选中/滚动/草稿、不触发网络；菜单勾选与生效值一致；正文仍按 `SCN-0010` 白底兜底。 | `ThemePreferenceStoreTests.invalidValueFallsBackToSystem` + `ThemeProbe.themeChangeDoesNotReloadBodyOrResetSelection`（`WKNavigationDelegate` 计数 + 选中/滚动快照） |

> `SCN-0011` 断言里的「正文仍白」是前置回归，引用 `SCN-0010` 的断言，不重复计数。菜单勾选断言必须先打开父级 View 菜单，再读取 `NSMenuItem.state`；本轮已实测静止读取会得到旧值（R26）。
>
> 测试替身：偏好逻辑用 `PresentationTests`（`@testable import Presentation`，经 internal `init(defaults:)` 注入独立 `UserDefaults` suite）；菜单/窗口/sheet 用独立 `ThemeProbe`（SwiftUI + AppKit）；真实 app bundle 的最终 chrome 用截图/AX 冒烟，证据入 `evidence/`。不新增 `uumail` 测试 target。

## 状态

`designed`（2026-11-16，T-1116-01 落卡）。Q5 已按 A 确认（`settings/appearance/theme-switch` + 系统 View 菜单）；P2 已确认。四元素齐；`T-SCN-0011-01..04` 为 3 正 1 反可执行 ID。实现与验证完成后由收尾节点转 `verified`；本轮实现节点只建议翻转，不自行改状态。

**已实现与验证（2026-11-16，T-1116-02/04/05）**：`ThemePreference`/`ThemePreferenceStore` 已落地；`UumailApp` 持 `@State theme` + `preferredColorScheme` + `.commands`，`ThemeCommands` 为系统 View「主题」三项 Picker。`ThemePreferenceStoreTests` 5 例通过；`ThemeProbe` 逐条通过 `T-SCN-0011-01`（默认勾跟随系统）、`T-SCN-0011-02`（深/浅即时切换、窗口与 sheet 同步、持久化）、`T-SCN-0011-03`（跟随系统、强制值忽略系统、重复选择不二次变更）、`T-SCN-0011-04`（损坏值回退、窗口不重建、正文不重载、选中不丢）。证据：`task-spaces/20261116-154416/evidence/ThemeProbe.txt`、`presentation-tests.txt`、`full-test.txt`、`architecture.txt`。建议收尾翻转 `SCN-0011` 为 `verified`、`REQ-0016` 为 `delivered`。
