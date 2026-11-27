---
layer: works
module: mail
scope: project:uumail
status: active
updated: 2026-11-27
---

# W-M3-24 设计：草稿双向同步与合并

## 数据

- 本地草稿仍是 `outbox`（`state='draft'`）；v13 增 `server_id`、`draft_hash`，新表 `draft_tombstones`。
- 指纹 = 收件人/抄送（去空白）+ 主题 + `bodyHTML ?? body`，`\u{1E}` 拼接；`draft_hash` 存上次同步值。

## 算法（`SyncEngine.syncDraftsOnce`，engine gate 内）

1. 拉：按 `Folder.isDrafts` 找文件夹，用 `fetchMessages` 取 delta，逐条 `fetchBody`；按指纹判：
   - 本地未改、服务器改 → 采用服务器（`adoptServerDraft`）；
   - 本地改、服务器未改 → 留待推（`draftsNeedingUpload`）；
   - 两边都改 → 先 `duplicateDraft`（本地版复制成未绑定行），再 `adoptServerDraft`（原行收服务器版）；
   - 本地无绑定 → `insertServerDraft`；
   - 服务器删：本地未改 → 删行；本地改 → 解绑保留，下轮上传。
2. 推：未绑定 → `createDraft`（ClientId = 行 id）→ `bindDraft`；已绑定且指纹不同 → `updateDraft` → `setDraftHash`；tombstone → `deleteDraft` → 清墓碑；每次写回包更新草稿集合 SyncKey。
3. 发送/删除已绑定草稿：`sendDraft`/`deleteDraft` 在同一事务写 tombstone。

## 触发与失败

- 触发：进入草稿箱、存草稿、删除、发送后；`SyncScene.syncDrafts()` 单飞。
- 失败：返回 `MailError`，本地草稿不改；下轮重试；离线不阻塞编辑。

## 协议

- `EASClient.createDraft/updateDraft/deleteDraft`：`Sync` 的 `Add`/`Change`/`Delete`，Add 带 ClientId + ApplicationData（To/Cc/Subject/Body Type 2）；解析 `Responses.ServerId` 与 `SyncKey`。

## 定级与风险

- **P1**（新写协议路径 + schema v13 + 草稿数据所有权），口径已人工确认。
- 风险：真实网关对 Drafts 的 `Sync Add` 行为未验证；`draft_hash` 是内容拼接串（不哈希，MailDomain 无 CryptoKit）；并发靠 gate + 单飞，进程崩溃可能出现「已上传未绑定」的重复草稿（可接受，人来删）。
