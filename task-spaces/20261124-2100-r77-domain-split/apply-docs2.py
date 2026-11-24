# ---------- architecture ----------
p = 'doc/design/architecture.md'
s = open(p, encoding='utf-8').read()
s = s.replace('10 个库 target + 2 个可执行 target', '12 个库 target + 2 个可执行 target', 1)

s = s.replace(
    '| `HTMLSupport` | L1 工具 | `MailDomain` | `Sources/HTMLSupport/{HTMLText,InlineImageHTML}.swift`（2026-11-24 从 `Scenes` 析出，CMP-HTML） |',
    '| `HTMLSupport` | L1 工具 | `MailDomain` | `Sources/HTMLSupport/{HTMLText,InlineImageHTML}.swift`（2026-11-24 从 `Scenes` 析出，CMP-HTML） |\n'
    '| `MeetingDomain` | L1 值域 | Foundation | `Sources/MeetingDomain/Meeting.swift`（2026-11-24 从 `MailDomain` 析出，CMP-MEETING-DOMAIN） |\n'
    '| `SyncContract` | L1 契约 | `MailDomain`、`MeetingDomain` | `Sources/SyncContract/SyncContract.swift`（`MessageDelta` 与同步端口，CMP-SYNC-CONTRACT） |',
    1)

s = s.replace(
    '| `CMP-MEETING-STORE` | `design/components/CMP-MEETING-STORE/spec.md` | L1a 数据（meetings 表） |',
    '| `CMP-MEETING-STORE` | `design/components/CMP-MEETING-STORE/spec.md` | L1a 数据（meetings 表） |\n'
    '| `CMP-MEETING-DOMAIN` | `design/components/CMP-MEETING-DOMAIN/spec.md` | L1 值域（会议） |\n'
    '| `CMP-SYNC-CONTRACT` | `design/components/CMP-SYNC-CONTRACT/spec.md` | L1 契约（同步批次） |',
    1)

s = s.replace(
    '| `Scenes` | 5 | ≤8 | `MailDomain`、`MailStore`、`SyncEngine`、`Outbox`、`HTMLSupport`；单个场景仍 1–3（≤5） |',
    '| `Scenes` | 7 | ≤8 | `MailDomain`、`MeetingDomain`、`MailStore`、`SyncEngine`、`Outbox`、`HTMLSupport`、`SyncContract`；单个场景仍 1–3（≤5） |',
    1)
s = s.replace(
    '| `Presentation` | 2 | ≤3 | `Scenes` + `HTMLSupport`（与 `MailDomain` 值类型） |',
    '| `SyncContract` | 2 | ≤4 | `MailDomain` + `MeetingDomain`，无业务依赖 |\n'
    '| `MeetingDomain` | 0 | ≤5 | 纯会议值域 |\n'
    '| `Presentation` | 4 | 业务 1（`Scenes`） | 另三个是值/契约 target：`MailDomain`、`MeetingDomain`、`HTMLSupport` |',
    1)

s = s.replace(
    '- 测试 target：`MailDomainTests`、`HTMLSupportTests`、`MailStoreTests`、`SyncEngineTests`、`OutboxTests`、`EASClientTests`、'
    '`EASAdapterTests`、`ScenesTests`、`PresentationTests`、`CompositionTests`。',
    '- 测试 target：`MailDomainTests`、`MeetingDomainTests`、`HTMLSupportTests`、`MailStoreTests`、`SyncEngineTests`、'
    '`OutboxTests`、`EASClientTests`、`EASAdapterTests`、`ScenesTests`、`PresentationTests`、`CompositionTests`。', 1)

anchor = '13. **日历只展示「收到的邀请」**'
i = s.index(anchor)
item = ('14. **会议契约已解耦（R77，2026-11-24）**：`Meeting.swift` 迁 `MeetingDomain`（682），`MessageDelta` 与三个同步端口迁 '
        '`SyncContract`（87），`Message` 不再携带 `meeting`，会议随 `MessageDelta.meetings` 同事务写入；'
        '`MailDomain` 756/800、不再依赖会议子域。决策 `history/decisions/2026-11-24-meeting-domain-split.md`。\n')
# insert after item 13's paragraph: find the end of its block (next blank line after anchor)
j = s.index('\n\n', i) + 2
s = s[:j] + item + '\n' + s[j:]
open(p, 'w', encoding='utf-8').write(s)

# ---------- risks ----------
p = 'doc/plan/risks.md'
s = open(p, encoding='utf-8').read()
i = s.index('| R77 |')
j = s.index('\n', i)
cells = s[i:j].split('|')
assert len(cells) == 7, (len(cells), cells)
cells[3] = cells[3].rstrip() + (' **已关闭（2026-11-24）**：`MailDomain` **756/800**（会议值类型→`MeetingDomain` 682，'
                                 '同步契约→`SyncContract` 87，`Message` 去 `meeting`）。')
cells[4] = cells[4].rstrip() + ' 决策与验证见 `history/decisions/2026-11-24-meeting-domain-split.md`。'
s = s[:i] + '|'.join(cells) + s[j:]

