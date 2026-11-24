import re

p = 'doc/plan/roadmap.md'
s = open(p, encoding='utf-8').read()

a = '## W-M3-17 任务表（双击浮动阅读窗、就地回复与列表 30 天窗口，2026-11-24 设计完成，待实现）'
b = '## W-M3-17 任务表（双击浮动阅读窗、就地回复与列表 30 天窗口，2026-11-24 已完成）'
assert s.count(a) == 1
s = s.replace(a, b)

for tid in ['T-1124-17', 'T-1124-18', 'T-1124-19', 'T-1124-20', 'T-1124-21']:
    i = s.index('| `%s` |' % tid)
    j = s.index('\n', i)
    row = s[i:j]
    assert '未开工' in row, (tid, row[-90:])
    row = row.replace('未开工（待 D3 结论）', '已完成（2026-11-24）').replace('| 未开工 |', '| 已完成（2026-11-24） |')
    s = s[:i] + row + s[j:]

a = '| W-M3-17 双击浮动阅读窗、就地回复与列表 30 天窗口 | M3 |'
i = s.index(a)
j = s.index('\n', i)
row = s[i:j]
assert '设计完成（2026-11-24）' in row
old_cell = ('设计完成（2026-11-24）：三卡 `accepted`、`SCN-0025`/`SCN-0026` 已建 `designed`、`SCN-0024` 已转 `designed`；'
            '载体探针定 AppKit、日历点击捕获已证；P1 读面已确认、`CMP-ROOT` 零改动；设计走查 '
            '`task-spaces/20261124-152611/design.md`，任务表见 §W-M3-17；待 `T-1124-17` 起实现；定级 P2')
new_cell = ('已完成（2026-11-24）：`T-1124-17`…`T-1124-21` 全部完成；`SCN-0025`/`SCN-0026`/`SCN-0024` 转 `verified`，'
            '三需求 `delivered`；459 tests / 77 suites、架构 4/4、`make-app.sh` 成功；5k 时间窗查询 0.047s；'
            '发布前人工冒烟项（真实拖动/缩放/多屏、撰写关闭确认、日历真实双击）已登记；任务表见 §W-M3-17')
assert old_cell in row
s = s[:i] + row.replace(old_cell, new_cell) + s[j:]

old_tail = ('场景分析 `task-spaces/20261124-152611/scenario-analysis.md`，任务表 `T-1124-16`…`T-1124-21` 见 §W-M3-17，定级 P2。'
            '同日设计完成（`T-1124-16`）：`SCN-0025`/`SCN-0026` 落 `designed`、`SCN-0024` 转 `designed`（去详情、选中、双击/Enter/空格打开）；'
            '窗口载体探针定 **AppKit `NSWindow`**（SwiftUI `Window` 无法在显示前应用计算尺寸），日历用 AppKit 点击捕获判单击/双击；'
            '`CMP-PRES`/`CMP-APP`/`CMP-STORE`/`CMP-SCN-READ` 增量就位，`CMP-ROOT` 零改动；探针证据 '
            '`task-spaces/20261124-152611/probe/`，R63/R68 关闭。')
new_tail = old_tail + ('同日实现并验证（`T-1124-17`…`T-1124-21`）：按引用取单封 + 30 天列表窗口（5k 窗口查询 0.047s）、'
                       '`ReaderViewModel`/`ReaderRouter`、AppKit 浮窗与就地撰写、日历去详情并支持单击选中/双击/Enter/空格；'
                       '`SCN-0025`/`SCN-0026`/`SCN-0024` 转 `verified`、`REQ-0031`/`REQ-0032`/`REQ-0033` 转 `delivered`；'
                       '459 tests / 77 suites、架构 4/4、`make-app.sh` 成功；`uumail` 不得 import `Scenes`/`Observation`，'
                       '因此浮窗用进程内单例 + 字符串入口（见 `CMP-APP` 实现节）。')
assert s.count(old_tail) == 1
s = s.replace(old_tail, new_tail)

open(p, 'w', encoding='utf-8').write(s)
print('roadmap updated')
