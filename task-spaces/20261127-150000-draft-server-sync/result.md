---
layer: works
module: mail
scope: project:uumail
status: closed
updated: 2026-11-27
---

# W-M3-24 结果：草稿与服务器 Drafts 双向合并同步

## 交付

- `78ed6cb` `feat(drafts): merge local drafts with the server Drafts folder (REQ-0044)`
- `37350c2` `fix(drafts): re-bootstrap the Drafts SyncKey after every write`（真实网关冒烟发现）
  - schema v13：`outbox.server_id`、`outbox.draft_hash`、`draft_tombstones`；`DraftRecord` 绑定字段与 `fingerprint`；`Folder.isDrafts`。
  - 草稿存储拆分为 `OutboxStore+Drafts.swift` / `OutboxStore+DraftSync.swift` 与 `DraftSyncStoreConformance.swift`。
  - 协议：`MailWriteGateway` 的 `createDraft/updateDraft/deleteDraft`（`DraftPayload`/`DraftWriteResult`），`EASClient` 的 Sync Add/Change/Delete，`EASAdapter` 映射。
  - 同步：`SyncEngine.syncDraftsOnce()`（拉-指纹合并-推；冲突两份都留；tombstone 补删；只写草稿集合 SyncKey）；`SyncScene.syncDrafts()` 单飞。
  - 界面：`MailboxViewModel.refreshDrafts/deleteDraft`；进入草稿箱/存草稿/删除/发送触发；草稿行右键与 Delete 删除。
- 未改发送入队/Outbox 状态机、Message 同步、收件箱/发件箱、搜索、附件。

## 验收

- 真实网关冒烟（2026-11-27，用户授权，临时库，未动真实本地库）**PASS**：
  1. 临时 `MailStore` 保存一条本地草稿 → `syncDraftsOnce()` 上传（`uploaded=1`）并绑定 ServerId；
  2. `fetchBody` 从服务器 Drafts 文件夹读到草稿正文（服务器确实有这封草稿）；
  3. 本地删除（tombstone）→ 下一轮同步 `deleted=1`、墓碑清空；
  4. `fetchBody` 失败 → 服务器副本已消失。
  证据：`task-spaces/20261127-152500-draft-smoke/probe/smoke3.txt`；另 `keyprobe.txt` 记录网关行为：写响应返回的 SyncKey 会被下一次 Sync 拒绝（status 3/4），已改为写后 `SyncKey=0` 重新引导。
- `./Scripts/swiftw test`：**485 tests / 83 suites** 全绿（新增 8 例：`EASDraftWriteTests` 3、`DraftSyncTests` 5；另有 `DraftBindingTests` 1 例并入 484）；`bash Scripts/check-architecture.sh`：**4/4 PASS**。
- 冲突规则按人工确认落地：原行采用服务器版本、本地版本复制成未绑定行并在同轮上传；`conflicts == 1`、两行都在。
- 发送/删除已绑定草稿：同事务 tombstone，下一轮 `Sync Delete`；离线安全。
- 裁决摘要：blocker 0 / decision 1（写响应 key 不可用 → 写后重新引导，已实现并有真机证据） / hold 1（多设备/OWA 同时改的冲突合并未人工验证；OWA 界面未目验）。

## 结论落点

| 结论 | 落点 |
|---|---|
| 同步运行序与验收 | `doc/design/scenarios/mail/send/drafts/scenario.md`（`SCN-0031` 增量，`T-SCN-0031-05`） |
| 组件实现 | `CMP-DOMAIN`/`CMP-OUTBOX-STORE`/`CMP-SYNC-CONTRACT`/`CMP-EAS`/`CMP-EASADAPTER`/`CMP-SYNC`/`CMP-SCN-COMPOSE`/`CMP-PRES`/`CMP-APP` 的 2026-11-27 增量 |
| 需求 | `doc/requirements/REQ-0044-draft-server-sync.md` |
| 排期与任务表 | `doc/plan/roadmap.md` §W-M3-24 |
| 导航摘要 | `doc/README.md` |

## 未覆盖 / 未决

- 真实网关上已验：`Sync Add`、`Sync Delete`、服务器正文可读、本地删除后服务器副本消失（临时库，授权后执行，未留测试草稿）。
- 未验：`Sync Change`（本地改已绑定草稿的增量更新）与 OWA/手机同时改的冲突合并；OWA 界面未人工目验（服务器存在性用 EAS `fetchBody` 证明）。
- 草稿附件/Bcc/已读状态不做；进程崩溃可能出现「已上传未绑定」的重复草稿（合并策略允许人来删）。
- `draft_hash` 为内容拼接串（`MailDomain` 无 CryptoKit 白名单），足够判等但占用 TEXT；如后续要摘要可迁到 store 侧计算。
