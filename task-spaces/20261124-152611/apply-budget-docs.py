import re

# ---------- component budget lines ----------
def replace_line(path, prefix, new):
    s = open(path, encoding='utf-8').read()
    i = s.index(prefix)
    j = s.index('\n', i)
    s = s[:i] + new + s[j:]
    open(path, 'w', encoding='utf-8').write(s)

replace_line('doc/design/components/CMP-STORE/spec.md',
    '- 尺寸预算：硬上限 1000 行；',
    '- 尺寸预算：硬上限 1000 行；当前 **952 行**（`MailStore.swift` 591 + `MailStore+Lookup.swift` 73 + `Migrations.swift` 210 + '
    '`SyncStoreConformance.swift` 40 + `Values.swift` 38，2026-11-24 `wc -l`）。2026-11-24 起 `meetings` 读写析出到 '
    '`CMP-MEETING-STORE`（287 行），outbox 早已独立到 `CMP-OUTBOX-STORE`；账号/文件夹拆分仍归 `W-REFACTOR-02`。')

replace_line('doc/design/components/CMP-STORE/spec.md',
    '- **预算（2026-11-24 人工确认「先拆」）**',
    '- **预算（2026-11-24 拆分后实测）**：`CMP-STORE` **952/1000**（`MailStore.swift` 591 + `MailStore+Lookup.swift` 73 + '
    '`Migrations.swift` 210 + `SyncStoreConformance.swift` 40 + `Values.swift` 38）；`MailStore+Meetings.swift`（273 行）已拆为 '
    '`MeetingStore+Read.swift` 140 + `MeetingStore+Write.swift` 147，并归 `CMP-MEETING-STORE`（≤400）。账号/文件夹拆分仍另立 '
    '`W-REFACTOR-02`，本批不夹带。')

replace_line('doc/design/components/CMP-SCN-READ/spec.md',
    '- 尺寸预算：≤800 行；',
    '- 尺寸预算：`Scenes` 组件 ≤1200 行（2026-11-24 D1 确认，取代此前的 800 行历史值）；当前 **923 行**（2026-11-24 `wc -l`），'
    '`HTMLText`/`InlineImageHTML` 已迁 `CMP-HTML`（391 行），`ReadScene.swift` 244。')

replace_line('doc/design/components/CMP-PRES/spec.md',
    '- 尺寸预算：单文件 ≤400 行；当前（2026-11-20 实测）',
    '- 尺寸预算：单文件 ≤400 行；当前（2026-11-24 实测）`MailboxViewModel` **366**、`MailboxViewModel+List` 69、'
    '`CalendarViewModel` **172**、`CalendarProjection` **254**、`ReaderViewModel` 223、`ReaderRouter` 120、`ComposeViewModel` 284；'
    '`Presentation` 共 **2721** 行。2026-11-24 预算拆分后所有单文件 ≤400（此前 `MailboxViewModel` 424、`CalendarViewModel` 424）。')

replace_line('doc/design/components/CMP-EAS/spec.md',
    '- 尺寸预算：≤1500 行；',
    '- 尺寸预算：≤1500 行；当前 **1150 行**（`EASClient.swift` 1065 + `URLSessionTransport.swift` 85，2026-11-24 `wc -l`）。'
    '`WBXML.swift`（363 行）已于 2026-11-24 析出到 `CMP-WBXML`（同 target、独立测试），本组件此前 1513 行超 1500。')

replace_line('doc/design/components/CMP-DOMAIN/spec.md',
    '- 尺寸预算：目标 ≤800 行；',
    '- 尺寸预算：目标 ≤800 行；**当前 1503 行已超**（2026-11-24 `wc -l`：`Meeting.swift` 682 + 其它 821；会议值类型 2026-11-24 P1 '
    '加入后未重新定预算）。是否拆出会议契约或上调预算需另行拍板（`plan/risks.md` R77），本批不静默调预算、不做拆分。')

# ---------- architecture ----------
p = 'doc/design/architecture.md'
s = open(p, encoding='utf-8').read()
s = s.replace('9 个库 target + 2 个可执行 target', '10 个库 target + 2 个可执行 target', 1)

