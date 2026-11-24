---
layer: works
module: global
scope: project:uumail
status: active
updated: 2026-11-24
---

# W-M3-19 顶部邮箱切换与发件箱（Sent Items 同步）

## 背景

用户在 2026-11-24 追加反馈：左侧默认文件夹列表太长、几乎都不使用；希望把「日历 / 收件箱」的切换放到顶部，并增加「发件箱」、实现 Sent 镜像。

人工确认（2026-11-24）：

- 导航：**顶部三段切换（收件箱 / 发件箱 / 日历），完全去掉左侧文件夹栏**；
- 发件箱：**显示服务器 Sent Items（folder type 5），并把该文件夹纳入同步**；
- 其他文件夹（草稿/已删除/垃圾邮件等）：**全部隐藏，不提供入口**。

## 范围

- 改：`MailboxView`（去掉 sidebar、顶部 Picker、两栏列表/阅读、日历整宽）、`MailboxToolbar` 刷新文案；
  `MailboxViewModel`（`sentFolderID`/`inboxFolderID`/`selectSent`/`refreshSent`）、`SyncScene.refreshSent`、
  `SyncEngine.syncSentOnce`（`syncInbox` 泛化为 `syncFolder`）、`MailDomain.Folder.isSentItems`。
- 不改：`SendMail` 请求（已有 `SaveInSentItems`，2026-11-20 测试已断言）、EAS 协议、schema、target、依赖、
  outbox 状态机、日历/会议、附件与正文读取。
- 已知限制：其他文件夹仍不同步，只是不再出现在导航里；Sent 只拉最近 30 天（与 `FilterType=5` 和列表窗口一致）。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| `T-1124-28` | design | — | 完成 | 用户口径、现有 `MailboxView`/`SyncEngine`/`SendMail`、本地库 folder type |
| `T-1124-29` | change | CMP-SYNC | 完成 | `SyncEngine.swift`/`SyncScene.swift` + `SyncEngineTests` |
| `T-1124-30` | change | CMP-PRES | 完成 | `MailboxViewModel.swift`/`+List.swift` + `MailboxViewModelTests` |
| `T-1124-31` | change | CMP-APP | 完成 | `MailboxView.swift`/`MailboxToolbar.swift` + L2 探针 |
| `T-1124-32` | verify | — | 完成 | 全量测试、架构 4 门、`make-app.sh`、L2 探针 |
| `T-1124-33` | doc | — | 进行中 | REQ/SCN/CMP/roadmap/README/open-questions |

## 验收标准

1. 启动后无左侧文件夹栏；顶部三段切换为「收件箱 / 发件箱 / 日历」，默认收件箱。
2. 邮件页为列表 + 阅读两栏，列表默认 480（min 320）；1440 窗口实测 list 480 / reading 952，900 窗口 480 / 412。
3. 日历页占满内容区，顶部切换仍在；切回收件箱/发件箱不丢顶部切换。
4. 发件箱选中时同步服务器 Sent Items（type 5），列表出现已发送副本；收件箱的 sync key 不被 Sent 同步移动。
5. `SendMail` 继续携带 `SaveInSentItems`；发件箱同步失败时保留缓存并给中文错误，不把收件箱判为失败。
6. 全量测试、架构 4 门、`make-app.sh` 通过。

## 未决 / 人工项

- 真实发一封测试信后，确认服务器 Sent Items 出现副本、App 发件箱能拉到；这需要一次真实外发，待用户确认后执行。
- 真实点击顶部切换、列表/阅读分隔条拖拽、深色主题视觉验收。
- 其他文件夹（草稿/已删除等）仍不同步；用户已选择隐藏，不再提供入口。
