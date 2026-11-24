import io

# --- SCN-0024: delayed selection note + refreshed evidence -------------------
p = 'doc/design/scenarios/calendar/browse/calendar-grid/scenario.md'
s = open(p, encoding='utf-8').read()
old = '- 单击：块进入选中态（月/周同一时刻只有一个选中）；Esc 取消选中。旧详情 sheet 删除。'
new = ('- 单击：0.28s 判定窗口后进入选中态（决策 D5，避免双击前闪一下选中）；月/周同一时刻只有一个选中；'
       'Esc 取消选中。旧详情 sheet 删除。双击会取消待生效的选中并直接打开。')
assert old in s
s = s.replace(old, new)
old = ('- 增量证据（L2）：`task-spaces/20261124-152611/evidence/calendar-click/calendar-click.txt`——生产 `CalendarSelection.swift`\n'
       '  的点击捕获被 `hitTest` 命中，`clickCount=1` 只选中、`1,2` 选中+打开。')
new = ('- 增量证据（L2）：`task-spaces/20261124-152611/evidence/calendar-click/calendar-click.txt`——生产 `CalendarSelection.swift`\n'
       '  的点击捕获被 `hitTest` 命中；`clickCount=1` 立即不选中、延迟 0.28s 后选中 1 次；`1,2` 取消选中并只打开 1 次。')
assert old in s
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)

# --- risks: R68 implementation note ----------------------------------------
p = 'doc/plan/risks.md'
s = open(p, encoding='utf-8').read()
i = s.index('| R68 |')
j = s.index('\n', i)
row = s[i:j]
cells = row.split('|')
assert len(cells) == 8, (len(cells), cells)
cells[3] = cells[3].rstrip() + (' **已实现（2026-11-24）**：`ClickCatcherView` 单次单击延迟 0.28s 判定，双击取消待生效选中；'
                                '探针 `evidence/calendar-click/calendar-click.txt`（立即 0 → 延迟后 1；1,2 → 选中 0/打开 1）。')
s = s[:i] + '|'.join(cells) + s[j:]
open(p, 'w', encoding='utf-8').write(s)

# --- roadmap: note the prerequisite status inside the sequencing section ----
p = 'doc/plan/roadmap.md'
s = open(p, encoding='utf-8').read()
old = ('2. **R21 修复**：`applyDelta` 的 `subject`/`sender`/`received_raw` 补 `COALESCE` + L1，先于 W-M3-17。\n'
       '3. 已开工的 `T-1124-17`/`T-1124-19` 若与本顺序冲突，**暂停并重排**；不把未拆分状态带进 `T-1124-20`。')
new = ('2. **R21 修复**：**已完成（2026-11-24）**——`applyDelta` 的 `subject`/`sender`/`received_raw` 改为 `COALESCE`，'
       '新增 L1 `partialReadChangeKeepsEnvelope`（只带 `Read` 的 Change 不清空信封）。\n'
       '3. 已开工的 `T-1124-17`/`T-1124-19` 若与本顺序冲突，**暂停并重排**；不把未拆分状态带进 `T-1124-20`。'
       '**现状（2026-11-24）**：并行会话已完成 `T-1124-17`…`T-1124-21` 的代码与验收（460 tests / 77 suites、架构 4/4），'
       '但第 1 条预算拆分工序**尚未开工**——`Scenes` 1306+、`CMP-STORE` 1152、`CMP-PRES` 424/400 仍超预算；'
       '实现先于拆分落地是本批遗留的顺序偏差，须在下一批按第 1 条补齐，不得把「已实现」当作拆分豁免。')
assert old in s
s = s.replace(old, new)
old = ('- **R68**：单击延迟 250–300ms 判定（决策 D5）。现有 `Sources/uumail/CalendarSelection.swift` 的 `clickCount` 立即选中需改；\n'
       '  点击探针只证明事件可达，不证明最终交互形态。若实现成本过高，回设计重开 D9，不静默沿用「闪一下」。')
new = ('- **R68**：单击延迟 250–300ms 判定（决策 D5）。**已实现（2026-11-24）**：`CalendarSelection.swift` 的 `ClickCatcherView`\n'
       '  改为 0.28s 延迟选中、双击取消待生效选中；点击探针已按新行为重跑（`evidence/calendar-click/calendar-click.txt`）。')
assert old in s
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)

print('docs updated')
