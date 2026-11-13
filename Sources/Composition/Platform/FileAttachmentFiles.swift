import CryptoKit
import Foundation
import MailDomain

/// Attachment cache on disk: deterministic file names, atomic writes, and the 2 GB
/// oldest-first budget decided in `history/decisions/2026-11-09-attachment-cache-cap.md`.
public struct FileAttachmentFiles: AttachmentFiles {
    public static let defaultMaxBytes: Int64 = 2_000_000_000

    public let directory: URL
    public let maxBytes: Int64

    public init(directory: URL, maxBytes: Int64 = FileAttachmentFiles.defaultMaxBytes) {
        self.directory = directory
        self.maxBytes = maxBytes
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("uumail/attachments", isDirectory: true)
        return base
    }

    public func cachedURL(for reference: AttachmentRef) -> URL? {
        let url = fileURL(for: reference)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func store(_ data: Data, for reference: AttachmentRef) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: reference)
        try data.write(to: url, options: .atomic)
        _ = try? Self.prune(directory: directory, maxBytes: maxBytes)
        return url
    }

    /// Keeps the cache under budget by deleting the oldest files first.
    @discardableResult
    public static func prune(directory: URL, maxBytes: Int64) throws -> Int {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return 0 }
        let files = try manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var entries: [(url: URL, size: Int64, modified: Date)] = []
        var total: Int64 = 0
        for file in files {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values.fileSize ?? 0)
            total += size
            entries.append((file, size, values.contentModificationDate ?? .distantPast))
        }
        guard total > maxBytes else { return 0 }

        var removed = 0
        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            guard total > maxBytes else { break }
            try? manager.removeItem(at: entry.url)
            total -= entry.size
            removed += 1
        }
        return removed
    }

    /// `<digest>-<safe name>`: the digest keeps two attachments with the same name
    /// apart; the display name is sanitised because it comes from the server.
    public func fileURL(for reference: AttachmentRef) -> URL {
        let digest = SHA256.hash(data: Data(reference.fileReference.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(16)
        let safeName = reference.displayName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent("\(digest)-\(safeName)")
    }
}
