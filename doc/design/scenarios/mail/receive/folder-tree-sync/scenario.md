---
layer: design
module: mail
status: designed
updated: 2026-11-14
flow: mail/receive
scenario: SCN-0002
---

# SCN-0002 文件夹树同步

**结果**：用户打开侧边栏时看到的文件夹树与服务器一致；服务器侧增删改文件夹后，本地在下次同步时跟随变化，不出现重复或幽灵文件夹。

## 入口

- `CMP-SCN-SYNC#refresh`、`#startAutoRefresh`（`design/components/CMP-SCN-SYNC/spec.md`）
- `CMP-SYNC#syncOnce`（`design/components/CMP-SYNC/spec.md`）
- `CMP-DOMAIN#MailGateway.fetchFolders`（经 `CMP-EASADAPTER`）
- `CMP-STORE#applyFolderSnapshot`（`MailStore` 直接遵循 `CMP-DOMAIN#SyncStore`）

## 运行序

流程 `F-RECEIVE-01`：

1. `SyncScene` 触发一次 `SyncEngine.syncOnce()`；引擎进入 `syncingFolders`。
2. `fetchFolders(syncKey: "0")` 取全量树（增量 key 只用于监测变化，不用来增量合并）。
3. 计算与本地快照的差集（新增、改名/改父、删除）。
4. `applyFolderSnapshot` 单事务写入并推进文件夹同步 key。
5. 侧边栏按 `type` 排序渲染：收件箱、草稿、已发送、已删除在前，其余按服务器顺序。

失败路径：

- 网络或网关失败 → 保留本地旧树，`RefreshOutcome.error` 进状态栏；不阻塞阅读；
- 认证/设备/策略错误 → 转对应 `MailError`，`SyncScene` 暂停自动刷新；
- 服务器返回空树 → 视为异常而非「用户没文件夹」，保留旧树（**实现未单独识别空树**）。

## 不可变引用

- `MailStore.applyFolderSnapshot` 的删除语义（服务器没有的文件夹本地软删除，不级联删信）。
- 文件夹 `type` 取值以 EAS 规范为准（`2` = 收件箱）。
- 分页与 key 推进由 `SyncEngine` 负责，场景只决定何时刷新。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0002-01` | 正 | 首次同步 → 收件箱等系统文件夹齐全，key 落库 |
| `T-SCN-0002-02` | 正 | 服务器新增一个子文件夹 → 下次同步本地出现且父级正确 |
| `T-SCN-0002-03` | 正 | 服务器删除某文件夹 → 本地软删除，其下邮件不丢 |
| `T-SCN-0002-04` | 反 | 同步中途失败 → 本地树保持旧快照且标 `stale`，不出现半棵树 |

## 状态

`designed`（2026-11-14 核对）。运行序、引用、测试方案与入口已按实现更新；实现与验证如下。

实现：`SyncEngine.refreshFolders` 每次按 `SyncKey=0` 取全量树（`1f0c0b3` 之前已有），`MailStore.applyFolderSnapshot` 单事务落库；真机落 21 个文件夹（`history/works/2026-11-09-m1-account-access/result.md`）。**无 `stale` 标记**，失败时保留旧树但没有「上次同步时间」状态。

| 测试项 | 现状 |
|---|---|
| `T-SCN-0002-01` | 通过（组件级）：`MailStoreTests`「applyFolderSnapshot stores folders in mailbox order and advances the key」；`ScenesTests` 单飞用例断言一次 folder 调用 |
| `T-SCN-0002-02` | 未覆盖：每次全量重取树，没有「服务器新增子文件夹」的增量断言 |
| `T-SCN-0002-03` | 部分：`MailStoreTests`「removed folders disappear from reads but survive as soft deletes」；「其下邮件不丢」未单独断言 |
| `T-SCN-0002-04` | 部分：`MailStoreTests`「an invalid folder rolls the whole batch back」覆盖回滚；`stale` 标记未实现 |

未转 `verified` 的原因：02–04 的断言不全，且没有场景级 harness。
