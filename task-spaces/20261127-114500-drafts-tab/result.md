---
layer: works
module: mail
scope: project:uumail
status: closed
updated: 2026-11-27
---

# W-M3-23 结果：草稿箱 tab 与就地继续编辑

## 交付

- `c0cc496` `feat(drafts): local drafts tab with in-place continue editing (REQ-0043)`
  - 数据：`MailDomain.DraftRecord`；`OutboxStore.drafts/updateDraft/sendDraft`；`ComposeScene.drafts/saveDraft(draftID:)/send(draftID:)`。
  - 视图模型：`ComposeViewModel.mode.draft/draftID`；`MailboxViewModel.drafts/loadDrafts/compose(draft:)`。
  - 界面：`MailboxSection.drafts`、四段 Picker（宽度 320）、`DraftListView`、`MailboxView+Drafts`（列表/就地编辑器/离开自动保存/关闭）、`MailboxView+Toolbar`（拆出后 `MailboxView` 274 行）、`ComposeView.isEmbedded`/`存草稿`⌘S/`onDraftSaved`。
- 不新增 schema/target/依赖；草稿仍是 `outbox` 的 `state='draft'` 行，发送为同行转 `queued`（同一 `ClientId`）。

## 验收

- `./Scripts/swiftw test`：**475 tests / 80 suites** 全绿（新增 9 例：`OutboxDraftTests` 3、`ComposeSceneDraftTests` 3、`DraftListTests` 3）；`bash Scripts/check-architecture.sh`：**4/4 PASS**。
- L2（`probe/`）：`draft-list.png`（三行草稿：主题/收件人/时间 + 「选择一封草稿」空态）、`embedded-compose.png`（就地编辑器：红色关闭、草稿标题、存草稿、发送、回填收件人/主题/正文）。
- 裁决摘要：blocker 0 / decision 0（口径已人工确认） / hold 1（真实点击 tab/草稿/存草稿/发送、⌘S 焦点、深浅色像素、VoiceOver 待发布前人工）。

## 结论落点

| 结论 | 落点 |
|---|---|
| 草稿箱运行序与验收 | `doc/design/scenarios/mail/send/drafts/scenario.md`（`SCN-0031`） |
| 组件实现 | `CMP-DOMAIN`/`CMP-OUTBOX-STORE`/`CMP-SCN-COMPOSE`/`CMP-PRES`/`CMP-APP` 的 2026-11-27 增量 |
| 需求 | `doc/requirements/REQ-0043-drafts-tab.md` |
| 排期与任务表 | `doc/plan/roadmap.md` §W-M3-23 |
| 导航摘要 | `doc/README.md` |

## 未覆盖 / 未决

- 服务器 Drafts 文件夹同步、删除草稿、搜索/批量、草稿附件均未做（登记为非目标）。
- 真实窗口点击四段切换/草稿行、⌘S 焦点与输入法、浅色/深色像素、VoiceOver 为发布前人工项。
- 草稿编辑中若自动保存失败会保留编辑器但不切走；用户返回该 tab 后可继续重试（未做单独提示条）。
