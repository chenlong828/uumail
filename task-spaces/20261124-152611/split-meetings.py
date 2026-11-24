p = 'Sources/MailStore/MailStore+Meetings.swift'
lines = open(p, encoding='utf-8').read().split('\n')
# 0-based slices; keep the imports (lines 1-7 => idx 0..6)
header = '\n'.join(lines[0:7])

def block(start, end):
    return '\n'.join(lines[start - 1:end])

write = header + '''

/// Meeting persistence, write side (schema v12). The `meetings` table has exactly one
/// writer: `upsertMeeting`, called from `applyDelta` inside the batch transaction.
extension MailStore {
''' + block(9, 102).rstrip() + '\n\n' + block(197, 217).rstrip() + '\n\n' + block(254, 272).rstrip() + '\n}\n'
open('Sources/MailStore/MeetingStore+Write.swift', 'w', encoding='utf-8').write(write)

read = header + '''

/// Meeting persistence, read side (schema v12). Only reads: list decoration, calendar range
/// queries and the `.ics` source lookup.
extension MailStore {
''' + block(104, 196).rstrip() + '\n\n' + block(218, 253).rstrip() + '\n}\n'
open('Sources/MailStore/MeetingStore+Read.swift', 'w', encoding='utf-8').write(read)
print('split written')
