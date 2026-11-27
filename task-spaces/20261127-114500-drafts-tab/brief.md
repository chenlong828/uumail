---
layer: works
module: mail
scope: project:uumail
status: active
updated: 2026-11-27
---

# W-M3-23 草稿箱 tab 与就地继续编辑

## 背景

用户要求（2026-11-26）：在「收件箱 / 发件箱 / 日历」旁增加「草稿箱」tab；内容显示草稿邮件，点击左侧草稿直接在右侧进入继续编辑状态。确认口径：仅本机草稿（不同步服务器 Drafts）；在右侧点「存草稿」后留在编辑器继续写。

## 范围

- 改：`MailDomain`（`DraftRecord`）、`CMP-OUTBOX-STORE`（drafts/updateDraft/sendDraft）、`CMP-SCN-COMPOSE`（drafts/saveDraft(draftID:)/send(draftID:)）、`CMP-PRES`（ComposeViewModel 草稿模式与 draftID、MailboxViewModel drafts/loadDrafts/compose(draft:)）、`CMP-APP`（四段切换、草稿列表、就地编辑器、`ComposeView.isEmbedded`/⌘S）。
- 不改：服务器 Drafts 同步（未做）、删除草稿、撰写 sheet 形态、格式栏/编辑器/收件人联想、发送入队与 Outbox 状态机、schema/target/依赖。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| `T-1127-01` | design | CMP-APP 等 | 完成 | 数据流与交互口径 |
| `T-1127-02` | change | CMP-DOMAIN / CMP-OUTBOX-STORE / CMP-SCN-COMPOSE | 完成 | `DraftRecord` 与三条 store/scene 方法 |
| `T-1127-03` | change | CMP-PRES / CMP-APP | 完成 | 视图模型 + 四段切换 + 列表 + 就地编辑器 + ⌘S |
| `T-1127-04` | verify | — | 完成 | 475 tests / 80 suites、架构 4/4、L2 截图 |
| `T-1127-05` | doc | — | 完成 | REQ-0043、SCN-0031、五组件增量、roadmap、README |
| `T-1127-06` | release | — | 完成 | `make-app.sh`、`dist/build-info.txt` |

## 验收标准

1. 顶部四段：收件箱 / 发件箱 / 草稿箱 / 日历；草稿箱在发件箱与日历之间。
2. 草稿列表按更新时间倒序，显示主题、收件人、时间；空主题/无收件人有兜底文案；无草稿有空态。
3. 单击草稿 → 右侧就地编辑（草稿标题、回填表单、存草稿、发送）。
4. 存草稿覆盖同一行、留在编辑器、列表刷新；发送把该行转 queued 并移出列表；离开 tab/切草稿自动保存。
5. 行被删、空收件人、存储失败均有明确失败路径，不静默丢内容。
6. 全量测试与架构门全绿。

## 未决

- 服务器 Drafts 同步、删除草稿、草稿搜索未做。
- 真实点击/⌘S/深色像素/VoiceOver 为发布前人工项。
