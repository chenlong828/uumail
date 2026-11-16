---
layer: history
module: global
status: frozen
updated: 2026-11-16
---

# 外观主题：菜单入口、白底范围与 P2 批次确认（2026-11-16）

## 背景

`REQ-0015`（深色阅读白底）与 `REQ-0016`（菜单主题切换）在 2026-11-16 完成需求分析与设计提案。设计按推荐路径 A 收敛为：只动 `CMP-APP` 与 `CMP-PRES`；正文画布「强制浅色 `WKWebView` 外观 + 不透明白底 + CSS 兜底」；偏好归 `CMP-PRES` 新增 public `ThemePreference`/`ThemePreferenceStore`；菜单落系统 View（中文「显示」）>「主题」；测试载体为 `PresentationTests` + 独立 `AppearanceProbe`/`ThemeProbe`，不新增 target。

按 `arch-design-spec`，本批为 **P2**（实质性跨文件/跨组件、新增兼容性 public 契约、非核心 UI 偏好）。P2 需人最终确认后方可合并；Q5（文档树归属与菜单入口）与 Q6（白底范围）是独立结构/范围决策，设计文档明确「默认 A 不是确认」。2026-11-16 的实现准出评审因此判 fail，回退到设计收口门 `T-1116-01`。

## 确认来源与范围

- 本记录由 W-M3-04 实现批次（run `20261116-154416`）在代码评审回退重跑时归档。
- 确认来自任务发起人在本次 agent-flow 回退重跑中给出的执行指令：回设计收口/人工确认阶段，先确认 Q5/Q6/P2，落 `SCN-0010`/`SCN-0011` 为 `designed`，再执行 `T-1116-02`…`T-1116-06`。
- 发起人**未逐项指定** Q5/Q6 的 A/B；按 `task-spaces/20261116-154416/brief.md` §6 与 `design.md` §6.1 的唯一推荐路径执行：**Q5 A + Q6 A + P2 确认**（含 D1 KVC 口径、D2 采样夹具、D4 公开面收窄）。原始确认没有独立 IM/邮件原文；**本记录是唯一书面落点**，不把编排指令伪造成第三方签字。
- 若发起人后续改选 Q5 B、Q6 B 或否决任一 P2 子项：按 `doc/plan/roadmap.md` §W-M3-04「条件与回退」重开设计，`T-1116-01` 重新出卡，不复用 `T-1116-02`…`T-1116-06` 的任务号与出口。

## 决定

1. **Q5 = A**：主题切换的场景树归属 `settings/appearance/theme-switch`（`flow: settings/appearance`），`SCN-0011` ID 不变；菜单落 macOS 系统 View 菜单（中文「显示」）下的「主题」子菜单，三项「跟随系统/浅色/深色」，不新增设置窗口或工具栏入口。
2. **Q6 = A**：深色阅读白底只限正文画布（`MessageWebView`）；附件条、远程图片开关、截断提示、侧栏、列表、工具栏随应用主题，不强制白。
3. **P2 确认**：
   - 白底机制 A：浅色 `WKWebView` 外观（`NSAppearance(named: .aqua)`）+ `underPageBackgroundColor = .white` + 沿用现有 KVC `drawsBackground=true` + `baseCSS` 白底；作者显式背景/文字色/表格/图片保留；作者 `prefers-color-scheme: dark` 媒体变体按浅色求值、不生效。
   - 应用机制 A：SwiftUI `preferredColorScheme`，不引入 `NSApp.appearance`/`NSWindow.appearance` 作为第二真源。
   - 偏好归属 B：`CMP-PRES` 新增 public `ThemePreference`/`ThemePreferenceStore`；按 D4 收窄为 `public init()` + internal `init(defaults:)`，`UserDefaults` 与 key 不进入公开面。
   - 菜单 A：系统 View 菜单「主题」子菜单；`ThemePreference → ColorScheme?` 映射留在 app target。
   - 测试载体 B′：`PresentationTests` 新增 `ThemePreferenceStoreTests`；像素/外观用独立 `AppearanceProbe`（直接编译生产 `MessageBodyStyle.swift`）与 `ThemeProbe`；不新增 `uumail` 测试 target。勾选断言先打开父级 View 菜单再读 `NSMenuItem.state`（R26）。
   - `MessageBodyStyle` 抽文件：`CMP-APP` 内部文件，无 public 契约；CSP 两档策略与注入顺序不变。
4. **边界**：不新增依赖/target/schema；不改 `MailDomain`/`MailStore`/`Scenes` 契约；不改 T5（禁 JS、默认阻止远程资源）；不改附件、已读、同步、发送。正文画布外观是常量，不随主题反向变化；主题偏好只写本地 `UserDefaults["appearance.theme"]`，不写业务库/Keychain/网络。

## 代价 / 影响

- `Presentation` 新增一个 public 三态枚举与一个本地偏好 store；公开面不含框架/存储类型，属 additive、兼容性变更。
- 正文画布固定浅色，只提供暗色媒体变体的邮件会显示其浅色/默认样式；这是「白底兜底」的直接代价，已由 P2 一并认可。
- 单窗口现状下所有窗口共享同一 `@State`；按窗口配置不在本批。
- 回滚 = 回退代码 + 保留无害的 `UserDefaults` key；无 schema/数据迁移。
- `UserDefaults.set` 无同步失败信号，写失败无法强制注入；设计以「`save` 不抛/不回滚 + 会话状态独立」保证，测试覆盖缺失/损坏/持久化/幂等，不伪造失败注入（R25）。

## 未采纳

| 方案 | 理由 |
|---|---|
| Q5 B：应用菜单「uumail > 外观」+ `app/preferences` | 可行但改需求入口描述，无用户收益；若选 B 还须补 `ThemeCommands` 应用菜单落点设计与 P2 清单参数化 |
| Q6 B：整个阅读右栏白 | 与深色 chrome 割裂，且须先改 `REQ-0015`/`SCN-0010` 范围 |
| 只 CSS 白底 / 只 `drawsBackground=true` | 前者压不住作者 dark-media，后者仍按深色求值；探针见 `task-spaces/20261116-145040/evidence/reading-pane-probe.txt` |
| `NSApp.appearance`/`NSWindow.appearance` | 第二外观真源，要手动 apply/reset；真实 SwiftUI 探针已证 `preferredColorScheme` 覆盖窗口与 sheet |
| 新增 `AppTests`/`AppearanceTests` target | 结构变更、编译/维护成本高；B′ 已可执行 |
| 存储协议/工厂/单例 | 只有一个 `UserDefaults` 实现，为想象的第二实现预付抽象 |

## 落点

- 场景：`doc/design/scenarios/mail/read/dark-reading-pane/scenario.md`（`SCN-0010`）、`doc/design/scenarios/settings/appearance/theme-switch/scenario.md`（`SCN-0011`）。
- 规格：`doc/design/components/CMP-APP/spec.md`、`doc/design/components/CMP-PRES/spec.md`（设计增量改为确认/实现记录）。
- 排期：`doc/plan/roadmap.md` §W-M3-04；待拍板：`doc/plan/open-questions.md` Q5/Q6 移入本记录。
- 实现：`Sources/Presentation/ThemePreference.swift`、`Sources/uumail/{ThemeCommands,MessageBodyStyle}.swift`、`Sources/uumail/{UumailApp,MessageBodyView}.swift`；测试 `Tests/PresentationTests/ThemePreferenceStoreTests.swift`。
- 证据：`task-spaces/20261116-154416/evidence/`（脱敏后的命令输出、探针原始值）。
