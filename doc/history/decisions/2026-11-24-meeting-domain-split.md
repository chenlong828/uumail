---
layer: history
module: global
status: frozen
updated: 2026-11-24
---

# 会议契约与同步契约解耦（2026-11-24，R77 / P1）

## 背景

`MailDomain` 在 2026-11-24 会议邀请 P1 之后变成 **1503 行 / 目标 800**：`Meeting.swift` 682 + 其它 821。
根因不是文件大，而是 `Message.meeting: MeetingInvite?` 把「一条消息携带会议」写进了平台契约，导致：

- 拆走 `Meeting.swift` 后 `MailDomain` 仍剩 821（>800），因为 `Message` 仍要引用会议类型；
- 会议随 `MessageDelta(added/changed: [Message(meeting:)])` 穿过同步端口，`MailDomain`（端口所在处）无法与会议解耦；
- `MailStore` 在读侧 `attachMeetings` 把会议贴回每条 `Message`，列表读无谓地多查一次 `meetings`。

用户 2026-11-24 在三个候选中选择「彻底重构（`Message` 不再携会议）」，并在随后确认采用
「新增 `SyncContract` target」的完整解耦方案（而非让 `MailDomain` 依赖会议子域的轻量方案）。

## 决定

### D1 新增两个 target

- `MeetingDomain`（叶子，仅 Foundation，682 行）：会议值类型、重复展开、`.ics` 序列化。
- `SyncContract`（依赖 `MailDomain` + `MeetingDomain`，87 行）：`MessageDelta`、`MeetingDeltaEntry`、
  `MailGateway`、`MailWriteGateway`、`SyncStore`。

`MailDomain` 只留纯邮件值与非同步端口，**756/800**，且**不依赖**会议子域。

### D2 `Message` 不再携带会议

- `Message.meeting` 与初始化参数删除；`MessageDelta` 增加 `meetings: [MeetingDeltaEntry] = []`。
- 写侧：`EASAdapter.fetchMessages` 在同一次响应里产出 `MessageDelta.added/changed` 与 `delta.meetings`；
  存储 `applyDelta` 在**同一事务**内写消息行与 `meetings` 行（保持「批次与 `sync_key` 同事务」不变量）；
  `upsertMeeting` 改为接收 `serverID`/`subject`/`invite`，不再从 `Message` 取。
- 读侧：删除 `attachMeetings` 装饰，新增 `MailStore.meeting(account:folder:serverID:)` 与
  `ReadScene.meeting(for:)`；`MailboxViewModel` 在选中时取一次并缓存为 `meetingInvite`（供邀请卡），
  `ReaderViewModel` 打开时取一次。列表页不再携带会议。

### D3 依赖方向

```
MailDomain (756)        MeetingDomain (682)
        \                 /
         \               /
          SyncContract (87)
          /      |      \
   EASAdapter  SyncEngine  MailStore/Scenes/Presentation/...
```

- `MailDomain` 不知道会议；`MeetingDomain` 不知道邮件与存储；两者只在 `SyncContract` 相遇。
- `MailDomain` 的 `Package.swift` 依赖已确认为空（原先临时依赖 `MeetingDomain` 已删除）。

## 代价与已知接受

- 单次编辑的跨模块修改面变大：`MessageDelta` 的签名字面在 `SyncContract`，任何改动都要在契约 target 落地。
- 邀请卡的取数从「派生属性」变为「选中时查询一次」，选择切换/刷新时由 `MailboxViewModel.refreshSelectedMeeting()`
  刷新；`meetingInvite` 的 setter 放宽为 `internal(set)`（同模块扩展写，公开读面不变）。
- 会话内不做「列表行显示会议标记」，因此无额外列表查询；若以后需要，需按 ref 批量查 `meetings`，不在本批。

## 验证

- `./Scripts/swiftw test` **460 tests / 77 suites** 全绿（会议存储用例改为经 `delta.meetings` 种子；
  会议纯值用例迁到新测试 target `MeetingDomainTests`）。
- `bash Scripts/check-architecture.sh` 4/4（新增 target 进 import 白名单；`Composition` 允许 `SyncContract`）。
- `./Scripts/make-app.sh` 成功。
- 预算：`MailDomain` 756/800、`MeetingDomain` 682/800、`SyncContract` 87/400。

## 回退

一个提交内可整体反向回退：恢复 `Message.meeting`、把 `MessageDelta` 与端口移回 `MailDomain`、删两个 target。
无 schema 变更、无数据迁移。