s = s.replace(
    '| `MailDomain` | L1 | Foundation | `Sources/MailDomain/{Values,Ports,Errors,Configuration}.swift` |',
    '| `MailDomain` | L1 | Foundation | `Sources/MailDomain/{Values,Ports,Errors,Configuration}.swift` |\n'
    '| `HTMLSupport` | L1 工具 | `MailDomain` | `Sources/HTMLSupport/{HTMLText,InlineImageHTML}.swift`（2026-11-24 从 `Scenes` 析出，CMP-HTML） |',
    1)
s = s.replace(
    '`Sources/MailStore/MailStore.swift#MailStore`、`OutboxStore.swift#OutboxStore`（2026-11-24 起 outbox 表读写） |',
    '`Sources/MailStore/MailStore.swift#MailStore`、`OutboxStore.swift#OutboxStore`（outbox 表读写）、'
    '`MeetingStore+{Read,Write}.swift`（meetings 表读写，CMP-MEETING-STORE） |', 1)
s = s.replace(
    '`Sources/EASClient/EASClient.swift#EASClient`、`WBXML.swift#WBXML` |',
    '`Sources/EASClient/EASClient.swift#EASClient`、`WBXML.swift#WBXML`（CMP-WBXML） |', 1)

s = s.replace(
    '| `CMP-DOMAIN` | `design/components/CMP-DOMAIN/spec.md` | L1 契约 |',
    '| `CMP-DOMAIN` | `design/components/CMP-DOMAIN/spec.md` | L1 契约 |\n'
    '| `CMP-HTML` | `design/components/CMP-HTML/spec.md` | L1 工具（纯函数） |\n'
    '| `CMP-WBXML` | `design/components/CMP-WBXML/spec.md` | L0 工具（编解码） |', 1)
s = s.replace(
    '| `CMP-OUTBOX-STORE` | `design/components/CMP-OUTBOX-STORE/spec.md` | L1a 数据（outbox 表） |',
    '| `CMP-OUTBOX-STORE` | `design/components/CMP-OUTBOX-STORE/spec.md` | L1a 数据（outbox 表） |\n'
    '| `CMP-MEETING-STORE` | `design/components/CMP-MEETING-STORE/spec.md` | L1a 数据（meetings 表） |', 1)

s = s.replace(
    '| `Presentation` | 1 | ≤3 | 只依赖 `Scenes`（与 `MailDomain` 值类型） |',
    '| `Scenes` | 5 | ≤8 | `MailDomain`、`MailStore`、`SyncEngine`、`Outbox`、`HTMLSupport`；单个场景仍 1–3（≤5） |\n'
    '| `Presentation` | 2 | ≤3 | `Scenes` + `HTMLSupport`（与 `MailDomain` 值类型） |\n'
    '| `HTMLSupport` | 1 | ≤5 | 只依赖 `MailDomain` 的 `Attachment` 值类型 |', 1)

s = s.replace(
    '- `./Scripts/swiftw test` → **437 tests / 71 suites**（2026-11-24，W-M3-16 完成后复测）。',
    '- `./Scripts/swiftw test` → **460 tests / 77 suites**（2026-11-24，W-M3-17 完成后复测）。', 1)
s = s.replace(
    '- 测试 target：`MailDomainTests`、`MailStoreTests`、`SyncEngineTests`、`OutboxTests`、`EASClientTests`、`EASAdapterTests`、`ScenesTests`、`PresentationTests`、`CompositionTests`。',
    '- 测试 target：`MailDomainTests`、`HTMLSupportTests`、`MailStoreTests`、`SyncEngineTests`、`OutboxTests`、`EASClientTests`、'
    '`EASAdapterTests`、`ScenesTests`、`PresentationTests`、`CompositionTests`。', 1)

s = s.replace(
    '12. **`Scenes` 组件超过 800 行历史预算**（2026-11-20 实测 1006；本设计 +约 170）：属既有超出，本设计登记不静默调预算；'
    'task-split 须写上限（本批新增 ≤170 行）与拆分触发（再改 `Scenes` 使其 >1200 行，或出现第二个 HTML 纯工具时，另立 P1 任务拆 '
    '`HTMLText`/`InlineImageHTML` 到纯工具组件）。',
    '12. **`Scenes` 预算已按 2026-11-24 D1 处理**：`HTMLText`/`InlineImageHTML` 拆到 `CMP-HTML`（新 target `HTMLSupport`，391 行），'
    '`Scenes` 现 **923/1200**；`ReadScene` 的按引用读取与时间窗读取未增 target。', 1)
