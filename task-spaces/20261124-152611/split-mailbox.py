p = 'Sources/Presentation/MailboxViewModel.swift'
s = open(p, encoding='utf-8').read()

def cut(start_marker):
    global s
    i = s.index(start_marker)
    j = s.index('\n    }\n', i) + len('\n    }\n')
    block = s[i:j]
    s = s[:i] + s[j:]
    return block

blocks = []
for marker, replacement in [
    ('    private func reloadFolders() throws {', '    func reloadFolders() throws {'),
    ('    func reloadCurrentList(autoSelect: Bool) throws {', None),
    ('    private func select(_ message: Message, open: Bool) {', '    func select(_ message: Message, open: Bool) {'),
    ('    private func clearSelection() {', '    func clearSelection() {'),
    ('    func isHidden(_ message: Message) -> Bool {', None),
]:
    block = cut(marker)
    if replacement:
        block = block.replace(marker, replacement, 1)
    blocks.append(block)

# Tidy the empty space left behind and keep the MARK + failure helper in the main file.
s = s.replace('    // MARK: - Local reads\n\n\n', '    // MARK: - Local reads\n\n')
open(p, 'w', encoding='utf-8').write(s)

header = '''import Foundation
import MailDomain
import Scenes

/// List loading and selection for the mailbox window. Extension-only so
/// `MailboxViewModel.swift` stays inside its 400-line budget (R70).
extension MailboxViewModel {
'''
open('Sources/Presentation/MailboxViewModel+List.swift', 'w', encoding='utf-8').write(
    header + '\n'.join(blocks).rstrip() + '\n}\n'
)
print('mailbox split done')
