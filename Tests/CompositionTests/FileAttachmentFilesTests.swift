import Foundation
import MailDomain
import Testing

@testable import Composition

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("uumail-attachments-\(UUID().uuidString)", isDirectory: true)
}

@Suite("FileAttachmentFiles")
struct FileAttachmentFilesTests {
    @Test("a stored file is discoverable and keeps its bytes")
    func storesAndFinds() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = FileAttachmentFiles(directory: directory)
        let reference = AttachmentRef(fileReference: "ref-1", displayName: "报表.pdf")

        #expect(files.cachedURL(for: reference) == nil)

        let url = try files.store(Data("hello".utf8), for: reference)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == Data("hello".utf8))
        #expect(files.cachedURL(for: reference) == url)
        #expect(url.lastPathComponent.hasSuffix("-报表.pdf"), "the display name survives sanitising")
    }

    @Test("the cache evicts the oldest files until it is under budget")
    func prunesOldestFirst() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let names = ["old.bin", "middle.bin", "new.bin"]
        for (index, name) in names.enumerated() {
            let url = directory.appendingPathComponent(name)
            try Data(repeating: 0x61, count: 6).write(to: url)
            let date = Date(timeIntervalSince1970: 1_000 + Double(index) * 10)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }

        // 18 bytes over a 12-byte budget: only the oldest (6 bytes) has to go.
        let removed = try FileAttachmentFiles.prune(directory: directory, maxBytes: 12)
        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("old.bin").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("new.bin").path))
    }

    @Test("T-SCN-0020-03a: a small budget makes store evict the oldest file")
    func storePrunesWithSmallBudget() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 64 KB budget: two 40 KB stores cannot both stay, without writing a real 2 GB.
        let files = FileAttachmentFiles(directory: directory, maxBytes: 64 * 1024)
        let oldReference = AttachmentRef(fileReference: "old", displayName: "old.bin")
        let newReference = AttachmentRef(fileReference: "new", displayName: "new.bin")

        let oldURL = try files.store(Data(repeating: 0x61, count: 40 * 1024), for: oldReference)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: oldURL.path
        )
        let newURL = try files.store(Data(repeating: 0x62, count: 40 * 1024), for: newReference)

        #expect(!FileManager.default.fileExists(atPath: oldURL.path), "the oldest file is evicted")
        #expect(files.cachedURL(for: oldReference) == nil)
        #expect(FileManager.default.fileExists(atPath: newURL.path), "the new file survives")
        #expect(try Data(contentsOf: newURL) == Data(repeating: 0x62, count: 40 * 1024))
        #expect(files.cachedURL(for: newReference) == newURL)
    }

    @Test("a prune under budget removes nothing")
    func pruneNoopUnderBudget() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: directory.appendingPathComponent("small.bin"))

        #expect(try FileAttachmentFiles.prune(directory: directory, maxBytes: 100) == 0)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("small.bin").path))
    }
}
