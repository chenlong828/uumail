---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-24
---

# W-M3-18 结果：四条界面反馈修复

## 结论

4 条可实施反馈全部落地并验证；第 2 条「其他文件夹没有邮件」核实为同步范围限制，不是界面缺陷，登记为开放问题。改动全部在 UI/投影层，schema、target、依赖、同步与存储未动。

## 反馈 → 落点

| 反馈 | 处理 | 证据 |
|---|---|---|
| 1. 邮件列表默认太窄 | 列表列 `min 320/ideal 480`（原 280/380）；侧栏、阅读区与切换行为不变 | `probe/column-width.txt`：1440=220/480/731，1000=220/480/291，900=220/480/191，760=220/480/51 |
| 2. 其他文件夹没有邮件 | **不改**：`SyncEngine` 只同步收件箱；本地库 `messages` 只有 folder 13 的 125 封，`sync_state` 只有 `folders` 与 `13` | 只读查询（见 `design.md` §1）；`plan/open-questions.md` |
| 3. 双击打不开浮窗 | 行上改用 AppKit `ClickCatcher`（`MessageRowClick`，单击立即选中、双击打开）；删除 `.onTapGesture(count:2)`；点击选中不再自动滚动居中（避免第二击落空） | `probe/message-row-click.txt`：1→仅选中、1,2→选中+打开、2→仅打开、`window.sendEvent` hitTest 命中 |
| 4. 浮窗位置太偏 | 默认相对主窗口居中并夹在屏幕可用区；新 autosave 名 `uumail.reader.centered`；用户拖动后记住位置 | L1 `ReaderRouter.centeredOrigin` 3 组断言；`probe` 之外的 AppKit 机制沿用 T-1124-20 |
| 5. 周视图 8:00–24:00 每小时虚线 | `CalendarProjection.week` 固定 8/24；`CalendarHourGrid` 每列 17 条灰色虚线 | L1 测试期望 8/24；`probe/hour-grid.png` 预览截图 |

## 验收

- `./Scripts/swiftw test`：**461 tests / 77 suites 全绿**（含 `ReaderRouter` 居中 3 组、日历投影固定 8/24）。
- `bash Scripts/check-architecture.sh`：**4/4 PASS**。
- `./Scripts/make-app.sh`：成功，`dist/build-info.txt` 记录 `commit 9cc90d1`、`2026-11-24 23:33:06 CST`、release。
- L2 探针：`probe/run.sh` 可复跑；输出已提交。
- 文件预算：`MailboxView.swift` 299/300；`CalendarView.swift` 293/300；`CalendarHourGrid.swift` 20；`MessageRowClick.swift` 21。

## 残余（发布前人工项）

- 真实鼠标双击（含长列表滚动位置）与拖动浮窗后重启沿用位置。
- 深色主题下周视图与会议块的整窗像素级视觉验收（预览截图已按深色主题核对 17 条虚线）。
- 8:00 前/24:00 后的会议块会被固定时间窗裁掉（用户已确认固定 8–24 的口径）。
- 其他文件夹按需同步未立项。

## 结论落点

- 需求：`REQ-0034`/`REQ-0035`/`REQ-0036` `delivered`；`REQ-0031` 追加双击修复记录。
- 场景：`SCN-0027` 新建 `verified`；`SCN-0025`/`SCN-0024` 增量后 `verified`。
- 组件：`CMP-APP`/`CMP-PRES` 设计增量与实现记录。
- 计划：`plan/roadmap.md` W-M3-18；`plan/open-questions.md` 文件夹同步。
