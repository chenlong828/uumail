import re

def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert old in s, (path, old[:60])
        s = s.replace(old, new, 1)
    open(path, 'w', encoding='utf-8').write(s)

# 1) SyncContract: a batch carries meetings (keyed to their source message)
edit('Sources/SyncContract/SyncContract.swift', [
("""public struct MessageDelta: Equatable, Sendable {
    public var added: [Message]
    public var changed: [Message]
    public var removedServerIDs: [String]
    public var syncKey: String
    public var moreAvailable: Bool

    public init(
        added: [Message],
        changed: [Message],
        removedServerIDs: [String],
        syncKey: String,
        moreAvailable: Bool
    ) {
        self.added = added
        self.changed = changed
        self.removedServerIDs = removedServerIDs
        self.syncKey = syncKey
        self.moreAvailable = moreAvailable
    }
}""",
"""public struct MessageDelta: Equatable, Sendable {
    public var added: [Message]
    public var changed: [Message]
    public var removedServerIDs: [String]
    public var syncKey: String
    public var moreAvailable: Bool
    /// Meeting requests parsed from the same response. They travel with the batch so the
    /// store can write messages and meetings in one transaction; `Message` itself stays
    /// free of meeting values (2026-11-24 P1, R77).
    public var meetings: [MeetingDeltaEntry]

    public init(
        added: [Message],
        changed: [Message],
        removedServerIDs: [String],
        syncKey: String,
        moreAvailable: Bool,
        meetings: [MeetingDeltaEntry] = []
    ) {
        self.added = added
        self.changed = changed
        self.removedServerIDs = removedServerIDs
        self.syncKey = syncKey
        self.moreAvailable = moreAvailable
        self.meetings = meetings
    }
}

/// One meeting carried by a sync batch, tied to the message that produced it.
public struct MeetingDeltaEntry: Equatable, Sendable {
    public var serverID: String
    /// Envelope subject, used when the invite itself has none.
    public var subject: String?
    public var invite: MeetingInvite

    public init(serverID: String, subject: String?, invite: MeetingInvite) {
        self.serverID = serverID
        self.subject = subject
        self.invite = invite
    }
}"""),
])

# 2) Message no longer carries a meeting
edit('Sources/MailDomain/Values.swift', [
('import Foundation\nimport MeetingDomain\n', 'import Foundation\n'),
("""    public var attachments: [Attachment]
    /// Present when the message is a meeting request (REQ-0029 / REQ-0030).
    public var meeting: MeetingInvite?
""",
"""    public var attachments: [Attachment]
"""),
("""        attachments: [Attachment] = [],
        cc: String? = nil,
        meeting: MeetingInvite? = nil
    ) {""",
"""        attachments: [Attachment] = [],
        cc: String? = nil
    ) {"""),
("""        self.cc = cc
        self.meeting = meeting
""",
"""        self.cc = cc
"""),
])

# 3) Adapter: keep meeting values in the batch, not in Message
edit('Sources/EASAdapter/EASAdapter.swift', [
("""    private static func delta(_ result: SyncResult) -> MessageDelta {
        MessageDelta(
            added: result.added.map(Self.message),
            changed: result.changed.map(Self.message),
            removedServerIDs: result.removedServerIDs,
            syncKey: result.syncKey,
            moreAvailable: result.moreAvailable
        )
    }""",
"""    private static func delta(_ result: SyncResult) -> MessageDelta {
        let meetings = (result.added + result.changed).compactMap { message -> MeetingDeltaEntry? in
            guard let invite = meeting(message) else { return nil }
            return MeetingDeltaEntry(serverID: message.serverID, subject: message.subject, invite: invite)
        }
        return MessageDelta(
            added: result.added.map(Self.message),
            changed: result.changed.map(Self.message),
            removedServerIDs: result.removedServerIDs,
            syncKey: result.syncKey,
            moreAvailable: result.moreAvailable,
            meetings: meetings
        )
    }"""),
("""            cc: message.cc,
            meeting: meeting(message)
        )""",
"""            cc: message.cc
        )"""),
])

# 4) Store: seed/batch API gains meetings; applyDelta writes them in the same transaction
edit('Sources/MailStore/MailStore.swift', [
("""    public func applySyncBatch(
        account id: AccountID,
        folder folderID: String,
        added: [MailMessage],
        changed: [MailMessage],
        removedServerIDs: [String],
        syncKey: String
    ) throws {
        let delta = MessageDelta(
            added: added,
            changed: changed,
            removedServerIDs: removedServerIDs,
            syncKey: syncKey,
            moreAvailable: false
        )""",
"""    public func applySyncBatch(
        account id: AccountID,
        folder folderID: String,
        added: [MailMessage],
        changed: [MailMessage],
        removedServerIDs: [String],
        syncKey: String,
        meetings: [MeetingDeltaEntry] = []
    ) throws {
        let delta = MessageDelta(
            added: added,
            changed: changed,
            removedServerIDs: removedServerIDs,
            syncKey: syncKey,
            moreAvailable: false,
            meetings: meetings
        )"""),
("""            try Self.reindexMessage(db, account: id, folder: folderID, serverID: message.serverID)
            try upsertMeeting(db, account: id, folder: folderID, message: message, now: now)
        }""",
"""            try Self.reindexMessage(db, account: id, folder: folderID, serverID: message.serverID)
        }

        for entry in delta.meetings {
            try upsertMeeting(
                db, account: id, folder: folderID,
                serverID: entry.serverID, subject: entry.subject, invite: entry.invite, now: now
            )
        }"""),
('            return try attachMeetings(db, account: id, messages: page)', '            return page'),
('                return try attachMeetings(db, account: id, messages: page)', '                return page'),
])

