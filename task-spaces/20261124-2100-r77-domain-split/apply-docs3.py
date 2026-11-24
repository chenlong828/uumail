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

p = 'doc/README.md'
s = open(p, encoding='utf-8').read().rstrip() + '\n\n'
s += ('2026-11-24 完成 R77 会议契约解耦（W-REFACTOR-04，P1）：`Meeting.swift` 迁新 target `MeetingDomain`（682 行），'
      '`MessageDelta` 与 `MailGateway`/`MailWriteGateway`/`SyncStore` 迁新 target `SyncContract`（87 行）；'
      '`Message` 不再携带 `meeting`，会议随 `MessageDelta.meetings` 在同步事务内写入，读侧改用 `ReadScene.meeting(for:)`；'
      '`MailDomain` 1503→**756/800**，不再依赖会议子域。验证：460 tests / 77 suites、架构 4/4、`make-app.sh` 成功；'
      '决策见 `history/decisions/2026-11-24-meeting-domain-split.md`。\n')
open(p, 'w', encoding='utf-8').write(s)
print('roadmap and README updated')
