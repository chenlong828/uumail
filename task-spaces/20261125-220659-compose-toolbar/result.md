---
layer: works
module: mail
scope: project:uumail
status: closed
updated: 2026-11-25
---

# W-M3-21 结果：撰写页顶栏（发送置顶、关闭存草稿）

## 交付

- 实现 `525e33e`（`feat(compose): title-bar send and save-draft prompt on close`）：只改 `Sources/uumail/ComposeView.swift`（174→186 行）。
  - 顶栏：左侧红色关闭（`.keyboardShortcut(.cancelAction)`、`.help("关闭（Esc）")`）、居中标题、右上唯一「发送」（`borderedProminent` + `controlSize(.large)` + `.defaultAction` + `!canSend` 禁用）。
  - 删除底部操作条与旧 `xmark`；`statusText` 非空时在顶栏下单独一行，编辑态零高度。
  - 关闭：`capture` → `hasEdits`；有改动弹「存储草稿？」，`存草稿`（成功才关）/`放弃`/`继续编辑`（默认 Esc）；发送失败/存草稿失败留在 sheet 并由状态行显示原因。
- 证据：`probe/`（`run.sh` + `ComposeToolbarProbe.swift` + `compose-900.png`/`compose-480.png`/`compose-225-480.png` + 同名 `.txt` 日志）。探针编译生产 `ComposeView.swift` 与依赖，托管 `NSWindow` 后用 `screencapture -l` 取图。

## 验收

- `./Scripts/swiftw build` 通过；`./Scripts/swiftw test`：**466 tests / 77 suites** 全绿；`bash Scripts/check-architecture.sh`：**4/4 PASS**。
- L2（人工读取三张图）：900×760、480×760、225%×480 均为「左红点 + 居中标题 + 右上蓝发送」，无底栏、无第二个关闭入口；225%×480 下标题与按钮不重叠；状态行编辑态不占高度（截图中无状态行）。
- `./Scripts/make-app.sh` 成功（release）；`dist/build-info.txt` 在收口时按 HEAD 重写。
- 裁决摘要：blocker 0 / decision 0（口径已人工确认，无待决） / hold 1（真实点击红点与弹窗三按钮、浅色主题像素、VoiceOver 待发布前人工执行）。

## 结论落点

| 结论 | 落点 |
|---|---|
| 顶栏形态与关闭口径 | `doc/design/scenarios/mail/send/html-reply-compose/scenario.md`（`REQ-0041` 增量） |
| 组件实现与验证 | `doc/design/components/CMP-APP/spec.md`（`REQ-0041` 增量） |
| 需求 | `doc/requirements/REQ-0041-compose-toolbar-close-draft.md` |
| 排期与任务表 | `doc/plan/roadmap.md` §W-M3-21 |
| 导航摘要 | `doc/README.md` |

## 未覆盖 / 未决

- 真实 sheet 内点击红色关闭、弹窗三按钮的真实跳转；浅色主题与不同字号组合的像素验收；VoiceOver——均为发布前人工项。
- 红点是 sheet 内自绘控件（系统红绿灯只在独立窗口上）；若要真红绿灯/独立撰写窗口，需另立增量（改窗口载体，会影响 sheet 等宽口径）。
- 不做 Cmd+S 存草稿、发送失败横幅、发送按钮图标化。
