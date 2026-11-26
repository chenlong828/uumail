---
layer: works
module: mail
scope: project:uumail
status: active
updated: 2026-11-26
---

# W-M3-22 主窗口顶栏：三段在左、动作在右、不折叠、有提示

## 背景

用户反馈（2026-11-26，附 1512pt 主窗口截图）：

- 「任务工具栏也不太合适，应该收件箱/发件箱/日历在左上，然后右上积累这回复等这一块工具栏」；
- 「空间很充足，但是最右侧的工具栏图标（是否显示远程图片等）还折叠了」；
- 「这一批图标也没有指示标签」。

确认口径：三段切换保持在左上；七个邮件动作移到右上并贴住搜索框；空间充足时不折叠；图标要有悬停提示（tooltip），不做常驻文字标签。

## 范围

- 改：`Sources/uumail/MailboxView.swift`（动作组迁到窗口级 `.toolbar`）、`Sources/uumail/ToolbarTooltips.swift`（贴右 + tooltip 安装）。
- 测试夹具：`Tests/MailStoreTests/PerformanceTests.swift` 的 30 天窗口数据改为相对时间（原固定 10 月日期已落出窗口，属时间炸弹，与本次功能无关但阻塞验收）。
- 不改：动作集合/禁用规则/刷新分派、搜索绑定、三段切换与日历页、浮窗工具栏、schema/依赖/target。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| `T-1126-01` | design | CMP-APP | 完成 | 现状归因（列挂载 → leading 组）与方案探针 |
| `T-1126-02` | change | CMP-APP | 完成 | `mailboxToolbar` 上提、`pinActionGroupToTrailingEdge`、tooltip 安装 |
| `T-1126-03` | verify | — | 完成 | 466 tests / 77 suites、架构 4/4、L2 1512/900 + 稳定性、夹具修正 |
| `T-1126-04` | doc | — | 完成 | `REQ-0042`、`SCN-0028` 增量、`CMP-APP`、roadmap、README |
| `T-1126-05` | release | — | 完成 | `make-app.sh`、`dist/build-info.txt` |

## 验收标准

1. 1512pt 窗口：三段切换在左，七个动作在右并紧贴搜索框，全部可见、无「»」溢出。
2. 悬停任一动作显示中文 tooltip。
3. 900pt 最小宽允许溢出，溢出项可从菜单触发；状态变化后分组与 tooltip 不丢。
4. 动作语义、禁用规则、刷新分派、搜索、三段切换、日历页与浮窗均不退化。
5. 全量测试与架构门全绿。

## 未决

- macOS 14/15 上 flexible space 的贴右效果未验证（本机 26.6）。
- 图标常驻文字标签不做；如需要另立增量。
