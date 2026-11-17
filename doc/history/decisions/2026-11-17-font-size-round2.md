---
layer: history
module: global
scope: project:uumail
status: frozen
updated: 2026-11-17
---

# 界面与阅读字体大小：第 2 轮设计修订（2026-11-17）

## 背景

第 1 轮设计（`design.md` 第 1 轮、`doc/history/decisions/2026-11-17-font-size.md`）被设计评审 `task-spaces/20261117-071134/review.md` 判 **fail（回设计）**，理由集中在证据与覆盖：

1. 把 `HeaderFixture` 写成“生产 `MessageHeaderView`”（探针 `FontSizeMechanismProbe.swift:75/255/287`，编译命令未带生产头文件）；
2. 225% 正文视口只有 `480-220` 算术（`FontSizeMechanismProbe.txt:97`），未在完整 `MessageBodyView` 上测；
3. `EmptyState`/按钮没有 L2 样本；
4. `UumailApp` 根级数据库错误页不在覆盖清单；
5. `CMP-PRES` 的拥有数据/变化轴仍是旧版，`CMP-APP` 入口符号与行数过期。

本轮（run `20261117-071134` 第 2 轮）按这五项修正，并把“设计期能证/只能实现期证”的边界写清。**P2 定级与默认确认口径不变**：仍是无人值守默认确认（未经人工），不是发起人签字。

## 决定

1. **证据来源拆开写，不再混用“生产”**：
   - 100% 基线：编译**未修改的生产源** `Sources/uumail/MessageHeaderView.swift` / `MessageBodyView.swift` / `MessageBodyStyle.swift`；实测生产头部最坏夹具 **159.5pt**（320/680 宽）、完整 body 视口 273pt（480 高）/353pt（560 高）。
   - 225% 几何：**生产源 + 设计 diff 补丁副本**（`evidence/font-size-probe/round2/patched/`，diff 见 `patches/`）。实测头部 312.5pt、标签列 99pt、值列起点 115、标签字体 29.25pt、不重叠；完整 body 视口 259pt（480 高）。
   - **生产源 225% 复跑 = 实现期 L2**。设计卡明确写“设计期：生产未改源头 100% + 设计 diff 副本 225%；实现期：生产源应用 diff 后复跑”，不再把 fixture/补丁副本写成“生产已证”。
   - 第 1 轮的 **158.5pt 是 fixture/补丁副本的拟合值**，不是生产基线；生产基线更正为 **159.5pt**。第 1 轮的“480-220=260”不再作为视口证据。

2. **225% cap 从“只 cap 头部”改为“175%/225% cap 整个元数据区”**：
   - 第 1 轮 `ViewThatFits + maxHeight: 220` 在真实 `VStack` 里 100% 也会选中 `ScrollView` 分支，元数据变成 220pt（`round2/CapDiag.txt`）；且只 cap 头部时 225% 完整 body 视口只有 **147.5pt**（`round2/HeaderBodyProbe.txt` 的 `variantA225`），不满足 200pt 下限。
   - 本轮：**175%/225%** 把「头部 + 附件条 + banner」整体包 `ScrollView` 并 `.frame(height: 220)`；480pt 保守高下正文视口 **259.0pt**（560 高下 339pt），达到 200 下限与 260 目标。**120%/145% 不 cap**：实测视口 242.5pt / 205.0pt，145 仍 ≥200（低于 260 目标，如实记录，不用 cap 隐藏元数据来凑目标）。
   - 否决：只 cap 头部（147.5pt）、只对 225% cap（175% 自然视口 164.5pt 也低于下限；225% 只 cap 头部为 147.5pt）、所有 >100% 都 cap（120/145 会出现不必要空白）。

3. **100% 恒等：不装根 `.font`，区分两种字体修饰**：
   - `FontMetricDiag.txt` 实测两行默认文本无修饰 32.0pt；装根 `.environment(\.font, .body)`、显式 `.font(.body)`、`.font(percent100.font(for:.body))` 都变成 31.5pt。因此 100% **只装 `\.fontSizePreference`，不装 `\.font`**。
   - 原来源已有 `.font(style)` 的点用 `scaledFont`（100% 返回原语义字体）；原来源继承默认字体的点用新增 `scaledInheritedFont`（100% 不加任何修饰，>100% 才加缩放字体）。这样 100% 生产头部 159.5pt、完整 body 视口 273pt 与生产逐点相等。
   - 按钮：100% 保留字符串标题（`Button("重试")` 的 50×24 与自定义 label 的 50×24 同高，但自定义 label 在 100% 会差 1pt 布局）；>100% 用显式缩放 label（225% 80×43）。不让字符串标题按钮静默不缩放。

4. **空态/按钮/根错误页纳入覆盖，并定义子树例外**：
   - `ContentUnavailableView` 100%→225% 尺寸比 1.00；`EmptyState` 100% 保留原组件，>100% 自绘。实测 100% title 26pt/height 31、root 描述 13pt、block 59 与 `ContentUnavailableView` 逐点相等；120% title 31.2、225% 58.5；root 描述 225% 29.25；按钮 50×24 → 55×27 → 80×43。
   - **title 基值是实测 26pt，不是 `.title2` 的 17pt**：用 `.title2` 会让 120% 标题（20.4pt）小于 100%（26pt）。>100% 分支用 `26 × scale` semibold。
   - `UumailApp` 根级数据库错误页（`composition == nil`）是应用自绘文字，纳入 `EmptyState` 覆盖；100% 与原渲染逐点相等，225% 标题/描述缩放。第 1 轮把它漏在清单外，本轮修正。
   - 100%→120% 会切换 `EmptyState` 的占位子树类型（`ContentUnavailableView` → 自绘）。该子树**无用户状态**（无选中/滚动/搜索/草稿），切换是 `REQ-0020`「不重建视图树」的显式例外；不重置任何用户状态。写入 `SCN-0015` 的 `T-SCN-0015-02`/`T-SCN-0015-04` 与 `REQ-0020` 第 2 轮澄清。