header = '## 变更记录\n\n'
entry = ('- 2026-11-24（R77 会议契约解耦，P1）：`Meeting.swift` → 新 target `MeetingDomain`（682）；`MessageDelta` 与 '
         '`MailGateway`/`MailWriteGateway`/`SyncStore` → 新 target `SyncContract`（87）；`Message.meeting` 删除，会议随 '
         '`MessageDelta.meetings` 同事务写入；读侧改为 `ReadScene.meeting(for:)`；`MailDomain` 756/800。R77 关闭。\n')
assert s.count(header) == 1
s = s.replace(header, header + entry, 1)
open(p, 'w', encoding='utf-8').write(s)

# ---------- roadmap ----------
p = 'doc/plan/roadmap.md'
s = open(p, encoding='utf-8').read()
anchor = '| W-REFACTOR-02 账号与文件夹存储拆分 | —（结构） |'
i = s.index(anchor)
row = ('| W-REFACTOR-04 会议契约与同步契约解耦（R77） | —（结构） | W-REFACTOR-03；R77；用户拍板「彻底重构（`Message` 不再携会议）」 | '
       'CMP-MEETING-DOMAIN（新 target `MeetingDomain`）、CMP-SYNC-CONTRACT（新 target `SyncContract`）、CMP-DOMAIN、CMP-STORE、'
       'CMP-EASADAPTER、CMP-SCN-READ、CMP-PRES | 已完成（2026-11-24）：`MailDomain` 1503→**756/800**；`MeetingDomain` 682/800；'
       '`SyncContract` 87/400；`Message` 去 `meeting`、会议随 `MessageDelta.meetings` 同事务写入；读侧 `ReadScene.meeting(for:)`；'
       '460 tests / 77 suites、架构 4/4、`make-app.sh` 成功 |\n')
s = s[:i] + row + s[i:]

anchor2 = '## 批次纪律'
i2 = s.index(anchor2)
section = '''## W-REFACTOR-04 会议契约与同步契约解耦（2026-11-24 完成，R77）

来源：`history/decisions/2026-11-24-meeting-domain-split.md`（P1；候选 A/B/C，选定「彻底重构」）。

| 项 | 拆前 | 拆后 | 说明 |
|---|---|---|---|
| `MailDomain` | 1503/800 | **756/800** | 会议值类型与同步契约迁出；不再依赖会议子域 |
| `MeetingDomain`（新 target） | — | **682/800** | `Meeting.swift` 整体迁入（叶子，仅 Foundation） |
| `SyncContract`（新 target） | — | **87/400** | `MessageDelta`（含 `meetings`）、`MeetingDeltaEntry`、`MailGateway`、`MailWriteGateway`、`SyncStore` |
| `Message` | 带 `meeting` | **不带** | 会议在 `MessageDelta.meetings` 中随批次走；`applyDelta` 同事务写入 |
| 读侧 | `attachMeetings` 装饰每行 | **`ReadScene.meeting(for:)`** | 邀请卡在选中时取一次；列表读不再查 `meetings` |
| `EASAdapter` / `MailStore` / `SyncEngine` / `Composition` | — | 改 `import SyncContract` | 契约 target 成为同步唯一相识面 |

**验证**：`./Scripts/swiftw test` **460 tests / 77 suites**；`bash Scripts/check-architecture.sh` 4/4（新增 target 与
`Composition` 白名单已登记）；`./Scripts/make-app.sh` 成功。**未做**：无 schema 变更；真实邮箱冒烟与既有发布前人工项不变。

'''
s = s[:i2] + section + s[i2:]

line_end = s.index('\n', s.index('首版范围已于 2026-11-09 确认'))
line = s[:line_end]
line += ('2026-11-24 另立 W-REFACTOR-04 并完成（R77 会议契约解耦）：`Meeting.swift` → 新 target `MeetingDomain`（682），'
         '`MessageDelta` 与同步端口 → 新 target `SyncContract`（87），`Message` 去 `meeting`、会议随 `MessageDelta.meetings` '
         '同事务写入、读侧改用 `ReadScene.meeting(for:)`；`MailDomain` 1503→756/800；460 tests / 77 suites、架构 4/4、'
         '`make-app.sh` 成功。')
s = line + s[line_end:]
open(p, 'w', encoding='utf-8').write(s)

# ---------- README ----------
p = 'doc/README.md'
s = open(p, encoding='utf-8').read().rstrip() + '\n\n'
s += ('2026-11-24 完成 R77 会议契约解耦（W-REFACTOR-04，P1）：`Meeting.swift` 迁新 target `MeetingDomain`（682 行），'
      '`MessageDelta` 与 `MailGateway`/`MailWriteGateway`/`SyncStore` 迁新 target `SyncContract`（87 行）；'
      '`Message` 不再携带 `meeting`，会议随 `MessageDelta.meetings` 在同步事务内写入，读侧改用 `ReadScene.meeting(for:)`；'
      '`MailDomain` 1503→**756/800**，不再依赖会议子域。验证：460 tests / 77 suites、架构 4/4、`make-app.sh` 成功；'
      '决策见 `history/decisions/2026-11-24-meeting-domain-split.md`。\n')
open(p, 'w', encoding='utf-8').write(s)

print('architecture, risks, roadmap, README updated')
