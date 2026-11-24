import re

scenarios = [
    'doc/design/scenarios/mail/read/floating-reader/scenario.md',
    'doc/design/scenarios/mail/receive/list-window/scenario.md',
    'doc/design/scenarios/calendar/browse/calendar-grid/scenario.md',
]
for p in scenarios:
    s = open(p, encoding='utf-8').read()
    assert 'status: designed\n' in s, p
    s = s.replace('status: designed\n', 'status: verified\n', 1)
    open(p, 'w', encoding='utf-8').write(s)

reqs = {
    'doc/requirements/REQ-0031-floating-reader-window.md':
        '- **状态**：`delivered`（2026-11-24 实现并验证：`SCN-0025` verified，460 tests / 77 suites、架构 4/4、`make-app.sh` 成功）',
    'doc/requirements/REQ-0032-calendar-double-click-mail.md':
        '- **状态**：`delivered`（2026-11-24 实现并验证：`SCN-0024` 增量 verified，460 tests / 77 suites、架构 4/4、`make-app.sh` 成功）',
    'doc/requirements/REQ-0033-list-default-30-days.md':
        '- **状态**：`delivered`（2026-11-24 实现并验证：`SCN-0026` verified，5k 窗口查询 0.047s，460 tests / 77 suites、架构 4/4）',
}
for p, line in reqs.items():
    s = open(p, encoding='utf-8').read()
    assert 'status: accepted\n' in s, p
    s = s.replace('status: accepted\n', 'status: delivered\n', 1)
    i = s.index('- **状态**：')
    j = s.index('\n', i)
    s = s[:i] + line + s[j:]
    open(p, 'w', encoding='utf-8').write(s)

print('frontmatter and requirement statuses updated')