5. **模块卡同步**：`CMP-PRES/spec.md` 的拥有数据增加 `appearance.fontSize` 镜像、变化轴增加字号档位、行数更新到 378/1229；`CMP-APP/spec.md` 的入口从 `FontSizeStyle.swift#FontSizeStyle` 改为实际符号（`EnvironmentValues.fontSizePreference`/`View.scaledFont`/`View.scaledInheritedFont`/`FontSizePreference.font(for:)`）、行数更新到 715。模块地图/数据所有权矩阵以卡片为准，不靠 `design.md` 补。

## 范围变更

- 无新增组件/依赖/target/schema：仍是 `CMP-PRES` 新增 public `FontSizePreference`/`FontSizePreferenceStore`，`CMP-APP` 新增 internal `FontSizeStyle`/`FontSizeCommands`/`EmptyState`。
- `FontSizeStyle` 增加一个 internal 修饰符 `scaledInheritedFont`；`EmptyState` 增加 `descriptionStyle`/`actionTitle`/`action`/`isSelectable` 参数，用来保持 100% 原渲染。
- 回退方式与第 1 轮相同：删除新增文件与调用点，回退 `UumailApp`/视图改动；`appearance.fontSize` key 可保留（无害），无数据迁移。

## 代价 / 影响

- 175/225% 元数据区 cap 220：超出部分内部滚动，附件/重试入口需滚动才可见（仍可达）；换来 259pt 正文视口。145% 不 cap，视口 205pt 只满足下限、不满足 260 目标；这是**如实保留的取舍**，不用隐藏元数据去凑目标。
- 100% 不装根 `.font`：默认文本/TextField/Form 在 100% 走系统默认；>100% 才装缩放字体。收益是 100% 行高 32.0pt 不被压到 31.5pt；代价是代码里多一个 `scaledInheritedFont` 分支，新增文本要判断原来源有没有显式 `.font`。
- 225% 空态标题 58.5pt、图标 117pt，占位页更大；在 480pt 高下仍可完整显示（root 页 block 231pt + 图标/间距约 140pt，未超）。
- 生产头部 100% 实测 159.5pt（不是 158.5）；R27/`SCN-0012` 的既有数值断言不改，仍以 96/107/127 那组生产夹具为准；159.5 是字号设计自己的最坏合成夹具，用于 225% 预算，不冒充 `SCN-0012` 的基线。

## 未采纳

| 方案 | 理由 |
|---|---|
| 继续用第 1 轮的 `HeaderFixture` 当“生产头部” | 评审已证伪；fixture 不是生产源 |
| 继续用 `ViewThatFits` 只 cap 头部 | 真实栈里 100% 也 cap；225% 视口 147.5pt |
| 只对 225% cap | 175% 自然视口 164.5pt 也低于 200 |
| 所有 >100% 都 cap 220 | 120/145 会出现不必要空白；145 本已 ≥200 |
| 用 `.title2` 缩放空态标题 | 17pt 基会让 120% 标题 20.4pt < 100% 的 26pt |
| 把根级数据库错误页列为“系统故障页”排除 | 它是应用自绘 `ContentUnavailableView`，225% 不缩放；纳入 `EmptyState` 成本低，覆盖更完整 |
| 100% 也装根 `.font` | 默认两行文本 32.0→31.5pt，破坏恒等 |
| 字符串标题按钮 + `.font` 修饰 | 字符串标题不响应环境字体；225% 仍 50×24 |
| 用自定义 label 覆盖所有档位 | 100% 布局差 1pt；按 100%/ >100% 分支 |

## 未决（交评审）

- OQ1 `EmptyState` >100% 是否需与系统组件逐像素一致？默认不要求（100% 已逐点相等）。
- OQ2 cap 档位是否下探到 145%（145 视口 205，低于 260 目标）？默认只 175/225，不隐藏 145 的元数据。
- OQ3 225% 状态栏文案尾部截断是否可接受？默认可接受，计数保可见。
- OQ4 系统工具栏/搜索框/标题栏不缩放是否确认？默认按系统能力边界登记。
- OQ5 覆盖审计用实现期探针脚本 vs 长期架构门？本批用探针，不改 4 门。
- OQ6 合法整数偏好（int 175）是否接受？默认接受（语义等价）。

## 落点

- 场景：`doc/design/scenarios/settings/appearance/font-size/scenario.md`（`SCN-0015`，`designed`，第 2 轮修订）。
- 规格：`doc/design/components/CMP-PRES/spec.md`、`doc/design/components/CMP-APP/spec.md`（第 2 轮修订）。
- 设计说明：`task-spaces/20261117-071134/design.md`（第 2 轮）。
- 证据：`task-spaces/20261117-071134/evidence/font-size-probe/round2/`（含补丁、命令、原始输出、诊断）。
- 需求澄清：`doc/requirements/REQ-0020-font-size-setting.md` 第 2 轮澄清。
- 排期：本节点不建 roadmap 任务，交 task-split；实现/验证后由评审/收尾翻转 `SCN-0015 verified` 与 `REQ-0020 delivered`。
