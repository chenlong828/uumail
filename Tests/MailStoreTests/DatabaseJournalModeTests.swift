import Foundation
import GRDB
import MailDomain
import Testing

@testable import MailStore

/// The journal-mode decision from 2026-11-24 (CMP-STORE increment): file databases run in
/// WAL; in-memory test databases keep SQLite's default. WAL is a property of the file, so a
/// second connection can read it back.
@Suite("Database journal mode")
struct DatabaseJournalModeTests {
    private func temporaryDatabasePath() throws -> (directory: URL, path: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-wal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("mail.sqlite").path)
    }

    @Test("a file database opens in WAL mode")
    func fileDatabaseUsesWAL() throws {
        let (directory, path) = try temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try MailStore(path: path)
        _ = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )

        let probe = try DatabaseQueue(path: path)
        let mode = try probe.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }
        #expect(mode?.lowercased() == "wal")
    }

    @Test("reopening a WAL database keeps the journal mode and its rows")
    func reopenKeepsRows() throws {
        let (directory, path) = try temporaryDatabasePath()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try MailStore(path: path)
        let account = try first.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )

        let second = try MailStore(path: path)
        #expect(try second.accounts() == [account])
        #expect(try second.outbox.pendingOutbox(account: account).isEmpty)
    }
}
