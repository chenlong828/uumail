import Foundation

/// Top switch sections (REQ-0037): the inbox, Sent Items and the calendar are the only
/// user-reachable mailboxes; the server's default folder list is not rendered.
enum MailboxSection: Hashable {
    case inbox
    case sent
    case calendar
}
