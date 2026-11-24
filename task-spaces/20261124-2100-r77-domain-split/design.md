# R77 设计：MailDomain 超预算与会议契约解耦（P1，2026-11-24）

## 1. 现状与问题

- `MailDomain` **1503/800 目标**：`Meeting.swift` 682 + 其它 821（`Values` 297、`Contacts` 209、`EnvelopeParser` 118、
  `Meeting` 682、`Ports` 64、`Configuration` 52、`Errors` 24、`AddressList` 57）。
- `Message.meeting: MeetingInvite?`（`Values.swift`）让「一条消息携带会议」成为平台契约的一部分，
  这也是「拆走 Meeting.swift 后仍剩 821」的原因：即使拆走，`Message` 仍要引用会议类型。
- 会议穿过同步链路的方式：`EASAdapter.fetchMessages → MessageDelta(added/changed: [Message(meeting:)])` →
  `SyncStore.applySyncBatch(delta:) → applyDelta → upsertMeeting(message:)` 在同一事务内写 `meetings` 表。
  读侧 `attachMeetings` 再把 `meetings` 行贴回 `Message.meeting`。
- 因此「`Message` 不再携会议」必须同时决定**会议怎么随同步批次走**，否则会破坏「批次与 `sync_key` 同事务」不变量。

## 2. 候选

### A 轻量解耦（推荐）

- 新 target **`MeetingDomain`**（叶子，仅 Foundation）：`Meeting.swift` 整体迁入（682 行）。
- 新 target **`MailParsing`**（叶子）：`EnvelopeParser.swift` + `AddressList.swift`（175 行）。
- `MailDomain` 只剩 `Values` 297 + `Contacts` 209 + `Ports` 64 + `Configuration` 52 + `Errors` 24 = **646 ≤ 800**，
  依赖 `MeetingDomain` 与 `MailParsing`。
- `Message` 去掉 `meeting`；`MessageDelta` 增加 `meetings: [MeetingInvite]`（默认 `[]`，additive）留在 `MailDomain`。
  → `MailDomain → MeetingDomain` 是叶子边（无环），但**核心契约知道会议**。
- 读侧：`MailStore` 不再 `attachMeetings`；`ReadScene` 新增 `meeting(for ref: MessageRef) throws -> MeetingInvite?`，
  `MailboxViewModel`/`ReaderViewModel` 在选中/打开时同步取一次（本地查询，无网络）。
- 写侧：`applyDelta` 从 `delta.meetings` upsert，仍与批次同事务；`EASAdapter` 把会议放进 `MessageDelta.meetings`。
- 改动面：约 8 个 target 的 `Package.swift` 依赖与 import；`Message.meeting` 的 26 处引用/7 个测试文件改为
  走 `delta.meetings` 或 `read.meeting(for:)`；`MailDomainTests` 拆出 `MeetingDomainTests`（会议用例整体平移）。
- 代价：`MailDomain` 仍依赖会议子域（`MessageDelta` 携带会议），编译器能守「没人能绕过 MeetingDomain 使用会议类型」，
  但守不住「核心不应知道会议」这条审美约束。

### B 彻底解耦（上一轮选的方向）

- 新 target `MeetingDomain`（叶子，682）。
- 新 target **`SyncContract`**（依赖 `MailDomain` + `MeetingDomain`）：把 `MessageDelta` 与 `MailGateway` /
  `MailWriteGateway` / `SyncStore` 三个协议从 `MailDomain` 迁入；`MailDomain` 只留纯邮件值与端口（约 761 ≤ 800）。
- 所有涉及同步契约的 target/测试改 import `SyncContract`（约 23 个文件）。
- 其余同 A（`Message.meeting` 移除、delta 携会议、读侧 `meeting(for:)`）。
- 收益：`MailDomain` 不知道会议，依赖方向完全干净；`MeetingDomain` 与 `SyncContract` 都由编译器隔离。
- 代价：多一个「同步契约」target 与一次跨 8 个 target 的契约搬迁；测试替身 import 全改；风险与工期明显高于 A。

### C 不做拆分、上调预算

- `CMP-DOMAIN` 目标 800 → 1600；推翻 D1「不上调预算」原则，不推荐。

## 3. 两案共同的迁移顺序（实现时按此切 task）

1. `MeetingDomain`：迁 `Meeting.swift`，新建 `MeetingDomainTests`（会议用例平移），`MailDomain` 暂留 `Message.meeting` 以便逐步编译。
2. 读侧去装饰：`attachMeetings` 删除，`ReadScene.meeting(for:)` 落地，`MailboxViewModel`/`ReaderViewModel` 改用；
   `Message.meeting` 字段删除，测试改走 `read.meeting(for:)`。
3. 写侧：`MessageDelta.meetings` 增加（默认空），`EASAdapter` 填充，`applyDelta` 从 delta 取会议；
   删除 `Message.meeting` 的写路径依赖。
4.（仅 B）`SyncContract`：迁 `MessageDelta` 与三个同步协议，改 23 个文件 import。
5.（仅 A）`MailParsing`：迁 `EnvelopeParser` + `AddressList`，`MailDomain` 依赖它。
6. 更新架构（target 图、组件索引、扇出）、`Package.swift`、`check-architecture.sh` 白名单、组件规格与 R77。

## 4. 风险

- **R19 类**：会议写入必须与消息批次、`sync_key` 同事务；两案都保留 `applyDelta` 内写，不分两次提交。
- **读侧时序**：`meetingCard` 由派生属性变为「选中时取一次」，需保证选择切换/快速点击下不贴错卡（用 ref 守卫）。
- **测试面**：`Message(meeting:)` 与 `message.meeting` 的断言要批量改写；`MeetingCard`/日历用例依赖会议种子，
  需提供「按 delta 种子」的夹具。
- **回退**：一个 commit 内可反向回退；不改 schema、无数据迁移。
- **工期**：A 约 1 轮；B 约 2–3 轮且中途编译不绿，建议在单独 worktree 执行。

## 5. 建议

先做 **A**：它已经实现「`Message` 不再携会议 + 会议类型独立 target + 编译器隔离会议类型」，成本约为 B 的一半；
若以后确实要求 `MailDomain` 完全不知道会议，再把三个同步协议上移到 `SyncContract`（步骤 4 可单独做），
不需要重做 A 的其它部分。
