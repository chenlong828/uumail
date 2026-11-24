p = 'doc/plan/risks.md'
s = open(p, encoding='utf-8').read()

def row_cells(risk_id):
    i = s.index('| %s |' % risk_id)
    j = s.index('\n', i)
    return i, j, s[i:j].split('|')

def patch(risk_id, trigger_col, trigger_prefix, note_col, handling_suffix, expected):
    global s
    i, j, cells = row_cells(risk_id)
    assert len(cells) == expected, (risk_id, len(cells), cells)
    cells[trigger_col] = cells[trigger_col].rstrip() + trigger_prefix
    if handling_suffix:
        cells[note_col] = cells[note_col].rstrip() + handling_suffix
    s = s[:i] + '|'.join(cells) + s[j:]

# §二 处置中 table: '', id, 风险, 触发/现状, 影响, 处置, 落点, '' = 8 cells
patch('R64', 3,
      ' **已设控制（2026-11-24 实现）**：撰写态由 `ReaderRouter` 独占（拒绝替换 + 提示），关窗走 `NSAlert`「放弃这封邮件？」；种子只取本窗 ref。',
      5,
      ' 仍未做自动化 UI 测试；关窗确认框与两份草稿的并发路径留给发布前人工冒烟（`SCN-0025` 失败路径）。', 8)
patch('R65', 3,
      ' **已实现（2026-11-24）**：缺失 ref 给「找不到这封邀请邮件」；正文补拉失败保留占位与重试。',
      5, ' 慢网/断网下的实际观感未在真机验证，仍留监控（`SCN-0024` 失败路径、发布前人工项）。', 8)
patch('R66', 3,
      ' **已设边界（2026-11-24 实现）**：只有 `ReaderWindowView` 阅读态传 `allowRemoteContent: true` 并显示静态提示；主窗口与撰写编辑器不传。',
      5, ' 隐私代价按 D6 接受；若评审否决，回退点只在 `ReaderWindowView` 一处（重开 D6 并改 `SCN-0025` 断言）。', 8)
patch('R67', 3,
      ' **实测通过（2026-11-24）**：5,000 封窗口内数据 `messages(since:)` **0.047s / 5,000 行**（阈值 1s），`PerformanceTests.windowBaseline` 常驻。',
      5, ' 大文件夹滚动体感未做像素探针，登记发布前人工项；若真机超阈值，回设计评估封顶/分页，不静默放宽。', 8)

# §三 已接受 table: '', id, 风险, 接受口径, 落点, '' = 6 cells
patch('R69', 2,
      '；**已实现（2026-11-24）**：打开即本地置读 + 后台回写，失败语义沿用现状',
      0, '', 6)

# §一 待拍板 table: '', id, 风险, 触发/现状, 影响, 选项与代价, 未拍板默认, 落点, '' = 9 cells
patch('R70', 3,
      ' **2026-11-24 实测 424**（本批 +8：窗口加载一处 + 失败回填 helper）。',
      5, '', 9)
patch('R71', 3,
      ' **已关闭（2026-11-24）**：`MailboxView` 292/300（行视图抽到 `MessageRowView`、入口抽到 `MailboxView+Reader.swift`）。',
      5, '', 9)

old = '- 2026-11-24（W-M3-17 设计，`T-1124-16`）：'
assert s.count(old) == 1
entry = ('- 2026-11-24（W-M3-17 实现，`T-1124-17`…`T-1124-21`）：R64/R65/R66 按实现收窄为「已设控制/已实现」并保留监控；'
         'R67 由 5k 实测关闭（0.047s/5,000 行，`PerformanceTests.windowBaseline`）；R69 按已接受实现；'
         'R70 更新为 424/400（本批 +8）；R71 由拆分关闭（`MailboxView` 292/300）。'
         '证据：`task-spaces/20261124-152611/evidence/`、测试输出 `BASELINE window30d-in-window=0.047s rows=5000`。\n')
s = s.replace(old, entry + old, 1)

open(p, 'w', encoding='utf-8').write(s)
print('risks updated')