open(p, 'w', encoding='utf-8').write(s)

# ---------- risks ----------
p = 'doc/plan/risks.md'
s = open(p, encoding='utf-8').read()

def patch_row(risk_id, trigger_prefix, note_col=None, note_suffix='', expected=9):
    global s
    i = s.index('| %s |' % risk_id)
    j = s.index('\n', i)
    cells = s[i:j].split('|')
    assert len(cells) == expected, (risk_id, len(cells))
    cells[3] = cells[3].rstrip() + trigger_prefix
    if note_col is not None and note_suffix:
        cells[note_col] = cells[note_col].rstrip() + note_suffix
    s = s[:i] + '|'.join(cells) + s[j:]

patch_row('R45', ' **已关闭（2026-11-24）**：`CMP-STORE` 现 **952/1000**（`meetings` 析出到 `CMP-MEETING-STORE` 287 行）。',
          5, ' 拆分记录见 `W-REFACTOR-03`。')
patch_row('R70', ' **已关闭（2026-11-24）**：`MailboxViewModel` 现 **366/400**（列表加载/选中拆到 `MailboxViewModel+List.swift` 69 行）。',
          5, '')
patch_row('R72', ' **已关闭（2026-11-24）**：`Scenes` 现 **923/1200**（`HTMLText`/`InlineImageHTML` 拆到 `CMP-HTML`，新 target `HTMLSupport`）。',
          5, '')

# new R77 after R73 row
i = s.index('| R73 |')
j = s.index('\n', i)
row = ('\n| R77 | `MailDomain` **1503/800 目标**（`Meeting.swift` 682 + 其它 821，2026-11-24 `wc -l`） | '
       '会议值类型 2026-11-24 P1 加入后未重估预算 | 平台契约组件继续增长，契约评审与装载成本上升 | '
       '**另立 P1 决定**：拆会议契约到独立组件，或经人工上调目标；本批只登记与实测，不静默调预算 | '
       '`CMP-DOMAIN/spec.md` 预算节、`plan/roadmap.md` |')
s = s[:j] + row + s[j:]

old = '- 2026-11-24（W-M3-17 实现，`T-1124-17`…`T-1124-21`）：'
entry = ('- 2026-11-24（W-REFACTOR-03 预算拆分）：R45 关闭（`CMP-STORE` 952/1000，`meetings` → `CMP-MEETING-STORE`）；'
         'R70 关闭（`MailboxViewModel` 366/400）；R72 关闭（`Scenes` 923/1200，`HTMLText`/`InlineImageHTML` → `CMP-HTML`）；'
         '`CMP-EAS` 1513→1150/1500（`WBXML` → `CMP-WBXML`）；`CMP-APP` 各文件 ≤300（2026-11-24 实测最大 293）；'
         '新增 R77（`MailDomain` 1503/800 目标，待 P1 决定）。\n')
assert s.count(old) == 1
s = s.replace(old, entry + old, 1)
open(p, 'w', encoding='utf-8').write(s)

# ---------- roadmap ----------
p = 'doc/plan/roadmap.md'
s = open(p, encoding='utf-8').read()
anchor = '| W-REFACTOR-02 账号与文件夹存储拆分 | —（结构） |'
i = s.index(anchor)
row = ('| W-REFACTOR-03 预算拆分（R45/R70/R71/R72） | —（结构） | W-M3-17；D1 拍板「不上调预算，先拆分」 | '
       'CMP-HTML（新 target `HTMLSupport`）、CMP-MEETING-STORE、CMP-WBXML、CMP-PRES、CMP-APP | '
       '已完成（2026-11-24）：`Scenes` 1306→923（新组件 `CMP-HTML` 391）；`CMP-STORE` 1225→952（新组件 `CMP-MEETING-STORE` 287）；'
       '`CMP-EAS` 1513→1150（新组件 `CMP-WBXML` 363）；`MailboxViewModel` 424→366、`CalendarViewModel` 424→172（+`CalendarProjection` 254）；'
       '`CMP-APP` 各文件 ≤300；`MailDomain` 1503/800 目标未处理，登记 R77；460 tests / 77 suites、架构 4/4、`make-app.sh` 成功 |\n')
s = s[:i] + row + s[i:]