edit('Sources/MailStore/MailStore+Lookup.swift', [
('            return try attachMeetings(db, account: id, messages: [message]).first',
 '            return message'),
('            return try attachMeetings(db, account: id, messages: rows.map(Self.storedMessage(from:)))',
 '            return rows.map(Self.storedMessage(from:))'),
])

# 5) upsertMeeting takes the invite + its source key instead of a Message
edit('Sources/MailStore/MeetingStore+Write.swift', [
("""    func upsertMeeting(
        _ db: Database,
        account id: AccountID,
        folder folderID: String,
        message: Message,
        now: Double
    ) throws {
        guard let invite = message.meeting, !invite.uid.isEmpty else { return }
""",
"""    func upsertMeeting(
        _ db: Database,
        account id: AccountID,
        folder folderID: String,
        serverID: String,
        subject: String?,
        invite: MeetingInvite,
        now: Double
    ) throws {
        guard !invite.uid.isEmpty else { return }
"""),
("""                db, account: id, folder: existing.exceptions.isEmpty ? folderID : folderID,
                serverID: message.serverID, subject: invite.subject ?? message.subject,
                invite: existing, now: now""",
"""                db, account: id, folder: folderID,
                serverID: serverID, subject: invite.subject ?? subject,
                invite: existing, now: now"""),
("""                id.raw, invite.uid, folderID, message.serverID, invite.subject ?? message.subject,""",
"""                id.raw, invite.uid, folderID, serverID, invite.subject ?? subject,"""),
])

# 6) Read side: drop the decoration, expose one meeting by message key
p = 'Sources/MailStore/MeetingStore+Read.swift'
s = open(p, encoding='utf-8').read()
start = s.index('    func attachMeetings(')
end = s.index('\n    }\n', start) + len('\n    }\n')
s = s[:start] + s[end:]
addition = '''    /// The meeting request attached to one message, if any. Used by the reading pane
    /// instead of decorating every list row (R77).
    public func meeting(account id: AccountID, folder folderID: String, serverID: String) throws -> MeetingInvite? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM meetings
                    WHERE account_id = ? AND folder_id = ? AND server_id = ?
                      AND is_cancelled = 0 AND message_type <> 4
                    LIMIT 1
                    """,
                arguments: [id.raw, folderID, serverID]
            ) else { return nil }
            return try? Self.decodeMeeting(row)
        }
    }
'''
s = s.rstrip() + '\n\n' + addition + '}\n'
open(p, 'w', encoding='utf-8').write(s)

# 7) Scene read API for the meeting card
edit('Sources/Scenes/ReadScene.swift', [
("""    public func attachments(for ref: MessageRef) throws -> [Attachment] {""",
"""    /// The meeting request carried by this message, if it is an invite (R77).
    public func meeting(for ref: MessageRef) throws -> MeetingInvite? {
        try store.meeting(account: account, folder: ref.folderID, serverID: ref.serverID)
    }

    public func attachments(for ref: MessageRef) throws -> [Attachment] {"""),
])

# 8) Presentation: meeting card comes from the scene, not from Message
edit('Sources/Presentation/MailboxViewModel.swift', [
('import Foundation\n', 'import Foundation\nimport MeetingDomain\n'),
("""    public var meetingCard: MeetingCardPresentation? {
        MeetingCardPresentation.make(from: selectedMessage?.meeting)
    }""",
"""    public var meetingCard: MeetingCardPresentation? {
        MeetingCardPresentation.make(from: meetingInvite)
    }

    /// Meeting request for the selected message; loaded on selection because `Message`
    /// no longer carries meeting values (R77).
    public private(set) var meetingInvite: MeetingInvite?

    func refreshSelectedMeeting() {
        guard let ref = selectedRef else {
            meetingInvite = nil
            return
        }
        meetingInvite = try? read.meeting(for: ref)
    }"""),
])

edit('Sources/Presentation/MailboxViewModel+List.swift', [
("""    func select(_ message: Message, open: Bool) {
        selectedListKey = Self.listKey(for: message)
        selection.messageID = message.serverID
        refreshDwell()""",
"""    func select(_ message: Message, open: Bool) {
        selectedListKey = Self.listKey(for: message)
        selection.messageID = message.serverID
        refreshSelectedMeeting()
        refreshDwell()"""),
("""    func clearSelection() {
        selection.messageID = nil
        selectedListKey = nil""",
"""    func clearSelection() {
        selection.messageID = nil
        selectedListKey = nil
        meetingInvite = nil"""),
])

edit('Sources/Presentation/ReaderViewModel.swift', [
('import Foundation\n', 'import Foundation\nimport MailDomain\nimport MeetingDomain\n'),
('        meetingCard = MeetingCardPresentation.make(from: message.meeting)',
 '        meetingCard = MeetingCardPresentation.make(from: try? read.meeting(for: ref))'),
])

print('stage 3 code applied')
