import Foundation
import MailDomain
import SyncContract

/// `MailStore` is the `DraftSyncStore` implementation (REQ-0044). Draft rows live in
/// `OutboxStore`; this file is only the protocol glue, mirroring `SyncStoreConformance`.
extension MailStore: DraftSyncStore {
    public func drafts(account id: AccountID) throws -> [DraftRecord] {
        try outbox.drafts(account: id)
    }

    public func draft(account id: AccountID, draftID: String) throws -> DraftRecord? {
        try outbox.draft(account: id, draftID: draftID)
    }

    public func draft(account id: AccountID, serverID: String) throws -> DraftRecord? {
        try outbox.draft(account: id, serverID: serverID)
    }

    public func unboundDrafts(account id: AccountID) throws -> [DraftRecord] {
        try outbox.unboundDrafts(account: id)
    }

    public func draftsNeedingUpload(account id: AccountID) throws -> [DraftRecord] {
        try outbox.draftsNeedingUpload(account: id)
    }

    public func bindDraft(account id: AccountID, draftID: String, serverID: String, hash: String) throws {
        try outbox.bindDraft(account: id, draftID: draftID, serverID: serverID, hash: hash)
    }

    public func setDraftHash(account id: AccountID, draftID: String, hash: String) throws {
        try outbox.setDraftHash(account: id, draftID: draftID, hash: hash)
    }

    public func adoptServerDraft(
        account id: AccountID, draftID: String, draft: Draft, updatedAt: Date, hash: String
    ) throws {
        try outbox.adoptServerDraft(
            account: id, draftID: draftID, draft: draft, updatedAt: updatedAt, hash: hash
        )
    }

    public func insertServerDraft(
        account id: AccountID, serverID: String, draft: Draft, updatedAt: Date, hash: String
    ) throws {
        try outbox.insertServerDraft(
            account: id, serverID: serverID, draft: draft, updatedAt: updatedAt, hash: hash
        )
    }

    public func duplicateDraft(account id: AccountID, draftID: String) throws -> String {
        try outbox.duplicateDraft(account: id, draftID: draftID)
    }

    public func unbindDraft(account id: AccountID, draftID: String) throws {
        try outbox.unbindDraft(account: id, draftID: draftID)
    }

    public func deleteDraft(account id: AccountID, draftID: String) throws {
        _ = try outbox.deleteDraft(account: id, draftID: draftID)
    }

    public func addDraftTombstone(account id: AccountID, serverID: String) throws {
        try outbox.addDraftTombstone(account: id, serverID: serverID)
    }

    public func draftTombstones(account id: AccountID) throws -> [String] {
        try outbox.draftTombstones(account: id)
    }

    public func removeDraftTombstone(account id: AccountID, serverID: String) throws {
        try outbox.removeDraftTombstone(account: id, serverID: serverID)
    }
}