anchor2 = '## 批次纪律'
i2 = s.index(anchor2)
section = '''## W-REFACTOR-03 预算拆分（2026-11-24 完成）

来源：`history/decisions/2026-11-24-risk-review-decisions.md` D1（「不上调预算，先拆分」）。

| 组件 | 拆前 | 拆后 | 处理 |
|---|---|---|---|
| `Scenes` | 1306/1200 | **923** | `HTMLText`（221）+ `InlineImageHTML`（170）迁新 target `HTMLSupport` → 新组件 `CMP-HTML`（391，≤420）；`Scenes`/`Presentation` 各加 `import HTMLSupport` |
| `CMP-STORE` | 1225/1000 | **952** | `MailStore+Meetings.swift`（273）拆为 `MeetingStore+Read.swift` 140 + `MeetingStore+Write.swift` 147，归新组件 `CMP-MEETING-STORE`（287，≤400） |
| `CMP-EAS` | 1513/1500 | **1150** | `WBXML.swift`（363）析出为 `CMP-WBXML`（同 target、独立测试） |
| `CMP-PRES` | `MailboxViewModel` 424、`CalendarViewModel` 424 | **366 / 172** | 新增 `MailboxViewModel+List.swift`（69，列表加载与选中）与 `CalendarProjection.swift`（254，纯网格数学）；`messages`/`folders` 的 setter 由 `private(set)` 放宽为 `internal(set)` 供同模块扩展写 |
| `CMP-APP` | `MailboxView` 305 | **291**（`CalendarView` 292） | 已在 W-M3-17 期间由 `MessageRowView` / `MailboxView+Reader` / `CalendarBlocks` 拆出 |
| `MailDomain` | 1503/800 目标 | 未处理 | 会议值类型 P1 后目标未重估：登记 `R77`，另立 P1 决定拆契约或上调 |

**验证**：`./Scripts/swiftw test` **460 tests / 77 suites**；`bash Scripts/check-architecture.sh` 4/4（新增 target 已进 import 白名单）；
`./Scripts/make-app.sh` 成功。**未做**：`MailDomain` 拆分/预算重估（R77）。

'''
s = s[:i2] + section + s[i2:]

old_tail = '场景分析 `task-spaces/20261124-152611/scenario-analysis.md`'
# append a sentence at the end of the narrative line 12
line_end = s.index('\n', s.index('首版范围已于 2026-11-09 确认'))
line = s[:line_end]
line += ('2026-11-24 另立 W-REFACTOR-03 并完成（D1 预算拆分）：`Scenes` 1306→923（新组件 `CMP-HTML`/target `HTMLSupport`）、'
         '`CMP-STORE` 1225→952（新组件 `CMP-MEETING-STORE`）、`CMP-EAS` 1513→1150（新组件 `CMP-WBXML`）、'
         '`MailboxViewModel`/`CalendarViewModel` 424→366/172；`MailDomain` 1503/800 目标未处理，登记 R77；'
         '460 tests / 77 suites、架构 4/4、`make-app.sh` 成功。')
s = line + s[line_end:]
open(p, 'w', encoding='utf-8').write(s)

# ---------- README ----------
p = 'doc/README.md'
s = open(p, encoding='utf-8').read()
s = s.rstrip() + '\n\n' + ('2026-11-24 完成预算拆分（W-REFACTOR-03，按 D1「不上调预算」）：`Scenes` 拆出 `HTMLText`/`InlineImageHTML` 到新组件 `CMP-HTML`'
    '（新 target `HTMLSupport`，391 行），`Scenes` 1306→923；`CMP-STORE` 的 meetings 读写拆为 `CMP-MEETING-STORE`（287 行），'
    '`CMP-STORE` 1225→952；`CMP-EAS` 的 `WBXML` 析出为 `CMP-WBXML`（363 行），`CMP-EAS` 1513→1150；'
    '`MailboxViewModel` 424→366、`CalendarViewModel` 424→172（新增 `MailboxViewModel+List` 与 `CalendarProjection`）；'
    '`CMP-APP` 各文件 ≤300。`MailDomain` 1503 行仍超 800 目标，登记 R77 待 P1 决定。验证：460 tests / 77 suites、架构 4/4、`make-app.sh` 成功。\n')
open(p, 'w', encoding='utf-8').write(s)

print('docs updated')
