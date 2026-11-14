---
layer: history
module: global
status: frozen
updated: 2026-11-14
---

# 邮箱写路径：非可选写端口、串行门与写响应语义（2026-11-14）

## 背景

`REQ-0013`（列表停留自动已读）与 `REQ-0014`（列表键盘删除）需要客户端向 EAS 服务器发写命令。设计把写路径收敛为「窄写端口 + 一个 `SyncEngine` 持 key + 本地先行/服务器确认」三件事，但涉及新增公共协议、`SyncStore` 契约变更、组合根装配与一个跨组件例外，按 `arch-design-spec` 定为 **P1**。设计复核（`task-spaces/20261114-232232/design.md` §5.1）列出待确认清单；实现前未落 frozen 记录，代码评审因此判 fail。

## 确认来源与范围

- 本记录由 W-M3-03 实现批次（run `20261114-232232`）在 2026-11-14 代码评审回退重跑时归档。
- 确认来自任务发起人（工作区所有者）在本次 agent-flow 继续执行中给出的明确指令：补齐 P1 frozen 记录并继续完成写路径实现与验证。原始确认没有独立的 IM/邮件原文；**本记录是唯一书面落点**，不把编排指令伪造成第三方签字。
- 确认范围 = 下述「决定」1–6 项；第 7–8 项是 R16 真机与真实窗口探针得到的**实现级修订**，在确认范围内按证据收敛，不改变用户可见语义。

## 决定

1. **写端口形状**：新增 `MailWriteGateway`（`markRead` / `delete`，每次一条 Sync 写命令，返回 `MessageDelta`），**不扩 `MailGateway`**；`SyncStore` 增 `markRead` / `commitMarkRead` / `commitDelete`。`MailGateway` 的 7 个读/发方法签名不变。
2. **全链路非可选**：`GatewayEndpoints.write`、`SyncEngine.init(writeGateway:)`、`ReadScene.init(writeEngine:)` 均无 `nil`/默认值；生产 target 不提供 `UnsupportedWriteGateway`，只读测试在测试 target 显式注入。装配测试断言生产 `write` 是 `EASAdapter`。
3. **串行归属**：一个账号一个 `SyncEngine`，`SyncScene` / `ReadScene` 共用；显式 FIFO 门（不是只靠 actor 重入）保证「一次 Sync（读或写）→ apply/commit」互斥，写命令共享同一集合 key；`syncInbox` 每轮门内重读 key。`Status=3/4` 的 `resetCollection` + 重建必须在**同一次门持有内**完成，排队写不得在 reset 后、重建前插队。
4. **场景编排**：`ReadScene.markReadLocally` 只写本地、零网络；`writeBackMarkRead` 后台尽力回写、失败不回滚、不抛给 UI；`deleteMessage` 只在服务器确认后由 `commitDelete` 软删。`T-1114-15` = `CMP-SYNC + CMP-ROOT（仅装配）`，`T-1114-16` = `CMP-SCN-READ + CMP-ROOT（仅装配）`，两个 change 串行、`CMP-ROOT` WIP 独占，组合根只构造/注入/路由。
5. **场景扇出 1–2 → 1–3**：仅 `ReadScene` 为写路径新增 `SyncEngine` 直接依赖；替代方案 F（窄 `SyncWriting` 端口，保持 2）保留为被否决记录，不再实现。
6. **同批边界**：`T-1114-11` 只加 `MailWriteGateway`（非破坏）；`T-1114-14` 同批完成 `SyncStore` 三方法 + `MailStore` 唯一生产遵循 + `SyncStoreConformance` 转发器 + 测试替身，避免不可编译中间态。不建 `pending_op`、不改 schema、不做离线队列（R18/Q2 维持）。

## R16 真机带来的实现级修订

- **写响应携带整页 delta 与 `MoreAvailable` 是正常分页**。真机：`Change/Read=1` 返回 `Collection/Status=1`、新 key、`Collection/MoreAvailable`、100 条 `Add`；`Delete` 同样。原设计「`moreAvailable == true` 抛 `unsupported`、不提交」会拒绝所有真实写响应；改为：delta + 本地效果 + 新 key 同事务提交，剩余页由下一轮增量同步消费。
- **not-found 是成功 no-op**：重复删除同一 `ServerId` 仍返回 `Collection/Status=1` + 新 key，无逐条 `Status`。删除语义为移到「已删除邮件」（`Type=4`，新 `ServerId`），不是永久删除，不需要 `DeletesAsMoves=1`。
- **前台信号用 NSApplication 通知**：真实 SwiftUI `WindowGroup` 探针显示 macOS 上 `scenePhase` 不随应用失活/回焦变化（始终 `.active`，而 `NSApp.isActive` 与 `didBecomeActive` / `willResignActive` 会变）。`MailboxView` 改为监听这两个通知转发 `setApplicationActive`，语义仍是「失活取消计时、回前台重新计满」，视图不判业务。
- 证据：`task-spaces/20261114-232232/evidence/r16-real-gateway.txt`、`r16-write-responses` 摘录、`scene-phase-probe.txt`、`ui-delete-probe-focus.txt`。

## 代价 / 影响

- 公共构造契约变更一次（`SyncEngine`/`ReadScene` 各多一个非可选依赖），生产与测试构造点同批更新。
- 写响应与普通同步共用 `commit*` 事务；目标 partial echo 被排除，其他消息照常应用。
- 文件拆分：`MailboxDwell`、`MailboxDeletion`、`MailboxViewModel+Compose`、`MailboxViewModel+Delete`、`MailboxViewModel+Body`；主 VM 从 400 行降到 298 行（目标 ≤380）。
- 未验证项不因此消失：真实 App bundle 的 `scenePhase` 探针仍以独立 SwiftUI 窗口代替；附件/发送等既有场景不在本批。

## 未采纳

| 方案 | 理由 |
|---|---|
| 扩 `MailGateway` 加写方法 | 污染只读 fake 与读契约；只读调用方被迫实现写 |
| `ReadScene` 直连 gateway | 并发推进同一 key；没有与同步共享的门 |
| 新写 actor / 第二把门 | 两个 key 持有者，互顶 |
| 整个 `syncOnce` 包门 | 删除要等整轮分页与限流 sleep |
| 本地先软删 + pending 表 | 需要 schema 与状态机；本批明确不做 |
| `moreAvailable` 一律拒绝写提交 | 真机写响应正常携带；会拒绝所有写 |
| 只靠 `scenePhase` 判前台 | 实测不随应用失活变化，计时不会暂停 |

## 落点

`Sources/MailDomain/Ports.swift`、`Sources/MailStore/{MailStore,SyncStoreConformance}.swift`、`Sources/SyncEngine/SyncEngine.swift`、`Sources/Scenes/ReadScene.swift`、`Sources/Presentation/{MailboxDwell,MailboxDeletion,MailboxViewModel(+Body,+Delete)}.swift`、`Sources/uumail/MailboxView.swift`；规格 `CMP-DOMAIN`、`CMP-EAS`、`CMP-EASADAPTER`、`CMP-STORE`、`CMP-SYNC`、`CMP-SCN-READ`、`CMP-PRES`、`CMP-APP`、`CMP-ROOT`；排期 `doc/plan/roadmap.md` §W-M3-03。
