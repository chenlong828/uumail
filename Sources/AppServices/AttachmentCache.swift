import Foundation

/// Keeps the attachment cache under a size budget by deleting the oldest files first.
/// The design default is 2 GB (see plan/open-questions.md Q2).
public enum AttachmentCache {
    public static let defaultMaxBytes: Int64 = 2_000_000_000

    @discardableResult
    public static func prune(directory: URL, maxBytes: Int64 = defaultMaxBytes) throws -> Int {
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
}
