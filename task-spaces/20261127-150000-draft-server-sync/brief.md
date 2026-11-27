---
layer: works
module: mail
scope: project:uumail
status: active
updated: 2026-11-27
---

# W-M3-24 草稿与服务器 Drafts 双向合并同步

## 背景

用户要求补充草稿箱与服务器 Drafts 文件夹的同步，策略为合并：远程与本地冲突时两份都保留，交给人删除。确认口径：双向同步（不只拉取）；冲突时原行收服务器版本，本地改动另存一份并上传成服务器第二份。

## 范围

- 协议：EAS 16.1 `Sync` 在 Drafts 文件夹 `Add`/`Change`/`Delete`（MS-ASEMAIL §4.4）。
- 数据：schema v13（`outbox.server_id`/`draft_hash`、`draft_tombstones`）；`DraftRecord` 绑定字段与内容指纹。
- 同步：`SyncEngine.syncDraftsOnce()` 先拉后推、指纹判改动、冲突两份、tombstone 补删；`SyncScene.syncDrafts()` 单飞。
- 界面：进入草稿箱/存草稿/删除/发送触发同步；草稿行右键与 Delete 删除（已绑定草稿同步删服务器）。
- 不改：发送入队/Outbox 状态机、Message 同步、收件箱/发件箱、搜索、附件。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| `T-1127-07` | design | CMP-EAS / CMP-SYNC | 完成 | 协议与合并算法（拉-合并-推、指纹、tombstone、单飞） |
| `T-1127-08` | change | CMP-DOMAIN / CMP-OUTBOX-STORE / CMP-SYNC-CONTRACT | 完成 | schema v13、绑定字段/指纹、草稿写与存储端口 |
| `T-1127-09` | change | CMP-EAS / CMP-EASADAPTER / CMP-SYNC | 完成 | Sync 草稿命令、适配、`syncDraftsOnce` |
| `T-1127-10` | change | CMP-SCN-COMPOSE / CMP-PRES / CMP-APP | 完成 | 删除/发送 tombstone、刷新触发、右键/Delete |
| `T-1127-11` | verify | — | 完成 | 484 tests / 83 suites、架构 4/4、新 8 例 |
| `T-1127-12` | doc | — | 完成 | REQ-0044、SCN-0031 增量、八组件增量、roadmap、README |
| `T-1127-13` | release | — | 完成 | `make-app.sh`、`dist/build-info.txt` |

## 验收标准

1. 进入草稿箱：本地列表立即显示，后台完成一轮合并后刷新；无服务器 Drafts 文件夹时不报错。
2. 服务器新增/修改的草稿被拉成本地行并绑定 ServerId；本地未改时采用服务器版本。
3. 本地新草稿上传后绑定 ServerId；本地改过的已绑定草稿推成服务器修改。
4. 两边都改过：本地出现两份（原行=服务器版、另一行=本地版），本地版上传成服务器第二份，`conflicts` 计数。
5. 删除/发送已绑定草稿：本地行消失且落 tombstone，下一轮同步删服务器副本；离线时保留 tombstone 待补。
6. 同步失败不阻塞本地读写；单飞保证同一草稿不会重复上传。

## 未决

- 真机（真实 Exchange）草稿 Add/Change/Delete 未验证；需要用户授权后才会在服务器 Drafts 写入测试草稿。
- 草稿附件、Bcc、草稿已读状态不做。
