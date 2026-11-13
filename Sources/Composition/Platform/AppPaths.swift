import Foundation

/// Where the app keeps its database and attachment cache. Only paths are computed;
/// nothing here reads or writes mail data.
public enum AppPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("uumail", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static var databasePath: String {
        supportDirectory.appendingPathComponent("mail.sqlite").path
    }

    public static var attachmentsDirectory: URL {
        supportDirectory.appendingPathComponent("attachments", isDirectory: true)
    }
}
