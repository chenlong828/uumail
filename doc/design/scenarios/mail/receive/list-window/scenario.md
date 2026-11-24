---
layer: design
module: mail
status: verified
updated: 2026-11-24
flow: mail/receive
scenario: SCN-0026
---

# SCN-0026 列表默认显示最近 30 天

**结果**：用户选中任一文件夹，列表显示该文件夹最近 30 天收到的**全部**邮件（不再按 200 条截断），按收信时间倒序，状态栏计数是真实条数；30 天前的邮件不在列表；5,000 封规模下列表加载仍在 1s 内。

## 入口

- `CMP-APP#MailboxView`（列表与状态栏计数）
- `CMP-PRES#MailboxViewModel`（加载窗口、计数、失败文案）
- `CMP-SCN-READ#messages(folderID:since:)`（时间窗读取）
- `CMP-STORE#messages(account:folder:since:)`（按 `received` 时间窗的单次查询）

## 运行序

流程 `F-RECEIVE-03`：

1. 选中文件夹 / 同步后刷新 / 手动刷新 → `MailboxViewModel` 计算窗口起点：`Calendar.current.startOfDay(for: now - 30d)`（本地自然日）。
2. 调 `ReadScene.messages(folderID:since:)` → `MailStore` 单次查询：`account = ? AND folder = ? AND received >= ? ORDER BY received DESC`，**不带条数上限**。
3. 结果一次性替换 `messages`；状态栏 `visibleMessages.count` 即查询结果条数（删除隐藏的行按现状排除）。
4. 删除、已读、搜索、同步沿用既有路径；30 天外的邮件不进入列表（仍在库里，可被搜索按现状上限命中）。
5. 切换文件夹 → 重新按同窗口查询；旧列表在新结果就绪前保持显示（不闪空态）。

失败路径：

- 查询失败 → `sync.phase = .failed` 或列表错误文案（沿用现有中文错误映射），保留上一次成功列表不清空，可重试。
- 空文件夹 / 30 天内无邮件 → 既有「没有邮件」空态，文案不变。
- 同一文件夹 30 天内条数极大（≥5,000）→ 仍全部返回；性能断言在 §测试 `T-SCN-0026-03` 覆盖，不在本卡放宽或加封顶。

## 不可变引用

- `SCN-0003`：同步窗口仍是 EAS `FilterType=5`（一个月）、`sync_key` 与批次同事务；本卡只改**读取窗口**，不改同步与写路径。
- `SCN-0004`：打开、正文补拉、渲染安全不变。
- `SCN-0009`：列表身份（folder + serverID 复合键）、删除隐藏集合与搜索删除语义不变。
- `SCN-0024`：日历「跳回来源邮件」仍能在列表里找到该行（时间窗与同步窗口同口径）。
- 搜索仍按 `ReadScene.search` 的既有上限（100 条），本卡不跟随。
- 不改 schema、不新增 target 与依赖。

## 测试

| ID | 类型 | 方案 |
|---|---|---|
| `T-SCN-0026-01` | 正 | 夹具 30 天内 250 封 + 31–60 天前 50 封 → 列表恰 250 行（不是 200）、按 `received` 倒序、计数 = 250；30 天前那封不在列表（L1 `MailboxViewModel` + `MailStore` 窗口边界） |
| `T-SCN-0026-02` | 正 | 夹具 30 天内 1,100 封 → 全部载入、计数 1,100、无「仅显示前 N」文案；切换文件夹后计数随新窗口正确（L1） |
| `T-SCN-0026-03` | 正 | 5,000 封夹具（M4 基线同规模）→ `messages(since:)` 查询 + 列表装载 < 1s（测试内阈值沿用 M4），滚动/选中不卡；与 200 条旧路径的耗时对比记录在证据里（L1 性能断言） |
| `T-SCN-0026-04` | 反 | 空文件夹 → 「没有邮件」空态；查询失败 → 中文错误 + 保留旧列表 + 可重试；窗口边界：恰好 30 天前 00:00 的邮件属于窗口内（`>=` 语义），23:59 前 31 天的在窗口外（L1 边界） |

## 状态

`verified`（2026-11-24 实现并验证）。

- 实现：`MailboxViewModel.reloadCurrentList` 改为 `read.messages(folderID:since: MailboxViewModel.listWindowStart())`；
  窗口起点 = 本地自然日往回 30 天；SQL 用 `julianday(received_raw) >= julianday(?, 'unixepoch')`，不带 LIMIT。
- 证据（L1）：`Tests/MailStoreTests/MessageLookupTests.swift`（边界、无封顶 250 行、排序、跨文件夹）、
  `Tests/ScenesTests/ReadSceneLookupTests.swift`（透传与零网络）、`Tests/PresentationTests/ReaderViewModelTests.swift`
  的 `MailboxListWindow` 套件（窗口去 200 条、空文件夹、边界 29.5 天保留 / 31 天排除）。
- 证据（性能，L1）：`Tests/MailStoreTests/PerformanceTests.swift` 的 `windowBaseline`
  实测 5,000 封窗口内查询 **0.047s**、返回 5,000 行（阈值 1s），原始输出见测试日志
  `BASELINE window30d-in-window=0.047s rows=5000`。
- 未覆盖（发布前人工项）：大文件夹滚动与选中手感、切换文件夹的视觉过渡。
