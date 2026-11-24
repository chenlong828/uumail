p = 'doc/plan/risks.md'
s = open(p, encoding='utf-8').read()

def patch_row(risk_id, trigger_prefix, note_suffix=''):
    global s
    i = s.index('| %s |' % risk_id)
    j = s.index('\n', i)
    cells = s[i:j].split('|')
    assert len(cells) == 7, (risk_id, len(cells))
    cells[3] = cells[3].rstrip() + trigger_prefix
    if note_suffix:
        cells[4] = cells[4].rstrip() + note_suffix
    s = s[:i] + '|'.join(cells) + s[j:]

patch_row('R45', ' **已关闭（2026-11-24）**：`CMP-STORE` 现 **952/1000**，`meetings` 读写析出到 `CMP-MEETING-STORE`（287 行）。',
          ' 拆分记录见 `plan/roadmap.md` §W-REFACTOR-03。')
patch_row('R70', ' **已关闭（2026-11-24）**：`MailboxViewModel` 现 **366/400**（列表加载与选中拆到 `MailboxViewModel+List.swift`，69 行）。',
          ' 另 `CalendarViewModel` 424→172 + `CalendarProjection` 254。')
patch_row('R72', ' **已关闭（2026-11-24）**：`Scenes` 现 **923/1200**（`HTMLText`/`InlineImageHTML` 拆到 `CMP-HTML`，新 target `HTMLSupport`）。',
          ' `HTMLSupport` 391 行；`Scenes`/`Presentation` 各加一条 `import`。')

i = s.index('| R73 |')
j = s.index('\n', i)
row = ('\n| R77 | `MailDomain` **1503/800 目标**（`Meeting.swift` 682 + 其它 821，2026-11-24 `wc -l`） | '
       '会议值类型 2026-11-24 P1 加入后未重估预算 | 平台契约组件继续增长，契约评审与装载成本上升 | '
       '**另立 P1 决定**：拆会议契约到独立组件，或经人工上调目标；本批只登记与实测，不静默调预算 | '
       '`CMP-DOMAIN/spec.md` 预算节、`plan/roadmap.md` |')
s = s[:j] + row + s[j:]

header = '## 变更记录\n\n'
entry = ('- 2026-11-24（W-REFACTOR-03 预算拆分）：R45 关闭（`CMP-STORE` 952/1000，`meetings` → `CMP-MEETING-STORE`）；'
         'R70 关闭（`MailboxViewModel` 366/400、`CalendarViewModel` 172）；R72 关闭（`Scenes` 923/1200，`HTMLText`/`InlineImageHTML` → `CMP-HTML`）；'
         '`CMP-EAS` 1513→1150/1500（`WBXML` → `CMP-WBXML`，363 行）；`CMP-APP` 各文件 ≤300（实测最大 293）；'
         '新增 R77（`MailDomain` 1503/800 目标，待 P1 决定）。\n')
assert s.count(header) == 1
s = s.replace(header, header + entry, 1)
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
print('risks, roadmap, README updated')
