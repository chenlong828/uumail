import Foundation
import Testing

@testable import MailStore

@Suite("MailStore folders and sync state")
struct MailStoreTests {
    private func makeStore() throws -> MailStore {
        try MailStore.inMemory()
    }

    @Test("createAccount returns a usable id")
    func createAccount() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        let account = try #require(try store.account(id))
        #expect(account.displayName == "工作")
        #expect(account.address == "jdoe@corp.test")
    }

    @Test("applyFolderSnapshot stores folders in mailbox order and advances the key")
    func applySnapshot() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(
            account: id,
            folders: [
                MailFolder(serverID: "9", parentID: "0", displayName: "Projects", type: 1),
                MailFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2),
                MailFolder(serverID: "7", parentID: "0", displayName: "Deleted", type: 4),
            ],
            syncKey: "3"
        )
        let folders = try store.folders(account: id)
        // 系统文件夹在前（收件箱/草稿/已发送/已删除），用户文件夹在后
        #expect(folders.map(\.displayName) == ["Inbox", "Deleted", "Projects"])
        #expect(try store.syncKey(account: id, collection: "folders") == "3")
    }

    @Test("re-applying the same snapshot does not duplicate rows")
    func idempotentUpsert() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        let snapshot = [MailFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2)]
        try store.applyFolderSnapshot(account: id, folders: snapshot, syncKey: "1")
        try store.applyFolderSnapshot(account: id, folders: snapshot, syncKey: "2")
        #expect(try store.folders(account: id).count == 1)
        #expect(try store.syncKey(account: id, collection: "folders") == "2")
    }

    @Test("removed folders disappear from reads but survive as soft deletes")
    func softDelete() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(
            account: id,
            folders: [
                MailFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2),
                MailFolder(serverID: "9", parentID: "0", displayName: "Old", type: 1),
            ],
            syncKey: "1"
        )
        try store.applyFolderSnapshot(account: id, folders: [], removedServerIDs: ["9"], syncKey: "2")
        #expect(try store.folders(account: id).map(\.displayName) == ["Inbox"])
    }

    @Test("a folder that comes back is resurrected, not duplicated")
    func resurrection() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "9", parentID: "0", displayName: "Old", type: 1),
        ], syncKey: "1")
        try store.applyFolderSnapshot(account: id, folders: [], removedServerIDs: ["9"], syncKey: "2")
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "9", parentID: "0", displayName: "Old", type: 1),
        ], syncKey: "3")
        #expect(try store.folders(account: id).count == 1)
    }

    @Test("an invalid folder rolls the whole batch back")
    func rollbackOnInvalidFolder() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        #expect(throws: MailStoreError.invalidFolder(reason: "empty serverID")) {
            try store.applyFolderSnapshot(
                account: id,
                folders: [
                    MailFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2),
                    MailFolder(serverID: "", parentID: "0", displayName: "Broken", type: 1),
                ],
                syncKey: "1"
            )
        }
        #expect(try store.folders(account: id).isEmpty)
        #expect(try store.syncKey(account: id, collection: "folders") == nil)
    }

    @Test("writing folders for an unknown account fails loudly")
    func unknownAccount() throws {
        let store = try makeStore()
        let ghost = AccountID("ghost")
        #expect(throws: MailStoreError.accountNotFound(ghost)) {
            try store.applyFolderSnapshot(account: ghost, folders: [], syncKey: "1")
        }
    }
}
