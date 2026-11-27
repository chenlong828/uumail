---
layer: works
module: mail
scope: project:uumail
status: active
updated: 2026-11-27
---

# W-M3-23 设计：草稿箱 = outbox 的 draft 行 + 就地编辑器

## 数据流

- 草稿唯一权威仍是 `outbox` 表（`state = 'draft'`，`is_draft = 1`），不新增表/列。
- 新增 `DraftRecord`（含 body/bodyHTML 以便回填编辑器）与 `OutboxStore.drafts/updateDraft/sendDraft`：
  - `drafts`：`state='draft' ORDER BY updated_at DESC, id DESC`；
  - `updateDraft`：同行 UPDATE（刷新 updated_at），行缺失返回 false；
  - `sendDraft`：同行 UPDATE 成 `state='queued', is_draft=0`（同一 id = 同一 ClientId），草稿不可能既投递又留在草稿箱。
- `ComposeScene.saveDraft/send` 增加可选 `draftID`：有则走同行更新/转队，行缺失回退插入/入队；既有调用签名兼容。

## 交互

- `MailboxSection` 加 `.drafts`；四段 Picker 在 `.navigation` 位（宽度 260→320）。
- 左列 `DraftListView`（List selection + 行 id）：单击 → `openDraft` → `ComposeViewModel(mode: .draft, draftID:)`。
- 右侧 `ComposeView(isEmbedded: true)`：`frame(nil)` 填满详情列；顶部多「存草稿」（⌘S）；保存成功不关闭，`onDraftSaved` 刷新列表；sheet 形态不变。
- 离开草稿箱/切换草稿：`leaveDraftEditor()` 先自动保存（失败则保留编辑器，不切走），再切换。
- 关闭编辑器仍复用「存储草稿？/放弃/继续编辑」确认；发送成功由 `onClose` 清空并刷新。

## 走查

1. 正常：切草稿箱 → 选中 → 改 → ⌘S（同行更新、状态「草稿已保存」）→ 发送（转 queued、移出列表）。
2. 失败：空收件人发送 → 错误留在编辑器；行被删 → 保存回退插入、发送回退入队；存储失败 → 编辑器保留。
3. 切换：草稿编辑中切 tab/选另一封 → 自动保存；保存失败则不切走。
4. 空态：无草稿「没有草稿」；有草稿未选中「选择一封草稿」。

## 定级与风险

- **P3**：新增视图/表单分支与三条 store/scene 方法，无 schema/依赖/target/public 破坏性契约变化。
- 风险：草稿列表只覆盖本机草稿（服务器 Drafts 不可见）——已作为非目标登记；`MailboxView` 300 行预算通过拆分 `MailboxView+Toolbar`/`+Drafts` 守住。
