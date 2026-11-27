import Foundation
import MailDomain
import SyncContract

/// One draft sync pass: pull server drafts into the local list, push local-only drafts and
/// local edits, then flush pending server deletes (REQ-0044).
public struct DraftSyncReport: Equatable, Sendable {
    public var downloaded = 0
    public var uploaded = 0
    public var updated = 0
    public var deleted = 0
    public var conflicts = 0

    public init() {}
}

extension SyncEngine {
    /// Pulls the server Drafts folder, merges it into the local draft rows, then pushes the
    /// local side back. Conflict rule (human confirmed 2026-11-27): keep both — the bound
    /// row takes the server version and the user's version is copied to a fresh local-only
    /// row, which the push step uploads as the second server draft.
    public func syncDraftsOnce() async throws -> DraftSyncReport? {
        guard let draftStore else { return nil }
        try await acquire()
        defer { release() }
        if Task.isCancelled { throw CancellationError() }
        do {
            try await gateway.provisionIfNeeded()
            let folders = try await refreshFolders()
            guard let folder = folders.first(where: { $0.isDrafts }) else { return nil }
            var report = DraftSyncReport()
            try await pullDrafts(folder: folder, into: draftStore, report: &report)
            try await pushDrafts(folder: folder, store: draftStore, report: &report)
            state = .idle
            consecutiveFailures = 0
            return report
        } catch {
            throw recordFailure(error)
        }
    }

    // MARK: - Pull

    private func pullDrafts(
        folder: Folder, into store: any DraftSyncStore, report: inout DraftSyncReport
    ) async throws {
        let key = try store.syncKey(account: account, collection: folder.serverID) ?? "0"
        let delta = try await gateway.fetchMessages(
            collectionID: folder.serverID, syncKey: key, window: 50, filterType: filterType
        )
        for message in delta.added + delta.changed {
            guard let fetched = try? await gateway.fetchBody(
                collectionID: folder.serverID, serverID: message.serverID
            ) else { continue }
            let html = Self.htmlBody(fetched)
            let draft = Draft(
                to: message.recipients ?? "",
                cc: message.cc,
                subject: message.subject ?? "",
                body: fetched.text,
                isDraft: true,
                bodyHTML: html
            )
            let updatedAt = Self.date(message.receivedRaw) ?? Date()
            let hash = Self.hash(draft, updatedAt: updatedAt)
            if let existing = try store.draft(account: account, serverID: message.serverID) {
                let localChanged = existing.draftHash != existing.fingerprint
                let serverChanged = existing.draftHash != hash
                if !localChanged && !serverChanged { continue }
                if localChanged && serverChanged {
                    // Keep both: the user's text moves to a new local-only row and the
                    // original adopts the server version.
                    _ = try store.duplicateDraft(account: account, draftID: existing.id)
                    report.conflicts += 1
                }
                if serverChanged {
                    try store.adoptServerDraft(
                        account: account, draftID: existing.id, draft: draft,
                        updatedAt: updatedAt, hash: hash
                    )
                    report.downloaded += 1
                }
            } else {
                try store.insertServerDraft(
                    account: account, serverID: message.serverID, draft: draft,
                    updatedAt: updatedAt, hash: hash
                )
                report.downloaded += 1
            }
        }
        for serverID in delta.removedServerIDs {
            if let existing = try store.draft(account: account, serverID: serverID) {
                if existing.draftHash == existing.fingerprint {
                    // Local side clean: the server delete wins.
                    try store.deleteDraft(account: account, draftID: existing.id)
                } else {
                    // Local side changed: keep the text as a local-only draft (re-uploaded).
                    try store.unbindDraft(account: account, draftID: existing.id)
                }
                report.deleted += 1
            }
            try store.removeDraftTombstone(account: account, serverID: serverID)
        }
        try store.setSyncKey(account: account, collection: folder.serverID, key: delta.syncKey)
    }

    // MARK: - Push

    private func pushDrafts(
        folder: Folder, store: any DraftSyncStore, report: inout DraftSyncReport
    ) async throws {
        var key = try store.syncKey(account: account, collection: folder.serverID) ?? "0"

        for record in try store.unboundDrafts(account: account) {
            let result = try await writeGateway.createDraft(
                Self.payload(record),
                collectionID: folder.serverID, syncKey: key, clientID: record.id
            )
            guard let serverID = result.serverID else {
                throw MailError.unsupported
            }
            try store.bindDraft(
                account: account, draftID: record.id, serverID: serverID,
                hash: record.fingerprint
            )
            key = result.syncKey
            try store.setSyncKey(account: account, collection: folder.serverID, key: key)
            report.uploaded += 1
        }

        for record in try store.draftsNeedingUpload(account: account) {
            guard let serverID = record.serverID else { continue }
            let result = try await writeGateway.updateDraft(
                serverID: serverID, payload: Self.payload(record),
                collectionID: folder.serverID, syncKey: key
            )
            try store.setDraftHash(account: account, draftID: record.id, hash: record.fingerprint)
            key = result.syncKey
            try store.setSyncKey(account: account, collection: folder.serverID, key: key)
            report.updated += 1
        }

        for serverID in try store.draftTombstones(account: account) {
            let result = try await writeGateway.deleteDraft(
                serverID: serverID, collectionID: folder.serverID, syncKey: key
            )
            try store.removeDraftTombstone(account: account, serverID: serverID)
            key = result.syncKey
            try store.setSyncKey(account: account, collection: folder.serverID, key: key)
            report.deleted += 1
        }
    }

    // MARK: - Helpers

    private static func payload(_ record: DraftRecord) -> DraftPayload {
        DraftPayload(
            to: record.to,
            cc: record.cc,
            subject: record.subject,
            bodyHTML: record.bodyHTML ?? htmlFromPlain(record.body)
        )
    }

    private static func hash(_ draft: Draft, updatedAt: Date) -> String {
        DraftRecord(
            id: "", to: draft.to, cc: draft.cc, subject: draft.subject,
            body: draft.body, bodyHTML: draft.bodyHTML, updatedAt: updatedAt
        ).fingerprint
    }

    /// Server bodies arrive as HTML (type 2) or plain text (type 1); plain text is wrapped
    /// so the draft editor always reopens an HTML document.
    private static func htmlBody(_ body: FetchedBody) -> String {
        body.isHTML ? body.text : "<div>\(escape(body.text))</div>"
    }

    private static func htmlFromPlain(_ text: String) -> String {
        "<div>\(escape(text))</div>"
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
