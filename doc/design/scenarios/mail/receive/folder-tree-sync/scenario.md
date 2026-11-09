---
layer: design
module: mail
status: draft
updated: 2026-11-09
flow: mail/receive
scenario: SCN-0002
---

# SCN-0002 文件夹树同步

**结果**：用户打开侧边栏时看到的文件夹树与服务器一致；服务器侧增删改文件夹后，本地在下次同步时跟随变化，不出现重复或幽灵文件夹。

## 入口

- `CMP-SYNC#forceSync`（`design/components/CMP-SYNC/spec.md`）
- `CMP-EAS#folderSync`（`design/components/CMP-EAS/spec.md`）
- `CMP-STORE#applyFolderSnapshot`

## 运行序

流程 `F-RECEIVE-01`：

1. SyncEngine 进入 `folderSync` 态，调 `CMP-EAS#folderSync(0)` 取全量树。
2. 计算与本地快照的差集（新增、改名/改父、删除）。
3. `CMP-STORE#applyFolderSnapshot` 单事务写入并推进文件夹同步 key。
4. 侧边栏按 `type` 排序渲染：收件箱、草稿、已发送、已删除在前，其余按服务器顺序。

失败路径：

- 网络或网关失败 → 保留本地旧树并标记 `stale`，侧边栏显示「上次同步时间」，不阻塞阅读；
- 认证/设备错误 → 转 `authFailed` / `deviceNotRegistered`，停止自动重试；
- 服务器返回空树 → 视为异常而非「用户没文件夹」，保留旧树并上报 `emptyFolderTree`。

## 不可变引用

- `CMP-STORE#applyFolderSnapshot` 的删除语义（服务器没有的文件夹本地软删除，不级联删信）。
- 文件夹 `type` 取值以 EAS 规范为准（`2` = 收件箱）。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0002-01` | 正 | 首次同步 → 收件箱等系统文件夹齐全，key 落库 |
| `T-SCN-0002-02` | 正 | 服务器新增一个子文件夹 → 下次同步本地出现且父级正确 |
| `T-SCN-0002-03` | 正 | 服务器删除某文件夹 → 本地软删除，其下邮件不丢 |
| `T-SCN-0002-04` | 反 | 同步中途失败 → 本地树保持旧快照且标 `stale`，不出现半棵树 |

## 状态

`draft`：运行序与测试方案齐；harness 与组件代码未落地。
