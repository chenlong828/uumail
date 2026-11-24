p = 'doc/design/components/CMP-DOMAIN/spec.md'
s = open(p, encoding='utf-8').read()

old_budget = ('- 尺寸预算：目标 ≤800 行；**当前 1503 行已超**（2026-11-24 `wc -l`：`Meeting.swift` 682 + 其它 821；会议值类型 2026-11-24 P1 '
              '加入后未重新定预算）。是否拆出会议契约或上调预算需另行拍板（`plan/risks.md` R77），本批不静默调预算、不做拆分。')
new_budget = ('- 尺寸预算：目标 ≤800 行；当前 **756 行**（2026-11-24 `wc -l`：`Values` 272 + `Contacts` 209 + `EnvelopeParser` 118 + '
              '`Ports` 21 + `Configuration` 52 + `Errors` 24 + `AddressList` 57 ≈ 756）。会议值类型已迁 `CMP-MEETING-DOMAIN`（682），'
              '同步契约（`MessageDelta`/`MailGateway`/`MailWriteGateway`/`SyncStore`）已迁 `CMP-SYNC-CONTRACT`（87）；本组件不再依赖'
              '会议子域（2026-11-24 R77 关闭）。')
assert old_budget in s
s = s.replace(old_budget, new_budget)

old = '## 契约卡：MailGateway v2'
new = ('> **已迁出（2026-11-24，R77）**：`MailGateway`/`MailWriteGateway`/`SyncStore` 与 `MessageDelta` 现属 '
       '`CMP-SYNC-CONTRACT`（`design/components/CMP-SYNC-CONTRACT/spec.md`）。本节保留为迁移前的契约摘要，'
       '**不作为现行设计依据**；增删字段以 `CMP-SYNC-CONTRACT` 为准。\n\n## 契约卡：MailGateway v2（已迁出）')
assert old in s
s = s.replace(old, new, 1)

old = '## 契约卡：SyncStore'
new = '## 契约卡：SyncStore（已迁出）'
assert old in s
s = s.replace(old, new, 1)

old = '## 设计增量：会议邀请值类型与 iCalendar（REQ-0029 / REQ-0030，2026-11-24，P1 已确认、已实现）'
new = ('## 设计增量：会议邀请值类型与 iCalendar（已迁至 CMP-MEETING-DOMAIN，2026-11-24）\n\n'
       '> 本节描述的值类型与 iCalendar 序列化已于 2026-11-24 迁至 `CMP-MEETING-DOMAIN`（target `MeetingDomain`）；'
       '`Message` 不再携带 `meeting`，会议随 `MessageDelta.meetings` 走。现行契约见 '
       '`design/components/CMP-MEETING-DOMAIN/spec.md` 与 `CMP-SYNC-CONTRACT/spec.md`。以下保留为迁移前记录。')
assert old in s
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)

# Implementation notes on the affected components
def append(path, text):
    s = open(path, encoding='utf-8').read().rstrip() + '\n'
    open(path, 'w', encoding='utf-8').write(s + text + '\n')

append('doc/design/components/CMP-STORE/spec.md', '''
## 实现（2026-11-24，R77 会议契约解耦）

- `MessageDelta` 与同步端口迁至 `CMP-SYNC-CONTRACT`；`MailStore` 仍实现 `SyncStore`（新增 `import SyncContract`）。
- 读侧不再 `attachMeetings`：`messages(account:folder:limit:)` / `messages(account:folder:since:)` / `message(account:folder:serverID:)`
  与搜索都只返回 `Message`；邀请卡改走 `MailStore.meeting(account:folder:serverID:)`（由 `CMP-MEETING-STORE` 提供）。
- 写侧 `applySyncBatch(account:folder:added:changed:removedServerIDs:syncKey:meetings:)` 新增 `meetings`（默认 `[]`），
  `MessageDelta.meetings` 在 `applyDelta` 的同一事务内写入；`CMP-STORE` 实测 952/1000 不变。
''')
append('doc/design/components/CMP-MEETING-STORE/spec.md', '''
## 实现（2026-11-24，R77 会议契约解耦）

- 写入来源从 `Message.meeting` 改为 `MessageDelta.meetings`（`MeetingDeltaEntry`：serverID + 主题回退 + `MeetingInvite`）；
  `upsertMeeting(_:account:folder:serverID:subject:invite:now:)`，不再接收 `Message`。
- 读侧新增 `meeting(account:folder:serverID:)`（按消息键取一条，过滤取消与 `MessageType=4`），供 `ReadScene.meeting(for:)`。
- 会议值类型现由 `MeetingDomain` 提供（`import MeetingDomain`）；组件 287/400 不变。
''')
append('doc/design/components/CMP-SCN-READ/spec.md', '''
## 实现（2026-11-24，R77 会议契约解耦）

- 新增 `ReadScene.meeting(for ref:) -> MeetingInvite?`（透传 `MailStore.meeting(account:folder:serverID:)`），
  供邀请卡读取；`ReadScene.message(_:)` / `messages(folderID:since:)` 签名不变、不再装饰会议。
- `Scenes` 增加 `import SyncContract`（`MessageDelta` 与同步端口）与 `import MeetingDomain`（会议值类型）；
  `Scenes` 932/1200。
''')
append('doc/design/components/CMP-PRES/spec.md', '''
## 实现（2026-11-24，R77 会议契约解耦）

- `MailboxViewModel.meetingCard` 改为由 `meetingInvite` 派生；`meetingInvite: MeetingInvite?` 在选中/刷新时由
  `refreshSelectedMeeting()` 调 `ReadScene.meeting(for:)` 取一次（setter `internal(set)`，公开读面不变）。
- `ReaderViewModel.load` 同样经 `ReadScene.meeting(for:)` 取卡；不再有 `Message.meeting`。
- 选中切换、刷新保留选中、删除后清空三条路径都覆盖：`select(_:open:)` 刷新、`clearSelection()` 置空。
''')
append('doc/design/components/CMP-EASADAPTER/spec.md', '''
## 实现（2026-11-24，R77 会议契约解耦）

- `fetchMessages` / `markRead` / `delete` 返回的 `MessageDelta` 现由 `CMP-SYNC-CONTRACT` 定义，并新增
  `meetings: [MeetingDeltaEntry]`：`EASAdapter.delta` 把同一响应里的邀请映射成 `MeetingDeltaEntry(serverID:subject:invite:)`。
- `EASAdapter.message(_:)` 不再构造会议；会议映射保留为 `EASAdapter.meeting(_:)`（测试直接调用）。
''')
print('component docs updated')
