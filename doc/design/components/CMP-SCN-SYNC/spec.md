---
layer: design
module: scenes
status: active
updated: 2026-11-14
component: CMP-SCN-SYNC
---

# CMP-SCN-SYNC SyncScene 组件规格

## 模块卡

- 状态：`active`
- 单元：组件（场景，actor）
- 层 / 类型：L2；刷新节奏与通知策略
- 业务价值：把「什么时候刷新、并发怎么合并、什么时候通知、失败后还刷不刷」收在一处；App 的 `.task` 与视图不再自己起轮询。
- 负责 X：`refresh` 单飞、`startAutoRefresh` 周期流、`stopAutoRefresh`、通知授权与发送条件、失败态到 `RefreshOutcome` 的映射、auth/device/policy 失败暂停自动刷新。
- 不负责 Y：SyncKey、分页、退避细算（`SyncEngine`）；通知 UI（`Notifier` 实现）；视图状态（`Presentation`）。
- 内部逻辑：并发 `refresh` 共享同一个在飞结果；通知只在 `report.added > 0` 时发，且授权每场景生命周期一次；暂停只停自动循环，手动 `refresh` 仍可执行。
- 拥有的数据：内存中的在飞状态、自动刷新任务与暂停标记（生命周期归本组件）。
- 变化轴：刷新触发方式（首版固定 5 分钟轮询；Ping 已实测不支持长轮询）与通知策略。
- 公开契约：`CMP-SCN-SYNC#refresh`、`#startAutoRefresh`、`#stopAutoRefresh`
- 入口：`Sources/Scenes/SyncScene.swift#SyncScene`、`#RefreshOutcome`
- 依赖：`SyncEngine`、`MailDomain`（`Notifier`、`MailClock`）。扇出 2。
- 冷热：冷；不与主线程共享。
- 尺寸预算：≤500 行；当前随 `Scenes` 共 666 行。
- 单独运行：`./Scripts/swiftw test --filter ScenesTests`
- 删除测试：删掉后视图自己起轮询、自己判通知 → 节奏规则散落在 UI，是真边界。

## 契约卡：SyncScene v1

- 签名：

  ```swift
  public struct RefreshOutcome: Equatable, Sendable { report: SyncReport?, error: MailError?, at: Date }
  public actor SyncScene {
      public init(engine: SyncEngine, notifier: any Notifier, clock: any MailClock)
      public func refresh() async -> RefreshOutcome
      public func startAutoRefresh(every: Duration = .seconds(300)) -> AsyncStream<RefreshOutcome>
      public func stopAutoRefresh()
  }
  ```

- 前置：`SyncEngine` 已绑定账号；`startAutoRefresh` 重复调用先停旧循环。
- 后置：`refresh` 返回时同步已结束（成功则库已提交）；`startAutoRefresh` 立即产出一个结果，之后每个间隔一个，直到暂停或消费者取消。
- 不变量：单飞（并发调用共享同一结果）；通知失败不影响同步结果；`authFailed/deviceNotRegistered/policyBlocked` 后自动刷新流结束，手动刷新仍可走。
- 错误模式：`RefreshOutcome.error` 透传 `MailError`；非 `MailError` 归为 `.offline`（`performRefresh` 的兜底）。
- 幂等 / 顺序 / 并发：同一时刻只有一次 `syncOnce`；`startAutoRefresh` 可停止后重启。
- 超时 / 取消：消费者取消 `AsyncStream` 即停止自动刷新任务；`stopAutoRefresh` 取消循环。
- 一致性：`RefreshOutcome.at` 是发起时间；成功返回后读库即可见。
- 兼容性：`SyncEngine.start/stop/stateStream` **未实现**，本场景只包 `syncOnce`；进度态可由 `SyncEngine.currentState()` 另读。
- 契约测试：`ScenesTests/SyncSceneTests.swift` 4 例。

## 实现进度（2026-11-14）

| 契约 | 代码 | 测试 |
|---|---|---|
| `refresh` 单飞 | ✅ | 「two concurrent refreshes share one SyncEngine run」 |
| 通知条件（added>0、授权一次） | ✅ | 「new mail asks for permission once and posts the added count」「a refresh with no new mail posts nothing」 |
| auth 失败暂停自动刷新、手动仍可 | ✅ | 「an auth failure is reported and pauses automatic refresh」 |
| `stopAutoRefresh` / 取消 | ✅ | 随 `MailboxViewModel.stopAutoRefresh` 与流终止；未单列断言 |

## 验证计划

| 维度 | 证明方式 |
|---|---|
| 单飞 | 两次并发刷新只产生一次 `provision`/`folders` 调用 |
| 通知 | added=3 → posts=[3]；added=0 → posts 空；授权只请求一次 |
| 暂停 | auth 失败后自动流为空；手动刷新仍达 engine |
| 依赖 | 门 1：`Scenes` 不 import EAS；门 2：场景之间不互调 |

## 依赖约束

- 只依赖 `SyncEngine` 与 `MailDomain` 端口；不 import `MailStore`/`Outbox`/EAS。
- 不写库、不发网络；刷新与通知的观测值由 `RefreshOutcome` 暴露。
